# Codex Praetor 0.16.2-alpha

## 本版交付

- `codex_praetor_plan` 现在要求每个待派发任务在创建时提供任务族、执行类型、允许/禁止路径、检查项、预算和验收标准，避免生成只有标题、随后无法安全派工的空合同计划。
- `codex_praetor_dispatch` 公开传递同一组范围、检查、预算和故障注入字段；内部脚本已有的安全合同不再被 MCP 工具面遗漏。
- 计划任务仍由 `codex_praetor_dispatch_plan_task` 派发；它会继续拒绝缺失合同、范围冲突、错误模式和无冻结基线的真实改码任务。

## 未扩大承诺

本版没有新增 provider、任务族、连接层或自动路由资格。canary、夹具和 marker 仍不能替代真实任务的 Codex `accepted` 记录。

## 发布后验收

Release On Main 必须从合并 SHA 构建同一不可变 zip、上传并远端下载复验。stable 安装和 host 刷新后，Codex 会用一条完整静态合同的真实 Qoder 只读任务验证：计划创建、dry-run、真实派工、完成证据、独立复跑和 Codex 验收能连续闭环。
