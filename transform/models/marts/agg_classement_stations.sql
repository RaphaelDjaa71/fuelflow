{{ config(materialized='table') }}

{#
  Question 2 (drill-down): "Quelles stations sont les moins chères pour
  chaque carburant, par région ?" → ranked list with the gap to the
  regional average so the dashboard can immediately surface relative
  bargains.

  RANK() (not ROW_NUMBER) handles ties — two stations posting the same
  price share the same rank. This matters for fuels with discrete
  rounding (multi-station promotions at identical prices).
#}

with derniers as (
    select
        d.station_sk,
        d.station_id,
        d.carburant_nom,
        d.carburant_id,
        d.region_nom,
        d.dept_nom,
        d.dept_code,
        d.ville,
        d.cp,
        d.latitude,
        d.longitude,
        d.prix_euro,
        d.maj_timestamp_utc
    from {{ ref('agg_dernier_prix_station_carburant') }} d
    where d.region_nom is not null
)

select
    d.station_sk,
    d.station_id,
    d.carburant_id,
    d.carburant_nom,
    d.region_nom,
    d.dept_nom,
    d.dept_code,
    d.ville,
    d.cp,
    d.latitude,
    d.longitude,
    d.prix_euro,
    d.maj_timestamp_utc,
    rank() over (
        partition by d.region_nom, d.carburant_nom
        order by d.prix_euro asc
    ) as rang_moins_cher_region,
    rank() over (
        partition by d.region_nom, d.carburant_nom
        order by d.prix_euro desc
    ) as rang_plus_cher_region,
    cast(
        d.prix_euro - a.prix_moyen
        as {{ dbt.type_numeric() }}
    ) as ecart_prix_vs_moyenne_region
from derniers d
join {{ ref('agg_prix_region_carburant') }} a
    on a.region_nom = d.region_nom and a.carburant_nom = d.carburant_nom
