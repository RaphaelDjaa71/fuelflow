{{
  config(
    materialized='view'
  )
}}

with source as (
    select * from {{ source('roulez_eco', 'ext_prix_bronze') }}
),

typed_and_utc as (
    select
        cast(station_id as {{ dbt.type_string() }}) as station_id,
        cast(cp as {{ dbt.type_string() }}) as cp,
        cast(ville as {{ dbt.type_string() }}) as ville,
        cast(adresse as {{ dbt.type_string() }}) as adresse,
        cast(pop as {{ dbt.type_string() }}) as pop,
        cast(latitude as {{ dbt.type_float() }}) as latitude,
        cast(longitude as {{ dbt.type_float() }}) as longitude,
        cast(carburant_id as {{ dbt.type_string() }}) as carburant_id,
        cast(carburant_nom as {{ dbt.type_string() }}) as carburant_nom,

        {# The source maj_timestamp is *clock time in Europe/Paris* but the
           Parquet column has no timezone. BigQuery imports it as TIMESTAMP-UTC
           (wrong), Snowflake as TIMESTAMP_NTZ (neutral). We strip whatever TZ
           BigQuery attached, then re-anchor the wall-clock to Europe/Paris,
           which yields the correct UTC instant on both warehouses. #}
        {% if target.type == 'bigquery' %}
        timestamp(datetime(maj_timestamp), '{{ var("source_timezone") }}') as maj_timestamp_utc,
        {% elif target.type == 'snowflake' %}
        convert_timezone('{{ var("source_timezone") }}', 'UTC', maj_timestamp) as maj_timestamp_utc,
        {% else %}
        {{ exceptions.raise_compiler_error("Unsupported target.type: " ~ target.type) }}
        {% endif %}

        cast(prix_euro as {{ dbt.type_numeric() }}) as prix_euro,
        cast(ingestion_ts as {{ dbt.type_timestamp() }}) as ingestion_ts,
        cast(source_url as {{ dbt.type_string() }}) as source_url

    from source
    where station_id is not null
      and carburant_id is not null
      and maj_timestamp is not null
      and prix_euro is not null
),

ranked as (
    select
        *,
        row_number() over (
            partition by station_id, carburant_id, maj_timestamp_utc
            order by ingestion_ts asc
        ) as _row_num
    from typed_and_utc
)

select
    {{ dbt_utils.generate_surrogate_key([
        'station_id', 'carburant_id', 'maj_timestamp_utc'
    ]) }} as prix_sk,
    station_id,
    cp,
    ville,
    adresse,
    pop,
    latitude,
    longitude,
    carburant_id,
    carburant_nom,
    maj_timestamp_utc,
    prix_euro,
    ingestion_ts,
    source_url
from ranked
where _row_num = 1
