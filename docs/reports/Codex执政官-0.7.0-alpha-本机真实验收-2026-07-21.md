# Codex 执政官 0.7.0-alpha 本机真实验收

> 验收日期：2026-07-21。报告记录的是 `v0.7.0-alpha` 已发布版本在本机的只读验收结果；其中的运行态时间戳按证据原样保留。

## 一、验收范围与边界

- 项目：`D:\Projects\CodexPraetor`
- 目标：只读验收 `0.7.0-alpha` 发布后，本机 Codex host 是否已经加载，以及正常真实派工是否可用。
- 路径：`intent/route → runtime_info → health → dry-run → 一次 bundled capability canary → health 复查 → 一次真实只读派工 → worker 结果/日志 → 库存与维护状态`。
- 写入边界：未改代码、未改 `active.json`、未手工编辑或伪造 readiness；只产生 `.codex-praetor` 正常派工产物和本报告。
- 仓库基线：开始验收时工作树干净；`HEAD`、本地 `main`、`origin/main` 均为 `726fb40a65f6e9c3af711ad599ebdcea59457a68`。当前检出分支名为 `codex/runtime-health-authority`，但提交与 `main` 完全相同，因此基线内容就是当前 `main`。

## 二、最终结论

| 判定层级 | 结论 | 关键证据 |
| --- | --- | --- |
| 公开已交付 | **是** | 本地保留的远端下载复验 ZIP 与 sidecar SHA256 一致：`281608c25a4adc226d9ff179d9b24e61553a0b49346b1207fbb62820872a80c6`；下载包 generation 为 `0.7.0-alpha--726fb40a65f6--7fa085dc8fe4`。本轮未再次联网下载。 |
| host 已加载 | **是** | 原生 `runtime_info` 返回 `0.7.0-alpha`；运行根目录为 `C:\Users\ga990\.codex\plugins\cache\personal\codex-praetor\0.7.0-alpha`，进程 PID `75660`。 |
| dry-run 可用 | **是** | 原生 dry-run 成功，`exit_code=0`，路由到 `qoder / qoder-night-cheap / Qwen3.7-Plus`，权限为 `local-audit-v1`。 |
| provider CLI 可执行 | **是** | bundled canary 启动 `codebuddy / codebuddy-free / hy3`，worker `exit_code=0`，返回 `CODEX_PRAETOR_CAPABILITY_CANARY_OK`，stderr 为空，worker worktree 干净。 |
| 正常真实派工可用 | **否，当前 blocked** | 原生 `health` 为 `blocked`；唯一一次正常真实只读派工在创建 job 前被 runtime health 门禁拒绝。 |

**总判定：`0.7.0-alpha` 已公开交付，当前 Codex host 也确实加载了 `0.7.0-alpha`，但产品的正常真实派工路径仍不可用。阻断不是 provider CLI 不能运行，而是运行中 health 仍错误地用旧 `active.json` 的 `0.4.1-alpha` generation 校验当前 readiness。**

## 三、逐步验收结果

### 1. Intent 与 route

- 单独对工作任务文本做路由时，因为文本本身没有“外部 worker/执政官”词，返回 `no_delegation`，置信度 `medium`。
- 将委托上下文补全为“用 Codex 执政官外部 CLI worker 真实只读派工”后，原生路由返回：
  - `route=codex_praetor_external_worker`
  - `confidence=high`
  - `matched_terms=["codex 执政官"]`
  - `native_codex_subagents_allowed=false`

结论：任务应走 Codex 执政官外部 worker，不应创建 Codex 原生 subagent。

### 2. Runtime info

- 版本：`0.7.0-alpha`
- runtime contract SHA256：`c85388889f361878dd994ea1f443522edc646ce93ab6643e00411c23b0b23d4f`
- 运行目录：`C:\Users\ga990\.codex\plugins\cache\personal\codex-praetor\0.7.0-alpha`
- MCP 目录：`C:\Users\ga990\.codex\plugins\cache\personal\codex-praetor\0.7.0-alpha\mcp`
- 运行进程：PID `75660`
- 源码、marketplace source、运行缓存的 generation 一致：`0.7.0-alpha--726fb40a65f6--7fa085dc8fe4`

结论：host 已经加载目标版本，不再是旧的 `0.6.3-alpha` host 缓存。

### 3. Health 与权威来源

两次原生 `health` 都返回：

- `status=blocked`
- `exit_code=2`
- `runtime_contract=0.7.0-alpha`
- 唯一 blocked 检查：`provider_readiness`

运行中 health 明确声明：

- `source_generation`：running bundled contract 是权威来源。
- `legacy_active_receipt`：旧 `active.json` 只是诊断项，不应阻断派工。

但底层实现与声明矛盾：

- 当前真实 readiness 文件 `C:\Users\ga990\.codex\codex-praetor-readiness.json` 已是：
  - generation：`0.7.0-alpha--726fb40a65f6--7fa085dc8fe4`
  - runtime contract SHA256：`c85388889f361878dd994ea1f443522edc646ce93ab6643e00411c23b0b23d4f`
  - provider/model/permission/task：`codebuddy / hy3 / local-audit-v1 / local_audit`
  - status：`passed`
  - entries：1 条，generation 同样是 `0.7.0-alpha`
- 旧 receipt `C:\Users\ga990\.codex\codex-praetor-releases\stable\active.json` 仍是：
  - version：`0.4.1-alpha`
  - generation：`0.4.1-alpha--4c882418c999--63c626d5a916`
  - runtime contract SHA256：`2c0f037de74e40198a49ad5ae5a0ca5718c213050bec8fda475894148700053c`
- 运行中 `get-codex-praetor-health.ps1` 虽把该 receipt 标为 legacy diagnostic，却在 provider readiness 校验时继续把 `receipt.generation.*` 传给 `Test-CodexPraetorProviderReadiness` 作为 `ExpectedGeneration` 和 `ExpectedRuntimeContract`。
- 因此 health 输出的“readiness generation 与当前 generation 不一致”中的“当前 generation”，实际是旧 receipt 的 `0.4.1-alpha`，不是正在运行的 `0.7.0-alpha`。

**权威判断：本轮应以 running generation `0.7.0-alpha` 为权威；`active.json` 是旧诊断收据。当前 blocked 是 health 权威选择实现错误，不是当前 readiness 缺失。**

### 4. Dry-run

原生 `codex_praetor_dispatch_dry_run`：

- `ok=true`
- `exit_code=0`
- provider：`qoder`
- tier：`qoder-night-cheap`
- model：`Qwen3.7-Plus`
- permission：`local-audit-v1`
- task kind：`local_audit`
- run mode：`blocking`
- contract hash：`6847126f9a9ff4f6d9d8b3fe17c8f3ff176061f21214828e5464a94994b05cb8`
- 只预览命令，没有创建该审计任务的 job。

结论：路由、配置解析和命令生成可用。

### 5. Bundled capability canary

按补充边界只执行了一次：

```powershell
& 'C:\Users\ga990\.codex\plugins\cache\personal\codex-praetor\0.7.0-alpha\skills\codex-praetor\scripts\test-provider-capability-canary.ps1' -Repo 'D:\Projects\CodexPraetor' -Provider codebuddy -TaskKind local_audit -Apply
```

真实 worker 结果：

- job：`20260721-031724-codebuddy-codebuddy-free-737c1c35`
- provider/tier/model：`codebuddy / codebuddy-free / hy3`
- mode：`readonly`
- generation：`0.7.0-alpha--726fb40a65f6--7fa085dc8fe4`
- runtime contract SHA256：`c85388889f361878dd994ea1f443522edc646ce93ab6643e00411c23b0b23d4f`
- worker `exit_code=0`
- stdout 包含 `CODEX_PRAETOR_CAPABILITY_CANARY_OK`
- stderr 为空
- worktree `D:\Projects\CodexPraetor\.codex-praetor\worktrees\cw-codebuddy-free-737c1c35` 干净

canary 总体仍返回失败：

```text
Canary changed the main checkout status.
```

原因：canary 启动前主检出干净；worker 运行期间，主检出出现与本轮无关的并发未提交修改。脚本在写 readiness 前执行主检出前后状态一致性检查，检测到变化后主动抛错。因此：

- 真实 provider canary 本身成功；
- 本次 canary 没有写 readiness；
- 不重试，符合“只执行一次”的补充边界；
- readiness 文件的现有 `0.7.0-alpha` 内容早于本次 canary，不是本次失败后伪造或手工写入。

### 6. 一次正常真实只读派工

等价复现命令如下；本轮只执行一次：

```powershell
& 'C:\Users\ga990\.codex\plugins\cache\personal\codex-praetor\0.7.0-alpha\skills\codex-praetor\scripts\invoke-codex-praetor.ps1' `
  -Provider auto `
  -Repo 'D:\Projects\CodexPraetor' `
  -Task '审计 D:\Projects\CodexPraetor 当前 main 的“发布后本机是否真实可用”，只读，不改代码。输出一份本地报告：版本、health、dry-run、真实派工、阻断点、下一步。' `
  -Mode readonly `
  -TaskKind local_audit `
  -RunMode blocking `
  -MaxTurns 8 `
  -TaskId 'local-real-acceptance-0-7-0-alpha' `
  -Acceptance '只读审计；必须报告版本、health、dry-run、真实派工、阻断点和下一步；不得修改代码。' `
  -NoNotify
```

原生 MCP 返回：

- `ok=false`
- `exit_code=1`
- `job_id` 为空
- `job_dir` 为空
- `command` 为空
- 未启动目标审计 worker

精确错误：

```text
Runtime generation health is blocked. Repair the installed plugin/Skill/cache generation in the selected profile before real dispatch.
```

结论：正常真实派工在 job 创建前被 health 门禁拒绝；未重复尝试。

## 四、worker 结果与日志

canary worker 证据：

- job 根目录：`D:\Projects\CodexPraetor\.codex-praetor\jobs\20260721-031724-codebuddy-codebuddy-free-737c1c35`
- `job.json`：任务、provider、generation、contract、命令和工作树。
- `completion.json`：`process_exited`、`exit_code=0`、stderr 为空。
- `stdout.log`：包含只读说明和 `CODEX_PRAETOR_CAPABILITY_CANARY_OK`。
- `stderr.log`：0 字节。
- MCP `codex_praetor_result` 分类为 `unknown_worker_state`，因为 `evidence_state=evidence_missing`、`governance_state=awaiting_supervisor`；这不否定进程和 marker 成功，但说明 durable job 的完成态分类仍未收敛。

正常审计派工没有 job 或日志，因为在启动前被门禁拒绝。

## 五、次要问题与库存

### 1. 旧 active receipt

- `active.json` 仍记录 `0.4.1-alpha`。
- 它不应再决定运行中插件的 generation，但当前 provider readiness 路径仍引用它，造成主阻断。

### 2. Generation retirement

- `total=34`
- `pending=0`
- `blocked_by_process=0`
- `deferred=34`
- `deleted=0`

这些是延迟保留项，不是本轮主阻断。

### 3. Runtime inventory

第二次 health 的库存计数：

- active：1
- retired：0
- clean+merged：21
- dirty/unmerged：6
- audit-retained：8
- test-scratch：0

库存较重，但 health 只把它标为 `degraded`，不是 blocked。

### 4. Windows 维护任务

- 任务名：`CodexPraetor-GenerationReconcile`
- `schtasks /Query` 返回：`ERROR: The system cannot find the file specified.`
- exit code：1
- health 状态：`degraded`

维护任务缺失是次要问题，不是本轮真实派工被拒绝的直接原因。

### 5. Lane 状态语义

`codex_praetor_list_lanes` 把多个已经 `process_exited` 的 job 仍标成 `active=true`。这会使“活跃 lane”展示混入已退出任务，属于库存/可观测性问题，不是本轮门禁根因。

### 6. 验收期间的并发工作树变化

本轮开始时工作树干净；canary 运行期间首先出现 9 个 health/readiness 相关未提交修改文件，这正是 canary 报告 `Canary changed the main checkout status.` 的触发条件。

到本报告最终核验快照时，并发改动已继续扩大；排除本报告后，共有：

- 39 个 tracked modified 文件；
- 2 个其他 untracked 文件：`docs/release/release-notes-0.7.1-alpha.md`、`scripts/verify/test-running-generation-health-proof.ps1`；
- 修改范围已经覆盖版本面、MCP、插件、发布脚本、文档和 health/readiness 测试，明显属于另一条正在进行的 `0.7.1-alpha`/health authority 工作流。

本轮没有修改、恢复或覆盖这些并发文件。该快照只说明验收期间存在共享工作区并发写入；这些未提交内容不能作为已发布 `main`、当前运行缓存或本轮验收通过证据。

## 六、下一步

1. 完成并验证“running generation 是 health/provider readiness 唯一权威”的修复，禁止 legacy `active.json` 反向决定 `ExpectedGeneration`。
2. 在干净且无并发修改的主检出上，重新发布新版本代际；不要原地覆盖 `v0.7.0-alpha`。
3. 新版本 host 加载后，先确认：
   - `runtime_info` 是新版本；
   - 当前 readiness 与 running generation/contract/tuple 一致；
   - `health` 至少不再 blocked；
   - 正常 `codex_praetor_dispatch` 能创建 job、worker 返回结果、`codex_praetor_result` 能给出明确完成分类。
4. 单独处理维护任务缺失、历史库存与 `process_exited` lane 仍显示 active 的可观测性问题；这些不应混入本次 health 权威修复。

## 七、证据索引

- 运行合同：`C:\Users\ga990\.codex\plugins\cache\personal\codex-praetor\0.7.0-alpha\runtime-contract.json`
- 运行 generation：`C:\Users\ga990\.codex\plugins\cache\personal\codex-praetor\0.7.0-alpha\release-generation.json`
- marketplace source generation：`C:\Users\ga990\plugins\codex-praetor\release-generation.json`
- 当前 readiness：`C:\Users\ga990\.codex\codex-praetor-readiness.json`
- 旧 active receipt：`C:\Users\ga990\.codex\codex-praetor-releases\stable\active.json`
- canary job：`D:\Projects\CodexPraetor\.codex-praetor\jobs\20260721-031724-codebuddy-codebuddy-free-737c1c35`
- 远端下载复验 ZIP：`D:\Projects\CodexPraetor\.codex-praetor\closeout-remote-0.7.0-alpha\codex-praetor-setup-0.7.0-alpha.zip`
- ZIP sidecar：`D:\Projects\CodexPraetor\.codex-praetor\closeout-remote-0.7.0-alpha\codex-praetor-setup-0.7.0-alpha.zip.sha256`
