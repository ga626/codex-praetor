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

## 发布交付边界

用户入口是 GitHub Release 的 `codex-praetor-setup-*.zip`，不是 `main` 源码树本身。

凡改到 `setup.cmd`、`setup.ps1`、`plugin/`、`skill/`、`mcp/`、安装/排错/发布文档、版本号或安装体验，都算影响发布。用户合并这类 PR 后，必须同步最新 `main`，构建 zip 和 `.sha256`，更新 GitHub Release 资产/说明，再下载远端 zip、解压复验 setup 文件、文档、版本和关键向导行为，才能说产品已交付。

### Release Generation And Closeout

- A release is one immutable generation: version, main commit, release zip SHA256, runtime contract, Skill tree, plugin tree, cache tree, marketplace activation, fresh-context MCP proof, and provider readiness must be recorded in one release receipt.
- A branch build is a candidate only. It must not overwrite the current user's stable Skill, plugin, cache, marketplace activation, or active receipt. Dev validation uses an explicitly supplied isolated user-profile root.
- Stable closeout is two phase: stage and hash-verify all local surfaces from the downloaded Release zip, then activate only after a fresh Codex context proves the required native MCP tools and a generation-matched provider readiness record passes.
- There is no cross-directory filesystem transaction. If stage or activation fails, do not write a new active receipt; keep or restore the previous active generation and report `代码已合并，产品未交付`.
- Real dispatch must fail closed when the active receipt, any install surface hash, marketplace entry, fresh-context proof, or provider readiness does not match the runtime contract generation.

## Research Authority

- Codex plus KnowledgeRadar owns external research routes and final evidence synthesis. Provider workers may do readonly candidate discovery or independent replication only under a Codex-issued research contract with `codex_kr_primary` authority and `supervisor_verified` acceptance.
- A worker research result must include source URL, retrieval time, excerpt, claim, and uncertainty. It cannot independently satisfy high-risk fact checks, cross-source conclusions, release decisions, or user-facing recommendations.

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
