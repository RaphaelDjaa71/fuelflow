"""FuelFlow ingestion package — XML feed to GCS bronze.

Downloads the roulez-eco snapshot, parses it into a typed Polars
DataFrame, and writes both the raw ZIP and the typed Parquet to a
deterministic, idempotent GCS path (or a local directory when running
with ``--local-only``).

Public surface:
- ``fuelflow_ingest.config.IngestConfig``
- ``fuelflow_ingest.download.download_feed``
- ``fuelflow_ingest.parse.parse_feed``
- ``fuelflow_ingest.storage.GcsBronzeWriter``, ``LocalBronzeWriter``
- ``fuelflow_ingest.cli.run``
"""

__version__ = "0.1.0"
