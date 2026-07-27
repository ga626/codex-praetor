---
name: codex-praetor
description: External worker orchestration for Codex using Qoder and Tencent CodeBuddy CLI workers. Use for staged isolated task delegation, dry-run dispatch, checkpoint tracking, and supervised acceptance.
---

# Codex Praetor

Codex is the planner, supervisor, integrator and final verifier. Qoder and CodeBuddy are bounded external workers, not native Codex subagents and not final authorities.

## Dispatch contract

1. Choose a stage result that can be independently inspected, explicit repository scope, hard forbidden paths, required checks and acceptance evidence. A stage may span multiple files and ordinary local exploration; it is not required to be a one-file task.
2. Use the project wrapper's `-DryRun` first. Select Qoder or CodeBuddy explicitly; provider auto models are not permitted.
3. Real worker work runs in a disposable Git worktree. Code-change work takes the per-repository edit lock.
4. Use blocking completion or the wrapper's background completion record. Prefer deterministic checkpoint/event collection over stream-polling a worker or repeatedly asking Codex to read logs.
5. Inspect the completion, logs, worktree diff and required checks yourself. Process exit is never acceptance.

## Safety boundary

- Use official CLIs and existing login state only. Never read, copy, print or alter authentication files, cookies, tokens, provider databases or caches.
- A worktree protects the project checkout, not the operating system. Permit ordinary work inside the approved isolated source area, but keep auth, provider databases, secrets, user configuration, production, publishing and irreversible external actions forbidden.
- External research remains Codex plus KnowledgeRadar work. A worker can contribute only traceable, supervisor-reviewed candidate evidence under an explicit readonly research contract.
- If a provider rejects a request, times out, emits no usable output or leaves a partial diff, record that terminal state and stop. A turn-limit observation is a diagnostic event, not proof that the worker is incapable or that a partial diff is accepted. Do not silently retry or call it success.

## Routing

- During Beijing daytime, use CodeBuddy `codebuddy-free` with model `hy3` for normal bounded work.
- During Beijing off-peak, prefer Qoder `qoder-night-cheap`; use `qoder-day-cheap` only when deliberately selected.
- Qoder models are limited to `Qwen3.7-Plus` and `Qwen3.7-Max`; CodeBuddy models are limited to `hy3`, `deepseek-v4-flash` and `deepseek-v4-pro`.

## Required worker packet

```text
Role: supervised worker.
Scope: <repository and allowed paths>
Task: <one concrete outcome>
Forbidden: auth, caches, unrelated files, generated reports.
Return: summary, files read/changed, checks run, risks or unknowns.
```

For multi-step work, use the durable plan file. Continue only while new evidence advances the current stage; repeated errors, no new acceptance evidence, a risk event or a requested input cause checkpoint review. Only Codex's explicit accepted verdict unlocks a dependent task.
