# Codex Praetor 排错指南

这份指南只讲用户会遇到的情况，不要求你理解内部实现。

## 快速判断

| 现象 | 通常原因 | 下一步 |
| --- | --- | --- |
| 看不到 Codex Praetor 插件 | 插件还没安装，或 Codex 还没刷新插件上下文 | 先确认安装脚本成功，再重启 Codex 或打开新任务 |
| 插件能看到，但 MCP 工具不可见 | MCP 配置没刷新，或 Node 不可用 | 运行轻量 reload；确认 Node.js 已安装 |
| MCP 工具报 `Transport closed` | 当前这一次工具句柄旧了，底层服务不一定坏 | 运行 reload/probe；失败后再重启 Codex 或打开新任务 |
| 没有 Qoder、CodeBuddy、MiMo | 不是故障 | 只能做 plan、dry-run、status、lane/conflict，不能真实派工 |
| provider 已安装但真实派工失败 | provider 未登录、权限不够或 CLI 路径不对 | 重新运行向导选择对应 provider，按官方流程登录，再跑 readonly canary |

## 看不到 Codex Praetor 插件

先确认你已经运行过安装向导。如果你使用的是 `0.1.1-alpha` 的 Windows 安装 zip，优先直接双击根目录的 `setup.cmd`。自动化或排错时也可以运行：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\setup.ps1 -Apply
```

成功输出应包含：

```text
[PASS] Codex Praetor plugin copied to a real local directory.
[PASS] Personal marketplace entry is present.
```

然后重启 Codex，或者打开一个新任务。

插件安装和更新后，Codex 通常需要一个新的工具上下文才能自然看到新插件。

## MCP 工具显示了，但调用时报 `Transport closed`

这通常不是你的任务写错了，也不一定是 Codex Praetor 服务坏了。

先运行轻量恢复：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\verify\reload-codex-praetor-mcp.ps1
```

如果你在 Codex 对话里，并且环境里有 `CODEX_THREAD_ID`，再运行：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\verify\probe-codex-praetor-mcp.ps1 -AfterDirectHandleFailure
```

如果 probe 成功，说明底层 MCP 服务还活着，只是当前这一次模型回合里的工具句柄旧了。可以等待下一轮工具上下文刷新，或重试一次原动作。

如果还是失败，再重启 Codex 或打开新任务。

## 没有安装 Qoder、CodeBuddy、MiMo

这不是故障。

你仍然可以使用：

- 任务意图识别
- plan
- dry-run
- list-jobs
- status
- lane/conflict

真实派工需要至少一个外部 CLI。

想配置 provider 时，重新运行 `setup.cmd`，选择“配置全部 provider”或只选择某一家。向导会检测命令；没装时会让你确认是否执行官方安装命令；装好后刷新 PATH、复检命令，等待你完成 provider 自己的登录/授权，然后写入本机配置。

如果安装过程中误关窗口，直接重新运行 `setup.cmd`。向导会读取 `%USERPROFILE%\.codex\codex-praetor.onboarding-state.json` 继续上次进度。这个状态文件不包含 token、cookie、PAT、API key、账号数据库或余额页面。

## provider 已安装但没有登录

请用 provider 自己的官方方式登录。

Codex Praetor 不会替你登录，也不会读取 provider 的账号数据库、token 或 cookie。

登录后，先预览只读 canary：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\verify\test-provider-readonly-canary.ps1 -Provider mimo
```

确认命令无误后，再真实运行：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\verify\test-provider-readonly-canary.ps1 -Provider mimo -Apply
```

如果 `-Apply` 失败，优先按 provider 官方方式重新登录或修正本地 `cliPath`，不要把 token、cookie、账号页面或本地数据库贴到 issue 或聊天里。

provider 说明：

- [Qoder](provider-notes/qoder.md)
- [CodeBuddy](provider-notes/codebuddy.md)
- [MiMo](provider-notes/mimo.md)

## WindowsApps `codex.exe` 报权限问题

有些 Windows 环境里，PowerShell 调 WindowsApps 别名会遇到权限问题。

优先使用 Codex Desktop 自己的插件/MCP 发现能力。诊断脚本会尽量从 Codex 安装目录寻找真实 `codex.exe`。

## 什么时候才需要新开任务

只有这些情况建议新开：

- 第一次安装插件后。
- 更新插件后。
- 轻量 reload/probe 失败后。
- 最终发布验收时。

平时每次使用 Codex Praetor，不应该都要求新开任务。

## 什么时候运行 doctor

doctor 是排查工具，不是正常使用前置。

只有你要发布、验证本机安装、或者 provider 派工失败时才运行：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\verify\doctor-codex-praetor.ps1 -RequireHead -PublicRelease
```

## 反馈问题前请准备

请只贴精简输出，不要贴 token、cookie、账号页面、provider 数据库、个人截图或完整长日志。

建议准备：

1. Windows 版本。
2. Codex 使用方式：Desktop 还是 CLI。
3. 安装方式：Release zip 还是源码。
4. 是否能看到 `Codex Praetor` 插件。
5. 是否能看到 `codex_praetor_*` MCP 工具。
6. dry-run 是否成功。
7. `reload-codex-praetor-mcp.ps1` 的精简输出。
8. `probe-codex-praetor-mcp.ps1 -AfterDirectHandleFailure` 的精简输出。

然后到 GitHub issue 里反馈：

```text
https://github.com/ga626/codex-praetor/issues
```
