# orchestration/

**Lot responsable :** L6 — Cloud Run Job + Cloud Scheduler.

**Statut :** non démarré.

Contenu attendu :
- Script de déploiement de l'image d'ingestion en Cloud Run Job
  (`gcloud run jobs deploy ...`).
- Définition Cloud Scheduler (cron `0 * * * *`, target Cloud Run Job
  via OIDC).
- Politiques de retry et d'alerting (Cloud Logging alert policy).
- Optionnel : un DAG Airflow équivalent dans `airflow-demo/` comme
  **artefact de compétence** (pas en production).

Spec de référence : ADR 0003 + ADR 0004.
