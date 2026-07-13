# Codex Praetor 用户验收清单

这份清单给最终人工验收用。它验证用户能不能从 GitHub 仓库一路安装、发现插件、做 dry-run，并在失败时知道下一步。

## 1. GitHub 首页

- [ ] 首页第一屏能看懂 Codex Praetor 是什么。
- [ ] 能看到 Release 下载入口。
- [ ] 能看到安装、排错、隐私和路线图入口。
- [ ] 能看懂没有 Qoder、CodeBuddy、MiMo 时仍然可以 dry-run。
- [ ] 能看懂真实派工前需要自己安装并登录至少一个 provider。

## 2. Release 包

- [ ] 从 `v0.1.0-alpha` Release 下载 `codex-praetor-setup-0.1.0-alpha.zip`。
- [ ] 校验 SHA256 文件和 zip 匹配。
- [ ] 解压后根目录能看到 `setup.cmd` 和 `setup.ps1`。
- [ ] 解压后能看到 `README.md`、`README.en.md`、`docs/user/installation.zh.md`、`docs/user/troubleshooting.zh.md`。
- [ ] 包内没有 `docs/internal`、`docs/development`、`handoff`、`node_modules`、本机 local config、token、auth、cookie 或 provider 数据库。

## 3. 安装

- [ ] 双击根目录的 `setup.cmd`。
- [ ] 中文安装向导先显示基础环境和 provider CLI 的可发现状态。
- [ ] 选择默认的“暂不配置 provider”，完成 Codex Praetor 本体安装。
- [ ] 输出包含插件复制成功。
- [ ] 输出包含 marketplace entry 写入成功。

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

## 7. 故障恢复

- [ ] `Transport closed` 说明里不会要求用户每次都新开任务。
- [ ] 用户能按排错指南先运行 reload：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\verify\reload-codex-praetor-mcp.ps1
```

- [ ] 在 Codex 线程里可以继续尝试 probe：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\verify\probe-codex-praetor-mcp.ps1 -AfterDirectHandleFailure
```

- [ ] reload/probe 失败后，文档才建议重启 Codex 或打开新任务。

## 8. 卸载和回滚

- [ ] `docs/user/uninstall.zh.md` 能说明默认安装路径。
- [ ] 能说明如何删除插件目录。
- [ ] 能说明如何从 marketplace 移除 `codex-praetor`。
- [ ] 能说明如何从备份目录回滚。

## 9. GitHub 反馈

- [ ] 仓库有 bug issue template。
- [ ] 仓库有 feature request template。
- [ ] 仓库有 pull request template。
- [ ] issue 模板明确禁止贴 token、cookie、账号页面、provider 数据库、个人截图和完整长日志。
