{{ config(
    materialized='table',
    format='parquet',
    external_location='s3://der-sp-bucket/staging/calend/'
) }}

select *
from from {{ ref("raw_dim_calend") }}
