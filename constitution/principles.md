# Principles

Conventions specific to this repo, worth keeping consistent as it grows. General software-engineering practice isn't repeated here — see [CLAUDE.md](../CLAUDE.md) for the current architecture these principles produced.

## Modeling

- **Staging is the Portuguese/English boundary.** Source column names (`"abertura"`, `"rodovia"`, ...) stay quoted and untouched only inside `stg_*` models. Everything downstream — dimensions, core, marts — uses English snake_case. Don't let a raw Portuguese column name leak past staging.
- **Materialize deliberately, not by default.** The project-level default per layer (`dbt_project.yml`) is a starting point; override it at the model level with a comment-worthy reason (e.g. `core_incidents` is incremental because the source is large and append-only; `dim_highway` is a table because it's small and read often). When overriding, prefer being explicit in the model's own `config()` over changing the shared default, so the exception is visible where it happens.
- **Partition incremental models by `dt_partition`**, and diff against `"{{ this.identifier }}$partitions"` rather than a `max(loaded_at)` style filter — this is the pattern already used in `stg_incidents` and `core_incidents`; keep new incremental models consistent with it unless there's a specific reason not to.
- **The km-range highway-match join is logic, not a one-off.** It appears in `core_incidents.sql` and is mirrored in `tests/staging/stg_assert_incidents_km_unmatched_highways_km.sql` to measure the match rate. If this predicate changes, change it in both places (or extract it into a macro — not done yet, worth doing if a third copy is ever needed).

## Testing

- Prefer a **singular test that measures a rate with a threshold** (`severity='warn'`, `warn_if`/`error_if`, or a `having pct > x`) over a strict "zero mismatches" test when the data source is real-world and expected to have some noise (see the two `unmatched_highways` tests). Reserve hard failures for invariants that should never break (e.g. `close_at < open_at`).
- A generic test belongs in `macros/tests/` (see `macro_empty_model`) once the same check is needed on more than one model; otherwise keep it as a singular SQL test under `tests/`.

## Documentation

- Every model should have a matching `.yml` alongside it (already the pattern for every model in `models/`) — keep this up even for quick experiments, since the point of the project is partly to practice writing good dbt docs.
- When the root `README.md` and `readme_new.md` disagree, treat the discrepancy as a signal that `README.md` needs to be reconciled or replaced, not that `readme_new.md` is wrong — see [workflow.md](./workflow.md).
