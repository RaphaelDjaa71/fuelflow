# infra/

**Lot responsable :** L2 — provisionnement des ressources cloud + landing
bronze→silver (external tables).

**Statut :** ✅ Côté GCP (bucket, datasets, service accounts, budget,
external table BigQuery) ; ⏳ Snowflake côté SQL **à exécuter par l'utilisateur**
via Snowsight UI (MFA exigé par le compte, voir § Handshake).

## Vue d'ensemble des ressources

| Couche | Stockage / objet | Localisation | Propriétaire |
|---|---|---|---|
| **Bronze (rejouabilité)** | `gs://fuelflow-498320-bronze/bronze/raw_xml/dt=…/hh=…/instantane.xml.zip` | GCS EU multi-region | Cloud Run Job (L6) via SA `fuelflow-ingest` |
| **Bronze (typé)** | `gs://fuelflow-498320-bronze/bronze/parquet/dt=…/hh=…/prix.parquet` | idem | idem |
| **Interface raw BigQuery** | `fuelflow-498320.fuelflow_bronze_ext.ext_prix_bronze` | BigQuery EU | External table hive-partitioned (`dt`, `hh`) |
| **Interface raw Snowflake** | `FUELFLOW.BRONZE_EXT.ext_prix_bronze` | Snowflake europe-west3 GCP | External table sur stage GCS |
| Silver dbt | `fuelflow_silver` (BQ) / `FUELFLOW.SILVER` (SF) | EU | dbt L4 |
| Gold dbt | `fuelflow_gold` (BQ) / `FUELFLOW.GOLD` (SF) | EU | dbt L5 + contracts |

**Distinction nette à retenir** : les external tables L2 sont une **interface**
au-dessus du bronze GCS, pas une couche silver. Aucun nettoyage, aucune dédup,
aucun typage strict ici. Tout ça arrive en dbt (L3 init / L4 silver / L5 gold).

## Garde-fous coût & sécurité

- **GCS** : uniform access, public access prevention `enforced`, lifecycle
  NEARLINE@30 j / COLDLINE@90 j. **Pas de DELETE** (ADR 0005 — rejouabilité).
- **Soft-delete** GCS par défaut 7 j (annulation accidentelle de suppression).
- **BigQuery** : free tier mensuel (1 To requêtes, 10 Go stockage) suffit
  largement à FuelFlow.
- **Snowflake** : warehouse `FUELFLOW_WH` `XSMALL` + `AUTO_SUSPEND=60` +
  `INITIALLY_SUSPENDED=TRUE` (ADR 0002).
- **Budget GCP** : `fuelflow-guardrail`, cap 5 EUR/mois, alertes 50/90/100 %.
- **Aucune clé SA téléchargée** en L2. Auth locale = ADC du user. La clé du
  SA `fuelflow-ci` sera générée en L7 et stockée en GitHub Actions Secrets,
  jamais committée.

## Ordre d'exécution (idempotent, sûr à rejouer)

### 1) GCP — automatisable

```bash
cd ~/fuelflow
set -a && . ./.env && set +a

bash infra/gcp/00_enable_apis.sh
bash infra/gcp/01_create_bucket.sh
bash infra/gcp/02_create_bq_datasets.sh
bash infra/gcp/03_service_accounts.sh
bash infra/gcp/04_budget_alert.sh
bash infra/gcp/05_bq_external_table.sh  # crée fuelflow_bronze_ext.ext_prix_bronze
```

### 2) Snowflake — handshake en 3 temps (UI)

Snowsight n'autorise pas l'auth password seul si MFA est activé sur le compte ;
ce projet exécute donc le SQL Snowflake dans **Snowsight UI** (le SQL reste
versionné, l'exécution est manuelle). Worksheets : <https://app.snowflake.com>.

| # | Action | Où |
|---|---|---|
| 2.1 | Coller et exécuter `infra/snowflake/01_db_warehouse.sql` | Snowsight |
| 2.2 | Coller et exécuter `infra/snowflake/02_storage_integration_gcs.sql` | Snowsight |
| 2.3 | Dans la sortie de `DESC STORAGE INTEGRATION GCS_FUELFLOW`, copier la valeur de **`STORAGE_GCP_SERVICE_ACCOUNT`** (un email `…@gcpeuropewest3-…iam.gserviceaccount.com`) | Snowsight |
| 2.4 | Exécuter le grant GCP côté terminal : `SNOWFLAKE_STORAGE_SA=<email-copié> bash infra/snowflake/02b_grant_snowflake_sa_on_bucket.sh` | terminal local |
| 2.5 | Coller et exécuter `infra/snowflake/03_stage_external_table.sql` | Snowsight |
| 2.6 | Confirmer `SELECT COUNT(*) FROM FUELFLOW.BRONZE_EXT.ext_prix_bronze;` ≈ même ordre que la même requête BigQuery | Snowsight |

> Note pour L7 : pour l'automatisation CI sur Snowflake, configurer une
> **key-pair authentication** sur un user de service (pas MFA). Hors scope L2.

## Schéma de l'external table BigQuery

13 colonnes Parquet + 2 colonnes hive (`dt` DATE, `hh` INTEGER) — inférées
automatiquement. Tous les types correspondent au schéma écrit par L1
(`STRING`, `FLOAT`, `TIMESTAMP`).

## Câblage GCS du worker L1

```bash
make ingest-gcs   # download → parse → upload réel sur gs://<bucket>/bronze/...
```

`make ingest-gcs` lit `.env` localement, s'authentifie via ADC (`gcloud auth
application-default login`), et écrit avec `if_generation_match=0` — un
re-run du même créneau horaire renvoie `skipped=true` sans dupliquer
(idempotence object-level, voir `ingestion/README.md`).
