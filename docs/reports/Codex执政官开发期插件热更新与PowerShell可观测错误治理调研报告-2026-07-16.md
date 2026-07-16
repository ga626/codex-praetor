# Codex 执政官开发期插件热更新与 PowerShell 可观测错误治理调研报告

日期：2026-07-16
调查对象：`D:\Projects\CodexPraetor`、当前 Codex Desktop/app-server 运行态、Windows PowerShell 5.1、Qoder capability canary  ︱
调查边界：本轮只读调研与报告落盘；不修改代码、不删除缓存、不重启 Codex、不更新安装态、不提交或推送。

## 一、结论先行

### 1. 旧插件缓存不能作为当前开发期的“强制清除”对象

这是 Codex 当前会话模型的限制，不是 Codex Praetor 单独造成的普通文件清理问题。现场事实是：

1. 新版本 `0.2.0-alpha` 已安装，app-server 的 `config/mcpServer/reload` 可以看到新 MCP server，版本为 `0.2.0-alpha`，工具数为 17。
2. 同一个已经打开的 Codex 对话仍然调用旧缓存路径 `...codex-praetor\0.1.1-alpha\scripts\dispatch\invoke-codex-praetor.ps1`，所以旧路径仍然是当前对话的有效引用。
3. 旧目录被当前 Codex 进程占用时，强删既不可靠，也会把“运行中的引用”变成缺文件或半更新状态；删除不是热更新协议。
4. 新启动的 `codex exec --ephemeral --sandbox read-only` fresh context 已加载 `0.2.0-alpha`。严格 fresh-context 验收中 17 个 `codex_praetor_*` 工具全部可见，`missing_expected=[]`，状态为 `passed`。

因此可以解决“后续开发不能继续”的问题，但解决方式不是每次改动都退出当前 Codex，也不是每次都创建一个永久新 task：

- **代码/脚本内容变化，工具合同不变**：开发期保持一个稳定的 dev MCP registration，指向当前源码或隔离的 dev generation；通过显式 reload/下一轮调用验证即可，不删除仍可能被引用的旧目录。
- **MCP 工具名、参数、Skill/Plugin manifest 或插件缓存来源变化**：需要一次新的 Codex context 做验收。它可以是新的 CLI ephemeral context 或用户主动打开的一个固定“验收任务”，不要求每次文件编辑都新建 task。
- **正式 stable 安装/发布**：采用不可变的版本化目录并行保留，切换 active pointer/marketplace 入口；只有确认没有进程引用旧 generation 后才做垃圾回收。

在当前 Codex 版本和公开 issue 证据下，没有可靠的“由当前正在运行的 Codex 对话自我替换其已加载 Skill、插件缓存路径和模型工具快照，同时又保证该对话继续执行”的强制方案。可以 reload MCP manager，但不能把它等同于当前模型上下文、Skill 注入和旧路径句柄的同步替换。

### 2. 第二个问题是项目脚本的可修复 bug，不是 Qoder 失败

`scripts/verify/test-provider-capability-canary.ps1` 在 Windows PowerShell 5.1 中设置 `$ErrorActionPreference = "Stop"`，随后执行：

```powershell
& powershell @argsList 2>&1
$exitCode = $LASTEXITCODE
```

`git worktree add` 成功时会向 stderr 写普通诊断信息，例如 `Preparing worktree (new branch ...)`。`2>&1` 把 stderr 合并到 PowerShell success stream；在这一包装层和 `$ErrorActionPreference = "Stop"` 组合下，普通 stderr 可能先被当成异常处理，脚本还没读 `$LASTEXITCODE` 就中断。现场隔离执行 Qoder 官方 CLI 已返回 `CODEX_PRAETOR_CAPABILITY_CANARY_OK`，说明 provider 能力本身通过。

推荐的修复契约是：**stdout/stderr 分离捕获，等待子进程结束，读取并判断 `$LASTEXITCODE`，把 stderr 作为诊断保留而不是当作失败条件**。这能同时保留真实失败、普通诊断和 provider marker。不能用“吞掉 stderr”或单纯关闭 native error preference 代替退出码判断。

## 二、问题一：开发中的插件/Skill/MCP 如何更新

### 2.1 现场行为与边界

本次本机链路形成了一个可重复的四层差异：

| 层 | 现场结果 | 含义 |
|---|---|---|
| 源码 checkout | `main`/`origin/main` 为 `0a62eb7` | 项目内容是新版本 |
| app-server reload | server `0.2.0-alpha`，17 tools | MCP server/process 层可以重新发现新版本 |
| 当前已打开对话 | 仍调用 `0.1.1-alpha` 旧路径 | 当前对话/工具句柄仍持有旧引用 |
| fresh context | 17 个工具全部可见，canary passed | 新 context 可以获得新工具合同 |

这解释了用户感知的矛盾：明明已经 reload，当前对话却还像旧版本；明明旧 cache 没法删除，退出又失去当前 Codex 的连续工作能力。两者分别属于“server manager 刷新”和“conversation/tool snapshot 更新”，不是同一个状态。

### 2.2 官方 Codex 证据说明了什么

- [openai/codex#8957](https://github.com/openai/codex/issues/8957)：`mcpServer/refresh` 已实现；active thread 收到 pending refresh，实际 MCP manager 在后续 turn 才重新初始化。它证明 reload 有效范围主要是 MCP manager/server 生命周期，而非立即改变当前模型已经拿到的完整 tool snapshot。
- [openai/codex#20605](https://github.com/openai/codex/issues/20605)：现有 Codex thread 无法可靠热加载本地 MCP 工具变化；fresh local probe 能看到新工具，而旧 thread 看不到；issue 中的实际 workaround 是新 thread/session。
- [openai/codex#16653](https://github.com/openai/codex/issues/16653)：当前会话修改本地 Skill/Plugin 后不会自动拾取，提出 `/reload-skills`、`/reload-plugins`；issue 记录的 workaround 是新 session。
- [openai/codex#4955](https://github.com/openai/codex/issues/4955)：MCP server 通常在 connection manager 初始化时启动，之后不会自动重启；说明“server 重启/重载”和“客户端会话状态刷新”需要分开处理。
- [openai/codex#21138](https://github.com/openai/codex/issues/21138)：Windows 上同一 `plugin.json.version` 下源内容变化可能继续使用旧 cache，当前 cache 判断主要依赖 version 目录，缺少内容/provenance 校验。
- [openai/codex#24390](https://github.com/openai/codex/issues/24390)：Windows Desktop 的已有 conversation 可能继续引用旧 cache path。
- [openai/codex#23902](https://github.com/openai/codex/issues/23902)：local marketplace、版本提升和实际 plugin cache refresh 之间可能出现脱节。
- [openai/codex#19834](https://github.com/openai/codex/issues/19834)：stale marketplace clone 与 stale plugin cache 容易混淆，用户缺少清晰的来源/版本诊断。
- [openai/codex#26934](https://github.com/openai/codex/issues/26934)：已合并的 curated plugin stale cache 清理主要针对被移除的 curated plugin，不等于任意旧 generation 都可以在运行中安全强制删除。

上述 Issue 是公开项目的实现/行为证据；其中部分仍为 open issue，不能当作已承诺的修复时间表。官方 Codex MCP、Plugins、App Server 文档说明了组件关系，但正文访问受 HTTP 403 影响，本报告将搜索摘要作为辅助证据，不把它升级为比源码和现场复现更高的证据等级。

### 2.3 哪些事情可以由 reload 解决

| 事项 | `config/mcpServer/reload` | 结论 |
|---|---:|---|
| 让 app-server 重新发现 MCP server | 可以 | 本次已现场看到 `0.2.0-alpha` 和 17 tools |
| 重建后续 turn 使用的 MCP manager | 通常可以，但有 pending/延迟边界 | 需要在后续 turn 验证 |
| 立即替换当前模型已拿到的 tool snapshot | 不能保证 | 旧对话仍可能继续使用旧工具合同 |
| 立即替换当前 Skill 内容 | 不能保证 | 官方 issue 明确记录需新 session 的 workaround |
| 立即改写当前插件 cache 路径 | 不能保证 | 已有 conversation 可能仍引用旧路径 |
| 安全删除被当前进程打开的旧目录 | 不可以 | reload 不是引用计数/文件事务机制 |

### 2.4 不需要每次改动都新建 task 的工作模型

建议把开发变更分为三类，而不是把“文件改动次数”当成“新 task 次数”：

**A. 实现内容变化，接口合同不变**

- 继续在同一开发 task 中工作。
- MCP server 使用隔离的 dev registration 或源码指向，不依赖 stable cache 的覆盖写入。
- 需要时发送一次 app-server reload；在下一个 turn 做一个轻量调用确认。
- 不删除任何仍可能被当前 Codex 引用的旧 cache。

**B. MCP 工具面或 Skill/Plugin 合同变化**

- 不必为每次编辑开 task；在一个开发批次结束后集中做一次 fresh-context native MCP canary。
- 只有在“工具名、工具参数、manifest、插件来源、Skill frontmatter、安装树”变化时，才触发这一验收边界。
- 当前开发 task 可以继续承载代码编写；fresh context 只承担“新合同是否被 Codex 看到”的验收，不承担永久的工作分裂。

**C. stable 发布 generation 变化**

- 构建新版本目录和发布 zip，保留旧 generation。
- stage、hash verify、fresh-context proof、provider readiness 通过后才 activate。
- 旧 generation 只在确认没有进程引用后异步清理；清理失败不阻塞新 generation 运行，只保留垃圾回收告警。

这套模型的关键是把“连续开发对话”和“新能力验收 context”分工。用户不需要退出当前 Codex 才能继续写代码，也不需要每次改一个文件就创建新 task；但当工具合同真的变化时，必须承认 fresh context 是当前平台的验收边界。

### 2.5 对 Codex Praetor 的工程要求

后续获得用户批准实施时，应优先评估以下方向：

1. **开发期 registration 与 stable plugin 分离**：开发期入口直接指向源码或带 generation 的隔离目录，避免把运行中的 stable cache 当作热替换目录。
2. **不可变 generation**：目录名包含版本/代际/内容身份；不在同一 version 目录原地覆盖内容。
3. **active pointer 而非 destructive replacement**：切换入口，旧目录保留；不能依赖 Windows 上对被占用目录的强制删除。
4. **合同变化触发 fresh-context gate**：把 native tool visibility、工具调用、Skill 版本和 plugin/cache provenance 记录到 receipt，而非只记录 server reload 成功。
5. **诊断命令输出四个版本**：源码版本、安装 plugin 版本、cache generation、当前 conversation/context 能看到的工具合同，避免把“reload 成功”误报成“当前对话已切换”。
6. **垃圾回收与激活解耦**：旧 generation 删除失败只进入待回收队列，不回滚或覆盖当前活动 generation；激活失败保持上一份 active receipt。

这些是本报告的实施建议，不是本轮已执行的代码变更。

## 三、问题二：PowerShell 为什么把 Qoder 成功误报成失败

### 3.1 具体根因

当前脚本 `scripts/verify/test-provider-capability-canary.ps1`：

- 第 19 行全局设置 `$ErrorActionPreference = "Stop"`。
- 第 82 行通过 `& powershell @argsList 2>&1` 启动 provider wrapper。
- 第 83 行才读取 `$LASTEXITCODE`。

在 Windows PowerShell 5.1 中，本机探针为：

- version：`5.1.19041.6456`
- edition：`Desktop`
- `$PSNativeCommandUseErrorActionPreference`：不存在

Qoder 的 `git worktree add` 成功执行时，会把 `Preparing worktree (new branch ...)` 写到 stderr。`2>&1` 将 stderr 重定向到 success stream；外层脚本的 `Stop` 可能在读完子进程退出码之前把这类 ErrorRecord 视为异常，导致 canary 失败或提前退出。真正的 provider 能力 canary 在隔离 worktree 中已返回：

```text
CODEX_PRAETOR_CAPABILITY_CANARY_OK
```

因此第 2 个问题的准确表述是：**包装器把“stderr 有内容”错误地当作“子进程失败”，而不是 Qoder 无法执行任务。**

### 3.2 为什么不能简单吞 stderr

stderr 有两种语义：

- 成功命令的进度、诊断和警告；
- 失败命令的错误信息。

PowerShell 官方 `about_Error_Handling`、`about_Preference_Variables` 和 `about_Redirection` 明确区分 native process 的 `$LASTEXITCODE` 与 PowerShell error stream；`2>&1` 会改变 stderr 的处理路径。PowerShell 7.3 引入、7.4 稳定化了 `$PSNativeCommandUseErrorActionPreference`，但本机仍是 Windows PowerShell 5.1，不能把该变量当作跨版本解决方案。

正确判定顺序应是：

1. 启动子进程并分别捕获 stdout/stderr；
2. 等待进程结束并获取 exit code；
3. exit code 非零才判定执行失败；
4. exit code 为零时允许 stderr 作为诊断输出；
5. 在 `-Apply` 模式下另外检查 marker、主仓库状态和 readiness tuple。

局部把 native invocation 的 `ErrorActionPreference` 临时降为 `Continue` 可以作为兼容性措施，但仍必须恢复原值并严格判断 `$LASTEXITCODE`。单纯设置 `$PSNativeCommandUseErrorActionPreference=$false` 也不够：旧 PowerShell 不识别它，而且即使关闭自动错误升级，非零退出仍然必须显式检查。

### 3.3 修复候选排序

| 方案 | 判断 | 原因 |
|---|---|---|
| 分离 stdout/stderr，读 exit code 后判定 | 首选 | 保留可观测性，兼容 Windows PowerShell 5.1，语义最清楚 |
| 局部 `ErrorActionPreference=Continue` + 显式 `$LASTEXITCODE` | 过渡方案 | 改动较小，但需严格限定作用域和恢复原值 |
| 全局关闭 native error preference | 不推荐 | 版本不一致，可能掩盖真正失败，且不能替代退出码判定 |
| `2>$null` | 禁止作为正式方案 | 丢失 provider、git、诊断信息，失败时难以定位 |
| 只检查 marker | 不足 | marker 可能存在于输出，但 wrapper/进程本身仍可能非零退出；必须同时检查 exit code |
| 只把有 stderr 当失败 | 当前错误行为 | 与 `git worktree add` 等正常 CLI 行为不兼容 |

### 3.4 必须覆盖的验证矩阵

未来实施修复时，至少要加入以下测试；本轮不执行修改：

| 场景 | exit code | stderr | 期望 |
|---|---:|---|---|
| 成功且有普通诊断 | 0 | 有 | 通过，诊断保留 |
| 成功且无诊断 | 0 | 无 | 通过 |
| 失败且有错误诊断 | 1 | 有 | 失败，保留 stderr 和退出码 |
| 失败但只写 stdout | 1 | 无/有 | 失败，不依赖 stderr |
| `git worktree add` 成功 | 0 | `Preparing worktree...` | 通过 |
| `git worktree add` 分支冲突 | 非零 | 有 | 失败且可定位 |
| provider 返回 marker | 0 | 任意 | apply canary 通过后再写 readiness |
| provider 非零退出但输出 marker | 非零 | 任意 | 仍失败，不能被 marker 掩盖 |
| canary 失败 | 任意 | 任意 | 不留下错误的 worktree/lock/readiness |

## 四、推荐的实际工作流

### 开发期

1. 当前 task 继续承担 Codex Praetor 的代码和文档开发。
2. 不覆盖 stable plugin/cache，不强制删除旧 generation。
3. 代码内容变更后，按需 reload MCP；不要把 reload 输出直接当成当前对话已切换的证明。
4. 每个开发批次完成后，以一次 fresh-context native MCP canary 验证新工具合同。
5. 只有工具合同或安装来源变化才触发新的 fresh context；普通实现编辑不触发。

### 发布期

1. 从最新 `main` 构建新的不可变 release generation。
2. 下载 zip 后先 stage 和 hash verify 所有本地 surface。
3. 用 fresh context 验证 17 个 native tools 和关键调用。
4. 验证 generation-matched provider readiness。
5. 通过后再 activate；旧 generation 延迟回收。
6. 下载远端 Release zip，解压并按普通用户路径复验 setup、文档、版本和关键向导行为。

### 失败处理

- reload 后旧对话继续显示旧工具：标记为 stale context，继续当前开发或开一次验收 context；不要删除旧 cache。
- 旧 cache 删除失败：标记为 deferred garbage collection；不影响新 generation 激活。
- fresh-context canary 失败：停止把新 generation 视为可交付，保留上一份 active receipt。
- PowerShell canary 报 stderr 异常但 provider marker/exit code 通过：归类为包装器观测 bug，不能把 provider 标成失败。
- provider 真正非零退出：保留 stdout/stderr、退出码和 worktree 生命周期证据，禁止只依据“有输出”或“进程启动”判定成功。

## 五、证据强度、缺口与最终判断

### 强证据

- 本机当前对话仍调用 `0.1.1-alpha` 旧 cache 路径；同一机器 fresh context 加载 `0.2.0-alpha` 并通过 17-tool native canary。
- app-server reload 返回新 server/version，但不能令当前对话立即改用旧工具句柄，这是现场行为与 Codex issue 一致。
- Windows PowerShell 5.1 的包装脚本确实把 `2>&1` 与全局 `Stop` 放在 `$LASTEXITCODE` 读取之前；Qoder 隔离执行返回固定成功 marker。
- PowerShell 官方资料明确要求区分 native exit code、stderr 和 PowerShell error stream。

### 工程推断

- 开发期最稳的生命周期模型是并行 immutable generation + active pointer + 延迟回收。
- “不让用户每次改动都新建 task”可以通过把 fresh context 限定为批次验收门，而不是编辑动作来实现。
- 当前平台没有证据表明存在一个能强制刷新 Skill、plugin cache path、模型 tool snapshot 且不丢失当前对话连续性的公开接口。

### 仍然缺少的证据

- Codex Desktop 对“当前对话已注入工具快照”的内部刷新时序没有公开稳定 API；`mcpServer/refresh` 的具体生效时点依版本可能变化。
- Windows 文件句柄的具体持有者、插件 cache 删除失败的每个句柄来源，本轮没有进行进程句柄扫描，因为用户明确要求不采取运行态行动。
- Codex 官方尚未给出 `/reload-skills`、`/reload-plugins` 的稳定公开命令或强制热替换契约；相关 issue 不能当作承诺。

### 最终判断

状态应写成：

- **问题一：有可落地的开发/发布流程解决方案，但没有“当前对话无缝强制自替换”的可靠平台能力。** 解决关键是 dev/stable 分离、generation 不可变、reload 与 fresh-context 验收分层、旧缓存延迟回收。无需每次改动新建永久 task。
- **问题二：可明确修复，根因在项目 PowerShell 包装器的 stderr 处理顺序；不是 Qoder provider 不可用。** 优先做 stdout/stderr 分离和 exit-code-first 判定，再用回归矩阵锁住行为。

本报告没有执行上述修复；它只为下一轮获得批准后的实现和验证提供边界。

## 六、研究访问路径

KnowledgeRadar 原生 MCP 路径：

- `health_check(mode="summary")`：health `ok`。
- `get_capabilities(summary=true)`：工具面 17 个工具。
- `kr_research(mode="deep_route", budget="deep")`：完成 Codex、PowerShell、provider 生命周期相关路线。
- 辅助使用 `kr_web_search`、`extract_web_page`、`search_github_repositories`。
- 当日 Tavily 额度耗尽，KnowledgeRadar 记录为降级，web 主要由 `anysearch` 提供；没有绕过 KnowledgeRadar 建立平行搜索路线。
- `get_task_status(compact=true)`：最近任务 34 completed、1 failed、1 cancelled、无 active/stale。
- `analyze_decision_logs(compact=true)`：最近 20 条决策日志 20 success、0 failure。

时间边界：外部资料按 2026-07-16 调研时可访问结果记录；公开 GitHub issue 的开放/合并状态可能继续变化，后续实施前应重新核对。
