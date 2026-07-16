# Codex 执政官开发期插件热更新与 PowerShell 可观测错误治理证据登记

日期：2026-07-16
范围：当前 Codex Desktop/app-server、Codex Praetor `main`、Windows PowerShell 5.1、Qoder capability canary。
本登记只记录调查证据和证据等级，不代表本轮已执行修复。

## 证据等级

- **A 级**：本机当前状态、真实命令结果、当前源码、官方正文或官方仓库实现/Issue 原文。
- **B 级**：官方搜索摘要、历史验收记录、公开文档的辅助结果；需注意版本、访问方式和时间边界。
- **C 级**：由多个 A/B 证据形成的工程推断，仍有平台内部实现细节缺口。

## 一、本地状态与复现证据

| ID | 等级 | 来源 | 事实 | 支持的结论 |
|---|---|---|---|---|
| L01 | A | `D:\Projects\CodexPraetor`：`git status --short --branch`、`git log` | 当前为 `main`，HEAD `0a62eb7`，与 `origin/main` 一致，tag `v0.2.0-alpha`，初始工作树干净 | 本轮报告未建立在未提交代码改动上 |
| L02 | A | `scripts\verify\reload-codex-praetor-mcp.ps1` | 脚本调用 app-server `config/mcpServer/reload`，随后查询 `mcpServerStatus/list` | 项目已有 MCP reload 探针，reload 能力边界可被单独验证 |
| L03 | A | 本轮现场复现记录 | 远端 `v0.2.0-alpha` 已安装；app-server reload 后显示 server version `0.2.0-alpha`、tool count 17 | MCP server 层已经刷新到新 generation |
| L04 | A | 本轮当前 Codex 对话的 native MCP 调用记录 | 同一对话仍调用 `...codex-praetor\0.1.1-alpha\scripts\dispatch\invoke-codex-praetor.ps1` | 当前对话仍保留旧 cache/path 引用，reload 不等于当前会话完全替换 |
| L05 | A | `codex exec --ephemeral --sandbox read-only` fresh-context 记录 | 第一次 fresh context route intent、Qoder readonly dry-run、lane list 通过；未创建真实 worker | 新 context 可加载新能力并完成只读路线 |
| L06 | A | 第二次严格 fresh-context native MCP 记录 | 17 个 `codex_praetor_*` 工具全部可见，`missing_expected=[]`，status `passed` | 问题一不是新包本身无法工作，而是旧对话上下文边界 |
| L07 | A | `C:\Users\ga990\.codex\plugins\cache\personal\codex-praetor\0.1.1-alpha` 与当前进程占用观察 | 旧 cache 目录被当前 Codex 进程占用，无法删除 | 强制清理不是可靠热更新策略；应延迟回收 |
| L08 | A | Windows PowerShell 版本探针 | `5.1.19041.6456`，edition `Desktop`，`$PSNativeCommandUseErrorActionPreference` 不存在 | 不能把 PowerShell 7.3/7.4 的 native error preference 当作本机通用修复 |
| L09 | A | `scripts\verify\test-provider-capability-canary.ps1:19,82-83` | 全局 `$ErrorActionPreference = "Stop"`；`& powershell @argsList 2>&1` 后才读取 `$LASTEXITCODE` | 包装器存在 stderr 先于 exit-code 判定的根因路径 |
| L10 | A | Qoder `git worktree add` 输出记录 | 成功时 stderr 含 `Preparing worktree (new branch ...)` | stderr 有内容不代表子进程失败 |
| L11 | A | 隔离 worktree 中直接执行官方 Qoder CLI | 返回 `CODEX_PRAETOR_CAPABILITY_CANARY_OK`，主仓库和 Qoder worktree 干净 | provider 能力通过；失败属于 PowerShell 包装层观测问题 |
| L12 | A | `scripts\verify\test-provider-capability-canary.ps1` apply 分支 | 在 exit code 后还检查 marker、主仓库前后状态，并写 readiness tuple | 修复必须保持 exit code、marker、状态和 readiness 的多重门禁，不能只吞 stderr |

## 二、Codex 官方仓库和文档证据

| ID | 等级 | URL | 调查结果 | 边界 |
|---|---|---|---|---|
| O01 | A | [openai/codex#8957](https://github.com/openai/codex/issues/8957) | `mcpServer/refresh` 已实现；active threads 收到 pending refresh；后续 turn 才重新初始化 MCP manager | 支持 reload 是延迟/分阶段机制，不保证当前模型快照立即换代 |
| O02 | A | [openai/codex#20605](https://github.com/openai/codex/issues/20605) | 已有 Codex thread 无法热加载本地 MCP 工具变化；fresh local probe 能看到新工具，旧 thread 看不到；workaround 是新 thread/session | 公开 issue 仍不能替代稳定官方热更新 API |
| O03 | A | [openai/codex#16653](https://github.com/openai/codex/issues/16653) | 当前会话修改本地 Skill/Plugin 后不会自动拾取；请求 `/reload-skills`、`/reload-plugins` | Skill/plugin 热替换边界仍是平台缺口 |
| O04 | A | [openai/codex#4955](https://github.com/openai/codex/issues/4955) | 请求单独重启 MCP server；issue 描述 MCP server 通常由 connection manager 初始化并持续运行 | server 生命周期和对话工具快照不能混为一谈 |
| O05 | A | [openai/codex#21138](https://github.com/openai/codex/issues/21138) | Windows stale plugin cache：同 version 目录源内容变化仍可能继续使用旧 cache，缺少内容/provenance 校验 | 原地覆盖同版本目录风险高 |
| O06 | A | [openai/codex#24390](https://github.com/openai/codex/issues/24390) | Windows Desktop plugin 更新后已有 conversation 仍可能引用旧 cache path | 支持延迟回收和 fresh context 边界 |
| O07 | A | [openai/codex#23902](https://github.com/openai/codex/issues/23902) | local marketplace、版本提升与实际 cache refresh 可能脱节 | 安装来源、manifest、cache generation 需要一体化诊断 |
| O08 | A | [openai/codex#19834](https://github.com/openai/codex/issues/19834) | stale marketplace clone 与 stale plugin cache 容易混淆 | 需要显示 source/version/provenance，而不是只报 reload 成功 |
| O09 | B | [openai/codex#26934](https://github.com/openai/codex/issues/26934) | 已合并 stale cache 清理，重点是 curated plugin 被移除后的缓存清理 | 不证明运行中旧目录可以安全强删 |
| O10 | B | [Codex MCP 文档](https://developers.openai.com/codex/mcp) | Codex Desktop、CLI、IDE extension 共享 MCP host 配置 | 官方页面正文在本环境 HTTP 403，结论按辅助证据使用 |
| O11 | B | [Codex Plugins 文档](https://developers.openai.com/codex/plugins) | 插件可包含 Skill 与 MCP-backed app；安装插件影响新对话可用能力 | 不据此推导当前对话的强制热替换能力 |
| O12 | B | [Codex App Server 文档](https://developers.openai.com/codex/app-server) | app-server 是客户端与 Codex runtime 的接口 | 正文访问受 HTTP 403，需以实现/现场验证为主 |

## 三、PowerShell 官方证据

| ID | 等级 | URL | 调查结果 | 对本项目的含义 |
|---|---|---|---|---|
| P01 | A | [about_Error_Handling](https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.core/about/about_error_handling?view=powershell-7.6) | native 程序主要通过 `$LASTEXITCODE` 报告失败；默认非零退出码不会自动成为 ErrorRecord；PowerShell 7.3 引入、7.4 稳定化 `$PSNativeCommandUseErrorActionPreference` | 必须显式保存并检查 exit code，不能用 stderr 代替 |
| P02 | A | [about_Preference_Variables](https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.core/about/about_preference_variables?view=powershell-7.6) | native 程序可以正常向 stderr 写附加信息；`$ErrorActionPreference=Stop` 会升级可处理的错误 | 普通诊断信息不能直接作为失败条件 |
| P03 | A | [about_Redirection](https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.core/about/about_redirection?view=powershell-7.6) | `2>&1` 把 Error stream 重定向到 Success stream | 当前脚本的输出合流会改变错误信息的处理语义 |
| P04 | B | [PowerShell PR #18695](https://github.com/PowerShell/PowerShell/pull/18695) | native error preference 开启时，`$ErrorActionPreference=Stop` 可使 native 非零退出打断脚本 | 说明全局 preference 组合具有版本敏感性 |
| P05 | B | [PowerShell issue #18368](https://github.com/PowerShell/PowerShell/issues/18368) | native stderr、重定向和错误处理的组合存在行为差异 | 需要回归矩阵覆盖 Windows PowerShell 5.1 与 PowerShell 7 |
| P06 | B | [PowerShell issue #27543](https://github.com/PowerShell/PowerShell/issues/27543) | native stderr/redirect/error preference 行为存在讨论和版本差异 | 不应依赖单一版本的隐式行为 |

## 四、解决方案证据与判断

| ID | 等级 | 判断 | 依据 | 仍需验证 |
|---|---|---|---|---|
| D01 | C | 问题一不能靠强删旧 cache 解决 | L04、L07、O05、O06；运行中的 conversation 仍持有旧路径，删除会制造缺文件风险 | 后续可在用户批准后做句柄归属探针，但不改变该生命周期结论 |
| D02 | C | 开发期应使用 dev/stable 分离、immutable generation、active pointer、延迟回收 | L03-L07、O01-O09；平台缺少跨目录事务和强制上下文替换契约 | 需要结合 Codex Praetor 安装器和 plugin marketplace 实际入口设计 |
| D03 | C | 不必每次改文件新建 task | O01-O03、L05-L06；fresh context 只在工具合同/Skill/manifest 变化时作为批次验收门 | 需要把变更分类规则落进项目文档和发布 receipt |
| D04 | A | 问题二是可修复的包装器 bug | L08-L11、P01-P03；provider 直接 canary 成功，包装器先处理合流 stderr | 实施后需运行完整矩阵 |
| D05 | C | 首选 stdout/stderr 分离捕获 + exit-code-first | P01-P03，兼容 5.1 且保留诊断 | 需验证异步读取/进程退出顺序，避免 stdout/stderr 管道死锁 |
| D06 | C | 不推荐吞 stderr 或只关 native preference | P01-P06；两者都会损失诊断或依赖版本差异，不能替代退出码 | 需在 5.1、7.x 两种 shell 下锁定行为 |

## 五、研究路线与质量记录

- 感知层：KnowledgeRadar 原生 MCP。
- 已调用：`health_check(mode="summary")`、`get_capabilities(summary=true)`、`kr_research(mode="deep_route", budget="deep")`、`kr_web_search`、`extract_web_page`、`search_github_repositories`、`get_task_status(compact=true)`、`analyze_decision_logs(compact=true)`。
- KnowledgeRadar health：`ok`；工具面 17 个。
- 最近任务：34 completed、1 failed、1 cancelled；无 active/stale。
- 最近 20 条决策日志：20 success、0 failure。
- 当日 Tavily 额度耗尽，KnowledgeRadar 已记录降级，web 主要由 `anysearch` 提供；本登记没有把内置 web 当成绕过 KnowledgeRadar 的平行研究路线。
- 文档正文访问缺口：Codex 官方页面和部分 Microsoft Learn 页面在当前环境出现 HTTP 403/静态抽取不完整；相关条目已降为 B 级或明确标注，不伪装成正文核验。

## 六、未执行事项

本轮明确没有执行：

- 修改 `scripts/`、`mcp/`、`plugin/`、`skill/` 或安装器；
- 删除 `C:\Users\ga990\.codex\plugins\cache` 下任何目录；
- 重启 Codex Desktop、app-server 或 provider；
- 更新 stable Skill、plugin、marketplace 或 readiness state；
- 提交、推送、创建或更新 PR。

后续实现前提：用户明确批准代码修复，并重新核对当前 Codex、PowerShell、provider CLI 版本和公开 issue 状态。
