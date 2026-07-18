# Codex Praetor 0.5.0-alpha

## 这次解决什么

这一版把任务执行、证据、Codex 验收、发布和运行态健康放进同一个可追溯控制面。worker 进程退出、历史 receipt 或 GitHub Release 单独存在时，都不会再被当作任务完成或产品已交付。

## 主要变化

- task ledger 增加 completion definition、write set、budget、stop-loss、selection、outcome 和 progress。
- health 动态检查 readiness generation、CLI hash、tuple、过期时间、维护任务 action/arguments/triggers/enabled 和 runtime inventory。
- maintenance adapter 统一 `Register-ScheduledTask`、`schtasks.exe` fallback、查询与验证定义。
- 默认只读 inventory 区分 active、retired、clean/dirty worktree、audit-retained 和 test scratch，不主动删除。
- CI 使用最小权限和固定 SHA 的 GitHub Actions，并增加 Dependabot 与本地供应链验收。

## 发布边界

不覆盖任何既有 tag 或 Release。合并后应从最新 `main` 构建并发布新的 `v0.5.0-alpha` zip 与 `.sha256`，再按 release gate 完成 stage、fresh-context proof、provider readiness、activation、health 和普通用户安装复验。
