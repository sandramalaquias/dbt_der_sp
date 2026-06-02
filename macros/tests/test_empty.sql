{% test macro_empty_model(model) %}

with df1 as (
    select 1
    from {{ model }}
    limit 1
)
select 1
from df1
having count(*) = 0

{% endtest %}