# Codex Praetor 用户验收清单

这份清单给最终人工验收用。它验证用户能不能从 GitHub 仓库一路安装、发现插件、做 dry-run，并在失败时知道下一步。

## 1. GitHub 首页

- [ ] 首页第一屏能看懂 Codex Praetor 是什么。
- [ ] 能看到 Release 下载入口。
- [ ] 能看到安装、排错、隐私和路线图入口。
- [ ] 能看懂没有 Qoder、CodeBuddy 时仍然可以 dry-run。
- [ ] 能看懂真实派工前需要自己安装并登录至少一个 provider。
- [ ] 能看懂中国版 Qoder CLI `stream-json` 与 CodeBuddy ACP 都由 Codex 监督，且首次真实任务与后续普通派工的证据门槛不同；全球 Qoder Agent SDK 不是中国版 CLI 的自动替代品。

## 2. Release 包

- [ ] 从 `v0.16.30-alpha` Release 下载 `codex-praetor-setup-0.16.30-alpha.zip`。
- [ ] 校验 SHA256 文件和 zip 匹配。
- [ ] 解压后根目录能看到 `setup.cmd` 和 `setup.ps1`。
- [ ] 解压后能看到 `README.md`、`README.en.md`、`docs/user/installation.zh.md`、`docs/user/troubleshooting.zh.md`。
- [ ] 包内没有 `docs/internal`、`docs/development`、`handoff`、`node_modules`、本机 local config、token、auth、cookie 或 provider 数据库。

## 3. 安装

- [ ] 双击根目录的 `setup.cmd`。
- [ ] 中文安装向导先显示基础环境和 provider CLI 的可发现状态。
- [ ] 向导提供 4 个选择：全部配置、全部跳过、只配置 Qoder、只配置 CodeBuddy。
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

- [ ] stable marketplace 的 `plugin/release-generation.json` 与下载 Release 根目录的 generation manifest 一致。
- [ ] 使用 Codex 支持的刷新动作或完全重启 Codex；仅打开新任务不能刷新 host。
- [ ] 刷新后新开任务，`codex_praetor_runtime_info` 的版本和 runtime contract SHA 等于安装身份。
- [ ] 能看到 `Codex Praetor` 插件和 `codex_praetor_*` MCP 工具。
- [ ] 在新 Codex 对话输入“开启 Codex 执行官模式”后，后续实质任务会先按插件 Skill 评估是否适合外派；讨论“执行官模式是什么”不会误开启，也不会调用模式状态工具。
- [ ] 同一对话的后续普通实质任务先按 Skill 评估，再在适合时调用 `codex_praetor_route_intent`；新对话或其他项目不继承该模式。
- [ ] 工具结果默认可读到中文短摘要；若外层工具卡仍由 Desktop 显示英文机器名，以摘要和结构化详情为准。
- [ ] 关闭模式后不再为后续任务主动外派；需要停止已启动 worker 时，明确指定 `job_id` 并读取取消终态。

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

- [ ] 没安装 Qoder、CodeBuddy 时，错误提示能说明这不是核心产品故障。
- [ ] plan、dry-run、status、lane/conflict 仍可用。
- [ ] 真实派工会被清楚地阻止或提示下一步。

## 7. provider 首用与排障 canary

- [ ] 只有第 4 节的安装身份和 host runtime 一致后，才开始真实派工或排障。
- [ ] 向导不会把“CLI 已发现”当作“真实派工已可用”；它会提醒用户完成官方登录/授权，但不会要求先运行只读 canary。
- [ ] 向导写入的本机配置在 `%USERPROFILE%\.codex\codex-praetor.local.json`，且不包含 token、cookie、PAT、API key 或账号数据库内容。
- [ ] provider 已安装并登录后，普通使用直接由 Codex 创建范围清楚的真实计划任务；首条合格的低风险只读任务自动建立本机证据。
- [ ] 只有连接排障时，才运行下面的 canary 预览：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\verify\test-provider-readonly-canary.ps1 -Provider codebuddy
```

- [ ] 确认命令无误后，再运行真实只读 canary：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\verify\test-provider-readonly-canary.ps1 -Provider codebuddy -Apply
```

- [ ] 输出包含 `CODEX_PRAETOR_CANARY_OK` 或等价成功标记。
- [ ] 开始 canary 前主仓库是干净的；若运行中出现仓库变动，输出会明确记录 `external_repo_drift_observed`，不会把它误报成 provider 失败。
- [ ] 更新插件后，health 的 `running_generation` 与当前 `runtime_info` 对应；旧 `active.json` 不会阻断当前版本的 canary 或真实派工。
- [ ] 首次真实任务由 Codex 创建带来源、范围、检查和验收的计划；不会把 canary、marker 或复制材料误报为真实改码证据。
- [ ] worker 持续没有结构化进展时，会进入 `progress_saturated` 并保留终态证据，而不是靠固定轮数无限重跑。

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
