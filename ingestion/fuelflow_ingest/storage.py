"""Bronze writers — idempotent at the OBJECT level.

Each ingestion run computes a deterministic slot path
``dt=YYYY-MM-DD/hh=HH/...``. Re-running on the same slot must NOT
create duplicates: GCS uses ``if_generation_match=0`` so a pre-existing
object short-circuits to a skip; the local writer checks for file
existence.

Row-level deduplication on (station_id, carburant_id, maj_timestamp)
is handled later by dbt at the silver/gold layer (cf. ADR 0006 and
``docs/data-model/star-schema.md``).
"""

from __future__ import annotations

import io
from dataclasses import dataclass
from datetime import datetime
from pathlib import Path
from typing import TYPE_CHECKING, Protocol

import polars as pl

if TYPE_CHECKING:
    from google.cloud.storage import Client as GcsClient


@dataclass(frozen=True)
class Slot:
    """An hourly ingestion slot in UTC: ``dt=YYYY-MM-DD/hh=HH``."""

    date: str
    hour: str

    @classmethod
    def from_datetime(cls, ts: datetime) -> Slot:
        return cls(date=ts.strftime("%Y-%m-%d"), hour=ts.strftime("%H"))


@dataclass(frozen=True)
class WriteResult:
    path: str
    bytes_written: int
    skipped: bool


class BronzeWriter(Protocol):
    def write_raw_zip(self, zip_bytes: bytes, slot: Slot) -> WriteResult: ...
    def write_parquet(self, df: pl.DataFrame, slot: Slot) -> WriteResult: ...


def _raw_zip_key(prefix: str, slot: Slot) -> str:
    return f"{prefix}/raw_xml/dt={slot.date}/hh={slot.hour}/instantane.xml.zip"


def _parquet_key(prefix: str, slot: Slot) -> str:
    return f"{prefix}/parquet/dt={slot.date}/hh={slot.hour}/prix.parquet"


def _df_to_parquet_bytes(df: pl.DataFrame) -> bytes:
    buf = io.BytesIO()
    df.write_parquet(buf, compression="snappy")
    return buf.getvalue()


class GcsBronzeWriter:
    """Writes to GCS with object-level idempotence."""

    def __init__(self, bucket: str, prefix: str, client: GcsClient) -> None:
        self._bucket = bucket
        self._prefix = prefix.rstrip("/")
        self._client = client

    def _upload_idempotent(self, key: str, data: bytes, content_type: str) -> WriteResult:
        from google.api_core.exceptions import PreconditionFailed

        bucket = self._client.bucket(self._bucket)
        blob = bucket.blob(key)
        try:
            blob.upload_from_string(data, content_type=content_type, if_generation_match=0)
            return WriteResult(
                path=f"gs://{self._bucket}/{key}",
                bytes_written=len(data),
                skipped=False,
            )
        except PreconditionFailed:
            return WriteResult(
                path=f"gs://{self._bucket}/{key}",
                bytes_written=0,
                skipped=True,
            )

    def write_raw_zip(self, zip_bytes: bytes, slot: Slot) -> WriteResult:
        return self._upload_idempotent(
            _raw_zip_key(self._prefix, slot),
            zip_bytes,
            content_type="application/zip",
        )

    def write_parquet(self, df: pl.DataFrame, slot: Slot) -> WriteResult:
        return self._upload_idempotent(
            _parquet_key(self._prefix, slot),
            _df_to_parquet_bytes(df),
            content_type="application/octet-stream",
        )


class LocalBronzeWriter:
    """Writes to a local directory with the same idempotent semantics."""

    def __init__(self, root: Path, prefix: str = "") -> None:
        self._root = Path(root)
        self._prefix = prefix.rstrip("/")

    def _local_path(self, key: str) -> Path:
        return self._root / key

    def _write_idempotent(self, key: str, data: bytes) -> WriteResult:
        path = self._local_path(key)
        if path.exists():
            return WriteResult(path=str(path), bytes_written=0, skipped=True)
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(data)
        return WriteResult(path=str(path), bytes_written=len(data), skipped=False)

    def write_raw_zip(self, zip_bytes: bytes, slot: Slot) -> WriteResult:
        return self._write_idempotent(_raw_zip_key(self._prefix, slot), zip_bytes)

    def write_parquet(self, df: pl.DataFrame, slot: Slot) -> WriteResult:
        return self._write_idempotent(_parquet_key(self._prefix, slot), _df_to_parquet_bytes(df))
