#!/usr/bin/env bash
# Build and push the ingestion image to Artifact Registry using Cloud
# Build. Runs from the repo root so the build context honours the
# .gcloudignore at the top level. Idempotent: each call retags `:latest`
# and creates a `:SHA-<git-sha>` immutable tag for traceability.
set -euo pipefail

: "${GCP_PROJECT_ID:?GCP_PROJECT_ID required (source .env)}"
REGION="${GCP_REGION:-europe-west1}"

GIT_SHA="$(git -C "$(dirname "$0")/.." rev-parse --short HEAD)"
IMAGE_LATEST="${REGION}-docker.pkg.dev/${GCP_PROJECT_ID}/fuelflow/ingest:latest"
IMAGE_SHA="${REGION}-docker.pkg.dev/${GCP_PROJECT_ID}/fuelflow/ingest:sha-${GIT_SHA}"

CONFIG_FILE="$(mktemp -t fuelflow_cloudbuild.XXXXXX.yaml)"
trap 'rm -f "${CONFIG_FILE}"' EXIT

cat > "${CONFIG_FILE}" <<EOF
steps:
  - name: gcr.io/cloud-builders/docker
    args: ['build', '-f', 'orchestration/Dockerfile',
           '-t', '${IMAGE_SHA}', '-t', '${IMAGE_LATEST}', '.']
images:
  - '${IMAGE_SHA}'
  - '${IMAGE_LATEST}'
options:
  logging: CLOUD_LOGGING_ONLY
EOF

echo "Building ${IMAGE_SHA}"
gcloud builds submit \
  --project="${GCP_PROJECT_ID}" \
  --region="${REGION}" \
  --config="${CONFIG_FILE}"

echo "Pushed ${IMAGE_SHA} and ${IMAGE_LATEST}"
