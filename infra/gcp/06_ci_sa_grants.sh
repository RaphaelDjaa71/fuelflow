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
  --condition=None \
  >/dev/null

# Project-level roles/bigquery.user gives the CI SA the ability to list
# datasets and read their metadata (jobUser alone does not). Without it,
# dbt-bigquery's pre-build check fails to detect that the silver/gold
# datasets already exist, attempts to create them, and bombs out on a
# missing bigquery.datasets.create permission. The dataEditor grants on
# the three datasets remain unchanged (they govern table-level writes).
echo "Granting roles/bigquery.user at project ${GCP_PROJECT_ID} to ${CI_SA}"
gcloud projects add-iam-policy-binding "${GCP_PROJECT_ID}" \
  --member="serviceAccount:${CI_SA}" \
  --role="roles/bigquery.user" \
  --condition=None \
  >/dev/null

# Per-dataset WRITER (= dataEditor) on the three FuelFlow datasets is
# what actually lets dbt-bigquery SELECT FROM and write the gold tables.
# We apply it via the Python BigQuery client because
# `bq add-iam-policy-binding` is a preview feature that requires
# project allowlisting and fails on standard projects with the
# 'This feature requires allowlisting' error.
echo "Granting WRITER on the three datasets to ${CI_SA}"
uv run --with google-cloud-bigquery python - <<'PY'
import os
from google.cloud import bigquery

project = os.environ["GCP_PROJECT_ID"]
ci_sa_entity = f"serviceAccount:fuelflow-ci@{project}.iam.gserviceaccount.com"

client = bigquery.Client(project=project)
for ds_id in ("fuelflow_bronze_ext", "fuelflow_silver", "fuelflow_gold"):
    ds = client.get_dataset(f"{project}.{ds_id}")
    entries = list(ds.access_entries)
    if any(e.entity_id == ci_sa_entity and e.role == "WRITER" for e in entries):
        print(f"  {ds_id}: CI SA already WRITER")
        continue
    entries.append(bigquery.AccessEntry("WRITER", "iamMember", ci_sa_entity))
    ds.access_entries = entries
    client.update_dataset(ds, ["access_entries"])
    print(f"  {ds_id}: added WRITER for CI SA")
PY

echo "CI SA grants up to date."
