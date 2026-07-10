# Codex Praetor Release Readiness Audit

Date: 2026-07-10

## Current Result

Codex Praetor is past the pure scaffold stage. The repository has clean commits, the core validation suite passes, the C-drive installed skill is a real copied directory, the plugin MCP package passes protocol smoke, and real MiMo, CodeBuddy, and Qoder readonly worker audits completed without modifying the main repository.

It is not ready for public GitHub release yet. The remaining work is now final-publication gating: safe GitHub CLI auth, final GitHub URLs, native fresh-context MCP verification after config reload, provider-missing UX refinements as new canary failures appear, and the user's confirmation before any public push, tag, release, or asset publication.

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

## Important Finding

The current Codex thread still reports `Transport closed` for `mcp__codex_praetor.*` calls after config cleanup. Local SDK/protocol smoke passes, so this is now a current-thread transport cache/reload problem, not proof that the bundled MCP server is broken.

Release acceptance must include a fresh Codex tool-context canary where native MCP calls succeed for:

- `codex_praetor_route_intent`
- `codex_praetor_dispatch_dry_run`
- `codex_praetor_list_lanes`
- `codex_praetor_detect_conflicts`

## Remaining Release Blocks

- Final GitHub repository URL is not configured yet.
- Safe GitHub CLI auth is not configured yet. Any exposed PAT must be revoked before publication continues.
- README now has setup, troubleshooting, and release-package instructions; provider-specific installation and login docs have a public first draft under `docs/provider-notes/` and have been checked by CodeBuddy/Qoder readonly canaries.
- Provider setup docs now explain that Qoder, CodeBuddy, and MiMo are user-installed optional CLIs.
- Doctor can still be improved as new provider-missing/login/capability cases are observed, but this is no longer a release-package blocker by itself.
- Plugin manifest should use final repository/homepage URLs before release.
- Native MCP verification requires a refreshed tool context after the new personal plugin/cache version is loaded.

## Next Actions

1. Revoke any exposed GitHub token, install GitHub CLI if needed, and complete `gh auth login` / `gh auth status`.
2. Confirm the final GitHub owner/repo URL, then replace placeholder repository URLs in plugin metadata with `scripts\set-codex-praetor-public-metadata.ps1 -RepositoryUrl https://github.com/OWNER/codex-praetor -Apply`.
3. Re-run public-release doctor, minimal validation, diff check, and release package build without `-AllowDraftMetadataPlaceholders` after the URL change.
4. Reload Codex or open a refreshed tool context so the new personal plugin/cache version is loaded.
5. Run a fresh-context native MCP canary using `docs/fresh-context-native-mcp-canary.md`.
6. Stop for user confirmation before first public push, `0.1.0-alpha` tag, GitHub release, or release asset publication.
