#!/usr/bin/env bash
# Enable Artifact Registry + Cloud Build APIs and create the Docker
# repository the ingestion image will live in. Idempotent.
set -euo pipefail

: "${GCP_PROJECT_ID:?GCP_PROJECT_ID required (source .env)}"
REGION="${GCP_REGION:-europe-west1}"

gcloud services enable \
  artifactregistry.googleapis.com \
  cloudbuild.googleapis.com

if gcloud artifacts repositories describe fuelflow \
    --location="${REGION}" >/dev/null 2>&1; then
  echo "Artifact Registry repo 'fuelflow' already exists in ${REGION}."
else
  gcloud artifacts repositories create fuelflow \
    --repository-format=docker \
    --location="${REGION}" \
    --description="FuelFlow container images (ingestion worker, ...)"
  echo "Created Artifact Registry repo 'fuelflow' in ${REGION}."
fi
