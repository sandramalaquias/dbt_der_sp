# Tech Stack

## Transformation

- **dbt-core** + **dbt-athena-community** adapter — the whole point of the project; see [mission.md](./mission.md).
- **dbt_utils** (`packages.yml`) — the one external package pulled in so far.

## Storage & compute (AWS)

- **Amazon Athena** — query engine dbt runs against. Three profile targets (`dev`, `seed`, `snapshot`) point at deliberately non-overlapping S3 locations/schemas in the same account — see `profile.yml`, and [principles.md](./principles.md#targets--s3-layout) for why the separation is mandatory rather than cosmetic.
- **AWS Glue Data Catalog** (`database: awsdatacatalog`) — metastore behind Athena; tables are registered here, not in a dedicated warehouse.
- **Amazon S3** — actual data storage, bucket `der-sp-bucket` (plus a shared `smm-packt-serverless-analytics` bucket for Athena query staging). Models write to explicit `external_location` paths per layer (`raw/`, `staging/`, `core/`, `dimension/`, `marts/`, `snapshot/`).
- **File formats**: Parquet for regular tables/incremental models; **Iceberg** specifically for snapshots, since Athena snapshot/SCD tracking needs a format with update support — plain Parquet-on-S3 doesn't.

Terraform was evaluated for provisioning the above and intentionally dropped (see [mission.md](./mission.md#non-goals)) — infra is created manually.

## Ingestion

- **Python** (`scripts/get_*.py`) — `requests` + `pandas` (+ `openpyxl` implicitly) to pull DER-SP/ANBIMA open data (XLSX/ZIP), normalize columns, and write both a local `.xlsx` copy (`files/`) and a tab-delimited CSV seed (`seeds/`).
- Seeds are loaded into Athena via `dbt seed --target seed`, landing in schema `dbt_der_raw`.

## CI/CD

- **GitHub Actions** (`.github/workflows/dbt_pipeline.yml`) — stands in for a real orchestrator, since this project has none. Steps: install `dbt-athena-community`, `dbt deps`, write a `[default]` AWS profile from the `DBT_ENV` secret and copy the repo's `profile.yml` into place, then the four dbt invocations with their own targets (`seed` → `run` → `test` → `snapshot`, per [principles.md](./principles.md#targets--s3-layout)), `dbt docs generate`, and publish `target/` to **GitHub Pages** via `peaceiris/actions-gh-pages`.
- **Manual trigger only** (`workflow_dispatch`). The `pull_request` and monthly `schedule` triggers were deliberately removed: every model pins an absolute `external_location`, so *any* run — PR or cron — writes to the same S3 prefixes and Glue schema as every other run. There is no environment isolation, so an automatic run would silently overwrite the project's only copy of the data. Re-adding `schedule` is a one-line change once that's addressed. Note the "Run workflow" button only appears once the file is on the default branch, and scheduled workflows only fire from the default branch.
- A failing step stops the job by default, so `dbt test` failing prevents the snapshot from running — matching `run_dbt_pipeline.sh` (see its inline comment for why).
- **`dbt_tests.yml`** is a second, separate workflow running only `dbt test`. It's split from the build because the two want different failure semantics: the build shouldn't abort on data-quality noise, while the monitor's whole job is to shout about it. Being test-only, it never writes — so unlike the build, it has no isolation problem and its `schedule` trigger could be enabled safely. It still defines all three targets: the profile describes the *environment*, not one job's needs (see [principles.md](./principles.md#environment-reproducibility)).

## BI / consumption

- **None yet.** `metabase/docker-compose.yml` is kept for a future visualization step, but nothing has been built on it — no dashboards exist. The marts are queried directly in Athena.
- `metabase/data/` is gitignored: it's the container's runtime H2 state, recreated on first start. It used to be committed, which meant a 7.2 MB binary rewritten in full on every change, preserving nothing but a connection form.

## Local dev environment

- Python **venv** (`.venv/`) + `pip install dbt-athena-community`.
- AWS credentials via a named profile (`aws_profile_name: default`) locally; via `AWS_ACCESS_KEY_ID`/`AWS_SECRET_ACCESS_KEY` secrets in CI.
