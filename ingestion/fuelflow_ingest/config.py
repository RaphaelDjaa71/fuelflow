"""Runtime configuration for the ingestion worker.

All values are read from environment variables with safe local-only
defaults. The worker is invoked either by Cloud Run Job (L6) with env
vars set by the deployment, or locally via ``python -m
fuelflow_ingest.cli --local-only`` which uses the defaults below.
"""

from __future__ import annotations

import os
from dataclasses import dataclass
from pathlib import Path

DEFAULT_SOURCE_URL = "https://donnees.roulez-eco.fr/opendata/instantane"
# LOCAL_BRONZE_ROOT is the local "bucket"; the prefix sits under it so the
# final paths mirror the GCS layout `gs://<bucket>/<prefix>/...`.
DEFAULT_LOCAL_BRONZE_ROOT = "data"
DEFAULT_GCS_PREFIX = "bronze"


@dataclass(frozen=True)
class IngestConfig:
    """Frozen config snapshot for a single ingestion run."""

    source_url: str
    gcs_bucket: str | None
    gcs_prefix: str
    local_bronze_root: Path
    http_timeout_seconds: float
    http_max_attempts: int

    @classmethod
    def from_env(cls) -> IngestConfig:
        return cls(
            source_url=os.environ.get("ROULEZ_ECO_INSTANT_URL", DEFAULT_SOURCE_URL),
            gcs_bucket=os.environ.get("GCS_BRONZE_BUCKET") or None,
            gcs_prefix=os.environ.get("GCS_BRONZE_PREFIX", DEFAULT_GCS_PREFIX),
            local_bronze_root=Path(os.environ.get("LOCAL_BRONZE_ROOT", DEFAULT_LOCAL_BRONZE_ROOT)),
            http_timeout_seconds=float(os.environ.get("HTTP_TIMEOUT_SECONDS", "60")),
            http_max_attempts=int(os.environ.get("HTTP_MAX_ATTEMPTS", "5")),
        )
