# Codex Praetor 0.16.30-alpha

This release makes Codex Praetor's external-worker route auditable and harder to stop at route-only classification.

- `route_intent` now returns `dispatch_required`, `next_required_tool`, delegable subtasks, Codex-reserved work, and an explicit blocking reason.
- The Skill uses the Chinese trigger “执政官模式” and requires route → plan → dry-run → dispatch continuation.
- Route-only regressions cover external delegation, primary research, explicit Codex-only work, and direct local work.
- Candidate activation remains idempotent for an already verified artifact, with the same host-refresh and cache-generation guarantees as 0.16.29-alpha.
- Qoder China tasks continue to use the documented `--print --output-format stream-json` transport; cancellation is controlled process cancellation rather than an unbounded worker retry.
