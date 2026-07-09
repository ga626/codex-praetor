# Codex Praetor

Codex Praetor is a cost-aware external worker orchestration layer for Codex.

中文名：Codex 执政官。

Codex keeps the planning, risk judgment, integration, and final verification role. Codex Praetor dispatches bounded tasks to external lower-cost CLI agents such as Qoder, CodeBuddy, and MiMo, records job state, and gives Codex an inspectable result to verify.

## Current Status

This repository is the productization workspace for the local `codex-praetor` skill and script bundle.

Current stage:

- Skill and script migration: completed for the local baseline.
- MCP server: v0 source implemented for route-intent, dry-run dispatch, list-jobs, plan, status, lane listing, lane lookup, and conflict detection.
- Plugin package: local personal-plugin packaging and protocol smoke are working; final public repository URLs and fresh-context native MCP verification are still required.
- Real worker chain: one MiMo readonly release audit has run successfully in an isolated worktree.
- Public GitHub release: not ready until install docs, final URLs, provider UX, and native MCP canary are complete.

## Product Shape

Codex Praetor has four layers:

1. Skill: natural-language workflow for Codex.
2. Scripts: deterministic Windows-friendly worker dispatch and job recording.
3. MCP: thin TypeScript wrapper around existing scripts for visible tool calls and job state.
4. Plugin: planned package shape for distribution.

## Boundaries

- Codex Praetor does not spawn Codex subagents by default.
- Codex Praetor does not use provider `auto` by default.
- Codex remains responsible for final verification.
- Worker edits must use an isolated worktree.
- Worker-generated artifacts should stay next to the current project under a project-local artifact root.
- Secrets, tokens, account databases, provider caches, and personal usage screenshots must not be committed.

## Layout

```text
README.md         Human entry point.
AGENTS.md         Instructions for future Codex agents working in this repo.
docs/             Architecture, roadmap, evidence, provider notes.
skill/            Source skill package for local development.
scripts/          Source dispatch, watcher, plan, and notification scripts.
mcp/              TypeScript MCP server source.
plugin/           Final Codex plugin package shape.
config/           Example provider/model tier config.
examples/         Small validation examples.
```

## Development vs Package Shape

Keep development files and final distribution files separate:

- Edit the source skill in `skill/codex-praetor`.
- Edit source scripts in `scripts`.
- Build MCP code under `mcp`.
- Treat `plugin` as the installable Codex plugin package shape.
- Treat `%USERPROFILE%\.codex\skills\codex-praetor` as the local installed skill, not as the source tree.

This mirrors the source-vs-distribution style used by mature tooling projects: agents can read the shallow source folders easily, while `plugin/` stays close to the final package that a Codex user would install.

Do not hide active source files under a deep package tree. If a future build step is added, generate release artifacts outside the source folders or into an ignored output folder.

## Local Installation Boundary

This repository is not loaded by Codex automatically. Codex loads the installed skill from:

```text
%USERPROFILE%\.codex\skills\codex-praetor
```

When the source skill changes, publish it by copying files into the installed skill directory. Do not use symlinks or path redirection for the local install.
Use the explicit publish script when local installation needs to be updated:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\publish-codex-praetor-skill.ps1 -Apply
```

This is a deliberate copy-and-verify operation, not automatic sync.

## Requirements

- Windows
- PowerShell
- Git
- Node.js and npm for MCP development and plugin runtime
- Codex with local skills/plugins enabled
- Optional provider CLIs for real dispatch:
  - Qoder or QoderWork CN CLI
  - Tencent CodeBuddy or WorkBuddy CLI
  - Xiaomi MiMo Code CLI

Codex Praetor does not install or log in to these providers for the user. Configure local CLI paths in an ignored local config and complete provider login through the provider's normal flow.

Provider setup notes:

- [Qoder](docs/provider-notes/qoder.md)
- [CodeBuddy](docs/provider-notes/codebuddy.md)
- [MiMo](docs/provider-notes/mimo.md)

## Setup

1. Clone the repository.
2. Copy `config/codex-praetor-tiers.example.json` to an ignored local config such as `config/codex-praetor.local.json`.
3. Fill in provider CLI paths for only the providers you have installed. Leave uninstalled providers as template paths; doctor will report them as optional disabled providers.
4. Run doctor:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\doctor-codex-praetor.ps1 -RequireHead -PublicRelease
```

Doctor uses `info` for provider facts that are intentionally not auto-verified, such as account login state. A missing provider is not a product failure; it only disables real dispatch for that provider. A provider is ready for real work only after a dry-run or readonly canary succeeds for that provider.

5. Run the minimal validation suite:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\test-codex-praetor.ps1
```

6. Start with a dry-run before any real dispatch.

If you have no provider installed yet, stop after doctor and MCP/plugin checks. You can still validate the local project shape, but real Qoder/CodeBuddy/MiMo dispatch will wait until you install and sign in to at least one provider.

## First Validation

Project commits are guarded by Git hooks under `.githooks/`, installed through `scripts/install-codex-praetor-hooks.ps1`. They run the release doctor and minimal test suite before commit or push. These are Git hooks, not Codex background hooks.

Run a dry-run before any real worker call:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\invoke-codex-praetor.ps1 -Provider mimo -Tier mimo-auto-readonly -Repo "<repo>" -Task "Dry run only. Verify Codex Praetor." -Mode readonly -DryRun
```

For the current project baseline, run the repeatable minimal verification set:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\test-codex-praetor.ps1
```

The validation script also runs the MCP package self-test. To run MCP tests directly:

```powershell
cd .\mcp
npm test
```

To rebuild the plugin-bundled MCP runtime:

```powershell
cd .\mcp
npm install
npm run build:plugin
```

## Troubleshooting

- If a provider is missing, Codex Praetor can still do route-intent, plan, dry-run, and status work, but real worker dispatch for that provider is disabled.
- If a provider is installed but not logged in, complete the provider's normal login flow outside Codex Praetor.
- If doctor reports `provider:<name>:cli` as `disabled`, install that provider or update only your ignored local config.
- If doctor reports provider auth as `info`, that is expected. Codex Praetor does not read provider account databases; prove login with a provider readonly canary.
- If MCP tools are visible but calls fail with `Transport closed`, remove duplicate same-name MCP registrations, republish the plugin, and verify in a refreshed Codex tool context. The current open thread may keep a stale transport.
- If worktree creation fails, make sure the target repository has at least one commit.
- If MiMo writes `.mimocode`, it should happen inside the isolated worktree, not the main repository.

## Roadmap

See [docs/roadmap.md](docs/roadmap.md).


