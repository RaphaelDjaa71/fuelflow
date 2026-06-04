{{ config(materialized='table') }}

{#
  Grain: one row per station_id (SCD type 1 — overwrite).

  Justification (ADR 0006): in this open data set, a station rarely
  changes address or markings, and when it does the new attributes are
  more useful for current analytics than the historical ones. We keep
  the most recent attributes by picking the row with the latest
  ingestion_ts per station_id.

  localisation_sk uses the same surrogate-key recipe as dim_localisation
  so a join from this dim to dim_localisation is exact (md5 of the same
  (cp, ville) pair on both sides).
#}

with ranked as (
    select
        station_id,
        cp,
        ville,
        adresse,
        pop,
        latitude,
        longitude,
        row_number() over (
            partition by station_id
            order by ingestion_ts desc
        ) as _row_num
    from {{ ref('stg_prix') }}
)

select
    {{ dbt_utils.generate_surrogate_key(['station_id']) }} as station_sk,
    {{ dbt_utils.generate_surrogate_key(['cp', 'ville']) }} as localisation_sk,
    station_id,
    cp,
    ville,
    adresse,
    pop,
    latitude,
    longitude
from ranked
where _row_num = 1
