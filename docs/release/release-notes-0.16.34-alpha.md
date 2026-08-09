# Codex Praetor 0.16.34-alpha

## 修复

- 派工计划不再只把展示标题交给 worker。所有 Qoder 与 CodeBuddy 路线现在共用可哈希的完整任务包，包含目标、验收、路径边界、检查、冻结基线与预算；“候选验收”这类标签不能再替代实际工作说明。
- CodeBuddy ACP 的 `refusal` 现在会明确记为 `provider_rejected / provider_refusal_before_tool_use`，不再因进程退出码为 0 而伪装成“等待 Codex 验收”。
- 对已证明“拒绝前无 diff、无副作用”的同一计划任务，新增一次透明的 `codex_praetor_recover_plan_task` 受控转交：CodeBuddy `hy3` 与当前时段的 Qoder `Qwen3.7-Plus` 可互为一次备选。超时、网络状态未知、已有改动、检查失败和第二次失败不会自动重派。

本版本不自动更新模型、不选择 Auto/全球版/未验证候选模型，也不读取账号、积分或认证数据。

Qoder 中国版仍使用既定的 `stream-json` 连接层，CodeBuddy 仍使用 ACP；既有的受控进程取消（controlled process cancellation）、终态回执与隔离 worktree 边界保持不变。
