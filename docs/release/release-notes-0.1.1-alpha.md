# Codex 执政官 0.1.1-alpha 发布说明

发布时间：2026-07-13

这是一次发布收口版，不是一次大功能扩张。它把前几轮已经完成的安装体验、provider 配置引导、目录整理、运行态隔离和发布包边界统一到一个新的公开 Release 版本里，避免用户在 GitHub 页面、README、安装指南和实际 zip 包之间看到互相打架的路径。

## 下载

- Release 页面：`v0.1.1-alpha`
- Windows 用户安装包：`codex-praetor-setup-0.1.1-alpha.zip`
- 校验文件：`codex-praetor-setup-0.1.1-alpha.zip.sha256`

解压后，普通 Windows 用户优先双击根目录里的：

```powershell
.\setup.cmd
```

自动化或排错时可以运行：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\setup.ps1 -Apply
```

## 这版解决了什么

- 公开下载包统一使用 `codex-praetor-setup-0.1.1-alpha.zip`，让用户一眼知道这是安装包，不是 GitHub 自动生成的源码包。
- 根目录保留 `setup.cmd` 和 `setup.ps1`，普通用户可以双击安装，开发者和自动化流程也能继续使用 PowerShell。
- 安装向导支持 5 个 provider 选择：配置全部、全部跳过、只配置 Qoder、只配置 CodeBuddy、只配置 MiMo。
- 向导会在用户确认后执行官方 provider 安装命令，刷新 PATH，等待用户完成官方登录/授权，复检 CLI，并把已发现的 provider 路径写入本机用户配置。
- 向导会保存非敏感断点恢复状态；误关窗口后重新运行 `setup.cmd` 可以继续上次进度。
- 向导最终输出中文状态总览，明确区分“本体已安装”“CLI 已发现”“仍需官方登录/授权”“可继续只读 canary”。
- 文档入口整理为 `docs/user`、`docs/release`、`docs/architecture` 和 `docs/reports`，用户安装和排错不需要翻历史调研报告。
- 脚本入口整理为 `scripts/dispatch`、`scripts/install`、`scripts/verify`、`scripts/release` 和 `scripts/maintenance`，发布检查和安装流程指向同一套路径。
- 运行态任务、锁、日志和 worker 输出继续放在项目内 `.codex-praetor`，不会在 `D:\Projects` 根目录旁边创建同级杂项目录。
- MCP、插件 manifest、安装向导和发布脚本的版本号统一到 `0.1.1-alpha`。

## 用户可以直接验证什么

- 下载 zip 后，根目录能看到 `setup.cmd`、`setup.ps1`、`README.md`、`docs/user/installation.zh.md` 和 `docs/user/troubleshooting.zh.md`。
- 双击 `setup.cmd` 会出现中文安装向导；向导会检查 PowerShell、Node.js、Git 和 provider CLI 是否可发现。
- 向导里可以选择全部 provider、全部跳过或只配置某一家；跳过 provider 不会让本体安装失败。
- 没有安装 Qoder、CodeBuddy、MiMo 时，计划、dry-run、状态查询和冲突检测仍然可以验收；真实派工会被清楚阻止。
- 安装后重启 Codex 或打开新任务，应该能看到 Codex Praetor 插件和 `codex_praetor_*` MCP 工具。

## 维护者发布前必须验证什么

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\verify\doctor-codex-praetor.ps1 -RequireHead -PublicRelease
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\verify\test-codex-praetor.ps1
npm test --prefix .\mcp
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\release\build-codex-praetor-release.ps1 -Apply
```

发布包必须排除 `docs/internal`、`docs/development`、`handoff`、`node_modules`、本机 local config、token、auth、cookie、provider 数据库、运行态 job 日志和个人截图。

## 仍然不是这版要做的事

- 不实现通用多 Agent 平台。
- 不在未经用户确认时安装或代登录 Qoder、CodeBuddy、MiMo。
- 不读取 provider token、cookie、账号数据库、余额页或个人截图。
- 不默认创建 Codex 原生 subagent。
- 不把 D 盘源码目录和 C 盘用户安装目录做软链接或自动同步。
- 不把 provider 真实派工失败恢复体验和文件级冲突合并成这次发布收口 PR。
