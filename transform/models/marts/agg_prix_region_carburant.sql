{{ config(materialized='table') }}

{#
  Questions 1 & 3:
    1. "Où le carburant est-il le moins cher en France ?" → prix_moyen
       and ranking by (region, carburant).
    2. "Quelle dispersion des prix par région/carburant ?" → stddev,
       min/max, p25/p50/p75.

  The aggregation runs over the latest price per station+fuel (not the
  full fact history) so that a station whose prix is unchanged for
  6 months doesn't get reweighted by the number of times it appeared in
  the source feed.

  Percentile approximation is target-aware:
    - BigQuery: APPROX_QUANTILES splits into 100 buckets and returns
      the offset boundaries; OFFSET(N) is the value at percentile N.
    - Snowflake: APPROX_PERCENTILE takes the fraction directly.
  Both are *approximate*; small divergences between BQ and SF on the
  three percentile columns are expected and documented.
#}

select
    region_nom,
    carburant_nom,
    count(*) as count_stations,
    cast(avg(prix_euro) as {{ dbt.type_numeric() }}) as prix_moyen,
    min(prix_euro) as prix_min,
    max(prix_euro) as prix_max,
    cast(stddev(prix_euro) as {{ dbt.type_numeric() }}) as prix_ecart_type,

    {% if target.type == 'bigquery' %}
    cast(approx_quantiles(prix_euro, 100)[offset(25)] as {{ dbt.type_numeric() }}) as prix_p25_approx,
    cast(approx_quantiles(prix_euro, 100)[offset(50)] as {{ dbt.type_numeric() }}) as prix_median_approx,
    cast(approx_quantiles(prix_euro, 100)[offset(75)] as {{ dbt.type_numeric() }}) as prix_p75_approx
    {% elif target.type == 'snowflake' %}
    cast(approx_percentile(prix_euro, 0.25) as {{ dbt.type_numeric() }}) as prix_p25_approx,
    cast(approx_percentile(prix_euro, 0.50) as {{ dbt.type_numeric() }}) as prix_median_approx,
    cast(approx_percentile(prix_euro, 0.75) as {{ dbt.type_numeric() }}) as prix_p75_approx
    {% endif %}

from {{ ref('agg_dernier_prix_station_carburant') }}
where region_nom is not null
group by region_nom, carburant_nom
