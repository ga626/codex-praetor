# Codex Praetor 0.16.18-alpha

## 真实任务不再被热身门禁挡住

- 合格的真实用户任务现在可以直接派给 Qoder 或 CodeBuddy；不再要求每个 worker tuple 先完成三条付费热身任务。
- 三条已验收记录改为“充分观察”标签，只影响推荐优先级，不再决定能否开始派工。
- 产品版本、generation 和 runtime contract 的常规变化不再清空 worker 历史；模型、权限、连接方式或 runner 变化仍会形成新的 worker identity。
- 计划派工会在真实 worker 启动后自动记录实际连接方式的证据上下文；`validation_only` 任务不能通过常规派工消耗 provider credits。
- dry-run 现在明确显示“预演通过，未启动”，并保证不创建 job，不会再误报已派发。

## 安全边界保持不变

认证资料、provider 数据库、生产环境与不可逆外部动作仍不外派。编辑仍只在隔离 worktree；worker 完成不代表 accepted，Codex 仍须检查范围、独立检查和最终结果后才可整合。
