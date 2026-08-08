# Codex Praetor 项目规则

## 产品与运行边界

- Codex Praetor 只让 Codex 向外部 CLI worker 派发边界清楚的工作；Codex 规划、监督、整合、验收，不扩展成通用多代理平台。正式名称仅为 `Codex Praetor`、`codex-praetor`、`codex_praetor_`；旧名仅限历史材料。
- `plugin/` 是稳定产品，`mcp/` 是源码，`scripts/` 按职责分组，`skill/` 是兼容镜像。stable 入口为 `%USERPROFILE%\plugins\codex-praetor`；仓库/zip 不是安装入口，开发候选默认使用隔离 worktree + `UserProfileRoot`。唯一例外是带 SHA 的发布候选进行真实 Desktop host 验收：它可在自动备份、可独立恢复、绝不手改 cache/认证/provider 数据库的前提下临时安装到维护者 stable；验收失败必须先恢复旧 stable，不能让候选继续充当日常版本。
- `config/public-capabilities.json` 是公开能力事实源：每项声明受众、入口、包内依赖、场景和故障注入。`installed_plugin` 经插件 MCP/Skill 完成，`release_bundle` 经下载包完成，`developer_only` 不得写成普通用户承诺。
- 每项派工先有单一结果、允许/禁止路径、所需检查和验收标准；provider 只接已获同任务族证据的任务。completion、stdout/stderr、worktree、独立复跑和 readiness 一致才可 accepted；拒绝、超时、无输出或遗留差异均为失败证据，不静默重试或合并。
- 发布制品硬门：发布构建只能从干净提交生成；工作树有已跟踪或未跟踪差异时，`-Apply` 构建必须失败。候选激活只能走 `activate-pr-candidate.ps1` 下载并校验 PR CI 保留的 artifact；本地 ZIP、未提交版本或没有 `codex-praetor-release-candidate/v1` receipt 的制品不得进入 stable、宿主缓存或任何发布证据。

## 主目录与 worktree 收口

- 主目录只承载当前 `main` 或一个正在准备的 `codex/<topic>` PR；开始普通开发前先从 `main` 建分支。合并完成后，收口硬门是 `fetch origin main --prune`、切回 `main`、快进到 `origin/main`、核对 `HEAD == origin/main`，再报告工作树状态。远端已删除的候选分支不能继续作为主目录的日常基线。
- `.codex/` 与 `Microsoft/` 是本机 Codex/PowerShell 运行产物，不是产品源码、候选制品或发布输入，必须保持 Git 忽略；不得把它们加入 PR。`docs/reports/` 下未跟踪的报告属于用户本地材料，若与远端同名，先做内容哈希比较并归档副本，禁止静默覆盖或删除。
- 仅当 worktree 有匹配的项目 ownership 记录、关联任务已终态、无进程占用、工作树干净且分支已进入 `origin/main` 时，才可由 `scripts/maintenance/clean-codex-praetor-runtime.ps1 -Apply` 退役。未登记、未合并或有差异的 worktree 必须保留并列为待审计；需要回收差异时，先把差异与 completion 回执归档到项目运行根，再单独删除。
- 每次 PR 收口后运行一次 cleanup dry-run 并记录候选数；只对已审阅的 eligible 项执行 `-Apply`，随后执行 `git worktree prune`。这一步回收派工副本，不得触碰 Codex Desktop 管理的认证、插件缓存或其他项目目录。

## 发布影响 PR

- 改 `plugin/`、`mcp/`、`skill/`、安装/排错/发布路径、版本、用户体验或公开能力即为发布影响 PR；同一 PR 更新版本面、changelog、release notes、`config/release-intent.json` 和能力清单。
- 固定链路：影响能力图 → 定向本地检查 → PR head 的干净隔离候选 → 推送与 PR CI 构建、验证并 attest 唯一候选 ZIP → artifact SHA/attestation/candidate receipt → 候选真实 Desktop host 验收 → host receipt 回写 PR → 合并后仅提升同一 ZIP。候选 receipt 必须绑定 PR head、source tree、ZIP SHA、runtime contract、host `runtime_info` 与实际检查；源码、`mcp/dist`、`plugin/mcp/dist`、zip、runtime contract、generation 或回执漂移即失败。
- 日常 commit/pre-push hook 只做 `git diff --check`、staged doctor、PowerShell/合同/工作流等快速静态检查；不得运行完整 `test-codex-praetor.ps1`、完整候选 preflight 或构建 ZIP。完整确定性矩阵与最终包验收只在每个冻结候选的 PR CI 运行一次；候选 SHA 变化才重跑，并在 PR 中留下不可复用原因。提交者仍须按实际风险在本地运行相关定向测试，不能把所有缺陷首次留给 CI。
- 同能力缺口/共同根因并入当前 PR，集中修复后重跑受影响组；只有公开能力、边界或已批准 PR 结构变化才暂停请求决定。真实 provider 仅在 provider identity、连接、权限、任务合同、派工或恢复语义变化时，对受影响 tuple 于隔离环境验证；文案、文档、普通 release metadata 和不影响执行的控制面版本变化不得机械消耗真实 provider 积分。
- PR CI 构建、验证并 attest 候选；候选 host 验收在合并前完成。main 合并后只由 `Release On Main` 验证 source tree 与 candidate receipt，然后创建 draft、上传同一 ZIP、认证下载复验并公开，绝不重新打包。公开后只核对 Release/tag/asset digest 与候选一致，不重跑 host、canary 或真实 worker。tag/draft 后失败只重跑原 run；创建 tag 前发现 workflow 缺陷才可用递增版本恢复 PR。release incident 修复必须新增能力场景或故障注入，禁止同版本补发、手工替代上传或把收口缺口留给下一 PR。
- 收口中发现新问题时，先分类为产品/发布缺陷、验收合同缺陷或本机宿主观察；立刻向用户说明根因、影响和唯一建议，未经用户明确继续不得自行创建恢复 PR。验收合同的允许路径、artifact 路径和预期 generation 必须由实际 manifest 或存在性检查生成/核对；路径缺失时只拒绝该验收，禁止把它伪装成 provider 失败或通过重跑真实 worker 掩盖。
- 候选尚未公开时，公开入口检查必须使用 `test-public-entry-consistency.ps1 -SkipRemoteRelease`；只有 tag/Release 已存在时才运行远端下载一致性检查。`config/release-intent.json.previous_version` 必须来自目标分支的实际版本，不能用未发布的历史候选版本跳过基线。

## 交付与本机验证

- 同一带 SHA manifest 的 ZIP 必须贯穿候选运行、candidate host 验收、draft 上传、远端下载、attestation 和公开 Release；交付由这同一 artifact 的构建、bundled runtime、真实 host 验收、Release 上传和远端下载复验共同决定。维护者候选 host 未刷新时不得公开；正式 Release 公开后不因本机再次刷新而否定已经绑定的候选验收。
- 候选验真后自动从 PR artifact 下载该 ZIP，事务性更新维护者 stable marketplace，执行 `codex plugin add codex-praetor@personal` 并核对 `codex plugin list`；候选顺序为 stable 备份 → candidate stable 安装身份 → 一次 host 刷新 → 新任务 `runtime_info` → 按影响选择 dry-run 或受影响 provider 的最小真实任务 → candidate receipt。公开后 main 只把同 SHA ZIP 上传/下载复验；不要求普通用户手工下载、解压、运行 doctor 或 canary。普通用户安装/更新后仍可能需要一次支持的 host 刷新，之后可直接自然语言派工；用户首次 tuple 证据由透明 bootstrap 完成。
- 重启前必须先看到“目标候选已安装/缓存身份已改变”的证据；如果安装仍是旧版本，重启不得继续。重启后第一项动作只能是新任务 `runtime_info`，不一致就保持阻断，不得继续真实派工、写 host receipt 或收口。
- `needs_host_restart` 对同一候选只请一次受支持的刷新/重启，之后先验 `runtime_info`；安装身份、host runtime、provider readiness 与 Release 独立记录，不能互相冒充。版本/tag 不可变；旧 generation 仅可限定根目录、可重试回收，权限/占用失败只记延期。
- Codex 插件缓存按版本目录复用，故候选身份绝不能只比较版本号。每次候选 host 验收前后都必须比较候选 receipt 的 PR head、ZIP SHA、generation ID、source tree 与 runtime contract，和新任务 `runtime_info` 返回的运行代际逐项一致；任一项不一致即为旧缓存，不得把“工具可调用”或“版本相同”写成候选已加载、provider 已验证或可发布。
- 若官方 `codex plugin add` 因缓存备份的 `Access is denied`/占用失败，状态只能是 `awaiting_host_exit`：保留自动备份，等待 Codex Desktop 完全退出后由受控 helper 再执行官方安装命令，再重新打开宿主并在当前任务动态发现工具、复核 `runtime_info`。禁止手改插件 cache、强杀宿主、用旧 generation 继续真实派工，或用额外真实 worker 测试掩盖安装身份不一致。
- 激活状态机必须在进入 `awaiting_host_exit` 时立即写出持久 `pending` 状态，记录候选 generation、ZIP SHA、观察到的宿主 PID/启动时间和唯一下一步；helper 的 `result.json=completed` 只证明官方 `plugin add/list` 成功且候选 generation 已进入 cache，随后重新打开宿主并由新任务 `runtime_info` 逐项确认代际后，才能形成 host receipt。`codex plugin list` 的版本行单独不能放行。
- 同一候选只允许一次宿主刷新请求；重试激活必须先读取 pending/completed/failed 状态并复用 SHA 一致的 artifact，不能重复下载、重复请求重启或启动第二个 helper。若当前会话仍持有旧工具快照，必须新开任务并重新核对 `runtime_info`，不能把旧会话可调用写成候选已加载。
- 原生 CLI 只有退出码 `0`、成功 marker、零越界差异、completion 和 readiness 一致才成功；`process_exited`、`timed_out`、`watcher_failed`、`unknown` 不等于运行中。每次按风险查差异、冲突、测试/构建、工作树和最终用户路径；重命名另扫旧名、dry-run、manifest、忽略规则。PowerShell 优先 ASCII；非 ASCII 用 UTF-8 BOM。
