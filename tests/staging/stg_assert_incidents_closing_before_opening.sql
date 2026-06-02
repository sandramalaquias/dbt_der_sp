SELECT 1
FROM {{ ref('stg_incidents') }}
WHERE close_at  < open_at
limit 1