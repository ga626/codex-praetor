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

- `scripts/invoke-codex-praetor.ps1`
- `scripts/watch-codex-praetor-job.ps1`
- `scripts/manage-codex-praetor-plan.ps1`
- `scripts/notify-codex-praetor-completion.ps1`

The current project artifact root defaults to:

```text
<project>.codex-praetor
```

## MCP Layer

The first MCP version is intentionally thin. It calls the existing scripts instead of reimplementing dispatch.

Detailed v0 plan: [mcp-v0-thin-wrapper-plan.md](mcp-v0-thin-wrapper-plan.md).

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

## Planned Plugin Layer

The plugin will bundle:

- the `codex-praetor` skill,
- MCP configuration,
- install metadata,
- default prompts,
- user-facing product copy.

Development and final package paths are intentionally separate:

```text
skill/    source skill used while developing
scripts/  source dispatch scripts
mcp/      future MCP server source
plugin/   final Codex plugin package shape
```

The source MCP package lives in `mcp/`. Build output under `mcp/dist/` is ignored. The plugin's `plugin/.mcp.json` still stays disabled until a local Codex tool-card verification is completed.

The active tree stays shallow on purpose. Future generated release bundles should be build outputs, not the place where agents edit source.

## Local Publish Boundary

There are three copies with different jobs:

- `skill/codex-praetor`: source skill for development.
- `plugin/skills/codex-praetor`: package copy for future Codex plugin distribution.
- `%USERPROFILE%\.codex\skills\codex-praetor`: local installed skill that Codex actually loads.

The installed skill must be updated by real file copy, not by path redirection. This keeps local Codex behavior independent from half-finished development work.
