# Codex Praetor 用户链路与轻量恢复规划

日期：2026-07-10

## 一句话结论

Codex Praetor 现在最大的问题不是“还能不能加功能”，而是要把它做成一个普通用户能安装、能理解、能稳定使用的 Codex 插件。

下一阶段不要扩展新的 worker 能力。先把这四件事做好：

1. GitHub 页面让普通用户看得懂。
2. 安装路径尽量一键化。
3. 正常使用时保持安静、轻量、少消耗 token。
4. 失败时自动走最短恢复路径，而不是要求用户反复新开对话。

## 本轮确认到的事实

### 1. 当前线程原生工具句柄仍会坏

本轮直接调用当前线程里暴露的 `mcp__codex_praetor.codex_praetor_route_intent`，结果仍是：

```text
Transport closed
```

这说明旧线程中已经注入的工具句柄不能被当成最终验收依据。它会保留旧 transport 状态。

### 2. 官方 app-server 轻量恢复路径有效

同一线程里，通过官方 app-server 路线执行：

- `config/mcpServer/reload`
- `mcpServerStatus/list`

结果成功，并且 `mcpServerStatus/list` 能看到 `codex-praetor` 的 8 个工具。

继续执行：

- `thread/resume`
- `mcpServer/tool/call codex_praetor_route_intent`

结果成功，返回核心判断：

```json
{
  "route": "codex_praetor_external_worker",
  "confidence": "high",
  "native_codex_subagents_allowed": false
}
```

这证明“旧线程失败后只能新开对话”不是正确产品策略。正确策略是：失败时先走官方 reload/status/probe，最终才提示用户重载 Codex 或新开任务。

### 3. KnowledgeRadar 原生 MCP 可用

本轮外部调研前先用 KnowledgeRadar：

- `health_check(mode="summary")`
- `get_capabilities(summary=true)`
- `kr_research(mode="deep_route")`

结果显示 KnowledgeRadar 原生工具面可用。后续内置 web/search 只作为 KnowledgeRadar 授权的 `host_internal_web_wave`。

### 4. OpenAI 官方页面对命令行抓取有限制

本机命令行访问部分 OpenAI 开发者页面返回 `403`。所以 OpenAI 插件/app-server 相关结论不能只靠网页抓取，要结合：

- 官方页面 URL。
- 当前 Codex app-server 实测。
- 项目里已经验证过的 plugin/MCP 行为。

### 5. GitHub 官方文档可访问

GitHub README 和 Release 官方文档可以直接访问。对我们的约束是：

- README 是用户进入仓库最先看到的内容，必须解释项目是什么、为什么有用、怎么开始、哪里求助。
- Release 是基于 tag 的软件迭代，可以附 release notes 和下载资产，alpha 应明确标记 prerelease。
- 发布前必须避免 token、账号数据、个人路径、缓存和本机私有文件进入公开仓库或 release 包。

## Codex 配合方式：正常轻，失败短

### 正常使用路径

用户说：

```text
拆分一下任务，分配给其他 agent 做一部分。
```

理想行为：

1. Skill 识别这是 Codex Praetor 外部 worker 路线。
2. MCP route-intent 做一次轻量判断。
3. 如果用户还没有确认真实派工，只做 plan 或 dry-run。
4. 不跑 doctor。
5. 不检查所有 provider。
6. 不解释一大堆稳定性策略。
7. 不创建 Codex 原生 subagent。

正常路径只能出现很短的人话，例如：

```text
我会先用 Codex Praetor 做 dry-run，确认任务边界和可用 worker。
```

### 失败恢复路径

只有出现真实故障时才进入恢复：

- MCP 工具不可见。
- MCP 工具返回 `Transport closed`。
- app-server 状态里看不到 `codex-praetor`。
- provider CLI 缺失。
- provider 未登录或版本不支持。
- 脚本入口缺失。

推荐恢复顺序：

1. 后台运行一次 `config/mcpServer/reload`。
2. 后台运行一次 `mcpServerStatus/list`。
3. 如果工具存在，运行一次 `thread/resume + mcpServer/tool/call codex_praetor_route_intent`。
4. probe 成功，重试原动作一次。
5. probe 失败，才告诉用户：当前 Codex 工具通道断了，已经尝试官方恢复，需要重载 Codex 或新开任务。

这个过程应该被包装成脚本，不应该让模型每次在回复里逐条自言自语。

## MCP 服务应该在哪一步

MCP 已经进入产品主链路，但下一阶段要把它从“能跑”打磨成“可恢复、可安装、可验收”。

分工应该是：

- Skill：负责自然语言触发。
- MCP：负责 Codex 可见工具面，包括 route、dry-run、plan、status、lane/conflict。
- PowerShell 脚本：负责 Windows 本机 worker 派工和恢复脚本。
- Plugin：负责安装包和 Codex 发现。
- app-server reload/probe：只在失败时作为恢复通道，不进入正常调用前置。

MCP 服务不应该做：

- 每次调用前健康检查。
- provider 登录探测。
- 后台常驻轮询。
- 读取账号数据库、token、cookie。
- 把 Codex 原生 subagent 当 fallback。

## GitHub 用户体验应该长什么样

### README 顶部

中文 README 是主界面，英文 README 作为切换链接。顶部要把用户最关心的三件事放在第一屏：

1. 这是什么：给 Codex 用的外部 Agent 派工插件。
2. 能做什么：把清楚边界的小任务派给 Qoder、CodeBuddy、MiMo，Codex 负责规划和验收。
3. 怎么开始：安装插件 -> 运行 dry-run -> 可选配置 provider。

不要把开发者验证命令放在最前面。doctor、CI、release build 这些放到后半部分。

### 安装入口

下一阶段应该提供三条路径，按用户友好度排序：

1. 推荐：Codex 插件 marketplace 安装。
2. 普通用户：下载 GitHub Release zip，运行 `scripts/install-user.ps1`。
3. 开发者：clone 仓库，运行 doctor/test/build。

`install-user.ps1` 的职责应该很窄：

- 检查 Windows、PowerShell、Node.js。
- 把 release 包里的 plugin 复制到 Codex 可识别位置。
- 写入或提示 repo marketplace 配置。
- 提示用户重载 Codex 或新开一个任务完成首次加载。
- 不安装 Qoder/CodeBuddy/MiMo。
- 不登录 provider。
- 不读取本机账号文件。

### 首次使用

首次使用不应该要求真实 provider。

没有 Qoder、CodeBuddy、MiMo 时，用户仍然可以验证：

- route-intent。
- plan。
- dry-run。
- list-jobs。
- status。
- lane/conflict。

真实派工只在用户安装并登录至少一个 provider 后启用。

### 故障页和 FAQ

需要新增 `docs/troubleshooting.zh.md`，按普通用户能理解的方式写：

- 看不到 Codex Praetor：先确认插件安装，再重载 Codex。
- MCP 工具失败：运行轻量 reload/probe。
- 没装 provider：不是产品坏了，只是不能真实派工。
- provider 没登录：去 provider 官方 CLI 登录，Codex Praetor 不代替登录。
- WindowsApps `codex.exe` 权限问题：使用真实 Codex binary 路径或 Codex app-server 路线。
- 什么时候才需要新开任务：安装或插件更新后首次加载、最终验收、reload/probe 失败后的兜底。

## 发布包边界

发布包应该包含：

- `plugin/`
- `README.md`
- `README.en.md`
- `LICENSE`
- `CHANGELOG.md`
- `SECURITY.md`
- `CONTRIBUTING.md`
- `docs/installation.zh.md`
- `docs/troubleshooting.zh.md`
- `docs/provider-notes/`
- `examples/`
- `config/codex-praetor-tiers.example.json`

发布包不应该包含：

- `handoff/`
- `docs/internal/`
- 本机 runtime/jobs/worktrees/cache。
- `*.local.json`
- `.env*`
- token、auth、cookie、账号数据库。
- provider 使用截图。
- C 盘安装版。
- D 盘开发机绝对路径配置。

## 下一阶段路线图

### P0：立刻固定产品原则

状态：进行中。

要做：

- README 顶部改成普通用户能懂的最快开始。
- 路线图明确：正常使用不做重检查，失败才 reload/probe。
- 文档统一中文主界面、英文可切换。
- 记录本轮实测：当前工具句柄坏，但 app-server reload/probe 成功。

完成标准：

- 用户看 README 第一屏就知道这是什么、能不能用、怎么开始。

### P1：实现轻量恢复脚本

要做：

- 新增 `scripts/reload-codex-praetor-mcp.ps1`。
- 新增 `scripts/probe-codex-praetor-mcp.ps1`。
- 复用现有 `scripts/invoke-codex-app-server.js`。
- 默认安静输出，失败时只给简短人话。
- `test-codex-praetor.ps1` 可以加可选 probe，但不能变成正常使用前置。

完成标准：

- 出现 `Transport closed` 时，可以在旧线程里完成 reload/probe。
- probe 成功后能重试 route-intent。
- probe 失败才建议重载 Codex 或新开任务。

### P2：补普通用户安装路径

要做：

- 新增 `.agents/plugins/marketplace.json`。
- 新增 `docs/installation.zh.md`。
- 新增 `docs/troubleshooting.zh.md`。
- 新增或设计 `scripts/install-user.ps1`。
- Release zip 中放清楚安装说明。

完成标准：

- 一个不懂编程但会安装 Codex 的 Windows 用户，可以按文档把插件装上，并跑通 dry-run。

### P3：发布体验收口

要做：

- README 中文优先，英文切换保留。
- Release notes 中文优先，英文可以后置。
- GitHub Release 标记 `0.1.0-alpha` 和 prerelease。
- GitHub 页面补齐截图或终端示例，但不放个人数据。
- 跑 public marker scan。
- 构建 release zip，并确认排除私有文件。

完成标准：

- GitHub 仓库打开就是产品页，不像开发工作台。
- Release 下载包拿到后知道怎么装、怎么试、怎么排错。

### P4：最终验收和发布

要做：

- 当前线程跑本地测试、doctor、release build、app-server reload/probe。
- 只开一次 fresh-context Codex 验收。
- 验收所有 MCP 主工具和自然语言触发。
- 通过后再创建 tag 和 GitHub Release。

完成标准：

- 新鲜 Codex 任务能自然发现插件。
- 自然语言“拆分任务给其他 agent”走 Codex Praetor，而不是 Codex 原生 subagent。
- route/dry-run/lane/conflict/status 主链路通过。
- GitHub Release 可下载、可安装、可复现。

## 暂时不做

- 不做新 provider。
- 不做复杂后台守护进程。
- 不做每次启动全量体检。
- 不做自动登录。
- 不做 C 盘和 D 盘自动同步。
- 不做通用多 Agent 平台。

## 来源和证据路径

- KnowledgeRadar：`health_check(mode="summary")`、`get_capabilities(summary=true)`、`kr_research(mode="deep_route")`。
- 本机实测：`config/mcpServer/reload` 成功，`mcpServerStatus/list` 可见 8 个 `codex-praetor` 工具。
- 本机实测：当前原生工具句柄返回 `Transport closed`，但 `thread/resume + mcpServer/tool/call` 可成功调用 `codex_praetor_route_intent`。
- GitHub README 文档：https://docs.github.com/en/repositories/managing-your-repositorys-settings-and-features/customizing-your-repository/about-readmes
- GitHub Release 文档：https://docs.github.com/en/repositories/releasing-projects-on-github/about-releases
- GitHub Managing Releases 文档：https://docs.github.com/en/repositories/releasing-projects-on-github/managing-releases-in-a-repository
- OpenAI Codex Plugins：https://developers.openai.com/codex/plugins
- OpenAI Codex Build Plugins：https://learn.chatgpt.com/docs/build-plugins
- OpenAI Codex App Server：https://developers.openai.com/codex/app-server
- MCP transport 规范：https://modelcontextprotocol.io/specification/2025-06-18/basic/transports
