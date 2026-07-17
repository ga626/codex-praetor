# Codex Praetor 0.4.0-alpha

## 这版解决什么

这一版把“worker 退出”与“任务被 Codex 接受”分开。它提供本地任务治理账本，让每次外部 worker 执行都有不可变 attempt、证据状态和主管 verdict，用户不必再从日志推断一个任务是否真的完成。

## 主要变化

- runtime contract 与 MCP/插件版本统一升级到 `0.4.0-alpha`；task ledger 兼容读取旧 plan，但不把旧 `completed` 误当 accepted outcome。
- watcher 只记录 attempt 的 process/evidence 状态；依赖任务只能在 Codex 写入 `accepted` verdict 后解锁。
- 取消改为持久化 `cancel_requested`，watcher 成为 terminal projection 的唯一写者，避免取消与 completion 相互覆盖。
- provider capability canary 写入可直接用于 release activation 的 generation readiness，同时 dispatch 继续按 provider tuple 检查；两者都支持显式 readiness 路径，PR 验证可使用隔离 profile，不会改写稳定安装的准入状态。
- dispatch 可显式选择 `dev` runtime channel；隔离 PR 验证使用独立 channel/tag，不会复用或覆盖 stable release generation。
- 默认顺序执行共享 write set；release tag 仍不可复用，产品交付仍要求下载 Release zip、校验 `.sha256`、隔离 fresh-context 和 provider readiness。

## 边界

这版不引入 A2A HTTP server、Temporal、第二 LLM supervisor 或 worker 群聊；不强制替换当前 Codex 对话、不强杀 Codex、不自动登录 provider，也不把 provider worker 的候选研究结果当作最终研究结论。
