# DER-SP: Incidents on São Paulo State Highways

A dbt project over DER-SP's public incident data, running on AWS (Athena + Glue Catalog + S3).

It is two things at once. It is a working analytics pipeline that answers three concrete questions about road incidents. It is also a **demonstration**: every dbt concept here is present to show *when, how and why* it applies, not because an operational requirement forced it. The snapshot is the clearest example — nobody needs SCD history of the highway reference table; it exists to demonstrate judgment about snapshots.

That dual purpose drives the design choices: prefer legibility and stated rationale over clever abstraction, and keep each decision visible in the file where it happens.

---

## Scope: three questions

**1. Incident Type Pareto** — which incident types account for the majority of occurrences? Counts by type, ranked, with a cumulative percentage. Types making up the cumulative 80% are the priority candidates for road safety action.

**2. Daily Incident Timeline** — a day-by-day timeline per highway, built on a full calendar spine so every day appears even with zero incidents. This is what makes temporal analysis possible: weekday effects, holidays, seasonality.

**3. Summary KPIs** — headline metrics for a quick read: total incidents, average per day, per impacted highway segment, and per impacted city.

## Deliberately out of scope

These are decisions, not omissions:

- **No IaC.** S3 buckets, the Glue catalog and the Athena setup are provisioned by hand. Terraform was considered and dropped: provisioning it properly is overhead unrelated to demonstrating dbt.
- **No Lambda / Step Functions ingestion.** Extraction is standalone Python scripts, run manually. See [Ingestion](#ingestion-raw-is-a-contract-boundary).
- **No test environment.** There is one environment and it is production. A second set of S3 prefixes and Glue schemas would double the infrastructure for no demonstration value.
- **Not a production platform.** No SLA, no on-call. Operational robustness is still taken seriously *from the raw layer onward*, because that layer is meant to behave like a real one.

---

## Data sources

| Source | URL | Format | Description |
|---|---|---|---|
| Incidents | [OCORRENCIAS.zip](https://www.der.sp.gov.br/WebSite/Arquivos/DadosAbertos/Acidentes/Ocorrencias/OCORRENCIAS.zip) | XLSX inside ZIP | State highway incident occurrences — ~267,883 records |
| Road network | [Sistema Rodoviário Estadual.xlsx](https://www.der.sp.gov.br/WebSite/Arquivos/DadosAbertos/MalhaRodoviariaEstadual/MalhaRodoviariaEstadual/Sistema%20Rodovi%C3%A1rio%20Estadual.xlsx) | XLSX | Highway + km to municipality mapping — 4,583 records |
| National holidays | [Feriados Nacionais](https://www.anbima.com.br/feriados/arqs/feriados_nacionais.xls) | XLS | National holidays 2001–2060, ANBIMA |
| Calendar | Generated in Excel | XLSX | Calendar 2025–2030 |

### Domain notes

**Highway coding** used by DER-SP:

| Type | Pattern |
|---|---|
| Trunk highway | `SP_XXX` |
| Access | `SPA_XXX/XXX` |
| Right marginal | `SPM_XXX_D` |
| Left marginal | `SPM_XXX_E` |
| Device | `SPD_XXX/XXX` |
| Interconnection | `SPI_XXX/XXX` |

**Municipality is derived, not given.** Incidents carry a highway code and a km marker; the city comes from joining the road network on `highway_code` plus `km BETWEEN km_start AND km_end`. No shapefile is needed.

**Coverage: 311 of the 312 highways** present in the incident data are matched by the road network — only SP-313 is absent. This is why the unmatched-highway tests assert a *threshold* rather than zero: the residue is a known property of the published data, not a bug to chase.

---

## Ingestion: raw is a contract boundary

Conceptually, data arrives in `raw` from a process that lives outside this repository. `dbt seed` stands in for the **landing** step — what would be an S3 drop plus a Glue crawler in a real setup. The extraction itself is real:

| Script | Responsibility |
|---|---|
| `scripts/get_all_files.py` | Orchestrator — calls the four extractors |
| `scripts/get_incidents.py` | Downloads `OCORRENCIAS.zip`, extracts the current year's XLSX → `seeds/raw_incidents.csv` |
| `scripts/get_highways.py` | Downloads the state highway network |
| `scripts/get_holidays.py` | Downloads national holidays |
| `scripts/get_calend.py` | Reads `files/calend.xlsx` — a hand-built Excel input, not a download — and writes the calendar seed |

```bash
python3 scripts/get_all_files.py
```

What the extraction guarantees, so downstream can rely on it:

- `raise_for_status()` on every download — an HTTP failure stops the run
- a `ValueError` **listing the files actually found** when the expected year's XLSX is missing, rather than silent success
- header normalization (`' '.join(col.split())`), collapsing the double spaces and line breaks DER-SP's spreadsheets carry
- `loaded_at` and `dt_partition` stamped on every row — the provenance a real loader would provide
- an archived `.xlsx` copy in `files/` alongside the seed (gitignored — the scripts can rebuild it)
- tab-separated CSV (`sep="\t"`), because free-text fields contain commas; `dbt_project.yml` matches with `+delimiter: "\t"`

The risk the pipeline defends against is therefore **the publisher, not the loader**: messy real-world values (km outside the network, closing before opening, unknown highway codes) rather than a flaky download.

### Why these aren't a Lambda

The goal is to demonstrate dbt, not to build a production ingestion service. A Lambda would need IaC to provision properly, a Step Function to sequence, and would still be manually triggered. Keeping the extraction as plain scripts spends the project's complexity budget on dbt.

---

## Architecture

```
raw          seeds → dbt_der_raw                     declared in models/staging/sources.yml
  ↓
staging      stg_incidents, stg_dim_highway,         dbt_der_staging
             stg_dim_calend, stg_dim_holidays        Portuguese → English boundary
  ↓
dimensions   dim_highway, dim_calend,                dbt_der_dim
             dim_incident_type
  ↓
core         core_incidents                          dbt_der_core
  ↓
marts        mart_incident_type_pareto,              dbt_der_marts
             mart_incidents_daily_by_highway,
             mart_incident_summary
```

`snapshots/snp_highway.sql` tracks `dim_highway` history in `dbt_der_snapshots`.

**Staging is the language boundary.** Source column names (`"abertura"`, `"rodovia"`, `"descrição da ocorrência"`) appear quoted only inside `stg_*` models reading from `source()`. Everything downstream uses English snake_case.

### Model inventory

Every model pins its own materialization and S3 location in its `config()` block. 8 of the 11 sit in a layer with no project-level default at all — `staging`, `dimensions` and `core` each mix tables and incrementals, so no layer-wide default would be true. The three marts are the exception: they inherit `+materialized: table` from `dbt_project.yml` and restate it.

**There are no views in this project**, which is itself a finding rather than an oversight: on Athena a view saves no storage but re-scans its sources on every read, so the cost moves to whoever queries it. See [mission.md](constitution/mission.md).

| Model | Materialized | Strategy | S3 location (under `der-sp-bucket`) | Partitioned by |
|---|---|---|---|---|
| `stg_incidents` | incremental | append | `/staging/incidents/` | `dt_partition` |
| `stg_dim_highway` | table | — | `/staging/highway/` | — |
| `stg_dim_calend` | table | — | `/staging/calend/` | — |
| `stg_dim_holidays` | table | — | `/staging/brazilian_holidays/` | — |
| `dim_highway` | table | — | `/dimension/highway/` | — |
| `dim_calend` | table | — | `/dimension/calend/` | — |
| `dim_incident_type` | incremental | append | `/dimension/incident_type/` | — |
| `core_incidents` | incremental | append | `/core/incidents/` | `dt_partition` |
| `mart_incident_type_pareto` | table | — | `/marts/mart_incident_type_pareto/` | — |
| `mart_incidents_daily_by_highway` | table | — | `/marts/mart_incidents_daily_by_highway/` | `year_ref` |
| `mart_incident_summary` | table | — | `/marts/mart_incident_summary/` | — |
| `snp_highway` (snapshot) | iceberg | timestamp | `/snapshot/snp_highway` | — |

### Notable mechanics

**Incremental by partition diff.** `stg_incidents` and `core_incidents` don't filter on a `max(loaded_at)`. They query Athena's `"<table>$partitions"` pseudo-table and process only the `dt_partition` values not yet present downstream. This is the right shape for a raw layer appended to by an external process, and it makes a re-run naturally skip work already done.

**Surrogate keys without a hash.** `dim_incident_type` is incremental: it takes distinct types from the latest partition, filters out those it already holds, and assigns `max(id) + row_number()`. New types get new ids; existing ids never move.

**The km-range match** in `core_incidents` joins on `highway_code` plus a km range, with boundary cases for segment starts:

```sql
(h.is_segment_start = 'y' and i.km >= h.km_start and i.km <= h.km_end)
or (h.is_segment_start <> 'y' and i.km >  h.km_start and i.km <= h.km_end)
or (h.is_segment_start = 'y' and i.km = 0.0)
```

This predicate also appears in `tests/staging/stg_assert_incidents_km_unmatched_highways_km.sql`, which uses it as a `left join` to measure the *non*-match rate. **Both copies must change together.**

**Calendar spine.** `mart_incidents_daily_by_highway` cross joins `dim_calend` with `dim_highway` (scoped to the years actually present in the incident data), then left joins counts and coalesces to zero. That's what guarantees a continuous timeline.

---

## Targets and the S3 layout

Three profile targets exist, and the separation is **functional, not organizational**. Their `s3_data_dir` values must stay on non-overlapping prefixes: an external table's location must not contain another table's files.

| Target | Purpose | `s3_data_dir` | `s3_data_naming` | Glue schema |
|---|---|---|---|---|
| `prod` | models and tests | `smm-packt-serverless-analytics/dbt-data/` | `schema_table` | `dbt_der` (+ layer suffix) |
| `seed` | loading `seeds/*.csv` into raw | `der-sp-bucket/raw/` | `table` | `dbt_der_raw` |
| `snapshot` | the Iceberg snapshot | `der-sp-bucket/snapshot/` | `schema_table` | `dbt_der` |

Which mechanism decides a location depends on the resource, and this is easy to get wrong:

- **Models** pin `external_location`, and the adapter honours it over `s3_data_dir`.
- **Seeds cannot pin a location**, so they land wherever the target says: `der-sp-bucket/raw/` + `s3_data_naming: table` → `s3://der-sp-bucket/raw/raw_incidents/`, registered in `dbt_der_raw`, which `sources.yml` hardcodes.
- **The snapshot isn't covered by its own `external_location` alone.** The adapter's snapshot materialization has no location handling of its own and falls back to the target's `s3_data_dir`, which makes that dedicated prefix structural. Iceberg compounds it: it manages `metadata/` and `data/` subdirectories under its location, so sharing a prefix with Hive tables corrupts it.

**Do not "tidy" these paths.** A path that looks unused may be the one holding the snapshot together.

### Never `dbt build`

A single invocation applies one target to *every* resource type, so `dbt build --target prod` would drag the seeds into the prod prefix — wrong bucket, wrong naming, wrong Glue schema. Always run the four steps explicitly:

```bash
dbt seed --target seed
dbt run --target prod
dbt test --target prod
dbt snapshot --target snapshot
```

### One environment, and it is production

The target is named `prod` rather than `dev` on purpose. There is no sandbox: every run reads and writes the project's only copy of the data. The old name meant the safest-sounding label pointed at the least safe destination, and a bare `dbt run` — which falls back to the profile's default target — would quietly hit it.

The protection against accidents is therefore not isolation, which doesn't exist here. It is that runs are **deliberate**: CI is manual-trigger only.

Nothing in the project branches on `target.name`, and it should stay that way — otherwise the single-environment premise starts leaking into the models.

### `num_retries: 0` is deliberate

The adapter default is 5, and 5 is wrong here. `num_retries` wraps the function that *submits and executes* the query, retrying on essentially any exception — including a query that reached Athena and failed. With `incremental_strategy='append'` the statement is an `INSERT INTO`, and Hive-on-S3 has no commit protocol: files written by a dying INSERT are already visible. A retry then either re-inserts everything (duplicates) or gets filtered by the `$partitions` diff and inserts nothing, leaving a partition that *looks* complete.

The adapter's own nested retry proves the distinction — it fires only for `ICEBERG_COMMIT_ERROR`, safe because Iceberg commits are atomic. Retry safety depends on the format having a commit protocol.

---

## Snapshot

`snapshots/snp_highway.sql` keeps SCD history of `dim_highway` using the `timestamp` strategy on `loaded_at`.

It is **Iceberg** (`table_type='iceberg'`), and that is a requirement rather than a preference: snapshots need update support, and plain Parquet-on-S3 has none. It writes to `s3://der-sp-bucket/snapshot/` in schema `dbt_der_snapshots`.

Its purpose in this project is to demonstrate the judgment — when a snapshot is the right tool, why the highway reference table is the candidate, and what the format constraint costs.

---

## Data quality tests

The approach splits by intent:

**Thresholds, for noise that is a property of the published data.** These use `severity='warn'` or a `warn_if`/`error_if` pair, and are points of attention rather than gates:

| Test | Asserts |
|---|---|
| `tests/staging/stg_assert_incidents_km_unmatched_highways_km.sql` | Share of incidents whose km falls outside any highway segment stays ≤ 1% |
| `tests/raw/raw_assert_incidents_closing_before_opening.sql` | Closing before opening in the raw source: warns above 0, errors above 10 |

**Invariants, for things that should never happen.** These fail hard:

| Test | Asserts |
|---|---|
| `tests/staging/stg_assert_incidents_closing_before_opening.sql` | No row with `close_at < open_at` after staging |
| `tests/staging/stg_incidents_code_unmatched_highways_code.sql` | Unmatched highway codes stay under 5% |

Plus the generic test `macros/tests/empty_model.sql` (`macro_empty_model`), reusable for asserting a model isn't empty, and column-level tests declared in each model's `.yml` (`not_null`, `unique`, and `dbt_utils.expression_is_true`).

A note on the convention, because it's easy to break when refactoring: **a singular test signals failure by returning a row.** `macro_empty_model` returns a row only when the model has none (`having count(*) = 0`); the threshold tests return a row only once the threshold is crossed. That row-on-failure logic must stay in the test — it can't move into a shared macro.

---

## The marts

Every column is described in the model's own `.yml`, alongside the tests that guard it, and `dbt docs generate` publishes that as a browsable site (the pipeline workflow deploys it to GitHub Pages). What follows is what a column list *doesn't* tell you: the grain of each table, and the decisions baked into it.

### `mart_incident_type_pareto`

**Grain:** one row per incident type — but only those inside the cumulative 80%. Rows past the cut are filtered out, so the table is the answer rather than the raw material for it.

**Excluded categories.** Five operational record types are dropped as not being incidents in the analytical sense: `Informação da Posição em Campo`, `Fiscalização geral (especificar)`, `Conservação / Obras na pista`, `Materiais Diversos fora da pista`, `Não localizado`. This is a domain judgment and it moves the ranking — worth revisiting if the question being asked changes.

**Technical note.** The running total and the grand total come from two window functions over the same pass — `sum(...) over (order by ranking rows between unbounded preceding and current row)` and `sum(...) over ()` — so the cumulative percentage needs no self-join or second aggregation.

### `mart_incidents_daily_by_highway`

**Grain:** one row per highway per calendar day, for every year present in the incident data.

**`qty_incident_count` is zero, never null**, on days with nothing recorded. This is the entire reason the model builds a spine (`dim_calend` × `dim_highway`) and left joins counts onto it, instead of aggregating incidents directly. A plain aggregation would omit quiet days, which silently breaks any average, moving window or trend computed downstream — a zero has to be a fact, not a missing row.

**The spine is scoped, not the full calendar.** `dim_calend` covers 2025–2030, but the model narrows it to the min/max year actually present in incidents, so the table doesn't carry future dates padded with zeros.

**Technical note on the holiday flag.** `fl_holiday` is a string `'1'`/`'0'`, and `holiday_description` is non-null exactly when the flag is set. Those two come from a left join in `dim_calend` and could drift apart silently, so the relationship is asserted by a `dbt_utils.expression_is_true` test rather than left to convention.

**Full refresh, not incremental**, and partitioned by `year_ref` — the spine has to be rebuilt whenever the incident date range grows.

### `mart_incident_summary`

**Grain:** a single row — headline metrics meant to be read as-is.

**Technical note on the averages.** `avg_incidents_daily` divides by the *observed* range (`date_diff` between the first and last incident, inclusive), not by a fixed 365, so the figure stays meaningful while a year is still incomplete. The per-segment and per-city averages divide by distinct counts drawn from `core_incidents` — which only holds incidents — so they read as "per **impacted** segment/city". A highway that recorded nothing doesn't dilute them, which is the opposite convention from the daily mart above and deliberate in both cases.

---

## Setup

```bash
python3 -m venv .venv
source .venv/bin/activate
pip install dbt-athena-community
dbt deps
```

`profile.yml` at the repo root is the **single definition of the environment**, shared by local runs and both CI workflows. Copy it into place rather than writing a new one:

```bash
mkdir -p ~/.dbt
cp profile.yml ~/.dbt/profiles.yml   # merge instead if that file already holds other projects
dbt debug
```

It carries no credentials. `aws_profile_name` is the one knob to change when reproducing: point it at your own named AWS profile in `~/.aws/credentials`. `dbt debug` validates the profile and runs a real connection test against Athena.

## Running

Full pipeline, with logs in `logs/` and the last 20 log lines echoed on failure:

```bash
./run_dbt_pipeline.sh
```

It runs `dbt deps`, then the four targeted invocations in order, aborting on the first failure. A failing `dbt test` stops the run **before** the snapshot: snapshots are append-only history, and persisting SCD rows built from rejected data is painful to undo.

Useful individual commands:

```bash
dbt run --select stg_incidents --target prod
dbt run --select core_incidents+ --target prod   # model and everything downstream
dbt test --select stg_incidents --target prod
dbt debug                                        # validate connection and profile
dbt clean                                        # wipes target/ and dbt_packages/ — rerun dbt deps after
```

## CI

Two workflows in `.github/workflows/`, both **`workflow_dispatch` only**:

| Workflow | Does |
|---|---|
| `dbt_pipeline.yml` | Full pipeline: `deps` → `seed` → `run` → `test` → `snapshot` → `docs generate`, then publishes dbt docs to GitHub Pages |
| `dbt_tests.yml` | `dbt test` only — a data quality monitor |

They are split because a build and a monitor want different failure semantics: a build shouldn't abort over data-quality noise, while a monitor's whole job is to surface it.

Neither runs automatically. With no environment isolation, an automatic run would overwrite the project's only copy of the data, so every execution is a deliberate act. Being test-only, `dbt_tests.yml` never writes and could safely be put on a schedule.

Both copy the repo's `profile.yml` instead of declaring their own, and write a `[default]` AWS profile into the runner from the `DBT_ENV` secret — giving the runner the same shape as a developer machine.

> Note: the `workflow_dispatch` button only appears once the workflow file is on the default branch.

## Visualization

No dashboards have been built. The marts are queryable directly in Athena, and a BI tool can be pointed at the Glue catalog schema `dbt_der_marts` to build visualizations as a later step — the three marts are shaped for it, being pre-aggregated and small. The repo carries a `metabase/` folder with a Docker Compose setup for that eventual step, unused so far.

---

## Project structure

| Path | Contents |
|---|---|
| `models/` | Transformations, in `staging/`, `dimensions/`, `core/`, `marts/` |
| `snapshots/` | SCD history (`snp_highway`) |
| `seeds/` | Tab-separated CSVs generated by `scripts/` — not hand-edited |
| `scripts/` | Python extraction from the open data sources |
| `tests/` | Singular data quality tests, by layer |
| `macros/` | Reusable Jinja, including the generic test in `macros/tests/` |
| `analyses/` | Ad hoc exploratory SQL |
| `files/` | Support files, gitignored because `scripts/` regenerates them — except `calend.xlsx`, which is a hand-built input nothing can regenerate and is therefore versioned |
| `metabase/` | Docker Compose setup for a future visualization step — no dashboards built |
| `constitution/` | Why the project is built this way |
| `profile.yml` | The environment definition — copy to `~/.dbt/profiles.yml` |
| `run_dbt_pipeline.sh` | Local pipeline runner |

## Where the rationale lives

`constitution/` holds the decisions behind the code, and is the place to look before changing something that seems odd:

| File | Contents |
|---|---|
| [mission.md](constitution/mission.md) | Why the project exists, what "done" means, non-goals |
| [tech-stack.md](constitution/tech-stack.md) | The tools and why each was chosen |
| [principles.md](constitution/principles.md) | S3 layout, retry policy, testing conventions, the single environment |
| [workflow.md](constitution/workflow.md) | Branching, commits, and the push boundary |
