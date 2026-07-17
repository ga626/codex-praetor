# Codex 执政官 0.3.0 交付后现状审计与下一阶段路线图

日期：2026-07-17  
项目：`D:\Projects\CodexPraetor`  
性质：项目考古、GitHub 远端审计、历史计划对账、外部调研与下一阶段实施建议。  
边界：本轮只新增本报告；未修改产品代码、稳定安装、GitHub 设置、分支或 Release。验证仅使用只读探针、dry-run 和隔离测试路径。

## 一、结论先行

Codex Praetor 已经越过“工程原型”阶段，当前准确状态是：

> **`v0.3.0-alpha` 已按普通发布链路交付，核心派工与发布控制面可用；下一阶段不应继续补散点功能，而应把一次性交付证明升级为可持续、可自证、可维护的运行态真值系统。**

这次考古没有发现需要推翻现有架构的证据。相反，历史上最重要的五条链已经成立：

1. runtime contract、generation、发布物和安装 surface 能对应到同一版本代际。
2. provider readiness 会按 generation、CLI hash、模型、权限和任务类型约束真实派工。
3. blocking/background 派工已经进入 durable job、watcher、completion 和 Codex 验收状态机。
4. GitHub Release zip、`.sha256`、fresh-context proof、稳定 activation 和退休清单形成交付收据。
5. 旧 generation 不被强删；占用或保留期内的目录进入延迟回收。

但还有四个真正的未完成面：

| 优先级 | 未完成面 | 当前影响 |
|---|---|---|
| P0 | 维护任务安装、卸载和 health 没有共享同一事实来源 | 本机只能靠人工 `schtasks` 补注册；任务消失后 health 仍可能是 `ready` |
| P0 | health 使用发布时 readiness 快照，不反映当前过期或 CLI 漂移 | 真实 dispatch 会 fail closed，但用户可能先看到失真的 `health=ready` |
| P1 | worker worktree、运行态和远端分支缺少持续卫生闭环 | 当前约 195.4 MB 运行态、9 个可清理 worktree、1 个不干净旧 worktree、20 条非主线远端分支 |
| P1 | GitHub 供应链与仓库治理仍停留在个人 alpha 水平 | 无 ruleset/分支保护、Release 非 immutable、无 attestation、Dependabot/CodeQL/私密漏洞报告未启用 |

下一步最合适的不是再加一个 provider 或新 MCP 工具，而是做一个聚焦的 **`0.3.1-alpha 运行态真值与供应链加固 PR`**。完成后再进入 `0.4.0-alpha` 的可观测性、provider 组合和规模化验收阶段。

## 二、审计方法与证据边界

本轮同时使用了四类证据：

- **本地源码与运行态**：Git、项目规则、脚本、MCP、配置、测试、stable receipt、retirement、scheduled task、worker worktree 和历史报告。
- **GitHub 远端事实**：仓库元数据、PR、Release、Actions、branch/ruleset、安全能力和 attestation 实际查询。
- **KnowledgeRadar 原生 MCP**：先执行 `health_check(mode="summary")`、`get_capabilities(summary=true)`，再用 `kr_research(mode="deep_route", budget="deep")` 规划官方 Web、GitHub 和学术来源生态，随后定向搜索和抽取正文。
- **官方资料**：OpenAI Codex 文档、MCP 规范、Microsoft Task Scheduler、GitHub 供应链文档、OpenTelemetry 和 Microsoft Agent Framework 可观测性资料。

KnowledgeRadar 收口时没有 active/stale 后台任务，最近 30 条决策日志成功率为 100%；历史队列中的 1 条 B 站网络超时与本研究无关。

三次研究质询用于防止“找到资料就结束”：

1. 本地考古后：旧报告里的待办是否真的还没做？结论是多数已经完成，不能照抄旧路线图。
2. 第一轮外部证据后：MCP `tools/list_changed` 是否能解决当前 Codex 对话热替换？结论是协议具备可选通知，但没有证据证明当前 Codex host 对已存在对话实施了完整热刷新，不能据此修改现有边界。
3. 成稿前：每个建议是否对应可复现缺口？最终只保留维护真值、动态 readiness、运行态卫生、供应链和可观测性五组有直接证据的任务。

OpenAI Codex manual helper 本轮对官方地址返回 HTTP 403；随后按规则改用 KnowledgeRadar 抽取官方 Codex 页面。学术检索只用于背景发现，没有学术元数据被用作本报告关键结论的唯一依据。

## 三、当前项目全景

### 3.1 代码与版本

| 项目 | 当前事实 |
|---|---|
| 当前分支 | `main` |
| HEAD / tag | `98afd88b64384268edaae22355c1a2de666d69b0` / `v0.3.0-alpha` |
| 与远端关系 | `main...origin/main`，工作树干净 |
| Git 提交数 | 51 |
| tracked files | 167 |
| 主要文件构成 | 61 个 PowerShell、8 个 TypeScript、52 个 Markdown、14 个 JSON |
| runtime contract | `codex-praetor-runtime-contract/v1` |
| 产品版本 | `0.3.0-alpha` |
| wrapper protocol | `2` |
| task contract | `codex-praetor-task-contract/v4` |
| MCP 工具数 | 17 |

代码结构已经形成明确分层：

```text
setup.cmd / setup.ps1
    -> scripts/install + scripts/release
    -> stable surfaces / generation receipt / retirement

mcp/src
    -> 17 个 codex_praetor_* 工具
    -> PowerShell 控制面薄封装

scripts/dispatch
    -> route / provider policy / worktree / durable job / watcher / cancel

skill/codex-praetor
    -> Codex 可复用工作流与 provider 参考资料

plugin
    -> 最终插件 manifest、MCP bundle 和 Skill 分发副本
```

产品边界仍然清楚：Codex 负责规划、监督、集成和最终验收；Qoder、CodeBuddy、MiMo 只执行边界明确的外部 CLI worker 任务；KnowledgeRadar 负责外部研究感知。

### 3.2 GitHub 仓库

截至本轮查询：

| 项目 | 远端事实 | 判断 |
|---|---|---|
| 仓库 | `ga626/codex-praetor`，public，MIT | 已公开 |
| 社区信号 | 3 stars、1 fork、0 open issues | 仍是早期 alpha |
| PR | 19 个，19 个已合并 | 开发历史完整 |
| Release | 6 个，全部为 prerelease | 尚无 stable/latest release |
| Actions | 最近 50 次全部 success | 当前 CI 稳定 |
| branches | 21 条，其中 20 条不是 `main` | 合并后分支未自动删除 |
| ruleset / branch protection | 无 | `main` 没有远端强制门禁 |
| Secret scanning | 已启用，push protection 已启用 | 基础秘密防护成立 |
| Dependabot security updates / alerts | 未启用 | 依赖风险没有持续提醒 |
| Code scanning | 无 analysis | 没有 CodeQL 或等价扫描 |
| Private vulnerability reporting | 未启用 | `SECURITY.md` 的“私下报告”缺少实际入口 |

当前 Release：

- `v0.3.0-alpha` 已发布，`isPrerelease=true`，`immutable=false`。
- zip：`codex-praetor-setup-0.3.0-alpha.zip`，532,823 bytes。
- zip SHA256：`1020c6e87bad9f1d9e22a6f3776d33af7da4f92c26c548c4b5e18e8e9bfdfacc`。
- zip 和 `.sha256` 各有 2 次下载记录。
- `gh attestation verify` 返回 `no attestations found`。
- 因为全部 Release 都是 prerelease，GitHub `releases/latest` 返回 404；README 使用精确版本 URL，因此当前下载入口仍有效。

### 3.3 stable 安装与交付收据

底层 health 当前为 `ready`，不是只看 README 或状态文字得出的判断：

| 检查项 | 当前结果 |
|---|---|
| active generation | `0.3.0-alpha--98afd88b6438--f37fb9ad8c60` |
| source generation | 与 runtime contract 一致 |
| installed Skill | hash 与 active receipt 一致，且为真实目录 |
| installed plugin | hash 与 active receipt 一致 |
| personal cache | `0.3.0-alpha`，hash 一致 |
| marketplace | 指向 active plugin |
| fresh context | passed |
| provider readiness | passed |
| retirement manifest | readable |

fresh-context 验收已观察到 17 个工具，并实际调用了 route、dry-run 和 lane 查询。当前对话仍可能持有旧工具快照，这与 stable 安装失败是两回事；新合同的最终证据必须来自 fresh context。

当前 readiness 只有一个真实通过 tuple：

```text
provider=codebuddy
model=hy3
permission_profile=local-audit-v1
task_kind=local_audit
wrapper_protocol=2
expires_at=2026-07-24T15:19:31+08:00
```

这足以证明本机至少有一条真实 provider 路线可用，不代表 Qoder 和 MiMo 当前也 ready。`cli_hash` 已记录，但 `cli_version` 为空，说明“精确版本”仍未成为可靠的强制字段。

### 3.4 自动回收与本地运行态

稳定退休清单当前有 28 项，全部为 `deferred_retention`，没有 `blocked_by_process`，也没有已删除项。这个状态符合 14 天保留规则，不是失败。

维护任务 `CodexPraetor-GenerationReconcile` 当前已启用，最近一次返回 0，每 15 分钟重试。但它不是产品脚本自动成功注册的：`Register-ScheduledTask` 在本机曾返回权限拒绝，收口时人工改用 `schtasks /Create` 才补齐。

项目内 `.codex-praetor` 当前约 204,865,784 bytes（195.4 MiB）、5800 个文件。清理脚本 dry-run 结果：

- 9 个 clean + merged worker worktree 可安全移除。
- 1 个旧 MiMo worktree 不干净，内容只有未跟踪 `.mimocode/`，必须先人工审计，不能自动删除。
- 2 个近期完成 job 尚在 14 天保留窗口。
- 本轮未执行任何删除。

这说明“发布 generation 回收”和“项目 worker/runtime 清理”是两套不同生命周期，不能混成一个删除器。

## 四、历史报告与实际完成度对账

### 4.1 已经完成，不应再列入下一阶段

| 历史目标 | 当前结论 | 证据 |
|---|---|---|
| Windows 双击安装和 provider 向导 | 已完成 | `setup.cmd`、`setup.ps1`，干净临时 profile smoke 通过 |
| 中文首页、安装、排错、隐私、卸载 | 已完成 | README 与 `docs/user/` |
| runtime contract 与 generation | 已完成 | `config/runtime-contract.json`、generation v2 |
| Release zip 确定性与远端复验 | 已完成 | determinism gate、远端 zip 与 `.sha256` |
| provider readiness fail closed | 已完成基础闭环 | dispatch 会校验 generation、CLI hash、tuple 和 expiry |
| durable job / timeout / cancel / completion | 已完成基础闭环 | job lifecycle smoke 通过 |
| Codex 验收后解锁计划依赖 | 已完成 | `awaiting_verification` 与 verify-task |
| fresh-context 工具合同验收 | 已完成 | stable closeout proof |
| 旧 generation 延迟回收 | 已完成基础机制 | retirement manifest + scheduled retry |
| 中文全局规则语义检查 | 已完成 | dev-env 验证通过 |

因此，`docs/roadmap.md` 中“本大 PR 一次完成”和后续 1-7 条仍把已交付内容写成近期目标，已经过时，应在下一 PR 首先重写。

### 4.2 部分完成，不能继续写成“已经彻底解决”

| 历史目标 | 实际差距 |
|---|---|
| 自动维护任务 | 脚本只有 `Register-ScheduledTask`；本机依赖人工 `schtasks` fallback |
| health 反映维护状态 | health 只读 retirement manifest，不检查任务是否存在、启用、action 是否正确、最近结果是否成功 |
| generation-aware readiness | dispatch 动态校验 expiry/hash；health 只信 active receipt 内发布时快照，可能失真 |
| 完整 provider tuple | `cli_hash` 有效，但当前 `cli_version` 为空；provider adapter 仍主要集中在大 PowerShell wrapper 中 |
| 强进程所有权 | 当前用 PID、启动时间和 CIM 递归子进程终止，尚未采用 Windows Job Object；对脱离父进程树的 child 仍需失败注入证明 |
| command identity | job 保存完整 command 和 args，但没有独立 command hash |
| 自动运行态卫生 | 有安全 dry-run 清理器，但未接入低频维护；不干净 worktree 需要显式人工决策 |
| 不可变发布 | 项目规则要求不可变语义，但 GitHub Release 设置仍为 `immutable=false` |
| 发布 provenance | 有 zip hash 和内容 manifest，无 GitHub artifact/release attestation 或 SBOM |

## 五、下一阶段必须解决的问题

### P0-1：把维护任务变成可验证的产品 surface

根因不是单一权限错误，而是“安装、查询、卸载、health”四处各自理解 scheduled task：

- 安装只调用 ScheduledTasks PowerShell module。
- 本机真正成功的是 `schtasks.exe`。
- 卸载只调用 `Unregister-ScheduledTask -ErrorAction SilentlyContinue`，即使任务没删也会继续删除脚本并打印 PASS。
- health 完全不检查任务。

下一 PR 应建立一个 canonical maintenance-task adapter：

1. 生成一份固定 task definition，包含登录触发和每 15 分钟触发、Limited/Interactive principal、`IgnoreNew`、稳定脚本路径和 `-Apply`。
2. 优先尝试 ScheduledTasks module；权限或模块失败时自动使用 `schtasks /Create /XML`，以保留双 trigger，而不是退化成行为不同的临时任务。
3. 注册后重新读取任务，验证 task name、action、arguments、principal、trigger、enabled、next run 和 last result。
4. 卸载通过同一 adapter 删除并确认任务确实不存在；确认后才删除维护脚本。
5. health 新增 `maintenance_task` 检查。任务缺失、禁用、action 漂移或长期无成功结果应为 `degraded`；脚本缺失或 task 指向越界路径应为 `blocked`。

### P0-2：区分“发布时证明”和“当前可运行状态”

active receipt 中的 readiness 是发布时 promotion proof，应该保持不可变；它不应被当成今天仍可派工的证明。

下一 PR 应把 health 拆成两层：

```text
release_provider_proof
    -> 证明 activation 当时至少一个 tuple passed

current_provider_readiness
    -> 读取当前 readiness 文件
    -> 校验 generation / contract / CLI path / CLI hash / tuple / expires_at
```

预期行为：

- readiness 过期：health 至少 `degraded`，真实 dispatch `blocked`。
- CLI 文件 hash 变化：当前 tuple 立即 stale/blocked。
- readiness 文件缺失或 schema 旧：不改变 active receipt，但真实 dispatch 继续 fail closed。
- 只有 provider 未配置：产品安装面可以 ready，provider dispatch 明确 disabled/manual_required，不能把整套产品说成坏了。

同时应让 canary 尽量记录真实 `cli_version`；若 provider 无法稳定返回版本，明确写 `version_unavailable` 和证据来源，而不是留空后仍让报告声称“精确版本已绑定”。

### P1-1：建立运行态卫生账本，而不是静默自动删

下一 PR 不应简单把 `clean-codex-praetor-runtime.ps1 -Apply` 塞进定时任务。更稳妥的顺序是：

1. 生成本地 inventory：worktree、branch、job、scratch、bytes、最后活动时间、clean/dirty、merged/unmerged。
2. clean + merged + 超过保留期的 worker worktree 才进入自动候选。
3. dirty、unmerged、无法读取或非 `cw-*` 的 worktree 永远只报告，不自动删。
4. job 先归档摘要，再按第二个更长保留期删除完整日志。
5. MCP health/status 只返回计数和下一步，不倾倒日志或私有 prompt。

本轮发现的旧 `.mimocode/` 必须先做一次人工内容审计；在没有判断其价值前，不应执行 `-Apply`。

### P1-2：把 GitHub 从“可用仓库”升级为“可持续仓库”

低成本、应立即补齐的仓库设置：

- 为 `main` 建 ruleset：要求 PR、要求 `validate` 成功、禁止 force push 和删除。
- 启用 merge 后自动删除 head branch，之后单独清理现有 20 条非主线远端分支。
- 启用 Dependabot alerts/security updates，并为 npm 与 GitHub Actions 添加 version updates。
- 启用 private vulnerability reporting，修正 `SECURITY.md` 的实际提交入口。
- 对 workflow 中的 `actions/checkout`、`actions/setup-node` 使用 full-length commit SHA，并让 Dependabot 维护版本注释。
- 显式保留 `GITHUB_TOKEN` 默认只读；release/attestation job 单独提升最小权限。

这些设置属于仓库管理员动作，不能只靠 PR 文件自动完成。报告和 PR 描述必须把“代码改动”和“合并后 GitHub 设置”分开验收。

### P1-3：让 Release 真正不可变且可验证来源

当前 zip hash 能证明“下载后没变”，但不能证明“由哪条受控 workflow 构建”。下一阶段应增加受审批的 release workflow：

1. 从精确 tag/commit 在 `windows-latest` 构建确定性 zip。
2. 重跑 public scan、版本一致性、determinism 和 release closeout smoke。
3. 生成 zip、`.sha256`、内容 manifest 和最小 SBOM。
4. 生成 GitHub artifact attestation；下载后用 `gh attestation verify` 验证。
5. 先创建 draft、上传全部资产，再由用户批准 publish。
6. 启用 immutable releases，发布后禁止移动 tag 或替换资产。

这仍然保留用户的发布审批权；只是把“本机打包再上传”升级为可复现、可证明的远端构建。

### P2：在不上传私有内容的前提下补可观测性

现有 job 已记录 provider、状态、时间、stdout/stderr、部分 token/cost 和 completion，但缺少跨 job 的聚合视图。`0.4.0-alpha` 可以增加本地只读 summary：

- 按 provider/tier/task kind 的成功率和失败分类。
- queue/start/run/verify 各阶段耗时，至少给 p50/p95。
- timeout、cancel、watcher_failed、orphaned 和 worktree_drift 趋势。
- provider 返回时才记录 token/cost；缺失就是 unknown，不估算。
- 默认不采集 prompt、tool args、源码或完整输出；内容采集必须显式 opt-in。
- 首先写本地结构化事件；OTLP 导出只能是可选适配器，不能成为产品运行依赖。

OpenTelemetry 和 Microsoft Agent Framework 的共同模式是 workflow/session/executor 分层 span、错误类型和时延；可以借鉴字段语义，但 GenAI semantic conventions 仍在演进，不应在 alpha 阶段把内部 schema 与外部草案强绑定。

## 六、外部调研对架构的约束

### 6.1 Codex 与 MCP 生命周期

OpenAI 官方资料确认：

- Skill 适合可复用工作流；Plugin 适合可安装、可共享、可组合 Skill 与 MCP 的能力包。
- Codex Desktop、CLI 和 IDE 共享同一 Codex host 的 MCP 配置。
- 修改 MCP 配置后的官方用户动作包含 Restart。
- Plugin/MCP 工具主要面向新 chat 加载。

MCP 2025-06-18 规范确实定义了 capability negotiation 和可选 `tools.listChanged`，但这是 server/client 协商能力，不等于任意 host 会重建已经交给模型的当前对话工具快照。

因此现有策略正确：

> 普通实现修改不新开任务；只有工具名/参数、Skill/Plugin manifest、安装入口或工具合同变化时，每个 generation 做一次 fresh-context 验收。不要承诺当前任务热替换自身。

### 6.2 Windows Task Scheduler

Microsoft 官方文档明确：scheduled task 在特定 security context 下注册和运行，调用进程必须具有正确凭据与权限；`schtasks.exe` 与 Task Scheduler 操作可互换，但权限和 principal 仍必须显式验证。

这支持“多 backend + 注册后读回验证”，不支持“捕获异常后假装安装成功”，也不支持为了回收旧 generation 提权或关闭 Codex。

### 6.3 GitHub 发布与供应链

GitHub 官方资料明确：

- immutable release 会锁定 tag 和资产，并自动生成 release attestation。
- artifact attestation 绑定 workflow、仓库、commit SHA 和触发事件；可附 SBOM。
- attestation 不是安全保证，只是 provenance，仍需测试和发布策略。
- ruleset 可保护 branch/tag；GitHub Actions 第三方 action 只有 pin 到完整 commit SHA 才是不可变引用。

这些能力与项目现有 generation/receipt 思路完全一致，下一阶段应接入，而不是再发明一套私有签名格式。

## 七、推荐路线图

### 里程碑 A：`0.3.1-alpha` 运行态真值与供应链加固

建议分支：`codex/operational-truth-0-3-1`

一个 PR 完成以下同一可靠性主题：

1. maintenance task canonical adapter、`schtasks /XML` fallback、安装后验证和对称卸载。
2. health 动态检查 scheduled task 与 current provider readiness。
3. provider canary 的 `cli_version`/不可用原因和 schema 负向测试。
4. runtime inventory、dirty worktree 保护、空间/保留期摘要。
5. 重写过时 roadmap，新增 sanitized delivery status 文档。
6. CI action SHA pinning、Dependabot 配置、最小 token permissions。
7. release workflow、attestation/SBOM 的可重复构建与验收脚本。

合并后由用户执行或确认的 GitHub 设置：ruleset、auto-delete branch、Dependabot/security updates、private vulnerability reporting、immutable releases。

版本选择规则：如果只增加 health 检查字段而不改变 MCP 工具名、参数和 Skill/Plugin manifest 合同，可使用 `0.3.1-alpha`；若新增公开 MCP 工具或改变已有输入/输出合同，应改为 `0.4.0-alpha` 并重新做一次 fresh-context proof。

### 里程碑 B：`0.4.0-alpha` 可观测性与 provider 组合

在里程碑 A 稳定后再做：

- 本地 job summary/index 和失败趋势。
- per-provider readiness 状态面，不再只展示 overall passed。
- Qoder、CodeBuddy、MiMo 的独立 capability matrix 与周期性小 canary。
- provider 冷却、最近失败和成本/时间偏好进入可解释路由结果。
- 可选 OTLP 导出，默认关闭内容采集。
- 面向真实小项目的回归 corpus：只读审计、代码修改、超时、取消、拒绝验收、provider 未登录、CLI 升级。

### 里程碑 C：进入 beta 前的产品门

满足以下条件再考虑非 alpha：

- 至少两个 provider 在两个不同 Windows 用户环境通过真实 canary。
- maintenance fallback、卸载、retention 到期删除完成跨机验证。
- 连续多个版本的 GitHub attestation 和 immutable release 可验证。
- 有最少一轮外部用户安装反馈，而不是只有作者机器和 CI 临时 profile。
- 安全报告入口、依赖更新和 branch ruleset 持续工作。
- 已定义兼容/迁移政策，而不是每次升级都依靠人工解释。

## 八、下一 PR 的详细实施顺序

1. **冻结基线**：记录 `v0.3.0-alpha` active receipt、scheduled task XML、readiness、运行态 inventory 和 GitHub 设置。
2. **先写负向测试**：模拟 `Register-ScheduledTask` access denied、task 缺失/禁用/action 漂移、uninstall 删除失败、readiness 过期、CLI hash 变化。
3. **实现 task adapter**：同一 task definition 驱动 ScheduledTasks 和 `schtasks /XML`，所有 native 调用继续使用统一 stdout/stderr/exit-code helper。
4. **改 health 真值模型**：release proof 与 current state 分开；维护失败不回滚 active generation，但必须准确降级。
5. **改 runtime inventory**：只自动处理 clean + merged + expired；dirty/unmerged 一律报告。
6. **补 CI/供应链文件**：action SHA、Dependabot、release workflow、attestation、SBOM、最小权限。
7. **更新文档和规则**：roadmap、安装、排错、卸载、release gate、GitHub 管理员动作。
8. **PR 前验收**：PowerShell 5.1/7、Node 22、产品验证、job lifecycle、maintenance fallback、卸载、public scan、determinism、isolated closeout、远端 CI。
9. **合并后管理员动作**：ruleset、安全能力、immutable release；随后发布新 tag 和远端包复验。
10. **最终收口**：fresh context 仅在合同触发时执行；确认 dynamic health、attestation、stable activation 和 retirement 后再称产品已交付。

关键验收场景：

| 场景 | 必须结果 |
|---|---|
| `Register-ScheduledTask` access denied | 自动 fallback，task definition 等价，安装继续 |
| task 被删或禁用 | health `degraded`，给出修复命令 |
| task action 指向非批准路径 | health `blocked` |
| uninstall 无法注销 task | 不删除维护脚本，不打印 PASS |
| readiness 到期 | current readiness stale/blocked，真实派工拒绝 |
| CLI hash 改变 | 旧 canary 立即失效 |
| dirty worker worktree | 永远不自动删，报告路径和原因 |
| release zip | `gh attestation verify` 成功，hash 和 manifest 一致 |
| immutable release | tag 与资产不可替换 |
| 当前 Codex 对话仍是旧工具面 | 不判产品失败；用 fresh context 验收新合同 |

## 九、明确不做

- 不强杀 Codex、provider 或未知进程来清理旧目录。
- 不承诺当前 Codex 对话热替换自己的 MCP/Skill/Plugin 工具快照。
- 不自动登录 provider、读取 token、账号数据库、cookie、余额或截图。
- 不把 Codex Praetor 扩展成云端通用多 agent 平台。
- 不默认上传 prompt、tool arguments、源码、stdout/stderr 或用户路径到遥测后端。
- 不因为远端分支多就批量删除；先把每条分支映射到已合并 PR，再由用户确认治理动作。
- 不在未审计 `.mimocode/` 前清理那个 dirty worktree。

## 十、证据登记

| ID | 访问路径 | 来源 | 关键事实 | 强度 |
|---|---|---|---|---|
| L01 | local_code | `AGENTS.md` | 定义产品、发布、回收、中文和用户/Codex 边界 | 强 |
| L02 | local_git | `git status/log/tag` | `main` clean，HEAD/tag 为 `98afd88` / `v0.3.0-alpha` | 强 |
| L03 | local_runtime | `get-codex-praetor-health.ps1` | stable health 当前 `ready` | 强 |
| L04 | local_runtime | `active.json` | active generation、fresh proof、provider proof 一致 | 强 |
| L05 | local_runtime | `retirement.json` | 28 项全部 `deferred_retention` | 强 |
| L06 | local_runtime | `schtasks /Query` | 维护任务 enabled，最近结果 0，每 15 分钟运行 | 强 |
| L07 | local_code | `install-codex-praetor-maintenance.ps1` | 无 `schtasks` fallback，卸载失败可被静默吞掉 | 强 |
| L08 | local_code | `get-codex-praetor-health.ps1` | health 不检查 task，也不动态检查 readiness expiry/hash | 强 |
| L09 | local_code | `invoke-codex-praetor.ps1` | real dispatch 动态校验 generation、tuple、CLI hash、expiry | 强 |
| L10 | local_probe | MCP/product/dev/native/job/public-entry tests | 本轮全部 0 失败 | 强 |
| L11 | local_probe | runtime cleanup dry-run | 9 个可清理、1 个 dirty worktree；未执行删除 | 强 |
| G01 | gh_cli | GitHub repository API | 19/19 PR merged、6 prerelease、50/50 最近 Actions 成功 | 强 |
| G02 | gh_cli | Release API | zip digest 可核对，release `immutable=false` | 强 |
| G03 | gh_cli | rulesets/protection/security APIs | 无 ruleset；Dependabot/CodeQL/私密漏洞报告未启用 | 强 |
| G04 | gh_cli | `gh attestation verify` | 当前 zip 没有 attestation | 强 |
| K01 | native_mcp | KnowledgeRadar health/capabilities/route | 17 工具，按 Web/GitHub/academic 路线调研 | 强 |
| E01 | native_mcp | OpenAI Codex Skills & Plugins | Skill/Plugin/MCP 的官方产品角色 | 强 |
| E02 | native_mcp | OpenAI Codex MCP | MCP 配置共享、Restart、enabled/required/tool timeout 边界 | 强 |
| E03 | native_mcp | MCP lifecycle/tools 2025-06-18 | capability negotiation 与可选 `tools.listChanged` | 强 |
| E04 | native_mcp | Microsoft Task Scheduler security contexts | task 注册/运行依赖正确 security context 与权限 | 强 |
| E05 | native_mcp | GitHub immutable releases | 锁定 tag/asset，并生成 release attestation | 强 |
| E06 | native_mcp | GitHub artifact attestations | provenance 绑定 workflow/repo/commit，可附 SBOM | 强 |
| E07 | native_mcp | GitHub rulesets / secure use | ruleset 保护 branch/tag；action 应 pin full SHA | 强 |
| E08 | native_mcp | OpenTelemetry / Microsoft observability | workflow、agent、tool 的 trace/metric/log 分层与隐私默认 | 中强 |

## 十一、证据路径与来源

本地关键证据：

- `%USERPROFILE%\.codex\codex-praetor-releases\stable\active.json`
- `%USERPROFILE%\.codex\codex-praetor-releases\stable\retirement.json`
- `.codex-praetor/stable-closeout/v0.3.0-alpha/fresh-context-proof.json`
- `.codex-praetor/stable-closeout/v0.3.0-alpha/provider-readiness.json`
- `scripts/install/install-codex-praetor-maintenance.ps1`
- `scripts/verify/get-codex-praetor-health.ps1`
- `scripts/dispatch/invoke-codex-praetor.ps1`
- `docs/reports/Codex执政官统一产品化与可靠性大PR整体整改方案-2026-07-17.md`
- `docs/roadmap.md`

外部来源：

- https://developers.openai.com/codex/skills-and-plugins
- https://developers.openai.com/codex/mcp
- https://modelcontextprotocol.io/specification/2025-06-18/basic/lifecycle
- https://modelcontextprotocol.io/specification/2025-06-18/server/tools.md
- https://learn.microsoft.com/en-us/windows/win32/taskschd/security-contexts-for-running-tasks
- https://learn.microsoft.com/en-us/windows-server/administration/windows-commands/schtasks
- https://docs.github.com/en/code-security/concepts/supply-chain-security/immutable-releases
- https://docs.github.com/en/actions/concepts/security/artifact-attestations
- https://docs.github.com/en/repositories/configuring-branches-and-merges-in-your-repository/managing-rulesets/about-rulesets
- https://docs.github.com/en/actions/reference/security/secure-use
- https://opentelemetry.io/blog/2026/genai-observability/
- https://learn.microsoft.com/en-us/agent-framework/workflows/observability

## 十二、最终判断

项目主线没有失控，也不需要再做一次全量架构重写。`0.3.0-alpha` 已经把过去最危险的“源码、安装、provider、job、Release 各说各话”收束成一个可交付控制面。

下一阶段真正的跃迁是：

```text
一次性交付证明
-> 动态健康真值
-> 可验证维护任务
-> 安全运行态卫生
-> GitHub 不可变来源证明
-> 本地隐私优先的可观测性
```

先完成 `0.3.1-alpha` 的运行态真值与供应链加固，再做 `0.4.0-alpha` 的可观测性和 provider 组合。这样既不会重复旧工作，也不会把 alpha 项目过早扩成沉重的通用平台。
