{{ config(materialized='table') }}

select
    {{ dbt_utils.generate_surrogate_key(['carburant_id']) }} as carburant_sk,
    carburant_id,
    carburant_nom,
    carburant_libelle_long
from {{ ref('seed_carburant') }}
