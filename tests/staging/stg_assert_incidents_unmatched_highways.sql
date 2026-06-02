-- description: "Validates that the percentage of incidents with highway codes not found in stg_highway is below 5%.
-- If unmatched incidents exceed 5% of total, the test fails indicating a data quality
-- issue in the highway reference table."

with df1 as (
    select distinct highway_code as code
    from {{ ref('stg_highway') }}
),
df2 as (
    select
        count(*) as total_count,
        count(df1.code) as matched_count
    from {{ ref('stg_incidents') }} si
    left join df1 on df1.code = si.highway_code
)
    select *, 100*(1 - matched_count / cast(total_count as double)) as perc_no_match
    from df2
    having 100*(1 - matched_count / cast(total_count as double)) > 5