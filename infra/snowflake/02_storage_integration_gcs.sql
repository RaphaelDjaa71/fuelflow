-- Snowflake <-> GCS handshake step 1: create the integration and
-- read back the GCP service account that Snowflake will impersonate
-- when reading the bucket. The actual IAM grant on the GCP side is done
-- in 02b_grant_snowflake_sa_on_bucket.sh AFTER this DESC.
--
-- IMPORTANT: the URL scheme is gcs:// (Snowflake convention), NOT gs://.

USE ROLE ACCOUNTADMIN;

CREATE STORAGE INTEGRATION IF NOT EXISTS GCS_FUELFLOW
  TYPE = EXTERNAL_STAGE
  STORAGE_PROVIDER = 'GCS'
  ENABLED = TRUE
  STORAGE_ALLOWED_LOCATIONS = ('gcs://fuelflow-498320-bronze/bronze/');

-- Run this and copy STORAGE_GCP_SERVICE_ACCOUNT before continuing:
DESC STORAGE INTEGRATION GCS_FUELFLOW;
