{{ config(
    materialized='table',
    format='parquet',
    external_location='s3://der-sp-bucket/staging/highway/'
) }}

with loaded as (
    select cast(current_timestamp as timestamp) as load_at
),

base as (
    select *
    from {{ source("raw", "raw_dim_highway") }}, loaded
    where rodovia is not null and rodovia <> ' '
),

with_lag as (
    select *,
        lag("km final") over (
            partition by "rodovia"
            order by "km inicial"
        ) as prev_km_end
    from base
)

select
    {{ dbt_utils.generate_surrogate_key(['"rodovia"', '"km inicial"']) }} as highway_id,
    nullif(trim("rodovia"), '')                             as highway_code,
    nullif(trim("tipo de rodovia"), '')                     as highway_class,
    nullif(trim("orientação"), '')                          as highway_direction,
    nullif(trim("origem"), '')                              as highway_level,
    nullif(trim("municipio"), '')                           as along_city,
    nullif(trim("regional (cgr)"), '')                      as regional_code,
    nullif(trim("sede coordenadoria geral regional"), '')   as regional_name,
    "km inicial"                                            as km_start,
    "km final"                                              as km_end,
    "extensão"                                              as parcial_lengh,
    nullif(trim("descrição inicial"), '')                   as description_start,
    nullif(trim("descrição final"), '')                     as description_end,
    nullif(trim("jurisdição"), '')                          as jurisdiction,
    nullif(trim("administrador"), '')                       as administrator,
    nullif(trim("conservador"), '')                         as conservator,
    nullif(trim("tipopista"), '')                           as highway_type,
    nullif(trim("sobreposição"), '')                        as overlap,
    nullif(trim("subposição"), '')                          as underlay,
    nullif(trim("perímetro urbano"), '')                    as is_urban,
    nullif(trim("estadual coincidente"), '')                as is_coincident_highway,
    nullif(trim("denominação"), '')                         as highway_name,
    case
        when trim("denominação") in (' ', 's/d') or "denominação" is null
        then nullif(trim("descrição final"), '')
        else nullif(trim("denominação"), '')
    end                                                     as highway_name_normalized,
    nullif(trim("legislação"), '')                          as legislation,
    nullif(trim("tpuso"), '')                               as highway_use_type,
    nullif(trim("transf. municipio"), '')                   as transfer_law,
    nullif(trim("subtrecho"), '')                           as sub_section,
    "data de início do contrato"                            as contract_start_date,
    "data de fim do contrato"                               as contract_end_date,
    prev_km_end,
    case when prev_km_end is null then 'y' else 'n' end as is_segment_start,
    'SP'                                                    as state_code,
    load_at as loaded_at
from with_lag
