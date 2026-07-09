# Codex Praetor

Codex Praetor is a cost-aware external worker orchestration layer for Codex.

中文名：Codex 执政官。

Codex keeps the planning, risk judgment, integration, and final verification role. Codex Praetor dispatches bounded tasks to external lower-cost CLI agents such as Qoder, CodeBuddy, and MiMo, records job state, and gives Codex an inspectable result to verify.

## Current Status

This repository is the productization workspace for the local `codex-praetor` skill and script bundle.

Current stage:

- Skill and script migration: completed for the local baseline.
- MCP server: v0 source implemented for route-intent, dry-run dispatch, list-jobs, plan, and status; plugin MCP remains disabled until tool-card verification.
- Codex plugin package: scaffolded, not install-ready yet.
- Public GitHub release: not ready.

## Product Shape

Codex Praetor has three layers:

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
handoff/          Migration report and continuation package.
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
For now there is no automatic publish script. When local installation needs to be updated, perform one explicit copy-and-verify operation.

## First Validation

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

## Roadmap

See [docs/roadmap.md](docs/roadmap.md).


