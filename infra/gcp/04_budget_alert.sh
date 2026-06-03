#!/usr/bin/env bash
# Budget guardrail: 5 EUR/month cap with alerts at 50% / 90% / 100%.
# Cost on this project is expected to be near-zero (BigQuery free tier
# fully covers FuelFlow volumes); the alert is a fail-safe in case
# something runs away.
#
# Requires that the user has the `roles/billing.admin` or equivalent
# on the billing account. If not, the API call fails — fall back to
# console (Billing > Budgets & alerts) and note that in infra/README.md.
set -euo pipefail

: "${GCP_PROJECT_ID:?GCP_PROJECT_ID required (source .env)}"

BILLING_RAW=$(gcloud billing projects describe "${GCP_PROJECT_ID}" --format="value(billingAccountName)" 2>/dev/null || true)
if [[ -z "${BILLING_RAW}" ]]; then
  echo "Billing account not linked. Link one in console, then re-run."
  exit 1
fi
BILLING_ID="${BILLING_RAW##*/}"

if gcloud billing budgets list --billing-account="${BILLING_ID}" --format="value(displayName)" 2>/dev/null | grep -q "^fuelflow-guardrail$"; then
  echo "Budget 'fuelflow-guardrail' already exists. Skipping."
  exit 0
fi

if ! gcloud billing budgets create \
  --billing-account="${BILLING_ID}" \
  --display-name="fuelflow-guardrail" \
  --budget-amount=5EUR \
  --threshold-rule=percent=0.5 \
  --threshold-rule=percent=0.9 \
  --threshold-rule=percent=1.0 \
  --filter-projects="projects/${GCP_PROJECT_ID}"; then
  echo "Budget creation via API failed (likely missing billing.admin)."
  echo "Create in console: Billing > Budgets & alerts > Create."
  echo "Document the resort in infra/README.md."
  exit 0
fi

echo "Budget 'fuelflow-guardrail' created at 5 EUR/month (50/90/100% alerts)."
