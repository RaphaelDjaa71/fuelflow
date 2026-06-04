# Guide — case study Power BI (Snowflake)

> Snowflake est le warehouse principal du projet (signal CV). Power BI
> Desktop sert de support de **case study** : capture d'écran + narratif
> de bout en bout. Pas de publication Power BI Service (nécessite une
> licence) ; le rendu reste sous forme d'images embarquées dans le
> README/case study écrit.

## 0) Pré-vol

- L'external table Snowflake `FUELFLOW.BRONZE_EXT.EXT_PRIX_BRONZE` est
  rafraîchie automatiquement par le hook `on-run-start` de dbt
  (cf. `transform/dbt_project.yml`). En pratique, **lance `make dbt-sf`
  avant d'ouvrir Power BI** : ça force un refresh + un rebuild
  incrémental du fait et des trois marts d'agrégation.
- MFA Snowflake activé. Power BI demandera une auth interactive (navigateur).

## 1) Connexion Power BI Desktop → Snowflake

1. **Get Data** → **More** → catégorie **Database** → **Snowflake**.
2. **Server** : `DOUCVHV-XC13247.snowflakecomputing.com` (sans le suffixe `.europe-west3.gcp`).
3. **Warehouse** : `FUELFLOW_WH`.
4. **Data Connectivity mode** : **Import** (les marts sont compacts, l'import suffit ; DirectQuery réveillerait le warehouse à chaque interaction utilisateur).
5. **Auth** : choisir **Microsoft account** non, **Username and password** **non** (MFA cassera) → choisir **Snowflake** avec ton user + mot de passe + MFA navigateur.
6. **Database** = `FUELFLOW`, **Schema** = `GOLD`. Importer :
   - `AGG_DERNIER_PRIX_STATION_CARBURANT`
   - `AGG_PRIX_REGION_CARBURANT`
   - `AGG_CLASSEMENT_STATIONS`
   - `DIM_CARBURANT`, `DIM_DATE` (pour les filtres temporels optionnels)

> Astuce : si l'auth password+MFA pose souci, importer via **ODBC**
> Snowflake avec le **key-pair JWT** (la clé privée locale
> `.secrets/snowflake_rsa_key.p8` est déjà en place). Sur Power BI
> Desktop pour Mac la prise en charge ODBC est limitée — Windows
> Power BI Desktop est le chemin propre.

## 2) Modèle de données (Power BI Modeling view)

Relations à créer :
- `AGG_DERNIER_PRIX_STATION_CARBURANT[CARBURANT_NOM]` → `DIM_CARBURANT[CARBURANT_NOM]`
- `AGG_PRIX_REGION_CARBURANT[CARBURANT_NOM]` → `DIM_CARBURANT[CARBURANT_NOM]`
- `AGG_CLASSEMENT_STATIONS[REGION_NOM, CARBURANT_NOM]` → `AGG_PRIX_REGION_CARBURANT[REGION_NOM, CARBURANT_NOM]`

Masquer les colonnes techniques (`STATION_SK`, `CARBURANT_SK`, etc.) pour ne laisser visibles que les attributs analytiques.

## 3) Visuels (mêmes 3 questions métier que Looker Studio)

### Visuel A — Map des stations (question 2)

- Map (built-in) avec latitude/longitude depuis `AGG_DERNIER_PRIX_STATION_CARBURANT`.
- Bubble size : `PRIX_EURO`. Color saturation : `PRIX_EURO` (vert → rouge).
- Slicer : `CARBURANT_NOM` (single select, Gazole par défaut).

### Visuel B — Classement régional (question 1)

- Bar chart horizontal trié.
- Axis : `REGION_NOM` de `AGG_PRIX_REGION_CARBURANT`.
- Values : `PRIX_MOYEN`.
- Tooltip : `COUNT_STATIONS`, `PRIX_MIN`, `PRIX_MAX`, `PRIX_ECART_TYPE`.

### Visuel C — Box-plot prix (question 3)

- Power BI n'a pas de box-plot natif → utiliser le **visual Box and Whisker** du marketplace, OU un bar chart « range » avec `PRIX_MIN` à `PRIX_MAX` et un marker sur `PRIX_MEDIAN_APPROX`.

### Cartes KPI (top du rapport)

- Prix moyen national, écart national, nombre de stations couvertes.
- Date du dernier `MAJ_TIMESTAMP_UTC` (drill carte fraîcheur).

## 4) Narratif case study

Le rendu final est un PDF ou un Notion (3-5 pages) avec :

1. **Problème métier** : qui a besoin de ces KPIs et pourquoi ?
2. **Architecture** : screenshot `docs/architecture/fuelflow-architecture.png` + narration en 5 lignes (ingestion horaire → bronze GCS → external tables BQ/SF → dbt silver/gold → BI).
3. **Différenciateurs livrés** :
   - Contracts enforced cross-warehouse (BQ + SF identiques).
   - CI bloquante prouvée (PR #1 cassée → red → BLOCKED → fix → green → merged).
   - Incrémental sur `fct_prix_carburant` avec watermark `ingestion_ts`.
   - 2 bugs de fuseau capturés par la doctrine dual-warehouse (cf. lessons learned).
4. **Lessons learned** :
   - Bug 1 : Parquet `TIMESTAMP_MICROS` lu par Snowflake comme secondes → year 54M (L3). Fix : `TO_TIMESTAMP_NTZ(..., 6)`.
   - Bug 2 : `cast(NTZ as TIMESTAMP_TZ)` utilise la session TIMEZONE → 835 fausses « future rows » sur trial US-WEST (L5). Fix : garder NTZ + `convert_timezone('UTC', current_timestamp())` côté test.
   - Bug 3 (process) : `bq add-iam-policy-binding` requiert preview allowlist → silent fail. Application IAM via Python BQ client en L7.
5. **Screenshots** :
   - `docs/architecture/fuelflow-architecture.png`
   - `docs/architecture/dbt-lineage.png`
   - Power BI map + bar (à produire)
   - Looker Studio public (à produire)
   - CI red/green sur PR #1 (à capturer dans le case study)

## 5) Anti-patterns

- **DirectQuery** sur le trial Snowflake → consomme des crédits à chaque interaction. Import → unique requête au refresh.
- Saisir le password Snowflake dans la connexion Power BI sans tester d'abord le MFA → connexion qui pend. Préférer auth navigateur.
- Tenter de publier sur Power BI Service sans licence Pro → blocage silencieux. Le case study reste en images.
