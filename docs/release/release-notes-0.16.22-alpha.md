# Codex Praetor 0.16.22-alpha

发布日期：2026-08-03

## 本次修复

- 修复 Qoder Agent SDK runner 在 Windows 状态文件替换遇到一次性 `EPERM`、`EBUSY` 或 `EACCES` 时把整个真实任务误判为 worker 失败的问题。
- 状态文件临时路径改为每次写入唯一，并对可恢复的文件锁做有限退避重试；最终失败仍保留明确失败证据，不会伪装成功。
- 新增状态替换成功、临时锁重试、最终失败清理临时文件的回归测试。

## 用户影响

Qoder 真实派工遇到 Windows 文件占用时会自动短暂重试，减少任务尚未开始就因 session 状态文件写入竞态失败的情况。Qoder 与 CodeBuddy 的 provider readiness 仍按当前 CLI、模型、连接方式和运行时代际精确绑定。

## 验收与发布

候选包必须在隔离环境完成 MCP 全量合同测试、最终 artifact 运行验收，以及 Qoder 和 CodeBuddy 各自的当前 generation canary 与真实任务验收；任一 provider 没有同一 artifact 的 accepted 证据都不得称为双 provider 发布完成。

本版本保留 **structured progress** 与 **formal cancellation** 合同：状态写入重试不能改变取消、超时、失败和 Codex accepted 的判定边界。
