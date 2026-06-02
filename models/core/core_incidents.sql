{{ config(
    materialized='incremental',
    format='parquet',
    external_location='s3://der-sp-bucket/core/incidents/',
    incremental_strategy='append',
    partitioned_by=['dt_open_at']
) }}

with incidents as (
    select *
    from {{ ref('stg_incidents') }}
    {% if is_incremental() %}
    where dt_partition = (select max(dt_partition) from {{ ref('stg_incidents') }})
    {% endif %}
),

highway_with_lag as (
    select *,
        lag(km_end) over (
            partition by highway_code
            order by km_start
        ) as prev_km_end
    from {{ ref('stg_highway') }}
)

select
    i.open_at,
    i.close_at,
    i.highway_code,
    h.highway_id,
    h.highway_name_normalized,
    h.along_city,
    h.is_urban,
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
from incidents i
left join highway_with_lag h
    on i.highway_code = h.highway_code
    and (
        -- OR used instead of CASE to allow query optimizer to evaluate conditions independently
        (h.prev_km_end = h.km_start and i.km > h.km_start and i.km <= h.km_end)
        or
        (
            (h.prev_km_end != h.km_start or h.prev_km_end is null)
            and i.km >= h.km_start
            and i.km <= h.km_end
        )
    )