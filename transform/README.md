# transform/ — dbt project

**Lot responsable :** L3 (staging) → L4 (intermediate) → L5 (gold + contracts).

**Statut L3 :** ✅ Staging + tests verts sur BigQuery (13/13).

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

### Snowflake (dev local)
`authenticator: externalbrowser` → un onglet de navigateur s'ouvre à chaque
`dbt build --target snowflake` pour le challenge MFA. Pas de password
stocké en `profiles.yml` quand cet authenticator est utilisé.

> **CI Snowflake = L7.** Pour automatiser dbt sur Snowflake dans GitHub
> Actions, il faudra basculer en **key-pair authentication** :
> `ALTER USER … SET RSA_PUBLIC_KEY = '…'` côté SF + clé privée en
> GitHub Secret, profile `authenticator: snowflake_jwt` + `private_key_path`.
> Hors scope L3.

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

## Audit empirique L3 sur BigQuery

```
row_count: 32 666 | distinct_keys: 32 666 (zero collision sur ce snapshot)
maj_min: 2024-05-24 08:17:53 UTC | maj_max: 2026-06-03 21:30:00 UTC
prix ∈ [0.699 ; 2.89]
```

Match exact avec `ext_prix_bronze` (L2).

## Pour rejouer en local

```bash
gcloud auth application-default login          # une fois
cd transform && DBT_PROFILES_DIR=. uv run dbt deps   # ou `make dbt-deps`
make dbt-bq                                    # full build sur BigQuery
make dbt-freshness-bq                          # source freshness
make dbt-sf                                    # Snowflake (browser MFA prompt)
```
