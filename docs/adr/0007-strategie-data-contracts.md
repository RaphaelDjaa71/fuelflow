# ADR 0007 — Stratégie data contracts

## Statut
Accepté — 2026-06-03

## Contexte
Les data contracts sont un des deux ou trois différenciateurs CV ciblés
par FuelFlow (cf. README). L'enjeu : **détecter immédiatement et
bruyamment** toute dérive du schéma source qui corromprait silencieusement
le warehouse, plutôt que de découvrir le problème via un dashboard cassé
ou une plainte utilisateur.

Trois niveaux possibles :

1. **Tests dbt génériques** (`not_null`, `unique`, `accepted_values`,
   `relationships`) — couvre la qualité ligne par ligne.
2. **Model contracts dbt** (YAML `contract: {enforced: true}` + types) —
   couvre la **forme du schéma** : si une colonne disparaît, change de
   type, ou apparaît, dbt refuse de construire le modèle.
3. **Freshness checks dbt** (`sources.yml` + `loaded_at_field`) —
   couvre la **vivacité** de la donnée : un retard de chargement
   déclenche un fail.

Sans data contracts, le risque typique : la source ajoute une colonne
`<station_horaires>`, le parser l'ignore, six mois plus tard un
analyste demande "depuis quand on a les horaires ?" — réponse : depuis
toujours, mais personne ne le sait. À l'inverse : la source renomme
`<prix maj=...>` en `<prix updated_at=...>`, le parser plante
silencieusement, le fact retourne 0 lignes pendant 48 h avant que
quelqu'un remarque.

## Décision
On applique les **trois niveaux** sur l'ensemble des modèles gold,
plus les sources critiques :

### 1) Tests dbt génériques
Sur chaque colonne de la spec `docs/data-model/star-schema.md` :
- `not_null` partout où la spec dit "non nullable".
- `unique` sur les surrogate keys et la clé naturelle composite.
- `accepted_values` sur `carburant_code` (Gazole / SP95 / SP98 / E10 /
  E85 / GPLc).
- `relationships` pour les FK fact → dim.

### 2) Model contracts (`contract: enforced: true`)
Sur **tous les modèles gold** (`fct_*`, `dim_*`). Le YAML déclare types
et constraints. dbt refuse de matérialiser si la requête SELECT ne
correspond pas exactement à la spec — c'est le mécanisme qui rend la
détection de drift **bloquante**.

Pour la portabilité Snowflake / BigQuery, on utilise des **types dbt
abstraits** (`NUMERIC`, `STRING`, `TIMESTAMP`) traduits par adapter au
moment du build (`dbt-bigquery` et `dbt-snowflake` gèrent les
équivalences ; cas exotiques documentés dans
`docs/data-model/star-schema.md` § portabilité).

### 3) Freshness checks
Sur `source('roulez_eco', 'instantane_parquet')` :
- `warn_after: { count: 90, period: minute }` — alerte si dernière
  ingestion > 90 min (couvre cadence horaire + 30 min de marge).
- `error_after: { count: 6, period: hour }` — fail si > 6 h.

### Intégration CI
Les trois niveaux tournent en CI (`dbt build` sur target BigQuery, ADR
0002). Un échec **bloque le merge**. C'est le différenciateur
principal du projet vs un repo dbt "ouvert sans gate".

## Conséquences
**Positives :**
- Drift schéma source = build fail explicite, jamais une corruption
  silencieuse.
- Confiance documentée : un consommateur du gold peut s'appuyer sur le
  contrat YAML sans inspecter le SQL.
- Différenciateur portfolio direct, immédiatement visible dans la CI
  GitHub.

**Négatives :**
- Maintenance des YAML contracts à chaque évolution de schéma. Mitigé
  par génération initiale via `dbt-codegen`.
- Les contracts dbt sont récents et certains adapters ont des
  limitations (`not_null` au niveau colonne en `enforced` n'est pas
  identique côté Snowflake et BigQuery). Cas connus documentés dans
  `docs/data-model/star-schema.md`.
- Le freshness `error_after: 6h` doit être ajusté si la cadence
  d'ingestion change ; lié à ADR 0004.
