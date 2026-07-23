# Codex Praetor 0.9.8-alpha

发布日期：2026-07-23

## 本次变更

- 产品 provider 集合收敛为 Qoder 与 CodeBuddy。
- MCP、派工、安装向导、配置、验收任务和发布包同步采用两家白名单。
- 新增针对 provider 集合、派生数据和发布包的完整性验收；未知 provider 不会被静默接入。
- 真实 worker 验收继续要求隔离 worktree、真实 completion、diff 或输出证据，以及 Codex 的最终验收。
- worker 的成功证据收敛为真实 stdout、completion 与退出码的一致回执；拒绝、超时、无法观察退出码与部分产物都会明确失败，不能伪装成“等待验收”。

## 用户影响

现有用户升级后只会看到 Qoder 与 CodeBuddy。此前发布版本及其不可变历史保持原样；新安装包不会携带已下线 provider 的 adapter、派工入口或说明。

## 验收与发布

本版本由 `Release On Main` 从合并 SHA 构建唯一 zip、上传 Release 并进行远端下载验真。本机激活只下载并安装同一个公开 zip；Desktop host 刷新后必须先验证 `runtime_info`，再运行 canary。
