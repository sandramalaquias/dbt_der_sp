{{ config(
    materialized='table',
    format='parquet',
    external_location='s3://der-sp-bucket/dimension/calend/'
) }}

select
c.date_ref,
c.week_day,
c.week_day_name,
c.is_weekend,
c.year_ref,
c.month_ref,
c.month_name,
c.year_day,
c.year_week,
c.month_week,
c.quarter_year,
case when h.date_ref is not null then '1' else '0' end as fl_holiday,
h.holiday_description,
cast(current_timestamp as timestamp) as load_at
from  {{ ref("stg_dim_calend") }} as c
left join {{ ref("stg_dim_holidays") }} as h on c.date_ref = h.date_ref
order by c.date_ref
