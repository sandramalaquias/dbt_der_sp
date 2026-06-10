{{ config(severity='warn') }}

with perc_unmatched as (
    select
        cast(sum(case when h.highway_code is null then 1 else 0 end) as double) /
        count(*) as perc_unmatched
    from {{ ref('stg_incidents') }} i
    left join {{ ref('stg_highway') }} h
        on i.highway_code = h.highway_code
        and (
            (h.is_segment_start = 'y' and i.km >= h.km_start and i.km <= h.km_end)
            or
            (h.is_segment_start <> 'y' and i.km > h.km_start and i.km <= h.km_end)
            or
            (h.is_segment_start = 'y' and i.km = 0.0)
        )
    where i.dt_partition = (select max(dt_partition) from {{ ref('stg_incidents') }})
)
select * from perc_unmatched
where perc_unmatched > 0.01