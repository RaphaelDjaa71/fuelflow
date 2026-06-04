{{ config(materialized='ephemeral') }}

{#
  Resolves the 4 foreign keys consumed by the L5 fact (fct_prix_carburant):
    station_sk      — md5(station_id)
    carburant_sk    — md5(carburant_id)
    localisation_sk — md5(cp, ville)
    date_sk         — YYYYMMDD as INT, derived from the *Europe/Paris*
                      calendar date of maj_timestamp_utc.

  Why date_sk is Paris-based, not UTC-based:
    The business calendar is Paris time. A price posted at 00:30 Paris
    (= 22:30 UTC the day before in summer / 23:30 UTC in winter) belongs
    to the Paris day, not the UTC day. Using UTC would smear evening
    prices into the previous business day and break "prix du jour"
    analytics.
#}

with src as (
    select * from {{ ref('stg_prix') }}
),

with_local_date as (
    select
        *,
        {% if target.type == 'bigquery' %}
        date(maj_timestamp_utc, '{{ var("source_timezone") }}') as maj_date_paris
        {% elif target.type == 'snowflake' %}
        to_date(convert_timezone('UTC', '{{ var("source_timezone") }}', maj_timestamp_utc)) as maj_date_paris
        {% endif %}
    from src
)

select
    prix_sk,
    {{ dbt_utils.generate_surrogate_key(['station_id']) }} as station_sk,
    {{ dbt_utils.generate_surrogate_key(['carburant_id']) }} as carburant_sk,
    {{ dbt_utils.generate_surrogate_key(['cp', 'ville']) }} as localisation_sk,
    {% if target.type == 'bigquery' %}
    cast(format_date('%Y%m%d', maj_date_paris) as int64) as date_sk,
    {% elif target.type == 'snowflake' %}
    cast(to_char(maj_date_paris, 'YYYYMMDD') as integer) as date_sk,
    {% endif %}
    maj_date_paris,
    maj_timestamp_utc,
    prix_euro,
    ingestion_ts,
    source_url
from with_local_date
