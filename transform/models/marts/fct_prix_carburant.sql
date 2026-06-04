{{ config(
    materialized='incremental',
    unique_key='prix_sk',
    incremental_strategy='merge',
    on_schema_change='fail',
    contract={'enforced': true}
) }}

{#
  Atomic fact table at the (station, fuel, source maj_timestamp) grain.
  Sourced from int_prix_keyed (ephemeral) which already resolved the
  four foreign keys and the Paris-day date_sk.

  Every cast is explicit and chosen to match the data_type declared in
  the contract (see marts/_models.yml). The enforced contract verifies
  the SELECT output schema against the YAML schema before materializing:
  a casting mistake fails the build rather than silently corrupting the
  warehouse.

  Why the casts matter on each warehouse:
    - prix_euro: NUMERIC(10,3) on both — money is decimal, not float.
      BigQuery's NUMERIC is a fixed 38,9; we still cast explicitly so
      the contract picks up the precise type rather than the upstream
      Float64 inferred from Parquet.
    - maj_timestamp_utc: TIMESTAMP (BQ has implicit UTC) vs
      TIMESTAMP_TZ (Snowflake) — both store a UTC instant.
    - date_sk: INT64 on BigQuery, NUMBER on Snowflake (38,0 default).
    - ingestion_date: DATE on both, derived from ingestion_ts.
#}

{%- if is_incremental() -%}
    {%- set max_ingestion_ts_query -%}
        select coalesce(max(ingestion_ts), cast('1900-01-01' as {{ dbt.type_timestamp() }})) from {{ this }}
    {%- endset -%}
    {%- set max_ingestion_ts_result = run_query(max_ingestion_ts_query) -%}
    {%- if execute -%}
        {%- set max_ingestion_ts = max_ingestion_ts_result.columns[0].values()[0] -%}
    {%- else -%}
        {%- set max_ingestion_ts = '1900-01-01 00:00:00' -%}
    {%- endif -%}
{%- endif -%}

with src as (
    select * from {{ ref('int_prix_keyed') }}
    {# Strict watermark: only rows captured *after* the last
       ingestion_ts already in the fact are reprocessed. The literal
       is resolved at compile time via run_query so the WHERE clause
       stays uncorrelated (Snowflake refuses correlated aggregates in
       WHERE). incremental_strategy=merge on unique_key=prix_sk is the
       second line of defense — silver-layer dedup already enforces
       natural-key uniqueness. #}
    {% if is_incremental() %}
        where ingestion_ts > cast('{{ max_ingestion_ts }}' as {{ dbt.type_timestamp() }})
    {% endif %}
)

select
    cast(prix_sk as {{ dbt.type_string() }}) as prix_sk,
    cast(station_sk as {{ dbt.type_string() }}) as station_sk,
    cast(carburant_sk as {{ dbt.type_string() }}) as carburant_sk,
    cast(date_sk as {{ dbt.type_int() }}) as date_sk,
    cast(localisation_sk as {{ dbt.type_string() }}) as localisation_sk,
    {% if target.type == 'bigquery' %}
    cast(prix_euro as numeric) as prix_euro,
    cast(maj_timestamp_utc as timestamp) as maj_timestamp_utc,
    cast(ingestion_ts as timestamp) as ingestion_ts,
    cast(date(ingestion_ts) as date) as ingestion_date
    {% elif target.type == 'snowflake' %}
    cast(prix_euro as number(10,3)) as prix_euro,
    {# Keep TIMESTAMP_NTZ on Snowflake. Casting NTZ to TIMESTAMP_TZ
       reads the session TIMEZONE and silently shifts the wall clock
       by hours when the session is not UTC. The whole project's
       convention (ADR 0006 and L4 silver schema) is that all
       *_utc columns store UTC instants in TIMESTAMP_NTZ; this keeps
       the gold layer consistent with that. #}
    cast(maj_timestamp_utc as timestamp_ntz) as maj_timestamp_utc,
    cast(ingestion_ts as timestamp_ntz) as ingestion_ts,
    cast(to_date(ingestion_ts) as date) as ingestion_date
    {% endif %}
from src
