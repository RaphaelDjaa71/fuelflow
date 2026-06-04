#!/usr/bin/env bash
# Configure Workload Identity Federation so GitHub Actions can mint
# Google credentials WITHOUT a downloaded JSON key. The provider is
# locked to this repository via attribute-condition; any other GitHub
# repo trying to impersonate the SA is rejected at the trust boundary.
# Idempotent.
set -euo pipefail

: "${GCP_PROJECT_ID:?GCP_PROJECT_ID required (source .env)}"
REPO="RaphaelDjaa71/fuelflow"
SA="fuelflow-ci@${GCP_PROJECT_ID}.iam.gserviceaccount.com"
PROJNUM="$(gcloud projects describe "${GCP_PROJECT_ID}" --format='value(projectNumber)')"

# --- Pool ---
if gcloud iam workload-identity-pools describe github \
    --project="${GCP_PROJECT_ID}" --location=global >/dev/null 2>&1; then
  echo "WIF pool 'github' already exists."
else
  gcloud iam workload-identity-pools create github \
    --project="${GCP_PROJECT_ID}" \
    --location=global \
    --display-name="GitHub Actions"
fi

# --- OIDC provider, repo-scoped ---
if gcloud iam workload-identity-pools providers describe fuelflow \
    --project="${GCP_PROJECT_ID}" \
    --location=global \
    --workload-identity-pool=github >/dev/null 2>&1; then
  echo "OIDC provider 'fuelflow' already exists. Skipping create."
else
  gcloud iam workload-identity-pools providers create-oidc fuelflow \
    --project="${GCP_PROJECT_ID}" \
    --location=global \
    --workload-identity-pool=github \
    --display-name="fuelflow repo" \
    --issuer-uri="https://token.actions.githubusercontent.com" \
    --attribute-mapping="google.subject=assertion.sub,attribute.repository=assertion.repository" \
    --attribute-condition="assertion.repository=='${REPO}'"
fi

# --- Trust the principalSet: only this repo's tokens can impersonate the CI SA ---
gcloud iam service-accounts add-iam-policy-binding "${SA}" \
  --project="${GCP_PROJECT_ID}" \
  --role="roles/iam.workloadIdentityUser" \
  --member="principalSet://iam.googleapis.com/projects/${PROJNUM}/locations/global/workloadIdentityPools/github/attribute.repository/${REPO}" \
  >/dev/null

cat <<EOF

==== GitHub Actions secrets / variables to set ====

WIF_PROVIDER       = projects/${PROJNUM}/locations/global/workloadIdentityPools/github/providers/fuelflow
CI_SERVICE_ACCOUNT = ${SA}

Add them at:
  https://github.com/${REPO}/settings/secrets/actions
EOF
