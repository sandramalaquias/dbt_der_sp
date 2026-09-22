{{ config(severity='warn', warn_if='>0', error_if='>10') }}

SELECT *
FROM {{ source('raw', 'raw_incidents') }}
WHERE fechamento is not null and abertura is not null and
      fechamento < abertura
