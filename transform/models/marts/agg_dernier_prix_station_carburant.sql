{{ config(materialized='table') }}

{#
  Question 2: "Quelles stations sont les moins chères, et où ?"
  Grain: one row per (station, fuel) carrying the most recent price
  the source published for that station+fuel. This is the table that
  feeds the bubble map of the Looker Studio dashboard.

  We pick the latest maj_timestamp_utc per (station, carburant) — not
  the latest ingestion_ts — because business latency follows the
  source's own update clock. Two ingest runs that capture the same
  maj_timestamp produce the same "latest price"; only a station
  actively publishing a new price advances the row.
#}

with ranked as (
    select
        f.station_sk,
        f.carburant_sk,
        f.localisation_sk,
        f.prix_euro,
        f.maj_timestamp_utc,
        row_number() over (
            partition by f.station_sk, f.carburant_sk
            order by f.maj_timestamp_utc desc
        ) as _row_num
    from {{ ref('fct_prix_carburant') }} f
)

select
    r.station_sk,
    r.carburant_sk,
    c.carburant_id,
    c.carburant_nom,
    r.prix_euro,
    r.maj_timestamp_utc,
    s.station_id,
    s.latitude,
    s.longitude,
    s.cp,
    s.ville,
    l.dept_code,
    l.dept_nom,
    l.region_nom
from ranked r
join {{ ref('dim_station') }} s on s.station_sk = r.station_sk
join {{ ref('dim_carburant') }} c on c.carburant_sk = r.carburant_sk
left join {{ ref('dim_localisation') }} l on l.localisation_sk = r.localisation_sk
where r._row_num = 1
