# Codex Praetor 0.9.3-alpha

## 本次变化

- 新增 `codex_praetor_provider_operations`：用简单状态说明 Qoder、CodeBuddy、MiMo 此时能否派工、依据和恢复动作。
- 增加版本化 provider onboarding checklist；未来新增 provider 必须完成 adapter、当前 canary、真实任务族和失败恢复证据，不能直接加入默认候选。
- Adapter 明确关联 checklist，同时保留官方 CLI、隔离 worktree 和不读取认证材料的边界。

## 用户可感知到的变化

不必读错误日志猜测员工是否可用。页面会告诉你它是“能派”“可小范围验证”“冷却中”“需要登录”“证据过期”还是“暂不可派”，并给出下一步。

## 发布与本机验收

合并后，`Release On Main` 会从该 merge SHA 自动发布不可变 `v0.9.3-alpha`，再验真远端包并自动更新 stable marketplace。之后需要一次受支持的 Codex Desktop host 刷新，才能验证新 runtime、canary 和真实 worker。
