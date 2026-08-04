# Codex Praetor 0.16.24-alpha

发布日期：2026-08-04

## 本次改进

- readiness 从“每次发布 generation 都重新作废”改为明确的 provider compatibility fingerprint：CLI 二进制、模型、权限、任务类型、连接方式、runner 与任务合同任一变化，旧证据立即失效；仅文档、包装和版本变化不会重复消耗 provider 积分。
- 已登录用户的第一条范围清楚、只读、隔离的真实计划任务会自动建立首用证据。普通使用不再要求先运行 canary；canary 只保留为安装、登录或连接问题的排障工具。
- 发布候选按变更实际影响决定真实 provider 验证：没有连接兼容性变化时只运行零积分 artifact/安装/合同检查；有变化时，每个受影响 provider 只需要一条经 Codex 验收的真实任务，不再强制叠加 canary。
- 发布证据按候选 ZIP SHA 绑定，任务合同的路径由实际 manifest 和存在性检查约束，避免把不存在的源码路径误写进 worker 合同。

## 用户影响

安装并刷新 Codex 后，只要 Qoder 或 CodeBuddy 已按其官方方式登录，你可以直接提出真实任务。Codex 会先拆成带允许路径、禁止路径、检查和验收标准的计划；首条合格低风险只读任务自动留下本机可用性记录。编辑、外网、认证、生产或不可逆操作不会借这个首用例外绕过原有合同和验收边界。

本版本不读取、不移动或打包 token、cookie、认证资料或 provider 数据库。任务失败仍不会自动合并；Codex 必须读取 completion、日志、worktree 和独立检查后才会采信。

## 进展与停止

- `structured progress`（结构化进展）继续把 worker 的启动、执行、停滞、完成和 Codex 验收分开记录；无输出或进程退出不会被误写成完成。
- 用户要求停止已知任务时，系统走 `formal cancellation`（正式取消）：记录取消请求并读取 provider 的终态回执。取消、超时、失败或没有 accepted 证据的任务都不会进入 readiness 或合并路径。

## 验收与发布

候选必须完成最终 ZIP 的确定性、安装身份、MCP runtime 与合同路径检查。只有 provider compatibility fingerprint 变化时，才在候选阶段对受影响连接完成最小真实任务；main 只提升同一不可变 artifact、发布 Release 并从远端下载复验 SHA，不在发布后重复烧 provider 积分。
