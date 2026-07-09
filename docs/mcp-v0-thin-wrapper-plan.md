# Codex Praetor MCP v0 Thin Wrapper Plan

Date: 2026-07-09

## Goal

MCP v0 should expose Codex Praetor as visible Codex tool cards without replacing the script layer. The existing PowerShell scripts remain the source of truth for provider selection, model rails, artifact roots, worktree naming, dry-run command construction, and future dispatch behavior.

## Non-Goals

- Do not implement real worker dispatch in v0.
- Do not create a generic multi-agent platform.
- Do not spawn Codex subagents.
- Do not add automatic D-drive to C-drive skill sync.
- Do not mutate Qoder, CodeBuddy, or MiMo internal databases, caches, or auth state.
- Do not enable `plugin/.mcp.json` until the server exists and is verified.

## Tool Surface

### `codex_praetor_route_intent`

Purpose: make the routing decision visible before dispatch.

Inputs:

- `request` string, required, the user's delegation request.
- `repo` string, optional.
- `allow_native_codex_subagents` boolean, default `false`.

Behavior:

- Classify the request as `codex_praetor_external_worker`, `native_codex_subagent`, `no_delegation`, or `needs_clarification`.
- Treat cost-saving, free/cheap worker, Qoder, CodeBuddy, WorkBuddy, Tencent, Alibaba, Xiaomi, MiMo, and ambiguous "other agent" delegation as Codex Praetor unless native Codex subagents are explicit.
- Return a compact route decision and suggested next MCP/tool action.
- Do not dispatch workers.

### `codex_praetor_list_jobs`

Purpose: summarize project-local job state.

Inputs:

- `repo` string, optional, defaults to current workspace when the host supplies it.
- `status` string, optional filter: `active`, `completed`, `failed`, `all`.
- `limit` integer, optional, default `20`.

Behavior:

- Resolve the project artifact root the same way the script layer does.
- Read `<project>.codex-praetor/jobs`.
- Return compact metadata only: job id, provider, tier, mode, run mode, state, created/updated timestamps, and path.
- Do not dump full logs.

### `codex_praetor_plan`

Purpose: create or inspect a small durable plan using the existing plan script.

Inputs:

- `repo` string.
- `title` string.
- `tasks` array of bounded task descriptions.
- `mode` string: `readonly` or `edit`.

Behavior:

- Call `scripts/manage-codex-praetor-plan.ps1`.
- Return plan id, plan path, and task ids.
- Keep Codex responsible for decomposition quality and acceptance criteria.

### `codex_praetor_dispatch_dry_run`

Purpose: show the exact worker command that would be run.

Inputs:

- `repo` string, required.
- `task` string, required.
- `provider` enum: `qoder`, `codebuddy`, `mimo`.
- `tier` string, optional.
- `mode` enum: `readonly`, `edit`, default `readonly`.
- `run_mode` enum: `blocking`, `background`, default `blocking`.

Behavior:

- Call `scripts/invoke-codex-praetor.ps1 -DryRun -NoNotify`.
- Parse key-value stdout into structured JSON.
- Return the command, artifact roots, selected model, policy result, and price note.
- Refuse provider `auto` in MCP v0.

### `codex_praetor_status`

Purpose: read one job or plan status.

Inputs:

- `repo` string.
- `job_id` string, optional.
- `plan_id` string, optional.

Behavior:

- If `job_id` is supplied, read the matching job folder and completion file when present.
- If `plan_id` is supplied, call/read plan state through the plan script.
- Return compact status and relevant paths.
- Never return full stdout/stderr logs by default.

## Implementation Shape

Recommended first implementation:

```text
mcp/
  package.json
  tsconfig.json
  src/
    server.ts
    paths.ts
    powershell.ts
    parse-key-value.ts
    tools/
      route-intent.ts
      list-jobs.ts
      plan.ts
      dispatch-dry-run.ts
      status.ts
```

The server can use the official MCP TypeScript SDK and run through Node. Keep PowerShell calls centralized in `powershell.ts` so quoting, timeout, stdout limits, and error normalization are handled in one place.

## Safety Defaults

- v0 tools are readonly or dry-run only.
- Tool output must be compact and structured.
- PowerShell calls should use `-NoProfile -ExecutionPolicy Bypass`.
- Set a command timeout.
- Cap stdout/stderr captured from child processes.
- Validate that `repo` exists before calling scripts.
- Keep runtime outputs project-local.
- Keep `plugin/.mcp.json` disabled until manual verification passes.

## Verification

Minimum checks before enabling MCP in the plugin package:

1. `powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\test-codex-praetor.ps1`
2. `npm test` or equivalent MCP unit tests.
3. `codex_praetor_route_intent` routes cost-saving "other agent" prompts to Codex Praetor and routes explicit "Codex subagent" prompts away from Codex Praetor.
4. `codex_praetor_dispatch_dry_run` returns the same key fields as the direct script dry-run.
5. `codex_praetor_list_jobs` handles an empty job directory without error.
6. `codex_praetor_status` gives a clear not-found result for an unknown job id.
7. `plugin/.mcp.json` is enabled only after local tool-card verification succeeds.

## First Implementation Order

1. Add MCP package skeleton under `mcp/`.
2. Implement route-intent classification first.
3. Implement path resolution and script invocation helpers.
4. Implement `codex_praetor_dispatch_dry_run`.
5. Implement `codex_praetor_list_jobs` and empty-state behavior.
6. Implement `codex_praetor_status`.
7. Add `codex_praetor_plan` after confirming the existing plan script interface.
8. Wire `plugin/.mcp.json` to the built server, still disabled.
9. Verify tool cards in Codex, then decide whether to flip `enabled` for local testing.
