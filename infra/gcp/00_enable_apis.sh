#!/usr/bin/env bash
# Enable the GCP APIs that L2 -> L7 depend on. Idempotent.
set -euo pipefail

if [[ -z "${GCP_PROJECT_ID:-}" ]]; then
  echo "GCP_PROJECT_ID is not set. Source .env first (set -a && . ./.env && set +a)." >&2
  exit 2
fi

gcloud config set project "${GCP_PROJECT_ID}" >/dev/null

gcloud services enable \
  bigquery.googleapis.com \
  storage.googleapis.com \
  run.googleapis.com \
  cloudscheduler.googleapis.com \
  secretmanager.googleapis.com \
  iam.googleapis.com \
  cloudbilling.googleapis.com \
  billingbudgets.googleapis.com

echo "APIs enabled on ${GCP_PROJECT_ID}."
