#!/usr/bin/env bash
# Create the BigQuery datasets in EU multi-region so external tables can
# read the EU bucket (BQ requires same location). Idempotent.
set -euo pipefail

: "${GCP_PROJECT_ID:?GCP_PROJECT_ID required (source .env)}"

DATASETS=(
  "${BQ_DATASET_BRONZE_EXT:-fuelflow_bronze_ext}"
  "${BQ_DATASET_SILVER:-fuelflow_silver}"
  "${BQ_DATASET_GOLD:-fuelflow_gold}"
)

for DS in "${DATASETS[@]}"; do
  if bq --location=EU show "${GCP_PROJECT_ID}:${DS}" >/dev/null 2>&1; then
    echo "Dataset ${GCP_PROJECT_ID}:${DS} already exists."
  else
    echo "Creating dataset ${GCP_PROJECT_ID}:${DS}..."
    bq --location=EU mk \
      --dataset \
      --description="FuelFlow ${DS}" \
      "${GCP_PROJECT_ID}:${DS}"
  fi
done
