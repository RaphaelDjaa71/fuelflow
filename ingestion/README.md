# ingestion/

**Lot responsable :** L1 — ingestion Python. **Statut : livré.**

## Ce que fait ce module

Worker Python qui télécharge le flux `donnees.roulez-eco.fr` (XML-ZIP
~1 Mo, ~10 000 stations, encodage ISO-8859-1), parse en respectant les
gotchas audités en L1 (coords ÷100000, prix déjà en euros décimaux,
mapping carburant 1=Gazole / 2=SP95 / 3=E85 / 4=GPLc / 5=E10 / 6=SP98),
produit un Parquet typé au grain `(station × carburant × maj)`, et
dépose à la fois le **ZIP brut** et le **Parquet** sur la couche bronze.

## Structure

```
ingestion/
├── fuelflow_ingest/      # package
│   ├── config.py         # IngestConfig (env vars + defaults)
│   ├── logging.py        # structlog JSON stdout
│   ├── download.py       # httpx + tenacity retry, ZIP extraction
│   ├── parse.py          # lxml -> Polars DataFrame typé
│   ├── storage.py        # GcsBronzeWriter + LocalBronzeWriter
│   └── cli.py            # orchestration : download -> parse -> write
├── scripts/
│   └── inspect_source.py # audit schéma jetable (L1, ne pas supprimer
│                         #   tant que la source n'est pas figée)
└── tests/                # fixtures + tests unitaires (pytest)
```

## Exécution locale

```bash
# Run réel contre la vraie source, sortie locale, AUCUN appel GCP
make ingest-local
# équivalent : PYTHONPATH=ingestion uv run python -m fuelflow_ingest.cli --local-only
```

Sortie : `data/bronze/bronze/raw_xml/dt=YYYY-MM-DD/hh=HH/instantane.xml.zip`
et `data/bronze/bronze/parquet/dt=YYYY-MM-DD/hh=HH/prix.parquet`.

Le dossier `data/` est dans `.gitignore`.

## Idempotence — précision importante

Le worker garantit l'idempotence **au niveau OBJET** : un re-run sur le
même créneau horaire n'écrit pas un second fichier. GCS le fait via
`if_generation_match=0` (un upload sur un objet existant lève
`PreconditionFailed`, le writer le traduit en `skipped=True`). Le writer
local fait pareil via `Path.exists()`.

L'idempotence **au niveau LIGNE** — déduplication sur
`(station_id, carburant_id, maj_timestamp)` — est gérée plus tard par
dbt aux couches silver (L4) et gold (L5), conformément à ADR 0006. Le
parquet bronze peut donc contenir des doublons logiques si deux runs
réussissent sur deux créneaux différents en récupérant le même
`<prix maj=...>` — c'est attendu, normal, et silencieusement traité en
silver via `unique_key = prix_sk`.

## Tests

```bash
make test
```

Couverture : parse (accents, coords, prix décimal, rupture ignorée,
station sans coord, drift schéma → erreur explicite), download (retry
503 → 200, persistant 503 → fail, ZIP extraction), storage
(`if_generation_match=0` côté GCS via mock, replay → `skipped=True`
côté local et GCS).
