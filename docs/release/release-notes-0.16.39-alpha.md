# Codex Praetor 0.16.39-alpha

## Fixes

- Qoder China `stream-json` now treats a structured `model_queue_status` event as a live provider queue rather than as a silent worker stall. Queue waiting is bounded by the task's wall-clock budget and the upstream advertised limit, so a short `max_stall_seconds` value cannot prematurely terminate an otherwise healthy queue.
- Queue receipts now record the local queue budget and the effective limit alongside Qoder's advertised queue maximum. This distinguishes a genuine provider queue timeout from a missing-heartbeat stall.
- Qoder readonly workers keep shell access closed even when the task has a supervisor-required check. Codex runs that deterministic check after the worker exits; the worker cannot append arbitrary shell commands through the `stream-json` tool protocol.

## Evidence

- The fixed `qoder_cn / supervised_cli_stream_json / Qwen3.7-Plus` tuple completed a real readonly task after more than three minutes of structured queue updates, returned the requested runtime-contract and readiness-tool facts, and left its isolated worktree clean.

## Boundaries

This version keeps Qoder China on supervised `stream-json` and CodeBuddy on ACP. It does not change provider credentials, models, authentication state, or automatic model selection.

The existing controlled process cancellation, task wall-clock limit, and terminal-evidence requirements remain in force for both worker routes.
