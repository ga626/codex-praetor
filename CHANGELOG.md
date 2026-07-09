# Changelog

## 0.1.0-alpha - Unreleased

- Created the Codex Praetor product workspace.
- Added the source skill, plugin skill shape, Windows PowerShell wrapper, job watcher, plan manager, and notification scripts.
- Added a thin MCP server for route intent, dry-run dispatch, job/plan status, lane listing, lane lookup, and conflict detection.
- Added public-release doctor checks, minimal validation, git hooks, and plugin MCP protocol smoke tests.
- Verified one real MiMo readonly worker audit in an isolated worktree without modifying the main repository.
- Cleaned local install boundaries: D drive is the source project, C drive skill/plugin paths are explicit copied installs, not symlinks or auto-sync.

Public GitHub release is still pending final repository URLs, native fresh-context MCP verification, and release packaging.
