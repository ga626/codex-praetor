# Codex Praetor Release Readiness Audit

Date: 2026-07-10

## Current Result

Codex Praetor is past the pure scaffold stage. The repository has two clean commits, the core validation suite passes, the C-drive installed skill is a real copied directory, the plugin MCP package passes protocol smoke, and a real MiMo readonly worker audit completed in an isolated worktree without modifying the main repository.

It is not ready for public GitHub release yet. The remaining work is product packaging: user-facing installation docs, final GitHub URLs, native fresh-context MCP verification after config reload, provider-missing UX, and release hygiene.

## Evidence

- Commit `f9f811e`: initialized the alpha workspace.
- Commit `a6c9741`: fixed MiMo readonly dispatch and moved skill backups out of the skills scan path.
- `doctor -RequireHead -PublicRelease`: PASS.
- `scripts/test-codex-praetor.ps1`: PASS, 0 warnings, 0 failures.
- Plugin MCP protocol smoke: PASS.
- Real MiMo readonly release audit: PASS; output started with `CP_WORKER_RELEASE_AUDIT`; main repo stayed clean except ignored runtime/internal folders.
- Local Codex config cleanup: removed the duplicate global `mcp_servers.codex-praetor` entry and kept the `codex-praetor@personal` plugin entry. Backup: `%USERPROFILE%\.codex\config.toml.bak-codex-praetor-dedupe-20260710-070243`.
- Personal plugin/cache publish: PASS for `0.1.0-alpha+codex.20260710071926`; both install copy and Codex cache use portable `"command": "node"` and MIT metadata.

## Important Finding

The current Codex thread still reports `Transport closed` for `mcp__codex_praetor.*` calls after config cleanup. Local SDK/protocol smoke passes, so this is now a current-thread transport cache/reload problem, not proof that the bundled MCP server is broken.

Release acceptance must include a fresh Codex tool-context canary where native MCP calls succeed for:

- `codex_praetor_route_intent`
- `codex_praetor_dispatch_dry_run`
- `codex_praetor_list_lanes`
- `codex_praetor_detect_conflicts`

## Remaining Release Blocks

- Final GitHub repository URL is not configured yet.
- README now has first-pass setup/troubleshooting; provider-specific installation and login docs have a public first draft under `docs/provider-notes/`, but still need to be checked against later canary results.
- Provider setup docs now explain that Qoder, CodeBuddy, and MiMo are user-installed optional CLIs.
- Doctor should make missing provider states more user-friendly.
- Plugin manifest should use final repository/homepage URLs before release.
- Native MCP verification requires a refreshed tool context after the new personal plugin/cache version is loaded.

## Next Actions

1. Refine provider-specific install/login/capability docs after CodeBuddy and Qoder canaries.
2. Keep improving `doctor` output for provider missing/login/capability states.
3. Reload Codex or open a refreshed tool context so the new personal plugin/cache version is loaded.
4. Run a fresh-context native MCP canary.
5. Set the GitHub remote and replace placeholder repository URLs.
6. Tag `0.1.0-alpha` only after a new user can run doctor and dry-run from README.
