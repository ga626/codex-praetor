# Changelog

## 0.9.2-alpha - 2026-07-22

- Added an explainable, read-only route recommendation that ranks only exact-tuple, current capability evidence after hard gates pass.
- Added bounded failure recovery guidance for provider blocks, transient faults, permissions, partial worktrees, tests and scope violations.
- Made evidence older than 30 days stale and prevented expired cooldown evidence from becoming an automatic retry path.

## 0.9.1-alpha - 2026-07-22

- Added a versioned real-task evaluation suite covering diagnosis, bounded code change, fixed test execution, and failure recovery.
- Added an evaluation plan preparer and read-only MCP view; prepared work is explicitly not provider capability evidence.
- Added deterministic suite-contract regression coverage to the release pipeline.

## 0.9.0-alpha - 2026-07-22

- Added a conservative, read-only capability-profile projection keyed by provider tuple and task family; it records observed, provisional, qualified, cooling-down and blocked evidence without changing default routing.
- Added public provider-adapter contracts for Qoder, CodeBuddy and MiMo, including permission semantics and the explicit disposable-worktree boundary.
- Bound Codex's verification verdict to the latest immutable attempt and added regression coverage for profile projection and adapter presence.

## 0.8.4-alpha - 2026-07-22

- Classified provider rejection, MiMo risk-control errors, max-turn exhaustion, and partial worktree artifacts as structured failures rather than successful worker reports.
- Made failed attempts enter rejected governance state; only clean process exits without a semantic failure remain awaiting Codex verification.
- Added deterministic isolated-worktree MCP dependency bootstrap, a table-shaped `codex plugin list` activation regression, and health output that separates dispatch authority from historical diagnostics.

## 0.8.3-alpha - 2026-07-22

- Recovered the 0.8.2-alpha CodeBuddy edit-worker release incident with a new immutable version; the published 0.8.2 artifact remains unchanged.
- Replaced the unsupported CodeBuddy `dontAsk`/`allowedTools` protocol with locally verified `-y --tools` allowlists for readonly and isolated edit worktrees.
- Added an executable permission fault-injection regression that rejects the historical protocol before a release candidate can pass.
- Made readiness entry-scoped across generations, strengthened edit canaries to require a worker-worktree change, and recorded report/artifact evidence without bypassing Codex verification.
- Made explicit worker-network authorization observable and consistent with the actual worker prompt while retaining the no-secret boundary.
- Remediated the published MCP dependency alerts by pinning `@hono/node-server` to `2.0.11` and `fast-uri` to `3.1.4`, with lockfile regression coverage.

## 0.8.2-alpha - 2026-07-22

- Unified bundled health and capability-canary generation resolution, so a valid Release generation proof is no longer rejected as a synthetic runtime-contract generation.
- Added the verified published-Release activation command: it downloads the immutable zip, checks its SHA256 and tag generation, runs the bundled installer, invokes official `codex plugin add`, installs maintenance, and reports the explicit host-refresh boundary.
- Allowed isolated worker worktrees from detached acceptance checkouts by branching from the resolved `HEAD` commit.
- Added packaged-generation, published-activation, and detached-worktree regressions.

## 0.8.1-alpha - 2026-07-21

- Added an explicit stable-install -> host-refresh -> runtime-identity -> canary state machine, with isolated regression coverage for old installs and old hosts.
- Separated same-artifact CI verification from published-artifact verification, so a stale local candidate cannot be misreported as a stale GitHub Release.
- Stopped the setup wizard from running a real canary before the Desktop host has loaded the installed generation.
- Added a Windows PowerShell encoding gate for non-ASCII `.ps1` files after CI exposed a UTF-8-without-BOM parser failure.

## 0.8.0-alpha - 2026-07-21

- Separated capability-canary provider proof from concurrent checkout drift: dirty-before is rejected, drift-during is durable evidence rather than a false provider failure.
- Corrected terminal worker lifecycle presentation: `process_exited`, timeout, watcher failure and unknown states no longer occupy active lanes; successful exits explicitly await Codex verification.
- Made shared release CI distinguish release-impact candidates from dependency-only candidates before immutable-tag checks.
- Added UTF-8 pipe-chunk decoding regression coverage and fault-injection coverage for canary drift and CI classification.

## 0.7.1-alpha - 2026-07-21

- Made the running plugin generation and bundled runtime contract authoritative for provider-readiness health; legacy `active.json` is now diagnostic-only and cannot block a newer loaded plugin.
- Kept real dispatch fail-closed on the exact provider/model/permission/task/CLI-hash tuple while making health report only valid tuples for the current generation.
- Added a regression fixture for an old receipt with a newer plugin generation and readiness record, plus JSON-safe source generation output.

## 0.6.3-alpha - 2026-07-20

- Recovered from the `0.6.2-alpha` release incident with a new version; the published 0.6.2 artifact is retained and is not activated or overwritten.
- Made `config/runtime-contract.json` the canonical runtime contract and generate all plugin/Skill contract surfaces from it.
- Required the final zip's real bundled MCP to match the canonical contract SHA, exact tool set, server version, and generation manifest.
- Bound publication to one `artifact_verified` manifest and SHA; the publisher no longer rebuilds a different upload candidate.
- Replaced successful closeout's fabricated runtime observation with a final-zip runtime proof and added a regression mutation for the historical contract split.

## 0.6.1-alpha - 2026-07-19

- Repaired the failed `0.6.0-alpha` release bootstrap with a new immutable version; the failed candidate never created a tag or Release.
- Made PR candidate validation and mainline publication call one reusable release pipeline, including real remote action-pin resolution before merge.
- Required every release-impacting PR to increment from the exact target-branch release intent, and limited post-publication recovery to a re-run of the original workflow SHA.

## 0.6.0-alpha - 2026-07-19

- 将发布意图、版本一致性、PR 门禁和 `main` 合并后自动 Release 串成一条流水线。
- 发布 workflow 自动构建、验证、上传不可变 Release 资产并复验远端 hash。
- 增加 release intent schema、版本面更新脚本和流程回归测试。

## 0.5.0-alpha - 2026-07-18

- 统一 logical task、attempt、event、selection、outcome、progress 和 release state 合同。
- 将 provider readiness、Windows maintenance task 和 runtime inventory 接入动态 health；漂移、过期和缺失均 fail-closed。
- 保留 `0.4.1-alpha`/`0.4.2-alpha` 历史代际不可变，下一次交付使用新的 `v0.5.0-alpha`。
- 补充供应链门禁、动作 pin、Dependabot 和 PR 前验收脚本。

## Unreleased

## 0.4.2-alpha - 2026-07-18

- Made stable release activation fail closed when the generation-reconciliation maintenance task cannot be registered and verified.
- Added a `schtasks.exe` XML fallback for Windows images where `Register-ScheduledTask` is denied, with equivalent user-level triggers and post-registration checks.
- Moved active-receipt writes after maintenance installation so a failed installer cannot be reported as an active generation.

## 0.4.1-alpha - 2026-07-18

- Added runtime identity to `codex_praetor_runtime_info`, including the loaded contract hash, runtime roots, PID, and process start time.
- Replaced name-only fresh-context evidence with a generation-bound runtime proof; activation and health now reject stale or identity-free proof records.
- Corrected the separate app-server diagnostic so it no longer claims to reload the already-running Codex Desktop host.

## 0.4.0-alpha - 2026-07-17

- Added the local task-governance ledger: logical tasks, immutable attempts, evidence state, append-only events, and Codex supervisor verdicts.
- Stopped treating worker process exit as a completed task; only an accepted verdict can unlock a dependent logical task.
- Made cancellation request-only until the watcher projects its terminal state, preserving the job artifact record.
- Added activation-compatible generation readiness with provider-tuple entries and explicit readiness-state paths, so development canaries and PR dispatch stay inside an isolated profile.
- Updated product version, release notes, roadmap, and release runbook for the `0.4.0-alpha` delivery contract.

## 0.3.0-alpha - 2026-07-17

- Bound generation, provider readiness, task contracts, durable jobs, completion records, and promotion receipts to one runtime contract.
- Rejected stale readiness evidence and reused release tags; upgraded generation and release receipts to v2.
- Recorded provider tuples and terminal states across completed, semantic failure, timeout, cancellation, and watcher failure paths.
- Made packaged Skill canary and native invocation self-contained instead of depending on the source checkout layout.
- Added the unified productization and reliability report, release notes, and isolated closeout coverage.

## 0.2.0-alpha - 2026-07-16

- Added one runtime contract shared by the source MCP, plugin metadata, Skill distribution, and personal-cache health gate.
- Added provider readiness records tied to CLI path/hash, model, task kind, permission profile, wrapper protocol, and expiry; real dispatch now fails closed without a current matching canary.
- Kept external network research with Codex and KnowledgeRadar; provider workers are limited to bounded local code work.
- Changed MiMo audit naming from readonly to isolated audit, and now run every provider task inside a disposable Codex-created worktree.
- Unified blocking/background execution around durable job metadata, completion files, timeout, safe process-tree cancellation, and semantic failure classification.
- Added MCP runtime-info, health, job-timeline, and cancel-job tools with user-facing state summaries.

## 0.1.3-alpha - 2026-07-15

- Separated product validation from developer-environment validation so PR, CI, and release gates no longer depend on the local Codex global rules, installed skill copy, or provider dry-run state by default.
- Added a public-entry consistency check to keep README, installation docs, roadmap, release notes, and GitHub Release assets aligned after publication.
- Made release package builds deterministic by writing zip entries in stable order with fixed timestamps, plus a repeat-build SHA256 verification gate.
- Added a dry-run-first runtime cleanup helper for merged clean worker worktrees, old completed jobs, and scratch artifacts under `.codex-praetor`.
- Updated all public download, package metadata, installer, and release automation references for the `0.1.3-alpha` release.

## 0.1.2-alpha - 2026-07-15

- Added MCP tools for the continuous orchestration loop: real worker dispatch, compact worker result reads, ready plan-task lookup, plan-task dispatch, and Codex verification verdict recording.
- Changed plan job recording so a completed worker moves the task to `awaiting_verification`; dependent tasks unlock only after Codex records an accepted verdict.
- Added worker outcome classification for common operator-facing failures such as max-turns exhaustion, missing provider CLI, auth/login requirements, permission denial, watcher failure, and missing completion files.
- Bumped source/plugin/MCP version metadata to `0.1.2-alpha` and published the GitHub Release asset.
- Added a user-facing readonly provider canary command that previews by default and only starts a real provider run with `-Apply`.
- Documented the canary in README, installation, troubleshooting, provider notes, and the user acceptance checklist.
- Kept the canary limited to reading `README.md`, checking for a success marker, and verifying that the main repository stays unchanged.

## 0.1.1-alpha - 2026-07-13

Release closeout for the Windows-first alpha install path.

- Updated the public install path to the setup package: `codex-praetor-setup-0.1.1-alpha.zip`.
- Aligned the README, installation guide, troubleshooting guide, acceptance checklist, release gate, and publish runbook with the grouped `docs/user`, `docs/release`, and `scripts/*` layout.
- Kept runtime artifacts project-local under `.codex-praetor` and documented that the development checkout is separate from the installed Codex plugin directory.
- Added `0.1.1-alpha` release notes for the double-click setup flow, release package boundary, repository layout cleanup, and validation checklist.
- Bumped MCP and plugin-facing version metadata to `0.1.1-alpha`.

## 0.1.0-alpha - 2026-07-10

Public GitHub prerelease: `v0.1.0-alpha`.

- Created the Codex Praetor product workspace.
- Added the source skill, plugin skill shape, Windows PowerShell wrapper, job watcher, plan manager, and notification scripts.
- Added a thin MCP server for route intent, dry-run dispatch, job/plan status, lane listing, lane lookup, and conflict detection.
- Added public-release doctor checks, minimal validation, git hooks, and plugin MCP protocol smoke tests.
- Verified one real MiMo readonly worker audit in an isolated worktree without modifying the main repository.
- Verified CodeBuddy and Qoder readonly provider-doc canaries without modifying the main repository.
- Added provider setup docs, CI workflow, release notes, and a local release package builder with release-tree checks.
- Cleaned local install boundaries: D drive is the source project, C drive skill/plugin paths are explicit copied installs, not symlinks or auto-sync.
- Published release asset `codex-praetor-0.1.0-alpha.zip`.

Known alpha boundary: an already-open Codex thread can keep stale MCP tool handles after plugin changes. Normal use should rely on refreshed tool context after install/update, and troubleshooting should use the lightweight reload/probe path before asking the user to open a new task.
