# Codex Praetor 0.16.32-alpha

## 修复

- 执政官模式的真实派工现在收敛到 durable plan task：未绑定计划的通用 `codex_praetor_dispatch` 会返回明确的 `use_dispatch_plan_task`，不会再在通用 readiness gate 前静默停住。
- 新增 `codex_praetor_dispatch_readiness`。它只读解析本次任务实际使用的 provider、模型、分发和连接方式，并明确返回 `direct_ready`、`bootstrap_eligible` 或阻断类别；不会创建 job、worktree 或 worker。
- 首用 bootstrap 现在先用同一任务解析到的 exact tuple 写入 evidence context，再启动同一项真实用户任务；不再以 `auto` 的猜测连接方式写入、启动后回填。
- 计划账本会持久记录 `preflight_ready`、`bootstrap_eligible`、`bootstrap_started`、`worker_started`、`dispatch_blocked` 等控制面状态和唯一下一步，避免对话中断后重复创建热身任务。
- provider 总览不再把“存在任一当前回执”说成“本任务能派”；总览只展示库存，本任务必须经过精确预检。

本版本不更换 Qoder 中国版 `stream-json`、Qoder Agent SDK 或 CodeBuddy ACP 路线，不读取或迁移认证材料，也不引入自动 provider fallback。真实 worker 仍由 Codex 规划、验收和整合。

取消仍使用既有的受控进程取消（controlled process cancellation）链路；本次不改变该行为。
