# Design du modèle de données — star schema FuelFlow

> Document **source de vérité** pour les lots L4 (silver) et L5 (gold + contracts).
> Toute divergence entre ce document et le code dbt doit être tranchée ici **avant** d'éditer
> le code. Les YAML de contrats (`contracts: enforced: true`) sont la transcription
> mécanique des tableaux ci-dessous.

## 1. Grain du fait

`fct_prix_carburant` a un grain : **une ligne par
(`station`, `carburant`, `événement de mise à jour de prix`
identifié par `maj_timestamp`)**.

Le champ `maj_timestamp` provient de l'attribut `maj` de l'élément
`<prix>` du XML source — c'est l'horodatage du **changement de prix
côté station**, pas l'horodatage de notre ingestion.

Conséquence : si une station ne change pas son prix de Gazole pendant
trois semaines, on aura **une seule ligne** dans `fct_prix_carburant`
pour ce carburant-là sur la période, peu importe que l'ingestion ait
tourné 504 fois.

## 2. Clé de déduplication

**Clé naturelle composite** :
```
(station_id, carburant_id, maj_timestamp)
```

**Clé surrogate** `prix_sk` :
```sql
md5(cast(station_id as string) || '|' ||
    cast(carburant_id as string) || '|' ||
    cast(maj_timestamp as string))
```

Identique entre Snowflake et BigQuery (`md5()` existe dans les deux).
Test dbt `unique(prix_sk)` doit toujours passer.

## 3. Tables — spec des contracts

### 3.1 `fct_prix_carburant` (fact)

**Contrat dbt `enforced: true` implémenté en L5** — la matérialisation
échoue si le SELECT du modèle ne correspond pas exactement à ces types.

| Colonne | Type abstrait | Snowflake | BigQuery | Nullable | Contrainte / Test |
|---|---|---|---|---|---|
| `prix_sk` | STRING(32) | `VARCHAR` | `STRING` | non | `unique`, `not_null`, PK |
| `station_sk` | STRING(32) | `VARCHAR` | `STRING` | non | `not_null`, FK → `dim_station.station_sk` |
| `carburant_sk` | STRING(32) | `VARCHAR` | `STRING` | non | `not_null`, FK → `dim_carburant.carburant_sk` |
| `date_sk` | INT | `NUMBER` | `INT64` | non | `not_null`, FK → `dim_date.date_sk` (format YYYYMMDD, jour Paris) |
| `localisation_sk` | STRING(32) | `VARCHAR` | `STRING` | non | `not_null`, FK → `dim_localisation.localisation_sk` |
| `prix_euro` | NUMERIC(10,3) | `NUMBER(10,3)` | `NUMERIC` | non | `not_null`, `prix_euro BETWEEN 0.5 AND 3.5` (sévérité **warn**) |
| `maj_timestamp_utc` | TIMESTAMP UTC | `TIMESTAMP_NTZ` (UTC convention) | `TIMESTAMP` (UTC implicite) | non | `not_null` |
| `ingestion_date` | DATE | `DATE` | `DATE` | non | `not_null` |

> **Note d'unité (audit L1)** : la source `donnees.roulez-eco.fr` expose
> aujourd'hui le champ `<prix valeur="...">` directement en **euros
> décimaux** (ex. `valeur="1.957"`). Aucune conversion `÷1000` n'est
> appliquée (le commentaire historique « millièmes d'euros » est
> obsolète sur le flux courant). Le bronze stocke un `Float64`
> arrondi à 3 décimales ; le contract gold remonte en `NUMERIC(10,3)`.
>
> **Décision L5 — sévérité du test de plage** : le test
> `prix_euro BETWEEN 0.5 AND 3.5` est implémenté en **sévérité `warn`**,
> pas `error`. Raison : la valeur est une donnée source que nous ne
> contrôlons pas ; une station qui publie une valeur hors plage (saisie
> erronée, promotion, GPLc à 0,7 €) doit alerter mais **ne doit pas
> casser le build CI**. Les tests `not_null`, `unique` et le contract
> lui-même restent en `error` (drift de schéma = fail bloquant).

**Index implicite / clustering** :
- Snowflake : clustering sur `(ingestion_date, station_sk)`.
- BigQuery : `partition by ingestion_date cluster by station_sk`.

### 3.2 `dim_station` (dimension)

| Colonne | Type abstrait | Snowflake | BigQuery | Nullable | Contrainte / Test |
|---|---|---|---|---|---|
| `station_sk` | STRING(32) | `VARCHAR(32)` | `STRING` | non | `unique`, `not_null`, PK |
| `station_id` | STRING | `VARCHAR(20)` | `STRING` | non | `unique`, `not_null` (natural key, ID source) |
| `latitude` | NUMERIC(9,6) | `NUMBER(9,6)` | `NUMERIC` | oui | `latitude BETWEEN 41 AND 52` (FR métropole, test custom) |
| `longitude` | NUMERIC(9,6) | `NUMBER(9,6)` | `NUMERIC` | oui | `longitude BETWEEN -5 AND 10` |
| `adresse` | STRING | `VARCHAR(500)` | `STRING` | oui | — |
| `cp` | STRING(5) | `VARCHAR(5)` | `STRING` | oui | code postal source (5 caractères, zéros de tête préservés) |
| `pop` | STRING(1) | `VARCHAR(1)` | `STRING` | oui | `accepted_values: ['R', 'A']` (Route / Autoroute) |

> **Marque / nom enseigne : hors scope de la source open data.** Le flux
> `donnees.roulez-eco.fr` (vérifié L1) n'expose ni le nom commercial ni
> la marque/enseigne des stations. Un enrichissement (Total / Shell /
> Esso...) nécessiterait un référentiel externe (web-scrape, base
> tierce) — non traité dans FuelFlow. Documenté ici pour qu'un futur
> contributeur ne crée pas la colonne par erreur.

**Décision SCD** : **Type 1** par défaut (overwrite). Justification dans
ADR 0006. Reconsidérer en L4 si un cas analytique le requiert.

### 3.3 `dim_carburant` (dimension)

| Colonne | Type abstrait | Snowflake | BigQuery | Nullable | Contrainte / Test |
|---|---|---|---|---|---|
| `carburant_sk` | STRING(32) | `VARCHAR(32)` | `STRING` | non | `unique`, `not_null`, PK |
| `carburant_code` | STRING(10) | `VARCHAR(10)` | `STRING` | non | `unique`, `accepted_values: [Gazole, SP95, SP98, E10, E85, GPLc]` |
| `carburant_libelle` | STRING(50) | `VARCHAR(50)` | `STRING` | non | `not_null` |

Cette dimension a au plus 6 lignes. Matérialisation : `table` (pas `incremental`).

### 3.4 `dim_date` (dimension)

| Colonne | Type abstrait | Snowflake | BigQuery | Nullable | Contrainte / Test |
|---|---|---|---|---|---|
| `date_sk` | INT | `NUMBER(8,0)` | `INT64` | non | `unique`, `not_null`, format YYYYMMDD |
| `date_jour` | DATE | `DATE` | `DATE` | non | `unique`, `not_null` |
| `jour_semaine` | INT | `NUMBER(1,0)` | `INT64` | non | `accepted_values: [1..7]` (ISO, 1=lundi) |
| `numero_semaine` | INT | `NUMBER(2,0)` | `INT64` | non | `accepted_values: [1..53]` |
| `mois` | INT | `NUMBER(2,0)` | `INT64` | non | `accepted_values: [1..12]` |
| `trimestre` | INT | `NUMBER(1,0)` | `INT64` | non | `accepted_values: [1..4]` |
| `annee` | INT | `NUMBER(4,0)` | `INT64` | non | `not_null` |
| `est_jour_ouvre` | BOOLEAN | `BOOLEAN` | `BOOL` | non | `not_null` |

Matérialisation : `table`. **Range effectif L5 : 2007-01-01 → 2031-12-31**
(9 131 jours). La borne basse a été élargie en L5 pour blinder le test
`relationships` `fct.date_sk → dim_date` contre une vieille `maj` source
sortie d'une station dormante (le `maj_min` empirique courant est ~2024
mais un futur snapshot pourrait surfacer plus vieux).

> **Conventions d'implémentation (L4)** : `day_of_week` est normalisé en
> ISO (1=Lundi, 7=Dimanche) sur les deux moteurs ; les libellés FR
> (`month_name_fr`, `day_name_fr`) sont générés via `CASE` portable —
> pas de `FORMAT_DATE`/`TO_CHAR` dépendant de la locale.

### 3.5 `dim_localisation` (dimension)

**Grain L4** : une ligne par `(cp, ville)` distinct vu dans `stg_prix`
(≈ 7 116 sur le snapshot courant).

| Colonne | Type abstrait | Snowflake | BigQuery | Nullable | Contrainte / Test |
|---|---|---|---|---|---|
| `localisation_sk` | STRING(32) | `VARCHAR(32)` | `STRING` | non | `unique`, `not_null`, PK (md5(`cp`, `ville`)) |
| `cp` | STRING(5) | `VARCHAR(5)` | `STRING` | oui | code postal source (zéros de tête préservés) |
| `ville` | STRING | `VARCHAR(100)` | `STRING` | oui | — |
| `dept_code` | STRING(3) | `VARCHAR(3)` | `STRING` | oui | `relationships → seed_departement.dept_code` |
| `dept_nom` | STRING | `VARCHAR(100)` | `STRING` | oui | jointure depuis `seed_departement` |
| `region_nom` | STRING | `VARCHAR(100)` | `STRING` | oui | jointure depuis `seed_departement` (18 régions : 13 métropole + 5 DOM) |

**Source des dérivations L4** : adresse + code postal de la station
(les coordonnées ne sont **pas** utilisées — on évite tout géocodage).
`dept_code` dérivé du `cp` par règles SQL portables :

| Pattern `cp` | `dept_code` | Exemple |
|---|---|---|
| `cp` commence par `97` ou `98` | `LEFT(cp, 3)` | `97400` → `974` (La Réunion) |
| `cp` commence par `20` et < `20200` | `2A` | `20000` → `2A` |
| `cp` commence par `20` et ≥ `20200` | `2B` | `20200` → `2B` |
| autres | `LEFT(cp, 2)` | `34150` → `34` |
| `cp` null/vide | null | — |

`dept_nom` et `region_nom` viennent d'un seed dbt
(`seed_departement.csv`, 101 lignes : 96 départements métropole avec
`2A`/`2B` + 5 DOM) — référentiel public stable, pas d'API au runtime.

> **Limitation connue** : la séparation 2A/2B par tranche de CP n'est
> pas exacte au bord de plage (un CP unique peut couvrir des communes
> dans les deux départements). Acceptable pour un projet portfolio ;
> documenté pour qu'un futur lecteur ne le découvre pas par surprise.

## 4. Note de portabilité Snowflake ↔ BigQuery

| Catégorie | Snowflake | BigQuery | Notes |
|---|---|---|---|
| Entier court | `NUMBER(P,0)` | `INT64` | dbt-adapter gère via `int` ou `bigint` |
| Décimal monétaire | `NUMBER(10,3)` | `NUMERIC` | Précision identique ; **éviter `FLOAT64`** côté BQ pour le prix |
| Chaîne courte | `VARCHAR(N)` | `STRING` | BQ ignore `N` ; le contract YAML stocke la limite logique |
| Timestamp sans TZ | `TIMESTAMP_NTZ` | `TIMESTAMP` | BQ `TIMESTAMP` est en UTC ; convention projet = UTC partout |
| Date pure | `DATE` | `DATE` | OK |
| Booléen | `BOOLEAN` | `BOOL` | OK |
| Hash | `md5(VARCHAR) → VARCHAR(32)` | `md5(STRING) → BYTES` | **Piège** : `md5()` BQ retourne BYTES, on `TO_HEX(MD5(...))` pour avoir une STRING(32) comparable Snowflake. Macro dbt à fournir. |

## 5. Conventions transverses

- **Timezone** : toutes les colonnes timestamp sont en UTC. Le
  `maj_timestamp` source est interprété comme heure de Paris (Europe/Paris)
  par la source, conversion en UTC en silver.
- **Encodage** : UTF-8 partout.
- **Nommage** : `snake_case` pour colonnes et tables.
- **Préfixe modèles dbt** : `stg_` (staging), `int_` (intermediate),
  `dim_` / `fct_` (gold).
- **Surrogate keys** : toujours `md5(...)` 32 hex chars, jamais
  `row_number()` (instable au rebuild).

## 6. Ce qui reste à trancher (dette technique tracée)

- **Référentiel INSEE communes** : seed dbt vs table externe → L4.
- **SCD `dim_station`** : confirmer type 1 ou passer type 2 → L4.
- **Région FR liste figée** : enum exact à figer en L4 (13 régions
  métropole + outre-mer ?).
- **Stratégie pour stations apparaissant/disparaissant** : politique
  d'inactivité (>X jours sans MAJ → flag `est_active = false`) → L5.
