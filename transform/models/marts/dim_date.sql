{{ config(materialized='table') }}

{# 2007-01-01 inclusive to 2032-01-01 exclusive (covers 2007 through
   2031). The lower bound is intentionally generous so the fct ->
   dim_date relationships test cannot fail because of an unusually
   stale <prix maj=...> from a station that has not updated in years.
   Reference: maj_min seen in the live feed is 2024-05-24 today, but
   future snapshots may surface older rows. #}
with date_spine as (
    {{ dbt_utils.date_spine(
        datepart='day',
        start_date="cast('2007-01-01' as date)",
        end_date="cast('2032-01-01' as date)"
    ) }}
),

calendar as (
    select cast(date_day as date) as full_date
    from date_spine
)

select
    {# date_sk = YYYYMMDD integer, computed portably. #}
    {% if target.type == 'bigquery' %}
    cast(format_date('%Y%m%d', full_date) as int64) as date_sk,
    {% elif target.type == 'snowflake' %}
    cast(to_char(full_date, 'YYYYMMDD') as integer) as date_sk,
    {% endif %}

    full_date,

    extract(year from full_date) as year,
    extract(quarter from full_date) as quarter,
    extract(month from full_date) as month,

    {# Month name in French via portable CASE. #}
    case extract(month from full_date)
        when 1 then 'Janvier'   when 2 then 'Février'  when 3 then 'Mars'
        when 4 then 'Avril'     when 5 then 'Mai'      when 6 then 'Juin'
        when 7 then 'Juillet'   when 8 then 'Août'     when 9 then 'Septembre'
        when 10 then 'Octobre'  when 11 then 'Novembre' when 12 then 'Décembre'
    end as month_name_fr,

    extract(day from full_date) as day_of_month,

    {# day_of_week: 1=Monday..7=Sunday, ISO. BigQuery returns 1=Sunday..7=Saturday
       by default, Snowflake also returns 0..6 with Sunday as 0 unless WEEK_START
       is set. We normalize to ISO 1..7 via target-specific expression. #}
    {% if target.type == 'bigquery' %}
    case extract(dayofweek from full_date)
        when 1 then 7  -- Sunday -> 7
        else extract(dayofweek from full_date) - 1
    end as day_of_week,
    {% elif target.type == 'snowflake' %}
    dayofweekiso(full_date) as day_of_week,
    {% endif %}

    case
        {% if target.type == 'bigquery' %}
        extract(dayofweek from full_date)
        when 2 then 'Lundi'    when 3 then 'Mardi'   when 4 then 'Mercredi'
        when 5 then 'Jeudi'    when 6 then 'Vendredi' when 7 then 'Samedi'
        when 1 then 'Dimanche'
        {% elif target.type == 'snowflake' %}
        dayofweekiso(full_date)
        when 1 then 'Lundi'    when 2 then 'Mardi'   when 3 then 'Mercredi'
        when 4 then 'Jeudi'    when 5 then 'Vendredi' when 6 then 'Samedi'
        when 7 then 'Dimanche'
        {% endif %}
    end as day_name_fr,

    {% if target.type == 'bigquery' %}
    extract(isoweek from full_date) as iso_week,
    {% elif target.type == 'snowflake' %}
    weekiso(full_date) as iso_week,
    {% endif %}

    {% if target.type == 'bigquery' %}
    extract(dayofweek from full_date) in (1, 7) as is_weekend
    {% elif target.type == 'snowflake' %}
    dayofweekiso(full_date) in (6, 7) as is_weekend
    {% endif %}

from calendar
order by full_date
