# Codex Praetor 0.8.4-alpha

本版不是增加新的“多 agent 功能”，而是把真实派工时最容易误导人的几种结果收紧为明确状态：worker 被 provider 拒绝、超出轮数、只留下半成品，或者本机插件其实已装好却被脚本误报失败。

## 主要改动

- MiMo 返回 `risk_control`、API 拒绝或无法解析的 JSON 事件时，completion 会记录明确失败类型、provider 错误码和下一步；不会再把错误输出写成有效报告。
- CodeBuddy 等 worker 出现 `Max turns exceeded` 时，会记录 `max_turns_exceeded`。若 worktree 已留下 diff，会明确标为“半成品”，仍不可直接验收或合并。
- 带结构化失败的进程退出会进入 `rejected`，而不是“等待 Codex 验收”；只有无语义失败的退出才会等待人工检查 diff、测试和业务结果。
- 新建隔离 worktree 处理本项目改码任务时，会在 worker 启动前以 `npm ci --ignore-scripts` 安装 MCP 依赖，避免把“新 worktree 没有 node_modules”误判成 worker 失败。
- 发布后自动本机激活改为识别官方 `codex plugin list` 的表格输出；插件已安装时不再因为状态列存在而误报失败。
- health 同时给出“可否派工”和“历史诊断状态”。旧回执、库存或维护提示仍会显示，但不再遮蔽已验证的运行代际和 provider readiness。

## 用户影响

遇到 provider 风控、轮数耗尽或半成品时，界面会直接告诉你这是失败或未完成，不会再以“已退出”制造成功假象。历史诊断问题需要维护时也仍会可见，但不会阻断已通过当前代际验收的正常派工。

## 发布与验收

合并后 `Release On Main` 必须从精确 merge commit 自动构建并发布新的不可变 zip。完成远端下载验真后，自动本机激活会安装同一 zip；随后按 host 刷新、`runtime_info`、provider canary、真实 worker 的顺序验收。任何发布链路失败均为 release incident，优先重跑原 SHA，不对同一版本补包。
