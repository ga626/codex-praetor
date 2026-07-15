# Codex Praetor Release Gate Checklist

Date: 2026-07-13

This checklist separates the development repository from the user-facing release package. The goal is a Windows-first Codex plugin users can install and operate, not a dump of every local development artifact.

## 1. Development Validation Layer

These checks protect the source repository. They may stay in the repo, but they are not the product experience.

- Git hooks: `.githooks/pre-commit` and `.githooks/pre-push` through `core.hooksPath`.
- GitHub CI: `.github/workflows/ci.yml` runs doctor with the public template, minimal validation, MCP tests, and a release package build.
- Release doctor: draft CI can run `scripts/verify/doctor-codex-praetor.ps1 -RequireHead -PublicRelease -AllowDraftMetadataPlaceholders`; final public release must run without `-AllowDraftMetadataPlaceholders`.
- Minimal validation: `scripts/verify/test-codex-praetor.ps1`.
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
- Draft release notes: `docs/release/release-notes-0.1.2-alpha.md`.
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
- Tag only after a new user path succeeds: clone -> doctor -> dry-run -> optional readonly canary.
- After a delivery-affecting PR is merged, update the GitHub Release zip, `.sha256`, and notes from latest `main` with `scripts/release/publish-github-release-asset.ps1 -Apply`; it must finish by running `scripts/release/verify-github-release-asset.ps1`.
- For the `0.1.2-alpha` orchestration-loop release, remote-download validation must prove the downloaded package exposes the new dispatch/result/verification MCP tools before calling the product delivered.

## 6. Final Human Confirmation

Stop before irreversible public release steps and ask for confirmation when:

- Choosing the final GitHub owner/repo URL.
- Completing GitHub account authorization outside Codex.
- Pushing the first public branch.
- Creating the `0.1.2-alpha` tag or GitHub release.
- Publishing any package/archive intended for other users.
- Replacing existing GitHub Release assets with `gh release upload --clobber`.
