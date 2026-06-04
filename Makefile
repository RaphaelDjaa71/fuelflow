.PHONY: setup lint format test diagram clean ingest-local ingest-gcs audit-source \
        dbt-deps dbt-debug dbt-bq dbt-sf dbt-freshness-bq dbt-docs-bq

setup:
	uv sync
	uv run pre-commit install

lint:
	uv run ruff check .

format:
	uv run ruff format .

test:
	uv run pytest -q

ingest-local:
	PYTHONPATH=ingestion uv run python -m fuelflow_ingest.cli --local-only

ingest-gcs:
	set -a && . ./.env && set +a && PYTHONPATH=ingestion uv run python -m fuelflow_ingest.cli

audit-source:
	uv run python ingestion/scripts/inspect_source.py

# --- dbt (transform/) ---
# DBT_PROFILES_DIR points at transform/ so dbt picks up transform/profiles.yml
# (gitignored) instead of the global ~/.dbt/profiles.yml.

dbt-deps:
	cd transform && DBT_PROFILES_DIR=. uv run dbt deps

dbt-debug:
	cd transform && DBT_PROFILES_DIR=. uv run dbt debug --target $(or $(T),bigquery)

dbt-bq:
	cd transform && DBT_PROFILES_DIR=. uv run dbt build --target bigquery

dbt-sf:
	cd transform && DBT_PROFILES_DIR=. uv run dbt build --target snowflake

dbt-freshness-bq:
	cd transform && DBT_PROFILES_DIR=. uv run dbt source freshness --target bigquery

dbt-docs-bq:
	cd transform && DBT_PROFILES_DIR=. uv run dbt docs generate --target bigquery

dbt-lineage:
	npx -y @mermaid-js/mermaid-cli -i docs/architecture/dbt-lineage.mmd -o docs/architecture/dbt-lineage.png -b transparent

diagram:
	npx -y @mermaid-js/mermaid-cli -i docs/architecture/fuelflow-architecture.mmd -o docs/architecture/fuelflow-architecture.png -b transparent

clean:
	rm -rf .ruff_cache .pytest_cache data/
