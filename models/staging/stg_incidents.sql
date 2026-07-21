{{ config(
    materialized='incremental',
    format='parquet',
    external_location='s3://der-sp-bucket/staging/incidents/',
    incremental_strategy='append',
    partitioned_by=['dt_partition']
) }}

{% if is_incremental() %}
with staging as (
    select dt_partition
    from {{ this.database }}.{{ this.schema }}."{{ this.identifier }}$partitions")
{% endif %}

select
    "abertura"                                        as open_at,
    "fechamento"                                      as close_at,
    nullif(trim("rodovia"), '')                       as highway_code,
    "km"                                              as km,
    nullif(trim("sentido"), '')                       as traffic_direction,
    nullif(trim("cgr"), '')                           as regional_code,
    nullif(trim("coordenadoria geral regional"), '')  as regional_name,
    nullif(trim("descrição da ocorrência"), '')       as incident_category,
    nullif(trim("tipo da ocorrência"), '')            as incident_type,
    "data"                                            as incident_date,
    nullif(trim("dia da semana"), '')                 as day_of_week,
    "latitude"                                        as geo_lat,
    "longitude"                                       as geo_lng,
    count(*)                                          as record_count,
    cast(current_timestamp as timestamp)              as load_at,
    dt_partition                                      as dt_partition
from {{ source('raw', 'raw_incidents') }}
where "data" is not null
    {% if is_incremental() %}
        and dt_partition not in (select dt_partition from staging)
    {% endif %}
group by 1,2,3,4,5,6,7,8,9,10,11,12,13,15,16