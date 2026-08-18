{{ config(
    materialized='table',
    format='parquet',
    external_location='s3://der-sp-bucket/marts/mart_incidents_daily_by_highway/',
    partitioned_by=['year_ref']
) }}

with incidents as (
    select
        highway_id,
        incident_date,
        count(*) as qty_incident_count
    from {{ ref('core_incidents') }}
    group by 1, 2
),

year_range as (
    select
        min(year(incident_date)) as min_year,
        max(year(incident_date)) as max_year
    from incidents
),

calend_scoped as (
    select
        c.date_ref,
        c.week_day,
        week_day_name,
        c.is_weekend,
        c.month_ref,
        c.month_name,
        c.year_day,
        c.year_week,
        c.month_week,
        c.quarter_year,
        c.fl_holiday,
        c.holiday_description,
        c.year_ref

    from {{ ref('dim_calend') }} c
    cross join year_range y
    where year_ref between y.min_year and y.max_year
),

spine as (
    select
        h.highway_id,
        h.highway_code,
        h.highway_name_normalized,
        h.along_city,
        h.is_urban,
        c.*
    from {{ ref('dim_highway') }} h
    cross join calend_scoped c
)

select
    s.highway_id,
s.highway_code,
s.highway_name_normalized,
s.along_city,
s.is_urban,
s.date_ref,
s.week_day,
s.week_day_name,
s.is_weekend,
s.month_ref,
s.month_name,
s.year_day,
s.year_week,
s.month_week,
s.quarter_year,
s.fl_holiday,
s.holiday_description,
coalesce(i.qty_incident_count, 0) as qty_incident_count,
s.year_ref

from spine as s
left join incidents as i
    on s.highway_id = i.highway_id
    and s.date_ref = i.incident_date