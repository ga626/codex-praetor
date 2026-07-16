# Codex Praetor Release Gate Checklist

Date: 2026-07-13

This checklist separates the development repository from the user-facing release package. The goal is a Windows-first Codex plugin users can install and operate, not a dump of every local development artifact.

## 1. Development Validation Layer

These checks protect the source repository. They may stay in the repo, but they are not the product experience.

- Git hooks: `.githooks/pre-commit` and `.githooks/pre-push` through `core.hooksPath`.
- GitHub CI: `.github/workflows/ci.yml` runs doctor with the public template, product validation, public-entry consistency, MCP tests, release package build, and release package determinism.
- Release doctor: draft CI can run `scripts/verify/doctor-codex-praetor.ps1 -RequireHead -PublicRelease -AllowDraftMetadataPlaceholders`; final public release must run without `-AllowDraftMetadataPlaceholders`.
- Product validation: `scripts/verify/test-codex-praetor.ps1`. This default gate must not depend on the current developer's global Codex rules, installed skill copy, provider login state, or local provider account data.
- Developer environment validation: `scripts/verify/test-codex-praetor-dev-env.ps1`. Use this when the change specifically touches local Codex installation, installed skill sync, provider dry-run behavior, or global-rule integration.
- Public entry consistency: `scripts/verify/test-public-entry-consistency.ps1`. Use `-SkipRemoteRelease` before publication and the full remote check during release closeout.
- Release package determinism: `scripts/verify/test-release-package-determinism.ps1`. The same staged release content must produce the same zip SHA256, stable entry order, and fixed zip entry timestamps.
- Continuous orchestration MCP validation: route-intent, dry-run, real dispatch tool listing, result reading, next-ready lookup, plan-task dispatch tool listing, and verify-task recording must pass protocol smoke before release.
- Provider readonly canary preview: `scripts/verify/test-provider-readonly-canary.ps1 -Provider mimo`.
- MCP source tests: `npm test` under `mcp/`.
- Plugin protocol smoke: `mcp/scripts/smoke-plugin-mcp.js` against the packaged runtime.
- Public marker scan: no personal account paths, auth files, local caches, or token-bearing artifacts in public paths.

## 2. User-Facing Release Package

The release package should contain only what helps a user install, configure, and run Codex Praetor.

Include:

- `plugin/` package shape with `.codex-plugin/plugin.json`, `.mcp.json`, bundled `plugin/mcp/dist/server.js`, and `plugin/skills/codex-praetor`.
- Root `README.md`, `LICENSE`, `CHANGELOG.md`, `SECURITY.md`, `CONTRIBUTING.md`.
- Root `setup.cmd` and `setup.ps1` as the Windows double-click setup entrypoints, including provider selection, human authorization wait, re-check, local config write, and final status summary.
- `.github/workflows/ci.yml` so the source release keeps its public validation path.
- `config/codex-praetor-tiers.example.json` as a template with no real local paths.
- Provider setup references for Qoder, CodeBuddy, and MiMo under `docs/provider-notes/`.
- User installation and troubleshooting docs: `docs/user/installation.zh.md` and `docs/user/troubleshooting.zh.md`.
- A minimal `examples/` folder with dry-run and readonly canary examples.
- Repository marketplace entry: `.agents/plugins/marketplace.json`.
- Current release notes: `docs/release/release-notes-0.2.0-alpha.md`.
- Local release package builder: `scripts/release/build-codex-praetor-release.ps1`.
- User installer: `scripts/install/install-user.ps1`.
  Draft CI checks may use `-AllowDraftMetadataPlaceholders`; final public builds must omit it so placeholder metadata URLs fail the gate.

Exclude from release bundles/assets:

- `handoff/`, `docs/internal/`, and private archaeology notes.
- `*.local.json`, `.env*`, auth/token/key files, screenshots, account databases, and provider caches.
- `mcp/node_modules/`, source build cache, test scratch, worktrees, job logs, and `.codex-praetor` runtime state.
- Machine-specific Codex config backups.

## 3. Provider UX Gate

Before release, a normal Windows user should see clear doctor states:

- CLI missing: what to install and where to configure `cliPath`.
- CLI missing or template path: report the optional provider as disabled, not as a core product failure.
- CLI installed: version probe result.
- Login unknown: clear instruction to complete the provider's normal login outside Codex Praetor.
- Setup wizard selection: all providers, skip all providers, Qoder only, CodeBuddy only, and MiMo only all work without turning optional provider absence into a product failure.
- Local config write: discovered provider CLI paths are written only to ignored user/local config and never include token, cookie, PAT, API key, account DB paths, balance pages, or screenshots.
- Capability mismatch: version/help probe fails or required flags are not accepted.
- No providers installed: local planning/dry-run/status still works, real dispatch is disabled.
- Provider installed and logged in: readonly canary can run with `-Apply`, return `CODEX_PRAETOR_CANARY_OK`, and leave the main repository clean.

Codex Praetor must not silently install providers, log in for the user, read provider auth databases, or promise free/cheap routing that depends on the user's account. It may guide users to official provider installation/authentication, wait for their manual action, re-check, and record non-secret CLI paths.

## 4. MCP Gate

Protocol smoke is necessary but not enough.

Required before release:

- Packaged runtime imports successfully.
- Protocol smoke can call route-intent, dry-run, lane listing, and conflict detection.
- Protocol smoke can see the real dispatch loop tools: `codex_praetor_dispatch`, `codex_praetor_result`, `codex_praetor_next_ready`, `codex_praetor_dispatch_plan_task`, and `codex_praetor_verify_task`.
- A completed worker job does not automatically unblock dependent plan tasks; release validation must confirm plan tasks advance only after a Codex verification verdict.
- `scripts/verify/reload-codex-praetor-mcp.ps1 -Json` can reload and report the packaged server.
- `scripts/verify/probe-codex-praetor-mcp.ps1 -Json` can route a dry-run request through the app-server MCP path.
- `scripts/verify/probe-codex-praetor-mcp.ps1 -AfterDirectHandleFailure -Json` can distinguish stale direct tool handles from a broken MCP service.
- Fresh Codex tool context shows native Codex Praetor MCP tools.
- Fresh-context native calls succeed for route-intent and dry-run.
- The current-thread `Transport closed` issue is documented as a reload/cache boundary, not treated as server failure.
- The final procedure follows `docs/architecture/fresh-context-native-mcp-canary.md`, and the result is recorded before public publication.

## 5. GitHub Gate

Before pushing or tagging:

- Revoke any GitHub Personal Access Token that was exposed in chat, logs, terminals, issues, or docs.
- Use GitHub CLI browser/device login, not pasted raw tokens. Required local checks: `gh --version`, `gh auth login`, and `gh auth status`.
- Follow `docs/release/github-publish-runbook.md` for repository creation, remote setup, push, tag, and GitHub release.
- Set the real GitHub remote.
- Replace draft GitHub URLs in plugin metadata with `scripts\release\set-codex-praetor-public-metadata.ps1 -RepositoryUrl https://github.com/OWNER/codex-praetor -Apply`.
- Re-run the public marker scan after the final URL change.
- Re-run the release package build without `-AllowDraftMetadataPlaceholders` after the final URL change.
- Enable or document GitHub secret scanning/push protection expectations.
- Confirm license, changelog entry, security policy, and README install path are current.
- Build the local release package and verify it excludes private/internal artifacts.
- Run the release package determinism check when the release builder or package contents change.
- Preview runtime cleanup with `scripts/maintenance/clean-codex-praetor-runtime.ps1` after merged worker worktrees or completed jobs accumulate. Apply cleanup only after the dry-run output is reviewed.
- Tag only after a new user path succeeds: clone -> doctor -> dry-run -> optional readonly canary.
- After a delivery-affecting PR is merged, publish the next version's GitHub Release zip, `.sha256`, and notes from latest `main` with `scripts/release/publish-github-release-asset.ps1 -Version NEXT_VERSION -Tag vNEXT_VERSION -Apply`; it must finish by running `scripts/release/verify-github-release-asset.ps1`, including the public-entry consistency gate.
- Remote-download validation must prove the downloaded package exposes the intended user-facing behavior before calling the product delivered.

## 5.1 Release Generation Closeout

For every delivery-affecting release, run `scripts/release/complete-codex-praetor-release.ps1` in two phases after the new GitHub Release zip and `.sha256` are available:

1. `stage` against the downloaded remote zip. It installs and hashes Skill, plugin, marketplace, and personal cache, then writes only a staged receipt. It must not delete old cache generations; old paths go to the retirement/reconcile queue.
2. If the MCP tool list, tool arguments, Skill/Plugin manifest, plugin source generation, or cache generation changed, ask the user to open one fresh Codex context for this generation. Do not require a new task for ordinary file edits. Collect required MCP tool names and convert the observation into a fresh-context proof with `scripts/verify/new-codex-praetor-fresh-context-proof.ps1`.
3. Produce a generation-matched provider readiness record from the capability canary, then run `activate` with both evidence files.
4. `activate` runs the reconcile once. Stable closeout also installs `scripts/install/install-codex-praetor-maintenance.ps1 -Apply`, which copies the maintenance scripts under the user's `.codex` directory and registers a user-level logon plus 15-minute retry task. The task may be inspected with `Get-ScheduledTask -TaskName CodexPraetor-GenerationReconcile`.
5. The reconcile may delete only non-active retired paths that are outside the retention window and not in use; an in-use path remains registered with a retry time. Cleanup failure does not roll back a valid activation and must not be reported as a clean cache. Isolated branch validation must pass `-SkipMaintenance` to avoid registering a real task.

Do not call the product delivered until the active receipt exists, `scripts/verify/get-codex-praetor-health.ps1 -Json` returns `ready`, the downloaded package passes the normal user path, and retirement status is explicitly `deleted`, `pending`, or `blocked_by_process`. A branch candidate must use an explicitly isolated `-UserProfileRoot` and must never overwrite the stable profile.

## 6. Final Human Confirmation

Stop before irreversible public release steps and ask for confirmation when:

- Choosing the final GitHub owner/repo URL.
- Completing GitHub account authorization outside Codex.
- Pushing the first public branch.
- Creating a new version tag or GitHub release.
- Publishing any package/archive intended for other users.
- Replacing existing GitHub Release assets with `gh release upload --clobber`.
