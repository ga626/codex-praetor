# Codex Praetor 发布前验证与开箱即用重构方案

日期：2026-08-04
性质：调研与实施规划；本文件不修改产品代码、不创建 PR。
产品基线：`origin/main`，提交 `5a8ca442058c442abb99bad99b0a04e268737922`。

## 先说结论

现在的流程把三件不同的事混成了一件：

1. **发布包有没有做对**：应在发布前用本地/CI 的无积分测试验证。
2. **某个 provider 在某个账号、CLI、模型和权限下能否真的干活**：只在这组条件真的变化时，做一次受控真实任务；不能每次版本号变化就重新烧积分。
3. **某台用户电脑是否完成安装和宿主刷新**：只能在那台电脑上观察，不能预先替用户完成，也不应要求用户运行 canary 才能开始工作。

目标不是“让每个用户先验证自己”，而是：用户安装、刷新 Codex 后，直接用自然语言下达真实任务。若 provider 已按官方方式登录，第一条低风险真实任务就是正常使用，同时自动留下这台机器的可用性证据。canary 只保留给排障，不再是使用前置条件。

发布维护者也不应在每个 PR 后重复两家 provider 的 canary 加两条真实任务。绝大多数发布包、文档、UI、工作流和合同变化可以在不调用 provider 的情况下验证；只有 provider 实际接入面变化才需要一次真实任务。正式 Release 从已验证的同一不可变 ZIP 提升，不在合并后重新做 provider 消耗测试。

## 一、现在为什么会重复花积分

### 1. 当前链路

当前候选预检 `scripts/verify/invoke-release-candidate-preflight.ps1` 已覆盖：静态合同、MCP 测试、最终 ZIP、ZIP 确定性、ZIP 内运行时、发布证据和隔离 closeout。这些检查本身不需要真实 provider 调用，应该继续保留。

但 provider readiness 目前同时绑定了 `generation_id`、runtime contract 和 tuple。每发布一个新 generation，旧证据就不再匹配。更严重的是，`scripts/dispatch/invoke-codex-praetor.ps1` 在创建 worker 前会拒绝没有 readiness 的 tuple；而 `record-codex-praetor-readiness.ps1` 又只能在 worker 成功结束后写入证据。结果是用户想开始第一条真实任务时被迫先跑 canary。

这与安装文档和排错文档的承诺相矛盾：它们都写着“第一次真实计划任务自动完成首用 bootstrap”。本次 `0.16.23-alpha` 的实测也复现了这个矛盾：宿主身份已正确，health 因新 generation 无 readiness 阻塞；只有手动运行两家 canary 后，真实任务才可派发。

### 2. 这不是安全所必需的

真正必须拦住的是：未安装/未刷新插件、错误 artifact、非法模型、越界权限、认证资料访问、不可逆外部动作、以及失败结果进入主项目。它们都可以靠安装身份、合同、worktree、权限档案、结果验收和合并门禁控制。

“先额外做一条空任务，才能允许第一条真正任务”只证明一次同一条连接可用；它不比真实任务本身更能保护主项目，却额外消耗时间和积分。

## 二、用户最终应该经历什么

### 普通用户（目标体验）

1. 下载并执行安装器；安装器校验 ZIP hash、写入 marketplace，并提示一次刷新 Codex。
2. 刷新后直接说“开启执行官模式”或直接让 Codex 拆分并外派任务。
3. Codex 自动读取运行时身份和任务合同；已登录的 provider 直接接第一条**真实、低风险、隔离**任务。
4. 该任务成功后自动记录本机 provider tuple；失败则给出简短失败类别和下一步，不把半成品合并。

用户不需要：运行内部 canary、理解 readiness、手工写 `runtime_info`、累计三条测试任务，或为了证明产品能用先耗完积分。

### 发布维护者（目标体验）

1. PR 内完成所有可离线完成的测试和最终 ZIP 验真。
2. 只有 provider 接入兼容指纹发生变化时，才做一次最小真实任务；同一条真实任务既验证连接，也验证正常任务闭环，不再额外加 canary。
3. 从该已验证 ZIP 的 SHA 直接提升到 Release；main 只发布、下载复验和做供应链证明，不再重新烧 provider 积分。
4. 维护者可做一次本机安装/宿主观察作为运行记录，但它不是要求普通用户重复的“发布后测试关”。

## 三、哪些事能在发布前证明，哪些不能

| 问题 | 正确验证位置 | 是否需要积分 | 是否可替用户完成 |
| --- | --- | ---: | --- |
| 源码、schema、路径、版本面、任务合同 | PR 定向测试 | 否 | 是 |
| ZIP 内容、hash、确定性、bundled MCP、runtime contract | PR 最终 artifact | 否 | 是 |
| 安装器把 ZIP 安装到隔离 marketplace、官方 `plugin add` 可见 | PR 的隔离用户目录 | 否 | 是 |
| 当前 Desktop 是否真的加载了该插件 | 发布候选的维护者宿主，或用户本机 | 否 | 不能替每个用户完成 |
| provider CLI/模型/连接能真实完成任务 | 兼容指纹变化时的一次最小真实任务 | 是，最少一次 | 不能替用户账号完成 |
| 用户账号是否已登录、是否有额度 | 用户第一条真实任务 | 取决于 provider | 否 |

因此，“收口后绝不会再有任何本机观察”不可能对所有用户成立；不同电脑的登录、CLI 和宿主缓存是各自状态。但可以做到：**公开产品已经完成其应完成的交付验证，用户不再承担开发者测试；用户第一条任务是生产使用，不是测试。**

## 四、建议的技术路线

### A. 把验证拆成三层，并给每层明确预算

**零积分层（每个相关 PR）**

- 静态合同、版本面、公开入口、生成路径和 task packet 路径存在性测试；任务范围必须从 manifest 生成，禁止手写会漂移的文件路径。
- 目标 ZIP 的 hash、确定性、canonical header、zip 内 MCP `runtime_info` 和 fixture transport 测试。
- 使用 Qoder/CodeBuddy 的本地协议夹具验证：解析、取消、状态、失败分类、边界拒绝、ledger 写入和恢复。夹具只能证明产品逻辑，不能冒充真实 provider 成功。
- 隔离 `UserProfileRoot` 的安装测试：安装器、marketplace 条目、官方 `codex plugin add` 与 `codex plugin list`。不碰真实 stable 和认证资料。

**有限真实层（只在兼容指纹变化时）**

- 定义 `provider_compatibility_fingerprint`：provider、CLI hash、固定模型、连接方式、permission profile、task kind、runner bundle hash、解析/状态协议版本。
- 文档、release note、ZIP 写入器、非 provider UI、发布工作流等变化不改变该指纹，不要求真实 provider 重跑。
- adapter、runner、CLI hash、模型、权限、连接方式、解析或恢复逻辑变化时，只要求受影响 provider 一条真实、只读、隔离任务；它取代“canary + 再做一条审计”的重复组合。
- 真实任务必须仍由 Codex 看 completion、stdout/stderr、worktree、范围和独立检查后写 `accepted`；一次失败不能用自动重试掩盖。

**用户/宿主观察层（非发布门禁）**

- 用户安装后，自动/简短地显示插件已加载的版本；不要求用户手动理解 SHA 或运行 canary。
- 没有当前 provider 证据时，仅允许第一条低风险、只读、显式合同的真实任务进入 bootstrap；不允许用它直接改代码、改认证、改生产或做不可逆动作。
- 该真实任务成功后写入 tuple 证据；失败时保留失败分类并让 Codex换 provider、缩小任务或提示用户完成官方登录。

### B. 修复 bootstrap 的逻辑顺序

1. 给计划任务增加 `bootstrap_eligible`：仅 `readonly + local_audit/read_only_diagnosis + 明确允许路径 + 无网络 + 无外部动作` 可为真。
2. readiness 缺失时，允许这一条真实计划任务创建隔离 worktree；其成功 completion 才写 `real_user_task_bootstrap`。
3. 其他任务仍需要匹配 tuple：编辑、测试执行、提升权限、不同模型或不同连接方式不能借 bootstrap 绕过。
4. `test-provider-capability-canary.ps1` 改为诊断入口；文档不再把它写成首用步骤。

这正好兑现现有用户文档的承诺，也比当前“先拒绝、后才有机会写证据”的实现逻辑一致。

### C. 不再让每次 generation 清空真实能力

readiness 的有效性不应由普通版本号决定，而由上面的兼容指纹决定。generation/runtime contract 仍用于判断插件是否已正确加载；它们不应自动否定一条未受发布改动影响的 provider 真实能力记录。

安全边界是：只要 runner bundle 或任一真实派工相关合同变化，兼容指纹必变，旧记录立即失效并要求一条新的真实任务。这样既不会把旧连接证据误用于新连接，也不会因为改了 README 或 ZIP 元数据而消耗两家 provider 积分。

### D. 把“正式发布后发现问题”前移

发布流程改为“候选先验，main 只提升同一物件”：

1. PR 构建唯一候选 ZIP 和 SHA；所有零积分测试对它执行。
2. 需要时，在隔离 profile 安装这个候选 ZIP，并用官方 plugin CLI 做安装身份测试。
3. 需要真实 provider 时，在候选阶段完成那一条受影响 provider 任务，记录 compatibility fingerprint 与 artifact SHA。
4. PR CI 复核候选提交、候选 ZIP、证据和 fingerprint；不在 PR CI 首次发现可重复的 release 问题。
5. main workflow 只提升该同一 ZIP、生成 tag/Release、远端下载验 SHA/attestation。它不再次运行 provider 测试。

真正的 Desktop 宿主加载只能在实际 Desktop 进程中观察。若要把维护者这一项也前移，可在**公开前**用候选 ZIP 更新维护者的 marketplace、刷新一次 Desktop，并核对 `runtime_info`；公开时只允许提升同 SHA 的 artifact。它能大幅减少发布后才发现宿主问题，但仍不能代表所有用户的账号和机器。

## 五、外部调研给出的依据

1. VS Code 官方把不依赖宿主的单元测试与在独立 Extension Development Host 运行的集成测试分开；集成测试可在 CI 中运行。这支持“少量真实宿主测试，而不是把它转嫁给每个用户”。[Testing Extensions](https://code.visualstudio.com/api/working-with-extensions/testing-extension)
2. GitHub 官方建议为用户实际下载/运行的软件生成并验证 artifact attestation，而不是为频繁的测试构建逐一签名。这支持“把同一不可变发布包作为真相”，而不是在发布后重新构造或反复试跑。[Artifact attestations](https://docs.github.com/en/actions/concepts/security/artifact-attestations)
3. contract testing 的常见做法是用 mock/fixture 快速验证交互合同，再以少量真实 provider 验证补足差异；mock 不应冒充真实端到端成功。这与本项目“夹具负责逻辑、真实任务负责 provider”的边界一致。[PactFlow 的说明](https://pactflow.io/blog/ai-automation-part-1/)

这些资料不支持“完全不要真实测试”；它们支持把高成本真实测试变成少量、按风险触发的证据，而不是每次发布的固定仪式。

## 六、单 PR 实施计划

建议只做一个发布影响 PR：**发布前验证与开箱即用重构**。它一次收齐下列共同根因，不再拆成零碎 PR。

### 做什么

1. 新增 provider compatibility fingerprint、证据 schema 与迁移读取逻辑。
2. 修复 bootstrap 顺序：允许一条受限真实用户任务建立首用证据；取消“无 readiness 一律拒绝”的死锁。
3. 将 canary 降级为显式诊断工具；移除“每个 generation 必须两家 canary + 两条真实任务”的发布要求。
4. 为最终 ZIP、安装器和任务合同路径增加无积分测试；生成/校验审计路径 manifest，避免本次人工写错 `plugin/release-generation.json` 与 `mcp/runtime-contract.json` 这类路径。
5. 将发布工作流改为候选 artifact 先验、main 仅同 SHA 提升和远端验真；增加“实测 provider 是否必要”的变更分类和预算回执。
6. 重写用户安装、首用与排错文档：普通用户不运行 canary；真实任务失败时给人话原因和可恢复动作。
7. 为发布前候选宿主观察增加可选、明确的维护者步骤；它使用同一候选 ZIP，不伪造为普通用户证明。

### 不做什么

- 不读取、迁移或打包认证、cookie、token 或 provider 数据库。
- 不承诺代表每个用户的 provider 登录、额度或网络状态。
- 不把 mock/fixture 写成真实 provider 成功。
- 不引入无限执行、无限积分预算或新的通用多 agent 平台。

### 通过标准

- 对仅文档/发布/包结构变化，真实 provider 调用数为 `0`，且最终 ZIP、安装、MCP contract、artifact SHA 仍全通过。
- 对 provider 接入变化，每个受影响 compatibility fingerprint 最多需要一条已验收真实只读任务；不再强制 canary 加第二条重复任务。
- 新安装且 provider 已登录时，用户的第一条合格低风险真实任务可直接派发并自动记录 readiness。
- 低风险 bootstrap 不能升级为编辑、外网、认证或不可逆操作；失败结果不合并。
- 用户文档不再要求 canary、三条历史记录或手工 readiness 操作。
- `Release On Main` 不再运行额外 provider 验证；只发布、attest、远端下载验 SHA 和可审计回执。

## 七、实施前需要接受的现实边界

可以承诺：发布包正确、安装器正确、插件可被宿主识别、受影响 provider 的连接已被真实验证、用户第一条任务不是测试任务。

不能诚实承诺：在用户尚未登录 provider、没有额度、网络被拦截或本机 CLI 被卸载时，产品仍能替他完成真实派工。正确产品行为是让这些情况清楚可见、可恢复，并绝不把失败结果进入主项目。

## 八、推荐裁决

按本方案实施一个 PR。它解决的是同一条问题链：**把“证明产品可交付”的工作前移、无积分化和不可变 artifact 化；把“某用户能否开始使用”的工作变成真实首用，而不是强制测试。**
