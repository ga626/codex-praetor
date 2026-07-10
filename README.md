# Codex Praetor

[简体中文](README.md) | [English](README.en.md)

Codex Praetor，中文名 **Codex 执政官**，是给 Codex 用的外部 Agent 编排工具。

它解决的是一个很具体的问题：当你说“拆分任务”“分配给其他 agent”“让别的 agent 做一部分”时，Codex 不应该默认再开自己的 Codex subagent，而应该优先把边界清楚的小任务派给本机已有的外部 CLI 工具，比如 Qoder、CodeBuddy、MiMo。Codex 仍然负责规划、判断风险、整合结果和最终验收。

## 当前状态

这个项目已经进入 **alpha 发布前验收阶段**。

已经完成：

- 项目已经完成独立仓库迁移。
- Skill、脚本、MCP 薄封装和插件包结构已经完成。
- MCP 已经实现任务意图识别、dry-run 派工、任务列表、状态查询、计划生成、lane 查询和冲突检测。
- GitHub 仓库已经创建并推送到 `ga626/codex-praetor`。
- CI 已经跑通过。
- 本地 release zip 已经可以构建。
- 已经做过一次 MiMo 只读真实链路审计。

还没有正式发布：

- 还需要清理和重装本机安装版，确保旧插件缓存不会和新版并存。
- 还需要在一个全新的 Codex 对话里完成全功能 MCP/插件验收。
- 还需要确认中文主界面、英文切换、安装说明、隐私清理和 release 包内容都符合公开发布要求。
- 验收通过后才会创建 GitHub tag 和 GitHub Release。

## 它做什么

Codex Praetor 有四层：

1. **Skill**：让 Codex 理解“拆分任务给外部 agent”这类自然语言。
2. **Scripts**：用 PowerShell 做稳定、可记录、Windows 友好的派工。
3. **MCP**：把脚本能力包成 Codex 能看见的工具调用。
4. **Plugin**：把 Skill 和 MCP 打包成 Codex 插件，方便安装和发布。

## 边界

- 不默认创建 Codex 原生 subagent。
- 不默认使用 provider `auto`。
- 不读取或发布你的 provider 账号数据库、token、cookie、使用截图。
- 不要求用户必须同时安装 Qoder、CodeBuddy、MiMo。
- 没装某个 provider 时，只禁用那个 provider 的真实派工，不影响计划、dry-run、状态查询和 MCP 基础能力。
- Worker 如果要改代码，必须使用隔离 worktree。
- D 盘是开发源，C 盘 `%USERPROFILE%\.codex\skills\codex-praetor` 是本机安装版。两者不做软链接，不自动同步。

## 适用范围

当前版本只面向：

- Windows
- Codex Desktop
- 本机 CLI worker
- 中文用户优先
- Qoder / CodeBuddy / MiMo 三类外部工具

这不是通用多 Agent 平台。它是一个小而清楚的 Codex 辅助工具。

## 目录结构

```text
README.md         中文主页，GitHub 默认展示。
README.en.md      英文说明。
AGENTS.md         给后续 Codex 维护者看的项目规则。
docs/             架构、路线图、验收、发布说明。
skill/            开发源 Skill。
scripts/          派工、watcher、doctor、发布脚本。
mcp/              TypeScript MCP 服务源代码。
plugin/           最终 Codex 插件包结构。
config/           provider 配置模板。
examples/         小型验证样例。
```

## 安装前准备

你至少需要：

- Windows
- PowerShell
- Git
- Node.js 和 npm
- Codex Desktop

真实派工还需要至少安装并登录一个外部 CLI：

- Qoder 或 QoderWork CN
- Tencent CodeBuddy 或 WorkBuddy
- Xiaomi MiMo Code

如果你没有安装这些外部 CLI，也可以先验证 Codex Praetor 的插件、MCP、计划和 dry-run 能力。

## 本地配置

复制配置模板：

```powershell
Copy-Item .\config\codex-praetor-tiers.example.json .\config\codex-praetor.local.json
```

然后在本地配置里填入你已经安装的 provider CLI 路径。没有安装的 provider 可以先留空或保留模板值。

这个本地配置不会被提交。

## 本地验证

运行 doctor：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\doctor-codex-praetor.ps1 -RequireHead -PublicRelease
```

运行测试：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\test-codex-praetor.ps1
```

运行 dry-run：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\invoke-codex-praetor.ps1 -Provider mimo -Tier mimo-auto-readonly -Repo "<repo>" -Task "Dry run only. Verify Codex Praetor." -Mode readonly -DryRun
```

## MCP 和插件验收

发布前必须完成一个全新的 Codex 对话验收。

验收目标：

- Codex 能看到 `codex-praetor` 插件。
- Codex 能看到 `codex_praetor_*` MCP 工具。
- 自然语言“拆分任务给其他 agent”会走 Codex Praetor 外部 worker 路线。
- 不会创建 Codex 原生 subagent。
- dry-run、plan、list-jobs、status、lane 查询和冲突检测都能正常返回。
- provider 缺失时给出清楚提示，不崩溃。
- 本机只保留一个有效安装版本，旧版本不会同时生效。

完整验收提示词保存在本地内部文档中，不随公开 release 包发布。

## 发布包

构建 release zip：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\build-codex-praetor-release.ps1 -Apply
```

release 包不会包含：

- token
- auth 文件
- provider 账号数据库
- 本机私有配置
- handoff 材料
- `node_modules`
- 本地缓存
- 个人截图或使用记录

正式发布前必须确认 GitHub URL 已经替换为真实仓库地址，不能留下 `YOUR_GITHUB_OWNER` 这类占位符。

## GitHub 发布

当前仓库地址：

[https://github.com/ga626/codex-praetor](https://github.com/ga626/codex-praetor)

发布顺序：

1. 本地 doctor 通过。
2. 测试通过。
3. release 包扫描通过。
4. 本机安装版清理和重装通过。
5. 新 Codex 对话全功能验收通过。
6. 创建 `v0.1.0-alpha` tag。
7. 创建 GitHub Release。
8. 上传 release zip。

## 常见问题

**没有安装 Qoder / CodeBuddy / MiMo 怎么办？**

可以先用计划、dry-run、MCP 和插件能力。真实派工需要至少一个 provider CLI。

**provider 已经安装但没有登录怎么办？**

请按 provider 自己的方式登录。Codex Praetor 不读取你的账号数据库。

**MCP 工具显示了，但调用时报 `Transport closed` 怎么办？**

通常是当前 Codex 对话里保留了旧 transport。需要清理重复安装、重新安装插件，并在新的 Codex 对话里验收。

**为什么不直接用 Codex subagent？**

因为这个项目的目标是把小任务派给外部低成本 CLI worker。Codex subagent 是另一条路线，会继续消耗 Codex 模型资源。

**为什么 D 盘和 C 盘不做自动同步？**

D 盘是开发源，C 盘是本机安装版。自动同步容易把开发中的文件带进安装版，也容易造成旧版本和新版本混在一起。这个项目要求显式复制、显式验证。

## 路线图

看 [docs/roadmap.md](docs/roadmap.md)。
