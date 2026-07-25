# Codex Praetor 0.15.0-alpha

## 本次交付

- 增加真实任务证据的受控起步路径：只有已冻结、来源明确的真实历史问题或真实用户请求，且任务账本完整记录范围、独立检查、连接方式和验收器身份时，才能在尚无同任务族历史证据时启动第一批受监督 CLI 验证。
- 普通派工仍要求同 provider tuple、同任务族的 3 条新鲜 `accepted` 证据；夹具、canary、marker 和合同回归不会获得这条起步资格，也不会被写成能力证明。
- 起步任务仍必须通过当前 generation 的 provider readiness，且会在 job receipt 中明确标记为 evidence bootstrap；它不是公开路由资格，也不改变连接层或 provider 承诺。

## 用户可见边界

- 本版只修复真实矩阵无法开始的系统性门禁矛盾，不宣称 Qoder 或 CodeBuddy 已能完成任何真实任务族。
- Codex 继续负责拆解、授权、独立验收、整合和最终答复。外部 worker 只接收边界清楚的隔离工作包。
- 不读取、输出、迁移认证资料或 provider 数据库，也不修改 provider 设置。
