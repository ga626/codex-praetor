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
- Xiaomi MiMo Code

没有这些外部 CLI 也可以先使用 Codex Praetor 的计划、dry-run、状态查询和冲突检测。只有真实派工需要至少一个外部 CLI。

安装前不需要：

- GitHub 登录
- provider token、cookie 或账号数据库
- 同时安装 Qoder、CodeBuddy、MiMo
- 修改 Codex 安装目录

## 推荐方式：从 GitHub Release 安装

### 1. 下载并解压

```powershell
Invoke-WebRequest -Uri "https://github.com/ga626/codex-praetor/releases/download/v0.1.0-alpha/codex-praetor-setup-0.1.0-alpha.zip" -OutFile ".\codex-praetor-setup-0.1.0-alpha.zip"
Expand-Archive .\codex-praetor-setup-0.1.0-alpha.zip .\codex-praetor-setup-0.1.0-alpha
cd .\codex-praetor-setup-0.1.0-alpha
```

也可以手动打开 Release 页面下载：

```text
https://github.com/ga626/codex-praetor/releases/tag/v0.1.0-alpha
```

### 2. 双击安装向导

打开解压后的目录，双击根目录里的 `setup.cmd`。

向导会：

- 检查 PowerShell、Node.js、Git 和 provider CLI 是否可发现。
- 显示 Codex Praetor 本体的安装范围。
- 默认允许你跳过 provider 配置，先完成本体安装。
- 调用现有安装脚本，把插件复制到当前用户目录。

向导不会：

- 自动安装 Qoder、CodeBuddy、MiMo 或 Node.js。
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

### 5. 让 Codex 发现插件

安装后重启 Codex，或者打开一个新任务。

这是 Codex 插件发现机制的正常要求，不是 Codex Praetor 每次使用都要新开任务。平时使用时，如果工具通道临时失败，优先看 [troubleshooting.zh.md](troubleshooting.zh.md) 的轻量恢复步骤。

### 6. 第一次 dry-run

在 Codex 里输入：

```text
拆分一下任务，分配给其他 agent 做 dry-run，不要真实修改文件。
```

你应该看到 Codex Praetor 选择外部 worker 路线，而不是创建 Codex 自己的 subagent。

dry-run 不会启动真实 worker，也不会修改文件。

### 7. 安装验收

在解压后的 release 目录运行：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\doctor-codex-praetor.ps1 -RequireHead -PublicRelease
```

看到 `[PASS]` 后，再在 Codex 里完成一次 dry-run。没有 provider 时，doctor 和 dry-run 仍然应该通过；只有真实派工会不可用。

## 从源码安装

适合开发者：

```powershell
git clone https://github.com/ga626/codex-praetor.git
cd codex-praetor
powershell -NoProfile -ExecutionPolicy Bypass -File .\setup.ps1 -Apply
```

源码安装和 Release 安装使用同一个安装脚本。

## 配置真实派工

真实派工前，你需要自己准备至少一个外部 CLI。

Codex Praetor 不会替你安装 provider，也不会读取账号数据库、token、cookie。Qoder 和 CodeBuddy 通常需要官方登录或授权；MiMo 可以先尝试官方 `mimo/mimo-auto` 限时免费匿名通道，失败或指定其它模型时再走 `/connect`、Token Plan 或 API key。

复制配置模板：

```powershell
Copy-Item .\config\codex-praetor-tiers.example.json .\config\codex-praetor.local.json
```

然后把你已经安装好的 provider CLI 路径填进去。本地配置不会提交到 Git。

更多 provider 说明：

- [Qoder](provider-notes/qoder.md)
- [CodeBuddy](provider-notes/codebuddy.md)
- [MiMo](provider-notes/mimo.md)

## 更新

下载新版 release zip 后，重新双击 `setup.cmd`。自动化场景也可以运行：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\setup.ps1 -Apply
```

安装脚本会用新的插件目录替换旧目录，并保留一次备份。

更新后如果 Codex 看不到插件：

1. 关闭并重新打开 Codex，或新开一个任务。
2. 运行上面的 doctor 验收命令。
3. 仍然失败时，按 [troubleshooting.zh.md](troubleshooting.zh.md) 的顺序执行 reload 和 probe。
4. 需要恢复旧版时，按 [uninstall.zh.md](uninstall.zh.md) 的“回滚到上一个备份”操作。

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
