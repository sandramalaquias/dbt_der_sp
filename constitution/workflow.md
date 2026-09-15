# Workflow

## Git & GitHub

- **Only Sandra pushes to GitHub.** Claude Code must never run `git push` — not even to a feature branch — without it being explicitly requested for that specific push. This is a standing rule for this repo, not a one-time approval.
- **Always announce a commit before making it, so Sandra can review the changes first.** Don't run `git commit` silently as part of a larger task — stop, summarize what would be committed (and show the diff/status if useful), and wait for a go-ahead. This applies every time, not just the first commit of a session.
- Claude Code may create local branches and amend its own uncommitted work freely; anything that leaves the machine (push, PR creation, GitHub Pages deploy) is Sandra's call, and every commit is announced first per the rule above.
- Current default branch: `main`. Feature work happens on branches like `der/kpis` (see current branch at time of writing).
- Opening a PR into `main` runs nothing: `.github/workflows/dbt_pipeline.yml` is `workflow_dispatch`-only by design (see [tech-stack.md](./tech-stack.md#cicd)). When it is triggered manually, it's a real cloud run against real AWS resources and billed Athena queries — and it writes to the project's only copy of the data, so treat pressing that button as touching production.

## Commit style

- Small, focused commits that track one conceptual change (one new model, one bugfix, one doc pass) — consistent with the existing history (`new kpi table - summary`, `New mart table - incident type pareto`, `fix: align dt_partition across raw, staging, and core for traceability`).

## Docs upkeep

- Three documents describe this project and each has a distinct job. **`README.md`** is for a reader arriving at the repo: scope, architecture, how to run it. **[CLAUDE.md](../CLAUDE.md)** is the as-built reference for AI agents working in the code — commands and mechanics, kept terse. This **`constitution/`** folder holds the *why*, including decisions that look like oversights until you know the reason.
- A decision that changes usually touches more than one of them. Update all that apply, not just the nearest — this repo has already had documentation outlive what it described.
