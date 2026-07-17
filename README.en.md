# Codex Praetor

[简体中文](README.md) | [English](README.en.md)

Codex Praetor is a Windows-first Codex plugin and MCP layer for dispatching bounded work to external CLI worker agents while Codex remains the planner, supervisor, integrator, and final verifier.

Current productization target: **0.4.0-alpha**.

[Download 0.4.0-alpha](https://github.com/ga626/codex-praetor/releases/tag/v0.4.0-alpha) · [Chinese installation guide](docs/user/installation.zh.md) · [Chinese troubleshooting guide](docs/user/troubleshooting.zh.md)

## What It Does

When you ask Codex to split a task or assign part of the work to another agent, Codex Praetor routes bounded work to local external CLIs such as Qoder, CodeBuddy, and MiMo instead of creating native Codex subagents by default.

The supported alpha scope is intentionally narrow:

- Windows
- Codex Desktop or Codex CLI
- Local CLI workers
- Chinese-first user documentation
- Qoder, CodeBuddy, and MiMo provider paths

## Quick Start

Download and extract the release zip:

```powershell
Invoke-WebRequest -Uri "https://github.com/ga626/codex-praetor/releases/download/v0.4.0-alpha/codex-praetor-setup-0.4.0-alpha.zip" -OutFile ".\codex-praetor-setup-0.4.0-alpha.zip"
Expand-Archive .\codex-praetor-setup-0.4.0-alpha.zip .\codex-praetor-setup-0.4.0-alpha
cd .\codex-praetor-setup-0.4.0-alpha
```

Preview the install:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\setup.ps1
```

Install:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\setup.ps1 -Apply
```

Restart Codex or open a new task, then start with a dry-run:

```text
拆分一下任务，分配给其他 agent 做 dry-run，不要真实修改文件。
```

## Provider Boundary

Qoder, CodeBuddy, and MiMo are optional external CLIs. They are not bundled.

Codex Praetor does not install providers, sign in for users, inspect provider account databases, read tokens or cookies, or promise that provider routing is free. Users install and authenticate each provider through that provider's normal flow.

Without a provider, Codex Praetor can still validate planning, route-intent, dry-run, job status, lane listing, and conflict detection. Real dispatch needs at least one installed and authenticated provider.

The 0.4.0-alpha source line records logical tasks, immutable worker attempts, evidence, and Codex supervisor verdicts separately. A worker process exit is not enough to advance dependent tasks; Codex must verify and record an accepted result first.

## Readonly Provider Canary

Before real dispatch, run a readonly canary. It previews the command by default:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\verify\test-provider-readonly-canary.ps1 -Provider mimo
```

After the provider is installed and signed in, add `-Apply`:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\verify\test-provider-readonly-canary.ps1 -Provider mimo -Apply
```

The canary asks the worker to read `README.md`, return a fixed marker, and leave the main repository status unchanged.

## Development Validation

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\verify\doctor-codex-praetor.ps1 -RequireHead -PublicRelease
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\verify\test-codex-praetor.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\verify\test-provider-readonly-canary.ps1 -Provider mimo
```

MCP tests:

```powershell
cd .\mcp
npm test
```

## Release Package Boundary

The release builder excludes internal handoff files, `docs/internal`, local configs, auth/token/secret files, provider caches, runtime job state, `node_modules`, and personal screenshots.

## Repository Layout

- `docs/`: documentation grouped by audience: `user`, `architecture`, `release`, and `reports`.
- `scripts/`: source scripts grouped by role: `dispatch`, `install`, `verify`, `release`, and `maintenance`.
- `skill/`: source skill package.
- `mcp/`: TypeScript MCP server source.
- `plugin/`: final Codex plugin package shape.

## More

- Architecture: [docs/architecture/architecture.md](docs/architecture/architecture.md)
- Roadmap: [docs/roadmap.md](docs/roadmap.md)
- Security: [SECURITY.md](SECURITY.md)
- Contributing: [CONTRIBUTING.md](CONTRIBUTING.md)
