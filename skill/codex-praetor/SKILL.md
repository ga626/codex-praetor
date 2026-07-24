---
name: codex-praetor
description: 当用户要求拆分、派发或让其他 agent 完成边界清楚的任务时，使用本机 Qoder 或 CodeBuddy CLI；Codex 负责规划、整合与验收。
---

# Codex Praetor

## 适用与边界

- “拆分任务”“派给其他 agent”“交给 Qoder/CodeBuddy”默认指外部 worker，不创建原生 Codex subagent；只有用户明确指定或接受时才走原生路线。
- 只派发边界清楚、可独立验收的只读、研究辅助或小型代码任务；无法检查、涉及认证/隐私或改变公开承诺的工作由 Codex 自己处理。
- Codex 负责目标、拆分、研究结论、整合和最终验收；worker 的退出码、报告和 completion 只是候选结果。只用当前本机配置允许的 Qoder/CodeBuddy 路由和固定模型，不默认 `auto`、付费预览或旧会话。
- 编辑任务必须使用隔离 git worktree，候选运行时另用隔离 `UserProfileRoot`；可用正常网络、登录态和用户授权额度，但不得读取、输出、复制或迁移 token、cookie、认证文件、provider 数据库、缓存或 Desktop 运行时。worktree 不是 OS 沙箱。

## 派工与验收

1. 先定义任务包：单一结果、允许/禁止路径、预算、所需检查和回传证据；说明派发理由、provider、隔离范围及 Codex 保留的工作。
2. 从项目根目录 route/plan/dry-run；真实编辑用 disposable worktree，多步任务写 durable plan，后台任务等 completion 事件，不高频轮询。
3. Codex 顺序检查 `completion.json`、stdout/stderr、worktree diff/status、允许范围和独立测试，记录 `accepted`、`rejected`、`retry`、`human_required` 或 `skipped`；只有 `accepted` 可解锁依赖。
4. 用户说“停”时，走正式取消路径并读取 `completion.json` 终态。provider 拒绝、超时、无可用输出或遗留部分差异都先如实记录，不静默重试或当作成功。

共享根因修复后重跑受影响能力。发布影响 PR 必须从最终候选 artifact 重跑受影响场景和全量确定性矩阵，并生成绑定 `HEAD` 与 artifact SHA 的回执；CI 只作独立复核。

## 任务提示词

```text
你是受 Codex 监督的 worker。
目标：<一件可验收的事>
范围：<仓库和允许路径>；禁止：<明确禁止项>。
完成后说明：做了什么、读/改了哪些文件、跑了什么检查、遗留风险。
```

项目内的产品边界、发布流程和验收命令，以该项目的 `AGENTS.md`、能力清单和当前计划为准；不要把本 Skill 当作业务项目的额外事实源。
