# Codex Praetor Project Rules

## Product Boundary

Codex Praetor serves Codex. It dispatches bounded work to external lower-cost CLI agents and keeps Codex as the planner, supervisor, and verifier.

Do not implement a broad generic multi-agent platform unless the user explicitly changes the product scope.

## Naming

Use these names consistently:

- Product display name: `Codex Praetor`
- Chinese name: `Codex 执政官`
- Repository name: `codex-praetor`
- Skill name: `codex-praetor`
- MCP server name: `codex-praetor`
- MCP tool prefix: `codex_praetor_`
- Local project path: this repository checkout.

Do not reintroduce `cheap-worker-orchestrator`, `WorkerLane`, or `workerlane` as active product names.

## Structure

Keep source and distribution paths separate but shallow:

- `skill/` is the source skill.
- `scripts/` is the source script set, grouped by role: `dispatch/`, `install/`, `verify/`, `release/`, and `maintenance/`.
- `mcp/` is the MCP source.
- `plugin/` is the final Codex plugin package shape.

Prefer updating root-level docs over burying important decisions in deep folders.

## Local Install Boundary

This repository checkout is the development project, not the installed Codex skill path.

The local installed skill remains under the current Windows user's Codex home:

```text
%USERPROFILE%\.codex\skills\codex-praetor
```

Do not replace the installed skill with a symlink, junction, shortcut, or path pointer to D drive.

Do not add an automatic publish/sync mechanism unless the user explicitly asks for it. When local installation needs to be updated, do one explicit copy-and-verify operation.

## Safety

Do not commit API keys, auth tokens, provider account files, usage screenshots, or local app databases.

Do not mutate Qoder, CodeBuddy, or MiMo internal databases. Use their official CLI surfaces.

Codex Praetor must not spawn Codex subagents by default. For cost-saving delegation, use external CLI workers.

## Verification

Before saying a rename or migration is complete:

- Scan for old names: `cheap-worker-orchestrator`, `WorkerLane`, `workerlane`, old script names.
- Run a dry-run through `scripts/dispatch/invoke-codex-praetor.ps1`.
- Confirm the skill frontmatter name is `codex-praetor`.
- Confirm plugin manifest name is `codex-praetor`.
- Confirm runtime outputs are ignored by Git and stay project-local.
- Confirm the C drive installed skill is a real directory, not a link to this repo.
