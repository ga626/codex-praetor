# ADR-0004: Local Task Governance for 0.4.0-alpha

## Status

Accepted for implementation on `codex/task-governance-0-4-0`.

## Decision

Codex Praetor keeps Codex as planner, supervisor, integrator, and final verifier. It does not introduce a second LLM supervisor, a Temporal service, an A2A HTTP server, or worker group chat.

The local control plane adopts A2A-inspired task, context, artifact, and lifecycle semantics:

```text
goal context -> logical task -> immutable attempt -> artifacts -> supervisor verdict -> outcome
```

`completed` means an accepted logical-task outcome only. A worker process exit is recorded separately and never unblocks a dependent task. Attempts are immutable after a terminal execution state; a retry or refinement creates a new attempt linked to the same logical task.

## State Model

Execution state: `draft`, `queued`, `running`, `cancel_requested`, `process_exited`.

Evidence state: `report_valid`, `artifact_valid`, `tests_passed`, `evidence_missing`.

Governance state: `awaiting_supervisor`, `accepted`, `rejected`, `retryable`, `blocked`, `needs_decision`.

The watcher is the single writer of an attempt execution terminal state. Cancellation records a request event; it must not overwrite an existing artifact or terminal completion.

## Collaboration Policy

Sequential execution is the default for a shared write set or a dependent acceptance criterion. Parallel edit attempts require non-overlapping normalized write sets and separate owners. Handoff is selected only by an explicit retry policy and failure class. Loops require a maximum attempt count, time budget, and stop-loss action.

## Contracts and Evidence

Every edit attempt records its base commit, write set, mode, acceptance criteria, timeout, budget, and required final report. Worker text is supporting evidence. Diff scope, tests, structured artifacts, and the supervisor verdict are authoritative.

The local ledger writes append-only events and uses a revisioned projection with a lock and unique temporary files. It can read legacy `codex-praetor-plan/v1` plans without treating their historical `completed` process state as an accepted logical outcome.

Usage or provider cost is recorded only when supplied by the provider; otherwise it is `unknown`. Account databases, tokens, cookies, and screenshots are never read.

## Product Boundary

MCP remains the Codex tool surface. A2A concepts are local schema semantics, not a network server. Existing stage/activate/retirement and fresh-context boundaries remain unchanged. This contract changes the MCP-visible task state and therefore targets `0.4.0-alpha` with a fresh-context proof before release activation.

