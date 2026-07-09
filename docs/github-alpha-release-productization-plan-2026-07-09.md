# Codex Praetor GitHub Alpha 发布产品化路线图

日期：2026-07-09  
项目：`D:\Projects\CodexPraetor`  
目标版本：`0.1.0-alpha`

## 一句话结论

Codex Praetor 已经不是只有想法的阶段。它现在有可运行的 skill、Windows 派工脚本、项目本地 job/plan/lock 目录规则、薄 MCP v0、插件包雏形、C 盘安装版 skill，以及本机个人插件验证路径。

但它还不能直接发布到 GitHub。2026-07-10 更新：首个提交、最小验证、MiMo readonly canary、MIT 许可证和基础发布文件已经补上；当前最大差距已经转为 README 安装体验、provider 缺失/登录 UX、最终 GitHub URL、原生 MCP fresh-context 验证和发布包收口。

正确路径是：继续收紧公开发布包和隐私边界，补 provider UX 和安装说明，刷新插件/MCP 验证，再做 GitHub alpha 发布。

## 当前已经做到什么

已经完成的能力：

- `skill/codex-praetor` 是 D 盘开发源 skill。
- `%USERPROFILE%\.codex\skills\codex-praetor` 是本机安装版 skill，并且是实目录，不是链接。
- `scripts/invoke-codex-praetor.ps1` 可以生成 Qoder、CodeBuddy、MiMo 的外部 worker 调用。
- `scripts/watch-codex-praetor-job.ps1` 可以做后台进程等待、completion 写入和锁释放。
- `mcp/` 已实现薄 MCP v0，并通过 `npm test`。
- `plugin/mcp/dist/server.js` 已可打包为插件内 MCP runtime。
- MCP 当前工具面覆盖 route-intent、dry-run、plan、status、list-jobs、lane/conflict 等核心读状态和计划能力。
- 全局规则已经把“拆分任务、分配给其他 agent、交给其他 agent”解释为 Codex Praetor 外部 worker，而不是 Codex 原生 subagent。
- 本轮自检 `scripts/test-codex-praetor.ps1` 通过，结果为 0 warnings、0 failures。

本轮新增修复：

- 修复了真实 MiMo canary 在空仓库上失败时只显示 `fatal: invalid reference: master` 的问题。
- 现在脚本会先检查 `HEAD` 是否存在；如果仓库还没有任何提交，会明确提示必须先创建干净初始提交。
- 这个修复已同步到三处：根脚本、源 skill 脚本、插件 skill 脚本。
- 已通过显式发布脚本把 D 盘源 skill 替换到 C 盘安装版；不是软链接，也不是自动同步。

## 当前真实阻塞

### 1. 首个提交和真实 worker 基线已经补上

2026-07-10 更新：仓库已经有干净提交，真实 MiMo readonly canary 已经能在独立 worktree 中运行。

这个问题已经从阻塞项变成回归检查项：真实 worker dispatch 仍必须依赖 git worktree，MiMo 即使 readonly 也要在独立 worktree 中运行，避免 `.mimocode` 污染主仓库。

人话说：真实 worker 链路已经跑通一小步；下一步不是证明能不能跑，而是把失败诊断、安装说明和 native MCP 验证做成普通用户能跟着走的流程。

### 2. 发布包里还有本机信息风险

当前这些内容不能原样公开：

- `config/codex-praetor-tiers.example.json` 里有本机路径，例如 Qoder、WorkBuddy、MiMo 的安装位置。
- `docs/evidence-register.md` 和部分 provider reference 里有本机额度、账号、缓存路径、截图证据或个人观察。
- `handoff/` 是项目迁移历史，对公开用户不一定有价值，也可能暴露本机路径和内部过程。
- 插件 manifest 已改为 MIT，但 repository/homepage 仍需要在创建 GitHub remote 后替换为真实仓库 URL。

GitHub alpha 前必须把公开材料和内部证据分开。公开仓库只保留模板、说明、公开证据链接和脱敏后的能力矩阵；本机账号、额度、缓存路径和截图证据留在 private/internal 或不发布。

### 3. 外部 Agent 不是 Codex Praetor 自带的

Codex Praetor 的原理不是内置三个模型，而是调用用户本机已经安装并登录好的官方 CLI：

- Qoder / QoderWork CN CLI。
- Tencent CodeBuddy / WorkBuddy CLI。
- Xiaomi MiMo Code CLI。

如果别人的电脑上没有这些东西，Codex Praetor 不能凭空派工。产品必须把它们定义为可选 provider，并提供 doctor：

- 没装：显示 provider disabled，并告诉用户安装入口。
- 装了但没登录：显示 auth required，并告诉用户先手动登录。
- 装了但命令参数不兼容：显示 capability mismatch，并给出当前 wrapper 期待的参数。
- 全都没有：仍可用 route-intent、plan、dry-run、list-jobs 等本地能力，但不能真实派工。

这不是失败，而是产品边界。Codex Praetor 是调度器，不是 Qoder/CodeBuddy/MiMo 的安装器、账号系统或代理登录工具。

## 外部 Agent 安装和缺失策略

### Qoder

公开说明应写清楚：用户需要安装 Qoder CLI 或 QoderWork CN 对应 CLI；需要按 Qoder 官方流程登录；Codex Praetor 只读取配置中的 CLI 路径并调用官方 CLI；默认只允许白名单模型，例如 `Qwen3.7-Plus` 和 `Qwen3.7-Max`；额度、折扣、每日签到、过期时间都属于 Qoder 平台规则，Codex Praetor 只能提醒用户自行确认。

doctor 检查：CLI 路径存在、`--version` 可执行、模型白名单可用、当前目录是 Git repo、真实派工前 HEAD 存在。

### CodeBuddy

公开说明应写清楚：用户需要安装 CodeBuddy / WorkBuddy CLI；Windows 上可能通过 Node 调用本地产品解包出的 CLI，也可能未来通过用户安装的标准命令；用户需要登录或配置 CodeBuddy 官方支持的认证方式；默认不能使用 `auto` 模型，避免 provider 自己切到未知模型；`hy3`、`deepseek-v4-flash`、`deepseek-v4-pro` 是当前策略里的固定白名单，是否免费或便宜必须由用户自己的账号界面确认。

doctor 检查：Node 可用、CLI 文件存在、认证环境可用、只读工具白名单是否被当前 CLI 接受。此前真实尝试暴露过 `Tool Bash not found in agent cli`，所以工具能力 probe 是必须项。

### MiMo

公开说明应写清楚：用户需要安装 MiMo Code CLI，例如 npm 包或官方安装脚本；首次启动可能需要完成配置；当前默认模型是 `mimo/mimo-auto`，但免费状态不能写死承诺，只能写“本机曾验证为 0 成本，用户需自行确认”；MiMo plan 模式也可能写 `.mimocode`，所以 Codex Praetor 即使 readonly 也会在 git worktree 里跑它。

doctor 检查：`mimo` 命令存在、版本可读、`mimo run --help` 参数存在、仓库有 HEAD、worktree 可创建、输出 JSON/event summary 可解析。

## MCP 应该在哪一步

MCP 不是最后才做，也不是一开始就接管所有逻辑。现在最正确的位置是：

1. 已完成：薄 MCP v0，用于 route-intent、dry-run、plan、status、list-jobs、lane/conflict 可见性。
2. 下一步：把 MCP 用作产品化可见工具面和 doctor 入口，而不是马上让 MCP 直接真实派工。
3. 真实 dispatch 仍先由 PowerShell wrapper 负责，因为它已经处理了路径、worktree、锁、watcher、UTF-8 和 provider 参数。
4. 等首个真实 worker canary 稳定后，再通过 MCP 加 `codex_praetor_dispatch` 和 `codex_praetor_collect`。

人话说：MCP 现在是仪表盘和按钮面板，脚本是发动机。不要现在把发动机拆了重装。

## 多对话并发目标

最终目标不是做大而全的多 Agent 平台，而是在 Codex 的多个对话、多个项目里安全使用 5 个以内外部 worker。

推荐原则：

- 允许多个项目同时有 worker。
- 同一项目默认只允许一个 edit worker。
- readonly worker 可以并行，但如果 provider 会写计划文件，也要在独立 worktree。
- 不做中心化排队系统；做冲突检测、状态可见和明确拒绝。
- Codex 永远负责最终合并和验收。

当前已经有项目本地 job/plan/lock 和 lane/conflict 读取。下一阶段需要补 file-scope metadata：真实派工时记录本次 worker 允许读写哪些路径，这样 conflict detection 可以从 repo 级别细化到路径级别。

## 发布前分阶段路线

### 阶段 A：发布边界和隐私清理

目标：确保没有个人数据会进 GitHub。

要做：

- 把 `config/codex-praetor-tiers.example.json` 改成模板，不含本机路径。
- 新增本地配置文件约定，例如 `config/codex-praetor.local.json`，加入 `.gitignore`。
- 把本机证据、账号、额度、截图、缓存路径移到 internal/private，或在公开仓库中删除。
- 检查 `.gitignore` 覆盖 `*.local.json`、auth/token/key、runtime job、worktree、缓存、截图、日志。
- 许可证已初步选 MIT；发布前还要确认仓库 owner 和最终 GitHub URL。

完成标准：全文搜索本机路径、账号、token/key、截图路径，无公开泄漏；插件 manifest 使用真实 GitHub URL。

### 阶段 B：首个干净提交

目标：让真实 worker 能创建 worktree。

要做：

- 先完成隐私清理。
- 跑 `scripts/test-codex-praetor.ps1`。
- 人工审查将要提交的文件。
- 创建首个 commit。

完成标准：`git rev-parse --verify HEAD` 成功，`git worktree add` 有可用基线。

### 阶段 C：真实 worker canary

目标：证明 Codex Praetor 真能把任务放进外部 worker 链路。

顺序：

1. MiMo readonly canary：只读审计一个小范围文件，不修改主仓库。
2. 读取 stdout/stderr/completion，确认 job 状态、成本字段、parser 字段、summary 字段。
3. 验证主仓库不被 `.mimocode` 污染。
4. 再考虑 CodeBuddy readonly canary，重点测工具白名单兼容。
5. 最后考虑 Qoder readonly canary，重点测 Git repo 和登录状态。

完成标准：至少一个真实外部 worker 成功返回可验收摘要，失败时有清楚原因和下一步。

### 阶段 D：doctor 和安装体验

目标：用户拿到仓库后知道自己缺什么。

要做：

- 新增 `scripts/doctor-codex-praetor.ps1`。
- 检查 Windows、PowerShell、Git、Node、npm、MCP build、Codex config、plugin manifest。
- 检查 Qoder/CodeBuddy/MiMo 三个 provider 的 installed/auth/capability 状态。
- 输出短表格：ready / missing / login_required / incompatible / skipped。
- 不自动安装、不自动登录、不改 provider 内部数据库。

完成标准：没有任一 provider 时，doctor 能说清楚还能用什么、不能用什么、下一步怎么装。

### 阶段 E：README 和用户文档

目标：站在真实用户视角写清楚安装和使用。

README 必须包含：

- 产品定位：给 Codex 用的外部 worker 调度器。
- 支持范围：Windows first，Codex first，中国用户友好，但命令/配置保留英文标识。
- 安装前提：Codex、Node、Git、PowerShell。
- 可选 provider：Qoder、CodeBuddy、MiMo，分别怎么安装、怎么登录、怎么验证。
- 配置：本地 config 模板如何复制成 local config。
- 第一次运行：doctor -> dry-run -> readonly canary。
- 隐私边界：不会发布账号、token、缓存；不会托管你的 provider 凭据。
- 故障排查：MCP 看不到、provider 缺失、worktree 失败、没有首 commit、工具参数不兼容。

### 阶段 F：MCP 和插件稳定性

目标：让 Codex 能稳定抓到工具面。

要做：

- 保留 direct MCP registration 作为开发 canary。
- 插件安装路径使用相对 `cwd = "."` 的打包 MCP。
- doctor 检查 MCP server 能启动、能 list tools、工具数符合预期、关键工具调用成功。
- 说明当前对话热加载限制：新装插件/MCP 不一定在已打开线程里出现，需要新鲜工具上下文做最终 canary。
- fallback 只能用于诊断，例如 SDK/protocol smoke；不能把 fallback 当正式产品路径。

完成标准：新鲜 Codex 上下文能看到 Codex Praetor 插件，route-intent 和 dry-run 能以原生 MCP 工具调用出现。

### 阶段 G：GitHub alpha 发布

目标：发一个诚实的 `0.1.0-alpha`。

要做：

- README、LICENSE、CHANGELOG、SECURITY 或安全说明、CONTRIBUTING 可先轻量。
- 插件 manifest 改成真实 repo URL、真实 license、真实项目主页或文档 URL。
- GitHub secret scanning / push protection 打开。
- GitHub Release 写清楚：alpha、Windows first、Codex-only、三个 provider 都是用户自备。
- Release assets 可以先不复杂，优先源码 + 插件包目录说明。

完成标准：一个新用户按 README 能跑 doctor、能完成至少 dry-run；有对应 provider 的用户能跑 readonly canary。

## 立即下一步

下一步不是继续真实 MiMo 派工。因为当前仓库没有首 commit，真实 worker 没有可检出的项目快照。

下一步应该按这个顺序：

1. 脱敏公开包：清理 config 示例、证据文件、handoff/private 内容。
2. 增加 local config 模板和 `.gitignore` 规则。
3. 补 doctor 脚本。
4. 跑完整自检。
5. 做首个干净 commit。
6. 再跑 MiMo readonly canary。
7. 根据 canary 结果扩 MCP dispatch/collect 或补 provider 兼容。

现在最重要的判断是：Codex Praetor 的核心方向没错，MCP 也已经放在正确位置；真正差的是公开发布工程、隐私隔离、安装体验和首个真实 worker 基线。
