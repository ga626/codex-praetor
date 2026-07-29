# Codex Praetor 0.16.5-alpha

## Changes

- Qoder Agent SDK and CodeBuddy ACP now supervise work by structured progress, a stall timeout, formal cancellation, and terminal evidence rather than a fixed turn count.
- A stalled SDK session uses `AbortController`; a stalled ACP session uses `session/cancel`. Both retain a classified terminal record for Codex review and cold recovery.
- The task ledger and MCP dispatch contract now accept a progress-stall budget while retaining `max_turns` only for historical compatibility.
- A first real task may create traceable evidence only through a frozen Codex plan; later normal dispatch still requires current readiness and qualified evidence for the exact provider tuple.
- Windows PowerShell UTF-8 BOM ledger parsing now preserves valid evidence instead of classifying it as malformed.

## Validation Scope

- This version is not published until the final dual-provider real code-change matrix, independent grading, candidate artifact validation, and release workflow all pass.

## Not Included

- No new provider, credential access, provider database access, automatic merge, or production-side external action is introduced. This release does not promise that every model, account, or provider tuple is ready for code changes.
