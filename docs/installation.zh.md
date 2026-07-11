# Codex Praetor 安装指南

这份指南面向普通 Windows 用户。你不需要先理解 MCP、Skill 或插件内部结构，只要按顺序做。

## 你需要准备什么

必须准备：

- Windows
- Codex Desktop 或 Codex CLI
- PowerShell
- Node.js

可选准备：

- Qoder 或 QoderWork CN
- Tencent CodeBuddy 或 WorkBuddy
- Xiaomi MiMo Code

没有这些外部 CLI 也可以先使用 Codex Praetor 的计划、dry-run、状态查询和冲突检测。只有真实派工需要至少一个外部 CLI。

## 推荐安装方式

### 方式一：从 GitHub Release 安装

1. 打开 GitHub Release 页面。
2. 下载 `codex-praetor-0.1.0-alpha.zip`。
3. 解压到一个普通目录，例如：

```powershell
Expand-Archive .\codex-praetor-0.1.0-alpha.zip .\codex-praetor-0.1.0-alpha
cd .\codex-praetor-0.1.0-alpha
```

4. 先预览安装计划：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\install-user.ps1
```

5. 确认路径没问题后执行安装：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\install-user.ps1 -Apply
```

6. 重启 Codex，或者打开一个新任务，让 Codex 重新发现插件。

### 方式二：从源码安装

适合开发者：

```powershell
git clone https://github.com/ga626/codex-praetor.git
cd codex-praetor
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\install-user.ps1 -Apply
```

## 第一次验证

先跑 dry-run，不要真实派工：

```text
拆分一下任务，分配给其他 agent 做 dry-run，不要真实修改文件。
```

你应该看到 Codex Praetor 选择外部 worker 路线，而不是创建 Codex 自己的 subagent。

## 配置真实派工

真实派工前，你需要自己安装并登录至少一个外部 CLI。

Codex Praetor 不会替你安装 provider，也不会读取账号数据库、token、cookie。

配置模板在：

```text
config\codex-praetor-tiers.example.json
```

复制成本地配置：

```powershell
Copy-Item .\config\codex-praetor-tiers.example.json .\config\codex-praetor.local.json
```

然后把你已经安装好的 provider CLI 路径填进去。本地配置不会提交到 Git。

更多 provider 说明：

- [Qoder](provider-notes/qoder.md)
- [CodeBuddy](provider-notes/codebuddy.md)
- [MiMo](provider-notes/mimo.md)

## 更新

下载新版 release zip 后，重新运行：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\install-user.ps1 -Apply
```

安装脚本会用新的插件目录替换旧目录，并保留一次备份。

## 下一步

如果插件看不到，或者 MCP 工具调用失败，请看：

[troubleshooting.zh.md](troubleshooting.zh.md)
