# Codex 执政官 0.7.1-alpha 真实验收与下一阶段统一治理规划

> 日期：2026-07-21
> 类型：只读考古、外部调研与下一阶段设计。本文不修改产品运行态，不把推测写成验收结论。

## 一句话结论

上一轮“修复运行中插件被旧收据阻断”的 PR 已经完成：`v0.7.1-alpha` 已公开发布，当前 Codex Desktop 也已经实际加载这个版本。此前那次真实验收并没有证明产品可用：它在 `0.7.0-alpha` 上发现了旧 `active.json` 错误阻断这一缺陷，随后真实任务在创建前停止。当前 `0.7.1-alpha` 的阻断原因已经不同且合理：新运行代际尚未完成一次真正成功的 provider capability canary，所以系统拒绝开始真实派工。

下一步不是绕过安全门禁，也不是再开一串收口补丁。应当先在一个新的、已刷新宿主任务中执行一次标准真实验收；然后以它的证据为输入，做一个单独但完整的 `v0.8.0-alpha` 运行态可用性与验收治理 PR。这个 PR 一次解决 canary 并发误伤、任务终态/活跃 lane 失真、维护与库存可观测性、文本编码回归，以及非发布依赖 PR 被错误套用发布 tag 门禁的问题。

## 1. 两条工作线到底各做了什么

| 工作线 | 已完成的事 | 没有完成的事 | 现状 |
| --- | --- | --- | --- |
| 运行中 readiness 修复 PR | 修复 health/readiness 把历史 `active.json` 当作当前运行代际权威的问题；补回归测试；合并、自动发布并下载复验同一 zip | 不能替代新版本的真实 provider 验收 | **已交付** |
| 本机真实验收 | 在 `0.7.0-alpha` 上验证 host 已加载、dry-run 可用、CodeBuddy canary worker 能运行；精确找出旧收据权威错误 | 没能让正常真实派工创建 job，也没有证明 `0.7.1-alpha` 的真实任务可用 | **部分完成，结论不可迁移** |

此前报告看起来像“没有启动”，实际并非如此：`0.7.0-alpha` 的 CodeBuddy canary 进程返回了成功 marker，真正的审计任务则在创建 job **之前**被 health 门禁挡住。根因是 health 在声明“运行 generation 为权威”的同时，仍把 `0.4.1-alpha` 的旧 receipt generation/contract 传入 readiness 校验。该矛盾已由 `0.7.1-alpha` 修复。

## 2. 当前事实快照

### 2.1 已经交付的部分

- `main` 当前为 `4877ecb 修复运行中插件的 readiness 权威链 (#32)`，工作树干净。
- GitHub Release `v0.7.1-alpha` 已公开发布：`codex-praetor-setup-0.7.1-alpha.zip`，资产 SHA256 为 `519028b8da926f53512638421dad56fd9ae50d6b7177ea64129da467fc4a35fb`。
- 本次 main 的 CI 与 `Release On Main` 均成功；远端下载、zip SHA256、解压后的 bundled MCP 合同均已在收口时复验。
- 当前原生 `codex_praetor_runtime_info` 返回 `0.7.1-alpha`，运行根为 `%USERPROFILE%\.codex\plugins\cache\personal\codex-praetor\0.7.1-alpha`，因此 Desktop 已完成 host 刷新。

这四项共同说明：**代码已合并、公开产品已交付、当前本机 host 已加载新插件**。它们不等同于“本机真实派工已经验收通过”。

### 2.2 当前真实可用性状态

| 检查 | 当前结果 | 含义 |
| --- | --- | --- |
| runtime contract / marketplace / plugin cache | ready | 安装源、缓存和当前运行合同一致 |
| legacy `active.json` | degraded，仅诊断 | 仍指向旧历史代际，但不再参与 dispatch 权威判断 |
| provider readiness | blocked | 当前 `0.7.1-alpha` 没有与自身 generation、合同、CLI hash、模型、权限和任务类型匹配的成功 canary |
| fresh-context 历史收据 | degraded | 旧 receipt 没有新 generation 的 proof；当前原生 `runtime_info` 已是 host 的直接观察 |
| generation maintenance | degraded | `CodexPraetor-GenerationReconcile` 在本机不存在 |
| runtime inventory | degraded | 存在历史 worktree、job 与审计保留项；不是派工阻断原因 |

因此当前 `health=blocked` 的唯一关键原因是“尚未对 **这个版本** 成功完成 provider canary”。这是刻意的安全条件：不允许旧版本、旧 CLI 或过期凭据给新版本背书。它不是发布事故，也不是把旧 `active.json` 再次错误用于拦截。

## 3. 为什么此前测试没跑完

### 3.1 第一个阻断：已修复的实现缺陷

`0.7.0-alpha` 的 readiness 文件本身已经包含当前 generation 的有效 CodeBuddy tuple，但 health 又读取旧 `active.json` 并把旧 generation/contract 当成期望值。结果是：真实 dispatch 在创建 job 前返回“运行 generation health blocked”。这不是 provider、账号或安全策略失败，而是 health 权威链自相矛盾。`0.7.1-alpha` 已将当前 bundled generation 与 runtime contract 设为唯一权威，并有旧 receipt/新 generation 回归测试。

### 3.2 第二个阻断：canary 的并发耦合

上一轮 canary 真正启动了 CodeBuddy worker，worker `exit_code=0`、marker 存在、stderr 为空、worktree 干净。但脚本在写 readiness 前做了主检出 `git status` 前后完全相等检查。验收期间另一条工作流在主检出写入文件，于是脚本抛出：

```text
Canary changed the main checkout status.
```

这条检查原本是为了证明“只读 canary 没有污染主仓库”，却把“其他人同时修改主仓库”也判成“canary 失败”。两件事不等价：前者影响 canary 是否安全，后者只影响本次能否声称主仓库静止。它导致 provider 的真实成功证据不能写入 readiness，随后所有真实任务必然被新 generation 的门禁挡住。

### 3.3 这次不能把门禁关掉

不能手改 `active.json`、readiness 或伪造 marker；那只会把“未经真实 provider 验证”的版本错误标成可派工。正确处理是：

1. 在没有其他写入者的窗口运行一次真实 canary；
2. canary 成功后，系统自动写入这一 generation 的 tuple；
3. 再执行一次有真实业务价值的只读任务；
4. 如果 canary 因登录、CLI、权限或 provider 自身失败，停止真实派工，精确记录失败类别；不重试空转。

## 4. 仍未解决、但应纳入下一大 PR 的问题

### P0：0.7.1-alpha 真实派工尚未验收

这是当前最大的未知，不是已证明的代码缺陷。必须通过一次成功的 current-generation canary 和一次真实只读 job 才能关闭。若 canary 合法失败，结果应为“本机 provider 未就绪”，而不是对产品代码下结论。

### P1：canary 将无关并发修改误判成自身污染

`test-provider-capability-canary.ps1` 与用户向导的 readonly canary 都直接比较主检出前后 git status。下一版应拆成两条证据：

- provider/worktree 证明：worker 成功、marker、completion、stderr、worktree diff、tuple 与 CLI hash；这是写 readiness 的依据。
- 仓库静止观察：clean-before、clean-after、外部 drift 明细；它只决定“能否宣称主仓库保持干净”，不否定已经完成的 provider 能力证明。

若开始前主仓库已经脏，canary 应明确拒绝或要求隔离验证；若运行中出现外部 drift，应记录 `external_repo_drift_observed`，而不是把 provider 成功改写成失败。两种行为都要有故障注入测试。

### P1：已退出 job 被错误展示为 active

现有 `isActiveStatus` 只排除 `completed/failed/blocked/skipped/cancelled`，遗漏 `process_exited`、`timed_out`、`watcher_failed` 和 `unknown`。因此完成记录虽然正确写成 `process_exited`，lane 列表仍标 `active=true`。这会污染冲突检测、库存和人的判断。

下一版应将“进程是否在跑”与“逻辑任务是否待验收”分开显示：

- `running` / `queued` / `cancel_requested` 才是 active；
- `process_exited` 应是 terminal + `awaiting_verification`，不能占用 active lane；
- `timed_out`、`watcher_failed`、`unknown` 必须显示为失败或需要人工处理；
- result 分类必须能解释“成功退出但没有足够业务证据”的状态，而不是一律 `unknown_worker_state`。

### P1：Dependabot 的非发布依赖 PR 被错误套用发布 tag 校验

当前两个开放 Dependabot PR（TypeScript `5.9.3 -> 7.0.2`、`@types/node` `25.9.5 -> 26.1.1`）失败原因不是依赖安装或测试失败。日志先明确输出“开发期 MCP 依赖更新不需要产品发布”，随后仍运行远端 immutable tag 检查，发现 `v0.7.1-alpha` 已存在而失败。

这说明 release-impact 判定只在部分步骤生效。下一版应让同一份 `release-impact` 结果驱动整个 reusable pipeline：非发布 PR 运行安装、构建、测试、协议 smoke 和安全扫描，但跳过 release-intent/tag/remote-release 前提；发布影响 PR 才要求递增版本、release intent 与不可复用 tag。两个 Dependabot PR 不应手动合并或绕过检查；修复 pipeline 后应由正常 CI 重跑验证真实依赖兼容性。

### P2：维护、库存与历史 receipt 的状态尚未收敛

- `CodexPraetor-GenerationReconcile` 缺失，当前不阻断派工，但缺少预期的延迟回收重试。
- runtime inventory 保留了大量 historical artifacts、clean/unmerged worker worktrees 和 job；应提供安全、可预览的回收计划，而不能由 health 暗示已清理。
- `fresh_context` 仍从 legacy receipt 读取 proof，和“运行 generation 是权威”的新模型不完全一致。应让 native runtime observation 与发布收据的职责彻底分离。

### P2：原生 health 的中文消息在 MCP 输出中出现乱码

脚本源码含正常中文，而当前 MCP health 的若干消息出现 `��`。这可能是 Node/PowerShell 进程输出解码边界，而不是文案文件本身。下一版要先补端到端 UTF-8 回归测试，再定位和修复；在没有测试前不把它断言为单一根因。

## 5. 真正的“把问题挖出来”应如何做

没有单个自然语言任务能数学上证明“所有问题都不存在”。可达成的标准是：所有已知用户路径、状态转换和失败类别都有明确证据；无法由本机控制的 provider/login/网络边界被显式标记，不伪造通过，也不无限重试。

下一阶段采用一个统一验收包，而不是临时拼命令。它由下表的八个面组成；真实任务只是其中最重要的一面。

| 面 | 要验证的事实 | 真实/模拟边界 |
| --- | --- | --- |
| 发布物 | 最终 zip 的版本、generation、MCP 工具和合同一致 | 真实 zip；已有 artifact-first 流程继续保留 |
| 安装与 host | marketplace、缓存、Desktop 原生 `runtime_info` 指向目标 generation | 真实新宿主任务 |
| 安全准入 | 当前 provider、模型、权限、task kind、CLI hash 和有效期都匹配 | 一次真实 readonly canary；绝不手写 readiness |
| 真实业务任务 | job 被创建、worker 返回可检查报告、completion/result/timeline 一致、主仓库不被 worker 污染 | 一次有业务价值的只读审计任务 |
| 失败路径 | 旧 receipt、过期 canary、CLI hash 漂移、权限拒绝、timeout、取消、外部 repo drift | 可重复故障注入；不能冒充真实 provider 成功 |
| 生命周期 | terminal job 不再列为 active；未验收不解锁依赖；result 可解释 | 单元/集成 smoke + 一个真实 job 交叉验证 |
| 发布流程 | release PR 与非发布依赖 PR 各走正确门禁 | GitHub Actions 可复现测试与两条 Dependabot PR 重跑 |
| 用户可读性 | 中文结构化输出未乱码，失败提示给出下一步 | MCP 端到端文本断言 |

### 5.1 下一次真实验收的最小自然语言任务

真实 worker 不应接收一大段测试说明。建议任务只有一个正常、可复查的目标：

```text
审计 Codex Praetor 当前 main 对普通用户是否可安装、可发现并能安全派发只读任务；只读，不改代码。列出发现的风险和证据。
```

调度器外围负责记录版本、canary、completion、worktree、result 和 git status；这些是验收协议，不应塞给 worker。这样该任务本身有真实价值，也会经过用户真正关心的派工链路。

### 5.2 门禁失败时怎么办

| 失败类别 | 允许做什么 | 不允许做什么 | 结论 |
| --- | --- | --- | --- |
| 当前 generation 没有 canary | 执行一次官方 readonly canary | 手写 readiness、借用旧版本记录 | 本机 provider 尚未验证 |
| provider 登录/CLI/权限失败 | 记录精准类别，按 provider 官方流程处理后再验收 | 连续重派、扩大权限、读取 auth 数据库 | 外部依赖未就绪 |
| canary 运行中出现外部 repo drift | 记录 drift，检查 worker worktree 与 proof；按新语义分类 | 将外部改动归咎于 canary | 验收完整性降级，但 provider 结果不被伪改 |
| 真实 job 失败 | 读取一次 completion/stdout/stderr/timeline，归类后停止 | 盲目重复相同派工 | 可复现的产品或环境问题 |
| host 仍为旧版本 | 完全重启 Desktop 后新建一个任务再验一次 | 连续新建任务企图热替换 | host 刷新未完成 |

## 6. 下一阶段的组织方式

不需要现在开多个并发对话。执行时只开 **一个** 新的 Codex 项目任务，专门做 `0.7.1-alpha` 的真实验收；当前对话保留为下一大 PR 的设计、实现和集成位置。

新任务的作用不是让另一个 Codex 模型代替开发，而是提供已刷新 Desktop host 的干净原生 MCP 观察面。它会通过 Codex Praetor 实际派发一个外部 CodeBuddy readonly worker。无需高频轮询：任务结束后只读取一次完整 result 和本地证据目录。

如真实验收通过，当前对话立刻进入下一大 PR；如失败，当前对话把失败证据作为同一大 PR 的输入。除非发现必须由用户完成登录、授权或网络恢复，否则不需要再新开第三个对话。

## 7. 下一大 PR：范围与执行顺序

建议版本：`v0.8.0-alpha`。这是发布影响 PR，因为会调整 bundled MCP、派工/验收脚本、CI 和用户可见诊断。

### 目标

把“发布物已交付、当前 host 已加载、provider 已验证、任务已完成”变成四个分开、可观察、不可互相伪造的状态；让每个发布影响 PR 合并后自动发布成功，而本机真实可用性作为独立的用户验收结果，绝不再制造收口补丁循环。

### 实施包

1. **真实验收协议与 canary 语义**：提取统一的 acceptance evidence schema；修正 canary 的并发判定；为 clean、dirty-before、drift-during、worker 失败、marker 缺失建立测试。
2. **job/lane/result 真值**：修正 active 判定；把 terminal execution、evidence、governance verdict 分层显示；补齐真实 completion 到 result 的分类和回归测试。
3. **运行态维护**：把 native host observation、历史 receipt、maintenance task、inventory 和安全回收职责拆开；维护任务注册失败必须可见且可测试；不直接删除 Codex cache。
4. **GitHub pipeline 分流**：把 release-impact 判定做成 reusable pipeline 的单一输入；非发布依赖 PR 不检查 tag/release intent，发布 PR 完整检查；为两类 PR 加 workflow 回归测试。
5. **编码与文档**：测试 PowerShell/Node/MCP 的 UTF-8 边界；更新安装、排错、验收清单、路线图和 release notes，使“发布交付”与“本机 provider 验收”分层写清。
6. **版本与发布面**：同 PR 更新 release intent、版本面、变更日志、release notes 和最终 zip 验收；合并后只允许 `Release On Main` 发布同一 artifact。

### PR 前验收标准

- 所有既有相关测试与新增故障注入通过；MCP 源码、bundled plugin 与最终 zip 三层合同一致。
- release-impact 与 dependency-only 的 GitHub Actions fixture/测试各通过一次；当前 #24/#25 在修复分支基础上能重新通过真实 CI，再判断依赖是否要合并。
- 使用隔离 profile 验证新插件合同、health、lane/result 和文字编码；不污染稳定安装。
- PR 描述明确：自动发布策略、版本/tag、发布资产、合并后唯一动作、普通用户下载验证方法和本机 host 验收边界。
- 合并后 release run 成功、远端下载复验成功即为“产品已交付”；Desktop 刷新/当前 generation canary 为单机 `needs_user_action`，不得再被包装成同版本收口事故。

## 8. 规则调整建议

### 项目规则：应在下一大 PR 直接落实

1. **验收状态分层**：任何状态输出都必须区分 `artifact_delivered`、`host_loaded`、`provider_ready`、`job_terminal`、`supervisor_accepted`；禁止用一个 `ready` 覆盖全部含义。
2. **canary 证据原则**：readiness 只能来自当前 generation 的真实 canary；仓库清洁度是独立观察，不能因外部 drift 否定 provider proof。
3. **流水线单一分流**：release-impact 判定必须由 reusable pipeline 计算一次并传给所有后续门禁；非发布 PR 绝不能被要求复用已存在 tag。
4. **状态终态原则**：`process_exited`、`timed_out`、`watcher_failed` 等不属于 active；“等待 Codex 验收”不等于“worker 仍在运行”。
5. **收口边界**：公开 Release 的 artifact-first 下载复验通过后，发布收口结束；本机 host/credential/provider 问题只能记录为单机验收结果，除非它揭示了已发布 artifact 的确定性缺陷。

### 全局规则候选：仅建议，暂不改写

可形成一条跨项目的短规则：**安全门禁阻断时，先区分“门禁实现错误”和“外部能力尚未验证”；只做一次受控真实尝试，记录底层证据，绝不为继续流程伪造通过状态。**

它来源于本项目连续出现的误解，适用于其他需要账号、设备、CLI 或外部 worker 的项目；是否写入全局规则应在本 PR 验证后再决定。

## 9. 外部调研如何影响本方案

| 来源 | 可确认的实践 | 对本项目的采用 |
| --- | --- | --- |
| VS Code Extension Testing | 集成测试运行在独立 Extension Development Host；可使用独立 user data，不能把正在运行的宿主当成唯一可测对象 | 把隔离 profile 合同测试与真实 Desktop host 验收分开 |
| MCP Inspector 官方文档 | Inspector 可检查连接、能力协商、工具 schema、定制输入、执行结果和错误边界 | 继续保留 bundled protocol smoke；补工具/参数/错误输出契约测试，不以协议 smoke 代替 Desktop 或真实 worker |
| Google SRE Canarying Releases | canary 是有限时间的局部验证；信号必须可归因，控制面与被测面要区分 | provider canary 只回答“这个 tuple 是否可用”，不拿无关主仓库变化否定它；drift 成为独立指标 |
| GitHub Artifact Attestations | 发布物可以由精确构建来源和可验证的资产绑定 | 保留并强化当前同一 artifact 构建、上传、下载复验；后续可评估 GitHub attestation，但不拿它替代运行时验收 |
| OpenAI Codex Plugin/MCP 文档检索 | 搜索结果显示插件向新任务提供 Skill/MCP 工具，MCP 配置在同一 Codex host 间共享 | 新任务用于观察已刷新 host；“只新开任务不重启 host”仍不能替代 host 刷新 |

外部来源均已通过 KnowledgeRadar 路由。OpenAI 官方正文抓取受 403 限制，故该项只采用搜索摘要可确认的边界，不做超出文档的推断。

## 10. 真实验收执行结果与下一步

本报告完成后，已在一个干净 worktree 的新 Codex 任务中执行一次只读真实验收；worker 提示词保持为一句自然语言，没有塞入验收规程。结果是：

- 当前原生 MCP 确认为 `0.7.1-alpha`，marketplace、缓存和 runtime contract 一致。
- 合法 dry-run 成功，路由为外部 Qoder readonly worker。
- 真实派工严格只尝试一次，在 worker 启动前被 `Runtime generation health is blocked` 拒绝；没有 `job_id`、lane、项目运行产物或仓库改动。
- 根因是 readiness 文件仍属于 `0.7.0-alpha`，而当前运行 generation 是 `0.7.1-alpha`。旧 proof 不得授权新 generation；本轮只读边界下没有手写 readiness、receipt 或伪造 canary。

因此结论不是“provider 已失败”，而是“本机当前 generation 尚未完成真实 provider 验证”。这个结果直接成为 `0.8.0-alpha` PR 的输入：修正 canary 的并发 drift 语义、终态展示、UTF-8 解码和 CI 分流；合并后的公开 Release 仍由唯一的 `Release On Main` 自动交付。新版本安装到本机后，再按一次正式 canary + 一次简短真实只读审计完成单机验收；它不再形成同版本收口补丁。
