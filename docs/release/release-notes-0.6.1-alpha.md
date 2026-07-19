# Codex Praetor 0.6.1-alpha

这不是对 `0.6.0-alpha` 的覆盖。`0.6.0-alpha` 在发布工作流启动前失败，未创建 tag、Release 或用户下载包；本版以新的不可变版本完成恢复，并把事故恢复规则做成门禁。

## 主要变化

- PR 候选验证与 `main` 发布共用同一份 `release-pipeline.yml`：同一套 action 固定版本、Node 安装、依赖、测试、构建与确定性检查会先在 PR 中实际运行。
- 发布影响 PR 必须把 `previous_version` 精确指向目标分支版本，并把版本递增；不能用未改版本的 intent 混过检查，也不能复用已有 tag。
- 版本面更新器保留原文件的 UTF-8 BOM；Windows PowerShell 安装入口会在隔离回归中重新解析，避免中文编码在发布前被改坏。
- 远端 tag 在 PR 阶段就检查。发布后如果只剩远端验证故障，只能重跑原 workflow run（它保留原始 commit SHA），不能从新分支或最新 `main` 手工补发。
- 删除了会从最新分支头部手工触发发布的 `workflow_dispatch` 入口。发布事故不会被下一次开发或手动分支头覆盖。
- 继续保留“公开 Release 成功”与“本机已交付”的边界：本机仍需 stage、fresh-context、provider readiness、activate 与普通用户路径证明。

## 发布边界

GitHub Release 是不可变交付物。发布失败的处置分两种：

1. 若 tag 或 draft/immutable Release 已存在：在 GitHub Actions 对原失败 run 使用 **Re-run jobs**；不得创建新 tag，不得改资产。
2. 若发布在创建 tag 前就因 workflow 定义错误失败：用一份显式递增版本的恢复 PR 修复定义。本版就是唯一这一类恢复；合并后仍由 `Release On Main` 自动发布。

## 验证

- `scripts/verify/test-release-workflow-readiness.ps1 -CheckRemoteActionPins`
- `scripts/verify/test-release-intent.ps1 -BaseRef origin/main -RequireReleaseImpact -CheckRemote`
- `scripts/verify/test-supply-chain-controls.ps1`
- `scripts/verify/test-codex-praetor.ps1`
- `npm test --prefix .\mcp`
- `scripts/verify/test-release-package-determinism.ps1`
- `scripts/verify/test-release-closeout.ps1`
