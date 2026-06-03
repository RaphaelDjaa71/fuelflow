# infra/

**Lot responsable :** L2 — provisionnement des ressources cloud.

**Statut :** non démarré.

Contenu attendu :
- Création du **bucket GCS bronze** (`gs://<project>-bronze/`,
  lifecycle policy NEARLINE 30 j / COLDLINE 90 j).
- Création des **datasets BigQuery** `fuelflow_silver` et `fuelflow_gold`.
- Création de la **base Snowflake** `FUELFLOW` + warehouse `FUELFLOW_WH`
  (XS, `AUTO_SUSPEND = 60`, `AUTO_RESUME = TRUE`).
- Création des **service accounts** GCP (un pour Cloud Run, un pour CI)
  avec rôles minimaux.
- Documentation des **secrets** à stocker dans GitHub Actions Secrets
  et dans Secret Manager GCP.

Spec de référence : ADR 0002 (garde-fou coût Snowflake) + ADR 0005.

**Choix outil de provisionnement** : à trancher en L2 entre
`gcloud` scripts vs Terraform vs Pulumi. Default proposé = scripts
`gcloud` + SQL Snowflake (suffisant au volume portfolio, lisible
sans setup Terraform).
