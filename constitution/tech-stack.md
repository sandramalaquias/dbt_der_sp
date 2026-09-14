# Tech Stack

## Transformation

- **dbt-core** + **dbt-athena-community** adapter — the whole point of the project; see [mission.md](./mission.md).
- **dbt_utils** (`packages.yml`) — the one external package pulled in so far.

## Storage & compute (AWS)

- **Amazon Athena** — query engine dbt runs against. Three profile targets (`dev`, `seed`, `snapshot`) point at different S3 locations/schemas for the same account — see `profile.yml`.
- **AWS Glue Data Catalog** (`database: awsdatacatalog`) — metastore behind Athena; tables are registered here, not in a dedicated warehouse.
- **Amazon S3** — actual data storage, bucket `der-sp-bucket` (plus a shared `smm-packt-serverless-analytics` bucket for Athena query staging). Models write to explicit `external_location` paths per layer (`raw/`, `staging/`, `core/`, `dimension/`, `marts/`, `snapshot/`).
- **File formats**: Parquet for regular tables/incremental models; **Iceberg** specifically for snapshots, since Athena snapshot/SCD tracking needs a format with update support — plain Parquet-on-S3 doesn't.

Terraform was evaluated for provisioning the above and intentionally dropped (see [mission.md](./mission.md#non-goals)) — infra is created manually.

## Ingestion

- **Python** (`scripts/get_*.py`) — `requests` + `pandas` (+ `openpyxl` implicitly) to pull DER-SP/ANBIMA open data (XLSX/ZIP), normalize columns, and write both a local `.xlsx` copy (`files/`) and a tab-delimited CSV seed (`seeds/`).
- Seeds are loaded into Athena via `dbt seed --target seed`, landing in schema `dbt_der_raw`.

## CI/CD

- **GitHub Actions** (`.github/workflow/dbt_pipeline.yml`) — triggers on PRs to `main`, a monthly cron (10th, 08:00 America/Sao_Paulo), and manual `workflow_dispatch`. Steps: install `dbt-athena-community`, `dbt deps`, build `~/.dbt/profiles.yml` from a `DBT_ENV` secret, `dbt seed --target seed`, `dbt build --target dev`, `dbt snapshot --target snapshot`, `dbt docs generate`, then publish `target/` to **GitHub Pages** via `peaceiris/actions-gh-pages`.

## BI / consumption

- **Metabase** (`metabase/docker-compose.yml`), run locally via Docker Compose, backed by a file-based `metabase.db` checked into the repo (`metabase/data/`). Used to explore and dashboard the `mart_*` tables.

## Local dev environment

- Python **venv** (`.venv/`) + `pip install dbt-athena-community`.
- AWS credentials via a named profile (`aws_profile_name: default`) locally; via `AWS_ACCESS_KEY_ID`/`AWS_SECRET_ACCESS_KEY` secrets in CI.
