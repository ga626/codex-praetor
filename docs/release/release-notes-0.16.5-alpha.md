# Codex Praetor 0.16.5-alpha

## 修复

- CodeBuddy 的无头派工改用当前 CLI 文档声明的 `dontAsk` 与 `--allowedTools` 合同，不再用广泛放行的 `-y + --tools` 组合。
- CodeBuddy 的任务回执改为记录实际 CLI 脚本文件及其 SHA-256，而不是 Node.js 启动器。

## 证据边界

- 修复依据为三条同配置 CodeBuddy 真实只读任务重复出现的 `Tool Bash not found in agent cli.`，以及当前本机 CodeBuddy CLI 的 `--help` 和内置文档。
- 这版不扩大 provider、任务族、自动路由、认证访问或外部网络权限承诺；修复后仍须重跑受影响的真实任务矩阵。
