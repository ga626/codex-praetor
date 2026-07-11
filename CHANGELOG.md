# Changelog

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
