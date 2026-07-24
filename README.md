# Codex Praetor

[简体中文](README.md) | [English](README.en.md)

Codex Praetor，中文名 **Codex 执政官**，是给 Codex 使用的外部 Agent 派工插件。

它解决的是一个很具体的问题：当你说“拆分一下任务”“分配给其他 agent 做一部分”时，Codex 不应该默认再开自己的 Codex subagent，而应该优先把边界清楚的小任务派给本机已有的外部 CLI 工具，比如 Qoder、CodeBuddy。Codex 仍然负责规划、风险判断、整合结果和最终验收。

当前产品化目标版本是 **0.12.0-alpha**。这一版把发布影响 PR、版本一致性、不可变 Release 和合并后自动远端复验串成一个闭环；本机 Desktop host 仍按 fresh-context 边界单独验收。

本版还新增只读能力画像：它按具体 provider、模型、权限和任务类型汇总真实尝试与 Codex 验收结论，帮助你看清证据；它不会在未经后续验证前擅自改变默认派工。

同时新增真实任务评测合同：每项任务都有隔离范围、确定性验收、预算和失败注入；准备任务不会被误当成 provider 已通过评测。

[下载 0.12.0-alpha](https://github.com/ga626/codex-praetor/releases/tag/v0.12.0-alpha) · [安装指南](docs/user/installation.zh.md) · [排错指南](docs/user/troubleshooting.zh.md) · [路线图](docs/roadmap.md)

## 适合你吗

适合：

- 你在 Windows 上使用 Codex Desktop 或 Codex CLI。
- 你希望 Codex 把小而清楚的任务交给外部 CLI worker。
- 你已经有，或准备按向导配置 Qoder、CodeBuddy 其中至少一个。
- 你想先验证 dry-run、计划、状态查询和冲突检测，再决定是否真实派工。

不适合：

- 你想要一个通用多 Agent 平台。
- 你希望它在未经确认时静默安装 provider、替你登录账号，或者读取 provider 的账号数据库。
- 你希望它默认创建 Codex 原生 subagent。Codex subagent 是另一条路线，会继续消耗 Codex 模型资源。

## 最快开始

普通 Windows 用户不需要打开 PowerShell。下载并解压 Release 包后，直接双击根目录里的 `setup.cmd`，按中文向导操作即可。

1. 打开 [Release 页面](https://github.com/ga626/codex-praetor/releases/tag/v0.12.0-alpha)，下载 Windows 安装 zip：`codex-praetor-setup-0.12.0-alpha.zip`。

   如果你更习惯 PowerShell，也可以运行：

   ```powershell
   Invoke-WebRequest -Uri "https://github.com/ga626/codex-praetor/releases/download/v0.12.0-alpha/codex-praetor-setup-0.12.0-alpha.zip" -OutFile ".\codex-praetor-setup-0.12.0-alpha.zip"
   Expand-Archive .\codex-praetor-setup-0.12.0-alpha.zip .\codex-praetor-setup-0.12.0-alpha
   cd .\codex-praetor-setup-0.12.0-alpha
   ```

2. 双击 `setup.cmd`。

向导会先检查 PowerShell、Node.js、Git 和可发现的 provider CLI，然后让你选择：

- 配置全部 provider。
- 先不配置 provider，只安装并验证 Codex Praetor 本体。
- 只配置 Qoder。
- 只配置 CodeBuddy。

选择 provider 后，向导会先检测本机命令；如果没装，会让你确认是否执行官方安装命令。安装完成后，它会刷新当前终端的 PATH、复检版本，并停在同一个向导里等待你完成官方登录、扫码、浏览器授权、站点选择、企业域、Token Plan 或 API key 等账号动作。你回到向导继续后，它会再次复检，写入当前用户的本机配置，并在最后给出一张中文状态总览。

3. 如果只想先查看安装计划，也可以在 PowerShell 中运行：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\setup.ps1
```

4. 确认路径没问题后安装：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\setup.ps1 -Apply
```

5. 重启 Codex，或者打开一个新任务，让 Codex 发现插件。

6. 先做 dry-run：

```text
拆分一下任务，分配给其他 agent 做 dry-run，不要真实修改文件。
```

你应该看到 Codex Praetor 选择外部 worker 路线，而不是创建 Codex 自己的 subagent。

## 没有 provider 也能先试

| 本机状态 | 可以做什么 | 不能做什么 |
| --- | --- | --- |
| 没有安装 Qoder、CodeBuddy | 本体安装、计划、dry-run、任务状态、lane 查询、冲突检测 | 真实派工 |
| 已安装 provider，但未登录 | dry-run、路径检查、配置检查、向导复检 | 真实派工通常会被 provider 拒绝 |
| 已安装并登录 provider | 先跑 readonly canary，再做真实派工 | 不建议跳过 canary 直接改代码 |

Codex Praetor 不会在未经你确认时安装 provider，不会替你登录，也不会读取 provider 的 token、cookie、账号数据库或使用截图。向导会尽量把能自动做的事做掉：执行官方安装命令、刷新 PATH、复检 CLI、记录非敏感路径；只有账号、扫码、授权、余额或 API key 这类必须由本人完成的步骤会停下来等你处理。

## 安全边界

- 不默认创建 Codex 原生 subagent。
- 不默认使用 provider `auto`。
- 不读取或发布 provider 账号数据库、token、cookie、使用截图。
- 不要求用户必须同时安装 Qoder、CodeBuddy。
- 没装某个 provider 时，只禁用那个 provider 的真实派工，不影响计划、dry-run、状态查询和 MCP 基础能力。
- 修改型 worker 任务必须使用隔离 worktree。
- 源码目录和本机安装目录保持分离，不做软链接、不自动同步。

更多隐私边界见 [docs/user/privacy.zh.md](docs/user/privacy.zh.md)。

## 它包含什么

Codex Praetor 有四层：

1. **Skill**：让 Codex 理解“拆分任务给外部 agent”这类自然语言。
2. **Scripts**：用 PowerShell 做稳定、可记录、Windows 友好的派工。
3. **MCP**：把脚本能力包成 Codex 能看见的工具调用。
4. **Plugin**：把 Skill 和 MCP 打包成 Codex 插件，方便安装和发布。

当前 MCP 工具覆盖：

- 任务意图识别
- dry-run 派工
- 真实 worker 派工
- worker 结果摘要和失败分类
- 任务列表
- 状态查询
- 计划生成
- 计划中下一批可运行任务查询
- 计划任务派发
- Codex 验收结论记录
- lane 查询
- lane 详情
- 冲突检测

这条闭环的关键边界是：worker 进程完成不等于任务完成。worker 结果必须由 Codex 读取报告、检查改动、运行必要验证后，记录为“采信、拒绝、重试、需要人工处理或跳过”。只有被 Codex 验收通过的计划任务，才会解锁后续依赖任务。

## 安装前准备

必须准备：

- Windows
- Codex Desktop 或 Codex CLI

安装向导会使用 Windows 自带的 PowerShell。Node.js 是 MCP runtime 的运行依赖，向导会检查它；没有 Node.js 时可以先安装插件，但 MCP 工具需要 Node.js 才能启动。

真实派工还需要至少一个外部 CLI 可用：

- Qoder 或 QoderWork CN
- Tencent CodeBuddy 或 WorkBuddy

Qoder 和 CodeBuddy 通常需要你按官方流程登录或授权。

provider 说明：

- [Qoder](docs/provider-notes/qoder.md)
- [CodeBuddy](docs/provider-notes/codebuddy.md)

## 本地配置

安装向导会把已发现的 provider CLI 路径写入当前用户的本机配置：

```text
%USERPROFILE%\.codex\codex-praetor.local.json
```

向导自己的断点恢复状态保存在：

```text
%USERPROFILE%\.codex\codex-praetor.onboarding-state.json
```

这个状态文件只记录你选择了哪些 provider、每家走到哪一步、CLI 路径、版本、canary 状态和最后一条非敏感提示。它不保存 token、cookie、PAT、API key、账号数据库、余额页面或截图。误关窗口后重新运行 `setup.cmd`，向导会从这里继续；需要完全重选时可运行 `setup.ps1 -ResetOnboardingState`。

如果你想手动配置，也可以复制配置模板：

```powershell
Copy-Item .\config\codex-praetor-tiers.example.json .\config\codex-praetor.local.json
```

然后在本地配置里填入你已经安装的 provider CLI 路径。没有安装的 provider 可以先留空或保留模板值。本机配置不会提交到 Git。

这个本地配置不会被提交。

## 成功时会看到什么

dry-run 成功时，输出会说明 selected provider、tier、repo、artifact root 和将要执行的外部 worker 命令。dry-run 不会启动真实 worker，也不会修改文件。

简化示例：

```text
provider=codebuddy
tier=codebuddy-free
mode=readonly
dry_run=True
project_artifact_root=...\<repo>\.codex-praetor
```

如果 provider 缺失，这不是产品坏了；它只表示真实派工暂不可用。

## 真实派工前的只读 canary

当你已经安装并登录某个 provider 后，先跑只读 canary。它默认只预览命令，不会启动真实 worker：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\verify\test-provider-readonly-canary.ps1 -Provider codebuddy
```

确认 provider 已经登录、命令看起来正确后，再加 `-Apply`：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\verify\test-provider-readonly-canary.ps1 -Provider codebuddy -Apply
```

这个 canary 只要求 worker 读取 `README.md` 并返回固定标记。成功时主仓库的 Git 状态应保持不变。

## 更新、卸载和回滚

更新时下载新版 Release zip 后，重新双击 `setup.cmd` 即可。也可以运行：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\setup.ps1 -Apply
```

安装脚本会先复制到临时目录，校验后再替换旧插件目录，并保留一次备份。

卸载和回滚说明见 [docs/user/uninstall.zh.md](docs/user/uninstall.zh.md)。

## 排错

先看 [docs/user/troubleshooting.zh.md](docs/user/troubleshooting.zh.md)。

常见情况：

- 看不到插件：确认安装成功后，刷新正在运行的 Desktop host 或重启 Codex；仅打开新任务不保证刷新插件发现。
- MCP 工具显示了但报 `Transport closed`：先读取 `runtime_info`，再用独立 host 诊断区分安装态和 Desktop host；诊断脚本不负责刷新 Desktop。
- provider 已安装但没登录：按 provider 自己的官方方式登录，Codex Praetor 不读取账号数据库。
- WindowsApps `codex.exe` 权限问题：优先使用 Codex Desktop 自己的插件/MCP 发现能力。

## 开发者验证

开发者可以在仓库根目录运行产品验证。它只检查仓库、插件包、MCP、安装向导和临时用户安装路径，不依赖本机 Codex 全局规则、已安装 skill 或 provider 登录态：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\verify\doctor-codex-praetor.ps1 -RequireHead -PublicRelease
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\verify\test-codex-praetor.ps1
```

如果要检查当前开发机的 Codex 全局规则、已安装 skill 和 provider dry-run，再运行开发者环境验证：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\verify\test-codex-praetor-dev-env.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\verify\test-provider-readonly-canary.ps1 -Provider codebuddy
```

运行 dry-run：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\dispatch\invoke-codex-praetor.ps1 -Provider codebuddy -Tier codebuddy-free -Repo "<repo>" -Task "Dry run only. Verify Codex Praetor." -Mode readonly -DryRun
```

## 发布包边界

release 包不会包含：

- token
- auth 文件
- provider 账号数据库
- 本机私有配置
- 内部交接材料
- `docs/internal`
- `node_modules`
- 本地缓存
- 个人截图或使用记录

## 仓库结构

```text
README.md         中文主页，GitHub 默认展示。
README.en.md      英文说明。
AGENTS.md         给后续 Codex 维护者看的项目规则。
docs/             文档入口；user、architecture、release、reports 按读者角色分组。
skill/            源码 Skill。
scripts/          源码脚本；dispatch、install、verify、release、maintenance 按用途分组。
mcp/              TypeScript MCP 服务源代码。
plugin/           最终 Codex 插件包结构。
config/           provider 配置模板。
examples/         小型验证样例。
.agents/          Codex repo marketplace 入口。
```

## 贡献和反馈

- 报 bug 前请先看 [docs/user/troubleshooting.zh.md](docs/user/troubleshooting.zh.md)。
- 提交 issue 时不要粘贴 token、cookie、账号页面、provider 数据库、个人截图或完整长日志。
- 贡献说明见 [CONTRIBUTING.md](CONTRIBUTING.md)。
- 安全边界见 [SECURITY.md](SECURITY.md)。
