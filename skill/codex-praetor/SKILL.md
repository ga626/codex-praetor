---
name: codex-praetor
description: 当用户说“开启执政官模式”或要求拆分、派发边界清楚的任务时，使用本机 Qoder 或 CodeBuddy CLI；Codex 负责规划、整合与验收。
---

# Codex Praetor

## 执政官模式（正式触发词）

- 用户说“开启执政官模式”时，从下一项实质任务开始持续使用本 Skill；“打开执政官模式”“进入执政官模式”是同义触发。旧称“执行官模式”只作为历史兼容别名，不作为新的用户口径。
- 开启后，每项实质任务仍必须先调用 route，但 route 只是分类，不是流程终点。若结果指向外部 worker，且任务存在可独立验收的子结果，Codex 必须继续完成 `plan → dry-run → dispatch`；不能因为 route 已完成、尚未有 evidence 或任务整体较大就直接回退而不检查可拆分部分。
- 只有存在可核实的阻断（认证/隐私、生产或不可逆外部动作、缺少 provider/连接/权限、无法形成明确验收合同、或任务必须由 Codex 作最终裁决）时，才可由 Codex 接管。接管时必须向用户说明具体阻断和保留的可外派子任务。
- 大任务默认拆成“Codex 保留的规划/敏感操作/整合验收”与“worker 执行的只读、确定性或局部修改”两部分；不能以整体复杂为由把所有工作留给 Codex。
- `route_intent` 完成不等于已派工；真实派工只有在返回 `job_id`、`execution_worktree` 和 started 状态后才能确认。合同预检通过也不等于 worker 已启动。

## 适用与边界

- “拆分任务”“派给其他 agent”“交给 Qoder/CodeBuddy”默认指外部 worker，不创建原生 Codex subagent；只有用户明确指定或接受时才走原生路线。
- 只派发边界清楚、可独立验收的只读、研究辅助或小型代码任务；无法检查、涉及认证/隐私或改变公开承诺的工作由 Codex 自己处理。Codex 保留目标、拆分、研究结论、整合和最终验收；worker 的退出码、报告和 completion 只是候选结果。
- 只用当前本机配置允许、且已有同任务族证据的 Qoder/CodeBuddy 路由与固定模型，不默认 `auto`、付费预览或旧会话。编辑任务必须使用隔离 git worktree，候选运行时另用隔离 `UserProfileRoot`；可用网络、登录态和用户授权额度，但不得读取、输出、复制或迁移 token、cookie、认证文件、provider 数据库、缓存或 Desktop 运行时。worktree 不是 OS 沙箱。

## 派工与验收

1. 定义任务包：一件可验收的结果、允许/禁止路径、预算、所需检查和回传证据，并说明派发理由、provider、隔离范围及 Codex 保留的工作。测试任务必须声明精确检查；由 supervisor 准备依赖，worker 不得 `install`/`update` 依赖。真实代码修改必须通过 `codex_praetor_dispatch_plan_task` 的计划合同，冻结 `base_commit` 和 `immutable_paths`。
2. 从项目根目录依次执行 route、plan、dry-run；dry-run 通过后必须继续真实 dispatch，除非记录了可核实阻断。真实编辑用 disposable worktree，多步任务写 durable plan，后台任务等 completion 事件，不高频轮询。
3. Codex 顺序检查 `completion.json`、stdout/stderr、worktree diff/status、允许范围、成功 marker 和独立复跑，才记录 `accepted`；只有 `accepted` 可解锁依赖。拒绝、超时、无输出或遗留部分差异均为失败证据，不静默重试、合并或当作成功。
4. 用户说“停”时，走正式取消并读取 `completion.json` 终态。共享根因修复后重跑受影响能力；发布影响 PR 必须从最终候选 artifact 重跑受影响场景和全量确定性矩阵，生成绑定 `HEAD` 与 artifact SHA 的回执，CI 只作独立复核。

## 任务提示词

```text
你是受 Codex 监督的 worker。
目标：<一件可验收的事>
范围：<仓库和允许路径>；禁止：<明确禁止项>。
完成后说明：做了什么、读/改了哪些文件、跑了什么检查、遗留风险。
```

项目内的产品边界、发布流程和验收命令，以该项目的 `AGENTS.md`、能力清单和当前计划为准；不要把本 Skill 当作业务项目的额外事实源。
