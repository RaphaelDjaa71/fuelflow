{#
  generate_schema_name — override dbt's default schema naming.

  Default behavior prefixes with the target schema (target_schema_custom).
  We want layer-named schemas without prefix so the warehouse layout
  mirrors the medallion vocabulary (silver / gold) on both backends:
    - BigQuery: dataset = "fuelflow_silver" or "fuelflow_gold"
    - Snowflake: schema = "SILVER" or "GOLD" inside the FUELFLOW database

  Models without a custom_schema_name (i.e. no +schema config) land in
  the profile's default schema (silver), which is the L3 staging convention.
#}
{% macro generate_schema_name(custom_schema_name, node) -%}
  {%- if custom_schema_name is none -%}
    {{ target.schema }}
  {%- elif target.type == 'bigquery' -%}
    fuelflow_{{ custom_schema_name | trim }}
  {%- else -%}
    {{ custom_schema_name | trim | upper }}
  {%- endif -%}
{%- endmacro %}
