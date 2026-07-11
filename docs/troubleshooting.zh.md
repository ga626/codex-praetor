# Codex Praetor 排错指南

这份指南只讲用户会遇到的情况，不要求你理解内部实现。

## 看不到 Codex Praetor 插件

先确认你已经运行过：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\install-user.ps1 -Apply
```

然后重启 Codex，或者打开一个新任务。

插件安装和更新后，Codex 通常需要一个新的工具上下文才能自然看到新插件。

## MCP 工具显示了，但调用时报 `Transport closed`

这通常不是你的任务写错了，也不一定是 Codex Praetor 服务坏了。

先运行轻量恢复：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\reload-codex-praetor-mcp.ps1
```

如果你在 Codex 对话里，有 `CODEX_THREAD_ID`，再运行：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\probe-codex-praetor-mcp.ps1 -AfterDirectHandleFailure
```

如果 probe 成功，说明底层 MCP 服务还活着，只是当前这一次模型回合里的工具句柄旧了。继续工作时可以等待下一轮工具上下文刷新；如果还是失败，再重启 Codex 或打开新任务。

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

## provider 已安装但没有登录

请用 provider 自己的官方方式登录。

Codex Praetor 不会替你登录，也不会读取 provider 的账号数据库、token 或 cookie。

## WindowsApps `codex.exe` 报权限问题

有些 Windows 环境里，PowerShell 调 WindowsApps 别名会遇到权限问题。

优先使用 Codex Desktop 自己的插件/MCP 发现能力；诊断脚本会尽量从 Codex 安装目录寻找真实 `codex.exe`。

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
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\doctor-codex-praetor.ps1 -RequireHead -PublicRelease
```

## 仍然不行怎么办

请记录三件事：

1. 你运行的命令。
2. `reload-codex-praetor-mcp.ps1` 的输出。
3. `probe-codex-praetor-mcp.ps1 -AfterDirectHandleFailure` 的输出。

然后到 GitHub issue 里反馈。
