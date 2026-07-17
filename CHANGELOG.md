# Changelog

## Unreleased

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
