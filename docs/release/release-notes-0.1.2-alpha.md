# Codex 执政官 0.1.2-alpha 发布说明

`0.1.2-alpha` 的目标是把 Codex Praetor 从“安装可用、dry-run 可见”推进到“持续编排闭环可用”。

## 这次新增什么

- 新增真实 worker 派发 MCP 工具。Codex 可以通过工具调用启动外部 worker，而不是只展示 dry-run 命令。
- 新增 worker 结果读取工具。Codex 可以读取 job 摘要、completion、日志尾部和失败分类，不需要把完整日志倒给用户。
- 新增计划推进工具。Codex 可以查询下一批可运行任务，并把计划中的 pending 任务派给外部 worker。
- 新增 Codex 验收记录。worker 完成后不会自动解锁后续任务，必须由 Codex 记录“采信、拒绝、重试、需要人工处理或跳过”。
- 新增常见失败分类：超轮数、provider CLI 缺失、未登录/授权、权限拒绝、watcher 失败、completion 缺失和普通 worker 失败。

## 用户会感觉到什么变化

以前 Codex Praetor 更像安全预览工具：能识别外部 worker 路线，能做 dry-run，能查状态。

现在它开始进入真实编排：Codex 可以把任务交出去、等 worker 回来、读取结果、做验收判断，再继续下一步。关键边界是：worker 进程退出不等于任务完成，Codex 验收通过才算完成。

## 仍然不做什么

- 不自动替用户登录 Qoder、CodeBuddy 或 MiMo。
- 不读取 token、cookie、账号数据库、余额页面或截图。
- 不让 worker 自动合并、自动发布或自动替用户确认付费/账号动作。
- 不默认创建 Codex 原生 subagent。

## 发布验收

发布前必须验证：

- 新鲜 Codex 工具上下文能看到 `codex_praetor_dispatch`、`codex_praetor_result`、`codex_praetor_next_ready`、`codex_praetor_dispatch_plan_task` 和 `codex_praetor_verify_task`。
- MCP protocol smoke 通过。
- 一个 plan task 在 worker 完成后进入等待 Codex 验收状态，只有验收 `accepted` 后才解锁依赖任务。
- 从 GitHub Release 下载的 zip 和 `.sha256` 对应同一个版本。

## 发布边界

本说明只是 `0.1.2-alpha` 的发布说明草稿。代码合并不等于产品已交付；只有 GitHub Release 资产构建、上传、下载复验全部通过后，用户才真正拿到这一版。
