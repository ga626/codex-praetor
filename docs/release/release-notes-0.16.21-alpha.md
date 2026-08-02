# Codex Praetor 0.16.21-alpha

## 发布后首次使用真正可用

- provider 已按官方方式安装和登录后，普通用户可以直接开始一个真实计划任务。
- 如果当前用户还没有匹配的 provider readiness，系统会在隔离 worktree 中自动完成一次受控首用 bootstrap；不要求用户理解或手动运行内部 canary。
- 只有真实 worker 成功完成、completion 证据完整时，才会写入 readiness；失败、超时、取消或部分改动不会成为能力证据。

## 真实派工状态更清楚

- dry-run、job 创建、worker 启动、completion 和 Codex accepted 现在有独立事实字段。
- Codex 宿主遇到 `stream disconnected before completion` 时，可以按同一 `job_id` 读取已有 timeline；不会因为宿主断线盲目重复执行任务。
- readiness 记录 provider、CLI、模型、权限、任务类型、连接方式和 runner identity，普通控制面更新不会无条件清空可复用证据。

## 验收合同

- **structured progress**：任务时间线把 job 创建、worker 启动、恢复、completion 和 Codex accepted 分开记录。
- **formal cancellation**：取消、超时、失败和宿主断线不会写入成功 readiness，也不会被当作运行中或已验收。

## 边界不变

- 不读取或预写用户 token、cookie、账号数据库、余额或 provider 私有状态。
- 不替用户登录，不自动合并失败 worker 的改动，不执行不可逆生产动作。
- 发布 artifact provenance、用户安装 identity、provider readiness 和 Codex 最终验收仍是四条独立证据链。
