-- Snowflake <-> GCS handshake step 3: define the stage and the external
-- table on top of the bronze Parquet, AFTER the GCP-side grant from
-- 02b is in place. Run this in a fresh worksheet/session.

USE ROLE SYSADMIN;
USE DATABASE FUELFLOW;
USE SCHEMA BRONZE_EXT;

CREATE OR REPLACE FILE FORMAT bronze_parquet_format
  TYPE = PARQUET;

CREATE STAGE IF NOT EXISTS bronze_stage
  STORAGE_INTEGRATION = GCS_FUELFLOW
  URL = 'gcs://fuelflow-498320-bronze/bronze/parquet/'
  FILE_FORMAT = bronze_parquet_format;

-- One row per <prix> record from the L1 worker's Parquet output.
-- The columns are derived from VALUE (Parquet -> VARIANT) on read; this
-- keeps the external table tolerant to source schema drift (a new column
-- in Parquet does NOT break the table — it just gets ignored until we
-- add a derived column for it). dbt L4 is where types are enforced.
--
-- Timestamp pitfall (L3 closure): polars writes maj_timestamp as Parquet
-- INT64 with logical type TIMESTAMP(MICROS). Snowflake exposes this as
-- a 16-digit integer in the VARIANT (e.g. 1780475640000000). A naive
-- ::TIMESTAMP_NTZ cast interprets that integer as SECONDS since epoch
-- and produces year-54M garbage that silently passes not_null/unique
-- tests. We must call TO_TIMESTAMP_NTZ(..., 6) so Snowflake reads the
-- value with scale=6 (microseconds). ingestion_ts is written by polars
-- as a tz-aware Datetime[us,UTC] which Snowflake surfaces as an
-- ISO-8601 string, so the original ::TIMESTAMP_TZ cast works there.
CREATE OR REPLACE EXTERNAL TABLE ext_prix_bronze (
  station_id    STRING  AS (VALUE:station_id::STRING),
  cp            STRING  AS (VALUE:cp::STRING),
  ville         STRING  AS (VALUE:ville::STRING),
  adresse       STRING  AS (VALUE:adresse::STRING),
  pop           STRING  AS (VALUE:pop::STRING),
  latitude      FLOAT   AS (VALUE:latitude::FLOAT),
  longitude     FLOAT   AS (VALUE:longitude::FLOAT),
  carburant_id  STRING  AS (VALUE:carburant_id::STRING),
  carburant_nom STRING  AS (VALUE:carburant_nom::STRING),
  maj_timestamp TIMESTAMP_NTZ AS (TO_TIMESTAMP_NTZ(VALUE:maj_timestamp::NUMBER, 6)),
  prix_euro     FLOAT   AS (VALUE:prix_euro::FLOAT),
  ingestion_ts  TIMESTAMP_TZ AS (VALUE:ingestion_ts::TIMESTAMP_TZ),
  source_url    STRING  AS (VALUE:source_url::STRING)
)
LOCATION = @bronze_stage
FILE_FORMAT = bronze_parquet_format
PATTERN = '.*prix[.]parquet'
AUTO_REFRESH = FALSE;

-- Audit queries to run after creation:
SELECT COUNT(*) AS row_count FROM ext_prix_bronze;

SELECT MIN(prix_euro)  AS prix_min,
       MAX(prix_euro)  AS prix_max,
       MIN(latitude)   AS lat_min,
       MAX(latitude)   AS lat_max,
       COUNT(DISTINCT station_id) AS distinct_stations
FROM ext_prix_bronze;
