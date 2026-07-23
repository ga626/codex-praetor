# Codex Praetor 安装指南

这份指南面向普通 Windows 用户。你不需要先理解 MCP、Skill 或插件内部结构，只要按顺序做。

## 安装前准备

必须准备：

- Windows
- Codex Desktop 或 Codex CLI

安装向导会使用 Windows 自带的 PowerShell。Node.js 是 MCP runtime 的运行依赖，向导会检查它；如果没有安装，Codex Praetor 本体仍可先安装，但 MCP 工具需要 Node.js 才能启动。

可选准备：

- Qoder 或 QoderWork CN
- Tencent CodeBuddy 或 WorkBuddy

没有这些外部 CLI 也可以先使用 Codex Praetor 的计划、dry-run、状态查询和冲突检测。真实派工、结果收集和计划任务推进需要至少一个外部 CLI。

安装前不需要：

- GitHub 登录
- provider token、cookie 或账号数据库
- 同时安装 Qoder、CodeBuddy
- 修改 Codex 安装目录

## 推荐方式：从 GitHub Release 安装

### 1. 下载并解压

```powershell
Invoke-WebRequest -Uri "https://github.com/ga626/codex-praetor/releases/download/v0.9.8-alpha/codex-praetor-setup-0.9.8-alpha.zip" -OutFile ".\codex-praetor-setup-0.9.8-alpha.zip"
Expand-Archive .\codex-praetor-setup-0.9.8-alpha.zip .\codex-praetor-setup-0.9.8-alpha
cd .\codex-praetor-setup-0.9.8-alpha
```

也可以手动打开 Release 页面下载：

```text
https://github.com/ga626/codex-praetor/releases/tag/v0.9.8-alpha
```

### 2. 双击安装向导

打开解压后的目录，双击根目录里的 `setup.cmd`。

向导会：

- 检查 PowerShell、Node.js、Git 和 provider CLI 是否可发现。
- 显示 Codex Praetor 本体的安装范围。
- 让你选择“配置全部 provider / 全部跳过 / 只配置某一家”。
- 对选中的 provider 检查命令；如果没装，会让你确认是否执行官方安装命令。
- 安装 provider 后刷新当前终端 PATH，并复检命令和版本。
- 在同一个向导里等待你完成 provider 官方登录、扫码、浏览器授权、站点选择、企业域、Token Plan 或 API key 等账号动作。
- 你回到向导继续后再次复检，并给出 canary 预览或真实只读 canary 选项。
- 把已发现的 provider CLI 路径写入当前用户本机配置。
- 最后给出一张中文状态总览，告诉你本体是否可用、哪些 provider 可继续 canary、哪些还缺安装或登录。
- 调用现有安装脚本，把插件复制到当前用户目录。
- 安装用户级代际维护任务：登录时运行一次，之后每 15 分钟重试旧 generation、备份和失败临时目录的安全回收。

向导不会：

- 在未经你确认时安装 Qoder、CodeBuddy 或 Node.js。
- 替你登录 provider。
- 读取 token、cookie、账号数据库或个人截图。
- 修改 Codex 安装目录或永久修改 PowerShell 执行策略。

### 3. 只预览安装计划

如果你想先看路径和检查结果，可以在解压目录打开 PowerShell，运行：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\setup.ps1
```

预览只会显示将要复制到哪里，不会改文件。

### 4. 用 PowerShell 执行安装

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\setup.ps1 -Apply
```

双击 `setup.cmd` 时，向导会自动执行同一个安装流程。成功时会看到：

```text
[PASS] Codex Praetor plugin copied to a real local directory.
[PASS] Personal marketplace entry is present.
```

默认安装位置：

```text
%USERPROFILE%\plugins\codex-praetor
```

默认 marketplace 文件：

```text
%USERPROFILE%\.agents\plugins\marketplace.json
```

安装脚本会先复制到临时目录，校验文件 hash 后再替换旧目录。旧目录会被移动到备份目录。

旧目录不会在安装瞬间强制删除。维护任务会按退休清单保留仍可能被占用的目录，并在后续安全重试；不会强杀 Codex，也不会影响已加载的新插件。旧 `active.json` 只记录历史发布证据，不是当前插件是否可派工的依据。可以这样查看任务：

```powershell
Get-ScheduledTask -TaskName CodexPraetor-GenerationReconcile
```

正式更新会生成发布证据，记录下载包校验和同一 artifact 的发布结果。真实派工由当前运行插件自身决定：它会验证当前 bundled generation、runtime contract，以及所选 provider 的 CLI、模型、权限、任务类型和有效的只读 canary。旧发布回执、旧缓存或旧 `active.json` 不会反向阻断已加载的新插件；如果当前版本尚未完成 canary，系统会明确提示先运行一次真实只读 canary。

### 5. 让 Codex 发现插件

先确认 stable marketplace 已安装该下载包的 `release-generation.json`，再使用 Codex 支持的刷新动作或完全重启 Codex Desktop。刷新后新开一个任务，先调用 `codex_praetor_runtime_info`；它的版本和 runtime contract SHA 必须等于下载包。仅打开新任务不能刷新已经运行的 host。

身份一致后才运行真实只读 canary；canary 通过后再做 dry-run 或真实派工。平时工具通道临时失败时，优先看 [troubleshooting.zh.md](troubleshooting.zh.md) 的轻量恢复步骤。

### 6. 第一次 dry-run

在 Codex 里输入：

```text
拆分一下任务，分配给其他 agent 做 dry-run，不要真实修改文件。
```

你应该看到 Codex Praetor 选择外部 worker 路线，而不是创建 Codex 自己的 subagent。

dry-run 不会启动真实 worker，也不会修改文件。等 provider 安装、登录和只读 canary 都通过后，Codex 才应该进入真实派工闭环：派发 worker、读取结果、检查报告或改动、记录验收结论，再继续下一批计划任务。

### 7. 安装验收

在解压后的 release 目录运行：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\verify\doctor-codex-praetor.ps1 -RequireHead -PublicRelease
```

看到 `[PASS]` 后，再在 Codex 里完成一次 dry-run。没有 provider 时，doctor 和 dry-run 仍然应该通过；只有真实派工会不可用。

如果你已经安装并登录某个 provider，再跑只读 canary。默认只预览命令，不会启动真实 worker：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\verify\test-provider-readonly-canary.ps1 -Provider codebuddy
```

确认 provider 已经登录、命令看起来正确后，再加 `-Apply`：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\verify\test-provider-readonly-canary.ps1 -Provider codebuddy -Apply
```

这个 canary 只读取 `README.md`。开始前主仓库必须是干净的；如果运行期间有其他流程改动仓库，系统会保留真实 provider 结果并记录这次仓库变动，先审查变动再进入编辑任务。它通过后，再考虑真实派工。真实派工完成后不代表任务自动完成；Codex 还要读取 worker 结果，确认输出能采信，必要时看 diff、跑验证，再把任务标成采信、拒绝、重试、需要人工处理或跳过。

## 从源码安装

适合开发者：

```powershell
git clone https://github.com/ga626/codex-praetor.git
cd codex-praetor
powershell -NoProfile -ExecutionPolicy Bypass -File .\setup.ps1 -Apply
```

源码安装和 Release 安装使用同一个安装脚本。

## 向导里的 provider 选择

安装本体时，向导会出现 5 个选项：

```text
1. 配置全部 provider
2. 先不配置 provider，只安装并验证 Codex Praetor 本体
3. 只配置 Qoder
4. 只配置 CodeBuddy
```

默认推荐第 2 项。这样即使你还没准备 Qoder 或 CodeBuddy，也可以先把 Codex Praetor 本体装好，并在 Codex 里验证 dry-run。

如果你选择某个 provider，向导会按这个顺序处理：

1. 检查本机有没有对应命令。
2. 没有命令时，列出官方安装方式，并让你选择“执行官方安装 / 打开官方说明 / 重新检测 / 跳过”。
3. 你确认后，向导先检查对应官方安装源的网络是否可用，再执行 provider 的官方安装命令；它不使用第三方镜像，不把 provider 打进 Codex Praetor 包。
4. 安装结束后，向导刷新当前终端 PATH，并主动检查 provider 的常见安装目录，例如 Qoder 的 `.qoder`、CodeBuddy 的 `AppData\Local\codebuddy\bin`，然后重新检测命令和版本。
5. 命令可用后，向导进入登录/授权陪跑。它会停在同一个窗口里，让你启动 provider 官方 CLI，并按官方流程完成登录、扫码、站点选择、企业域、Token Plan 或 API key 等账号动作。
6. 你回到向导继续后，向导再次检测 CLI，并把已发现的 CLI 路径写入本机配置。
7. 最后给出只读 canary 的预览或真实运行选项。

这里的“等待你完成”很重要。Codex Praetor 会把能自动做的事情做掉，但不会替你输入密码、选择站点、扫码、购买 Token Plan、复制 API key，也不会读取任何 provider 账号文件。

如果你在安装或登录阶段选择跳过，Codex Praetor 本体仍然会继续安装。跳过只表示这家 provider 暂时不能真实派工；之后重新运行 `setup.cmd`，选择同一家 provider，就可以继续配置。

如果官方安装源因为网络或代理暂时不可达，向导会给出中文提示。你可以修好网络后重试，也可以先跳过这家 provider；这不会影响 Codex Praetor 本体安装。

## 配置真实派工

真实派工前，你需要至少一个外部 CLI 已安装、已授权，并通过只读 canary。

Codex Praetor 不会在未经你确认时安装 provider，也不会读取账号数据库、token、cookie。Qoder 和 CodeBuddy 通常需要官方登录或授权。

向导会优先写入当前用户级配置：

```text
%USERPROFILE%\.codex\codex-praetor.local.json
```

向导还会保存一个断点恢复状态：

```text
%USERPROFILE%\.codex\codex-praetor.onboarding-state.json
```

如果安装过程中误关窗口，重新双击 `setup.cmd`，向导会提示继续上次进度。这个状态文件只记录选择、步骤、CLI 路径、版本、canary 状态和失败原因，不记录 token、cookie、PAT、API key、账号数据库、余额页面或截图。想完全重来，可以运行：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\setup.ps1 -ResetOnboardingState
```

如果你想手动维护仓库内的本地配置，可以复制模板：

```powershell
Copy-Item .\config\codex-praetor-tiers.example.json .\config\codex-praetor.local.json
```

然后把你已经安装好的 provider CLI 路径填进去。本地配置不会提交到 Git。

更多 provider 说明：

- [Qoder](../provider-notes/qoder.md)
- [CodeBuddy](../provider-notes/codebuddy.md)

## 更新

下载新版 release zip 后，重新双击 `setup.cmd`。自动化场景也可以运行：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\setup.ps1 -Apply
```

安装脚本会用新的插件目录替换旧目录，并保留一次备份。

旧 generation、插件备份和失败临时目录由同一个回收清单统一追踪。更新后不需要每次手动清理；如果 Codex 仍在使用旧路径，健康检查会显示延迟回收状态，释放占用后维护任务自动重试。

更新后如果 Codex 看不到插件：

1. 关闭并重新打开 Codex，或新开一个任务。
2. 运行上面的 doctor 验收命令。
3. provider 已经安装并登录时，先跑只读 canary，再做真实派工。
4. 仍然失败时，按 [troubleshooting.zh.md](troubleshooting.zh.md) 区分独立 host 诊断与正在运行的 Desktop host；不要把新任务当作刷新动作。
5. 需要恢复旧版时，按 [uninstall.zh.md](uninstall.zh.md) 的“回滚到上一个备份”操作。

## 卸载和回滚

看 [uninstall.zh.md](uninstall.zh.md)。

## PowerShell 提示不能运行脚本

使用本指南里的命令：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\setup.ps1 -Apply
```

这个命令只对本次运行临时绕过执行策略，不会永久修改系统策略。

## 下一步

如果插件看不到，或者 MCP 工具调用失败，请看：

[troubleshooting.zh.md](troubleshooting.zh.md)
