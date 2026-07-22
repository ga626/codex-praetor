# Codex Praetor 项目规则

## 产品与安装边界

- Codex Praetor（Codex 执政官）只为 Codex 派发边界清楚的外部 CLI 工作；Codex 规划、监督和验收，不扩展成通用多代理平台。
- 活动名称固定为 `Codex Praetor`、`codex-praetor`、`codex_praetor_`；旧名仅可留在迁移/历史材料。
- `plugin/` 是最终包，`mcp/` 是源码，`scripts/` 按职责分组；`skill/` 是派生兼容镜像，不能成为安装入口或运行时依赖。
- 仓库检出目录不是安装目录。稳定入口只有 personal marketplace 指向的 `%USERPROFILE%\plugins\codex-praetor`；开发只用隔离 `UserProfileRoot`。不得手改 `%USERPROFILE%\.codex\plugins\cache`、认证或 provider 数据库。
- 真实开发验收用独立 worktree 加隔离 `UserProfileRoot`；可经官方 CLI 使用已有登录态、联网和正常额度，但不得读写、输出或迁移认证数据。worktree 只隔离代码，不是系统沙箱。

## PR 与发布

- 改 `plugin/`、`mcp/`、`skill/`、安装/排错/发布路径、版本或用户安装体验即为发布影响 PR；同一 PR 必须更新版本面、changelog、release notes 和 `config/release-intent.json`。
- PR 就绪前：从最终 stage/zip 启动 bundled MCP，核对版本、runtime contract SHA、工具集和 generation manifest；源码、`mcp/dist`、`plugin/mcp/dist`、zip 任一漂移即失败。构建、测试、候选 CI 和发布共用同一入口。
- main 合并后仅由受保护的 `Release On Main` 从合并 SHA 自动构建、发布、下载复验；同一带 SHA manifest 的 zip 必须贯穿运行时验收、上传、远端下载和 attestation。tag/draft 后失败只重跑原 run；创建 tag 前发现 workflow 缺陷才允许递增版本的恢复 PR。
- 每个 release incident 必须在下一次修复 PR 中加入可重复故障注入测试，并落到 artifact 或合同不变量；模拟 proof 不能替代真实收口证据。
- 公开结果仅为 `产品已交付` 或 `代码已合并，产品未交付（release incident）`。后者停止下一次发布影响 PR，先修自动发布路径或重跑原 SHA；不得同版本补发、手工上传替代包或留收口尾巴。

## 公开交付与本机验收

- 公开交付：同一 artifact 的构建、bundled runtime、Release 上传和普通用户远端下载复验全部通过。本机未刷新不否定公开交付。
- 每个发布影响 PR 的收口，在公开验真通过后必须自动完成本机激活：下载并再次验真该同一 Release zip，调用包内安装器更新 stable marketplace，再执行官方 `codex plugin add codex-praetor@personal`，并确认 `codex plugin list` 已显示目标版本。不得要求用户手工下载、解压或安装，也不得手改 cache。
- 本机验收严格按：下载并验真目标 Release → stable marketplace 安装身份等于该 Release → 刷新 Codex host → 新任务内 `runtime_info` 等于安装身份 → provider canary → 真实 worker。新任务不能替代 host 刷新。
- 自动本机激活成功后若状态为 `needs_host_restart`，Codex 只要求用户执行一次受支持的 host 刷新或重启；不得强杀宿主、猜测已刷新或提前运行 canary。用户确认刷新后，Codex 必须先验 `runtime_info`，再继续后续验收。
- 任何不等必须停止并精确报告：`needs_install`、`needs_host_restart`、`needs_canary` 或 `local_candidate_stale`；不得用旧缓存、旧回执、手写 readiness、手工 cache 操作或重启猜测跳关。
- 安装身份、host runtime、provider readiness 和公开 Release 是四个独立观察；收据只能证明自身范围，不能互相冒充。真实 canary 必须在干净仓库或隔离 checkout；worker/worktree 证据、provider proof 和仓库漂移分别记录。
- readiness 以 entries 中 generation/contract/tuple 为权威；文件顶层 generation 仅是兼容摘要，不能遮蔽其他 generation 的有效记录。`code_change` canary 必须留下 worker worktree 的真实改动证据，不能只回 marker。

## 版本、运行与安全

- 版本和 tag 不可变；不覆盖可能被对话引用的目录，不用 junction/稳定指针把旧合同映射为新合同。旧版本由限定根目录、可重试的回收机制处理；占用或权限失败只记录并延期，不强杀 Codex，也不改变交付结论。
- 原生 CLI 成功以退出码 `0` 为前提；再检查 marker、工作树、completion 和 readiness。统一进程辅助程序分离 stdout/stderr，记录启动、超时、退出码和诊断尾部，兼容 Windows PowerShell 5.1/7。
- PowerShell 脚本优先 ASCII；含非 ASCII 文本必须 UTF-8 BOM，并由产品验证扫描，避免本机中文代码页与 GitHub Windows runner 的解析差异。
- `process_exited`、`timed_out`、`watcher_failed`、`unknown` 都不是运行中；“等待 Codex 验收”不等于 worker 运行中。非发布 dependency PR 仍构建/测试，但不进入 release-intent 或 immutable-tag 门禁。
- 外部研究由 Codex + KnowledgeRadar 综合；外部 provider 仅可在只读、可追溯、经监督验收的研究契约中工作。不得提交密钥、token、账户文件、截图或本地数据库。

## 最小验证

- 每次改动按风险验证差异、冲突、相关测试/构建、工作树和最终用户路径；重命名另扫活动文件旧名、dry-run 派工、核对 Skill/plugin manifest，并确认运行输出被忽略。
