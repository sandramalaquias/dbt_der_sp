{{ config(
    materialized='table',
    format='parquet',
    external_location='s3://der-sp-bucket/marts/mart_incident_type_pareto/'
) }}

with consolidado as (
    select
        incident_type,
        count(*) as total_incidents
    from {{ ref('core_incidents') }}
    where incident_type not in (
        'Informação da Posição em Campo',
        'Fiscalização geral (especificar)',
        'Conservação / Obras na pista',
        'Materiais Diversos fora da pista',
        'Não localizado'
    )
    group by 1
),

ranked as (
    select
        incident_type,
        total_incidents,
        row_number() over (order by total_incidents desc) as ranking
    from consolidado
),

acumulado as (
    select
        *,
        sum(total_incidents) over (order by ranking rows between unbounded preceding and current row) as cumulative_incidents,
        sum(total_incidents) over () as total_state
    from ranked
),

pareto as (
select
    incident_type,
    total_incidents,
    ranking,
    cumulative_incidents,
    round(100.0 * cumulative_incidents / total_state, 2) as pct_cumulative,
    case when round(100.0 * cumulative_incidents / total_state, 2) <= 80 then true else false end as is_priority_80
from acumulado)

select *
from pareto
where is_priority_80 = true
order by ranking