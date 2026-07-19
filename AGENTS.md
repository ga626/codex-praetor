# Codex Praetor 项目规则

## 产品边界

Codex Praetor 服务于 Codex：把边界清楚的工作分配给外部命令行代理，由 Codex 负责规划、监督和验收。除非用户明确改变范围，否则不要扩展为通用多代理平台。

## 命名与结构

统一使用：产品 `Codex Praetor`，中文名 `Codex 执政官`，仓库/Skill/MCP 服务名 `codex-praetor`，MCP 工具前缀 `codex_praetor_`。

- `skill/`：Skill 源码。
- `scripts/`：按 `dispatch/`、`install/`、`verify/`、`release/`、`maintenance/` 分组的脚本。
- `mcp/`：MCP 源码。
- `plugin/`：最终插件包结构。

旧名称 `cheap-worker-orchestrator`、`WorkerLane`、`workerlane` 只能出现在迁移记录、审计规则或历史报告中，不得作为活动产品名称或新接口名称。

## 本地安装边界

仓库检出目录是开发项目，不是已安装 Skill。当前用户的已安装 Skill 位于：

```text
%USERPROFILE%\.codex\skills\codex-praetor
```

已安装 Skill 必须是真实目录，不得链接到仓库检出目录。开发验证使用明确隔离的 `UserProfileRoot`，不得覆盖稳定 Skill、插件、市场、缓存或活动收据。稳定发布由受保护的 `Release On Main` workflow 自动执行；本地安装仍必须显式复制并校验。

## 开发、PR 与发布

详细发布步骤以 `docs/release/release-gate-checklist.md` 为准；本文件只规定判断边界：

用户入口是 GitHub Release 的 `codex-praetor-setup-*.zip`，不是 `main` 源码树。修改 `setup.cmd`、`setup.ps1`、`plugin/`、`skill/`、`mcp/`、安装/排错/发布文档、版本号或安装体验，均属于影响交付的修改。

- **PR 开发中**：只改源码检出目录和隔离验证环境。发布影响变更必须在同一个 PR 内更新 `config/release-intent.json`、版本面、release notes 和 changelog。
- **PR 就绪**：基于最新目标分支完成工作树、测试、构建、打包、文档、release-intent、冲突和不可复用 tag 检查；缺少 release intent 的发布影响 PR 不得合并。
- **PR 合并后**：受保护的 `Release On Main` workflow 从精确合并提交自动构建、创建 draft、上传资产、发布不可变 Release 并下载复验；不得再靠人工补发版。候选 CI 与发布必须调用同一份 reusable pipeline。若 tag/draft/Release 已存在而后段失败，只能重跑原 GitHub Actions run（它保留原 SHA）；若在创建 tag 前发现 workflow 定义错误，才允许一份显式递增版本的恢复 PR。GitHub 的外部 API/网络存在不可消除的瞬时失败，因此失败状态必须公开，不能静默进入下一次开发。
- **全新上下文触发条件**：只有 MCP 工具名称/参数、Skill 或 Plugin manifest、安装入口、插件来源或工具合同变化时，每个版本代际验收一次；普通实现修改、reload 或文件编辑不触发。
- **产品已交付**：必须同时有活动收据、健康门禁通过、远端包按普通用户路径复验通过，并记录旧版本代际的回收状态。旧文件被占用时报告“新版本已交付，旧版本自动延迟回收中”，不得声称缓存已全部清空。

Codex 负责分支、修改、验证、提交、推送和 PR 材料；用户负责 GitHub 创建/合并 PR 以及一次性仓库权限配置。合并后的发布由受保护 workflow 自动完成，不再要求用户或 Codex 另开发布尾巴。

## 版本代际与回收

- 发布版本代际不可变；不得原地覆盖可能仍被 Codex 对话引用的目录。
- 发布器不得直接删除旧缓存、插件、Skill 或备份，必须交给统一的退休/回收机制。
- 回收机制必须可重复、限定在批准根目录内，并在发布收口、安装、用户登录和后续定时维护时重试。活动版本永远不是回收候选。
- Windows 报告占用、权限或临时 IO 失败时，保留旧版本，记录原因和下次重试时间；不得强杀 Codex、停止 provider 或把延迟删除报告为成功。
- 回收失败不得改变活动收据或回滚已通过的 activation。若自动回收机制尚未实现，不得声称产品已交付。
- 不得用兼容 junction/稳定指针把旧工具合同静默映射到新合同；同合同兼容别名也必须有记录和测试。

## 原生进程调用

- 原生 CLI 以进程退出后的 `exit_code == 0` 判定成功；`stderr` 只是诊断信息。
- 需要读取 `$LASTEXITCODE` 时，不得在 `$ErrorActionPreference = "Stop"` 下用 `2>&1` 合并 provider、Git、发布或 app-server 调用的错误流。
- 统一辅助程序分离捕获 stdout/stderr，记录启动失败、超时、退出码和诊断尾部，兼容 Windows PowerShell 5.1 与 PowerShell 7，避免流死锁。
- marker、工作树、completion 和 provider readiness 是退出码之后的附加门禁；退出码或 marker 任一失败都必须失败。

## 研究与安全

- 外部研究由 Codex 与 KnowledgeRadar 负责路线和证据综合。Provider 代理只能在 Codex 签发、具有 `codex_kr_primary` 并经 `supervisor_verified` 验收的只读研究契约下工作；结果必须有来源、时间、摘录、主张和不确定性。
- 不得提交 API 密钥、认证 token、provider 账户文件、截图或本地数据库；不得修改 Qoder、CodeBuddy、MiMo 内部数据库，必须使用官方命令行接口。
- Codex Praetor 默认不启动 Codex 子代理；节省成本的派工使用外部命令行代理。

## 最小验证

完成代码、迁移或重命名前，必须根据改动范围执行真实文件/命令验证：检查差异和冲突、运行相关测试/构建、确认工作树状态，并确认最终用户路径可用。重命名/迁移还必须：扫描活动产品文件中的旧名称（排除本规则、迁移记录和历史报告）、运行 `scripts/dispatch/invoke-codex-praetor.ps1` 试运行、确认 Skill/plugin manifest 名称、确认运行时输出被 Git 忽略且已安装 Skill 是真实目录。
