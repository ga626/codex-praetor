# 依赖与 Provider 更新治理

Codex Praetor 不允许 GitHub Dependabot 自动创建版本升级 PR，也不允许任何 bot 自动合并依赖更新。`.github/dependabot.yml` 故意不存在。

GitHub 管理员应保留 **Dependabot Alerts**，但关闭 **Dependabot Security Updates** 的自动 PR。安全告警是人工维护信号，不是自动变更授权。

`@qoder-ai/qoder-agent-sdk`、provider runner、外部 CLI 协议和固定模型目录都属于 **provider-critical**。它们只能通过明确命名的升级候选 PR 更新，并在同一候选 artifact 上完成受影响路线的验证。

外部 QoderWork 和 CodeBuddy/WorkBuddy 的升级不由本项目安装或回滚。派工前会比较 CLI 路径、hash、连接模式、runner、模型、权限和任务类型；任一受影响 tuple 改变时，仅暂停该路线并要求维护者批准一次最小验证。未变 tuple 复用已有证据，不重复消耗 provider 积分。

模型价格、折扣和 `Auto` 不构成版本升级依据。模型必须固定、显式选择；价格仅能作为带日期的人工参考。
