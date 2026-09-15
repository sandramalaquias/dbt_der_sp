# Mission

## Why this project exists

This is a personal hands-on project to learn dbt in a realistic setting — end to end, against a real cloud data stack (AWS), not a toy/local warehouse. DER-SP's public highway incident data was picked because it's real, free, messy enough to require actual staging/cleaning decisions, and large enough (~268k incident records) to make materialization and partitioning choices actually matter.

The artifacts here double as a **demonstration**: each dbt concept is present to show *when, how and why* to use it, not because an operational requirement forced it. The snapshot is the clearest example — it exists to demonstrate judgment about snapshots, not because anyone needs SCD history of the highway table. **This should bias design decisions toward legibility and documented rationale over operational cleverness** — prefer showing a concept plainly in the file where it happens over abstracting it into shared plumbing that demonstrates nothing.

## What "done" looks like

There's no fixed ship date or external stakeholder — "done" is a moving target defined by which dbt/analytics-engineering concepts have been exercised hands-on. So far that includes:

- Layered modeling (staging → dimensions → core → marts)
- Materialization choices — `table` vs `incremental`, and when each applies. The project ended up with no views at all, which is itself the finding: on Athena a view saves no storage but re-scans on every read, so the cost lands on the consumer.
- Incremental strategies against a non-native-incremental engine (Athena), including manual partition-diffing via `"{{ this.identifier }}$partitions"`
- Snapshots or SCD tracking (`snapshots/snp_highway.sql`), including the Iceberg-vs-Parquet tradeoff on Athena
- Seeds fed by a real (if lightweight) ingestion process
- Custom singular tests for data-quality guardrails (join-match rates, date sanity), plus a reusable macro-based test
- CI (GitHub Actions) standing in for an orchestrator — building the project and publishing `dbt docs`

Still open, not yet exercised:

- A BI layer consuming the marts. `metabase/docker-compose.yml` is in place, but no dashboards have been built.

New iterations should keep adding to this list deliberately — pick a concept, exercise it against this dataset, document the decision in [principles.md](./principles.md) if it's non-obvious.

## Non-goals

- **Not a production data platform.** No SLAs, no on-call, no need for the ingestion step to be bulletproof.
- **No IaC.** Infrastructure (S3 buckets, Athena workgroup, Glue catalog/crawler) is provisioned manually / out of band. Terraform was considered and deliberately dropped — see `readme_new.md` — because provisioning it properly would be overhead unrelated to learning dbt.
- **No production-grade ingestion.** The Python extraction scripts (`scripts/get_*.py`) are intentionally simple, manually-triggered, local scripts — not a Lambda/Step Functions pipeline. This keeps the project's focus on dbt itself.
- **Not optimizing for "correct" analytics.** Business logic (Pareto threshold, km-range highway matching, etc.) is good enough to be realistic, not rigorously validated against ground truth.
