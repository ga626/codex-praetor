# Codex Praetor 0.16.11-alpha

## 发布内容

- 修复 Qoder 与 CodeBuddy 派工使用的 linked worktree 台账根路径，所有派工、验收和证据记录统一落到 Git common-root 的同一份项目内状态。
- 修复候选 canary 的隔离运行态传递：候选 `UserProfileRoot`、readiness、job、plan、lock 与 scratch 根不再串到其他运行代际。
- 修复 Windows 下 CodeBuddy ACP 对盘符大小写不同的允许路径误拒绝；仍拒绝真正越出声明范围的请求。
- 修复 Windows Git 的行尾提示被发布前 MCP 验收误当作失败的问题；实际失败仍按退出码和明确成功标记判定。
- 用真实 Qoder SDK 与 CodeBuddy ACP worker 分别完成三条独立、受限的隔离 worktree 改动并由 Codex 验收；两条连接保留可观察的 structured progress，formal cancellation 和新任务冷恢复也分别在干净 worktree 中验证。

## 用户影响

- 已正常登录并配置 Qoder 或 CodeBuddy 的用户，可以让 Codex 对已拆分、范围明确的任务进行真实派工；Codex 始终负责授权、检查、整合与最终答复。
- 取消任务不会以“进程结束”冒充成功：Qoder 需要 SDK abort 的终态，CodeBuddy 需要 ACP `session/cancel` 的 provider 确认；之后由 Codex 创建新任务恢复。
- 本版不新增 provider、模型或自动合并；不读取认证资料、provider 数据库、token 或 cookie，也不执行生产侧不可逆动作。

## 验证

- Qoder SDK 与 CodeBuddy ACP 均有三条独立的真实 `bounded_code_change` 已验收记录；每条均包含 completion、允许范围、不可变路径、独立 `git diff --check` 与 Codex 验收。
- 两个 provider 分别通过正式取消、provider 终态与干净 worktree 冷恢复验证。
- 从最终候选 artifact 重跑受影响场景及完整确定性发布矩阵，并生成绑定最终 `HEAD` 与 artifact SHA 的回执。

## 未包含内容

- 不把 canary、marker 或合成夹具计入真实改码能力证据。
- 不把 worker 的退出码、ACP session 或 SDK session 单独视为自动验收或自动合并。
