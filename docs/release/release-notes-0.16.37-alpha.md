# Codex Praetor 0.16.37-alpha

## 修复

- Qoder 中国版 `stream-json` 现在以事件驱动方式观察模型排队。上游持续发出的 `model_queue_status` 只证明请求进入排队，不再被误判为任务进展；达到明确的队列等待上限后，会记录 `provider_queue_timeout / model_queue_saturated`、队列类型、位置、等待时间和服务可用性，而不是消耗完整任务超时。
- CodeBuddy ACP 的 `refusal` 继续被拒绝为 provider 失败，同时在官方扩展字段存在时只记录安全白名单诊断码、状态或类别。不会把任务正文、Agent 消息、自由文本错误或账号资料写入作业回执。
- 新增两条连接层回归：纯排队 stream 必须在队列上限结束；ACP refusal 的公开诊断可见，但自由文本不能泄露到持久记录。

## 使用与边界

本版本没有自动改模型、读取余额、迁移认证或选择 Auto。Qoder 仍固定走中国版 `stream-json`，CodeBuddy 仍固定走 ACP；既有的 controlled process cancellation、终态回执与隔离 worktree 边界保持不变。真正派工仍须由 Codex 检查 completion、输出、范围和独立验证后才可接受。
