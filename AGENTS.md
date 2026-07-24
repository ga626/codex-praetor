# Codex Praetor 项目规则

## 产品与运行边界

- Codex Praetor 只让 Codex 向外部 CLI worker 派发边界清楚的工作；Codex 规划、监督、整合、验收，不扩展成通用多代理平台。正式名称仅为 `Codex Praetor`、`codex-praetor`、`codex_praetor_`；旧名仅限历史材料。
- `plugin/` 是稳定产品，`mcp/` 是源码，`scripts/` 按职责分组，`skill/` 是兼容镜像。stable 入口为 `%USERPROFILE%\plugins\codex-praetor`；仓库/zip 不是安装入口，开发候选须隔离 worktree + `UserProfileRoot`。不得手改 plugin cache、认证或 provider 数据库。
- `config/public-capabilities.json` 是公开能力事实源：每项声明受众、入口、包内依赖、场景、故障注入。`installed_plugin` 经插件 MCP/Skill 完成，`release_bundle` 经下载包完成，`developer_only` 不得写成普通用户承诺。

## 发布影响 PR

- 改 `plugin/`、`mcp/`、`skill/`、安装/排错/发布路径、版本、用户体验或公开能力即为发布影响 PR；同一 PR 更新版本面、changelog、release notes、`config/release-intent.json` 和能力清单。
- 固定交付链路：影响能力图 → 定向检查 → 干净隔离候选构建 → 最终 stage/zip 的受影响场景和全量确定性矩阵 → `HEAD`+artifact SHA 回执 → 推送 → 同一流水线 PR CI。源码、`mcp/dist`、`plugin/mcp/dist`、zip、runtime contract、generation、回执任一漂移即失败。
- 同能力缺口/共同根因并入当前 PR，集中修复并重跑受影响组；只有公开能力、边界或已批准 PR 结构变化才暂停请求决定。真实 provider 仅在合同、权限、派工或恢复行为变化时于隔离环境验证。
- PR CI 只复核 PR 候选；main 合并后仅 `Release On Main` 从合并 SHA 构建、发布、远端下载复验，二者共用流水线。tag/draft 后失败只重跑原 run；创建 tag 前发现 workflow 缺陷才可用递增版本恢复 PR。
- 同一带 SHA manifest 的 zip 贯穿候选运行、上传、下载和 attestation。release incident 修复必须新增能力场景或故障注入；模拟 proof 不替代最终包，禁止同版本补发、手工替代上传或把收口缺口留给下一 PR。

## 交付与本机验证

- 交付由同一 artifact 的构建、bundled runtime、Release 上传、远端下载复验决定；本机未刷新不否定交付。验真后自动下载该 zip，更新 stable marketplace，执行 `codex plugin add codex-praetor@personal` 并核对 `codex plugin list`；不要求用户手工下载、解压、安装。
- 本机固定为 Release → stable 安装 → host 刷新 → 新任务 `runtime_info` → canary → 真实 worker。`needs_host_restart` 只请一次受支持的刷新/重启；之后先验 `runtime_info`。安装身份、host runtime、provider readiness 与 Release 独立记录，不能互相冒充。
- 版本/tag 不可变；旧 generation 只可限定根目录、可重试回收，权限/占用失败只记延期。原生 CLI 只有退出码 `0`、marker、工作树、completion、readiness 一致才成功；`process_exited`、`timed_out`、`watcher_failed`、`unknown` 不是运行中。每次按风险查差异、冲突、测试/构建、工作树、最终用户路径；重命名另扫旧名、dry-run、manifest、忽略规则。PowerShell 优先 ASCII；非 ASCII 用 UTF-8 BOM。
