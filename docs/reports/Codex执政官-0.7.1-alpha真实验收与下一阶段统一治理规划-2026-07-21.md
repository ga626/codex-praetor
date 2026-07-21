# Codex 执政官：从“只读试跑”到真实改码验收的统一计划

> 日期：2026-07-21
> 性质：只读考古、外部调研与执行设计；本文不修改产品运行态、provider 凭据、readiness 或缓存。
> 面向：希望判断“现在该不该提 PR、发布后怎样真验收、失败后会不会又变成收口补丁”的读者。

## 先说结论

**当前 `0.8.0-alpha` 分支应该现在提交 PR，不再把真实改码验收继续塞进这一个 PR。**

这不是放弃验收，反而是把两类事情分开，避免再次混乱：

1. 当前 PR 修的是“发布、canary、任务状态和 CI 怎样正确工作”。它已经完成本地制品验证并通过远端 CI。
2. 真实改码验收要验证的是“普通用户拿到已发布插件后，外部 worker 能否在隔离仓库里真正修改代码并把证据交回来”。它必须基于公开发布的 `0.8.0-alpha` 制品和当前代际的真实 provider proof 才有意义。
3. 所以先合并并让自动发布完成；发布收口只做公开制品的下载复验。随后再做本机 provider 激活与真实改码验收。它们是**发布后的单机验收**，不是同版本的发布尾巴，更不是为收口准备的补丁。
4. 如果真实改码验收发现确定性的产品缺陷，再把同一条链路的问题集中成下一份完整 PR；如果只是登录、权限、CLI 或 provider 不可用，则标为本机环境问题，不误报为发布失败或产品代码缺陷。

这套安排回答了一个容易混淆的问题：**产品已交付**证明 GitHub 上的用户已经能下载正确制品；**本机真实派工通过**证明这台机器、这个账号和这个 provider tuple 也能完成工作。前者不能等后者，后者也不能伪造前者。

## 1. 当前到底是什么状态

| 项目 | 真实状态 | 说明 |
| --- | --- | --- |
| 当前分支 | `codex/runtime-acceptance-governance` | 已推送至远端 |
| 当前提交 | `c408067` | 包含 `0.8.0-alpha` 的治理修复和发布面更新 |
| 工作树 | 干净 | 本报告重写前没有未提交改动 |
| 远端 CI | 通过 | [run 29813789807](https://github.com/ga626/codex-praetor/actions/runs/29813789807) 成功 |
| GitHub PR | 尚未创建 | 因此尚未合并、尚未发布 `0.8.0-alpha` |
| 公开产品 | `0.7.1-alpha` 已交付 | 不应把它误称为 `0.8.0-alpha` 已交付 |

当前分支已修复的重点是：canary 不再把别的写入者造成的仓库变化错误归咎于自己；已退出或超时的 worker 不再伪装成仍在运行；PowerShell 到 MCP 的 UTF-8 分段输出有回归保护；依赖更新 PR 不再误走 release tag 门禁。它还同步了版本、release intent、文档、测试和最终 zip 验收。

## 2. 上一次真实验收做了什么，为什么没有成功

上一次验收不是“worker 做坏了”，也不是“只读任务就没价值”。它完成了一个必要但不充分的检查：确认 `0.7.1-alpha` 已被 Desktop 加载、安装源和 runtime contract 一致、dry-run 可用，并且只真正尝试了一次派工。

真实任务在创建 job **之前**被安全门禁停止。原因是运行 generation 已是 `0.7.1-alpha`，而本机只有 `0.7.0-alpha` 的 provider readiness。旧版本的成功记录不能替新版本、不同合同、不同 CLI 或不同权限状态背书，这个 fail-closed 行为本身是正确的。

因此，当时没有产生 `job_id`、lane、worker diff 或 completion。它不能被称为“真实 worker 执行失败”，更不能把手写 readiness 当作解决办法。真正需要修的是：让一次已成功执行的 canary 不会因为主仓库被别的流程同时改动而丢失自身 provider proof；这正是当前 `0.8.0-alpha` PR 已经处理和测试的内容。

## 3. 为什么现在不能直接做“更破坏性的真实改码验收”

用户想要的方向是对的：下一次不应只让 worker 读文件，而要让它在可丢弃环境中读代码、改代码、跑测试、交回 diff，并让 Codex 独立验收。

但它不应现在在未发布分支上进行，原因有四个：

- **不能代表用户制品。** 当前源码分支并不是普通用户安装到的 zip；在这里成功，只能证明开发检出可用，不能证明发布包可用。
- **当前 generation 还没有真实 proof。** 强行继续只会再次被正确的 health gate 拦住；手写 proof 会让安全门禁失去意义。
- **会把 PR 无限扩容。** 当前 PR 的范围已经是完整的运行态治理与发布修复；把一次探索性压力验收及其所有发现继续塞入，会回到“为了收口不断开补丁”的旧模式。
- **失败归因会混在一起。** 未发布源码、发布逻辑、账号登录、外部 CLI、模型权限和工作任务失败会彼此混淆，最后谁也无法知道真正的问题在哪。

正确顺序是：先让当前 PR 交付正确的公开制品；再对这台机器做一次可归因的激活；最后才让真实 worker 改代码。

## 4. 当前 PR 应怎样推进

这是一个发布影响 PR。现在应创建 PR，而不是继续扩大实现范围。

合并前的最后核对只需确认：目标分支仍是最新 `main`、本报告和证据侧车已纳入变更、工作树干净、PR 页面没有新的冲突或失败检查。现有本地构建、最终 zip runtime 验收和远端 CI 已是前置证据，不需要为了创建 PR 再重复一次大规模测试。

合并后，`Release On Main` 必须从精确合并提交构建并发布 `v0.8.0-alpha`，然后下载公开的 `codex-praetor-setup-0.8.0-alpha.zip` 复验同一 artifact。只有这一步通过，状态才是“产品已交付”。

如果 release workflow 失败，合法状态是“代码已合并，产品未交付（release incident）”。应重跑同一 SHA 的 workflow 或按规则处理 workflow 缺陷；**不得**为同一版本手工补传 zip，也不得新开“收口修复 PR”。

## 5. 发布后如何做真正的改码验收

这里的“更真实”不等于允许 worker 碰主仓库。它意味着让 worker 在隔离 worktree 中完成一件完整、可验证、可丢弃的开发工作。

### 5.1 第一关：当前代际激活（不是新的 PR）

进入条件：`v0.8.0-alpha` 已公开发布，并已完成远端下载复验。

执行：安装公开 zip，完全刷新 Codex Desktop，创建一个干净任务，调用 `runtime_info` 确认插件版本、合同 SHA、运行目录和 generation 一致；随后执行一次真实 provider capability canary，让系统自己写入当前 generation 的 readiness。

退出条件：health 中 provider readiness 只引用当前 generation 的真实 proof。不能手改 `active.json`、readiness、receipt 或缓存。

若失败：只取一次底层证据并分类为登录、CLI、权限/模型合同、网络、provider 运行失败或产品 gate 缺陷。前四类不是产品发布失败；最后一类才进入下一份产品 PR 候选。

### 5.2 第二关：真实项目 worktree 验收（不是新的 PR）

只有第一关通过后才开始。由调度器在 disposable linked worktree 中以 `code_change` 模式派发外部 CLI worker；主仓库、`.git`、账号文件、插件缓存和 `node_modules` 都是禁止写入区域。worktree 只用于验收，永不合并。

给 worker 的自然语言保持短，不把验收协议塞进提示词：

```text
在这个项目里完成一个小而完整的改进，修改代码并运行相关测试；完成后说明改了什么、测试结果和剩余风险。
```

外围调度器而非提示词负责限制 allowed paths、记录任务类型、版本、超时、测试命令和证据位置。Codex 最终必须独立检查：

- 真实 job、worktree 与 worker 启动记录存在；
- diff 只在允许路径内，且主仓库没有变化；
- worker 的测试确实执行，必要时由 Codex 重跑关键测试；
- completion、result、timeline 和 stdout/stderr 相互一致；
- 清理后 worktree 已解除注册、job 已归档、主工作树仍干净。

### 5.3 第三关：真实问题型 fixture 压力验收（建议与第二关同一验收窗口）

真实项目任务验证“能不能在本项目工作”；fixture 验证“是否真的能完成问题闭环”。建立一个一次性 Git fixture：初始状态有一个真实失败测试，worker 必须阅读代码、修改实现，并让该测试从 fail 变 pass。

这不是造假的“永远能通过”脚本。它要记录修改前失败、worker diff、修改后通过、completion/result/timeline、Codex 复核和清理回执。SWE-bench 的核心方法正是把模型补丁应用到真实仓库并运行仓库测试，而不是相信模型的文字回答。

## 6. 完整路线图：哪些是 PR，哪些不是

| 阶段 | 是否 PR | 目标 | 成功出口 | 失败后怎么走 |
| --- | --- | --- | --- | --- |
| PR 1：`0.8.0-alpha` | 是，现在提交 | 修复验收/发布治理本身 | 合并、同 SHA 自动发布、公开下载复验 | release incident：只重跑原 SHA 或修自动发布路径 |
| 单机激活 | 否 | 新 generation 真实 canary 与 readiness | 当前 generation 的 provider proof | 登录/CLI/权限/provider 问题留在本机；产品 gate 缺陷进入问题清单 |
| 真实改码验收 | 否 | 隔离 worktree 真实 diff + 测试 + 清理 | Codex 独立验收通过且主仓库无变化 | 收集证据，不立即补丁、不重复盲跑 |
| PR 2：验收发现的集中修复 | 仅有确定性产品缺陷时 | 修复同一链路的全部可复现缺陷与故障注入 | 新 artifact-first PR 完整通过 | 按正常发布流程，不称为 PR 1 的“收口修复” |
| 长期 eval harness | 可单独规划 | 把真实验收变成可重复的产品能力 | 固定短任务、固定 fixture、可比结果 | 逐步扩充样本，不一次性制造大平台 |

这意味着：当前 PR 合并后不会留下“产品没有发布”的尾巴；真实派工发现问题也不会偷偷变成当前版本的发布尾巴。它只会产生两种清晰结果：本机环境待处理，或下一份完整产品 PR 的明确输入。

## 7. 验收体系的边界和证据标准

没有一次测试能证明“以后绝不会出任何问题”。可执行的严谨标准是：每个可控链路都有进入条件、真实证据、退出条件和明确归因；不可控依赖不会被伪装成产品缺陷或发布失败。

| 证据面 | 必须证明什么 | 不能替代什么 |
| --- | --- | --- |
| artifact-first 发布 | 源码、构建、zip、上传和远端下载是同一 artifact | 不能证明本机账号可用 |
| host 观察 | Desktop 确实加载新 generation | 不能替代完整重启或 provider proof |
| provider canary | 此 provider/CLI/模型/权限 tuple 当前可用 | 不能证明 worker 完成业务任务 |
| worker 改码任务 | 有真实 diff、真实测试和完整生命周期证据 | 不能证明所有类型任务都可用 |
| fixture fail-to-pass | agent 能完成具体问题闭环 | 不能替代真实项目的兼容性判断 |
| 清理回执 | 隔离副作用已被回收、主仓库不受污染 | 不删除 Codex 管理的缓存或历史代际 |

为了避免“worker 说成功但其实没有完成”的老问题，验收结论至少需要四类独立证据：worker 产生的 diff、实际测试输出、控制层 completion/result/timeline、Codex 的独立复核。任意一项缺失都只能标为未通过或证据不足。

## 8. 外部调研得到的做法，以及本项目怎样采用

| 证据 | 外部做法 | 本项目采用 | 不照搬的地方 |
| --- | --- | --- | --- |
| [Git worktree 文档](https://git-scm.com/docs/git-worktree) | 一个仓库可有多个 linked worktree；实验可使用无分支的可丢弃 worktree，结束须 `remove`/`prune` | 所有真实改码验收在 disposable worktree，主工作树禁止写入；清理须检查 Git 注册也已解除 | 不把“删除目录”误当成已清理；必须用 Git 命令确认 |
| [SWE-bench Evaluation](https://www.swebench.com/SWE-bench/guides/evaluation/) | 对真实仓库应用补丁并运行测试，以容器化环境保持可复现 | fixture 使用 fail-to-pass 测试、真实 patch 与独立复核 | 不需要一开始引入 Docker 集群或完整 benchmark；先做一个小而稳定的 fixture |
| [OpenAI：系统化评估 Agent Skill](https://developers.openai.com/blog/eval-skills) | 用“短提示词 → 运行轨迹与产物 → 小检查集 → 可比较得分”而不是凭感觉判断 | 提示词短；外围记录证据；检查 diff、测试、清理、行为和效率 | 不把评分取代人工安全验收；Codex 仍是最终监督者 |
| [GitHub Artifact Attestations](https://docs.github.com/en/actions/how-tos/secure-your-work/use-artifact-attestations/use-artifact-attestations) | 构建证明可以绑定制品来源和构建过程 | 保持当前同一 artifact 的构建、上传、下载复验；后续可将 attestation 作为增强 | provenance 不能证明 provider 或真实任务成功 |
| [OpenAI 插件文档](https://developers.openai.com/codex/plugins/build) 与 [MCP 文档](https://developers.openai.com/codex/mcp) | 插件可打包 Skill/MCP；本地 Codex host 的 MCP 配置由 Desktop、CLI、IDE 共享 | 把“发布物可用”和“当前 host 已刷新”明确分层；新任务仅用于观察刷新后的 host | 不以反复新建任务替代 host 重启，也不把开发检出当安装入口 |
| [SWE-bench Live 论文](https://arxiv.org/abs/2505.23419) | 静态 benchmark 有数据污染和过拟合风险，动态真实任务仍需可复现环境 | fixture 要轮换并记录版本、环境、任务和测试；不能只看单个成功样本 | 不把外部 benchmark 分数当本项目质量结论 |

本轮外部调研由 KnowledgeRadar 先规划路线，再使用其原生正文抽取与搜索工具；没有把搜索摘要当作强证据。OpenAI 文档本轮已获得正文抽取，取代此前 403 下的摘要级引用。

## 9. 进入下一步前的清单

现在：把本报告和证据侧车作为当前 `0.8.0-alpha` PR 的文档补充，创建 PR，检查新出现的 GitHub 问题后合并。

发布收口：只验证自动 Release 是否从合并 SHA 发布，并下载公开 zip 复验；成功即“产品已交付”。

随后：完全刷新本机 host，做一次当前 generation canary；通过后在 disposable worktree 中连续完成“真实项目小改动”和“fail-to-pass fixture”两项验收；不高频轮询，只在 worker 结束后收取一次完整证据。

最后：把验收输出分为三类：`通过`、`本机/provider 待处理`、`确定性产品缺陷`。只有第三类才建立下一份集中修复 PR。这样可以获得真实、甚至有一定破坏性的验证强度，同时不污染主线、不伪造安全状态，也不会让发布收口再次变成无止境的补丁链。
