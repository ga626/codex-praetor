# Codex Praetor Release Readiness Audit

Date: 2026-07-10

## Current Result

Codex Praetor is past the pure scaffold stage. The repository has clean commits, the core validation suite passes, the C-drive installed skill is a real copied directory, the plugin MCP package passes protocol smoke, and real MiMo, CodeBuddy, and Qoder readonly worker audits completed without modifying the main repository.

The alpha has been published as GitHub release `v0.1.0-alpha` with `.release/codex-praetor-0.1.0-alpha.zip` uploaded as the release asset. The final native fresh-context MCP canary remains blocked only in this already-open Codex thread because its MCP tool context still has stale transport state.

## Evidence

- Commit `f9f811e`: initialized the alpha workspace.
- Commit `a6c9741`: fixed MiMo readonly dispatch and moved skill backups out of the skills scan path.
- Draft public doctor gate: PASS/WARN with `-AllowDraftMetadataPlaceholders`; the only warning is the intentionally unresolved public metadata URL.
- Final public doctor gate without `-AllowDraftMetadataPlaceholders`: FAIL by design until the real GitHub owner/repo URL replaces placeholder metadata.
- `scripts/test-codex-praetor.ps1`: PASS, 0 warnings, 0 failures.
- Plugin MCP protocol smoke: PASS.
- Real MiMo readonly release audit: PASS; output started with `CP_WORKER_RELEASE_AUDIT`; main repo stayed clean except ignored runtime/internal folders.
- Real CodeBuddy readonly provider-doc canary: PASS; output marker `CP_CODEBUDDY_PROVIDER_DOCS_CANARY`; root README links into `docs/provider-notes/`, provider index links Qoder/CodeBuddy/MiMo notes, and the main repo stayed clean.
- Real Qoder readonly provider-doc canary: PASS; output marker `CP_QODER_PROVIDER_DOCS_CANARY`; Qoder docs cover official install, login boundary, local config, and readonly canary; the main repo stayed clean.
- Local Codex config cleanup: removed the duplicate global `mcp_servers.codex-praetor` entry and kept the `codex-praetor@personal` plugin entry. Backup: `%USERPROFILE%\.codex\config.toml.bak-codex-praetor-dedupe-20260710-070243`.
- Personal plugin/cache publish: PASS for `0.1.0-alpha+codex.20260710071926`; both install copy and Codex cache use portable `"command": "node"` and MIT metadata.
- Draft local release package builder: PASS for `.release/codex-praetor-0.1.0-alpha.zip` with `-AllowDraftMetadataPlaceholders`; the package excludes `handoff/`, `docs/internal/`, `node_modules/`, local configs, personal publish scripts, and known machine-local markers.
- Final local release package builder without `-AllowDraftMetadataPlaceholders`: FAIL by design until real public metadata URLs are configured.
- GitHub CLI on the current machine: missing from PATH at audit time; raw Personal Access Tokens must not be used as a substitute. Publication requires `gh auth login` / `gh auth status`.
- MiMo readonly release-blocker audit: PASS for job `20260710-114335-mimo-mimo-auto-readonly-0c27df67`; it confirmed the same live blockers: placeholder GitHub URLs, no remote, fresh-context MCP canary still pending, and GitHub publication requiring safe auth. The audit worktree was created from HEAD, so findings about files added later in the working tree are treated as stale.
- Current validation refresh: `scripts/test-codex-praetor.ps1 -SkipInstalledSkillCheck` PASS with 0 warnings and 0 failures; `npm test --prefix .\mcp` PASS; `git diff --check` PASS; draft release package rebuilt successfully at `.release/codex-praetor-0.1.0-alpha.zip` with placeholder warning only.
- GitHub repository created: `https://github.com/ga626/codex-praetor`.
- Public metadata replaced: `plugin/.codex-plugin/plugin.json` now points to `https://github.com/ga626/codex-praetor`.
- Final public doctor: PASS after GitHub CLI was made available for the command environment.
- Final release package builder without `-AllowDraftMetadataPlaceholders`: PASS for `.release/codex-praetor-0.1.0-alpha.zip`; plugin metadata no longer contains placeholders, and the release tree passed private-marker checks.
- First public push: PASS; local `main` tracks `origin/main`.
- GitHub tag and release publication: PASS for `v0.1.0-alpha`; `.release/codex-praetor-0.1.0-alpha.zip` was uploaded as the release asset.
- Fresh-context MCP canary: BLOCKED only in this already-open thread. The WindowsApps `codex.exe` alias returns `Access is denied`, the current thread native `mcp__codex_praetor.*` surface still returns stale `Transport closed`, and no Codex thread-creation tool is exposed in the current tool surface.

## Important Finding

The current Codex thread still reports `Transport closed` for `mcp__codex_praetor.*` calls after config cleanup. Local SDK/protocol smoke passes, so this is now a current-thread transport cache/reload problem, not proof that the bundled MCP server is broken.

Release acceptance must include a fresh Codex tool-context canary where native MCP calls succeed for:

- `codex_praetor_route_intent`
- `codex_praetor_dispatch_dry_run`
- `codex_praetor_list_lanes`
- `codex_praetor_detect_conflicts`

## Remaining Follow-ups

- Final fresh-context native MCP canary is not complete in this already-open thread, but local SDK/protocol smoke passed and the published package contains the intended portable MCP startup metadata.
- README now has setup, troubleshooting, and release-package instructions; provider-specific installation and login docs have a public first draft under `docs/provider-notes/` and have been checked by CodeBuddy/Qoder readonly canaries.
- Provider setup docs now explain that Qoder, CodeBuddy, and MiMo are user-installed optional CLIs.
- Doctor can still be improved as new provider-missing/login/capability cases are observed, but this is no longer a release-package blocker by itself.
- Native MCP verification requires a refreshed tool context after the new personal plugin/cache version is loaded.

## Next Actions

1. Open a refreshed Codex Desktop context with Codex Praetor plugin/MCP loaded, or provide a working Codex CLI path that does not hit the WindowsApps `Access is denied` failure.
2. Run a fresh-context native MCP canary using `docs/fresh-context-native-mcp-canary.md`.
3. If the canary fails in a fresh context, fix plugin/MCP loading before the next release train.
