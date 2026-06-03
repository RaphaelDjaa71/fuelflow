# ADR 0006 — Grain du fait et clé de déduplication

## Statut
Accepté — 2026-06-03

## Contexte
Le flux source `donnees.roulez-eco.fr` est un **snapshot complet**
toutes les 10 minutes : chaque XML contient l'état actuel de toutes les
stations et tous les prix. Une cadence d'ingestion horaire (ADR 0004)
ramène donc le **même prix** plusieurs fois s'il n'a pas changé entre
deux runs.

Si on n'a pas une politique claire de grain de fait :
- Soit on **dédoublonne mal** et `fct_prix_carburant` explose en taille
  (chaque heure réinsère ~55 000 lignes identiques).
- Soit on **agrège trop tôt** (one row per day per station) et on
  perd la granularité temporelle qui fait l'intérêt analytique.

Le bon grain doit refléter le **vrai événement** : un changement de
prix publié par la station. La source fournit pour ça un champ
`maj` (`<prix maj="2026-06-03 09:42:00" ... />`), un timestamp de
dernière mise à jour côté station.

## Décision
**Grain de `fct_prix_carburant`** : une ligne par
`(station, carburant, événement de mise à jour de prix)`.

**Clé naturelle composite** :
```
(station_id, carburant_id, maj_timestamp)
```

**Clé surrogate** (`prix_sk`) :
```
md5(station_id || '|' || carburant_id || '|' || cast(maj_timestamp as string))
```
Stable, déterministe, identique entre Snowflake et BigQuery (les deux
ont `md5()`).

**Politique de dédup** :
- En **silver** : on garde la première occurrence rencontrée pour une
  même clé naturelle (premier hit chronologique en ingestion).
- En **gold** : `unique_key = prix_sk` pour les modèles dbt
  incrémentaux. Un MERGE remplaçant la ligne existante par la nouvelle
  si elle arrive ; en pratique elle ne devrait jamais arriver deux fois
  avec des valeurs différentes.

Cette clé garantit que **`fct_prix_carburant` reste idempotent quelle
que soit la cadence d'ingestion** (10 min, horaire, quotidienne) : on
ne crée jamais de doublons.

## Conséquences
**Positives :**
- Idempotence prouvable : un test dbt `unique(prix_sk)` doit toujours
  passer.
- Cadence ajustable sans refonte (cf. ADR 0004).
- Possibilité de calculer des KPIs "fréquence de changement de prix par
  station" sans bruit de répétition.

**Négatives :**
- Si la source modifie le format de `maj` (changement de timezone,
  ajout de millisecondes), la clé surrogate change et on a un *churn*
  artificiel. Mitigé par un test dbt qui surveille la distribution des
  longueurs/formats `maj_timestamp`.
- Le hash `md5` est très peu coûteux mais reste une colonne à stocker.
  Au volume cible (~2-5 M lignes/an), négligeable.

## Dette technique tracée
- **SCD type 1 ou type 2 pour `dim_station`** : tranchée à L4. Décision
  par défaut = **type 1** (overwrite des changements d'adresse/marque),
  car déménagement de station très rare et le projet portfolio ne
  démontre rien de plus sur un type 2 à ce stade. À reconsidérer si un
  cas analytique le justifie.
