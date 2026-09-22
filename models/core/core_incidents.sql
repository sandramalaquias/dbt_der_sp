{{ config(
    materialized='incremental',
    format='parquet',
    external_location='s3://der-sp-bucket/core/incidents/',
    incremental_strategy='append',
    partitioned_by=['dt_partition']
) }}

{% set stg = ref('stg_incidents') %}

{% if is_incremental() %}
with staging_partitions as (
    select dt_partition
    from {{ stg.database }}.{{ stg.schema }}."{{ stg.identifier }}$partitions"
),

core_partitions as (
    select dt_partition
    from {{ this.database }}.{{ this.schema }}."{{ this.identifier }}$partitions"
),

to_process as (
    select dt_partition
    from staging_partitions
    where dt_partition not in (select dt_partition from core_partitions)
)
{% endif %}

select
    i.open_at,
    i.close_at,
    i.highway_code,
    h.highway_id,
    h.highway_name_normalized,
    h.along_city,
    h.is_urban,
    h.is_segment_start,
    i.km,
    i.traffic_direction,
    i.regional_code,
    i.regional_name,
    i.incident_category,
    i.incident_type,
    i.incident_date,
    i.day_of_week,
    i.geo_lat,
    i.geo_lng,
    i.record_count,
    cast(current_timestamp as timestamp) as load_at,
    i.dt_partition
from {{ ref('stg_incidents') }} i
join {{ ref("dim_highway") }} h
    on i.highway_code = h.highway_code
    and (
        (h.is_segment_start = 'y' and i.km >= h.km_start and i.km <= h.km_end)
        or
        (h.is_segment_start <> 'y' and i.km > h.km_start and i.km <= h.km_end)
        or
        (h.is_segment_start = 'y' and i.km = 0.0)
    )
{% if is_incremental() %}
where i.dt_partition in (select dt_partition from to_process)
{% endif %}