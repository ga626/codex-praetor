# GitHub Publish Runbook

Date: 2026-07-19
Target release: `0.9.4-alpha`

Status: `v0.9.3-alpha` is a public release incident and must not be activated or overwritten. `v0.9.4-alpha` is its new immutable recovery release and is published automatically by `Release On Main` after this PR reaches `main`.

This runbook defines the single merge-to-release pipeline. A release-impacting PR is not merge-ready until it contains the version surface, `config/release-intent.json`, release notes, and passing candidate gates. After merge, GitHub Actions builds the exact merge commit, creates a draft Release, uploads all assets, publishes it, and verifies the remote download. There is no manual post-merge publish step.

## Hard Rules

- Do not paste GitHub Personal Access Tokens into Codex, docs, scripts, issues, release notes, or config files.
- If a token is pasted into any chat, issue, log, or terminal transcript, revoke it immediately in GitHub before continuing.
- Prefer GitHub CLI browser/device login over raw token handling.
- The repository must have a protected `main` branch, required CI checks, and `contents: write` permission for the `Release On Main` workflow.
- Release tags and assets are immutable. A version already tagged on another commit is a hard failure, never an asset replacement.
- A publishable artifact must have an `artifact_verified` manifest matching its zip SHA; the publisher may not rebuild a second upload candidate.
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
   powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\verify\doctor-codex-praetor.ps1 -RequireHead -PublicRelease -AllowDraftMetadataPlaceholders
   powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\verify\test-codex-praetor.ps1
   powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\verify\test-public-entry-consistency.ps1 -SkipRemoteRelease
   npm test --prefix .\mcp
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
   powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\verify\doctor-codex-praetor.ps1 -RequireHead -PublicRelease
   powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\verify\test-codex-praetor.ps1
   powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\verify\test-public-entry-consistency.ps1 -SkipRemoteRelease
   npm test --prefix .\mcp
   git diff --check
   powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\release\build-codex-praetor-release.ps1 -Apply
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
   powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\release\activate-published-codex-praetor-release.ps1 -Version 0.9.4-alpha -Json
   ```

   它不手改 cache 或 readiness；会停在 `needs_host_restart` 或 `needs_canary`。前者只需要一次受支持的 Desktop 刷新，之后必须先用 `runtime_info` 验明运行身份，再运行 canary。

9. 已公开 Release 只能下载复验，不能替换资产或修改说明。源代码、合同或 artifact 有缺陷时，必须使用递增版本的恢复 PR。

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
