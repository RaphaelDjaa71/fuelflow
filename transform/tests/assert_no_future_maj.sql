{#
  Singular test: no priced row may live in the future.

  Both sides of the comparison are normalized to UTC wall-clock so the
  test is symmetric on BigQuery (where TIMESTAMP carries UTC semantics
  and current_timestamp() returns UTC) and on Snowflake (where
  maj_timestamp_utc is TIMESTAMP_NTZ-as-UTC and current_timestamp()
  returns TIMESTAMP_LTZ in the session TIMEZONE — left raw, the
  comparison silently uses the session offset and falsely flags rows
  as "in the future").
#}

select
    prix_sk,
    station_sk,
    maj_timestamp_utc
from {{ ref('fct_prix_carburant') }}
where
    maj_timestamp_utc >
    {% if target.type == 'bigquery' %}
        current_timestamp()
    {% elif target.type == 'snowflake' %}
        cast(convert_timezone('UTC', current_timestamp()) as timestamp_ntz)
    {% endif %}
