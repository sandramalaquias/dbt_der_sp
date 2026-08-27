-- models/marts/mart_incident_summary.sql
{{ config(
    materialized='table',
    format='parquet',
    external_location='s3://der-sp-bucket/marts/mart_incident_summary/'
) }}

select
    count(*) as total_incidents,
    round(1.0 * count(*) / (date_diff('day', min(incident_date), max(incident_date)) + 1), 2) as avg_incidents_daily,
    count(distinct highway_id) as total_impacted_segments,
    round(1.0 * count(*) / count(distinct highway_id), 2) as avg_incidents_per_segment,
    count(distinct along_city) as total_impacted_cities,
    round(1.0 * count(*) / count(distinct along_city), 2) as avg_incidents_per_city
from {{ ref('core_incidents') }}