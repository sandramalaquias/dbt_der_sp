{{ config(
    materialized='incremental',
    format='parquet',
    external_location='s3://der-sp-bucket/dimension/incident_type/',
    incremental_strategy='append'
) }}

with last_partition as (
    select max(dt_partition) as max_dt
    from {{ ref('stg_incidents') }}
),

new_types as (
    select distinct
        incident_type,
        incident_category
    from {{ ref('stg_incidents') }}, last_partition
    where dt_partition = last_partition.max_dt
    {% if is_incremental() %}
    and incident_type not in (
        select incident_type from {{ this }}
    )
    {% endif %}
),

max_id as (
    {% if is_incremental() %}
    select coalesce(max(incident_type_id), 0) as last_id from {{ this }}
    {% else %}
    select 0 as last_id from (values (1)) as t(x)
    {% endif %}
)

select
    max_id.last_id + row_number() over (order by new_types.incident_category, new_types.incident_type) as incident_type_id,
    new_types.incident_type,
    new_types.incident_category
from new_types, max_id