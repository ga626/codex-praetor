# Codex Praetor Release Gate Checklist

Date: 2026-07-13

This checklist separates the development repository from the user-facing release package. The goal is a Windows-first Codex plugin users can install and operate, not a dump of every local development artifact.

## 1. Development Validation Layer

These checks protect the source repository. They may stay in the repo, but they are not the product experience.

- Git hooks: `.githooks/pre-commit` and `.githooks/pre-push` through `core.hooksPath`.
- GitHub CI: `.github/workflows/ci.yml` runs doctor with the public template, product validation, public-entry consistency, MCP tests, release package build, and release package determinism.
- Release doctor: draft CI can run `scripts/verify/doctor-codex-praetor.ps1 -RequireHead -PublicRelease -AllowDraftMetadataPlaceholders`; final public release must run without `-AllowDraftMetadataPlaceholders`.
- Product validation: `scripts/verify/test-codex-praetor.ps1`. This default gate must not depend on the current developer's global Codex rules, installed skill copy, provider login state, or local provider account data.
- Durable job lifecycle regression: `scripts/verify/test-job-lifecycle.ps1` covers exit-code-zero semantic failure, timeout, and cancellation terminal-state preservation.
- Developer environment validation: `scripts/verify/test-codex-praetor-dev-env.ps1`. Use this when the change specifically touches local Codex installation, installed skill sync, provider dry-run behavior, or global-rule integration.
- Release receipt contract validation: `scripts/verify/test-release-receipt-contract.ps1` checks the staged/active/delivered state contract used by closeout receipts.
- Dev channel isolation validation: `scripts/verify/test-dev-channel-isolation.ps1` stages a candidate into a disposable profile and proves it cannot create a stable active receipt.
- Release intent validation: `scripts/verify/test-release-intent.ps1` requires every release-impacting PR to carry the version, tag, artifact and auto-on-main release contract.
- Mainline publication workflow: `.github/workflows/release-on-main.yml` is the only supported path from a merged release-impacting PR to an immutable GitHub Release.
- Candidate CI and mainline publication must call the same `.github/workflows/release-pipeline.yml`; action pins, setup and package gates may not be maintained as two copies.
- Public entry consistency: `scripts/verify/test-public-entry-consistency.ps1`. Use `-SkipRemoteRelease` before publication and the full remote check during release closeout.
- Release package determinism: `scripts/verify/test-release-package-determinism.ps1`. The same staged release content must produce the same zip SHA256, stable entry order, and fixed zip entry timestamps.
- Continuous orchestration MCP validation: route-intent, dry-run, real dispatch tool listing, result reading, next-ready lookup, plan-task dispatch tool listing, and verify-task recording must pass protocol smoke before release.
- Provider readonly canary preview: `scripts/verify/test-provider-readonly-canary.ps1 -Provider mimo`.
- MCP source tests: `npm test` under `mcp/`.
- Plugin protocol smoke: `mcp/scripts/smoke-plugin-mcp.js` against the packaged runtime.
- Final artifact runtime acceptance: `scripts/verify/test-release-artifact-runtime.ps1` extracts the exact zip and starts its `plugin/mcp/dist/server.js`; it must verify the handshake version, runtime contract, required MCP tools and generation manifest before publication.
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
- Current release notes: `docs/release/release-notes-0.6.1-alpha.md`.
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
- `scripts/verify/reload-codex-praetor-mcp.ps1 -Json` reports what a separately started app-server resolves; it must state that it does not refresh Desktop.
- `scripts/verify/probe-codex-praetor-mcp.ps1 -Json` is a separate-host thread probe, not proof that the current Desktop host changed.
- Native `codex_praetor_runtime_info` from the Desktop canary binds version, contract SHA256, path, PID, and start time to the staged generation.
- Fresh Codex tool context shows native Codex Praetor MCP tools.
- Fresh-context native calls succeed for route-intent and dry-run.
- A stale Desktop host is documented as a host-discovery boundary, not treated as a server failure or solved by repeatedly opening new tasks.
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
- A release-impacting PR must merge with `config/release-intent.json`, the matching version surfaces, release notes and changelog already committed. After merge, `.github/workflows/release-on-main.yml` automatically builds, publishes and verifies the immutable Release from that exact merge commit. There is no manual post-merge publish command.
- `previous_version` must equal the target branch intent and `version` must be greater. If a tag/draft/Release exists, recover only by re-running the original Actions run; do not dispatch latest `main`, reuse a tag, or open a version-hiding follow-up PR. A pre-tag workflow-definition failure is the sole exception: record an incident and use one explicitly incremented recovery version.
- Remote-download validation must prove the downloaded package exposes the intended user-facing behavior before calling the product delivered.
- A green source test is not enough: the final zip is the release candidate. If the extracted runtime differs from source or the smoke cannot start, publication is blocked before tag/Release creation.

## 5.1 Release Generation Closeout

For every delivery-affecting release, run `scripts/release/complete-codex-praetor-release.ps1` in two phases after the new GitHub Release zip and `.sha256` are available:

1. `stage` against the downloaded remote zip. It installs and hashes Skill, plugin, marketplace, and personal cache, then writes only a staged receipt. It must not delete old cache generations; old paths go to the retirement/reconcile queue.
2. If the MCP tool list, tool arguments, Skill/Plugin manifest, plugin source generation, or cache generation changed, first ensure the already-running Desktop host has refreshed its plugin discovery state. A new task alone is not sufficient. Collect native tool names and the full `codex_praetor_runtime_info` response, then convert that observation into a fresh-context proof with `scripts/verify/new-codex-praetor-fresh-context-proof.ps1`.
3. Produce a generation-matched provider readiness record from the capability canary, then run `activate` with both evidence files.
4. `activate` runs the reconcile once. Stable closeout also installs `scripts/install/install-codex-praetor-maintenance.ps1 -Apply`, which copies the maintenance scripts under the user's `.codex` directory and registers a user-level logon plus 15-minute retry task. The task may be inspected with `Get-ScheduledTask -TaskName CodexPraetor-GenerationReconcile`.
5. `activate` means only that the generation is active. It does not mean the product is delivered. After the ordinary user path succeeds, write a `codex-praetor-user-path-proof/v1` file and run `complete-codex-praetor-release.ps1 -Phase deliver -UserPathProofPath <proof>`. The receipt reaches `delivered` only in this phase.
6. The reconcile may delete only non-active retired paths that are outside the retention window and not in use; an in-use path remains registered with a retry time. Cleanup failure does not roll back a valid activation and must not be reported as a clean cache. Isolated branch validation must pass `-SkipMaintenance` to avoid registering a real task.

Do not call the product delivered until the active receipt exists, `scripts/verify/get-codex-praetor-health.ps1 -Json` returns `ready`, the downloaded package passes the normal user path, and retirement status is explicitly `deleted`, `pending`, or `blocked_by_process`. A branch candidate must use an explicitly isolated `-UserProfileRoot` and must never overwrite the stable profile.

## 6. Final Human Confirmation

Stop before irreversible public release steps and ask for confirmation when:

- Choosing the final GitHub owner/repo URL.
- Completing GitHub account authorization outside Codex.
- Pushing the first public branch.
- Creating a new version tag or GitHub release.
- Publishing any package/archive intended for other users.
- Replacing existing GitHub Release assets with `gh release upload --clobber`.
