#!/usr/bin/env bash
# Create the two service accounts used by the project, with least-privilege
# IAM bindings. No keys are downloaded in L2 (the developer uses ADC).
# The CI key for fuelflow-ci is generated in L7 and stored in GitHub
# Actions secrets — NEVER committed.
set -euo pipefail

: "${GCP_PROJECT_ID:?GCP_PROJECT_ID required (source .env)}"
: "${GCS_BRONZE_BUCKET:?GCS_BRONZE_BUCKET required (source .env)}"

create_sa () {
  local sa_name="$1"
  local display="$2"
  local email="${sa_name}@${GCP_PROJECT_ID}.iam.gserviceaccount.com"
  if gcloud iam service-accounts describe "${email}" --project="${GCP_PROJECT_ID}" >/dev/null 2>&1; then
    echo "SA ${email} already exists."
  else
    echo "Creating SA ${email}..."
    gcloud iam service-accounts create "${sa_name}" \
      --project="${GCP_PROJECT_ID}" \
      --display-name="${display}"
  fi
}

create_sa "fuelflow-ingest" "FuelFlow ingestion (Cloud Run runtime)"
create_sa "fuelflow-ci"     "FuelFlow CI (GitHub Actions, BigQuery)"

INGEST_SA="fuelflow-ingest@${GCP_PROJECT_ID}.iam.gserviceaccount.com"
CI_SA="fuelflow-ci@${GCP_PROJECT_ID}.iam.gserviceaccount.com"

# Ingest writes to the bronze bucket.
gcloud storage buckets add-iam-policy-binding "gs://${GCS_BRONZE_BUCKET}" \
  --member="serviceAccount:${INGEST_SA}" \
  --role="roles/storage.objectAdmin" \
  --condition=None

# CI runs dbt build on BigQuery.
gcloud projects add-iam-policy-binding "${GCP_PROJECT_ID}" \
  --member="serviceAccount:${CI_SA}" \
  --role="roles/bigquery.jobUser" \
  --condition=None \
  >/dev/null

# Per-dataset dataEditor for the CI SA so it can materialize models.
# Done via bq query instead of console clicks for reproducibility.
for DS in \
  "${BQ_DATASET_BRONZE_EXT:-fuelflow_bronze_ext}" \
  "${BQ_DATASET_SILVER:-fuelflow_silver}" \
  "${BQ_DATASET_GOLD:-fuelflow_gold}"; do
  bq add-iam-policy-binding \
    --member="serviceAccount:${CI_SA}" \
    --role="roles/bigquery.dataEditor" \
    "${GCP_PROJECT_ID}:${DS}" \
    >/dev/null
done

echo "Service accounts and IAM bindings applied."
