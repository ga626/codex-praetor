---
name: codex-praetor
description: External worker orchestration for Codex using Qoder and Tencent CodeBuddy CLI workers. Use for bounded task delegation, dry-run dispatch, job tracking, and supervised acceptance.
---

# Codex Praetor

Codex is the planner, supervisor, integrator and final verifier. Qoder and CodeBuddy are bounded external workers, not native Codex subagents and not final authorities.

## Dispatch contract

1. Choose a single inspectable outcome, explicit repository scope, allowed paths, forbidden paths, required checks and acceptance evidence.
2. Use the project wrapper's `-DryRun` first. Select Qoder or CodeBuddy explicitly; provider auto models are not permitted.
3. Real worker work runs in a disposable Git worktree. Code-change work takes the per-repository edit lock.
4. Use blocking completion or the wrapper's background completion record. Do not stream-poll a worker.
5. Inspect the completion, logs, worktree diff and required checks yourself. Process exit is never acceptance.

## Safety boundary

- Use official CLIs and existing login state only. Never read, copy, print or alter authentication files, cookies, tokens, provider databases or caches.
- A worktree protects the project checkout, not the operating system. Give workers only the task scope they need.
- External research remains Codex plus KnowledgeRadar work. A worker can contribute only traceable, supervisor-reviewed candidate evidence under an explicit readonly research contract.
- If a provider rejects a request, times out, exceeds turns, emits no usable output or leaves a partial diff, record that terminal state and stop. Do not silently retry or call it success.

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

For multi-step work, use the durable plan file. Only Codex's explicit accepted verdict unlocks a dependent task.
