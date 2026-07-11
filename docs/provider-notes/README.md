# Provider 说明

Codex Praetor 支持以下可选外部 CLI provider：

- [Qoder](qoder.md)
- [CodeBuddy](codebuddy.md)
- [MiMo](mimo.md)

这些 provider 不随 Codex Praetor 附带。用户需要按各 provider 官方流程安装和登录，然后在不会提交的本地配置里填入 CLI 路径。

没有配置 provider 时，Codex Praetor 仍然可以做意图识别、计划、dry-run、状态查询、lane/冲突可见性和 MCP 工具发现。真实派工需要至少一个 provider CLI 已安装、已登录，并通过只读 canary。

返回安装入口：[README](../../README.md)。
