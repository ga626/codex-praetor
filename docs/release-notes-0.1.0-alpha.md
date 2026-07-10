# Codex Praetor 0.1.0-alpha Release Notes

Status: published alpha.

## What This Release Is

Codex Praetor is a Windows-first Codex plugin and MCP tool layer for dispatching bounded work to external CLI worker agents while Codex remains the planner, supervisor, integrator, and final verifier.

Supported optional providers:

- Qoder / QoderWork CN CLI
- Tencent CodeBuddy / WorkBuddy CLI
- Xiaomi MiMo Code CLI

These providers are not bundled. Users install and sign in to them through each provider's official flow, then configure local CLI paths in an ignored local config.

## Included

- Source `codex-praetor` skill.
- Windows PowerShell wrapper scripts for dry-run, blocking dispatch, background watcher, plans, completion notification, and local publishing.
- Thin MCP server for route-intent, dry-run, list jobs, plan/status, lane listing, lane lookup, and conflict detection.
- Plugin package shape with bundled MCP runtime.
- Provider setup notes under `docs/provider-notes/`.
- Public-release doctor and minimal validation suite.
- Release package builder: `scripts/build-codex-praetor-release.ps1`.

## Verified For This Alpha

- Final public doctor gate without draft metadata placeholders.
- `scripts/test-codex-praetor.ps1`.
- `npm test --prefix .\mcp`.
- Local release package build and private-marker check.
- Plugin MCP protocol smoke.
- Fresh Codex project-thread acceptance with native `codex-praetor` MCP tool calls.
- MiMo readonly canary.
- CodeBuddy readonly canary: `CP_CODEBUDDY_PROVIDER_DOCS_CANARY`.
- Qoder readonly canary: `CP_QODER_PROVIDER_DOCS_CANARY`.
- Installed C-drive skill is a real copied directory, not a link.
- Personal plugin install/cache publish path was refreshed. A running Codex process may keep one older cache directory locked until Codex reloads.

## Known Alpha Boundaries

- Windows first.
- Codex first.
- Provider accounts, credits, login state, and pricing are owned by each provider and the user's account.
- Codex Praetor does not install providers, log in for users, read provider auth databases, or promise free routing.
- Current open Codex threads may keep stale MCP transports after plugin changes. Final acceptance requires a fresh Codex tool context.
- GitHub publication should use GitHub CLI browser/device auth. Do not paste Personal Access Tokens into Codex, docs, scripts, issues, release notes, or config files.

## Post-Alpha Follow-Ups

- Improve first-run setup around provider CLI discovery, login guidance, and capability canaries.
- Make stale plugin-cache cleanup friendlier when a running Codex process holds the old cache directory open.
- Keep expanding native MCP acceptance coverage as Codex App plugin/tool loading evolves.
