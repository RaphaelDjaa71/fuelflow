"""Tests for the bronze writers.

The GCS writer is exercised with an injected mock client; no real GCP
calls happen. The local writer uses ``tmp_path``.
"""

from __future__ import annotations

from datetime import UTC, datetime
from unittest.mock import MagicMock

import polars as pl
import pytest
from fuelflow_ingest.storage import (
    GcsBronzeWriter,
    LocalBronzeWriter,
    Slot,
)
from google.api_core.exceptions import PreconditionFailed

ZIP_BYTES = b"PK\x03\x04 fake zip bytes for tests"


@pytest.fixture()
def df() -> pl.DataFrame:
    return pl.DataFrame(
        {
            "station_id": ["1000001"],
            "carburant_id": ["1"],
            "prix_euro": [1.799],
        }
    )


@pytest.fixture()
def slot() -> Slot:
    return Slot.from_datetime(datetime(2026, 6, 3, 10, 0, 0, tzinfo=UTC))


def test_slot_from_datetime_formats_date_and_hour() -> None:
    s = Slot.from_datetime(datetime(2026, 6, 3, 7, 0, 0, tzinfo=UTC))
    assert s.date == "2026-06-03"
    assert s.hour == "07"


def test_local_writer_writes_then_skips_on_replay(tmp_path, df: pl.DataFrame, slot: Slot) -> None:
    writer = LocalBronzeWriter(root=tmp_path, prefix="bronze")

    raw1 = writer.write_raw_zip(ZIP_BYTES, slot)
    pq1 = writer.write_parquet(df, slot)
    assert raw1.skipped is False
    assert pq1.skipped is False
    assert raw1.bytes_written == len(ZIP_BYTES)
    assert pq1.bytes_written > 0

    raw2 = writer.write_raw_zip(ZIP_BYTES, slot)
    pq2 = writer.write_parquet(df, slot)
    assert raw2.skipped is True
    assert pq2.skipped is True
    assert raw2.bytes_written == 0
    assert pq2.bytes_written == 0

    assert raw1.path.endswith("bronze/raw_xml/dt=2026-06-03/hh=10/instantane.xml.zip")
    assert pq1.path.endswith("bronze/parquet/dt=2026-06-03/hh=10/prix.parquet")


def test_gcs_writer_calls_upload_with_if_generation_match_zero(
    df: pl.DataFrame, slot: Slot
) -> None:
    blob = MagicMock()
    bucket = MagicMock()
    bucket.blob.return_value = blob
    client = MagicMock()
    client.bucket.return_value = bucket

    writer = GcsBronzeWriter(bucket="my-bucket", prefix="bronze", client=client)
    result = writer.write_raw_zip(ZIP_BYTES, slot)

    client.bucket.assert_called_once_with("my-bucket")
    bucket.blob.assert_called_once_with("bronze/raw_xml/dt=2026-06-03/hh=10/instantane.xml.zip")
    blob.upload_from_string.assert_called_once()
    kwargs = blob.upload_from_string.call_args.kwargs
    assert kwargs["if_generation_match"] == 0
    assert kwargs["content_type"] == "application/zip"
    assert result.skipped is False
    assert result.path == "gs://my-bucket/bronze/raw_xml/dt=2026-06-03/hh=10/instantane.xml.zip"


def test_gcs_writer_skips_on_precondition_failed(df: pl.DataFrame, slot: Slot) -> None:
    blob = MagicMock()
    blob.upload_from_string.side_effect = PreconditionFailed("already exists")
    bucket = MagicMock()
    bucket.blob.return_value = blob
    client = MagicMock()
    client.bucket.return_value = bucket

    writer = GcsBronzeWriter(bucket="my-bucket", prefix="bronze", client=client)
    result = writer.write_parquet(df, slot)

    assert result.skipped is True
    assert result.bytes_written == 0
    assert result.path == "gs://my-bucket/bronze/parquet/dt=2026-06-03/hh=10/prix.parquet"
