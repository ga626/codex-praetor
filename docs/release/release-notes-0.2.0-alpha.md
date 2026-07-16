# Codex 执政官 0.2.0-alpha 发布说明

0.2.0-alpha 将真实派工从“脚本能启动”升级为“安装态、任务合同、provider capability 和验收状态都能被证明”的闭环。

## 用户能感受到的变化

- 联网搜索、外部调研、来源发现和事实核查由 Codex 通过 KnowledgeRadar 执行，不会再派给 Qoder、CodeBuddy 或 MiMo。
- 外部 agent 可以承担受控的代码修改任务，但所有任务都会在 Codex 创建的独立 worktree 中执行。worker 无法直接写主工作区；只有 Codex 验收后才能整合变更。
- 真实派工前会检查 Plugin、Skill、MCP 和 personal cache 是否属于同一运行时代际。版本混装时只允许健康检查和 dry-run，真实派工会明确拒绝。
- provider 需要通过当前 CLI、模型、权限合同对应的 capability canary。旧版本、路径变化、模型变化或过期 canary 都会让它退出自动候选池。
- Codex Praetor MCP 现在能显示运行时合同、健康结论、job 生命周期和取消结果，而不是只显示一条外部命令。

## 任务边界

外部 worker 可以进行本地文件读取、仓库搜索、受控修改和约定测试。它们不是外部研究感知层，不应替代 KnowledgeRadar。

MiMo 的默认 Build agent 具备写入能力，因此 audit tier 改名为 mimo-isolated-audit。它表示“在可丢弃 worktree 中隔离运行”，不再暗示技术性只读。

## 发布验收

发布后必须从 GitHub Release 下载 0.2.0-alpha 安装包并重新安装，然后在新 Codex 任务中确认：

1. codex_praetor_runtime_info 与 codex_praetor_health 显示同一运行时代际。
2. 当前 MCP 工具面包含 health、runtime info、job timeline 和 cancel job。
3. 每个声明支持的 provider tuple 都有未过期的真实 capability canary；不支持者必须显示 blocked 或 disabled。
4. 超时、取消、语义失败和 worktree 并发用例均留下正确 completion 状态。
