#!/usr/bin/env bash
# Snowflake <-> GCS handshake step 2: grant the Snowflake-owned service
# account read access to the bronze bucket.
#
# Inputs:
#   SNOWFLAKE_STORAGE_SA  the STORAGE_GCP_SERVICE_ACCOUNT value returned
#                         by `DESC STORAGE INTEGRATION GCS_FUELFLOW`
#                         (looks like '...@gcpeuropewest3-...iam.gserviceaccount.com')
#
# Re-runnable safely.
set -euo pipefail

: "${GCS_BRONZE_BUCKET:?GCS_BRONZE_BUCKET required (source .env)}"
: "${SNOWFLAKE_STORAGE_SA:?SNOWFLAKE_STORAGE_SA required, see DESC STORAGE INTEGRATION output}"

BUCKET="gs://${GCS_BRONZE_BUCKET}"

gcloud storage buckets add-iam-policy-binding "${BUCKET}" \
  --member="serviceAccount:${SNOWFLAKE_STORAGE_SA}" \
  --role="roles/storage.objectViewer" \
  --condition=None

gcloud storage buckets add-iam-policy-binding "${BUCKET}" \
  --member="serviceAccount:${SNOWFLAKE_STORAGE_SA}" \
  --role="roles/storage.legacyBucketReader" \
  --condition=None

echo "Granted ${SNOWFLAKE_STORAGE_SA} read access on ${BUCKET}."
