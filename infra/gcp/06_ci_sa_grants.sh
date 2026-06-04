#!/usr/bin/env bash
# Top up the IAM grants on the CI service account so the GitHub Actions
# workflow can run dbt against BigQuery end to end. Idempotent:
# add-iam-policy-binding is upsert.
#
# Recap of the CI SA permissions after this script:
#   - roles/storage.objectViewer  on gs://fuelflow-498320-bronze
#   - roles/bigquery.jobUser      on the project (granted in L2)
#   - roles/bigquery.dataEditor   on fuelflow_bronze_ext / silver / gold (L2)
set -euo pipefail

: "${GCP_PROJECT_ID:?GCP_PROJECT_ID required (source .env)}"
: "${GCS_BRONZE_BUCKET:?GCS_BRONZE_BUCKET required (source .env)}"

CI_SA="fuelflow-ci@${GCP_PROJECT_ID}.iam.gserviceaccount.com"

echo "Granting roles/storage.objectViewer on gs://${GCS_BRONZE_BUCKET} to ${CI_SA}"
gcloud storage buckets add-iam-policy-binding "gs://${GCS_BRONZE_BUCKET}" \
  --member="serviceAccount:${CI_SA}" \
  --role="roles/storage.objectViewer" \
  --condition=None
