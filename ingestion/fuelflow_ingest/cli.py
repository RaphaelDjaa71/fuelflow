"""End-to-end ingestion CLI: download -> parse -> bronze write.

Invoked locally as ``python -m fuelflow_ingest.cli --local-only`` (which
writes to ``data/bronze/...`` and never touches GCS), or by the Cloud
Run Job entrypoint in L6 (no flag — writes to GCS).
"""

from __future__ import annotations

import argparse
import sys
from datetime import UTC, datetime
from time import perf_counter

from fuelflow_ingest.config import IngestConfig
from fuelflow_ingest.download import download_feed
from fuelflow_ingest.logging import configure_logging, get_logger
from fuelflow_ingest.parse import parse_feed
from fuelflow_ingest.storage import (
    BronzeWriter,
    GcsBronzeWriter,
    LocalBronzeWriter,
    Slot,
)


def _build_writer(config: IngestConfig, local_only: bool) -> BronzeWriter:
    if local_only:
        return LocalBronzeWriter(root=config.local_bronze_root, prefix=config.gcs_prefix)
    if not config.gcs_bucket:
        raise RuntimeError("GCS_BRONZE_BUCKET is not set; either set it or run with --local-only")
    from google.cloud.storage import Client

    return GcsBronzeWriter(
        bucket=config.gcs_bucket,
        prefix=config.gcs_prefix,
        client=Client(),
    )


def run(local_only: bool = False, now: datetime | None = None) -> int:
    configure_logging()
    log = get_logger().bind(component="cli", local_only=local_only)

    config = IngestConfig.from_env()
    ingestion_ts = (now or datetime.now(UTC)).replace(minute=0, second=0, microsecond=0)
    slot = Slot.from_datetime(ingestion_ts)
    log = log.bind(slot_date=slot.date, slot_hour=slot.hour, source_url=config.source_url)

    t0 = perf_counter()

    log.info("download.start")
    payload = download_feed(
        config.source_url,
        timeout=config.http_timeout_seconds,
        max_attempts=config.http_max_attempts,
    )
    log.info(
        "download.done",
        zip_bytes=len(payload.zip_bytes),
        xml_bytes=len(payload.xml_bytes),
        xml_entry=payload.xml_entry_name,
    )

    log.info("parse.start")
    df, stats = parse_feed(
        xml_bytes=payload.xml_bytes,
        ingestion_ts=ingestion_ts,
        source_url=config.source_url,
    )
    log.info(
        "parse.done",
        station_count=stats.station_count,
        price_row_count=stats.price_row_count,
        parse_errors=stats.parse_errors,
    )

    writer = _build_writer(config, local_only=local_only)

    raw = writer.write_raw_zip(payload.zip_bytes, slot)
    log.info(
        "write.raw_zip",
        path=raw.path,
        bytes_written=raw.bytes_written,
        skipped=raw.skipped,
    )

    pq = writer.write_parquet(df, slot)
    log.info(
        "write.parquet",
        path=pq.path,
        bytes_written=pq.bytes_written,
        skipped=pq.skipped,
    )

    log.info(
        "run.done",
        duration_seconds=round(perf_counter() - t0, 3),
        station_count=stats.station_count,
        price_row_count=stats.price_row_count,
        parse_errors=stats.parse_errors,
    )
    return 0


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(prog="fuelflow_ingest")
    parser.add_argument(
        "--local-only",
        action="store_true",
        help="write bronze artefacts to LOCAL_BRONZE_ROOT instead of GCS",
    )
    args = parser.parse_args(argv)
    return run(local_only=args.local_only)


if __name__ == "__main__":
    sys.exit(main())
