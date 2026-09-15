# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project

dbt project analyzing 2025 incident (ocorrência) data on São Paulo state highways (DER-SP open data), run on Athena/Glue over S3-backed Iceberg/Parquet tables. It's a learning/showcase project for dbt: each concept is present to demonstrate when, how and why it applies. Ingestion is deliberately standalone Python scripts rather than a Lambda/Step Functions pipeline, and `raw` is treated as a contract boundary fed from outside, with seeds standing in for the landing step.

## Setup

```bash
python3 -m venv .venv
source .venv/bin/activate
pip install dbt-athena-community
```

`profile.yml` at the repo root is the single definition of all three targets, shared by local runs and both CI workflows — copy it into `~/.dbt/profiles.yml`, never re-declare it elsewhere. `aws_profile_name` is the field to repoint at your own AWS profile.

**Don't blind-`cp` it over `~/.dbt/profiles.yml`** — that file is shared across dbt projects and holds unrelated profiles on this machine. Merge the `der_sp:` block in, then verify with `dbt debug` (it runs a real Athena connection test).

## Common commands

Full pipeline (deps → seed → run → test → snapshot, logs to `logs/`, tails the log on failure):
```bash
./run_dbt_pipeline.sh
```

Equivalent individual steps (note each uses a different `--target`):
```bash
dbt seed --target seed        # load seeds/*.csv into raw tables (schema dbt_der_raw)
dbt run --target prod          # build staging/dimensions/core/marts (schema dbt_der / per-layer schema below)
dbt test --target prod
dbt snapshot --target snapshot
```

Single model / test:
```bash
dbt run --select stg_incidents --target prod
dbt run --select core_incidents+ --target prod   # model and downstream
dbt test --select stg_incidents --target prod
```

Other:
```bash
dbt debug     # validate connection/profile
dbt deps      # install packages.yml (dbt_utils)
dbt clean     # wipe target/ and dbt_packages/
```

Re-fetch raw source data (populates `seeds/*.csv` and `files/*.xlsx`):
```bash
python3 scripts/get_all_files.py          # orchestrates all sources
python3 scripts/get_incidents.py          # OCORRENCIAS.zip -> seeds/raw_incidents.csv
python3 scripts/get_highways.py
python3 scripts/get_holidays.py
python3 scripts/get_calend.py
```

There is no BI layer yet. `metabase/docker-compose.yml` exists for a future visualization step and nothing has been built on it — `metabase/data/` is gitignored runtime state that Docker recreates on first start.

## Architecture

**Layer flow:** `raw` (Athena source tables, schema `dbt_der_raw`, loaded from `seeds/`) → `staging` (`stg_*`) → `dimensions` (`dim_*`) → `core` (`core_incidents`) → `marts` (`mart_*`).

`dbt_project.yml` sets per-layer schemas (`staging`, `dim`, `core`, `marts`) and only one materialization default, `table` for marts. **Every model declares its own materialization and an explicit `external_location`** in its `config()`, so there is no layer-wide materialization default to rely on outside marts — `staging`, `dimensions` and `core` mix tables and incrementals, which is why no default is declared for them.

- `stg_incidents`, `core_incidents` and `dim_incident_type` are `materialized='incremental'` with `incremental_strategy='append'`. The first two are partitioned by `dt_partition` and diff `"{{ this.identifier }}$partitions"` against upstream rather than filtering on `this`; `dim_incident_type` instead assigns `max(id) + row_number()` to types it doesn't already hold.
- Everything else is `materialized='table'`, including every `stg_dim_*` and `dim_*` model. **There are no views in this project.**
- Because each model pins `external_location`, the target's `s3_data_dir` is not what places them. Seeds and the snapshot are the exceptions, and that distinction matters — see `constitution/principles.md`.

**Highway matching** (`core_incidents.sql`): incidents are joined to `dim_highway` by `highway_code` plus a km-range match against `km_start`/`km_end`, with special-cased boundary logic for segment starts (`is_segment_start = 'y'`) vs. interior km 0. The identical predicate is duplicated in `tests/staging/stg_assert_incidents_km_unmatched_highways_km.sql`, which uses it as a `left join` to measure the non-match rate — **change both copies together**. (The other unmatched test, `stg_incidents_code_unmatched_highways_code.sql`, joins on `highway_code` only and has no km logic.)

**Calendar spine**: `mart_incidents_daily_by_highway` builds a full date × highway cross join (`dim_calend` × `dim_highway`, scoped to the year range actually present in incidents) and left-joins incident counts, so every highway/day combination appears even with zero incidents — this is what enables timeline/seasonality analysis.

**Snapshots**: `snapshots/snp_highway.sql` snapshots `dim_highway` using the `snapshot` target/profile, `table_type='iceberg'` — Iceberg is required for snapshot targets (regular tables use Parquet + `external_location` instead). Snapshot output goes to `s3://der-sp-bucket/snapshot/...` under schema `dbt_der_snapshots`.

**Seeds**: tab-delimited CSVs (`seed-paths`, `+delimiter: "\t"` in `dbt_project.yml`) generated by the `scripts/get_*.py` files, not hand-edited. Column names come straight from the source XLSX headers (Portuguese, e.g. `"abertura"`, `"rodovia"`, `"coordenadoria geral regional"`) and get renamed to English (`open_at`, `highway_code`, ...) in the staging layer — staging models are the boundary where Portuguese source columns become English semantic names.

**Data quality tests** (`tests/`): custom singular tests, not generic schema tests, mostly checking the highway-match join rate (`stg_incidents_code_unmatched_highways_code.sql`, `stg_assert_incidents_km_unmatched_highways_km.sql`, both `severity='warn'` with a threshold) and open/close date sanity (`raw_assert_incidents_closing_before_opening.sql`, `stg_assert_incidents_closing_before_opening.sql`). There's also a generic macro-based test at `macros/tests/empty_model.sql` (`macro_empty_model`) for asserting a model isn't empty.

## Naming conventions

- Portuguese source column names only appear quoted, inside `stg_*` models reading directly from `source()`; everything downstream of staging uses English snake_case.
- Highway codes follow DER-SP's coding scheme (documented in `README.md`): trunk `SP_XXX`, access `SPA_XXX/XXX`, right/left marginal `SPM_XXX_D`/`SPM_XXX_E`, device `SPD_XXX/XXX`, interconnection `SPI_XXX/XXX`.

## Constitution

`constitution/` holds the project's mission, tech-stack rationale, engineering principles, and collaboration workflow (including the git push rule below). Read it for *why* decisions were made, not just *what* the code does.

## Git

**Always announce a commit before making it** — summarize what would be committed and wait for a go-ahead, every time, not just once per session. **Never run `git push`** without it being explicitly requested for that specific push — only Sandra pushes to GitHub. See `constitution/workflow.md`.
