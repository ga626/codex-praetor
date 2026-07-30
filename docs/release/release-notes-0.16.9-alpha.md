# Codex Praetor 0.16.9-alpha

## 发布内容

- 修复 Windows PowerShell 以 UTF-8 BOM 写入的正式能力证据在运行时能力画像中被忽略的问题。
- 已被 Codex 验收的真实 worker 任务现在会被正确投影为 durable receipt，而不是被误判为 `legacy_plan` 或 `unknown`。
- 新增带 BOM 正式能力证据的回归测试，确保同一 provider tuple 与任务族的真实验收记录可以继续按既有规则累计。
- 既有的 structured progress 与 formal cancellation 合同保持不变；本次修复确保其真实终态证据能参与后续资格判断。

## 用户影响

这是一项发布事故修复：它不会放宽派工授权，也不会把一次任务直接提升为 qualified。修复后，已验收的真实任务会被准确显示为 observed；仍需同一精确 tuple 与任务族的三条独立 accepted 记录，才允许普通派工。

## 验证

- MCP 全量确定性合同测试，包括带 BOM 的 durable capability evidence 回归。
- 干净隔离候选构建、最终安装包能力画像验证和发布前置检查。

## 未包含内容

- 不新增 provider、认证资料访问、provider 数据库访问、自动合并或生产侧不可逆动作。
