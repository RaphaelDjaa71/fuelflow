# transform/ — dbt project

**Lot responsable :** L3 (staging) → L4 (intermediate) → L5 (gold + contracts).

**Statut L3 :** ✅ Staging + tests verts **sur les deux warehouses**, audits Snowflake et BigQuery identiques.

## Structure

```
transform/
├── dbt_project.yml          # project config, profile=fuelflow
├── packages.yml             # dbt_utils >=1.3, <2
├── profiles.yml             # GITIGNORED (creds Snowflake + BQ)
├── models/staging/
│   ├── _sources.yml         # roulez_eco.ext_prix_bronze + freshness
│   ├── _models.yml          # stg_prix schema + tests
│   └── stg_prix.sql         # typed view + UTC + dedup over natural key
└── target/, dbt_packages/, logs/  # all gitignored
```

## Cibles Make

| Cible | Action |
|---|---|
| `make dbt-deps` | Installe les packages dbt (`dbt_utils`). |
| `make dbt-debug T=bigquery` (ou `T=snowflake`) | Valide la connexion. |
| `make dbt-bq` | `dbt build` sur le target **bigquery** (oauth via ADC, free tier, CI). |
| `make dbt-sf` | `dbt build` sur le target **snowflake** (browser MFA prompt — voir § auth). |
| `make dbt-freshness-bq` | `dbt source freshness` (seuils warn 90 min / error 6 h). |
| `make dbt-docs-bq` | `dbt docs generate`. |

## Authentification

### BigQuery (par défaut, CI)
`method: oauth` → utilise les Application Default Credentials du user
(`gcloud auth application-default login`). Pas de clé JSON locale, pas de
secret committé. En L7 la CI utilisera une clé du SA `fuelflow-ci` chargée
depuis GitHub Actions Secrets.

### Snowflake — **key-pair JWT** (dev local + CI L7)
`authenticator: jwt` + `private_key_path` pointant sur
`.secrets/snowflake_rsa_key.p8` (gitigné). Aucun mot de passe dans
`profiles.yml`, aucun prompt MFA à chaque run (la clé privée seule
fait foi).

Set-up déjà fait pour le user `RAPHAELDJAA` :
```bash
# clé générée localement (sans passphrase pour MVP) :
openssl genrsa 2048 | openssl pkcs8 -topk8 -inform PEM \
  -out .secrets/snowflake_rsa_key.p8 -nocrypt
openssl rsa -in .secrets/snowflake_rsa_key.p8 -pubout \
  -out .secrets/snowflake_rsa_key.pub
# clé publique enregistrée côté Snowflake :
#   USE ROLE ACCOUNTADMIN;
#   ALTER USER RAPHAELDJAA SET RSA_PUBLIC_KEY = '<pubkey>';
```
> Le détour par MFA (Snowsight UI / `externalbrowser` / `username_password_mfa`)
> a été écarté en L3 : le trial Snowflake n'a pas SAML IdP configuré
> (externalbrowser KO) et la méthode MFA disponible
> ("none of your current MFA methods are supported for programmatic
> authentication") n'est pas exploitable depuis le connecteur Python.
> Key-pair est la voie propre et c'est ce que la CI utilisera en L7.

## Modèle de staging — `stg_prix`

Matérialisation : `view` (rapide, pas de stockage redondant).

Transformations appliquées :
1. **Typing strict** via `dbt.type_string()`, `type_float()`, `type_numeric()`,
   `type_timestamp()` — portable Snowflake ↔ BigQuery.
2. **Conversion timezone** : la colonne `maj_timestamp` source est en heure
   locale Europe/Paris (naive). Sur BigQuery elle est lue comme TIMESTAMP-UTC
   (faussement) ; on la passe en DATETIME pour gommer ce TZ, puis on
   ré-ancre en Europe/Paris pour récupérer l'instant UTC exact. Sur
   Snowflake, `convert_timezone('Europe/Paris', 'UTC', maj_timestamp)` sur
   un `TIMESTAMP_NTZ` fait la même chose.
3. **Déduplication ligne** sur la clé naturelle
   `(station_id, carburant_id, maj_timestamp_utc)` via `ROW_NUMBER()`
   ordonné par `ingestion_ts` croissant (on garde la première occurrence
   chronologique).
4. **Surrogate key** `prix_sk` via `dbt_utils.generate_surrogate_key`
   (md5 cross-warehouse de la clé naturelle).

## Tests appliqués (13 au total, tous PASS sur BigQuery)

| Type | Cible | Niveau |
|---|---|---|
| `not_null` | prix_sk, station_id, carburant_id, carburant_nom, maj_timestamp_utc, prix_euro, ingestion_ts | error |
| `unique` | prix_sk | error |
| `accepted_values` | carburant_id ∈ {1,2,3,4,5,6} | error |
| `accepted_values` | carburant_nom ∈ {Gazole, SP95, SP98, E10, E85, GPLc} | error |
| `dbt_utils.unique_combination_of_columns` | (station_id, carburant_id, maj_timestamp_utc) | error |
| `dbt_utils.expression_is_true` (BETWEEN 0.5 AND 3.5) | prix_euro | **warn** (donnée source, n'arrête pas la CI) |

## Audit empirique L3 — Snowflake et BigQuery, identiques

| Métrique | BigQuery | Snowflake |
|---|---|---|
| `row_count` | 32 666 | 32 666 |
| `distinct prix_sk` | 32 666 | 32 666 |
| `prix_min` / `prix_max` | 0.699 / 2.89 | 0.699 / 2.89 |
| `lat_min` / `lat_max` | 41.391 / 51.065 | 41.391 / 51.065 |
| `lon_min` / `lon_max` | -4.723 / 9.547 | -4.723 / 9.547 |
| `distinct station_id` | 9 608 | 9 608 |
| `maj_min` (UTC) | 2024-05-24 08:17:53 | 2024-05-24 08:17:53 |
| `maj_max` (UTC) | 2026-06-03 21:30:00 | 2026-06-03 21:30:00 |

Le grain et la conversion Paris→UTC sont parfaitement reproductibles
sur les deux moteurs.

### Sortie `dbt build --target snowflake`
```
Found 1 model, 12 data tests, 1 source, 652 macros
Concurrency: 4 threads (target='snowflake')
...
Completed successfully
Done. PASS=13 WARN=0 ERROR=0 SKIP=0 NO-OP=0 TOTAL=13
```

### Sortie `dbt build --target bigquery`
```
Found 1 model, 12 data tests, 1 source, ...
Concurrency: 4 threads (target='bigquery')
...
Completed successfully
Done. PASS=13 WARN=0 ERROR=0 SKIP=0 NO-OP=0 TOTAL=13
```

### Piège timestamp Snowflake — corrigé en L2
La closure Snowflake a révélé que `maj_timestamp` (polars
`Datetime[us]` naïf → Parquet `TIMESTAMP(MICROS)`) était lu par
Snowflake comme un entier de microsecondes mais cast en `TIMESTAMP_NTZ`
en l'interprétant comme **secondes**, produisant des années en
54 millions. Les tests `not_null` / `unique` ne détectaient pas
l'anomalie. Fix appliqué à `infra/snowflake/03_stage_external_table.sql` :
remplacement de `VALUE:maj_timestamp::TIMESTAMP_NTZ` par
`TO_TIMESTAMP_NTZ(VALUE:maj_timestamp::NUMBER, 6)` (scale=6 = micro).
`ingestion_ts` arrive en ISO-8601 (polars `Datetime[us, UTC]`) et n'est
pas affecté.

## Pour rejouer en local

```bash
gcloud auth application-default login          # une fois
cd transform && DBT_PROFILES_DIR=. uv run dbt deps   # ou `make dbt-deps`
make dbt-bq                                    # full build sur BigQuery
make dbt-freshness-bq                          # source freshness
make dbt-sf                                    # Snowflake (browser MFA prompt)
```
