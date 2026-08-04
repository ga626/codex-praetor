# Codex Praetor 项目规则

## 产品边界

- Codex Praetor 只让 Codex 派发边界清楚的外部 CLI 工作；Codex 规划、监督、整合和验收，不扩展成通用多代理平台。活动名称固定为 `Codex Praetor`、`codex-praetor`、`codex_praetor_`；旧名仅限历史材料。
- `plugin/` 是稳定产品，`mcp/` 是源码，`scripts/` 按职责分组，`skill/` 只是兼容镜像；仓库检出和 zip 根目录不是安装入口。稳定入口是 personal marketplace 的 `%USERPROFILE%\plugins\codex-praetor`；开发用隔离 worktree + `UserProfileRoot`。不得手改 plugin cache、认证或 provider 数据库。
- Codex 创建的开发候选只能位于本项目已忽略的 `.codex-praetor/supervisor-worktrees/<name>`；阶段夹具只能位于 `.codex-praetor/fixtures/<name>`。不得在项目父目录创建同级 `CodexPraetor-*` 目录，不得移动、清理或接管 Codex Desktop 默认 worktree 或用户显式创建的 Git worktree。
- 公开能力以 `config/public-capabilities.json` 为准：每项声明受众、入口、包内依赖、场景和故障注入。`installed_plugin` 必须从插件 MCP/Skill 完成，`release_bundle` 必须从下载包完成，`developer_only` 不得写成普通用户承诺。

## 发布与验收

- 改 `plugin/`、`mcp/`、`skill/`、安装/排错/发布路径、版本、用户体验或公开能力即为发布影响 PR；同一 PR 更新版本面、changelog、release notes、`config/release-intent.json` 与能力清单。
- PR 就绪前从最终 stage/zip 验证受影响场景和全量确定性能力矩阵；源码、`mcp/dist`、`plugin/mcp/dist`、zip、runtime contract 或 generation 任一漂移即失败。真实 provider 仅在其合同、权限、派工或恢复行为变化时，于隔离环境验证并记录真实状态。
- 发布影响 PR 的合并硬门还包括 PR 正文中的 provider evidence：CI 会把标记段落 materialize 到被忽略的 `.codex-praetor/provider-release-evidence.json`，并绑定 artifact 自己记录的生成提交、同一已验证 artifact SHA、当前 generation/runtime contract，以及可移植的 provider compatibility surface SHA；分别包含 Qoder 与 CodeBuddy 各一条 Codex `accepted` 的真实任务和 accepted canary。PR merge ref 与 provider 任务的 source head 可以不同，CI 不得依赖本机已被 amend 的旧 commit；它必须用正文携带的 surface SHA 证明 provider 合同内容未变。合并后的 `main` 由 promotion tree 校验保证该候选 artifact 与合并内容一致。缺任一家、只提供合成夹具、只提供 process exit 0、surface SHA 或 artifact SHA 不一致都不得合并或发布。证据不进入源码和发布包，避免改变 artifact 身份。
- 候选 CI 必须显式检出 PR 的 immutable head，并在日志中断言 `git rev-parse HEAD` 与 PR head 相同；不得依赖 GitHub `pull_request` 的默认 synthetic merge ref。候选 artifact 的 SHA 只能绑定该实际检出的提交，main promotion 另行验证合并后的 promotion tree。
- 发布 ZIP 是跨环境身份物，不得把任意运行时的默认 `ZipArchive`/压缩器输出当作跨机器确定性承诺。写入器必须固定排序、UTF-8 标志、DOS 时间、版本/平台、属性、extra/comment 和压缩方式；确定性检查除重复构建外必须检查这些二进制头字段。遇到 artifact SHA 不一致，先区分检出提交、stage 内容和 ZIP 字节格式，再决定修复；禁止只改 evidence SHA 后重试 CI。
- 同一发布 PR 首次 CI 失败后，后续推送前必须归类该 PR 的全部失败 run，并用本地定向证据证明共同根因已被覆盖；历史失败可用于补充检查项，但 Dependabot 或无关 PR 的失败不得混入产品根因结论。
- 本机 GitHub 发布链路默认走用户当前代理节点：推送、PR、Actions/Release 查询或远端资产下载前，先以不超过 20 秒的 `127.0.0.1:7897` 代理 HTTPS 探针和同一代理环境下的 `git ls-remote --heads origin main` 探针确认链路；`gh` 与 Git 都只在当前进程设置 `HTTP_PROXY`、`HTTPS_PROXY`、`ALL_PROXY`。不得将直连作为正常候选或自动兜底；只有用户明确当前节点支持直连时才做对照诊断。两项代理探针任一失败即停止并提示切换节点，不把它归为代码、CI、认证或 artifact 缺陷；两项均通过后出现的 HTTP 认证/权限错误、分支保护、CI 断言、旧提交/候选内容或 artifact 问题分别处理，不允许再归咎节点。不得写全局 Git、Codex 或 provider 代理配置。
- 本机代理只负责本机到 GitHub 的控制面；GitHub-hosted Actions 的 runner 不经过这台电脑的代理。PR CI 或 `Release On Main` 失败必须先读取对应 run 日志：runner 网络/权限/工作流失败进入 CI 或 release incident；不能靠改本机代理、直连重试或手工替换发布资产“修好”。
- 阶段 1 的 route、plan、dry-run 和真实 worker 任务属于取证；单样本失败只记录分类并继续冻结矩阵，不得直接触发版本、Release 或 host 刷新。只有至少两条独立真实任务证明同一产品根因，才建立一个集中修复 PR。
- 共同根因 PR 的开发期只跑受影响组。版本面、候选 artifact 和全量确定性矩阵只能在范围冻结后各运行一次；候选冻结后发现的独立问题记入下一证据门，不回填当前 PR。host 刷新只属于 PR D 的用户交付链，不得作为 PR B 或阶段 1 的诊断工具。
- 对话只在阶段 1/2 事实报告、公开边界变化、PR D host 刷新或不可恢复 release incident 停下。
- main 合并后仅由受保护的 `Release On Main` 从合并 SHA 自动构建、发布和远端下载复验；同一带 SHA manifest 的 zip 贯穿运行时验收、上传、下载和 attestation。tag/draft 后失败只重跑原 run；创建 tag 前发现 workflow 缺陷才可用递增版本恢复 PR。
- main promotion 必须区分“候选 artifact 的 PR head”与“合并后的 main commit”：artifact generation commit 绑定前者，后者只能以完整 source tree 与候选回执验证同内容。不得要求两个 commit SHA 相同；必须回归“同 tree、不同 SHA 通过”和“tree 不同拒绝”，避免把正常 merge 误判为发布故障。
- provider 真实任务证据按实际兼容面而非文件名或 release version 判断：runtime-contract 的纯版本递增不得要求重跑或消耗 provider 积分；tuple、权限、adapter、任务合同等语义变化才触发受影响 provider 的真实证据门，并且必须有“版本不触发、语义变化触发”回归。
- PR 候选 artifact 的命名只能由 `scripts/release/get-release-candidate-artifact-name.ps1` 生成；上传、main 提升和回归检查必须共用该唯一合同，禁止在 YAML 或其他脚本手写第二套命名规则。
- main 提升同一候选 ZIP 后，若最终运行时验收依赖仓库 MCP 测试工具，发布作业必须先调用受控的 `mcp/scripts/install-mcp-dependencies.ps1`；不得假定 PR CI 的依赖目录会跨作业存在。
- release incident 的修复必须把故障纳入能力场景或故障注入；模拟 proof 不替代最终包证据。不得同版本补发、手工上传替代包或把收口缺口留给下一 PR。

## 本机与运行边界

- 公开交付由同一 artifact 的构建、bundled runtime、Release 上传和远端下载复验决定；本机未刷新不否定它。公开验真后自动下载并验真该 zip，更新 stable marketplace，执行 `codex plugin add codex-praetor@personal` 并核对 `codex plugin list`；不要求用户手工下载、解压或安装。
- 本机按“Release → stable 安装 → host 刷新 → 新任务 `runtime_info` → canary → 真实 worker”验收。自动激活若为 `needs_host_restart`，只请用户做一次受支持的刷新或重启；用户确认后先验 `runtime_info`。安装身份、host runtime、provider readiness 与公开 Release 独立记录，不能互相冒充。
- 版本/tag 不可变；旧 generation 只可限定根目录、可重试回收，权限或占用失败只记录延期。原生 CLI 以退出码 `0` 加 marker、工作树、completion、readiness 为成功；`process_exited`、`timed_out`、`watcher_failed`、`unknown` 都不是运行中。
- PowerShell 优先 ASCII；非 ASCII 必须 UTF-8 BOM。每次改动按风险查差异、冲突、相关测试/构建、工作树和最终用户路径；重命名另扫旧名、dry-run、manifest 和忽略规则。
