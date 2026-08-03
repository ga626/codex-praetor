# Codex Praetor 项目规则

## 产品边界

- Codex Praetor 只让 Codex 派发边界清楚的外部 CLI 工作；Codex 规划、监督、整合和验收，不扩展成通用多代理平台。活动名称固定为 `Codex Praetor`、`codex-praetor`、`codex_praetor_`；旧名仅限历史材料。
- `plugin/` 是稳定产品，`mcp/` 是源码，`scripts/` 按职责分组，`skill/` 只是兼容镜像；仓库检出和 zip 根目录不是安装入口。稳定入口是 personal marketplace 的 `%USERPROFILE%\plugins\codex-praetor`；开发用隔离 worktree + `UserProfileRoot`。不得手改 plugin cache、认证或 provider 数据库。
- Codex 创建的开发候选只能位于本项目已忽略的 `.codex-praetor/supervisor-worktrees/<name>`；阶段夹具只能位于 `.codex-praetor/fixtures/<name>`。不得在项目父目录创建同级 `CodexPraetor-*` 目录，不得移动、清理或接管 Codex Desktop 默认 worktree 或用户显式创建的 Git worktree。
- 公开能力以 `config/public-capabilities.json` 为准：每项声明受众、入口、包内依赖、场景和故障注入。`installed_plugin` 必须从插件 MCP/Skill 完成，`release_bundle` 必须从下载包完成，`developer_only` 不得写成普通用户承诺。

## 发布与验收

- 改 `plugin/`、`mcp/`、`skill/`、安装/排错/发布路径、版本、用户体验或公开能力即为发布影响 PR；同一 PR 更新版本面、changelog、release notes、`config/release-intent.json` 与能力清单。
- PR 就绪前从最终 stage/zip 验证受影响场景和全量确定性能力矩阵；源码、`mcp/dist`、`plugin/mcp/dist`、zip、runtime contract 或 generation 任一漂移即失败。真实 provider 仅在其合同、权限、派工或恢复行为变化时，于隔离环境验证并记录真实状态。
- 发布影响 PR 的合并硬门还包括 PR 正文中的 provider evidence：CI 会把标记段落 materialize 到被忽略的 `.codex-praetor/provider-release-evidence.json`，并绑定 artifact 自己记录的生成提交或其 source tree、同一已验证 artifact SHA、当前 generation/runtime contract，分别包含 Qoder 与 CodeBuddy 各一条 Codex `accepted` 的真实任务和 accepted canary；PR merge ref 与 provider 任务的 source head 可以不同，但必须证明 Git tree 相同；合并后的 `main` 由 promotion tree 校验保证该候选 artifact 与合并内容一致。缺任一家、只提供合成夹具、只提供 process exit 0 或 artifact SHA 不一致都不得合并或发布。证据不进入源码和发布包，避免改变 artifact 身份。
- 阶段 1 的 route、plan、dry-run 和真实 worker 任务属于取证；单样本失败只记录分类并继续冻结矩阵，不得直接触发版本、Release 或 host 刷新。只有至少两条独立真实任务证明同一产品根因，才建立一个集中修复 PR。
- 共同根因 PR 的开发期只跑受影响组。版本面、候选 artifact 和全量确定性矩阵只能在范围冻结后各运行一次；候选冻结后发现的独立问题记入下一证据门，不回填当前 PR。host 刷新只属于 PR D 的用户交付链，不得作为 PR B 或阶段 1 的诊断工具。
- 对话只在阶段 1/2 事实报告、公开边界变化、PR D host 刷新或不可恢复 release incident 停下。
- main 合并后仅由受保护的 `Release On Main` 从合并 SHA 自动构建、发布和远端下载复验；同一带 SHA manifest 的 zip 贯穿运行时验收、上传、下载和 attestation。tag/draft 后失败只重跑原 run；创建 tag 前发现 workflow 缺陷才可用递增版本恢复 PR。
- PR 候选 artifact 的命名只能由 `scripts/release/get-release-candidate-artifact-name.ps1` 生成；上传、main 提升和回归检查必须共用该唯一合同，禁止在 YAML 或其他脚本手写第二套命名规则。
- main 提升同一候选 ZIP 后，若最终运行时验收依赖仓库 MCP 测试工具，发布作业必须先调用受控的 `mcp/scripts/install-mcp-dependencies.ps1`；不得假定 PR CI 的依赖目录会跨作业存在。
- release incident 的修复必须把故障纳入能力场景或故障注入；模拟 proof 不替代最终包证据。不得同版本补发、手工上传替代包或把收口缺口留给下一 PR。

## 本机与运行边界

- 公开交付由同一 artifact 的构建、bundled runtime、Release 上传和远端下载复验决定；本机未刷新不否定它。公开验真后自动下载并验真该 zip，更新 stable marketplace，执行 `codex plugin add codex-praetor@personal` 并核对 `codex plugin list`；不要求用户手工下载、解压或安装。
- 本机按“Release → stable 安装 → host 刷新 → 新任务 `runtime_info` → canary → 真实 worker”验收。自动激活若为 `needs_host_restart`，只请用户做一次受支持的刷新或重启；用户确认后先验 `runtime_info`。安装身份、host runtime、provider readiness 与公开 Release 独立记录，不能互相冒充。
- 版本/tag 不可变；旧 generation 只可限定根目录、可重试回收，权限或占用失败只记录延期。原生 CLI 以退出码 `0` 加 marker、工作树、completion、readiness 为成功；`process_exited`、`timed_out`、`watcher_failed`、`unknown` 都不是运行中。
- PowerShell 优先 ASCII；非 ASCII 必须 UTF-8 BOM。每次改动按风险查差异、冲突、相关测试/构建、工作树和最终用户路径；重命名另扫旧名、dry-run、manifest 和忽略规则。
