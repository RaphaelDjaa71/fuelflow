#!/usr/bin/env bash
# Create a BigQuery external table over the Parquet bronze layer, with
# Hive partitioning derived from the dt=YYYY-MM-DD/hh=HH path layout
# that the L1 worker writes. dbt L4 will SELECT FROM this table; nothing
# is materialized inside BigQuery at this layer.
set -euo pipefail

: "${GCP_PROJECT_ID:?GCP_PROJECT_ID required (source .env)}"
: "${GCS_BRONZE_BUCKET:?GCS_BRONZE_BUCKET required (source .env)}"

DATASET="${BQ_DATASET_BRONZE_EXT:-fuelflow_bronze_ext}"
TABLE="ext_prix_bronze"
PARQUET_PREFIX="gs://${GCS_BRONZE_BUCKET}/bronze/parquet/"

EXTDEF_FILE="$(mktemp)"
trap 'rm -f "${EXTDEF_FILE}"' EXIT

cat > "${EXTDEF_FILE}" <<JSON
{
  "sourceFormat": "PARQUET",
  "sourceUris": ["${PARQUET_PREFIX}*"],
  "hivePartitioningOptions": {
    "mode": "AUTO",
    "sourceUriPrefix": "${PARQUET_PREFIX}"
  },
  "parquetOptions": {
    "enableListInference": true
  }
}
JSON

FQN="${GCP_PROJECT_ID}:${DATASET}.${TABLE}"

if bq show "${FQN}" >/dev/null 2>&1; then
  echo "External table ${FQN} already exists. Recreating to refresh the partition discovery."
  bq rm -f -t "${FQN}"
fi

echo "Creating external table ${FQN}..."
bq mk \
  --external_table_definition="${EXTDEF_FILE}" \
  "${FQN}"

echo
echo "Schema:"
bq show --schema --format=prettyjson "${FQN}"
