# GitHub Publish Runbook

Date: 2026-07-19
Target release: `0.16.32-alpha`

Status: `v0.16.14-alpha` stopped before creating a tag, Release, or public download. It must not be backfilled or overwritten. `v0.16.32-alpha` is the next immutable recovery release and is published automatically by `Release On Main` after this PR reaches `main`.

This runbook defines the single merge-to-release pipeline. A release-impacting PR is not merge-ready until it contains the version surface, `config/release-intent.json`, release notes, and passing candidate gates. After merge, GitHub Actions builds the exact merge commit, creates a draft Release, uploads all assets, publishes it, and verifies the remote download. There is no manual post-merge publish step.

## Hard Rules

- 本机 GitHub 发布链路默认走用户当前代理节点：每次推送、创建 PR、查询 Actions/Release 或下载资产前，先在 `127.0.0.1:7897` 临时代理下完成不超过 20 秒的 HTTPS 与 `git ls-remote --heads origin main` 探针。只有这两项都通过，才对当次 Git 与 `gh` 命令设置进程级 `HTTP_PROXY`、`HTTPS_PROXY`、`ALL_PROXY`；代理失败则停止并提示更换节点。直连不是正常发布候选，也不能自动作为代理失败后的兜底，除非用户明确当前节点支持直连或要求做诊断对照。

- 这条代理规则只覆盖本机控制面：`git fetch/push/ls-remote`、`gh` 查询和本机远端下载。GitHub-hosted Actions 的 runner 不经过本机代理；因此在两项本机代理探针均通过后，CI 或 `Release On Main` 失败必须读取其 run 日志并按权限、workflow、候选内容或 GitHub runner 故障处理，不能通过切直连、重配本机代理或手工替换 Release 资产掩盖。

- Do not paste GitHub Personal Access Tokens into Codex, docs, scripts, issues, release notes, or config files.
- If a token is pasted into any chat, issue, log, or terminal transcript, revoke it immediately in GitHub before continuing.
- Prefer GitHub CLI browser/device login over raw token handling.
- The repository must have a protected `main` branch, required CI checks, and `contents: write` permission for the `Release On Main` workflow.
- Release tags and assets are immutable. A version already tagged on another commit is a hard failure, never an asset replacement.
- A publishable artifact must have an `artifact_verified` manifest matching its zip SHA; the publisher may not rebuild a second upload candidate.
- 合并后的 main commit 与 PR candidate head 通常不是同一个 SHA。promotion 必须以候选回执和 `source_tree` 证明它们内容相同；不得把“SHA 不同”当成 artifact 失效，也不得在树不同的情况下提升候选包。
- The automatic workflow is the only supported public release path; do not run the old manual sequence after merge.

## User-Owned One-Time Actions

1. Revoke any exposed token:

   https://github.com/settings/tokens

2. Install GitHub CLI if `gh --version` is not available:

   https://cli.github.com/

3. Sign in with a browser or device-code flow:

   ```powershell
   gh auth login
   gh auth status
   ```

4. Tell Codex the final owner/repo pair, for example:

   ```text
   OWNER/codex-praetor
   ```

These are the only manual steps expected before Codex can run the GitHub publication commands.

## Codex-Owned Publication Steps

After `gh auth status` succeeds and the user confirms the final owner/repo:

1. Confirm the working tree and release gates:

   ```powershell
   git status --short
   powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\verify\invoke-release-candidate-preflight.ps1 -BaseRef origin/main -CheckRemote -AllowDraftMetadataPlaceholders
   ```

2. Create or connect the GitHub repository:

   ```powershell
   gh repo create OWNER/codex-praetor --public --source . --remote origin --description "Codex external worker orchestration plugin and MCP layer" --disable-wiki
   ```

   If the repository already exists, use:

   ```powershell
   git remote add origin https://github.com/OWNER/codex-praetor.git
   ```

3. Replace draft metadata:

   ```powershell
   powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\release\set-codex-praetor-public-metadata.ps1 -RepositoryUrl https://github.com/OWNER/codex-praetor -Apply
   ```

4. Re-run final gates without draft placeholders:

   ```powershell
   powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\verify\invoke-release-candidate-preflight.ps1 -BaseRef origin/main -CheckRemote
   ```

5. Run the final fresh-context native MCP canary:

   ```text
   docs/architecture/fresh-context-native-mcp-canary.md
   ```

6. Prepare the release through the same PR that changes the product. Run the version updater, commit `config/release-intent.json`, the matching release notes and changelog, then run:

   ```powershell
   powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\release\set-codex-praetor-version.ps1 -Version NEXT_VERSION -Apply
   powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\verify\test-release-intent.ps1 -BaseRef origin/main -RequireReleaseImpact
   ```

7. After the PR merges, `Release On Main` performs, in one idempotent workflow:

   - checkout of the exact merge commit;
   - release-intent, source, MCP, product, public-entry and deterministic package gates;
   - creation of the tag and a draft Release;
   - real bundled-MCP proof of the final zip, then upload of that same SHA and `.sha256` before publishing the immutable Release;
   - download/hash/entry/notes verification through `verify-github-release-asset.ps1`.

   A workflow failure is a delivery incident with an explicit run URL, not a hidden manual tail. It must be retried or fixed before the next release-impacting PR.

   CI uses `same-artifact` verification against its own verified manifest. A later local audit of an already published Release must use `-VerificationMode published-artifact`; it verifies the downloaded zip, sidecar hash and tag commit without treating an old local candidate as a remote-release failure.

8. 远端下载复验通过后，Codex 在本机执行同一 Release 的自动激活：

   ```powershell
   powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\release\activate-published-codex-praetor-release.ps1 -Version 0.16.32-alpha -Json
   ```

   它不手改 cache 或用户 readiness；会停在 `needs_host_restart` 或 `needs_first_use_bootstrap`。前者只需要一次受支持的 Desktop 刷新，之后必须用 `runtime_info` 验明运行身份。后者不是发布失败：用户完成 provider 官方登录后，第一次真实计划任务会在隔离 worktree 中自动记录首用 readiness；不要求用户手动运行内部 canary。

   发布维护者先完成最终 artifact 和隔离用户目录的零积分验证。只有 provider compatibility fingerprint 变化时，才对受影响 provider 各完成一条经 Codex 验收的真实只读任务；canary 仅用于排障，不重复计作发布前置。维护者证据证明发布包能走通，不冒充普通用户的账号 readiness。

9. 已公开 Release 只能下载复验，不能替换资产或修改说明。源代码、合同或 artifact 有缺陷时，必须使用递增版本的恢复 PR。

候选硬门：`build-codex-praetor-release.ps1 -Apply` 只能从干净提交运行；维护者不得用本地脏工作树 ZIP 代替 PR CI artifact。`activate-pr-candidate.ps1` 是候选安装唯一入口，显式 ZIP 没有 `codex-praetor-release-candidate/v1` receipt 时会被阻断。重启前先确认目标 generation 已安装，重启后第一步用新任务读取 `runtime_info`。

## Blockers That Stop Publication

- `gh auth status` fails or GitHub CLI is missing.
- The final owner/repo is unknown.
- Public metadata still contains placeholder URLs.
- Public release scan finds local paths, account data, auth/token/secret material, provider caches, or private evidence.
- Fresh-context native MCP canary fails.
- `Release On Main` lacks repository write permission or required branch protection.
- The GitHub Release zip, notes, public README, installation guide, or roadmap point to different user-downloadable versions.
## 发布事故恢复边界

不要在 `main` 上手工运行发布脚本，也不要从最新分支头部手工 dispatch 发布 workflow。

- 已经创建 tag、draft Release 或公开 Release：在对应的 GitHub Actions run 页面使用 **Re-run jobs**。GitHub 会保留原始 `GITHUB_SHA`，所以它是同一交付物的恢复，不是新代码覆盖旧版本。
- 在创建 tag 前、且根因是 workflow 定义本身：先登记 `docs/release/incidents/`，再以递增版本建立恢复 PR。该 PR 仍由 `Release On Main` 自动发布。
- 任何恢复完成后都要重新走远端下载复验和本机交付链路；不能把 workflow 绿灯直接称为产品已交付。

## 依赖更新 PR 的处理

`mcp/`、plugin 或安装包依赖会进入用户下载的 zip，因此属于发布影响变更。Dependabot 可以继续提出候选 PR，但它不会自动填写产品版本、release notes 和 release intent；这类 PR 的失败门禁是预期的“不得直接合并”信号。审阅通过后，把依赖变更纳入下一份显式递增版本的产品 PR，而不是绕过门禁合并。
# Candidate-first release sequence

1. PR CI builds, package-tests, and attests the one candidate ZIP before any real provider or Desktop-host proof is requested.
2. The maintainer activates that ZIP with its candidate receipt; the installer automatically preserves the preceding stable plugin.
3. After one supported Desktop refresh, `runtime_info` proves the candidate generation. In a new task, enable Codex Praetor execution mode and complete one bounded real `code_change` task through route, contract preflight, worker startup, completion and Codex acceptance. Use `write-candidate-user-path-evidence.ps1` with that accepted plan/job and the installed Skill, then pass its output to `write-candidate-host-receipt.ps1`. Add the resulting candidate-host receipt to the PR body under `<!-- codex-praetor-candidate-host-receipt -->`.
4. Only then merge. Main retrieves the existing ZIP, verifies the receipt and source tree, creates a draft, uploads the same ZIP, downloads it for SHA/package verification, then publishes the draft.

Do not rebuild after host acceptance, substitute an asset, or rerun a public provider task after publication. A failed tag or draft is a release incident: rerun the original workflow SHA and preserve the existing candidate/draft evidence.
