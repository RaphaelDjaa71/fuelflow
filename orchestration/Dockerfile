FROM python:3.12-slim

# uv: deterministic, fast dep resolver. We copy a pinned uv binary out of
# the official image so the build is reproducible (no `pip install uv`
# from the public index).
COPY --from=ghcr.io/astral-sh/uv:0.5.11 /uv /usr/local/bin/uv

WORKDIR /app

# Install runtime deps only (no dev group -> excludes dbt, pytest, ruff,
# pre-commit, snowflake-connector-python). The lockfile is committed and
# `--frozen` forbids resolver drift; `--no-install-project` skips
# installing this repo as a package (we set PYTHONPATH instead because
# [tool.uv] package = false).
COPY pyproject.toml uv.lock ./
RUN uv sync --no-dev --frozen --no-install-project

# Worker code only. Anything outside ingestion/ is ignored via
# .dockerignore at the build context (.env, .secrets/, transform/, docs/,
# data/, etc.).
COPY ingestion/ ./ingestion/

ENV PATH="/app/.venv/bin:${PATH}" \
    PYTHONPATH="/app/ingestion" \
    PYTHONUNBUFFERED=1

# Cloud Run Job entrypoint: no --local-only flag means the worker
# authenticates to GCS via the attached service account (ADC), reads
# GCS_BRONZE_BUCKET from env, and writes to the real bucket.
ENTRYPOINT ["python", "-m", "fuelflow_ingest.cli"]
