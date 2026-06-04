# FuelFlow — pipeline analytique sur les prix des carburants en France

[![ci](https://github.com/RaphaelDjaa71/fuelflow/actions/workflows/ci.yml/badge.svg)](https://github.com/RaphaelDjaa71/fuelflow/actions/workflows/ci.yml)
[![dbt-docs](https://github.com/RaphaelDjaa71/fuelflow/actions/workflows/dbt-docs.yml/badge.svg)](https://raphaeldjaa71.github.io/fuelflow/)

> Projet portfolio Analytics Engineer — chaîne complète de l'**open data
> XML brut** jusqu'au **dashboard public**, avec contrats de schéma, CI
> qui bloque le merge, et pipeline autonome qui tourne tout seul.
> Coût d'exploitation ≈ 0 €.

## 1. Le problème métier

Un comparateur de carburants, un distributeur multi-marques, ou un
opérateur de flotte reçoit le flux public de l'État
([`donnees.roulez-eco.fr`](https://donnees.roulez-eco.fr/opendata/instantane))
mis à jour environ **toutes les 10 minutes**, couvrant **~11 000
stations-service** du territoire français et **6 carburants** (Gazole,
SP95, SP98, E10, E85, GPLc). Il doit exposer des indicateurs prix/géo
**fiables** et **testés** : prix moyen par région, dispersion,
classement des stations les moins chères, carte interactive.

Le piège est invisible :

- La source est un **XML-ZIP en ISO-8859-1** dont le format peut changer
  du jour au lendemain (donnée publique, hors contrôle).
- Le flux est un **snapshot complet** à chaque tirage : ingéré
  naïvement, on ré-empile les mêmes prix toutes les heures et la table
  fact explose.
- Sans **contrats de schéma** ni **tests automatisés bloquant le merge**,
  un changement source silencieux corrompt le warehouse pendant des
  semaines avant qu'un dashboard cassé ne révèle le problème.

**FuelFlow construit la chaîne complète qui répond à ce problème**, en
montrant les disciplines qu'on attend d'un *Analytics Engineer* :
contrats explicites, idempotence, freshness, CI bloquante prouvée,
médaillon, dbt portable entre deux warehouses cloud.

## 2. Démo & docs

| Surface | Lien | Source |
|---|---|---|
| Dashboard live (carte + KPIs prix/région) | _Looker Studio public — lien à coller après assemblage (cf. `docs/bi/looker-studio-guide.md`)_ | BigQuery `fuelflow_gold` |
| dbt docs (lineage réel, contracts, tests) | <https://raphaeldjaa71.github.io/fuelflow/> | manifest dbt |
| CI status | Badge en haut de page | GitHub Actions |
| Case study Power BI | _Screenshots à publier (cf. `docs/bi/powerbi-guide.md`)_ | Snowflake `FUELFLOW.GOLD` |

## 3. Architecture

![Architecture FuelFlow](docs/architecture/fuelflow-architecture.png)

> Source : `docs/architecture/fuelflow-architecture.mmd`. Régénération :
> `make diagram`.

Une nouvelle partition horaire de bronze atterrit dans GCS toutes les
heures sur le calendrier de **Paris**, sans intervention humaine. dbt
matérialise le silver/gold dans **les deux warehouses** ; la CI exécute
le build complet sur BigQuery à chaque PR.

## 4. Stack

`Python • uv • lxml • polars • GCS • Cloud Run Job • Cloud Scheduler • Snowflake • BigQuery • dbt Core • GitHub Actions (WIF keyless) • GitHub Pages • Looker Studio • Power BI`

## 5. Ce qui rend ce projet différent

| Pratique | Comment c'est démontré ici |
|---|---|
| **Data contracts dbt enforced** | `contract: enforced: true` sur **le fait + les 4 dimensions** (`data_type` Jinja **target-aware** Snowflake/BigQuery). Le build casse si la projection diverge du contrat. Spec dans [`docs/data-model/star-schema.md`](docs/data-model/star-schema.md). |
| **CI qui bloque vraiment le merge — prouvé** | `dbt build` sur PR via WIF keyless (aucune clé SA téléchargée). Une PR avec un test volontairement cassé a vu son merge passer en `mergeStateStatus: BLOCKED` ; le fix l'a rebasculée en `CLEAN`. (cf. PR #1 dans l'historique.) |
| **Ingestion autonome, incrémentale, idempotente** | Cloud Run Job déclenché par Cloud Scheduler (cron horaire Europe/Paris). Clé naturelle `(station_id, carburant_id, maj_timestamp)` + idempotence object-level GCS via `if_generation_match=0`. `fct_prix_carburant` matérialisé en **incremental merge** avec watermark strict sur `ingestion_ts`. |
| **Freshness checks** | `dbt source freshness` warn 90 min / error 6 h sur `ingestion_ts`. Non-bloquant en CI (responsabilité du scheduler, pas du contributeur). |
| **dbt portable Snowflake ↔ BigQuery** | Deux targets, types abstraits dbt (`dbt.type_string`, `type_numeric`, `type_timestamp`), conversions TZ et timestamps target-aware (cast `TIMESTAMP_NTZ`, `convert_timezone`, `APPROX_QUANTILES` vs `APPROX_PERCENTILE`). Parité **93/93 PASS** sur les deux moteurs. |
| **ADR pour chaque décision structurante** | 7 ADR au format Nygard sous [`docs/adr/`](docs/adr/) — dual-warehouse, Cloud Run vs Airflow, cadence horaire (jamais « temps réel »), médaillon, grain & dédup, contracts. |
| **Lineage public** | dbt docs déployées sur GitHub Pages à chaque push main. |

## 6. Lessons learned — 3 bugs réels capturés

Le dual-warehouse (Snowflake **+** BigQuery) a agi comme **détecteur de bugs** : un seul moteur les aurait laissé passer en silence.

1. **Timestamp Parquet `TIMESTAMP_MICROS` lu par Snowflake comme secondes.** L'external table SF avec `VALUE:maj_timestamp::TIMESTAMP_NTZ` produisait des années en **54 millions**. Les tests `not_null` et `unique` ne détectaient rien (les valeurs étaient présentes et distinctes). BQ lisait correctement le logical type. Fix : `TO_TIMESTAMP_NTZ(VALUE:maj_timestamp::NUMBER, 6)` avec scale=6.
2. **Cast `TIMESTAMP_NTZ → TIMESTAMP_TZ` côté Snowflake utilise le timezone de session.** Le trial sur AWS eu-west-3 tournait en `America/Los_Angeles` par défaut → 835 fausses « lignes futures » détectées par le test singulier `assert_no_future_maj`. Fix : garder `TIMESTAMP_NTZ` en convention UTC implicite (cohérent silver) et `cast(convert_timezone('UTC', current_timestamp()) as timestamp_ntz)` côté comparaison.
3. **`bq add-iam-policy-binding` en silent-fail.** L'API est en preview et requiert allowlisting projet ; sur un projet standard elle échoue silencieusement. Découvert seulement quand la CI a tenté de lire l'external table BQ en L7. Fix : grants per-dataset via le client Python BigQuery, idempotent et reproductible.

Méta-leçon : **les tests dbt seuls ne suffisent pas — la cross-validation entre deux moteurs trouve les bugs que ni l'un ni l'autre ne signale.**

## 7. Structure du repo

```
.
├── README.md
├── docs/
│   ├── architecture/          # diagramme (.mmd + .png) et dbt lineage
│   ├── adr/                   # 7 ADR au format Nygard (français)
│   ├── data-model/            # spec star schema + contracts
│   ├── bi/                    # guides Looker Studio + Power BI
│   └── case-study/            # case study HTML + brouillon LinkedIn
├── ingestion/                 # L1 — worker Python XML→Parquet (idempotent)
├── infra/                     # L2 + L7 — scripts gcloud / Snowflake / WIF
├── transform/                 # L3-L5+L8 — projet dbt (staging → int → gold + agg)
├── orchestration/             # L6 — Dockerfile + scripts Cloud Run/Scheduler
├── .github/workflows/         # L7 — CI dbt build bloquante + dbt docs Pages
├── pyproject.toml             # uv-managed
└── Makefile                   # setup / lint / test / diagram / ingest / dbt-*
```

## 8. Avancement par lot (10 / 10)

| Lot | Sujet | Statut |
|---|---|---|
| **L0** | Initialisation, ADR, design du modèle, diagramme, outillage | ✅ |
| **L1** | Ingestion Python (worker XML→Parquet, idempotence, retry, logs JSON) | ✅ |
| **L2** | Infra cloud (bucket GCS EU, datasets BQ, Snowflake DB/WH/integration) | ✅ |
| **L3** | dbt staging dual-target Snowflake + BigQuery, 13/13 PASS chacun | ✅ |
| **L4** | Intermediate + 4 dims + intégrité référentielle, 72/72 PASS chacun | ✅ |
| **L5** | Gold `fct_prix_carburant` + contracts enforced + tests, 63/63 PASS | ✅ |
| **L6** | Orchestration Cloud Run Job + Cloud Scheduler horaire Europe/Paris | ✅ |
| **L7** | CI/CD GitHub Actions WIF keyless + gate bloquant prouvé + fct incrémental + dbt docs Pages | ✅ |
| **L8** | 3 marts d'agrégation question-driven + guides BI (Looker Studio public + Power BI case study) | ✅ |
| **L9** | README final orienté problème, case study HTML, brouillon LinkedIn, diagramme rafraîchi | ✅ |

## 9. Démarrer en local

**Prérequis** :
- Python `>= 3.12` (uv gère)
- [`uv`](https://docs.astral.sh/uv/) `>= 0.5` (`curl -LsSf https://astral.sh/uv/install.sh | sh`)
- `git >= 2.30` (`brew install git` si le git système macOS est en 2.14)
- `node >= 18` + `npx` (pour `make diagram`)
- `gcloud` + ADC, et la clé privée RSA dans `.secrets/snowflake_rsa_key.p8` (pour le target Snowflake)

```bash
git clone https://github.com/RaphaelDjaa71/fuelflow.git
cd fuelflow
make setup            # uv sync + pre-commit install
make lint             # ruff
make diagram          # régénère le PNG d'architecture

# Worker d'ingestion
make ingest-local     # download + parse, sortie locale data/bronze/
make ingest-gcs       # idem avec upload réel GCS (ADC requis)

# dbt
make dbt-deps
make dbt-bq           # build complet sur BigQuery (CI target)
make dbt-sf           # build complet sur Snowflake (warehouse principal)
make dbt-docs-bq      # génère target/manifest + catalog
make dbt-lineage      # rend docs/architecture/dbt-lineage.png
```

Variables d'environnement : copier `.env.example` en `.env` et
renseigner. Les vrais secrets ne sont **jamais** commités — hook
`gitleaks` actif en pre-commit.

---

*Projet portfolio de **Raphaël DJAA** — Analytics Engineer. Licence MIT.
Case study écrit : [`docs/case-study/fuelflow-case-study.html`](docs/case-study/fuelflow-case-study.html).*
