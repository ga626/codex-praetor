# Codex 执政官 0.1.0-alpha 发布说明

这是 Codex Praetor（Codex 执政官）的第一个 alpha 预发布版。它面向 Windows 上的 Codex 用户，用来把边界清楚的小任务交给本机外部 CLI worker，同时让 Codex 继续负责规划、监督、整合和最终验收。

## 下载

- Release 页面：`v0.1.0-alpha`
- Windows 用户安装包：`codex-praetor-setup-0.1.0-alpha.zip`，解压后双击根目录的 `setup.cmd`
- 安装指南：[docs/user/installation.zh.md](https://github.com/ga626/codex-praetor/blob/main/docs/user/installation.zh.md)
- 排错指南：[docs/user/troubleshooting.zh.md](https://github.com/ga626/codex-praetor/blob/main/docs/user/troubleshooting.zh.md)
- 隐私边界：[docs/user/privacy.zh.md](https://github.com/ga626/codex-praetor/blob/main/docs/user/privacy.zh.md)

## 这个版本能做什么

- 识别“拆分任务”“分配给其他 agent”“交给外部 agent 做一部分”这类自然语言。
- 优先走 Codex Praetor 外部 worker 路线，而不是默认创建 Codex 原生 subagent。
- 支持计划、dry-run、任务列表、状态查询、lane 查询和冲突检测。
- 通过 MCP 工具把这些能力暴露给 Codex。
- 支持 Qoder、CodeBuddy、MiMo 这三类可选 provider 路线。

## 重要边界

- 这是 alpha 预发布版，适合试用和验收，不建议当成稳定生产依赖。
- Qoder、CodeBuddy、MiMo 不随包附带，用户需要按各自官方方式安装和登录。
- Codex Praetor 不替用户登录 provider，不读取 token、cookie、账号数据库、余额页或个人截图。
- 没有安装 provider 时，仍然可以使用计划、dry-run、状态查询、lane 查询和冲突检测；真实派工需要至少一个可用 provider。
- 安装或更新插件后，Codex 可能需要刷新工具上下文。日常调用失败时，先按排错指南使用轻量 reload/probe，不要把“每次都新开任务”当成正常使用方式。

## 已验证内容

- 公开发布检查通过。
- `scripts/verify/test-codex-praetor.ps1` 通过。
- MCP 自测通过。
- 插件内置 MCP runtime smoke test 通过。
- release 包构建和私有信息扫描通过。
- 新 Codex 任务里的原生 MCP route/dry-run 验收通过。
- MiMo、CodeBuddy、Qoder 只读 canary 已跑通过。
- 本机安装目录使用真实复制目录，不使用软链接或自动同步。

## 首次使用

下载并解压 release zip 后，直接双击：

```powershell
.\setup.cmd
```

安装向导会先显示检查结果，并默认允许跳过 provider 配置。安装完成后，重启 Codex，或打开一个新任务，让 Codex 发现插件。第一次建议只做 dry-run：

```text
拆分一下任务，分配给其他 agent 做 dry-run，不要真实修改文件。
```

## 后续计划

- 继续简化首次安装、卸载和回滚体验。
- 改善 provider CLI 发现、登录提示和只读 canary。
- 让 MCP 工具通道失败后的恢复路径更轻、更清楚。
- 持续补齐中文用户文档和 GitHub 仓库体验。

<details>
<summary>English summary</summary>

Codex Praetor 0.1.0-alpha is a Windows-first Codex plugin and MCP layer for dispatching bounded tasks to external CLI worker agents while Codex remains the planner, supervisor, integrator, and final verifier.

Optional providers are Qoder, CodeBuddy, and MiMo. They are not bundled. Users install and sign in to providers through each provider's official flow.

This alpha includes route intent, dry-run dispatch, job listing, status, planning, lane lookup, and conflict detection. It is intended for trial and acceptance, not as a stable production dependency.

</details>
