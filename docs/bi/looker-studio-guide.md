# Guide — assembler le dashboard FuelFlow dans Looker Studio (BigQuery)

> Looker Studio est un outil GUI. Ce guide donne les étapes manuelles à
> reproduire pour assembler le dashboard public à partir des marts dbt
> livrés en L8. dbt produit la donnée ; Looker Studio l'expose.

## Mapping question métier ↔ mart ↔ visuel

| Question métier | Mart BigQuery | Visuel principal |
|---|---|---|
| « Où le carburant est-il le moins cher en France ? » | `fuelflow_gold.agg_prix_region_carburant` | Carte choroplèthe par région (fallback : bar chart classé) |
| « Quelles stations sont les moins chères, et où ? » | `fuelflow_gold.agg_dernier_prix_station_carburant` | **Bubble map** lat/long, couleur/taille = `prix_euro` |
| « Quelle dispersion des prix par région/carburant ? » | `fuelflow_gold.agg_prix_region_carburant` | Histogramme `prix_min` → `prix_max`, ou error bars |
| « Top 10 / Flop 10 par région/carburant » | `fuelflow_gold.agg_classement_stations` | Tableau filtré sur `rang_moins_cher_region <= 10` |

## 1) Créer les sources de données (BigQuery)

1. <https://lookerstudio.google.com> → **Create** → **Data source** → connecteur **BigQuery**.
2. Project : `fuelflow-498320` → Dataset : `fuelflow_gold` → Tables :
   - `agg_dernier_prix_station_carburant`
   - `agg_prix_region_carburant`
   - `agg_classement_stations`
3. **Data freshness** : 1 hour (cohérent avec la cadence d'ingestion L6).
4. **Credentials** : **Owner's credentials**. ⚠️ Sans ça, un visiteur anonyme ne pourra rien voir.
5. Ajuster les types des colonnes géo :
   - Sur `agg_dernier_prix_station_carburant` : créer un champ calculé
     `geo` = `CONCAT(latitude, ", ", longitude)` typé **« Latitude, Longitude »**.

## 2) Créer le rapport

- **Create** → **Report** → ajouter les 3 sources.
- Définir un **filtre global carburant** (Gazole par défaut) : Add a control → Drop-down list → `carburant_nom`.

### Visuel 1 — Carte des stations (question 2, **hero**)

- Chart : **Bubble map**.
- Data source : `agg_dernier_prix_station_carburant`.
- Geo dimension : champ calculé `geo`.
- Bubble color : `prix_euro` (gradient vert → rouge).
- Bubble size : `prix_euro` (ou constante si la lecture devient confuse).
- Filtre carburant connecté au control global.

### Visuel 2 — Classement régional (question 1)

Si la carte choroplèthe FR fonctionne (peu probable d'office) :
- Chart : **Filled map** → geo `region_nom`, geo type **Region**, country **France**.
- Color metric : `prix_moyen`.

Sinon (fallback fiable) :
- Chart : **Bar chart trié**.
- Dimension : `region_nom`.
- Metric : `prix_moyen`.
- Sort : ascending (régions les moins chères en haut).

### Visuel 3 — Dispersion (question 3)

- Chart : **Bar chart** combiné min/max sur `prix_min` et `prix_max` par région.
- Optionnel : ajouter `prix_ecart_type` en tooltip.

### Visuel 4 — Top 10 stations (question 2 — drill-down)

- Chart : **Table**.
- Source : `agg_classement_stations`.
- Filtre : `rang_moins_cher_region <= 10`, optionnellement filtré par région via control.
- Colonnes : `region_nom`, `ville`, `station_id`, `prix_euro`, `rang_moins_cher_region`, `ecart_prix_vs_moyenne_region`.

### Scorecards globaux (en-tête)

- Prix moyen national = `AVG(prix_euro)` depuis `agg_dernier_prix_station_carburant` (filtré par carburant via control).
- Nombre de stations = `COUNT_DISTINCT(station_sk)`.
- Écart national = `MAX(prix_euro) - MIN(prix_euro)`.

## 3) Partager publiquement

- **Share** (bouton en haut à droite) → **Manage access** → **Anyone with the link** → **Viewer**.
- Copier l'URL → la coller dans le README racine (section « Démo »).

## 4) Hygiène

- Renommer le rapport : `FuelFlow — prix carburants en France (live)`.
- Ajouter un texte d'intro : 3 phrases sur la source open data + cadence horaire.
- Mettre un footer : « Données : donnees.roulez-eco.fr — pipeline FuelFlow, mis à jour toutes les heures depuis Cloud Run Job ».

## 5) Anti-patterns connus

- **Ne pas s'acharner sur la choroplèthe régionale FR** : la résolution geo de Looker Studio pour les régions françaises est instable. Bar chart classé > choroplèthe cassée.
- **Ne pas exposer `fct_prix_carburant` directement** : la table est large (~38 k lignes mais à grain événementiel). Le mart `agg_dernier_prix_station_carburant` est la bonne porte d'entrée — un visiteur n'a pas à voir les doublons d'événements.
- **Ne pas oublier de passer en Owner's credentials** : sinon le rapport public renvoie 403 aux visiteurs non authentifiés sur GCP.

## 6) Vérification

- Ouvrir le lien partagé dans **un navigateur en navigation privée non connecté à Google** → les 4 visuels doivent rendre sans login.
- Vérifier qu'un changement de filtre carburant met à jour la carte + le top 10.
- Vérifier la fraîcheur du libellé « dernière mise à jour » dans le footer (= `maj_timestamp_utc` max).
