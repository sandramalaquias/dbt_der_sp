# Principles

Conventions specific to this repo, worth keeping consistent as it grows. General software-engineering practice isn't repeated here — see [CLAUDE.md](../CLAUDE.md) for the current architecture these principles produced.

## Modeling

- **Staging is the Portuguese/English boundary.** Source column names (`"abertura"`, `"rodovia"`, ...) stay quoted and untouched only inside `stg_*` models. Everything downstream — dimensions, core, marts — uses English snake_case. Don't let a raw Portuguese column name leak past staging.
- **Materialize deliberately, not by default.** The project-level default per layer (`dbt_project.yml`) is a starting point; override it at the model level with a comment-worthy reason (e.g. `core_incidents` is incremental because the source is large and append-only; `dim_highway` is a table because it's small and read often). When overriding, prefer being explicit in the model's own `config()` over changing the shared default, so the exception is visible where it happens.
- **Partition incremental models by `dt_partition`**, and diff against `"{{ this.identifier }}$partitions"` rather than a `max(loaded_at)` style filter — this is the pattern already used in `stg_incidents` and `core_incidents`; keep new incremental models consistent with it unless there's a specific reason not to.
- **The km-range highway-match join is logic, not a one-off.** It appears in `core_incidents.sql` and is mirrored in `tests/staging/stg_assert_incidents_km_unmatched_highways_km.sql` to measure the match rate. If this predicate changes, change it in both places (or extract it into a macro — not done yet, worth doing if a third copy is ever needed). If extracted, the macro should only produce the **boolean ON-clause predicate** (drop-in for both the inner `join` in `core_incidents.sql` and the `left join` in the test) — it must not absorb the test's own aggregation/threshold logic, which is what makes the test return a row on failure (see below).

## Targets & S3 layout

- **The three profile targets (`prod`, `seed`, `snapshot`) are load-bearing, not redundant.** Their `s3_data_dir` values must stay on separate, non-overlapping S3 prefixes — overlapping locations make Athena/Glue read the wrong data or fail outright, since an external table's location must not contain another table's files.
- **Do not change the S3 paths in `profile.yml`.** They are validated by having been run; treat them as fixed infrastructure, not as configuration to tidy. In particular, do not "simplify" a path that looks unused — see the snapshot case below.
- Which mechanism decides a location depends on the resource, and the distinction is easy to get wrong:
  - **Models pin their own `external_location`** — every one does today (`staging/`, `core/`, `dimension/`, `marts/` under `der-sp-bucket`). `generate_s3_location` in the adapter returns `external_location` when set, so for them it wins.
  - **Seeds cannot pin a location** (`dbt_project.yml` sets only `+file_format` and `+delimiter`), so they land wherever the target's `s3_data_dir` + `s3_data_naming` say: `s3://der-sp-bucket/raw/` + `s3_data_naming: table` → `s3://der-sp-bucket/raw/raw_incidents/`, in schema `dbt_der_raw`, which is what `models/staging/sources.yml` hardcodes.
  - **The snapshot is not covered by its own `external_location` alone.** The adapter's snapshot materialization contains no location handling, so it falls back to the chain rooted in `target.s3_data_dir` — making the `snapshot` target's dedicated prefix structural. Iceberg compounds this: it manages `metadata/` and `data/` subdirectories under its location, so sharing a prefix with Hive/Parquet tables corrupts it. This is also why the snapshot must be Iceberg at all — plain Parquet-on-S3 has no update support for SCD history.
- **Never use `dbt build` in this project.** A single invocation applies one target to *all* resource types, so `dbt build --target prod` drags the seeds into the `prod` target's prefix (wrong bucket, wrong `s3_data_naming`, wrong Glue schema) and breaks the separation above. Always run the four steps explicitly, each with its own target: `dbt seed --target seed` → `dbt run --target prod` → `dbt test --target prod` → `dbt snapshot --target snapshot`. This is what `run_dbt_pipeline.sh` does, and CI must match it.

## Don't raise num_retries

- **`num_retries: 0` on the `seed` and `snapshot` targets is deliberate. Do not "fix" it** — the adapter default is 5, and 5 is wrong for this project.
- In `dbt-athena`'s `connections.py`, the `@retry` driven by `num_retries` wraps the function that *submits and executes* the query, and its predicate retries on essentially any exception (it only declines `TOO_MANY_OPEN_PARTITIONS`). A query that reaches Athena and fails raises `OperationalError(state_change_reason)`, which the retry catches — so **the whole statement is re-issued**, not just a pre-flight API call.
- That is unsafe for our incremental models, which use `incremental_strategy='append'` (an `INSERT INTO`). Hive-on-S3 has no commit protocol: files written by a dying INSERT are already visible, because the table just lists what's at the location. So a retry either re-inserts everything (**duplicates**) or, if the partial write registered the partition, gets filtered out by the `this$partitions` diff and inserts nothing (**an incomplete partition that looks complete** — silent).
- The adapter's own nested retry proves the distinction: it fires only for `ICEBERG_COMMIT_ERROR`, which is safe because Iceberg commits are atomic and a failed commit leaves nothing visible. **Retry safety depends on the format having a commit protocol**, and Hive append doesn't.
- The posture that follows: fail loudly and re-run deliberately. Given a single production environment and manual triggers, an unattended retry that might corrupt data is a worse trade than a failure you re-run by hand.

## One environment, and it is production

- **There is no test environment, by design.** A second set of S3 prefixes and Glue schemas would double the infrastructure for no demonstration value, so every run — local script or manual CI dispatch — reads and writes the project's only copy of the data.
- The target is therefore named **`prod`**, not `dev`. This is a legibility decision, not cosmetics: the previous name meant the safest-sounding label was wired to the least safe destination, and a bare `dbt run` (which falls back to the profile's default target) would quietly hit production. Now every command that touches it says `prod` out loud.
- The protection against accidents is consequently **not** isolation, which doesn't exist here. It's that runs are deliberate: CI is `workflow_dispatch`-only, and concurrent runs must be prevented, since two of them would write the same S3 prefixes at once.
- Renaming the target was safe precisely because nothing derives behaviour from it — no model, macro, snapshot or test references `target.name`. Locations come from each model's own `external_location` and schemas from the target's `schema:` key. Keep it that way: **don't branch logic on the target name**, or the single-environment premise starts leaking into the models.

## Environment reproducibility

- **Premise: whoever clones this repo must be able to reproduce the environment from it.** The repo is the definition of the environment, not just of the transformations.
- Consequence: **the profile always defines all three targets, everywhere it appears.** Don't trim it to whatever one job happens to execute — a partial profile is a partial environment, and anyone reproducing from it would find `run_dbt_pipeline.sh` broken, since the script needs all three.
- **`profile.yml` at the repo root is that single definition**, and both workflows just `cp profile.yml ~/.dbt/profiles.yml`. It carries no credentials, but it **does** declare `aws_profile_name` on purpose: that's the one knob someone reproducing the project has to change, and an explicit key states the dependency where they'll look for it. Leaving it to boto3's implicit resolution chain would work but hide it.
- Because the profile names a profile, **CI writes a real `[default]` entry into the runner's `~/.aws/credentials`** from the `DBT_ENV` secret, instead of exporting loose env vars. The runner then has the same shape as a developer machine, which is the premise above applied to CI itself.
- Verify a setup with `dbt debug` — it resolves the profile and runs a connection test against Athena.
- This replaced three separate copies of the profile, which had already drifted: the CI copy had the `seed` target on `schema: dbt_der` instead of `dbt_der_raw`, which would have sent seeds to the wrong Glue schema while models kept reading the old tables. Any new consumer of the profile copies the file — it never re-declares it.

## Testing

- **A singular test fails when its query returns any row — it never fails by returning `false` or a status column.** Both existing tests already follow this: `stg_assert_incidents_km_unmatched_highways_km.sql` returns a row only when `perc_unmatched > 0.01`; `macro_empty_model` returns a row only when the model has zero rows (via `having count(*) = 0` over the whole result, no `group by` needed since the aggregate collapses it to one row). Keep this invariant whenever a test is refactored or its logic is shared with a model — the "row on error" query must stay in the test, not move into a shared macro.
- Prefer a **singular test that measures a rate with a threshold** (`severity='warn'`, `warn_if`/`error_if`, or a `having pct > x`) over a strict "zero mismatches" test when the data source is real-world and expected to have some noise (see the two `unmatched_highways` tests). Reserve hard failures for invariants that should never break (e.g. `close_at < open_at`).
- A generic test belongs in `macros/tests/` (see `macro_empty_model`) once the same check is needed on more than one model; otherwise keep it as a singular SQL test under `tests/`.

## Documentation

- Every model should have a matching `.yml` alongside it (already the pattern for every model in `models/`) — keep this up even for quick experiments, since the point of the project is partly to practice writing good dbt docs.
- `README.md` is the single project README, and it is current. It documents the marts by **grain and by the decisions behind them**, not column by column — every column already has a description and its tests in the model's `.yml`, which `dbt docs` publishes. Don't reintroduce column tables there: the previous README's most detailed one described `mart_trechos_criticos`, a mart that no longer exists.
