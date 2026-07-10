---
name: codex-praetor
description: External worker orchestration for Codex using local Qoder/QoderWork CN, Tencent WorkBuddy/CodeBuddy, and Xiaomi MiMo Code CLIs. Trigger on natural Chinese delegation phrases like "拆分一下任务", "把任务拆一下", "分配给其他 agent", "交给其他 agent", "让别的 agent 做一部分", "多 agent 分工", "派给腾讯/阿里/小米", or "用 MiMo/Qoder/CodeBuddy". Use when Codex should split coding or research-support work into bounded tasks for external worker agents, prepare dry-run dispatch, track jobs, and verify worker outputs while Codex remains the planner.
---

# Codex Praetor

Use this skill to let Codex remain the planner, supervisor, and verifier while external agentic workers do bounded tasks through their official CLI surfaces.

This is a cross-conversation routing workflow, not only a project-local habit. If this skill is loaded because the user mentioned splitting, assigning, delegating, "other agents", multi-agent division of work, external providers, free/cheap workers, or cost-saving mode, assume the first decision is route selection:

1. Codex Praetor external workers for bounded task delegation.
2. Native Codex subagents only when the user explicitly asks for Codex subagents or accepts that fallback.
3. No worker dispatch when the task is too small, unsafe, or not inspectable.

Natural trigger phrases: prefer the user's normal delegation language, including "拆分一下任务", "把任务拆一下", "分配给其他 agent", "交给其他 agent", "让别的 agent 做一部分", "多 agent 分工", "自己去分配一下", "派给腾讯/阿里/小米", and "用 MiMo/Qoder/CodeBuddy". Do not require special cost-saving slang before choosing this route.

Important terminology boundary:

- In this skill, "other agents" usually means external worker agents such as CodeBuddy, Qoder, and MiMo unless the user explicitly says "Codex subagent".
- Do not satisfy this skill by spawning Codex subagents or additional GPT-5.5/GPT-5.x workers. Codex subagents are useful for native Codex parallelism, but they spend Codex model tokens and are not the user's intended codex-praetor route.
- If the user says "拆分任务", "把任务拆一下", "分配给其他 agent", "交给其他 agent", or similar cross-agent delegation language, first load this skill and prepare a route decision or `invoke-codex-praetor.ps1` dry-run. Only use Codex subagents when the user explicitly asks for Codex subagents or when external worker CLIs are unavailable and the user accepts that fallback.
- If the request is ambiguous but mentions delegation, external providers, cost, free quota, cheap workers, or cross-agent dispatch, resolve the ambiguity toward Codex Praetor and make the first visible action a dry-run or a short route decision. Do not silently create a native Codex subagent.

## Core Policy

- Keep Codex in charge of decomposition, final judgment, edits merge, and verification.
- Treat CodeBuddy, Qoder, and MiMo Code as worker agents, not dumb model APIs. Codex sets the goal, scope, cost/safety rails, and acceptance checks; the worker agent may plan its own internal file reads/searches/edits inside that boundary.
- Dispatch bounded, inspectable task packets: one outcome, one repo/path scope, explicit no-go areas, and a required summary/diff/test report.
- Prefer dry runs before real worker execution. Do not spend model credits unless the user asks for a real run or the task is explicitly tiny.
- Do not mutate QoderWork/WorkBuddy internal databases, auth files, caches, or desktop runtime state. Use official CLIs only.
- Treat Qoder credits as expiring in 25 days until the Usage page or `qoderclicn /usage` proves otherwise.
- Ask the user to do desktop-only actions manually when needed: QoderWork daily check-in, usage/expiration page checks, or login flows.
- Put permission decisions at the Codex layer. Worker CLIs should run non-interactively once Codex has chosen the repo, scope, mode, and worktree; do not make every worker ask the user again.
- Do not supervise in real time. Use blocking worker calls or event-driven background jobs that return one completion signal. Avoid streaming output, fixed-interval polling, and step-by-step monitoring unless diagnosing a stuck process.
- Before dispatching more than one worker, state what Codex keeps for itself and why. Codex may keep planning, integration, final verification, tiny unblockers, or high-risk cross-cutting fixes; it must not turn codex-praetor mode into "workers audit while Codex writes the main feature" without saying so and getting a clear reason.
- Separate worker waiting from local command waiting. If workers are running, use the wrapper's blocking/background completion signal. If Codex itself runs a long test or quality gate, give at most one threshold update before completion unless the user asks for status; do not repeatedly narrate "still running" every round.

## Artifact Placement

Project work should follow the current Codex project path passed as `-Repo`; do not hard-code one business repo such as KnowledgeRadar.

The wrapper derives a project artifact root from the git root when available, otherwise from the given `-Repo` path. By default it creates sibling folders next to the project, not inside the tracked source tree:

- `<project>.worktrees\<worker-worktree>` for isolated edit/read execution.
- `<project>.codex-praetor\jobs\<job_id>` for `job.json`, `stdout.log`, `stderr.log`, and `completion.json`.
- `<project>.codex-praetor\plans\<plan_id>` for durable multi-step plan state.
- `<project>.codex-praetor\locks\*.json` for per-project edit locks shared by multiple Codex conversations.
- `<project>.codex-praetor\scratch\<job_id>` or `scratch\blocking-*` for temporary files.

This means worker-created task artifacts are tied to the current project and can be reviewed or deleted as a group. Worker prompts must tell the agent to put scratch files, downloaded references, generated plans, and temporary outputs only under the execution worktree or project artifact root unless Codex explicitly allowed another path.

Do not move vendor installations, login state, or long-lived app configuration into the project artifact root. CodeBuddy, Qoder, and MiMo CLI binaries, auth, model cache, and provider profiles remain in their verified global/user locations unless a separate validation proves a per-project profile works without breaking login, free routing, or model selection.

## Hard Rails vs Soft Choices

Hard rails are fixed and must not be crossed:

- Model pools: CodeBuddy may route only `hy3`, `deepseek-v4-flash`, and `deepseek-v4-pro` by default; Qoder may route only `Qwen3.7-Plus` and `Qwen3.7-Max` by default; MiMo may route only `mimo/mimo-auto` by default.
- Do not use provider `auto` models by default.
- Do not use `hy3-preview-agent` by default; it is a known paid preview route, not the free CodeBuddy route.
- Do not use expensive/known-but-not-default models unless the user explicitly accepts the cost and the wrapper is called with the relevant override.
- Do not continue/resume old worker sessions by default.
- Edit work must use an isolated git worktree and the repo edit lock.

Soft choices are selected by Codex per task, then translated by the wrapper:

- Reasoning effort: CodeBuddy `--effort`, Qoder `--reasoning-effort`, MiMo `--variant`.
- Agent mode: e.g. MiMo `plan` for readonly/planning and `build` for worktree edits.
- Context window: mainly Qoder `--context-window`, only when the task needs it.
- Output shape: text for normal reports; JSON/schema/event-stream when Codex needs machine-checkable acceptance.

Before dispatch, Codex should briefly state why it chose the worker, model, reasoning effort, agent mode, permissions, and output format.

## Routing

Use `scripts/codex-praetor-tiers.json` as the editable source of truth for local paths, model IDs, and price notes.

Default routing:

- Beijing time 22:00-08:00: prefer Qoder `qoder-night-cheap` for normal tasks, then `qoder-night-strong` for harder tasks.
- Beijing time 08:00-22:00: prefer CodeBuddy `codebuddy-free` for normal work. This tier uses the fixed Hy3 model ID `hy3`, not `auto` and not the charged `hy3-preview-agent` route. Use Qoder daytime only when deliberately burning soon-expiring Qoder credits.
- Use MiMo `mimo-auto-readonly` for free readonly/planning or long-context exploration when it fits the task. MiMo writes `.mimocode` plan/session files even for planning, so the wrapper runs MiMo in a Codex-created worktree for both readonly and edit tasks. Verify that local `mimo stats` still reports `mimo/mimo-auto` cost as zero.
- Avoid Qoder Auto, Qoder DeepSeek/GLM/Kimi/MiniMax, CodeBuddy auto, MiMo paid/old/openai routes, and expensive nonessential models unless the user requests them.
- Do not use CodeBuddy `auto` by default. It is blocked in the wrapper because it gives model choice back to the provider. Use only the selected fixed CodeBuddy model IDs in `allowedModels`; the local CLI help list is evidence, not permission to route to every listed model.
- CodeBuddy approved default routes are `hy3`, `deepseek-v4-flash`, and `deepseek-v4-pro`. `hy3-preview-agent` is known but not default-routable; it requires explicit paid fallback approval.
- For CodeBuddy non-interactive readonly file checks on Windows, use the wrapper's verified `-y --tools Read,Glob,Grep` path. Avoid `--permission-mode plan` for real file checks; it can exceed turns or return unreliable file existence results.
- For edit tasks, isolate workers in Codex-created `git worktree` checkouts. If `-WorktreeName` is omitted, the wrapper generates one, creates the worktree, and starts the worker inside that directory.
- For multiple concurrent projects, run one worker per project lane by default. Edit tasks now take a per-repo lock by default, so another Codex conversation will not accidentally dispatch a second edit worker to the same repo. Use `-AllowConcurrentRepoEdit` only when file scopes are known not to overlap.

## Dispatch Workflow

1. Decompose the user goal into worker-sized packets. See `references/orchestration-policy.md`.
2. For each packet, choose a tier from `codex-praetor-tiers.json`.
3. Run `scripts/invoke-codex-praetor.ps1 -DryRun` first and inspect the command.
4. If a real run is appropriate, execute one packet with default `-RunMode blocking`; wait for the worker to finish and return a final report. For edit packets, use the default `-MaxTurns 8` unless the task is deliberately tiny.
5. Verify worker output yourself with file reads, tests, diffs, or targeted commands.
6. Only then send the next packet.

Do not treat `exit_code=0` as proof that the worker succeeded. Always inspect the worker's required output plus `stderr.log`, changed files, diffs, tests, and any acceptance text. A worker can exit cleanly while reporting a missing tool or producing no useful answer.

When the user asks to split work and the task is suitable for Codex Praetors, the minimum visible action is one of:

- a dry-run command for each proposed worker task, or
- a real `invoke-codex-praetor.ps1` dispatch, or
- a short reason why no CodeBuddy/Qoder/MiMo dispatch is safe for this task.

Do not merely say that work "could be split" and then do it all inside Codex.

Use `-RunMode background` when the worker should run after the current Codex turn ends. It records `job.json`, `stdout.log`, `stderr.log`, and `completion.json` under the project-local `<project>.codex-praetor\jobs\<job_id>` root unless `-JobRoot` is explicitly overridden. The wrapper starts `watch-codex-praetor-job.ps1`; that watcher starts the worker, waits for process exit, writes completion state, and releases repo edit locks. This is an OS process wait, not interval polling.

If `$env:CODEX_THREAD_ID` is present, background jobs notify the originating Codex thread through the local Codex app-server when the worker exits. Use `-NoNotify` for dry validation or when the user does not want an automatic follow-up turn.

For multi-step work, create a durable plan with `scripts/manage-codex-praetor-plan.ps1`. Use `PlanId`, `TaskId`, `DependsOn`, and `Acceptance` when dispatching background jobs. The wrapper records dispatched tasks as `running`; the watcher records worker exits as `completed`, `failed`, or `blocked` in project-local `<project>.codex-praetor\plans\<plan_id>\plan.json` unless `-PlanRoot` is explicitly overridden. This plan file is the recovery point after context compaction or when multiple worker completions arrive out of order.

## UI Visibility

The current lightweight implementation is script-based. It gives reliable local files:

- dry-run command output in the current Codex turn,
- `<project>.codex-praetor\jobs\<job_id>\job.json`,
- `stdout.log`, `stderr.log`, and `completion.json`,
- optional thread notification when the worker exits.

It does not create native Codex subagent cards. That is intentional: native subagents are Codex workers and consume Codex model tokens.

If the user wants Codex UI cards similar to KnowledgeRadar tool calls, the next product step is to wrap this worker dispatcher as an MCP server or plugin-bundled MCP server. MCP tools such as `dispatch_codebuddy_worker`, `dispatch_qoder_worker`, `dispatch_mimo_worker`, and `get_worker_job_status` would appear as tool calls in Codex. Keep that as Phase 2 because it adds a long-running service and MCP stability burden.

Recommended first probes:

```powershell
powershell -ExecutionPolicy Bypass -File "$env:USERPROFILE\.codex\skills\codex-praetor\scripts\invoke-codex-praetor.ps1" -Provider auto -Repo "<repo>" -Task "Read-only probe. Summarize the relevant files only. Do not modify anything." -Mode readonly -DryRun
```

Force Qoder during the 25-day credit-burn window:

```powershell
powershell -ExecutionPolicy Bypass -File "$env:USERPROFILE\.codex\skills\codex-praetor\scripts\invoke-codex-praetor.ps1" -Provider auto -PreferQoder -Repo "<repo>" -Task "Read-only probe. Do not modify anything." -Mode readonly -DryRun
```

## Task Packet Shape

Give workers prompts like this:

```text
Role: worker agent. Codex is supervising.
Scope: <repo/path>
Task: <single concrete goal>
Allowed: read/search only OR specific edit scope.
Forbidden: do not touch auth, caches, generated reports, unrelated files.
Output required:
1. What you did
2. Files read/changed
3. Tests or checks run
4. Risks/unknowns
```

## References

- Read `references/qoder-credits.md` when reasoning about Qoder expiration, off-peak discounts, or daily check-in.
- Read `references/codebuddy-setup.md` when CodeBuddy login, local setup, CN environment, or non-interactive `-p` authentication is relevant.
- Read `references/evidence-register.md` when the user asks why the routing, permission, worktree, no-polling, or concurrency policy is justified.
- Read `references/task-packet-template.md` when preparing prompts for repeated worker dispatch.
- Read `references/orchestration-policy.md` when splitting large projects, coordinating multiple conversations, or deciding whether to use one or two workers.

