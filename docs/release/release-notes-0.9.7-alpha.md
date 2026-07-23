# Codex Praetor 0.9.7-alpha

## 本次修复

- 修复 capability canary 的伪阳性：外层命令回显不再能冒充 worker 成功；readiness 只接受真实 worker stdout 与 completion 的一致回执。
- readiness 升级为 v3，带最小回执身份与哈希。旧格式可保留为历史记录，但不能授权新的真实派工。
- 修复 Windows watcher 的退出码采集：改为同一原生进程异步收集 stdout/stderr 与退出码，非零或无法观察的退出码都会明确拒绝。
- 任务账本、能力画像、路由恢复和 provider 运营视图统一识别 `worker_process_failed` 与 `worker_exit_code_unavailable`，不再把它们放进“等待验收”。
- MiMo 441 风控保持不可自动重试；当前没有新的独立 canary 前，MiMo 不会作为默认可派候选。

## 用户可感知到的变化

系统宁可明确显示“当前不能派”，也不会把 provider 风控、无效回执或未知退出码说成已经可用。CodeBuddy 和 Qoder 仍需按当前 generation 的真实 canary 派工；MiMo 只有通过新的真实验证后才会重新进入受控验证范围。

## 发布与本机验收

这是新的不可变版本，不覆盖已有 tag 或 Release。合并后，`Release On Main` 将从 merge SHA 自动发布 `v0.9.7-alpha`，用同一公开包完成远端下载验真、stable marketplace 自动更新和本机激活。用户只需在系统报告 `needs_host_restart` 时执行一次受支持的 Codex host 刷新；刷新后先核对 `runtime_info`，再做 provider canary 与真实 worker 验收。
