{% snapshot snp_highway %}

{{
    config(
        target_schema='dbt_der_snapshots',
        unique_key='highway_id',
        table_type='iceberg',
        strategy='timestamp',
        updated_at='loaded_at'
    )
}}

select * from {{ ref('stg_highway') }}

{% endsnapshot %}