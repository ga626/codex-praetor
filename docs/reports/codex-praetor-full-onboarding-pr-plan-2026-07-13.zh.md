# Codex Praetor 完整开箱向导与一次 PR 收口方案

日期：2026-07-13  
范围：Codex Praetor Windows 用户下载、安装、provider 引导、人工授权配合、只读验收、公开文档和发布验收的一次性产品化 PR  
结论级别：外部资料已重新核对，当前思路成立；建议用一个 PR 完整收口，不再拆成“先改向导、后改文档验收”两段。

## 结论

这次应该按一个 PR 完成。

原因很简单：用户拿到的是一个产品体验，不是一个代码模块。只把安装向导做完，却不同时更新首页、安装指南、provider 页面、排错说明、验收清单和 Release 说明，会让用户看到的说明和实际体验不一致。反过来，只改文档不改向导，也只是继续把复杂度丢给用户。所以这次 PR 的边界应该是：

> 用户从 GitHub 下载 Codex Praetor，双击一个入口，按中文向导完成本体安装；可以选择全部配置 provider、全部不配置，或只配置 Qoder / CodeBuddy / MiMo 中任意一个；provider 没装时，向导在用户确认后执行官方安装命令，并刷新 PATH、复检版本；涉及账号、扫码、浏览器授权、Token Plan、API key 的步骤由用户本人在官方流程中完成；向导负责等待、复检、记录本机路径、运行只读验收，并给出最终状态总览。

这个目标可以实现，但不能做成“完全无人值守”。外部证据再次确认：Qoder、CodeBuddy 和 MiMo 都把账号、授权、站点选择、Token Plan、账单或 API key 放在各自官方边界里。Codex Praetor 可以把用户带到正确位置，可以等待用户完成，可以复检结果；但不能替用户输入密码、扫码、选择企业域、购买套餐、复制密钥、读取账号数据库或判断余额。

## 这次外部调研更新了什么

这次重新核对后，旧报告的大方向没有被推翻，但有三个地方要说得更准确。

第一，Codex 的产品方向仍然支持我们现在的形态。OpenAI 文档说明，插件可以把 Skill、MCP-backed app 或二者组合打包给 ChatGPT/Codex 使用；插件安装后可以给新任务增加 skills、connectors 和 MCP tools。也就是说，Codex Praetor 作为“Skill + MCP + Plugin”的产品形态是正确方向，不应该退回到只让用户运行脚本。

第二，外部 CLI 的登录体验已经有成熟范式。GitHub CLI、Azure CLI、Cloudflare Wrangler、Vercel CLI 都采用“CLI 发起，浏览器或 device flow 授权，用户确认，CLI 继续”的模式。RFC 8628 也把“程序显示 URL/验证码，用户在浏览器完成授权，程序等待结果”定义成标准思路。我们的向导不需要自己实现三家 provider 的 OAuth，但可以采用同样的交互结构：停下来告诉用户现在要做什么，用户完成后回到向导点继续检测。

第三，CLI 对普通用户并不天然友好。Google/ACM 的 CLI 可访问性研究指出，CLI 是非结构化文本界面，会有自己的可访问性问题。CLI UX 资料也反复强调，好的命令行工具应该在工具本身里给用户下一步，而不是把用户扔进十页文档。对 Codex Praetor 来说，这意味着“显示文档路径”还不够；向导必须把“装好了什么、还缺什么、下一步点哪里、失败是什么意思”讲清楚。

## 改动前项目做到了哪里

现在的版本已经不是空壳。它已经有这些能力：

- 用户可以从 Release 下载安装包。
- 解压后可以双击一个入口安装 Codex Praetor 本体。
- 安装时会检查 PowerShell、Node.js、Git 和三家 provider 命令是否可发现。
- 用户可以先不配置任何 provider，只验证 Codex Praetor 本体。
- Codex 里已经有外部 worker 路由、dry-run、任务状态、lane 查询、冲突检测等 MCP 工具。
- 三家 provider 都已经有只读 canary 思路：让外部 agent 只读 `README` 并返回成功标记，主仓库保持干净。
- README、安装指南、排错指南、隐私边界、provider 页面、验收清单和 release 文档都已经存在。

真正没完成的是“把这些点串起来”。改动前的向导看到 provider 以后，只会告诉用户“发现了 / 没发现 / 去看某个文档”。它还没有做到：

- 带用户选择“全部配置 / 都不配置 / 只配置某一家”后的完整流程。
- 对没装的 provider 给出官方安装路径，并在用户确认后执行官方安装命令。
- 安装后刷新当前终端 PATH 并重新检测。
- 用户需要登录、扫码、选择站点或配置 Token Plan 时，进入“请完成官方授权，我在这里等你”的中间页。
- 用户点“已完成”后复检 provider 状态。
- 把可用 provider 的 CLI 路径写入本机忽略配置。
- 在向导里直接发起只读 canary。
- 最后用一张中文总览告诉用户：本体是否可用、哪些 provider 可真实派工、哪些还缺登录、哪些只是可尝试、下一步在 Codex 里输入什么。

## 本次 PR 的最终用户体验

这个 PR 完成后，普通用户看到的流程应该是这样。

用户下载 `codex-praetor-setup-版本号.zip`。Release 页面明确告诉他：普通用户下载 setup 包，不要下载 GitHub 自动生成的 Source code。README 第一屏也说清楚：这是给 Codex 用的外部 agent 派工插件，可以先不装 provider 验证本体，真实派工至少需要 Qoder、CodeBuddy 或 MiMo 中一个可用。

用户解压到桌面、下载目录或任意临时目录，双击根目录入口。向导第一屏不用讲 MCP、Skill、插件目录这些内部词，而是说：

```text
这个向导会安装 Codex Praetor 本体，并帮助你检查或配置 Qoder、CodeBuddy、MiMo。
它不会替你登录账号，不会读取 token、cookie、账号数据库，也不会替你确认账单。
你可以先跳过 provider，只验证 Codex Praetor 本体。
```

然后向导检查基础环境。这里要区分“本体安装必须项”和“真实派工可选项”。PowerShell、用户插件目录可写、本体包完整性是必须项；Node/npm、WinGet、Git、provider 命令是能力项。Node 缺失不能吓用户说安装失败，只能说：本体可以安装，但某些 provider 的 npm 安装方式不可用。

本体安装完成后，向导进入 provider 选择：

```text
1. 配置全部 provider
2. 先不配置 provider，只验证 Codex Praetor 本体
3. 只配置 Qoder
4. 只配置 CodeBuddy
5. 只配置 MiMo
```

推荐默认仍然是第 2 项，因为它保证用户不会被第三方账号流程卡住本体安装。但第 1 项必须存在，因为用户的直觉就是“一次配齐”。

如果用户选择某个 provider，向导先判断它是否已经安装。已安装就显示版本和下一步授权提示；未安装就给出官方安装方式，并让用户选择“执行官方安装命令 / 打开官方说明 / 重新检测 / 跳过”。用户确认后，向导执行官方命令，刷新当前进程 PATH，再复检命令和版本。这里不引入第三方镜像，不把 provider 打进 Codex Praetor 包，也不在未经用户确认时安装 Node 或 provider。

到登录或授权时，向导不代办，只等待。比如：

```text
现在请在 Qoder 官方窗口里完成登录。
你可能会看到浏览器登录、验证码、PAT 或终端交互提示。

[Enter] 我已完成，继续检测
[S] 跳过 Qoder
```

CodeBuddy 也类似，但要明确用户可能要选择中国站、国际站、企业域或 iOA。MiMo 则优先走 `mimo/mimo-auto`；如果 Auto 失败，才提示 `/connect`、MiMo Platform、Token Plan 或 API key。

用户点继续后，向导重新检测命令和版本；如果用户愿意，继续预览或运行真实只读 canary。canary 的意义要讲人话：

> 这一步不是让 agent 改代码，而是让它读一个固定文件并返回固定标记，用来证明 Codex Praetor 确实能调用它。通过后，才建议真实派工。

最后显示状态总览：

```text
Codex Praetor 本体：已安装，可 dry-run
Codex 插件：已写入，重启 Codex 或打开新任务后可发现
MCP 工具：已随插件安装，新任务中应能看到
Qoder：已安装，登录未知 / canary 已通过 / 已跳过
CodeBuddy：未安装 / 已安装，需登录 / canary 已通过
MiMo：Auto 可尝试 / Auto 已通过 / 需连接 provider
下一步：打开 Codex 新任务，输入“拆分一下任务，分配给其他 agent 做 dry-run，不要真实修改文件。”
```

这个总览是本次 PR 的产品成败关键。用户不需要知道哪些脚本被改了，他只需要知道“我现在能做什么”。

## 三家 provider 的处理方式

Qoder 的正确体验是：向导检测 `qodercli`，没有就给官方 Windows 安装方式；首次使用需要认证，官方文档写明推荐交互登录，也支持环境变量用于自动化。向导可以打开登录说明或提示用户进入 TUI，但不应该要求普通用户粘贴 PAT。PAT 更适合自动化，不适合作为小白主路径。Windows on Arm 不支持也要在失败提示里讲清楚，避免用户误以为 Codex Praetor 坏了。

CodeBuddy 的正确体验是：向导先检测 Node.js 和 `codebuddy`。官方 Quick Start 写明 Node.js 18.20+ 和 Windows/macOS/Linux 支持；安装可以走 npm，全局命令安装后用 `codebuddy --version` 验证。首次使用需要登录，并可能选择中国站、国际站、企业域或 iOA。向导不能替用户选站点或判断账号权益，只能提示“请在官方流程完成登录，然后回来继续检测”。

MiMo 的正确体验是：向导优先检测 `mimo`，未安装时给官方 PowerShell 安装或 npm fallback。官方 GitHub README 写明 MiMo Auto 是限时免费、匿名、零配置通道，首次启动会自动引导配置；但 MiMo Platform / Token Plan / 自定义 provider 仍然涉及授权、余额、API key 或账单。向导默认先尝试 `mimo/mimo-auto` 的只读 canary；失败时把问题归类为 MiMo 免费通道、版本、网络或官方策略变化，而不是 Codex Praetor 本体失败。

## 文档要怎么改

文档要和向导一起改，不能滞后。

首页要从“工程说明”变成“产品入口”。第一屏只讲三件事：这是什么、下载哪里、能不能先不装 provider。MCP、Skill、目录结构和开发者命令后移。

安装指南要从“PowerShell 操作说明”变成“普通用户路径”。主路径是下载、解压、双击、选择是否配置 provider、看状态总览、回 Codex dry-run。命令行只作为高级路径保留。

Provider 总览页要告诉用户：只装一个也可以；没装 provider 也能验证本体；真实派工至少需要一个 provider 通过只读 canary。三家页面统一模板：它是什么、什么时候需要、官方安装方式、如何验证、登录/授权怎么做、Codex Praetor 会做什么、哪些问题不是 Codex Praetor 的问题、失败后下一步。

Qoder 页面要强调交互登录是普通路径，PAT/环境变量是自动化路径；Windows on Arm 不支持是 provider 边界。

CodeBuddy 页面要强调 Node.js 18.20+、npm 安装、Native Binary Beta、首次登录选择站点/企业域/iOA、Git Bash 缺失时的行为和 PATH/旧版本问题。

MiMo 页面要把 MiMo Auto 和 MiMo Platform 分开讲：Auto 是限时免费匿名通道，优先尝试；Platform/Token Plan/API key 是另一条路线，涉及用户授权和余额。

排错指南要按用户看到的现象组织，而不是按内部模块组织。比如：安装完看不到插件、看到了插件但没有 MCP 工具、provider 命令找不到、provider 要登录、余额或 Token Plan 不够、Transport closed、自然语言派工却走了 Codex 原生 subagent、想卸载。

路线图要移除或改写“不会安装 provider”这种容易误解的话。正确说法是：不会替用户登录、不会读取凭据、不会未经确认安装或越过官方流程；但会在用户确认后执行官方安装命令，并提供授权陪跑、复检和 canary。

验收清单要升级成完整用户链路：从 GitHub 首页到 Release 下载，从双击入口到本体安装，从跳过 provider 的 dry-run 到安装一个 provider 的 canary，再到自然语言派工不走 Codex 原生 subagent。

Release 说明要中文优先，明确普通用户下载 setup 包，不要下载 Source code；说明 alpha 边界；说明不包含 provider、不保存密钥、没有 provider 也能先验证本体。

## 技术边界讲人话

这次 PR 要实现的不是“自动装好所有账号”，而是“把复杂流程变成有人看得懂的导航”。

安全边界是：Codex Praetor 只保存本机 CLI 路径、用户选择、步骤状态、版本、canary 状态和非敏感失败原因；不保存 token、cookie、PAT、API key、账号数据库、余额页面或截图。需要密钥的 provider，由 provider 自己保存；Codex Praetor 只调用 provider 官方 CLI。

状态边界是：`已安装` 不等于 `可真实派工`。真实派工至少要经过“命令可见、用户完成官方登录或选择可匿名路线、只读 canary 通过”这几步。

失败边界是：provider 登录失败、余额不足、企业域选择错误、MiMo Auto 政策变化，都不应该算 Codex Praetor 本体坏了。向导要把这些归类成“provider 需要你处理”，并给下一步。

体验边界是：不要把所有 doctor 检查塞到一开始。安装时只做轻量检查；doctor 留给发布前、提交 issue 前或用户主动要求。

## 一次 PR 的完成标准

这个 PR 只有在下面这些都完成时才算完成。

第一，普通用户可以从 GitHub 首页看懂下载哪个包。

第二，下载后双击入口能完成 Codex Praetor 本体安装。

第三，向导里能选择全部配置、全部跳过、只配置任意一家 provider。

第四，对每家 provider，向导能做到检测、官方安装引导、等待用户授权、复检、可选 canary。

第五，向导最后输出清楚状态总览，而不是只吐出命令和路径。

第六，没有 provider 时，本体 dry-run 仍然可用；这不能被当成失败。

第七，只装一个 provider 并完成授权后，可以跑只读 canary；不要求三家都装。

第八，文档和向导口径一致，不再出现“向导能引导配置”和“不会安装 provider”互相打架的说法。

第九，发布包不包含内部交接材料、本机路径、local config、token、auth、cookie、provider 数据库或运行日志。

第十，最终验收必须从用户视角跑：打开仓库、下载、解压、双击、跳过 provider dry-run、配置至少一个 provider、完成官方授权、跑 canary、在 Codex 里确认自然语言派工走 Codex Praetor 而不是 Codex 原生 subagent。

## 本次 PR 实施清单

本次 PR 按这份方案一次收口，不再拆成“先改向导、后改文档验收”两段。

用户能直接感受到的变化是：

- 双击安装入口后，向导不再只是展示 provider 文档路径，而是提供 5 个选择：全部配置、全部跳过、只配置 Qoder、只配置 CodeBuddy、只配置 MiMo。
- 选择 provider 后，向导会在用户确认后执行官方安装命令，提示用户完成官方登录、浏览器授权、站点选择、企业域、Token Plan 或 API key 等账号动作，然后回到向导复检。
- 已经能发现的 provider CLI 会写入当前 Windows 用户的本机配置。这个配置只记录 CLI 路径，不记录 token、cookie、PAT、API key、账号数据库或余额页面。
- 向导最后会输出中文状态总览，告诉用户本体是否安装成功、哪些 provider 已跳过、哪些 provider 已发现、哪些还需要登录或 canary。
- 没有 provider 时，本体安装和 dry-run 仍然是成功路径；真实派工才需要至少一个 provider 完成官方授权和只读 canary。

文档同步的变化是：

- 首页把“下载、双击、选择 provider、先 dry-run”放到普通用户路径里。
- 安装指南补上向导的 5 个选择，以及每个选择到底意味着什么。
- Provider 页面统一说明：Codex Praetor 会在用户确认后执行官方安装命令、等待用户完成官方登录、复检和记录 CLI 路径，但不会未经确认静默安装、代登录或读取凭据。
- 排错指南按用户看到的现象解释：没 provider 不是本体故障，provider 已安装但失败时先重新走向导和官方登录，再跑只读 canary。
- 路线图把完整安装向导列入已完成，把下一阶段收窄到真实派工失败恢复、插件缓存恢复和发布校验体验。
- 验收清单新增 5 选项向导、本机配置写入、最终状态总览和只读 canary 的用户视角检查。

## 证据登记

| 编号 | 来源 | 关键事实 | 对本 PR 的影响 | 强度 |
| --- | --- | --- | --- | --- |
| E1 | OpenAI Codex Plugins 文档：`https://developers.openai.com/codex/plugins` | 插件可以把 skills、connectors、MCP tools 带入新任务；CLI/IDE/Desktop 都有插件入口。 | Codex Praetor 继续走 plugin 分发是正确方向。 | 强 |
| E2 | OpenAI Build plugins 文档：`https://developers.openai.com/codex/build-plugins` | 插件结构包含 manifest、skills、hooks、`.mcp.json`、assets 等。 | 当前 repo 的 Skill + MCP + Plugin 结构合理，PR 不应退化成脚本包。 | 强 |
| E3 | OpenAI MCP 文档：`https://developers.openai.com/codex/mcp` | MCP 配置在 Codex config 中，Desktop/CLI/IDE 可共享配置。 | 安装后需要提示重启或新任务刷新工具上下文。 | 强 |
| E4 | GitHub README 文档：`https://docs.github.com/.../about-readmes` | README 应说明项目做什么、为什么有用、如何开始、哪里求助。 | README 第一屏必须产品化，不能先讲内部架构。 | 强 |
| E5 | GitHub Release 文档：`https://docs.github.com/.../managing-releases-in-a-repository` | Release 可以附加二进制/资产，并可标记 prerelease。 | Release 页面要明确 setup 包是用户入口。 | 强 |
| E6 | GitHub Source archives 文档：`https://docs.github.com/.../downloading-source-code-archives` | Source code zip/tar.gz 是仓库快照，不等于安装包。 | Release 说明必须提醒普通用户不要下载 Source code。 | 强 |
| E7 | Microsoft WinGet 文档：`https://learn.microsoft.com/windows/package-manager/winget/` | WinGet 是 Windows 包管理客户端，但新用户首次登录后才可能注册完成。 | 向导可检测 WinGet，但不能依赖它一定存在。 | 强 |
| E8 | PowerShell ExecutionPolicy 文档：`https://learn.microsoft.com/powershell/module/microsoft.powershell.security/set-executionpolicy` | 执行策略是安全策略，组策略可能覆盖本机设置；Process 作用域只影响当前会话。 | 向导只用本次进程绕过，不永久修改系统策略。 | 强 |
| E9 | npm 安装 Node/npm 文档：`https://docs.npmjs.com/downloading-and-installing-node-js-and-npm/` | npm 官方建议先检查 node/npm，Windows 可用安装器或版本管理器；全局包可能有权限问题。 | Node/npm 缺失应作为 provider 能力问题，不阻断本体安装。 | 强 |
| E10 | npm Windows global config 文档：`https://docs.npmjs.com/try-the-latest-stable-version-of-npm/` | Windows npm 全局安装路径可能需要核对。 | 向导要检测命令是否真的进入 PATH，而不是只相信 npm 成功。 | 强 |
| E11 | Qoder CLI Quick Start：`https://docs.qoder.com/en/cli/quick-start` | Qoder 支持 Windows PowerShell 安装，Windows on Arm 暂不支持；使用前需要认证，交互登录推荐。 | 向导可引导安装和登录，但不能代替用户认证。 | 强 |
| E12 | CodeBuddy Quick Start：`https://www.codebuddy.ai/docs/cli/quickstart` | CodeBuddy 需要 Node.js 18.20+，支持 Windows；首次使用需要登录认证。 | 向导要区分安装成功和登录完成。 | 强 |
| E13 | CodeBuddy Installation：`https://www.codebuddy.ai/docs/cli/installation` | npm 全局安装是官方路径；安装后用 `codebuddy --version` 验证。 | 向导可检测版本并引导官方安装。 | 强 |
| E14 | CodeBuddy Troubleshooting：`https://www.codebuddy.ai/docs/cli/troubleshooting` | Windows 下 Git Bash 推荐，缺失时会 fallback 到 PowerShell；Node 版本是常见问题。 | 排错文档要按用户现象解释，不把它都归为 Codex Praetor 错。 | 强 |
| E15 | MiMo Code GitHub：`https://github.com/XiaomiMiMo/MiMo-Code` | Windows PowerShell 安装、npm fallback、MiMo Auto 限时免费匿名通道、首次启动自动配置。 | MiMo 默认优先 Auto canary，但不能承诺永久免费。 | 强 |
| E16 | Xiaomi MiMo Code 配置文档：`https://mimo.mi.com/docs/en-US/tokenplan/integration/mimo-code` | MiMo Platform/Token Plan 路线支持授权登录、余额或 Token Plan、API key 管理。 | MiMo Auto 与 Platform/API key 要分开讲。 | 强 |
| E17 | RFC 8628：`https://datatracker.ietf.org/doc/html/rfc8628` | Device flow 让程序显示 URL/验证码，用户在浏览器完成授权，客户端等待结果。 | 向导的“请完成官方授权，我在这里等你”是成熟模式。 | 强 |
| E18 | GitHub CLI auth 文档：`https://cli.github.com/manual/gh_auth_login` | 默认是浏览器登录，完成后 token 存入系统凭据存储；无凭据存储时 fallback 到文件。 | 外部 CLI 登录应由 provider 自己处理凭据，Codex Praetor 不碰。 | 强 |
| E19 | Azure CLI 登录文档：`https://learn.microsoft.com/cli/azure/authenticate-azure-cli-interactively` | CLI 可打开浏览器，失败时可用 device code；MFA 使用户名密码不适合自动化。 | 人工登录不是缺陷，是现代 CLI 的正常安全边界。 | 强 |
| E20 | Cloudflare Wrangler login 文档：`https://developers.cloudflare.com/workers/wrangler/commands/general/` | Wrangler 用 OAuth 打开浏览器登录；CI 用 API token 另走路径。 | 普通用户路径和自动化路径必须分开。 | 强 |
| E21 | Vercel CLI login changelog：`https://vercel.com/changelog/new-vercel-cli-login-flow` | Vercel CLI 改用 OAuth Device Flow，强调从任意浏览器安全登录。 | 证明 device-flow 风格是新的 CLI 登录趋势。 | 中强 |
| E22 | Google Research / ACM CLI accessibility：`https://research.google/pubs/accessibility-of-command-line-interfaces/` | CLI 是非结构化文本界面，有自己的可访问性问题。 | 向导要减少术语和长日志，给结构化状态。 | 中强 |
| E23 | CLI UX patterns：`https://www.lucasfcosta.com/blog/ux-patterns-cli-tools` | 好的 CLI onboarding 应在工具内引导下一步，而不是要求用户读大量文档。 | 当前“显示文档路径”不够，要把流程串起来。 | 中 |
| E24 | WorkOS CLI auth guide：`https://workos.com/guide/best-practices-for-cli-authentication-a-technical-guide` | CLI auth 常见模式包括 API key、browser OAuth、device flow；应避免明文长期凭据和糟糕恢复路径。 | Codex Praetor 不应保存密钥，应给清晰失败恢复。 | 中 |

## 最终判断

旧报告的核心方向仍然正确，但现在应该把它收束成一个更明确的一次性 PR：

> 做完整开箱向导 MVP，同时更新所有用户可见文档和验收链路。

不建议继续把“向导实现”和“产品化收口”拆开。拆开以后，第一个 PR 用户仍会看到半成品，第二个 PR 又变成修口径。真正合理的边界是：一个 PR 让用户拿到的安装体验、文档说明、排错路径和验收清单全部一致。

这次 PR 不需要做 GUI，不需要做 exe，不需要未经确认安装 Node 或 provider，不需要读取任何 provider 凭据。文本向导足够，但它必须是完整向导，而不是提示菜单。
