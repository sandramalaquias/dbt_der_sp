{{ config(
    materialized='table',
    format='parquet',
    external_location='s3://der-sp-bucket/staging/brazilian_holidays/'
) }}

select distinct
cast(data as date) as date_ref,
"dia da semana" as week_day,
"feriado" as holiday_description,
loaded_at
from {{ source("raw", "raw_dim_holidays") }}
