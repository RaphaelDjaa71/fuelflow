# ADR 0005 — Architecture médaillon, bronze sur GCS

## Statut
Accepté — 2026-06-03

## Contexte
On doit décider :
1. Quelle architecture de transformation (one-layer SQL direct, lakehouse,
   médaillon Bronze/Silver/Gold, autre).
2. Où poser le bronze (GCS, Snowflake stage, BigQuery raw dataset, S3).
3. Quel format de fichier (XML brut conservé, Parquet, JSON,
   directement table warehouse).

Contraintes :
- Le format source XML peut changer (source publique, hors notre
  contrôle). Si on ne conserve pas l'XML brut, une régression sur le
  parser est **non rejouable**.
- Le dual-target Snowflake/BigQuery (ADR 0002) impose un bronze
  **agnostique du warehouse** — sinon on double le coût de stockage.
- GCS est natif au compte GCP du projet, intégré aux deux warehouses
  via external tables / external stages.

## Décision
On adopte l'**architecture médaillon** :
- **Bronze** = GCS bucket `gs://<project>-bronze/raw/...`, deux formats
  cohabitent par ingestion :
  - `xml/dt=YYYY-MM-DD/hh=HH/instantane.xml` — **XML brut intact**,
    rejouable, traçable.
  - `parquet/dt=YYYY-MM-DD/hh=HH/prix.parquet` — **Parquet typé** issu du
    parsing, prêt à charger en warehouse sans re-parse XML.
- **Silver** = vues / tables nettoyées dans chaque warehouse
  (snowflake.fuelflow_silver, bigquery.fuelflow_silver). Clés typées,
  doublons éliminés, joinables.
- **Gold** = star schema (cf. ADR 0006, `docs/data-model/star-schema.md`).

**Partitionnement bronze** : par **date d'ingestion** (`dt=YYYY-MM-DD`)
et heure (`hh=HH`). Pas par date métier — la cohérence rejouable est sur
la date d'ingestion.

**Idempotence** : le worker calcule un nom de fichier déterministe
(`instantane-<run_ts>.xml`), upload avec `if_generation_match=0` pour
ne pas écraser. Un run rejoué sur la même tranche horaire écrit un
sibling, pas un overwrite.

## Conséquences
**Positives :**
- Rejouabilité totale : si le parser casse en V2, on re-parse depuis
  l'XML brut sans re-télécharger le flux (qui pourrait avoir bougé).
- Découplage warehouse / stockage. Migrer Snowflake → autre warehouse
  n'impacte pas la couche bronze.
- Coût GCS ≈ négligeable au volume FuelFlow (~5 Go/mois bronze
  total).

**Négatives :**
- **Stockage doublé** (XML brut + Parquet). Acceptable au volume cible.
  Une lifecycle policy GCS (transition vers `NEARLINE` après 30 j,
  `COLDLINE` après 90 j) sera ajoutée en L2.
- Charge cognitive supplémentaire : il faut savoir si une régression
  vient du parse (réparable depuis XML) ou de la source (non
  réparable).
- Coût opérationnel : deux jobs de chargement bronze → silver
  (Snowflake + BigQuery). Mitigé par le fait que les deux pointent
  vers les **mêmes fichiers Parquet** via external table.
