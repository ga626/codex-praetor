# Codex Praetor 0.9.2-alpha

## 本次变化

- 增加 `codex_praetor_explainable_route`：派工前用完整 provider tuple、当前硬门和同任务族能力证据解释推荐、排除与 fallback。
- 画像证据在 30 天后自动标记为 `stale`；旧网络故障在冷却结束后要求重新 canary，不能被当作可无限重试的成功历史。
- 固化风险控制、认证、网络/限流、权限、超轮数、测试失败和范围越界的恢复出口；建议不会自动派工、合并或发布。

## 用户可感知到的变化

派工建议不再只是“选了谁”。它会告诉你：这项工作属于什么任务族、每个候选通过了哪些硬门、最近有什么可信成绩、为什么推荐或排除、失败时会停住、冷却还是交回 Codex。

## 发布与本机验收

合并后，`Release On Main` 会从该 merge SHA 自动生成不可变 `v0.9.2-alpha`。公开包远端验真和 stable marketplace 自动安装属于本次收口；Codex Desktop host 刷新仍按四 PR 总目标统一在 PR 4 后执行一次。
