# Codex Praetor 0.16.33-alpha

## 修复

- 执政官模式现在把 `active` 作为每一项实质任务 route 的显式输入，并生成可写入 durable plan 的决策回执；MCP 不再假装能够自行读取或记住宿主对话状态。
- 新增受跟踪的模型路由目录。Qwen3.7-Plus 保持固定低成本档，Qwen3.7-Max 改为显式强档并记录 0.5x / 0.1x 快照；Qwen3.8、DeepSeek 保持候选，Auto 与历史 MiMo 配置不参与路由。
- 新增 `prepare_plan_task` 和执政官模式状态回执：没有 `job_id` 时明确显示“尚未真实派工”，不能再把 route、预检或文字说明当作已派工。
- 派工摘要显示固定 provider、连接、模型、选择理由和带日期的价格状态。价格过期或账号价格冲突时不会自动改选模型。
- 保持既有的 controlled process cancellation：取消仍由受控 watcher 投影为终态并保留 stdout/stderr 与 completion 证据；本版本未改变该取消链路。

本版本不读取认证、余额或账号配置，不自动更新模型，不改变 Qoder CN stream-json、Qoder Agent SDK 或 CodeBuddy ACP 的既定连接路线。
