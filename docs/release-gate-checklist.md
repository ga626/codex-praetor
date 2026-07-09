# Codex Praetor Release Gate Checklist

Date: 2026-07-10

This checklist separates the development repository from the user-facing release package. The goal is a Windows-first Codex plugin users can install and operate, not a dump of every local development artifact.

## 1. Development Validation Layer

These checks protect the source repository. They may stay in the repo, but they are not the product experience.

- Git hooks: `.githooks/pre-commit` and `.githooks/pre-push` through `core.hooksPath`.
- Release doctor: `scripts/doctor-codex-praetor.ps1 -RequireHead -PublicRelease`.
- Minimal validation: `scripts/test-codex-praetor.ps1`.
- MCP source tests: `npm test` under `mcp/`.
- Plugin protocol smoke: `mcp/scripts/smoke-plugin-mcp.js` against the packaged runtime.
- Public marker scan: no personal account paths, auth files, local caches, or token-bearing artifacts in public paths.

## 2. User-Facing Release Package

The release package should contain only what helps a user install, configure, and run Codex Praetor.

Include:

- `plugin/` package shape with `.codex-plugin/plugin.json`, `.mcp.json`, bundled `plugin/mcp/dist/server.js`, and `plugin/skills/codex-praetor`.
- Root `README.md`, `LICENSE`, `CHANGELOG.md`, `SECURITY.md`, `CONTRIBUTING.md`.
- `config/codex-praetor-tiers.example.json` as a template with no real local paths.
- Provider setup references for Qoder, CodeBuddy, and MiMo.
- A minimal `examples/` folder with dry-run and readonly canary examples.

Exclude from release bundles/assets:

- `handoff/`, `docs/internal/`, and private archaeology notes.
- `*.local.json`, `.env*`, auth/token/key files, screenshots, account databases, and provider caches.
- `mcp/node_modules/`, source build cache, test scratch, worktrees, job logs, and `.codex-praetor` runtime state.
- Machine-specific Codex config backups.

## 3. Provider UX Gate

Before release, a normal Windows user should see clear doctor states:

- CLI missing: what to install and where to configure `cliPath`.
- CLI installed: version probe result.
- Login unknown: clear instruction to complete the provider's normal login outside Codex Praetor.
- Capability mismatch: version/help probe fails or required flags are not accepted.
- No providers installed: local planning/dry-run/status still works, real dispatch is disabled.

Codex Praetor must not install providers, log in for the user, read provider auth databases, or promise free/cheap routing that depends on the user's account.

## 4. MCP Gate

Protocol smoke is necessary but not enough.

Required before release:

- Packaged runtime imports successfully.
- Protocol smoke can call route-intent, dry-run, lane listing, and conflict detection.
- Fresh Codex tool context shows native Codex Praetor MCP tools.
- Fresh-context native calls succeed for route-intent and dry-run.
- The current-thread `Transport closed` issue is documented as a reload/cache boundary, not treated as server failure.

## 5. GitHub Gate

Before pushing or tagging:

- Set the real GitHub remote.
- Replace `https://github.com/YOUR_GITHUB_OWNER/codex-praetor` in plugin metadata.
- Re-run the public marker scan after the final URL change.
- Enable or document GitHub secret scanning/push protection expectations.
- Confirm license, changelog entry, security policy, and README install path are current.
- Tag only after a new user path succeeds: clone -> doctor -> dry-run -> optional readonly canary.

## 6. Final Human Confirmation

Stop before irreversible public release steps and ask for confirmation when:

- Choosing the final GitHub owner/repo URL.
- Pushing the first public branch.
- Creating the `0.1.0-alpha` tag or GitHub release.
- Publishing any package/archive intended for other users.
