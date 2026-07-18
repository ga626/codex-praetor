# Codex Praetor 排错指南

这份指南只讲用户会遇到的情况，不要求你理解内部实现。

## 快速判断

| 现象 | 通常原因 | 下一步 |
| --- | --- | --- |
| 看不到 Codex Praetor 插件 | 插件还没安装，或常驻 Desktop host 仍解析旧注册表 | 先确认安装脚本成功；新任务不能刷新 host，使用 Codex 支持的刷新动作或完全退出后重新启动 |
| 插件能看到，但 MCP 工具不可见 | Desktop host 的插件发现未刷新，或 Node 不可用 | 先确认 Node.js；用独立 host 诊断区分磁盘安装与常驻 Desktop host |
| MCP 工具报 `Transport closed` | 当前回合的工具句柄旧，或常驻 host 未刷新 | 单独 probe 只能诊断，不能刷新 Desktop；先确认 runtime identity，再按支持的 Desktop 刷新动作恢复 |
| 没有 Qoder、CodeBuddy、MiMo | 不是故障 | 只能做 plan、dry-run、status、lane/conflict，不能真实派工 |
| provider 已安装但真实派工失败 | provider 未登录、权限不够、CLI 路径不对、任务超轮数或 worker 无有效产出 | 先读取 worker result 摘要和失败分类；需要账号动作时重新运行向导，任务太大时缩小后重派 |
| 执行 provider 官方安装时提示网络不可用或超时 | 官方安装源、DNS、代理或系统网络还没准备好 | 检查网络/代理后重试；也可以先跳过 provider，先完成本体安装 |
| 更新后旧目录仍然存在 | 旧 generation 仍在保留窗口内，或被 Codex/运行时占用 | 查看 health/退休清单；不要强杀 Codex，维护任务会在下次登录或 15 分钟重试 |

## 看不到 Codex Praetor 插件

先确认你已经运行过安装向导。如果你使用的是 `0.4.1-alpha` 的 Windows 安装 zip，优先直接双击根目录的 `setup.cmd`。自动化或排错时也可以运行：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\setup.ps1 -Apply
```

成功输出应包含：

```text
[PASS] Codex Praetor plugin copied to a real local directory.
[PASS] Personal marketplace entry is present.
```

然后使用 Codex 支持的插件刷新动作，或者完全退出并重新启动 Codex。仅打开一个新任务不保证刷新已经运行数小时的 Desktop host。

插件安装和更新后，需要同时满足“Desktop host 已重新解析插件”和“新工具上下文已创建”两个条件。后者不能替代前者。

## MCP 工具显示了，但调用时报 `Transport closed`

这通常不是你的任务写错了，也不一定是 Codex Praetor 服务坏了。

下面的命令只会启动一个独立 app-server 来诊断磁盘上的安装代际；它不会刷新已经运行的 Codex Desktop。它适合回答“新 host 能否解析当前插件”，不适合作为 Desktop 已修复的证据：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\verify\reload-codex-praetor-mcp.ps1
```

如果你在 Codex 对话里，并且环境里有 `CODEX_THREAD_ID`，再运行：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\verify\probe-codex-praetor-mcp.ps1 -AfterDirectHandleFailure
```

如果 probe 成功，只说明独立 app-server 可以调用该工具；它不能证明当前 Desktop host 已切换。先在 native `codex_praetor_runtime_info` 中核对版本、SHA256 和路径，再完成一次支持的 host 刷新。

如果 native `runtime_info` 仍显示旧版本或旧路径，完全退出并重新启动 Codex 后再做一次 canary；不要靠反复新建任务绕过。

## 旧 generation 没有立即删除

这是预期的生命周期状态，不代表新版本没有安装成功。发布或更新会先写入新的 immutable generation，再把旧插件、Skill 备份、cache 目录登记到退休清单。只有 active receipt 存在、路径超过保留窗口且没有占用时，维护任务才会删除它。

查看维护任务和退休清单：

```powershell
Get-ScheduledTask -TaskName CodexPraetor-GenerationReconcile
Get-Content "$env:USERPROFILE\.codex\codex-praetor-releases\stable\retirement.json"
```

`blocked_by_process` 表示 Windows 拒绝了当前删除尝试；不要手动移动旧目录，也不要强杀 Codex。关闭或退出仍引用旧路径的程序后，任务会自动重试。`active` generation 永远不会进入回收候选。

## 没有安装 Qoder、CodeBuddy、MiMo

这不是故障。

你仍然可以使用：

- 任务意图识别
- plan
- dry-run
- list-jobs
- status
- lane/conflict

真实派工、worker result 读取和计划任务推进需要至少一个外部 CLI。没有 provider 时，MCP 工具仍然可以创建计划、做 dry-run、查 lane/conflict，但不会真的启动 worker。

想配置 provider 时，重新运行 `setup.cmd`，选择“配置全部 provider”或只选择某一家。向导会检测命令；没装时会让你确认是否执行官方安装命令；装好后刷新 PATH、复检命令，等待你完成 provider 自己的登录/授权，然后写入本机配置。

如果安装过程中误关窗口，直接重新运行 `setup.cmd`。向导会读取 `%USERPROFILE%\.codex\codex-praetor.onboarding-state.json` 继续上次进度。这个状态文件不包含 token、cookie、PAT、API key、账号数据库或余额页面。

如果你只是暂时跳过 provider 安装或登录，这也是正常状态。本体安装、dry-run 和状态查询应该继续可用；真实派工等你后续把至少一家 provider 配好以后再启用。

如果官方安装源网络不可用或安装命令超时，先确认浏览器能打开对应 provider 官网，再重新运行 `setup.cmd`。公司网络、代理软件、VPN、DNS 或刚恢复的虚拟机网络都可能导致官方安装源暂时不可达。

## provider 已安装但没有登录

请用 provider 自己的官方方式登录。

Codex Praetor 不会替你登录，也不会读取 provider 的账号数据库、token 或 cookie。

如果向导刚装完 provider 后一时找不到命令，先重新运行 `setup.cmd` 选择同一家 provider。新版向导会同时检查 PATH 和常见安装目录：Qoder 的 `.qoder`、CodeBuddy 的 `AppData\Local\codebuddy\bin`、MiMo 的 `.mimocode\bin`。

登录后，先预览 capability canary：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\verify\test-provider-capability-canary.ps1 -Provider mimo
```

确认命令无误后，再真实运行：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\verify\test-provider-capability-canary.ps1 -Provider mimo -Apply
```

如果 `-Apply` 失败，优先按 provider 官方方式重新登录或修正本地 `cliPath`。版本、模型或权限合同变化后需要重新运行 canary；不要把 token、cookie、账号页面或本地数据库贴到 issue 或聊天里。

## worker 完成但任务没有继续

这是正常安全边界。

Codex Praetor 现在把“worker 进程完成”和“任务验收通过”分开处理。worker 完成后，计划任务会停在等待 Codex 验收的状态；Codex 必须读取 worker 结果、看必要的文件差异或报告、运行最小验证，然后记录结论。

结论有五种：

- 采信：结果可用，后续依赖任务可以继续。
- 拒绝：结果不可用，不推进后续任务。
- 重试：任务需要缩小、换 provider 或提高轮数后重派。
- 需要人工处理：登录、授权、发布、合并或产品判断需要用户参与。
- 跳过：这项任务被明确取消或不再需要。

如果 worker 输出里出现 `Max turns exceeded` 或类似超轮数提示，不要把它当作有效完成。正确做法是缩小任务、提高轮数、换 provider，或者让 Codex 接管并说明原因。

provider 说明：

- [Qoder](../provider-notes/qoder.md)
- [CodeBuddy](../provider-notes/codebuddy.md)
- [MiMo](../provider-notes/mimo.md)

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
