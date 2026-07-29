# Codex Praetor 0.16.6-alpha

## Changes

- Qoder Agent SDK and CodeBuddy ACP share the supervised real-dispatch path. Codex reads structured progress, stall state, formal cancellation, and terminal evidence before it evaluates a worker result.
- Fixed durable plan creation so every declared allowed path, forbidden path, required check, and immutable path is preserved exactly in the PowerShell ledger.
- Fixed the plan response so `task_ids` returns the actual durable task identifiers that `codex_praetor_dispatch_plan_task` accepts.
- Added a multi-path round-trip regression covering the returned task ID and every persisted scope field.
- Fixed Windows-safe durable completion writes for cancellation, watcher, and plan-ledger records so an existing target file cannot break the lifecycle check on a hosted Windows runner.

## Validation Scope

- The MCP typecheck and full deterministic contract suite must pass before release packaging.
- The release candidate must rebuild the bundled MCP runtime and verify the staged artifact against the final commit.

## Not Included

- No new provider, credential access, provider database access, automatic merge, or production-side external action is introduced.
