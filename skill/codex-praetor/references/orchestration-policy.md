# Orchestration Policy

Use this policy when Codex delegates work to CodeBuddy, Qoder, or MiMo Code.

## Control Boundary

Codex owns planning, scope, permissions, final verification, and merge decisions. Worker agents receive a bounded task and run non-interactively after Codex has approved the scope. Avoid making every worker ask for permission again.

CodeBuddy, Qoder, and MiMo Code are worker agents, not dumb model APIs. Codex should define the goal, model/cost rails, repo scope, permission profile, and acceptance criteria. The worker agent may choose its own internal read/search/edit path inside that boundary.

Do not micromanage worker steps unless the task is deliberately tiny. Prefer task packets that state outcome, scope, allowed actions, forbidden paths, autonomy, and required report fields.

The worker boundary is not a security boundary. Use filesystem scope, git worktrees, task packets, and final verification as the real controls.

For edit tasks, the wrapper intentionally uses non-interactive approval inside a narrow tool whitelist and a Codex-created git worktree. Codex creates the linked worktree first, then starts the worker with that worktree as its working directory:

- CodeBuddy readonly: `-y --tools Read,Glob,Grep`.
- CodeBuddy: `-y --tools Read,Glob,Grep,Edit,Write,Bash` inside `<repo>\.codex-praetor\worktrees\<name>`.
- Qoder: `--permission-mode bypass_permissions --tools Read Grep Glob Edit Write Bash` with `-w <repo>\.codex-praetor\worktrees\<name>`.
- MiMo: `mimo run --model mimo/mimo-auto --agent build --format json --dir <repo>\.codex-praetor\worktrees\<name>` after Codex creates the worktree.

The wrapper does not rely on each vendor CLI's internal `--worktree` path for edit dispatch. That is intentional: official CodeBuddy docs allow direct `git worktree` creation before starting a session, and this keeps branch naming, location, cleanup, and verification under Codex control.

This is not a general trust grant. Codex must choose the repo, task packet, and worktree first, then verify the final diff and tests.

## No Real-Time Supervision

Default to blocking dispatch for short or medium work:

1. Codex sends one complete task packet.
2. The worker runs until completion, blockage, or failure.
3. The worker returns one final report.
4. Codex verifies the result.

Do not stream, poll every N seconds, or supervise step by step.

Use event-driven background dispatch when the worker should continue after Codex stops spending tokens. In background mode, Codex starts a local watcher process and then can finish the current turn. The watcher starts the worker, waits on the worker process, records `completion.json`, releases the repo lock, and optionally sends one follow-up message to the originating Codex thread through the local Codex app-server.

This watcher model is not timer polling. The machine has one waiting process, not a model loop that repeatedly asks whether the worker is done.

## Controller Lane

Before Codex dispatches multiple workers, it must write a short split of labor:

- worker-owned tasks
- Codex-owned tasks
- why each Codex-owned task should stay with Codex
- expected files or outputs per owner
- which command or review will prove the worker result is acceptable

Codex may keep these tasks:

- decomposition, routing, permissions, and final decision-making
- integration, conflict resolution, and final verification
- a small unblocker needed before workers can finish
- a high-risk cross-cutting fix that would be unsafe to delegate without more context

Codex should not keep broad implementation while workers are still running unless it explicitly declared that lane before dispatch. In codex-praetor mode, worker tasks must produce meaningful inspectable output, not just a token audit while Codex does all important edits.

Codex may continue doing local work while workers run only when that work is one of the declared controller tasks. If the remaining local work turns into the main feature, stop and either delegate a new worker packet or tell the user why the split changed.

## Long Local Commands

Distinguish two kinds of waiting:

- Worker waiting: use the worker wrapper's blocking return or event-driven background watcher. Do not poll logs or ask "done yet" in the model loop.
- Local command waiting: if Codex itself starts a long test, quality gate, package build, or server command, it may wait for the process, but it should not repeatedly narrate each wait interval. Give one start message, optionally one threshold message when the command is unusually slow, and one completion or failure message.

When a local command is likely to run for a long time, prefer one of these:

- run the narrower verification first
- use the command's own timeout or structured timeout handling
- move it behind the final verification gate after worker results are merged
- if supported, run it as a background OS process with one completion signal

## Task Size

Avoid both extremes:

- Too large: "build the whole feature" across many modules, ambiguous tests, broad architectural choices.
- Too small: "read one file", "change one line", or "run one command" repeated many times.

Good worker packet size:

- 20-90 minutes of human work, or one coherent code slice.
- Usually 3-12 files expected to be touched for edit tasks; tighten this if files are risky or shared.
- One acceptance test or one observable verification target.
- Enough context to complete without asking Codex mid-task.
- Small enough that Codex can review the final diff in one pass.

Good examples:

- "Implement the parser for this one input format and add focused tests."
- "Audit this module and produce a risk-ranked bug list, no edits."
- "Convert these three related call sites to the new helper and run the existing test target."

Bad examples:

- "Refactor the entire backend."
- "Fix all flaky tests."
- "Read this file and tell me what it does" as a repeated worker task.

## Project Lanes

Use one lane per repo or project by default. A lane is the combination of:

- Repo path
- Worker provider/tier
- Worktree or branch
- Task packet
- Verification command

For multiple projects in multiple Codex conversations, prefer one worker per project lane. Do not let two conversations assign edit work to the same repo checkout.

Before dispatching edit work, define the lane in plain terms:

- repo path
- provider/tier
- branch/worktree name
- file or directory scope
- verification command
- expected artifact or final report

If another Codex conversation is already editing the same repo, wait by default. The wrapper takes a per-repo edit lock under `%USERPROFILE%\.codex\codex-praetor-locks` before creating the worktree. For background dispatch, the lock is held by the watcher process and released when the worker exits. Use `-AllowConcurrentRepoEdit` only when file scopes are known not to overlap and Codex will merge results one at a time.

## Same-Repo Concurrency

Use two workers in one repo only when all are true:

- Each worker has a separate git worktree.
- File scopes do not overlap.
- Each task has its own verification command.
- Codex will merge results one at a time.

Readonly tasks may share the main checkout. Edit tasks must use worktrees and the default per-repo edit lock.

## Worker Selection

- Qoder off-peak `Qwen3.7-Plus`: default cheap coding worker for normal tasks.
- Qoder off-peak `Qwen3.7-Max`: harder tasks that still fit a bounded packet.
- CodeBuddy `codebuddy-free`: fixed `hy3` by default. This is the Tencent Cloud TokenHub CodeBuddy Code documented model id. Bundled product configs list `hy3-preview-agent` as a preview/credit-multiplied route, so `hy3-preview-agent` is not the default route. Do not use `auto` for normal dispatch.
- CodeBuddy `auto`: blocked by default. It is an automatic provider-selected route, so it violates cost-controlled orchestration unless the user explicitly chooses it for a one-off run.
- CodeBuddy DeepSeek fallbacks: use `deepseek-v4-flash` as the cheap fallback and `deepseek-v4-pro` as the stronger fallback. These are the user-approved DeepSeek V4 options and are present in the bundled product catalog/docs. `DeepSeek-V3.2` is only a current CLI-help observation, not a selected default/recommended tier.
- CodeBuddy DeepSeek tiers are explicit fallbacks only after verifying the current UI price/model mapping. The wrapper blocks unlisted CodeBuddy model IDs by default because unsupported IDs can silently fall back provider-side.
- Avoid expensive models unless a packet fails on cheaper tiers or needs stronger reasoning.
- Do not use CodeBuddy Agent Teams or swarm as the default. They add coordination overhead and token use. Prefer external Codex dispatch unless the task genuinely benefits from inter-member discussion or competitive parallel hypotheses.

## Verification

Codex must verify after each returned task:

- Read the worker's summary.
- Inspect changed files or generated reports.
- Run the smallest meaningful test/check.
- Compare the result against the task's acceptance target.
- Merge or continue only after verification.

If verification fails, Codex either fixes directly or sends one revised task packet. Do not enter a loop of live steering.

## Known Limits

- Git worktrees isolate tracked-file edits and branches; they do not isolate ports, databases, caches, credentials, running services, or OS permissions.
- New worktrees do not automatically contain gitignored local files such as `.env.local`; copy or regenerate them only when the task truly needs them.
- Two worktrees can still create merge conflicts if their file scopes overlap. Codex must merge worker outputs one at a time.
- CodeBuddy and Qoder permission bypass modes are acceptable only after Codex has chosen the repo, task, worktree, and tool whitelist.
- `-MaxTurns` is a hard cap, not a quality control. Too-low values can stop an otherwise correct worker before it reports; edit packets default to 8 turns.
- The local Codex app-server notification path is a local desktop/CLI integration, not a public cloud API. If that path changes in a future Codex release, worker completion still lands in `completion.json`; the automatic Codex wake-up becomes degraded until the invoker is refreshed.
