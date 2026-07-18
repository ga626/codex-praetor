# Codex Praetor 用户验收清单

这份清单给最终人工验收用。它验证用户能不能从 GitHub 仓库一路安装、发现插件、做 dry-run，并在失败时知道下一步。

## 1. GitHub 首页

- [ ] 首页第一屏能看懂 Codex Praetor 是什么。
- [ ] 能看到 Release 下载入口。
- [ ] 能看到安装、排错、隐私和路线图入口。
- [ ] 能看懂没有 Qoder、CodeBuddy、MiMo 时仍然可以 dry-run。
- [ ] 能看懂真实派工前需要自己安装并登录至少一个 provider。

## 2. Release 包

- [ ] 从 `v0.5.0-alpha` Release 下载 `codex-praetor-setup-0.5.0-alpha.zip`。
- [ ] 校验 SHA256 文件和 zip 匹配。
- [ ] 解压后根目录能看到 `setup.cmd` 和 `setup.ps1`。
- [ ] 解压后能看到 `README.md`、`README.en.md`、`docs/user/installation.zh.md`、`docs/user/troubleshooting.zh.md`。
- [ ] 包内没有 `docs/internal`、`docs/development`、`handoff`、`node_modules`、本机 local config、token、auth、cookie 或 provider 数据库。

## 3. 安装

- [ ] 双击根目录的 `setup.cmd`。
- [ ] 中文安装向导先显示基础环境和 provider CLI 的可发现状态。
- [ ] 向导提供 5 个选择：全部配置、全部跳过、只配置 Qoder、只配置 CodeBuddy、只配置 MiMo。
- [ ] 选择默认的“暂不配置 provider”，完成 Codex Praetor 本体安装。
- [ ] 选择某一个 provider 时，向导能在用户确认后执行官方安装命令、刷新 PATH、等待用户完成官方登录/授权、复检命令、写入本机配置，并在最终状态总览里说明结果。
- [ ] 误关窗口后重新运行 `setup.cmd`，向导能从 `%USERPROFILE%\.codex\codex-praetor.onboarding-state.json` 继续，且状态文件不包含 token、cookie、PAT、API key、账号数据库或余额页面。
- [ ] 输出包含插件复制成功。
- [ ] 输出包含 marketplace entry 写入成功。
- [ ] 输出最后能用普通中文说明：本体是否可用、哪些 provider 已跳过、哪些 provider 缺安装或登录、下一步 dry-run 输入什么。

高级/自动化路径：

- [ ] 运行预览安装：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\setup.ps1
```

- [ ] 运行真实安装：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\setup.ps1 -Apply
```

- [ ] `%USERPROFILE%\plugins\codex-praetor` 是真实目录，不是链接。
- [ ] `%USERPROFILE%\.agents\plugins\marketplace.json` 里有 `codex-praetor`。

## 4. Codex 插件发现

- [ ] 重启 Codex 或打开一个新任务。
- [ ] 能看到 `Codex Praetor` 插件。
- [ ] 能看到 `codex_praetor_*` MCP 工具。

## 5. dry-run

在 Codex 输入：

```text
拆分一下任务，分配给其他 agent 做 dry-run，不要真实修改文件。
```

验收：

- [ ] 走 Codex Praetor 外部 worker 路线。
- [ ] 不创建 Codex 原生 subagent。
- [ ] 不启动真实 worker。
- [ ] 不修改文件。
- [ ] 输出能说明 provider、tier、mode、artifact root 或等价信息。

## 6. provider 缺失场景

- [ ] 没安装 Qoder、CodeBuddy、MiMo 时，错误提示能说明这不是核心产品故障。
- [ ] plan、dry-run、status、lane/conflict 仍可用。
- [ ] 真实派工会被清楚地阻止或提示下一步。

## 7. provider 只读 canary

- [ ] 向导不会把“CLI 已发现”当作“真实派工已可用”；它会提醒用户真实派工前仍需官方登录/授权和只读 canary。
- [ ] 向导写入的本机配置在 `%USERPROFILE%\.codex\codex-praetor.local.json`，且不包含 token、cookie、PAT、API key 或账号数据库内容。
- [ ] provider 已安装并登录后，先运行预览：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\verify\test-provider-readonly-canary.ps1 -Provider mimo
```

- [ ] 确认命令无误后，再运行真实只读 canary：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\verify\test-provider-readonly-canary.ps1 -Provider mimo -Apply
```

- [ ] 输出包含 `CODEX_PRAETOR_CANARY_OK` 或等价成功标记。
- [ ] 主仓库 Git 状态没有因为只读 canary 变脏。

## 8. 故障恢复

- [ ] `Transport closed` 说明里不会要求用户每次都新开任务。
- [ ] 用户能按排错指南运行独立 host 诊断，并知道它不会刷新正在运行的 Desktop：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\verify\reload-codex-praetor-mcp.ps1
```

- [ ] 在 Codex 线程里可以继续尝试独立 host thread probe：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\verify\probe-codex-praetor-mcp.ps1 -AfterDirectHandleFailure
```

- [ ] 文档明确：native `runtime_info` 仍显示旧 generation 时，先刷新或重启 Desktop host；反复打开新任务不是修复动作。

## 9. 卸载和回滚

- [ ] `docs/user/uninstall.zh.md` 能说明默认安装路径。
- [ ] 能说明如何删除插件目录。
- [ ] 能说明如何从 marketplace 移除 `codex-praetor`。
- [ ] 能说明如何从备份目录回滚。

## 10. GitHub 反馈

- [ ] 仓库有 bug issue template。
- [ ] 仓库有 feature request template。
- [ ] 仓库有 pull request template。
- [ ] issue 模板明确禁止贴 token、cookie、账号页面、provider 数据库、个人截图和完整长日志。
