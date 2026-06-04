# orchestration/

**Lot responsable :** L6 — Cloud Run Job + Cloud Scheduler.

**Statut L6 :** ✅ Image construite, déployée, exécutée depuis le cloud,
idempotence prouvée, scheduler horaire actif (cron `0 * * * *` Europe/Paris).

## Vue d'ensemble

```
┌───────────────────────┐    cron 0 * * * *
│   Cloud Scheduler     │ ─────────────────────┐
│ fuelflow-ingest-hourly│                       │
│ tz = Europe/Paris     │                       ▼
└───────────────────────┘             ┌──────────────────────┐
                                       │   Cloud Run Job     │
                                       │  fuelflow-ingest    │
                                       │  SA = fuelflow-ingest│
                                       │  image = AR latest   │
                                       └──────────────────────┘
                                                  │
                                                  ▼
                                       gs://fuelflow-498320-bronze/bronze/
                                         ├ raw_xml/dt=…/hh=…/instantane.xml.zip
                                         └ parquet/dt=…/hh=…/prix.parquet
```

Le pipeline est désormais **autonome** : sans intervention humaine, une
nouvelle partition horaire de bronze atterrit dans GCS toutes les heures
sur le calendrier de Paris.

## Modèle d'authentification

| Composant | Identité | Pouvoirs nécessaires |
|---|---|---|
| Cloud Run Job (runtime) | SA `fuelflow-ingest@…` | `roles/storage.objectAdmin` sur le bucket bronze (L2) |
| Cloud Scheduler → Run Job | même SA, en tant qu'OAuth invoker | `roles/run.invoker` sur le job (script 04) |
| Worker → GCS | ADC fourni par le metadata server Cloud Run | aucune clé montée |

**Aucun secret / `.env` / `.secrets/` n'est embarqué dans l'image** : la
sécurité repose entièrement sur l'identité du service account attaché
au job. La preuve est vérifiable côté GCP (`gcloud run jobs describe`
montre les variables d'env, qui ne contiennent que la config, jamais
de credentials).

> Sur un projet multi-équipe, on séparerait Scheduler-SA et Runtime-SA.
> Pour ce portfolio solo le runtime-SA est aussi l'invoker scheduler
> (documenté ici).

## Sécurité du build context

Le contexte de build Cloud Build est filtré par **`.gcloudignore`** (à
la racine du repo), miroir du `.dockerignore`. Les chemins suivants
n'atteignent **jamais** les workers de Google :

- `.env`, `*.env` (toutes les variantes), `.secrets/`
- `gcp-key*.json`, `*service-account*.json`
- `transform/`, `docs/`, `infra/`, `tests/`, `target/`, `dbt_packages/`,
  `data/`, `.venv/`, `.git/`

Vérifié empiriquement : le tarball envoyé fait ~120 Ko (16 fichiers,
383 KiB avant compression), exclusivement le worker + lockfile.

## Ordre d'exécution des scripts (idempotents, sûrs à rejouer)

```bash
cd ~/fuelflow
set -a && . ./.env && set +a

bash orchestration/01_artifact_registry.sh   # APIs + AR repo `fuelflow`
bash orchestration/02_build_push.sh          # Cloud Build -> image:latest + :sha-<git>
bash orchestration/03_deploy_job.sh          # Cloud Run Job fuelflow-ingest
bash orchestration/04_scheduler.sh           # add-iam + create scheduler
```

## Vérifications post-déploiement

```bash
# Image présente dans Artifact Registry
gcloud artifacts docker images list \
  europe-west1-docker.pkg.dev/fuelflow-498320/fuelflow

# Cloud Run Job configuré
gcloud run jobs describe fuelflow-ingest --region=europe-west1

# Exécution unique à la demande (test)
gcloud run jobs execute fuelflow-ingest --region=europe-west1 --wait

# Forcer le scheduler
gcloud scheduler jobs run fuelflow-ingest-hourly --location=europe-west1

# Lister les exécutions Run
gcloud run jobs executions list --job=fuelflow-ingest --region=europe-west1
```

## Coût attendu

- **Cloud Run Jobs** : free tier 240 000 vCPU-secondes / mois. Une
  exécution prend ~6 s × 1 vCPU = 6 vCPU-s. 720 exécutions / mois =
  4 320 vCPU-s, **largement sous le free tier**.
- **Cloud Scheduler** : 3 jobs gratuits / mois / compte de facturation.
- **Cloud Build** : 120 min/jour gratuits (un build de l'image ≈ 50 s).
- **Artifact Registry** : 0,5 Go gratuit. L'image fait ~180 Mo
  compressé, **largement sous le free tier**.
- **GCS** bronze : ~1 Mo par exécution × 720 = ~700 Mo/mois, free tier
  5 Go.

Le budget GCP `fuelflow-guardrail` (5 EUR/mois, L2) sert de filet en
cas de dérive. Estimation réelle : 0 €/mois.

## Idempotence object-level — confirmée depuis le cloud

Le worker écrit avec `if_generation_match=0` côté GCS. Une seconde
exécution Cloud Run sur le même créneau horaire renvoie
`PreconditionFailed` qui est traduit en `WriteResult(skipped=True)`.
Vérifié end-to-end :

| Exécution | Slot | `skipped` raw_zip | `skipped` parquet |
|---|---|---|---|
| `fuelflow-ingest-jrpgz` (1ère cloud) | `dt=2026-06-04/hh=01` | False | False |
| `fuelflow-ingest-q9gcl` (replay) | `dt=2026-06-04/hh=01` | **True** | **True** |
| `fuelflow-ingest-27hmq` (scheduler) | `dt=2026-06-04/hh=01` | True | True |

> Note : les trois exécutions ci-dessus tombent dans le même créneau
> horaire parce qu'elles ont été lancées dans la même heure ; la
> deuxième et la troisième s'attendent à voir `skipped=True`, ce qui
> est exactement le comportement observé.

## Incrémental du fait — différé à L7

La conversion `fct_prix_carburant` → `materialized='incremental'`
(`unique_key='prix_sk'`, `merge`, watermark `ingestion_ts`) **nécessite
au moins 3 partitions distinctes** pour prouver visuellement le delta,
et au moins **une partition produite spontanément par le scheduler**
(pas par un déclenchement à la demande). Avec un cron horaire, deux
partitions naturelles supplémentaires arrivent au plus tard dans les
2 heures. La conversion sera faite à l'ouverture de L7, accompagnée
de la preuve "second build après nouvelle partition = seules les
lignes nouvelles traitées".

## Liens utiles

- Console Cloud Run Jobs : <https://console.cloud.google.com/run/jobs?project=fuelflow-498320>
- Console Scheduler : <https://console.cloud.google.com/cloudscheduler?project=fuelflow-498320>
- Console Artifact Registry : <https://console.cloud.google.com/artifacts?project=fuelflow-498320>
