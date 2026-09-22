{{ config(
    materialized='table',
    format='parquet',
    external_location='s3://der-sp-bucket/dimension/highway/'
) }}

select *
from {{ ref ("stg_dim_highway") }}

