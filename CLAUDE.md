# FuelFlow — instructions pour Claude Code

## Doctrine (non négociable)
- **Un seul sub-agent à la fois** — jamais d'orchestration parallèle.
- **Audit du schéma réel avant d'écrire du code/SQL** — inspecter la vraie
  donnée, pas supposer. Si la source ne peut pas être interrogée, le dire
  explicitement et marquer l'hypothèse à confirmer.
- **Vérification visuelle finale obligatoire** (Lesson 10) — sans preuve
  (output, run réel, render d'image, df.head), un lot n'est PAS livré.
- **Pas de scope creep** : pas de ML, pas de notebook d'exploration,
  rien hors spec sans décision conjointe avec l'utilisateur.
- Code / commits / modèles dbt / tests en **anglais** ; ADR / README /
  case study / docs en **français**.
- Pas de dépendance ajoutée sans justification dans le commit.

## Convention git
- Tag forensique **avant chaque lot** : `forensic/L{N}-pre-{slug}`.
- Commits atomiques, messages en anglais, sujet ≤ 70 chars.
- Pas de force-push sur `main`. Pas de merge sans CI verte (à partir de L7).
- Ne jamais commiter `.env`, clé service-account, dump Parquet/XML.

## Doctrine d'exécution Claude Code
- Pre-commit utilise un `git` récent (>= 2.30). Sur cette machine,
  préfixer `PATH=/opt/homebrew/bin:$PATH` aux invocations qui invoquent
  pre-commit/git-fetch — le `/usr/local/bin/git` système est en 2.14.
- `shell cwd` est reset entre commandes ; toujours utiliser des
  **chemins absolus** sous `/Users/toji/fuelflow/`.

## Décisions clés (voir docs/adr/)
- **Warehouses dual-target** Snowflake (principal, headline CV) +
  BigQuery (démo live durable + CI). dbt portable, types abstraits dans
  les contracts (ADR 0002).
- **Orchestration** Cloud Run Job + Cloud Scheduler (PAS Airflow en
  prod). DAG Airflow local = artefact de compétence séparé (ADR 0003).
- **Ingestion** micro-batch HORAIRE, incrémentale + idempotente sur
  grain 10 min. Prête pour 10 min = changer le cron. **Jamais
  "temps réel"** (ADR 0004).
- **Médaillon** : bronze sur GCS (XML brut + Parquet typé, partitionné
  par date d'ingestion). Silver/gold dans chaque warehouse (ADR 0005).
- **Grain du fait** : `(station, carburant, maj_timestamp)`. Clé
  surrogate = `md5(station_id||'|'||carburant_id||'|'||maj_timestamp)`
  (ADR 0006).
- **Data contracts** : `dbt-contracts: enforced: true` sur le gold,
  freshness checks, fail bloquant en CI (ADR 0007).

## Source de vérité pour le modèle de données
`docs/data-model/star-schema.md`. Toute divergence entre ce document
et du code dbt doit être tranchée dans ce fichier **avant** d'éditer
le SQL.

## Avancement
Voir la table d'avancement dans `README.md` § 7.
