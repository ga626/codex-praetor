# Codex Praetor 0.16.7-alpha

## Changes

- The MCP PowerShell timeout path now terminates the complete child process tree on Windows before returning the timeout result. This prevents an outer timeout from being mistaken for a completed cleanup.
- Durable plan reads and writes now share a per-plan cross-process mutex and use atomic replacement. Concurrent controller, watcher, cancellation, and verification updates no longer expose partial JSON or silently overwrite one another.
- Added regressions for PowerShell child-process cleanup and two-writer plan concurrency. Both are included in the standard product test and release-candidate preflight.
- Existing structured progress and formal cancellation behavior for the already supported Qoder Agent SDK and CodeBuddy ACP paths remains unchanged; this release makes their controller-side lifecycle records more reliable.

## Validation Scope

- The MCP typecheck and full deterministic contract suite, including the new process-tree cleanup regression, must pass before packaging.
- The product validation suite must prove the two-writer plan replay preserves all events, a monotonic revision, and parseable JSON.
- The release candidate must rebuild the bundled MCP runtime and verify the staged artifact against the final commit.

## Not Included

- No new provider, credential access, provider database access, automatic merge, parallel worker routing, or production-side external action is introduced.
