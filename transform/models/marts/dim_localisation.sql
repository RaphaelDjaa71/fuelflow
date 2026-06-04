{{ config(materialized='table') }}

{#
  Grain: one row per (cp, ville) seen in stg_prix.

  dept_code derivation from cp (no geocoding, ADR L4 — out of scope):
    - 5-char cp starting with '97' or '98' -> overseas (DOM), take left 3
      (971 Guadeloupe, 972 Martinique, 973 Guyane, 974 La Réunion,
       976 Mayotte). 98xxx codes are New Caledonia / Polynesia which are
      not in the seed; they will fail the relationships test if any
      station ships them, which is the wanted alert.
    - 5-char cp starting with '20' (Corsica): split lexicographically.
      cp in '20000'..'20199' -> '2A' (Corse-du-Sud, Ajaccio area),
      cp >= '20200'         -> '2B' (Haute-Corse, Bastia area).
      Limitation: a postal code can straddle the border in rare cases.
      Documented imperfection (ADR L4 known limitation).
    - otherwise -> left(cp, 2).
    - null/empty cp -> dept_code null (relationships test ignores nulls).
#}

with distinct_pairs as (
    select distinct
        cp,
        ville
    from {{ ref('stg_prix') }}
),

derived as (
    select
        cp,
        ville,
        case
            when cp is null or length(cp) = 0 then cast(null as {{ dbt.type_string() }})
            when length(cp) = 5 and substr(cp, 1, 2) in ('97', '98') then substr(cp, 1, 3)
            when length(cp) = 5 and substr(cp, 1, 2) = '20'
                then case when cp < '20200' then '2A' else '2B' end
            when length(cp) >= 2 then substr(cp, 1, 2)
            else cast(null as {{ dbt.type_string() }})
        end as dept_code
    from distinct_pairs
)

select
    {{ dbt_utils.generate_surrogate_key(['cp', 'ville']) }} as localisation_sk,
    d.cp,
    d.ville,
    d.dept_code,
    s.dept_nom,
    s.region_nom
from derived d
left join {{ ref('seed_departement') }} s
    on d.dept_code = s.dept_code
