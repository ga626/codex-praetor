# Evidence Register

Use this file to justify the codex-praetor orchestration policy without re-running the full investigation.

## Strong Local Evidence

- The detailed three-agent local capability snapshot is internal evidence and must not be published when it includes user paths, accounts, usage pages, or screenshots.
- CodeBuddy local `--help` shows `--effort`, `--json-schema`, `--subagent-permission-mode`, `--agent`, `--agents`, `--bg`, `--swarm`, `--tools`, and permission controls. The wrapper treats `--effort` as a soft Codex-selected field while keeping model allowlists as hard rails.
- Qoder local `--help` shows `--reasoning-effort`, `--context-window`, `--config-dir`, `--agent`, `--agents`, `--permission-mode`, `--tools`, remote controls, and MCP settings. The wrapper maps the unified reasoning/context fields to Qoder flags.
- Qoder local `--list-models` shows `Auto`, `Qwen3.7-Max`, `Qwen3.7-Plus`, `Qwen3.6-Flash`, `DeepSeek-V4-Pro`, `DeepSeek-V4-Flash`, `GLM-5.2`, `Kimi-K2.7-Code`, and `MiniMax-M2.7`. Only `Qwen3.7-Plus` and `Qwen3.7-Max` remain default-routable.
- MiMo local `mimo run --help` shows `--model`, `--agent`, `--format`, `--dir`, `--variant`, `--continue`, `--session`, `--share`, and `--dangerously-skip-permissions`. The wrapper uses `mimo run` directly and does not launch WezTerm.
- MiMo local free-route smoke forced `mimo/mimo-auto`, cleared `OPENAI_API_KEY`, ran while not logged in, returned `MIMO_AUTO_FREE_SMOKE_OK`, and `mimo stats --models 10` showed `mimo/mimo-auto` cost `$0.0000`.
- MiMo wrapper smoke on 2026-07-08 showed that `agent plan` can still read repository files and write `.mimocode/plans/...` inside the target repo. The generated validation artifact was removed and the wrapper was changed so MiMo runs in a Codex-created worktree even for readonly/planning tasks.
- MiMo background watcher validation on 2026-07-08 completed with exit code 0 and parsed JSON event fields into `completion.json`: `provider_cost=0`, token counts, `tool_use_count`, and `parser_errors=0`. The main repo stayed clean; MiMo-generated `.mimocode` files stayed inside the disposable worktree, which was removed after validation.
- CodeBuddy real smoke after adding `--effort medium` returned `CODEBUDDY_EFFORT_OK` with model `hy3`.
- Qoder real smoke after adding `--reasoning-effort medium --context-window 200000` returned `QODER_REASONING_OK` with model `Qwen3.7-Plus`.
- Design conclusion: CodeBuddy, Qoder, and MiMo are worker agents. Codex hard-codes cost/security/model rails, then chooses reasoning effort, agent mode, context window, and output shape per task.
- CodeBuddy CLI `--help` on this machine shows `-p/--print`, `--output-format`, `-y`, `--permission-mode`, `--tools`, `--worktree`, `--bg`, `ps`, `logs`, `attach`, `kill`, `--swarm`, `--max-turns`, `--agent`, and `--agents`.
- Qoder CLI CN `--help` on this machine shows `-p/--print`, `--worktree`, `--permission-mode`, `--tools`, `--allowed-tools`, `--disallowed-tools`, `--remote`, `--list-sessions`, `--session-id`, `--agent`, `--agents`, and `--max-output-tokens`.
- CodeBuddy headless key path is configured and verified locally with user-level `CODEBUDDY_API_KEY` plus `CODEBUDDY_INTERNET_ENVIRONMENT=internal`.
- CodeBuddy blocking wrapper validation returned `WRAPPER_AUTH_OK`.
- CodeBuddy background wrapper validation first failed because PowerShell `Start-Process -ArgumentList` split a CLI path containing spaces; wrapper was fixed to pass a single quoted argument line. Retest returned `BACKGROUND_OK_2` and the process exited.
- `codebuddy ps` reported no active sessions after validation.
- Bundled CodeBuddy product configs list `hy3-preview-agent` as `Hy3 preview` with a credit multiplier, plus DeepSeek V4 fallback entries. Tencent Cloud TokenHub CodeBuddy Code official setup uses model id `hy3` in `models.json` and `availableModels`. Account-specific billing observations are private evidence and are not included in the public release.
- Skill validation passed with `quick_validate.py`.
- Codex Desktop exposes `CODEX_THREAD_ID` inside shell turns on this machine. The current thread id was visible as an environment variable without reading private auth material.
- Local Codex app-server `thread/resume` was validated against the current thread with `excludeTurns=true`; it returned thread metadata without starting a model turn.
- Prior local rule-curator automation had already paused a heartbeat and moved toward event-driven `FileSystemWatcher` push; this is a local precedent that fixed-interval heartbeats are not the preferred design for change-triggered notifications.
- Cheap-worker watcher validation used a dummy process, not Tencent/Alibaba model credits. The watcher starts the worker, waits at OS process level, records `completion.json`, releases the lock, and captures a fast failure exit code (`7`) as `status=failed`.

## Official Evidence

- CodeBuddy Headless Mode: `-p` runs programmatically without interactive UI; output can be text/json/stream-json; `-y` is required for non-interactive operations that need authorization; JSON output supports parsing; session resume is supported.
- CodeBuddy CLI Reference: supports `ps/logs/attach/kill`, `--bg`, `--name`, `--worktree`, `--tools`, `--allowedTools`, `--disallowedTools`, `--max-turns`, `--permission-mode`, `--sandbox`, and `--serve`.
- CodeBuddy Worktree: worktrees isolate AI changes for parallel development; subagents can use `isolation: worktree`; the docs explicitly say this is file-conflict isolation, not a security sandbox.
- CodeBuddy Permission Modes: `dontAsk` is fixed-whitelist automation; `bypassPermissions` should be used only in trusted/sandboxed contexts; non-interactive `ask` outcomes are denied unless a permission strategy exists; Agent Teams have separate permission inheritance.
- CodeBuddy Agent Teams: useful for parallel exploration, but token use is significantly higher; sequential tasks, same-file edits, and complex dependencies should use single-session or subagents instead.
- CodeBuddy Models docs: `availableModels` filters which model IDs are shown/usable after configuration merge; examples use exact IDs `deepseek-v4-pro` and `deepseek-v4-flash`. Environment variable docs also show `CODEBUDDY_MODEL=deepseek-v4-pro` and `CODEBUDDY_SMALL_FAST_MODEL=deepseek-v4-flash`.
- Qoder CLI docs: print mode is non-interactive; `/usage` shows Credits; `--worktree` is for parallel work in a Git repo; `--allowed-tools`, `--disallowed-tools`, `--max-turns`, and `--yolo` exist.
- Qoder Permissions: headless `ask` auto-denies; `dont_ask` never prompts and denies unapproved actions; `bypass_permissions` is YOLO; protected paths remain special; trust directories and tool rules define the practical boundary.
- Qoder Credits: Credits are shared across QoderWork CN and Qoder CLI CN, successful requests consume Credits, failed model calls do not, and Credits with earliest expiration are consumed first.
- Qoder off-peak discount: Qwen3.7-Plus is `0.04x` at 22:00-08:00 UTC+8 and `0.1x` daytime; Qwen3.7-Max is `0.1x` off-peak and `0.25x` daytime. Discount applies automatically to covered products including Qoder CLI CN and QoderWork CN.
- Qoder daily check-in: 100 Credits per day, each package valid for 30 days, reset at 00:00 UTC+8, missed days cannot be recovered.

## Community Evidence

- `smtg-ai/claude-squad`: manages multiple Claude Code, Codex, Gemini, Aider, and other local agents in separate workspaces; supports background tasks, yolo/auto-accept, reviewing changes before applying, and isolated git workspaces.
- `Santos-Enoque/magents`: manages multiple Claude Code instances across git branches with worktree isolation, Docker containers, task assignment, and dashboards.
- `sters/ai-workspace`: multi-repo manager using git worktrees and skills, but its README marks the repo deprecated because prompt-centered behavior was hard to customize. This is a warning against overbuilding a prompt-only orchestrator.
- `jvogan/a-fable-of-codexes`: uses a conductor/worker pattern with worktree and branch per worker, fleet table, dispatch/collect/integrate/verify waves, fixed-schema worker reports, and review gates.

## 2026-07-08 Issue-by-Issue External Validation

This section records the problems encountered during real wrapper validation and whether the fix is a root-cause fix, a supported workaround, or a remaining risk.

| Local symptom / question | External evidence | Verdict | Action |
| --- | --- | --- | --- |
| Background CodeBuddy failed when `Start-Process -ArgumentList` split a path containing spaces. | Microsoft `Start-Process` docs say array `ArgumentList` values are joined with spaces and recommend one full argument string with embedded quoting for best results. PowerShell issue #5576 remains open and documents the same whitespace/double-quote failure mode. | Root-cause-level for our wrapper. The bug is a known PowerShell argument-construction problem, not a CodeBuddy-only fluke. | Keep background mode using one quoted argument string. Continue avoiding ad hoc array passing for `Start-Process` when arguments contain paths or quotes. |
| `git worktree add` stdout contaminated the function return value. | Microsoft `about_Return` states PowerShell returns the output of every statement, even without `return`. | Root-cause-level for that symptom. Native command stdout inside a function can become returned data. | Suppress non-return command output with `Out-Null`; audit helper functions before adding new native command calls. |
| CodeBuddy internal `--worktree` was brittle locally; should Codex create worktrees directly? | Git official docs describe `git worktree add` as the primitive for linked worktrees. CodeBuddy worktree docs explicitly document creating worktrees directly with Git and then starting CodeBuddy inside the worktree. Qoder docs require Git repo context for worktree sessions. | Supported design change, not a blind workaround. Codex-created worktrees give us deterministic path, branch, and merge control. | Wrapper now creates git worktrees itself for edit tasks and runs CodeBuddy/Qoder inside them, without passing CodeBuddy/Qoder internal `--worktree`. |
| Are worktrees enough isolation for multiple agents? | Git docs, CodeBuddy FAQ, Conductor docs, and Upsun's worktree article all distinguish file/workspace isolation from runtime/security isolation. Upsun lists port, dependency, database, disk, and merge-conflict risks. | Partial fix only. Worktrees solve main checkout pollution and file-conflict review, but not environment isolation. | Policy now states worktree is not a security boundary; do not run overlapping file scopes; isolate ports/db/services separately for tasks that need runtime execution. |
| CodeBuddy `-p -y` and Qoder `bypass_permissions` look risky. | CodeBuddy headless docs require `-y` for non-interactive operations and warn to use it only in trusted explicit tasks. Qoder permissions docs say headless `ask` auto-denies, `dont_ask` denies unapproved actions, and `bypass_permissions` is for trusted local experiments. | Acceptable only under Codex-controlled scope. Not a blanket trust grant. | Keep worker permissions non-interactive only after Codex chooses repo, worktree, tool whitelist, and verification command. |
| `MaxTurns=4` caused a worker to hit max turns while still making the correct edit. | CodeBuddy CLI reference defines `--max-turns` as the non-interactive agent-turn cap. | Expected behavior, not random failure. Too-low turns can truncate reports. | Wrapper default changed from 4 to 8; tiny readonly probes can still pass lower `-MaxTurns`. |
| Which Hy3 name should be the default: `hy3` or `hy3-preview-agent`? | Local smoke evidence shows `hy3` returned `CODEBUDDY_OK`. Tencent Cloud TokenHub CodeBuddy Code official setup uses `hy3` as the model id and `availableModels` entry. Bundled product configs mark `hy3-preview-agent` as a credit-multiplied preview route. Private account billing observations are not published. | `hy3` is the correct default route. `hy3-preview-agent` is a paid/preview route and should not be the default. | `codebuddy-free` now uses `hy3`; `hy3-preview-agent` remains allowed only as an explicit paid fallback. |
| CodeBuddy `hy3`, `deepseek-v4-flash`, and `deepseek-v4-pro` IDs are not all exposed by current local CLI help. | Local `codebuddy --help` lists `auto`, `glm-*`, `kimi-k2.5`, `minimax-m2.7`, `deepseek-v3-2-volc`, and `custom-local:deepseek-ai/DeepSeek-V4-Flash`, but not `hy3`, `hy3-preview-agent`, `deepseek-v4-flash`, or `deepseek-v4-pro` as direct IDs. Official TokenHub docs use `hy3`; bundled docs/catalog show DeepSeek V4 IDs and mark `hy3-preview-agent` as charged. | CLI help is evidence for visible built-ins, but not enough for our selected routing policy. Official setup docs plus usage billing evidence outrank the help list for the free Hy3 route. | Wrapper uses explicit `allowedModels`: `hy3`, `hy3-preview-agent`, `deepseek-v4-flash`, `deepseek-v4-pro`. Default `codebuddy-free` is fixed `hy3`; CodeBuddy DeepSeek fallbacks are `deepseek-v4-flash` and `deepseek-v4-pro`. |
| `codebuddy-free` was temporarily changed to `auto`, then incorrectly changed to DeepSeek-V3.2, then to `hy3-preview-agent`. | Local `codebuddy --help` treats `auto` as a supported model choice, not a fixed backend. DeepSeek-V3.2 was never selected as the preferred Tencent model. Later `hy3-preview-agent` looked canonical in bundled configs, but those configs also mark it as a preview/credit-multiplied route. The official setup route is `hy3`. | `auto`, DeepSeek-V3.2, and `hy3-preview-agent` are all wrong defaults for the selected fixed Tencent route. | `codebuddy-free` now uses fixed `hy3`; `auto` remains in `blockedModels`; the wrapper rejects `auto` unless `-AllowAutoModel` is intentionally passed. DeepSeek-V3.2 is not a default/recommended tier. |
| Multiple Codex conversations may accidentally dispatch edit work to the same repo. | Community worktree orchestrators and Git/CodeBuddy docs rely on isolated worktrees plus review gates, but worktrees alone do not stop two dispatchers from choosing overlapping files. | Skill plus wrapper is still enough for the current stage; a full MCP queue is not necessary yet. A shared local repo lock covers the common accidental multi-conversation case. | Wrapper creates a per-repo edit lock under `%USERPROFILE%\.codex\codex-praetor-locks` for edit dispatch. Background dispatch holds that lock through the watcher process and releases it when the worker exits. |
| Background worker completion cannot rely on Codex asking "done yet?" every few seconds. | Windows/.NET process waiting and PowerShell `Start-Process -Wait -PassThru` support blocking until a process exits without a model loop. CodeBuddy/Qoder CLIs expose non-interactive/headless modes, and community orchestrators use detached workers plus collect/verify phases. | Root design change. Completion should be event-driven from the local OS process, not model polling or heartbeat polling. | Background jobs now start a watcher process. The watcher starts the worker, waits for process exit, writes `completion.json`, releases locks, and optionally sends one Codex app-server thread message. |
| A watcher that attaches to an already-started PID can miss very fast failures. | Local dummy validation showed a process can exit before the watcher attaches, making exit-code capture unreliable. PowerShell validation also showed `Start-Process` with redirected output needs `-Wait -PassThru` for reliable `ExitCode`. | Root-cause-level for the watcher design. | The watcher now starts the worker itself while the repo lock is held by the watcher PID. Fast failure validation captured `exit_code=7` and `status=failed`. |
| Can an external script wake a Codex thread without MCP? | Local app-server schema and legacy rule-curator scripts document `thread/resume` and `turn/start`; current validation of `thread/resume` succeeded. The Codex app tool surface also exposes `send_message_to_thread`, but that tool is only available inside a running Codex turn. | Supported locally, but it is not a public stable cloud API. Good enough for this 25-day lightweight setup; MCP remains unnecessary for now. | Add `invoke-codex-app-server.js` and `send-codex-thread-message.ps1`; use it as an optional notification path, with `completion.json` as durable fallback. |

## Derived Policy

- Current implementation should remain a Codex skill plus wrapper scripts, not a full MCP service yet. A skill persists across conversations and can load local scripts and policy with low overhead.
- MCP becomes useful only if we need a shared queue, lock service, or external programmatic API across multiple host agents.
- Default to blocking worker calls for short work. Background mode is allowed as an event-driven detached job with a watcher, `completion.json`, lock release, and optional Codex app-server notification. Do not implement fixed-interval log polling.
- Prefer external Codex dispatch over CodeBuddy Agent Teams/swarm. Use built-in teams only when member communication is itself valuable.
- Use worktrees for every edit packet. Read-only packets can share a checkout.
- Keep packets medium-sized: coherent enough to finish without mid-run steering, small enough for Codex to verify in one pass.

## Source URLs

- https://www.codebuddy.ai/docs/cli/headless
- https://www.codebuddy.ai/docs/cli/cli-reference
- https://www.codebuddy.ai/docs/cli/worktree
- https://www.codebuddy.ai/docs/cli/permission-modes
- https://www.codebuddy.ai/docs/cli/agent-teams
- https://www.codebuddy.cn/docs/cli/iam
- https://www.codebuddy.ai/docs/zh/cli/env-vars
- https://docs.qoder.com/zh/cli/using-cli
- https://docs.qoder.com/en/cli/permissions
- https://docs.qoder.com/en/cli/tools
- https://docs.qoder.com/en/cli/plugins
- https://help.aliyun.com/zh/lingma/product-overview/qwen-3-7-series-model-staggering-discount
- https://help.aliyun.com/zh/lingma/product-overview/credits
- https://help.aliyun.com/zh/lingma/product-overview/billing-description
- https://help.aliyun.com/en/lingma/product-overview/daily-check-in-100-credits-reward-program-terms
- https://github.com/smtg-ai/claude-squad
- https://github.com/Santos-Enoque/magents
- https://github.com/sters/ai-workspace
- https://github.com/jvogan/a-fable-of-codexes
- https://github.com/PowerShell/PowerShell/issues/5576
- https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.management/start-process
- https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.core/about/about_return
- https://git-scm.com/docs/git-worktree
- https://www.conductor.build/docs/concepts/git-worktrees
- https://developer.upsun.com/posts/ai/git-worktrees-for-parallel-ai-coding-agents

