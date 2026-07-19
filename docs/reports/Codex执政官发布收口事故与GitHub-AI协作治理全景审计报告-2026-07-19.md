# Codex 执政官发布收口事故与 GitHub / AI 协作治理全景审计报告

日期：2026-07-19
范围：`ga626/codex-praetor`、账户 `ga626` 的可读 GitHub 状态、当前 Codex 协作规则、发布事故、公开资料与外部对标。
边界：本报告只记录事实、建议与后续执行计划；除已在本次收口前完成的分支保护和 Actions 写权限外，不修改任何 GitHub 开关、账户资料或全局规则。

## 1. 先给结论

本轮 PR #27 已合并到 `main`，但产品尚未交付。

不是发布权限不足，也不是 tag 已占用。`Release On Main` 在启动步骤就失败：`.github/workflows/release-on-main.yml` 把 `actions/setup-node` 固定到了一个不存在的提交号，最后一位是 `...21`；实际能解析并已被 CI 使用的是 `...20`。因此 runner 连 Node 都没有安装，tag、GitHub Release、zip 和本机 stable 代际都没有被创建。

这次暴露的不是“还缺一条手工发布命令”，而是新流程还缺少一个 **发布工作流启动前验证**：PR CI 验证了业务包，却没有验证“合并后 workflow 所引用的每个 action 固定提交号都能被 GitHub 解析”。

正确处置不能是手工运行发布脚本。那会重新制造“代码合并后靠人补发布”的旧流程。正确路径是一个极小的发布 workflow 修复 PR：修正固定 SHA，并补上可在 PR 阶段检查 release workflow action 依赖的门禁；合并后再由 `Release On Main` 自动发布 `v0.6.0-alpha`。在此之前，状态必须保持为：**代码已合并，产品未交付**。

GitHub 与账户层面已经具备一部分重要基础（`main` 保护、PR、必需 CI、管理员不能绕过、Actions 仅对发布 job 授予写权限、secret scanning 与 push protection），但仍有四类高优先级缺口：账户两步验证、过宽的 CLI token、依赖/漏洞自动治理、代码扫描与 workflow 依赖可解析性。

## 2. 本次发布收口事实

| 项目 | 观察事实 | 判断 |
|---|---|---|
| PR | #27 已在 2026-07-19 06:53:35 UTC 合并 | 代码已合并 |
| main | `6b3cfe30ae6838f6a64a293ad89b50ef6d1bf52c` | 已同步到本地 |
| 发布 workflow | Run `29677178250`，在 `Set up job` 失败 | 产品未交付 |
| 权限 | 日志显示 `GITHUB_TOKEN Permissions: Contents: write` | 不是权限问题 |
| 失败文本 | `Unable to resolve action actions/setup-node@...0021` | 固定 SHA 不存在 |
| tag | 远端没有 `v0.6.0-alpha` | 未产生半成品 tag |
| Release | `gh release view v0.6.0-alpha` 返回未找到 | 未产生半成品 Release |
| stable 本机代际 | 本轮未进入 stage / activate / deliver | 不能声称本机已更新 |

### 2.1 为什么上一次 PR CI 没抓到它

PR CI 中的 `actions/setup-node` 使用的是可用的 `...0020`，而合并后 Release workflow 使用了 `...0021`。现有供应链检查只验证了“看起来像完整 SHA”，没有向 GitHub 验证该 SHA 是 action 仓库中真实存在的对象，也没有要求 CI 与 release workflow 共用同一份 action 固定版本来源。

这也是为什么 PR CI 可以绿、合并后 release workflow 却在第一个 job 失败。

### 2.2 本轮关闭状态

| 状态层 | 当前结论 |
|---|---|
| 本地开发改动 | 已合并，无待提交工作树改动 |
| PR | #27 已合并 |
| GitHub Release | 未创建 |
| 用户可下载包 | 未创建 |
| 本机插件/Skill/stable 代际 | 未更新 |
| 产品已交付 | 否 |

## 3. 当前 GitHub 仓库真实状态

### 3.1 已经配置正确的部分

| 领域 | 当前状态 | 价值 |
|---|---|---|
| 主分支 | `main` 强制 PR、`validate` 必须通过、要求最新基线、管理员也受规则约束 | 阻止直接绕过与未验证合并 |
| 分支安全 | 禁止强推、禁止删除、要求讨论解决 | 保住发布源 |
| Actions 权限 | 默认工作流权限已设为 write；CI job 自己声明 `contents: read`，发布 job 声明 `contents: write` | 具备最小权限结构的雏形 |
| 机密保护 | secret scanning 与 push protection 已启用；当前 secret-scanning open alerts 为 0 | 能阻止一部分误提交密钥 |
| 发布策略 | intent、版本面、release notes、不可变 tag、远端包复验已进入仓库 | 发布不是口头约定 |
| 依赖更新配置 | `.github/dependabot.yml` 已覆盖 GitHub Actions 和 `mcp/` npm | 已有更新入口 |
| 公共仓库基本资料 | README、LICENSE、SECURITY、CONTRIBUTING、PR 模板、issue form 文件都存在 | 社区健康度 API 为 85% |

### 3.2 已确认的缺口与建议

| 优先级 | 事实 | 风险 | 建议 | 是否应立即改 |
|---|---|---|---|---|
| P0 | 账户 API 显示 `two_factor_authentication: false` | 账户接管即获得所有仓库和发布权限 | 在 GitHub 账户安全页面启用 passkey/验证器 2FA，保存恢复码 | 是，但只能由账户本人完成 |
| P0 | 当前 gh CLI token 具有 `delete_repo`、多个 admin scope、`workflow` 等宽泛权限，且将于 2026-07-27 到期 | 本机 token 泄漏的破坏面远超本项目所需 | 2FA 后撤销或退出该 token，改用短期/细粒度 token 或 device login；仅授予实际仓库与 workflow 所需权限 | 是，人工账户动作 |
| P0 | `Release On Main` 固定 action SHA 写错；没有 PR 级解析验证 | 合并后才发现发布不能启动 | 修复 SHA；增加 release workflow dependency preflight；CI/release 共用 action pin 清单或静态一致性检查 | 是，作为发布事故修复 PR |
| P1 | Dependabot alerts disabled，automated security fixes disabled，vulnerability alerts disabled | 已知依赖漏洞不会形成告警或自动修复 PR | 先启用 dependency graph / Dependabot alerts，再启用 security updates；保留人工审阅自动 PR | 是，先做设置审查后启用 |
| P1 | Code scanning default setup 为 `not-configured`，覆盖语言含 Actions、JavaScript/TypeScript | 脚本与 workflow 的静态安全问题没有平台扫描 | 启用 CodeQL default setup；初期只报告，不立刻设为 required check | 是 |
| P1 | Actions policy 为 `allowed_actions: all`，repo 没有强制 SHA 固定 | 第三方 action 面太宽，且错误 SHA 仅靠人工发现 | 先清点所需 action，再改为 GitHub-owned + verified 或显式 allowlist；评估强制 SHA 固定是否适配当前计划 | 是，分阶段 |
| P1 | 未使用 artifact attestation / provenance | 用户无法以 GitHub 原生证明 zip 来自哪个 workflow/commit | 对公开 zip 加 attestation；发布 workflow 增加 `attestations: write`、`id-token: write`，并在交付验收下载验证 | 是，下一次发布治理 PR |
| P2 | `delete_branch_on_merge: false` | 已合并分支积累，容易误用旧分支 | 打开自动删除分支；保留受保护 `main` 与 active release tag | 建议 |
| P2 | 三种 merge 方式均允许，squash 标题不作为默认 | 版本化项目的历史语义不稳定 | 选定一种主策略：小团队建议 squash merge；发布提交由 PR 标题产生可读历史 | 建议，需你选择 |
| P2 | 未要求签名提交，未要求线性历史 | 可追溯性仍可加强，但会增加个人维护摩擦 | 先配置 SSH/GPG 签名并观察，再决定是否把签名/线性历史设成硬门禁 | 暂不强制 |
| P2 | API 显示 issue template 为 null，但仓库实际有 issue form | 平台社区健康检查与真实入口可能不一致 | 在网页上做一次普通用户 issue 创建演练，确认 form 可见、模板分类清晰 | 建议验证 |

### 3.3 不建议现在启用的项目

- 不要给 release environment 加人工审批。你的明确产品语义是“PR 合并就发布”；审批会重新引入合并后的人工尾巴。
- 不要为了看起来专业而盲开 merge queue。单人维护、低并发仓库当前没有收益，反而增加理解成本。
- 不要把 `contents: write` 给 CI。保留 CI read-only，只有发布 job 有 write 是正确分层。
- 不要把对外 provider、账户、浏览器资料接到 GitHub Secrets 或仓库配置。它们不属于公开产品 release 的必需依赖。

## 4. GitHub 账户与公开专业形象

### 4.1 当前事实

- 账号：`ga626`；公开仓库 6 个；无公开 profile README 仓库；没有 pinned repositories；没有公开 social accounts。
- 当前 bio：`量化交易系统开发者 | 金融科技创新 | 让投资更智能`。
- 当前公开代表作已包括 `codex-praetor`、`codex-provider-switcher`、个人站点和若干历史项目。
- 账户 company 为 `@QuantumTrading`，与当前公开的 Codex / Windows developer tools 方向不一致。

这不是“简介写得不好”，而是公开信号互相矛盾：访客先看到金融量化身份，再看到 AI developer tooling 项目，却没有 README 或置顶仓库解释两者关系。

### 4.2 建议的公开定位

建议把账号定位写成“独立开发者，主线是 Windows-first AI developer tools；量化/金融科技为第二兴趣或历史领域”，而不是同时把两条线都写成唯一主业。

建议 bio 草案（不在本轮直接修改）：

```text
Independent developer building Windows-first AI developer tools and local-first workflows.
Codex · MCP · PowerShell · Developer Experience
```

如果你希望保留金融科技身份，可改为：

```text
Independent developer — AI developer tools, local-first automation, and fintech systems.
Codex · MCP · PowerShell · Windows
```

建议创建 `ga626/ga626` profile README，并使用四块简短内容：

1. 你解决什么问题：Windows 上的 Codex、MCP、provider 与可验证发布。
2. 精选项目：Codex Praetor、CodeX Provider Switcher、个人站点，第四个位置由你在量化项目和其他开发工具间选择。
3. 工作方式：local-first、release evidence、可复验自动化。
4. 联系方式：只放你愿意永久公开的个人站点或公开邮箱；不要放个人手机号、常用聊天账号、真实地址或 token 线索。

随后固定置顶 3–4 个项目，并把每个项目的 About、topics、Release、README 首屏与 profile 叙事对齐。`codex-praetor` 现有 topics 已经较好；其余旧项目应补 description/topics，或降低可见度/归档，避免访客把空描述仓库当成当前代表作。

## 5. AI 协作与项目运行流程审计

### 5.1 已经正确的设计

- 用 `AGENTS.md` 写持久项目约束，而不是每次在聊天中重新解释。
- 用 Skill 包装可复用流程，Plugin 作为分发单元，MCP 处理运行时工具接入；这与 Codex 官方“guidance / skills / MCP / plugins 各司其职”的分层一致。
- 外部 worker 只处理边界明确任务，Codex 保留规划、监督和验收，符合本项目产品边界。
- 已把“当前 Desktop host 不能保证热更新”与“远端 Release 已发布”分开表达，没有再用新任务冒充 host 已刷新。

### 5.2 当前堵点

| 堵点 | 根因 | 系统性解决方向 |
|---|---|---|
| 合并后 release 在启动前失败 | release workflow 的 action pin 未被 PR 验证 | 建立 workflow dependency preflight，并让 CI 与 release 共享 pin 来源 |
| 发布状态过多且分散 | GitHub Release、远端包、本机 stage、host refresh、provider readiness、user path 是不同事实源 | 维护一张 machine-readable delivery receipt；GitHub workflow 写 remote release evidence，本机脚本追加 projection evidence |
| 规则易变成长文 | 运行态细节、一次性故障、跨项目偏好混在同一层 | 全局只留短行为规则；项目 release 合同留项目文档；重复程序写 Skill/脚本 |
| 发布 incident 没有独立入口 | workflow 失败只能从 Actions 列表发现 | 建立 release incident template：run URL、失败阶段、tag/Release 状态、修复 PR、恢复验证、交付结论 |
| `main` 自动发布和本机验收天然跨边界 | GitHub runner 不可能重启你的 Codex Desktop 或登录 provider | 不试图“自动化伪造”；把 host refresh/provider/user path 列成可见的发布后投影步骤 |

### 5.3 新的最小流程

```text
开发 PR
  -> PR CI：业务测试 + release intent + workflow dependency preflight
  -> 合并 main
  -> Release On Main：构建、发布、远端下载复验、写 remote receipt
  -> 本机：下载同一 zip、stage、fresh-context、provider readiness、user path
  -> delivered 或 release incident
```

其中只有最后一段需要本机真实 host / provider 证据；它不是“忘了发布”，而是远端系统无法替你证明本机已经加载了新进程。若远端 Release workflow 失败，立即进入 release incident，禁止开始下一次发布影响 PR，也禁止手工补发包。

## 6. 规则修订候选

本节只给候选，不直接改全局规则。

### 6.1 适合全局规则的候选

| 候选 | 具体 delta | 原因 | 验证 |
|---|---|---|---|
| 发布 workflow 改动必须做启动前验证 | 对任何发布影响 PR，CI 必须验证 release workflow 使用的 actions、输入、权限与基线历史可用；不只验证业务测试 | 本次两次事故分别证明 PR 事件基线与 release action pin 都会在合并后暴露 | PR 事件和 main push 事件各有一次真实成功 run |
| GitHub 设置变更必须回读 | 修改分支保护、Actions 权限或安全开关后，必须用 API/页面回读实际生效值，再继续 PR | 设置文字不等于远端状态 | 报告保存 before/after 与 API 结果 |
| 自动化失败不得靠人工绕过 | 自动发布失败先记录 incident、修复自动路径并复验；除非用户明确授权应急人工发布 | 防止重新产生合并后手工尾巴 | 发布恢复仍由 workflow 产生 Release |

### 6.2 只适合 Codex Praetor 项目规则的候选

1. `Release On Main` 的每个外部 action pin 必须由 PR preflight 解析；CI 与 release workflow 的同类 action 从同一清单引用或由测试强制一致。
2. 发布 workflow 首次上线或变更后，必须有一次 **workflow boot proof**：确认 runner 能完成 setup、checkout、依赖安装和发布前 gate；仅本地脚本通过不够。
3. 每个 release incident 必须在 `docs/release/incidents/` 留简短事件记录，写明 run URL、是否创建 tag/Release、恢复 PR 和最终交付事实。
4. `delivered` 的定义继续保持严格：远端 Release 验证 + 本机 receipt + health + 真实用户路径；不能仅由 GitHub 绿灯决定。

## 7. 分阶段执行计划

### 阶段 A：先恢复本次 0.6.0-alpha 交付

1. 从最新 `main` 建立 `codex/release-workflow-pin-repair`。
2. 把 release workflow 中错误的 setup-node SHA 改为 CI 已验证的 `...0020`。
3. 增加 workflow pin 一致性 / 可解析性 preflight，至少覆盖 `.github/workflows/*.yml` 中的外部 `uses:`。
4. 跑针对性本地测试、PR CI；用户合并修复 PR。
5. 确认 `Release On Main` 创建 `v0.6.0-alpha`、zip、sha256，且远端下载复验通过。
6. 下载同一 zip 完成本机 stage、fresh-context、provider readiness、activate、普通用户路径和 retirement 状态记录。

这是一次发布 incident 修复 PR，不是新功能，也不能被手工发布替代。

### 阶段 B：账户与仓库安全基线

1. 账户启用 2FA/passkey；保存恢复码。
2. 重新做 GitHub CLI 登录，移除超宽 token，使用短期或细粒度授权。
3. 启用 Dependabot alerts 与 security updates；先审阅首批 PR。
4. 启用 CodeQL default setup，先观察告警质量再决定是否 required。
5. 收紧 Actions allow policy；评估并启用 SHA pin enforcement。
6. 打开 merged branch 自动删除；决定 squash merge 与签名提交策略。

### 阶段 C：供应链与公开专业化

1. 给发布 zip 添加 artifact attestation / provenance 和验签步骤。
2. 建 profile README、更新 bio、清理 company/项目定位冲突、置顶 3–4 个代表仓库。
3. 为历史仓库补 About/topics/README，或明确 archive；不要把没有说明的旧仓库当成当前作品集。
4. 检查 issue form、security reporting 路径和 private vulnerability reporting 是否真正对外可用。

## 8. 外部证据与适用边界

- GitHub Actions 安全建议最小权限，并建议把默认 `GITHUB_TOKEN` 维持为 read、在具体 job 升权；本项目的 CI read-only / release write 方向正确。
- GitHub 说明 branch protection 可要求 PR、status check、讨论解决、签名、线性历史和 merge queue；不是每个开关都适合单人维护。
- GitHub profile 文档明确 profile README 与 pinned items 是公开作品集的主入口；所有公开资料应按永久公开的风险审查。
- Codex 官方资料明确 `AGENTS.md` 应保持小而持久，Skill 适合可复用程序，MCP 处理外部系统，Plugin 适合稳定分发。不要把所有故障细节堆回全局规则。
- 本次 OpenAlex 学术检索的结果偏离“AI coding agent CI 治理”主题，未作为本报告结论证据；这也是证据登记中应保留的失败面，而不是硬凑引用。

主要来源：

- https://docs.github.com/en/actions/reference/security/secure-use
- https://docs.github.com/repositories/configuring-branches-and-merges-in-your-repository/managing-protected-branches/about-protected-branches
- https://docs.github.com/en/code-security/dependabot/dependabot-alerts/about-dependabot-alerts
- https://docs.github.com/en/code-security/secret-scanning/introduction/about-secret-scanning
- https://docs.github.com/en/code-security/code-scanning/introduction-to-code-scanning/about-code-scanning
- https://docs.github.com/en/account-and-profile/concepts/personal-profile
- https://developers.openai.com/codex/concepts/customization
- https://developers.openai.com/codex/guides/agents-md
- https://developers.openai.com/codex/learn/best-practices
- https://developers.openai.com/codex/hooks

## 9. 现在该做什么

先处理阶段 A。当前不能把 #27 当作收口完成，也不应先改 profile、开安全开关或继续下一轮发布影响开发。待 `v0.6.0-alpha` 真的发布、下载并完成本机用户路径后，再按阶段 B 和 C 逐项执行；每项设置变更都先做备份/回读，避免把“看上去更专业”变成新的不可验证阻断点。
