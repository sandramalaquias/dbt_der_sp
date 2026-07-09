{{ config(
    materialized='incremental',
    format='parquet',
    external_location='s3://der-sp-bucket/core/incidents/',
    incremental_strategy='append',
    partitioned_by=['dt_open_at']
) }}

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
    i.load_at,
    i.dt_partition,
    cast(i.open_at as date) as dt_open_at
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
where i.dt_partition = (select max(dt_partition) from {{ ref('stg_incidents') }})
{% endif %}