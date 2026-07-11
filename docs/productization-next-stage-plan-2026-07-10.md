# Codex Praetor 下一阶段产品化规划

日期：2026-07-10

## 结论

Codex Praetor 下一阶段不应该继续扩功能。重点应该是把“用户怎么安装、怎么正常使用、失败时怎么安静恢复、GitHub 页面怎么让普通用户看懂”这条产品链路打磨完整。

产品原则：

- 正常使用时不预检、不巡检、不自言自语。
- 只有真实失败时才进入轻量恢复。
- 恢复优先使用 Codex 官方机制，不发明重型守护进程。
- 用户文档先服务普通用户，再服务开发者。
- 发布包只给用户使用，不混入开发阶段脚本、handoff、内部考古和本机配置。

## 证据摘要

1. Codex 插件官方文档说明：插件可以包含 skills、MCP servers、hooks 等能力；安装后，用户在新任务中直接使用插件。桌面端和 IDE extension 都要求安装后开启新任务或新聊天再使用 bundled skills/tools。
2. Codex 插件官方文档说明：插件可通过 marketplace 分发；repo marketplace 位于 `$REPO_ROOT/.agents/plugins/marketplace.json`，也可以通过 `codex plugin marketplace add owner/repo` 添加 GitHub marketplace。
3. Codex app-server 官方文档提供 `config/mcpServer/reload`、`mcpServerStatus/list`、`mcpServer/tool/call`。本机实测：`config/mcpServer/reload` 成功，`mcpServerStatus/list` 能看到 `codex-praetor` 的 8 个工具；`thread/resume + mcpServer/tool/call` 能在旧线程上下文里直接调用新版 MCP 工具。
4. MCP 官方规范说明 stdio transport 是由客户端启动 MCP server 子进程，并通过 stdin/stdout 传 JSON-RPC；如果 stdio transport 断开，当前模型回合已注入的工具句柄不会自动神奇换成新进程。
5. GitHub 官方 README 文档说明 README 是用户进入仓库时最先看到的内容，应该回答项目做什么、为什么有用、如何开始、哪里求助、谁维护。
6. GitHub 官方 Release 文档说明 Release 是可部署的软件迭代，可附 release notes 和二进制/压缩包资产；预发布可以标记为 prerelease。

## 产品调用模型

### 正常路径

用户说：

```text
拆分一下任务，分配给其他 agent 做一部分。
```

理想行为：

1. Codex 根据 Skill 或 MCP route-intent 识别为 Codex Praetor 外部 worker 路线。
2. 如果任务适合派工，直接生成计划或 dry-run。
3. 不主动跑 doctor。
4. 不主动讲一堆安装状态、provider 状态、稳定性策略。
5. 不创建 Codex 原生 subagent，除非用户明确要求。

正常路径最多应该出现一句短解释：

```text
我会先用 Codex Praetor 做只读 dry-run，确认任务边界和 worker 路线。
```

### 失败路径

只有在 MCP 工具不可见、工具调用失败、返回 `Transport closed`、脚本入口缺失、provider CLI 缺失等真实故障时，才进入恢复。

推荐恢复顺序：

1. 不打扰用户，先做一次轻量 reload：
   - `config/mcpServer/reload`
   - `mcpServerStatus/list`
2. 如果工具可见，再用 `thread/resume + mcpServer/tool/call` 做一次最小 probe：
   - 调 `codex_praetor_route_intent`
   - 只验证工具通道，不跑 provider。
3. probe 成功后重试原工具调用一次。
4. probe 失败时，给用户一句人话：
   - 当前 Codex 工具通道断了。
   - 已尝试官方 reload。
   - 需要重载 Codex 或开新任务。

不推荐：

- 每次正常调用前跑 `doctor`。
- 每次正常调用前跑 provider version/auth 检查。
- 每次失败都让用户新开对话。
- 后台常驻轮询 MCP 状态。
- 在模型回复里反复展开检测清单。

## 稳定性设计

下一阶段应实现一个轻量恢复脚本，而不是重型监控系统。

建议新增：

- `scripts/reload-codex-praetor-mcp.ps1`
  - 调官方 app-server `config/mcpServer/reload`。
  - 可选输出 `mcpServerStatus/list` 中 `codex-praetor` 的 compact 状态。
  - 默认安静；只有失败时打印人话。

- `scripts/probe-codex-praetor-mcp.ps1`
  - 先 `thread/resume`。
  - 再 `mcpServer/tool/call codex_praetor_route_intent`。
  - 用一个固定中文任务文本验证路由。
  - 输出三态：`ok`、`reload_needed`、`manual_reload_needed`。

- MCP/Skill 文档中的失败处理规则：
  - 第一次失败：reload + probe + retry。
  - 第二次失败：简短说明，建议重载 Codex。
  - 不在正常路径显示这些步骤。

这个设计的好处：

- 正常使用零额外 token。
- 故障时只多一次轻量 RPC。
- 使用 Codex 官方 app-server，不做私有守护进程。
- 不要求用户频繁新开对话。

## 安装体验规划

当前 README 对开发者足够，但对普通用户还不够。

用户从 GitHub 进入后的理想路径：

1. 看见一句话说明：
   - 这是给 Codex 用的外部 Agent 派工插件。
2. 看见“我需要准备什么”：
   - Windows
   - Codex Desktop 或 Codex CLI
   - 至少一个外部 CLI worker，或者先只用 dry-run/plan
3. 看见“最快安装”：
   - 用 Codex 官方插件目录或 repo marketplace 安装。
4. 看见“没有 Qoder/CodeBuddy/MiMo 也能做什么”：
   - 可以做 route-intent、plan、dry-run、list/status/lane/conflict。
5. 看见“真实派工怎么启用”：
   - 安装并登录至少一个 provider CLI。
   - 配置 `codex-praetor.local.json`。
6. 看见“出问题怎么办”：
   - 先运行轻量 reload/probe。
   - 再看 provider 设置。
   - 最后才重载 Codex 或开新任务。

## GitHub 仓库体验缺口

当前已经有：

- 中文 README
- 英文 README
- LICENSE
- CHANGELOG
- SECURITY
- CONTRIBUTING
- CI
- release zip 构建
- provider notes

还缺：

- 面向普通用户的 `docs/installation.zh.md`
- 面向普通用户的 `docs/troubleshooting.zh.md`
- repo marketplace 文件：`.agents/plugins/marketplace.json`
- release asset 使用说明：下载 zip 后怎么安装插件
- README 顶部的“最快开始”三步
- provider 缺失场景说明：没有外部 CLI 时不是失败，只是不能真实派工
- 一键或半自动安装脚本：
  - `scripts/install-user.ps1`
  - 做复制插件包、写入 marketplace、提示重启/新任务
  - 不读取账号数据库，不登录 provider

## 下一阶段任务排序

### P0：修正文档口径

- README 不再说 `Transport closed` 必然要新对话。
- Roadmap 明确：新线程只用于最终 fresh-context 验收，不是日常恢复方案。
- 增加“正常调用轻、失败恢复轻”的产品原则。

### P1：补轻量恢复脚本

- `reload-codex-praetor-mcp.ps1`
- `probe-codex-praetor-mcp.ps1`
- `test-codex-praetor.ps1` 增加可选 MCP app-server probe，不作为普通用户每次使用前置。

### P2：补用户安装路径

- 增加 repo marketplace。
- 增加 `install-user.ps1`。
- README 顶部改成“最快开始”。
- 安装说明分成：
  - 插件安装
  - 可选 provider 安装
  - 第一次 dry-run
  - 故障恢复

### P3：补 GitHub 发布体验

- GitHub Release 说明写成中文优先。
- release zip 附安装说明。
- 标记 prerelease。
- Release notes 明确 alpha 边界。
- README 中把开发者验证命令移到后面，不挡普通用户。

### P4：最终验收

- 当前线程跑本地测试、release build、app-server reload/probe。
- 只开一次 fresh-context 验收，验证真实用户打开新任务后能自然调用插件。
- 通过后再 tag 和 GitHub Release。

## 不做的事

- 不做常驻后台健康监控。
- 不做每次调用前的 doctor。
- 不做自动 provider 登录。
- 不读取 provider auth/token/cookie/database。
- 不把开发源和 C 盘安装版做软链接。
- 不把 Codex 原生 subagent 当作 Codex Praetor fallback。

## 来源

- OpenAI Codex Plugins: https://developers.openai.com/codex/plugins
- OpenAI Codex Build Plugins: https://learn.chatgpt.com/docs/build-plugins
- OpenAI Codex App Server: https://developers.openai.com/codex/app-server
- Model Context Protocol Transports: https://modelcontextprotocol.io/specification/2025-06-18/basic/transports
- GitHub README docs: https://docs.github.com/en/repositories/managing-your-repositorys-settings-and-features/customizing-your-repository/about-readmes
- GitHub Releases docs: https://docs.github.com/en/repositories/releasing-projects-on-github/about-releases
- GitHub Managing Releases docs: https://docs.github.com/en/repositories/releasing-projects-on-github/managing-releases-in-a-repository
