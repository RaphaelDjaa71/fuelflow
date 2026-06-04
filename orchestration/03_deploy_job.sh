#!/usr/bin/env bash
# Deploy / update the Cloud Run Job that runs the ingestion worker.
# Idempotent (gcloud run jobs deploy upserts).
#
# Authentication:
#   - The job runs as fuelflow-ingest@... (created in L2).
#   - The SA already holds roles/storage.objectAdmin on the bronze bucket.
#   - The worker uses ADC via the Cloud Run metadata server. No key is
#     attached to the image, mounted in the job, or set in env vars.
set -euo pipefail

: "${GCP_PROJECT_ID:?GCP_PROJECT_ID required (source .env)}"
: "${GCS_BRONZE_BUCKET:?GCS_BRONZE_BUCKET required (source .env)}"
REGION="${GCP_REGION:-europe-west1}"
SOURCE_URL="${ROULEZ_ECO_INSTANT_URL:-https://donnees.roulez-eco.fr/opendata/instantane}"

IMAGE="${REGION}-docker.pkg.dev/${GCP_PROJECT_ID}/fuelflow/ingest:latest"
SA="fuelflow-ingest@${GCP_PROJECT_ID}.iam.gserviceaccount.com"

gcloud run jobs deploy fuelflow-ingest \
  --project="${GCP_PROJECT_ID}" \
  --region="${REGION}" \
  --image="${IMAGE}" \
  --service-account="${SA}" \
  --set-env-vars="GCP_PROJECT_ID=${GCP_PROJECT_ID},GCS_BRONZE_BUCKET=${GCS_BRONZE_BUCKET},GCS_BRONZE_PREFIX=bronze,ROULEZ_ECO_INSTANT_URL=${SOURCE_URL}" \
  --max-retries=2 \
  --task-timeout=300s \
  --memory=512Mi \
  --cpu=1
