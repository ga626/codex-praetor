# Codex Praetor 产品化执行图

日期：2026-07-10
目标版本：`0.1.0-alpha`
项目目录：Codex Praetor local productization workspace

## 人话结论

Codex Praetor 已经过了“能不能做”的阶段。现在已经有可运行的 skill、Windows 派工脚本、薄 MCP v0、插件包雏形、Git hooks、最小验证、协议 smoke，以及一次真实 MiMo 只读 worker 链路。

还没到 GitHub 发布阶段。真正剩下的是产品化收口：公开包脱敏、用户安装说明、provider 缺失/登录/能力诊断、GitHub CLI 安全授权、MCP 原生工具面最终验收、真实 GitHub URL、以及发布前冻结。

新开一个 Codex 对话不是下一步。它只属于最后的 fresh-context native MCP 验收，用来证明一个新用户/新线程能看到并调用 Codex Praetor MCP 工具。开发过程继续在当前项目和当前路线图里推进。

## 已完成到什么程度

| 模块 | 当前状态 | 说明 |
| --- | --- | --- |
| 项目迁移 | 已完成 | 当前源项目已固定为本地 productization workspace，不再迁移目录。 |
| Git 基线 | 已完成 | 仓库已有多次提交，真实 worker 可以基于 HEAD 创建 worktree。 |
| Skill | 已完成首版 | D 盘是开发源，C 盘安装版是实目录复制，不是链接。 |
| 脚本派工 | 已完成首版 | `invoke`、`watch`、`plan`、`notify` 脚本存在，并处理 worktree、job、completion、lock。 |
| MCP v0 | 已完成首版 | 已有 route-intent、dry-run、plan、status、list-jobs、lane/conflict 工具。 |
| Plugin 包 | 已完成本机雏形 | personal plugin/cache 发布过，包内 MCP runtime 使用 `node` 和相对 cwd。 |
| 最小验证 | 已完成首版 | doctor、test、MCP/package smoke、public marker scan 已跑通过。 |
| 真实 worker canary | 三条 provider gate 已完成 | MiMo、CodeBuddy、Qoder readonly 均跑通过；主仓库未被污染。 |
| 多对话状态 | 已有 v0 | 项目本地 jobs/plans/locks/lane/conflict 可读；file-scope metadata 还没补。 |

## 当前没有完成的事

| 缺口 | 为什么重要 | 放在哪一阶段 |
| --- | --- | --- |
| Provider 用户文档 | 已有公开首版，还需要随 doctor UX 和 canary 结果继续补。 | Phase 3 |
| Doctor 用户体验还不够完整 | 现在能区分 CLI、version、auth unknown，但还要更清楚地输出安装/登录/能力问题。 | Phase 3 |
| 公开发布包脱敏还要复查 | 不能把账号、token、usage 截图、provider cache、本机路径和 handoff/internal 历史发出去。 | Phase 2 |
| Plugin metadata 仍是占位 URL | 已完成：metadata 已替换为 `https://github.com/ga626/codex-praetor`。 | Phase 6 |
| GitHub 安全授权未完成 | 已完成本机安全路径：使用 GitHub CLI keyring 登录态；没有把聊天中的 PAT 写入命令、配置或仓库。 | Phase 6 |
| 当前线程 MCP transport 已陈旧 | 本线程的 `Transport closed` 不能当产品失败，也不能当最终通过。 | Phase 7 |
| 原生 fresh-context MCP 验收未做 | 必须在最终阶段用新工具上下文验证真实 Codex 能看见并调用工具。 | Phase 8 |
| Provider canary 结果需持续回归 | MiMo、CodeBuddy、Qoder 已跑通过；后续发布前仍要作为回归检查。 | Phase 5 |
| GitHub 发布动作未做 | 仓库和 `main` 已公开；tag/release 因 fresh-context MCP canary 未完成而暂停。 | Phase 9 |
| Release 包本地构建 | 草稿包已可构建；公开发布前必须替换最终 URL，并在不带 `-AllowDraftMetadataPlaceholders` 的情况下重跑。 | Phase 6 |

## 正确执行顺序

### Phase 0：冻结方向，停止重复迁移

状态：已完成。

标准：

- 继续使用当前本地 productization workspace。
- 不再从旧调研目录重新搬文件。
- `handoff/` 只作为内部历史，不进入发布包。

### Phase 1：保住开发基线

状态：已完成，后续只做回归检查。

标准：

- `doctor -RequireHead -PublicRelease -AllowDraftMetadataPlaceholders` 草稿门禁通过；不带该开关的最终门禁会因占位 URL 正确失败。
- `scripts/test-codex-praetor.ps1` 通过。
- Git hooks 明确是 `.githooks` 下的 Git hooks，不是 Codex app 设置页里的后台钩子。
- C 盘 installed skill 是实目录，不是 symlink/junction/path pointer。

### Phase 2：发布包边界和隐私清理

状态：进行中。

要做：

- 复查公开路径：`README.md`、`docs/`、`config/`、`scripts/`、`skill/`、`plugin/`、`examples/`。
- 保持 `handoff/`、`docs/internal/`、`mcp/node_modules/`、`mcp/dist/`、runtime job、worktree、local config 在发布包外。
- 搜索并阻断个人路径、账号、auth、token、provider cache、usage 截图、机器特定配置。
- 确认 `config/codex-praetor-tiers.example.json` 只有模板路径，例如 `C:\Path\To\...`，真实路径只放 ignored local config。

完成标准：

- public marker scan 通过。
- `git status --short --ignored` 只显示预期 ignored 目录。
- 发布包说明清楚哪些文件属于用户安装，哪些只属于开发验证。

### Phase 3：用户安装和 Provider UX

状态：进行中。公开 provider 文档已经有首版，doctor UX 仍需继续收紧。

要做：

- 新增或整理公开 provider 文档，至少覆盖 Qoder、CodeBuddy、MiMo 三页。首版位置：`docs/provider-notes/`。
- 写清楚三者都是用户自备 CLI，Codex Praetor 不安装、不登录、不读取账号数据库。
- 写清楚没有任何 provider 时仍可使用 route-intent、plan、dry-run、status，但不能真实派工。
- Doctor 输出继续收紧为用户能懂的状态：missing、ready、auth unknown、capability info/mismatch、next action。
- README 增加从零路径：clone -> local config -> doctor -> dry-run -> optional readonly canary。

完成标准：

- 一个没有 Qoder/CodeBuddy/MiMo 的 Windows 用户也能看懂为什么真实 dispatch 被禁用。
- 一个已经安装 provider 的用户知道下一步去哪里登录、怎么验证 CLI、怎么跑 readonly canary。

### Phase 4：MCP 作为产品工具面，不急着替代脚本

状态：v0 已完成，仍需产品化收口。

原则：

- 脚本仍是发动机，MCP 是仪表盘和按钮面板。
- v0 工具保持 read-only / dry-run / plan / status / lane/conflict。
- 不在这个阶段重写调度器。
- 当前线程 `Transport closed` 只记录为 reload/cache 边界。

完成标准：

- packaged runtime protocol smoke 继续通过。
- 工具 schema 和安全注解稳定。
- fallback SDK/protocol smoke 只用于诊断，不冒充 Codex 原生工具卡验收。

### Phase 5：真实 worker 链路扩展

状态：MiMo readonly、CodeBuddy readonly、Qoder readonly 均已完成。

要做：

- 保留 MiMo readonly 作为回归 canary。
- 保留 CodeBuddy readonly canary，重点验证工具白名单和非交互参数。2026-07-10 已通过 `CP_CODEBUDDY_PROVIDER_DOCS_CANARY`。
- 保留 Qoder readonly canary，重点验证 Git/worktree、登录状态和模型白名单。2026-07-10 已通过 `CP_QODER_PROVIDER_DOCS_CANARY`。
- 记录每次 canary 的 completion、stderr 摘要、主仓库干净状态、失败 next action。

完成标准：

- 三条真实 worker 链路均有通过记录。
- 如果后续 provider 因为未登录/未安装失败，也能给出用户可执行的下一步。
- 不把 provider 失败等同于 Codex Praetor 核心失败。

### Phase 6：GitHub 公开仓库准备

状态：已完成到仓库创建和首次 push；tag/release 等待 Phase 8 canary。

要做：

- 不把已经暴露的 GitHub Personal Access Token 粘进 Codex 命令、脚本、文档或仓库。
- 安装并验证 GitHub CLI：`gh --version`、`gh auth login`、`gh auth status`。本机已通过 keyring 登录态完成。
- 把 GitHub 发布路径固定到 `docs/github-publish-runbook.md`：用户只做账号授权和 owner/repo 确认，Codex 负责后续命令。
- 设置真实 GitHub remote：`https://github.com/ga626/codex-praetor.git`。
- 替换 plugin metadata 中的 draft GitHub repository URL。
- 确认 README、LICENSE、CHANGELOG、SECURITY、CONTRIBUTING、examples 是公开可读的。
- 按 GitHub 官方建议使用 README 解释项目用途和使用方法；按 GitHub release 模型用 tag/release 发布可下载版本。
- 启用或至少文档化 secret scanning / push protection 预期，防止 hardcoded credentials 进入公开仓库。
- 使用 `scripts/build-codex-praetor-release.ps1 -Apply -AllowDraftMetadataPlaceholders` 生成草稿 release zip，并确认不含 internal/handoff/local/provider 私有材料。最终公开包必须去掉该开关并使用真实 URL。

完成标准：

- `gh auth status` 在本机通过，或者明确记录为发布阻塞。
- remote、homepage、repository URL 一致。
- public marker scan 在 URL 替换后重新通过。
- 用户确认可以进行第一次公开 push。

### Phase 7：插件/MCP 本机重新加载验收准备

状态：未完成。

要做：

- republish personal plugin/cache。
- 记录版本号。
- 确认 packaged MCP runtime 能启动并 list/call 关键工具。
- 不在当前陈旧线程里反复证明 native MCP，因为这个线程可能保持旧 transport。

完成标准：

- 本机包可被 Codex 插件系统发现。
- protocol smoke 通过。
- 具备进入 fresh-context native MCP canary 的条件。

### Phase 8：最终新对话验收

状态：阻塞。当前线程 MCP transport 陈旧，WindowsApps `codex.exe` 无法执行，当前工具面没有创建新 Codex 线程的工具。

这个阶段才开新 Codex 对话。目标不是开发，而是模拟新鲜用户上下文。

验收提示词应覆盖：

- 能否发现 Codex Praetor plugin/skill。
- 能否原生调用 `codex_praetor_route_intent`。
- 能否原生调用 `codex_praetor_dispatch_dry_run`。
- 能否原生调用 `codex_praetor_list_lanes` 和 `codex_praetor_detect_conflicts`。
- 自然语言“拆分任务给其他 agent”是否走 Codex Praetor 外部 worker 路线，而不是 Codex subagent。
- 不做真实 worker dispatch，除非已经进入 provider canary 子关。

完成标准：

- 新线程里能看到原生 MCP 工具卡。
- route-intent / dry-run / lane/conflict 均成功。
- 没有创建 Codex native subagent。

### Phase 9：`0.1.0-alpha` 发布

状态：未开始，需要用户确认。

要做：

- 创建 tag。
- 创建 GitHub release。
- release notes 明确：alpha、Windows first、Codex first、Qoder/CodeBuddy/MiMo 是用户自备可选 provider。
- 发布后从干净 clone 跑一次 README 路径：doctor -> dry-run -> optional readonly canary。

完成标准：

- GitHub 页面可读。
- release 可下载。
- 新用户路径不依赖本机私有目录。

## 下一步到底做什么

下一步不是开新对话，也不是继续刷新 MiMo canary。

Phase 3 和 provider canary 首轮已经完成。下一步进入 GitHub URL/发布包准备，同时维持 Phase 2 的发布包边界检查。

具体顺序：

1. 整理 Qoder、CodeBuddy、MiMo 的公开安装/登录/验证说明。
2. 把 README 的 Setup 和 Troubleshooting 改成新用户路径。
3. 让 doctor 的 provider 输出更像产品诊断，而不是开发日志。
4. 把 GitHub CLI 安全授权和发布命令写入正式 runbook，避免再使用暴露 PAT。
5. 跑草稿门禁 `doctor -RequireHead -PublicRelease -AllowDraftMetadataPlaceholders`、最终阻断门禁 `doctor -RequireHead -PublicRelease`、`test-codex-praetor.ps1`、`git diff --check`。
6. Provider canary 已完成；下一步进入 GitHub URL/发布包准备，遇到公开发布动作前停下等用户确认。

## 外部依据记录

本路线使用 KnowledgeRadar 做了路线准入：`health_check(mode="summary")`、`get_capabilities(summary=true)`、`kr_research(mode="deep_route")`。内置 web/search 只作为 KnowledgeRadar 授权的 `host_internal_web_wave` 使用。

参考官方资料：

- GitHub README 文档：README 应说明项目有什么用、用户能做什么、怎么使用。
  https://docs.github.com/en/repositories/managing-your-repositorys-settings-and-features/customizing-your-repository/about-readmes
- GitHub push protection 文档：发布前应防止 token、secret、credential 被推送到仓库。
  https://docs.github.com/en/code-security/concepts/secret-security/push-protection
- GitHub releases 文档：release 是基于 Git tag 的可下载软件迭代。
  https://docs.github.com/en/repositories/releasing-projects-on-github/about-releases
- OpenAI Codex plugins 文档：plugin 可打包 skills，也可附带 MCP server configuration 和展示资产。
  https://developers.openai.com/codex/plugins
- OpenAI Codex MCP 文档：Codex 支持 MCP server；plugin-bundled MCP server 由 plugin manifest 提供，用户配置可控制启用状态和工具策略。
  https://developers.openai.com/codex/mcp
- OpenAI Codex configuration reference：plugin-provided MCP server 可以通过 `plugins.<plugin>.mcp_servers.<server>` 控制 enabled、enabled_tools、disabled_tools 和 approval mode。
  https://developers.openai.com/codex/config-reference
