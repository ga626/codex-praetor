# Codex Praetor Architecture

Codex Praetor is a thin orchestration layer, not a second brain.

Codex decides what should happen. Codex Praetor gives Codex reliable tools to dispatch bounded work to cheaper external agents, wait for completion at the process level, and read structured job state.

## Roles

Codex owns:

- decomposition,
- worker selection,
- permission and cost decisions,
- final diff review,
- test selection,
- merge or reject decisions.

External workers own:

- scoped readonly archaeology,
- small isolated edits,
- focused tests,
- candidate findings,
- concise final reports.

Codex Praetor owns:

- command construction,
- model allowlists,
- worktree creation,
- project-local artifacts,
- background watcher process,
- completion files,
- repository edit locks,
- MCP tool surface.

## Current Script Layer

The script layer is already functional enough for dry-runs and smoke validation.

Core scripts:

- `scripts/dispatch/invoke-codex-praetor.ps1`
- `scripts/dispatch/watch-codex-praetor-job.ps1`
- `scripts/dispatch/manage-codex-praetor-plan.ps1`
- `scripts/dispatch/notify-codex-praetor-completion.ps1`

The current project artifact root defaults to:

```text
<project>\.codex-praetor
```

Worker git worktrees, jobs, plans, locks, and scratch files live under that ignored runtime root. They do not create sibling folders next to the project checkout.

## MCP Layer

The first MCP version is intentionally thin. It calls the existing scripts instead of reimplementing dispatch.

Implemented v0 tools:

- `codex_praetor_route_intent`
- `codex_praetor_list_jobs`
- `codex_praetor_plan`
- `codex_praetor_dispatch_dry_run`
- `codex_praetor_status`

Later tools:

- `codex_praetor_dispatch`
- `codex_praetor_collect`
- `codex_praetor_finalize`
- `codex_praetor_list_locks`

## Plugin Layer

The plugin bundles:

- the `codex-praetor` skill,
- MCP configuration,
- install metadata,
- default prompts,
- user-facing product copy.

Source folders and final package folders are intentionally separate:

```text
skill/    source skill
scripts/  source dispatch scripts
mcp/      MCP server source
plugin/   final Codex plugin package shape
```

The source MCP package lives in `mcp/`. Build output under `mcp/dist/` is ignored. The plugin package carries `plugin/mcp/dist/server.js` as the bundled runtime. `plugin/.mcp.json` points at that bundled runtime with `cwd = "."`; native Codex verification must be done in a refreshed tool context because an already-open thread can keep a stale closed transport.

The active tree stays shallow on purpose. Future generated release bundles should be build outputs, not the place where agents edit source.

## Local Install Boundary

There are three copies with different jobs:

- `skill/codex-praetor`: source skill for development.
- `plugin/skills/codex-praetor`: package copy for future Codex plugin distribution.
- `%USERPROFILE%\plugins\codex-praetor`: local installed plugin package that Codex discovers through the personal marketplace entry.

The installed plugin must be updated by real file copy, not by path redirection. This keeps local Codex behavior independent from half-finished development work.
