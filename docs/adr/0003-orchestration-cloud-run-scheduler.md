# ADR 0003 — Orchestration Cloud Run Job + Cloud Scheduler

## Statut
Accepté — 2026-06-03

## Contexte
L'ingestion FuelFlow télécharge un flux XML-ZIP toutes les heures
(cf. ADR 0004), le transforme en Parquet typé et le dépose sur GCS. Il
faut donc un déclencheur planifié, capable d'exécuter un container
Python court (~30-60 s par run), idempotent, observable, gratuit ou
quasi-gratuit en idle.

Alternatives évaluées :

| Option | Coût idle | Complexité | Verdict |
|---|---|---|---|
| **Cloud Composer (Airflow managé GCP)** | ~400 €/mois minimum (GKE permanent) | Élevée | **Écarté** — pas de free tier, sur-dimensionné pour 1 DAG |
| **Airflow self-hosted (VM/Docker)** | VM permanente facturée | Moyenne | Écarté — over-engineering portfolio + maintenance |
| **Cloud Functions + Scheduler** | Gratuit en idle | Faible | Limité à 9 min d'exec, payload XML pourrait poser souci |
| **Cloud Run Job + Cloud Scheduler** | **Gratuit en idle** (pas de min instances) | Faible | **Retenu** |
| **Dagster Cloud** | Plan dev gratuit limité | Moyenne | Bon outil mais hors scope CV cible |

## Décision
On utilise **Cloud Run Job** (job = exécution courte one-shot, pas
service), déclenché par **Cloud Scheduler** (cron HTTP) toutes les
heures. Le code Python d'ingestion vit dans `ingestion/`, est packagé en
image Docker, et déployé via `gcloud run jobs deploy`.

Une fonction Cloud Function `trigger-fuelflow-ingest` (Gen2) peut être
ajoutée comme couche d'invocation HTTP authentifiée, mais le chemin
direct **Scheduler → Cloud Run Job (via OIDC)** est préféré pour
simplicité.

L'orchestration ne pilote pas dbt : `dbt build` tourne en **GitHub
Actions** sur la CI (target BigQuery) et en local pour Snowflake. Aucun
besoin d'Airflow tant qu'il n'y a qu'un seul DAG de fait.

### Note de compétence séparée
Un DAG Airflow équivalent (local, docker-compose) peut être livré dans
`orchestration/airflow-demo/` en **artefact de compétence**
indépendant — pas en production. Cela montre la maîtrise Airflow sans
en payer le coût opérationnel.

## Conséquences
**Positives :**
- Coût idle = 0 €. Coût horaire négligeable (~quelques centimes/mois).
- Simplicité : un container + un cron. Démontre la doctrine
  "pas d'Airflow par défaut" — signal de maturité.
- Logs Cloud Run + Cloud Logging suffisent pour l'observabilité au stade
  portfolio.

**Négatives :**
- Pas de **DAG visuel** (Airflow UI) à montrer. Le case study devra
  l'expliquer ; le diagramme Mermaid en `docs/architecture/` y répond
  partiellement.
- Si le projet évolue vers plusieurs DAGs interdépendants, il faudra
  migrer (Composer, Dagster ou Airflow self-hosted). Le coût de
  migration est faible — un seul job actuellement.
- Retries / alerting à configurer manuellement (Cloud Scheduler retry
  policy + Cloud Logging alert policy).
