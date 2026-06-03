#!/usr/bin/env bash
# Create the GCS bronze bucket (EU multi-region) with safety controls:
#   - uniform bucket-level access (no per-object ACLs)
#   - public access prevention enforced (cannot be made public by mistake)
#   - lifecycle: NEARLINE @30d, COLDLINE @90d. NEVER delete (ADR 0005:
#     the raw XML is kept for replay).
# Idempotent.
set -euo pipefail

: "${GCP_PROJECT_ID:?GCP_PROJECT_ID required (source .env)}"
: "${GCS_BRONZE_BUCKET:?GCS_BRONZE_BUCKET required (source .env)}"

BUCKET="gs://${GCS_BRONZE_BUCKET}"

if ! gcloud storage buckets describe "${BUCKET}" >/dev/null 2>&1; then
  echo "Creating ${BUCKET} in EU multi-region..."
  gcloud storage buckets create "${BUCKET}" \
    --project="${GCP_PROJECT_ID}" \
    --location=EU \
    --uniform-bucket-level-access \
    --public-access-prevention
else
  echo "Bucket ${BUCKET} already exists. Re-applying controls."
  gcloud storage buckets update "${BUCKET}" \
    --uniform-bucket-level-access \
    --public-access-prevention
fi

LIFECYCLE_FILE="$(mktemp)"
trap 'rm -f "${LIFECYCLE_FILE}"' EXIT
cat > "${LIFECYCLE_FILE}" <<'JSON'
{
  "rule": [
    { "action": {"type": "SetStorageClass", "storageClass": "NEARLINE"},
      "condition": {"age": 30, "matchesStorageClass": ["STANDARD"]} },
    { "action": {"type": "SetStorageClass", "storageClass": "COLDLINE"},
      "condition": {"age": 90, "matchesStorageClass": ["NEARLINE", "STANDARD"]} }
  ]
}
JSON

gcloud storage buckets update "${BUCKET}" --lifecycle-file="${LIFECYCLE_FILE}"
echo "Lifecycle applied (NEARLINE@30d / COLDLINE@90d, no DELETE)."
