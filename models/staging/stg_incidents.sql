{{ config(
    materialized='incremental',
    format='parquet',
    external_location='s3://der-sp-bucket/staging/incidents/',
    incremental_strategy='append',
    partitioned_by=['dt_partition']
) }}

with df1 as (
    select
        cast(current_timestamp as timestamp) as timestamp_now,
        {% if is_incremental() %}
        max(dt_partition)   as max_dt_partition
        from {{ this }}
        {% else %}
        cast('1900-01-01' as date) as max_dt_partition
        from (values (1)) as t(x)
        {% endif %}
)

select
    "abertura"                                      as open_at,
    coalesce("fechamento", "abertura")              as close_at,
    nullif(trim("rodovia"), '')                     as highway_code,
    "km"                                            as km,
    nullif(trim("sentido"), '')                     as traffic_direction,
    nullif(trim("cgr"), '')                         as regional_code,
    nullif(trim("coordenadoria geral regional"), '') as regional_name,
    nullif(trim("descrição da ocorrência"), '')      as incident_category,
    nullif(trim("tipo da ocorrência"), '')           as incident_type,
    "data"                                          as incident_date,
    nullif(trim("dia da semana"), '')               as day_of_week,
    "latitude"                                      as geo_lat,
    "longitude"                                     as geo_lng,
    count(*)                                        as record_count,
    df1.timestamp_now                               as load_at,
    max(dt_partition)                               as dt_partition
from {{ source('raw', 'incidents') }} as inc, df1
where "abertura" is not null and
       coalesce("fechamento", "abertura") >= "abertura"
       --and inc.dt_partition > df1.max_dt_partition
group by 1,2,3,4,5,6,7,8,9,10,11,12,13,15