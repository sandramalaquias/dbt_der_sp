# Workflow

## Git & GitHub

- **Only Sandra pushes to GitHub.** Claude Code must never run `git push` — not even to a feature branch — without it being explicitly requested for that specific push. This is a standing rule for this repo, not a one-time approval.
- **Always announce a commit before making it, so Sandra can review the changes first.** Don't run `git commit` silently as part of a larger task — stop, summarize what would be committed (and show the diff/status if useful), and wait for a go-ahead. This applies every time, not just the first commit of a session.
- Claude Code may create local branches and amend its own uncommitted work freely; anything that leaves the machine (push, PR creation, GitHub Pages deploy) is Sandra's call, and every commit is announced first per the rule above.
- Current default branch: `main`. Feature work happens on branches like `der/kpis` (see current branch at time of writing).
- Opening a PR into `main` runs nothing: `.github/workflows/dbt_pipeline.yml` is `workflow_dispatch`-only by design (see [tech-stack.md](./tech-stack.md#cicd)). When it is triggered manually, it's a real cloud run against real AWS resources and billed Athena queries — and it writes to the same S3 paths and Glue schema the dashboards read, so treat pressing that button as touching production.

## Commit style

- Small, focused commits that track one conceptual change (one new model, one bugfix, one doc pass) — consistent with the existing history (`new kpi table - summary`, `New mart table - incident type pareto`, `fix: align dt_partition across raw, staging, and core for traceability`).

## Docs upkeep

- `README.md` (root) is currently stale relative to the actual models (see [principles.md](./principles.md)); `readme_new.md` is the accurate draft. Until they're reconciled, prefer `readme_new.md` and this `constitution/` folder over `README.md` for anything architectural.
- [CLAUDE.md](../CLAUDE.md) documents the current, as-built architecture and commands for AI agents working in this repo. This `constitution/` folder documents the *why* behind that architecture and the collaboration rules — update both when a decision changes, not just one.
