# ingestion/

**Lot responsable :** L1 — ingestion Python.

**Statut :** non démarré.

Contenu attendu :
- Worker Python qui télécharge le flux XML-ZIP de `donnees.roulez-eco.fr`,
  parse en Parquet typé, dépose sur GCS bronze (`gs://<bucket>/raw/`).
- Logique d'idempotence et de retry.
- Logging structuré (JSON).
- Dockerfile pour Cloud Run Job (déploiement en L6).
- Tests unitaires dans `../tests/`.

Spec de référence : ADR 0004, ADR 0005, ADR 0006 dans `docs/adr/`.
