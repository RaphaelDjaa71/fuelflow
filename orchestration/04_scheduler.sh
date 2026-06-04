#!/usr/bin/env bash
# Create the Cloud Scheduler job that triggers the ingestion Cloud Run
# Job every hour on the Europe/Paris calendar. Idempotent.
#
# Auth model:
#   - Scheduler is given the SA `fuelflow-ingest@...` to mint an OAuth
#     token with audience = the Run Job endpoint.
#   - The SA must hold roles/run.invoker on the job (granted below).
#   - On a multi-team project we would split into a separate
#     scheduler-only SA. For a solo portfolio project, reusing the
#     runtime SA is acceptable and documented.
set -euo pipefail

: "${GCP_PROJECT_ID:?GCP_PROJECT_ID required (source .env)}"
REGION="${GCP_REGION:-europe-west1}"
SA="fuelflow-ingest@${GCP_PROJECT_ID}.iam.gserviceaccount.com"

gcloud run jobs add-iam-policy-binding fuelflow-ingest \
  --project="${GCP_PROJECT_ID}" \
  --region="${REGION}" \
  --member="serviceAccount:${SA}" \
  --role="roles/run.invoker"

URI="https://${REGION}-run.googleapis.com/v2/projects/${GCP_PROJECT_ID}/locations/${REGION}/jobs/fuelflow-ingest:run"

if gcloud scheduler jobs describe fuelflow-ingest-hourly \
    --location="${REGION}" --project="${GCP_PROJECT_ID}" >/dev/null 2>&1; then
  echo "Scheduler job fuelflow-ingest-hourly already exists. Updating."
  gcloud scheduler jobs update http fuelflow-ingest-hourly \
    --project="${GCP_PROJECT_ID}" \
    --location="${REGION}" \
    --schedule="0 * * * *" \
    --time-zone="Europe/Paris" \
    --uri="${URI}" \
    --http-method=POST \
    --oauth-service-account-email="${SA}"
else
  gcloud scheduler jobs create http fuelflow-ingest-hourly \
    --project="${GCP_PROJECT_ID}" \
    --location="${REGION}" \
    --schedule="0 * * * *" \
    --time-zone="Europe/Paris" \
    --uri="${URI}" \
    --http-method=POST \
    --oauth-service-account-email="${SA}" \
    --description="Hourly trigger for the fuelflow-ingest Cloud Run Job"
fi

echo "Scheduler fuelflow-ingest-hourly configured: cron='0 * * * *' Europe/Paris -> ${URI}"
