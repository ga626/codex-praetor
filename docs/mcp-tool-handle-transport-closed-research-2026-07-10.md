# MCP 工具句柄 `Transport closed` 调研结论

日期：2026-07-10

## 人话结论

如果问的是：**当前这一轮模型已经拿到的那个 `mcp__codex_praetor.*` 工具句柄，报了 `Transport closed` 以后，能不能在同一轮里原地修好，让这个同一个句柄立刻恢复？**

结论：**目前不能。**

如果问的是：**底层 MCP 服务、插件状态、下一次工具上下文，能不能恢复？**

结论：**可以，而且本机已经验证成功。**

更准确地说：

- 当前坏掉的工具句柄：不能热替换。
- 底层 MCP 服务：可以通过 app-server reload/status/probe 恢复或确认健康。
- 同一个旧线程的下一次 active turn：有机会拿到刷新后的 MCP 状态。
- 新线程/fresh context：最可靠，用于最终验收，不应该作为日常恢复第一步。

## 本轮本机证据

### 证据 1：当前原生工具句柄仍然坏

直接调用当前线程已经暴露的工具：

```text
mcp__codex_praetor.codex_praetor_route_intent
```

结果仍然是：

```text
tool call failed for `codex-praetor/codex_praetor_route_intent`
Caused by:
    Transport closed
```

这说明当前模型回合里的工具句柄没有被之前的 reload 原地替换。

### 证据 2：底层 app-server reload 成功

通过官方 app-server 调用：

```text
config/mcpServer/reload
mcpServerStatus/list
```

结果：

```json
{"id":1,"result":{}}
{"id":2,"found":true,"toolCount":8,"authStatus":"unsupported","version":"0.1.0-alpha"}
```

这说明 `codex-praetor` MCP 服务在 app-server 层是存在的，并且能列出 8 个工具。

### 证据 3：底层 app-server 直接工具调用成功

通过官方 app-server 调用：

```text
thread/resume
mcpServer/tool/call codex_praetor_route_intent
```

结果成功：

```json
{
  "route": "codex_praetor_external_worker",
  "confidence": "high",
  "native_codex_subagents_allowed": false,
  "repo": "D:\\Projects\\CodexPraetor"
}
```

这说明问题不是 Codex Praetor MCP 服务本身坏了，而是当前模型工具面里的句柄引用坏了。

### 证据 4：远程插件目录同步 403 不是主因

app-server 输出里还有：

```text
remote installed plugin bundle sync failed
chatgpt authentication required for remote plugin catalog; api key auth is not supported
```

以及 featured plugin 请求 `403`。

但同一轮里 `mcpServerStatus/list` 已经能看到本机 `codex-praetor` 的 8 个工具，`mcpServer/tool/call` 也能成功，所以这不是当前 `Transport closed` 的根因。它影响远程目录/catalog 同步，不等于本地插件/MCP 不可用。

## 官方文档证据

### Codex app-server

OpenAI Codex app-server 文档明确提供了这些方法：

- `config/mcpServer/reload`：从磁盘重载 MCP 配置，并为已加载线程排队刷新。
- `mcpServerStatus/list`：列出 MCP servers、tools、resources 和 auth 状态。
- `mcpServer/tool/call`：按 `threadId`、server、tool 直接调用线程配置里的 MCP 工具。

关键点是：`config/mcpServer/reload` 是“排队刷新 loaded threads”，不是“替换当前模型回合里已经注入的工具函数对象”。这和本机实测吻合：app-server 能调用成功，但当前工具句柄仍然失败。

来源：

- https://developers.openai.com/codex/app-server
- https://github.com/openai/codex/blob/main/codex-rs/app-server/README.md

### Codex plugins

OpenAI Codex 插件文档说明：已安装插件可以给新聊天/新任务增加 skills、connectors 和 MCP tools；IDE extension 也要求安装后开启新聊天再使用插件携带的 skills/tools。

这支持一个判断：插件和工具面是按任务/线程上下文注入的，不是任意时刻都能在当前模型回合里原地变更。

来源：

- https://developers.openai.com/codex/plugins
- https://developers.openai.com/codex/plugins/build
- https://developers.openai.com/codex/mcp

## MCP 规范证据

MCP 规范说明，stdio transport 的模型是：

- client 启动 MCP server 子进程。
- server 从 `stdin` 读 JSON-RPC。
- server 往 `stdout` 写 JSON-RPC。
- server 关闭输出流并退出时，可以主动结束连接。
- shutdown 由底层 transport 体现。

这意味着 `Transport closed` 在协议层不是普通业务错误，而是 client 与 server 的通信通道已经断开。断开以后，必须由 host/client 建立新的 transport/session，原来的句柄本身没有协议级“复活”动作。

MCP 的 HTTP transport 有 session/resumability 设计，但我们当前 `codex-praetor` 是插件内 stdio MCP，主要恢复责任在 Codex host。

来源：

- https://modelcontextprotocol.io/specification/2025-06-18/basic/transports
- https://modelcontextprotocol.io/specification/2025-06-18/basic/lifecycle

## 社区和上游 issue 证据

调研到多个 OpenAI Codex / MCP 相关 issue，结论方向一致：`Transport closed` 经常是 host/transport 生命周期问题，不一定是 MCP server 业务逻辑坏。

### 0. 本轮扩展过的 KnowledgeRadar 感知面

本轮没有只用一个搜索入口。使用过的感知工具和作用如下：

- `health_check`：确认 KnowledgeRadar 自身工具面可用。
- `get_capabilities`：确认当前声明工具数为 17，并发现可用低层工具。
- `kr_research`：做路线准入，明确开放 Web、GitHub、中文社区、视频平台和运行日志的证据角色。
- `kr_web_search`：搜索 OpenAI Codex issue、官方 app-server 文档、`llms-full.txt`、MCP transport 问题。
- `search_github_repositories`：早期用于 GitHub 线索发现；对 issue 精确检索不如 `kr_web_search` 有效。
- `extract_web_page`：抽取 `openai/codex#16899`、`openai/codex#22571` 和 app-server README 正文。
- `search_zhihu`：查中文 Codex MCP 配置和 Windows 问题经验。
- `search_wechat_articles`：查中文公众号里的 Codex/MCP 配置、传输机制、稳定性痛点文章。
- `search_bilibili`：查中文视频平台里的 Codex/MCP 配置、插件不显示、上下文卡住等用户问题。
- `search_youtube`：查英文视频平台 MCP/Codex 技术解释，直接故障证据较弱。
- `search_xiaohongshu`：查用户体验层面的 Codex MCP 中断、连不上、桌面端 bug 反馈。
- `get_content_detail`：抽取小红书“发消息会打断 Codex MCP”详情，确认这是具体用户体验问题，不只是标题命中。
- `search_academic`：查 MCP/agent protocol 的连接生命周期和失败恢复背景，找到 MCP survey 和 agent protocol robustness 论文线索。
- `analyze_decision_logs`：确认 KnowledgeRadar 自身最近 100 条详情链路成功率约 91%，本轮不是感知层整体故障。

未深入使用的工具主要是强动态抽取和高成本多模态分析，因为这个问题的核心证据已经由官方 issue、app-server README、MCP 规范和本机 runtime probe 覆盖；继续做视频/图片深度理解会增加成本，但不会显著改变“当前句柄不能原地热修”的结论。

### 1. Codex 已有“服务健康但旧 session 不恢复”的报告

`openai/codex#22571` 描述：远程 MCP server 重启后，fresh MCP client 能成功，但现有 Codex session 卡在 timeout 或 `Transport closed`，实际恢复只能重启 session/app-server。issue 期望 Codex 能自动重连或暴露单个 MCP server transport reload/restart API。

来源：

- https://github.com/openai/codex/issues/22571

该 issue 的评论进一步补强了两个点：

- 重新启动/重连 MCP transport 可能会让当前 agent 丢掉它继续任务所需的唯一工具通道，因此“让模型自己去重启 MCP”是高风险操作。
- 有用户把 fresh subagent/fresh session 当临时绕法，因为新连接能拿到新的 MCP transport；这说明“新上下文有效”，但也证明它不是当前句柄原地修复。

### 2. Codex stdio MCP recovery 已有人提出补丁思路

`openai/codex#28704` 描述：stdio MCP transport 关闭后，Codex 不可靠恢复；提出的补丁思路是把 `TransportSend` / `TransportClosed` 当作可恢复错误，重建 transport/service，替换已保存的 stdio process handle，终止旧进程，并重试一次。

这个 issue 很重要，因为它反向证明：如果要真正自动恢复工具句柄，需要 Codex host 自身实现“重建并替换 transport/process handle”。这不是插件或 skill 能在用户态完全解决的。

来源：

- https://github.com/openai/codex/issues/28704

### 2.5. 长会话 stdio MCP 退化，但 fresh `codex exec` 仍成功

`openai/codex#16899` 是强相关证据。它描述的是长时间 Codex CLI session 中，stdio MCP server 一开始成功，随后在同一个 session 里永久退化到 `Transport closed`；与此同时，fresh `codex exec` 子进程仍能反复成功调用同一个 MCP server。

这个 issue 的关键价值是：它把问题定位到“长会话 MCP client/session connection state”，而不是 MCP server 业务逻辑或配置文件本身。

来源：

- https://github.com/openai/codex/issues/16899

### 3. Windows Codex Desktop 上有“直接 MCP 成功，Codex wrapper 失败”的类似案例

`openai/codex#18486` 描述：Windows 上同一个 Node MCP server，手动用 stdio JSON-RPC 调用成功，但 Codex Desktop 的 MCP wrapper 立即报 `Transport closed`，并且第一次失败后重复调用继续立即失败。

这和我们当前现象非常接近：底层服务可用，但 Codex 当前工具包装层/transport 句柄不可用。

来源：

- https://github.com/openai/codex/issues/18486

### 4. Browser MCP 也出现过“transport 掉线后本 session 不可靠”的报告

`openai/codex#13138` 描述：浏览器 MCP transport 中途掉线后，同一 session 变得不可靠；期望 Codex 自动恢复，不要求用户重启 app。issue 提到已有修复思路包括匹配 `Transport closed`、`Broken pipe` 等 transport failure，并做 in-session recovery。

这说明上游知道这类问题属于 Codex host 的恢复能力，不是单个插件独有问题。

来源：

- https://github.com/openai/codex/issues/13138

### 5. 远程 session 过期、HTTP stale session 也有同类问题

开放 Web 搜索还命中了：

- `openai/codex#13969`：远程 MCP server session 过期后，后续 MCP tool call 永久失败，fresh initialization 才能恢复。
- `openai/codex#12869`：streamable HTTP MCP stale session 后 CLI 退化，后续 tool call 失败。
- `openai/codex#18977`：stdio MCP tool calls 可能在底层操作健康时仍报 raw `Transport closed`，疑似 stale/closed transport handle。
- `openai/codex#18527`：配置中存在的远程 OAuth MCP server 在新 thread 工具目录里缺失，说明“工具不可见”和“transport closed”是两类不同故障。

这些证据说明：问题不是只发生在我们自己的插件，也不是只发生在 Windows；它覆盖 stdio、HTTP、remote MCP、browser MCP、Desktop、CLI、长会话等多种形态。

来源：

- https://github.com/openai/codex/issues/13969
- https://github.com/openai/codex/issues/12869
- https://github.com/openai/codex/issues/18977
- https://github.com/openai/codex/issues/18527

## 中文社区和用户体验证据

这些证据不如 OpenAI issue 和官方 README 强，但对“产品该怎么讲人话”很重要。

### 知乎

`search_zhihu` 命中多篇 Codex/MCP 配置经验，其中包括：

- “Codex 配置 MCP 实战指南：从原理、接入到排错，一次讲清楚”
- “codex 如何使用mcp？？”

其中有文章提到 Windows 上 Codex 使用 MCP 容易遇到问题，并转向 `mcp-router` 这类统一管理方案。它不能证明当前句柄是否能热修，但能证明普通用户确实会在 Codex/MCP/Windows 组合里卡住。

### 微信公众号

`search_wechat_articles` 命中：

- “详解 MCP 传输机制”：解释 MCP transport、stdio、JSON-RPC。
- “Codex ＋ Chrome-DevTools MCP 配置全流程”：用户遇到 Chrome MCP 启动不了，并通过搜索 openai GitHub issue 解决。
- “Claude Code 与 Codex 协作开发 3.0”：提到 MCP 作为独立进程长时间运行可能有卡死、session ID 丢失、socket timeout 等稳定性问题。

这些补充说明：MCP 传输和长时间进程稳定性是现实问题，不是 Codex Praetor 单点问题。

### B站和 YouTube

`search_bilibili` 命中多条 Codex/MCP 配置、插件不显示、登录报错、上下文卡住等视频。`search_youtube` 命中 MCP/Codex 能力总线解释类视频。

这两类结果对“当前句柄不能原地热修”没有强证明力，但说明用户教育和故障路径必须足够简单。

### 小红书

`search_xiaohongshu` 命中“为何我给 Hermes 发消息会打断 codex MCP”“codex 连不上 figma 看这里”“Codex 桌面端的一个严重的 BUG”等体验贴。

进一步用 `get_content_detail` 抽取第一条详情，正文明确描述：用户通过 Hermes/飞书指挥 Codex 工作时，收到反馈称每次新消息会打断正在跑的 Codex MCP 调用。这是弱到中等强度的用户体验证据，说明用户真正感受到的是“工具/任务突然被打断”，而不是底层 transport 术语。

## 学术和协议背景证据

`search_academic` 命中 MCP survey 和 agent protocol robustness 相关论文线索。它们不直接回答 Codex 的实现问题，但支持一个背景判断：MCP 是 session-oriented、JSON-RPC、capability negotiation 的协议体系；连接生命周期、transport latency、token/session lifecycle、failure recovery 是协议层面的真实挑战。

代表线索：

- “A Survey on Model Context Protocol: Architecture, State-of-the-art, Challenges and Future Directions”
- “ProtocolBench: Which LLM MultiAgent Protocol to Choose?”

这些作为背景证据，不作为 Codex 当前行为的直接依据。

## 为什么“当前句柄”不能热修

这里的关键是“工具句柄”不是 MCP server 本身。

当前模型回合开始时，Codex host 把可用工具注入给模型。模型看到的是一批已经绑定好的工具命名空间和调用入口，例如：

```text
mcp__codex_praetor.codex_praetor_route_intent
```

如果这个入口背后的 transport 已经关闭，模型在当前回合里没有能力：

1. 改写自己的工具列表。
2. 替换这个工具入口背后的 transport handle。
3. 重新初始化 MCP client 并把新句柄塞回当前工具命名空间。
4. 要求 Codex host 重新生成当前回合的 tool schema。

app-server 可以 reload，也可以直接 call tool，但那是另一个控制通道。它能证明服务层活着，也能作为恢复脚本的底层能力；它不能让当前这个已经坏掉的 `mcp__codex_praetor.*` 函数对象在同一个模型回合里自动变好。

## 能修到什么程度

### 能修：底层服务和后续上下文

可行方案：

1. `config/mcpServer/reload`
2. `mcpServerStatus/list`
3. `thread/resume`
4. `mcpServer/tool/call` 做最小 probe
5. 下一次 active turn 或 fresh context 再走原生工具面

这条路本机已经验证成功。

### 能绕：当前回合继续用 app-server 直接调用

如果当前回合必须继续完成任务，可以不用坏掉的 `mcp__codex_praetor.*` 句柄，而是通过 app-server 脚本直接调用：

```text
mcpServer/tool/call
```

这不是“修好了当前工具句柄”，而是绕过坏句柄，用官方控制通道调用同一个 MCP 工具。

### 不能修：同一回合原地替换当前工具句柄

目前没有看到官方文档、app-server API 或本机实测证据支持“把当前模型回合中已经坏掉的工具句柄原地替换成新 transport”。

## 对 Codex Praetor 的产品结论

### 正确策略

1. 正常路径不检查、不 reload、不 doctor。
2. 第一次工具失败时，自动后台执行 reload/status/probe。
3. probe 成功后，当前回合可用 app-server 直接调用作为兜底。
4. 下一次 active turn 再尝试原生工具面。
5. 如果仍失败，再提示用户重载 Codex 或开启 fresh-context 验收。

### 不正确策略

- 每次调用前全量 doctor。
- 把 `Transport closed` 解释成 Codex Praetor server 必然坏了。
- 每次失败都要求用户开新对话。
- 承诺当前坏句柄可以在同一回合原地修复。
- 用 Codex 原生 subagent 作为 fallback。

## 推荐实现

下一阶段应新增两个轻量脚本：

### `scripts/reload-codex-praetor-mcp.ps1`

职责：

- 调 `config/mcpServer/reload`。
- 调 `mcpServerStatus/list`。
- 只输出 compact 状态。

输出建议：

```text
ok: codex-praetor found, tools=8
```

### `scripts/probe-codex-praetor-mcp.ps1`

职责：

- `thread/resume`
- `mcpServer/tool/call codex_praetor_route_intent`
- 返回三态：
  - `ok`
  - `service_visible_but_direct_handle_stale`
  - `manual_reload_needed`

这两个脚本只在失败恢复时使用，不进入正常调用前置。

## 最终判断

**当前工具句柄坏了，不能在同一模型回合里原地修。**

但这不是绝望结论。真正可产品化的答案是：

- 底层 MCP 可以 reload。
- 旧线程可以通过 app-server probe 验证。
- 当前回合可以用 app-server 直接调用作为兜底。
- 下一次 active turn 或 fresh context 可以拿到更干净的工具上下文。
- 最终彻底自动恢复需要 Codex host 上游支持“transport closed 后重建并替换 MCP client/stdio process handle，再 retry 一次”。
