# Codex Praetor 0.3.0-alpha

## 这版解决什么

这一版把发布代际、provider readiness、任务合同、durable job、completion 和活动 receipt 绑定到同一 runtime contract。旧版本的 canary、旧 task contract 或旧 receipt 不会继续驱动新版本真实派工。

## 主要变化

- runtime contract 升级到 `task-contract/v4`，发布 generation 和 receipt 升级到 v2。
- readiness 记录 generation、runtime contract hash、CLI tuple、provider 来源和有效期。
- job/completion 记录 generation、合同 schema、provider tuple 和终态；退出码为 0 但工具合同/权限失败时仍按语义失败处理。
- 取消只允许作用于未终态任务，超时会终止进程树并保留诊断；旧 generation 回收仍由统一维护机制重试。
- release tag 不可复用；产品交付仍要求下载 Release zip、校验 `.sha256`、隔离 fresh-context 和 provider readiness。

## 边界

这版不强制替换当前 Codex 对话、不强杀 Codex、不自动登录 provider，也不把 provider worker 的候选研究结果当作最终研究结论。
