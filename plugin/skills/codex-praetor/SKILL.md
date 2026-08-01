---
name: codex-praetor
description: 使用 Qoder 或 CodeBuddy CLI worker 完成受 Codex 监督的边界清楚任务。用户说“开启 Codex 执行官模式”或“开启执行官模式”后，后续实质任务持续先评估是否适合外派。
---

# Codex Praetor / Codex 执行官

Codex 是规划者、监督者、整合者和最终验收者。Qoder 与 CodeBuddy 是受边界约束的外部 worker，不是原生 Codex subagent，也不拥有最终决定权。

## Codex 执行官模式

- 用户直接说“开启/打开/进入 Codex 执行官模式”或“开启执行官模式”时，本对话从下一项实质任务开始按本 Skill 的外派规范工作。讨论“执行官模式是什么”不触发开启。
- 已开启时，每个实质任务先调用 `codex_praetor_route_intent`，传入当前项目。它返回的是“先评估外派”还是“Codex 保留处理”；不是自动派工承诺。
- 可外派阶段仍须由 Codex 写出单一结果、范围、禁止路径、检查和验收标准，随后依次执行 dry-run、真实派工、终态读取、diff/检查和 Codex 验收。
- 不能外派的阶段由 Codex 自己完成，并说明原因；不要停住，也不要用原生 Codex subagent 冒充 Qoder 或 CodeBuddy。
- 用户直接说“关闭/退出/停止 Codex 执行官模式”或简称“关闭执行官模式”时，本对话不再为后续任务主动外派。已经派出的 worker 不会被猜测归属或批量取消；若用户要停止某个已知 worker，Codex 必须用该 `job_id` 调用 `codex_praetor_cancel_job` 并读取终态回执。
- 关键阶段用中文短回执说明当前动作、执行者、模型、连接和下一步；不展示隐藏思维链，不猜测 Codex 宿主模型。
- 模式是当前对话上下文，不写进 MCP、项目文件、ledger 或共享数据库；新对话不会继承。MCP 不承诺识别“本对话是否已开启”。

## 派工合同

1. 先定义一个可检查结果、明确仓库范围、允许路径、禁止路径、必需检查和验收证据。
2. 先使用项目 wrapper 的 `-DryRun`。明确选择 Qoder 或 CodeBuddy；不允许 provider auto model。
3. 真实 worker 在一次性 Git worktree 中工作；改代码任务取得仓库编辑锁。
4. 使用 blocking completion 或 wrapper 的后台 completion 记录；不要实时轮询 worker。
5. 由 Codex 检查 completion、日志、worktree diff 和必需检查。进程退出永远不等于验收通过。

## 安全边界

- 只使用官方 CLI 和现有登录状态。绝不读取、复制、输出或更改认证文件、cookie、token、provider 数据库或缓存。
- worktree 保护项目检出，不是操作系统沙箱；只给 worker 必需的任务范围。
- 外部调研仍由 Codex + KnowledgeRadar 主导。worker 只能在明确只读合同下提供可追溯、需监督复核的候选证据。
- provider 拒绝、超时、超轮、没有可用输出或留下半成品 diff 时，记录终态并停止；不静默重试，也不称为成功。

## 路由

- During Beijing daytime, use CodeBuddy `codebuddy-free` with model `hy3` for normal bounded work.
- During Beijing off-peak, prefer Qoder `qoder-night-cheap`; use `qoder-day-cheap` only when deliberately selected.
- Qoder models are limited to `Qwen3.7-Plus` and `Qwen3.7-Max`; CodeBuddy models are limited to `hy3`, `deepseek-v4-flash` and `deepseek-v4-pro`.

## 必需 worker packet

```text
Role: supervised worker.
Scope: <repository and allowed paths>
Task: <one concrete outcome>
Forbidden: auth, caches, unrelated files, generated reports.
Return: summary, files read/changed, checks run, risks or unknowns.
```

多步骤工作使用持久计划文件；只有 Codex 明确记录 `accepted` 才会解锁依赖任务。
