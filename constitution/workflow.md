# Workflow

## Git & GitHub

- **Only Sandra pushes to GitHub.** Claude Code may create local commits in this repo as part of normal work (implementing a model, fixing a test, updating docs) without asking each time, but must never run `git push` — not even to a feature branch — without it being explicitly requested for that specific push. This is a standing rule for this repo, not a one-time approval.
- Claude Code may create local branches, amend its own uncommitted work, and open local commits freely; anything that leaves the machine (push, PR creation, GitHub Pages deploy) is Sandra's call.
- Current default branch: `main`. Feature work happens on branches like `der/kpis` (see current branch at time of writing).
- A PR into `main` triggers the GitHub Actions pipeline (`.github/workflow/dbt_pipeline.yml`): full `dbt build` against Athena plus a `dbt docs` deploy to GitHub Pages. Keep that in mind before opening a PR — it's a real cloud run against real AWS resources and billed Athena queries, not a free local check.

## Commit style

- Small, focused commits that track one conceptual change (one new model, one bugfix, one doc pass) — consistent with the existing history (`new kpi table - summary`, `New mart table - incident type pareto`, `fix: align dt_partition across raw, staging, and core for traceability`).

## Docs upkeep

- `README.md` (root) is currently stale relative to the actual models (see [principles.md](./principles.md)); `readme_new.md` is the accurate draft. Until they're reconciled, prefer `readme_new.md` and this `constitution/` folder over `README.md` for anything architectural.
- [CLAUDE.md](../CLAUDE.md) documents the current, as-built architecture and commands for AI agents working in this repo. This `constitution/` folder documents the *why* behind that architecture and the collaboration rules — update both when a decision changes, not just one.
