# Codex Praetor Windows 用户安装体验与开箱即用方案

日期：2026-07-11  
范围：Codex Praetor 0.1.0-alpha 之后的 Windows 用户安装体验、GitHub 仓库呈现、provider 安装授权引导、轻量验证和发布前整理  
边界：本报告只做调研、判断和改造方案，不执行安装、不修改脚本、不操作本机 Codex 配置、不发布 GitHub、不替用户登录 provider。

## 一句话结论

Codex Praetor 现在已经有产品化骨架：中文 README、英文切换、安装文档、排错文档、隐私说明、provider 说明、release gate、插件目录、MCP 源码、用户安装脚本都已经存在。真正的问题不是“没有东西”，而是普通 Windows 用户从 GitHub 下载后，仍然会觉得自己拿到的是一个工程包，而不是一个可以放心点击、知道下一步该做什么的产品。

下一阶段最应该做的是一个轻量“一体化安装向导”。它不是把 Qoder、CodeBuddy、MiMo、Node.js 全塞进安装包，也不是替用户登录账号，而是把原本分散在 README、脚本、provider 官方文档、排错说明里的动作串成一条人能理解的路：

1. 用户下载 Codex Praetor 安装包。
2. 用户双击中文安装入口。
3. 安装向导检查基础环境。
4. 安装 Codex Praetor 本体。
5. 用户选择是否引导安装 Qoder、CodeBuddy、MiMo。
6. 安装向导只调用官方安装方式或打开官方说明。
7. 登录、扫码、Token Plan、企业域、API key 或免费通道初始化由用户在 provider 官方流程里完成。
8. 安装向导检测命令是否存在，并给出状态总览。
9. 用户回到 Codex，打开新任务或刷新上下文，运行一次 dry-run。
10. 真实派工前，至少有一个 provider 通过 readonly canary。

所以，这个方案可以做到“只运行一个入口程序”，但不能承诺“完全无人值守”。因为账号登录、浏览器授权、套餐确认、企业域选择、Token Plan、API key 和免费通道策略都是各家 provider 的账号和产品边界，Codex Praetor 不能也不应该越过。

## 本轮调研做了什么

本轮按项目规则，先使用 KnowledgeRadar 作为外部调研感知层。已确认 `mcp__knowledgeradar` 工具面可见，17 个工具存在；随后用官方网页、GitHub、B 站、知乎、微信公众号、小红书、学术搜索和正文抽取补证。

这份报告使用的证据分四类：

1. 强证据：官方文档、官方安装页、官方 GitHub 文档、Microsoft Learn、Node.js/npm 官方文档。
2. 中证据：GitHub 仓库 README/issue 形态，用来观察用户入口和文档呈现方式。
3. 弱到中证据：B 站、知乎、公众号、小红书，用来观察中文用户真实卡点，不把它们当官方事实。
4. 辅助证据：CLI 可用性研究，用来说明为什么“给命令”不等于“给产品体验”。

### 调研入口和工具面

| 工具 | 用途 | 本轮结论 |
| --- | --- | --- |
| `health_check` | 确认 KnowledgeRadar 工具面 | 工具面正常，17 个工具可见 |
| `get_capabilities` | 确认来源生态 | 可覆盖开放网页、GitHub、B站、知乎、小红书、公众号、学术等来源 |
| `kr_research` | 建立深度调研路线 | 官方文档和开放网页是主证据，中文平台用于用户卡点 |
| `kr_web_search` | 搜官方安装、依赖、仓库示例 | 找到 Qoder、CodeBuddy、MiMo、Node、WinGet、PowerShell 相关证据 |
| `extract_web_page` | 抽取官方正文 | 成功抽取 Qoder、CodeBuddy、MiMo 关键安装和登录页面 |
| `search_github_repositories` | 查类似项目和 README 形态 | 泛搜噪声较大，只作为仓库呈现参考，不把 stars 当质量证据 |
| `search_bilibili` | 查中文视频教程信号 | 大量“安装、配置、小白、保姆级”内容，说明用户需要可视化步骤 |
| `search_zhihu` | 查中文长文和经验帖 | 账号、安装、Node、配置和命令找不到是常见问题 |
| `search_wechat_articles` | 查公众号教程信号 | 公众号常按“安装基础软件、检查版本、输入命令、登录”写教程 |
| `search_xiaohongshu` | 查轻量用户笔记 | 小白安装、两步使用、保姆教程这类表达很多 |
| `search_academic` | 查 CLI 可用性研究 | CLI 是文本化界面，对普通用户和可访问性都有门槛 |

## 证据摘要

### E1. Codex 官方方向：插件和 MCP 是正路

来源：

- OpenAI Codex 插件文档：`https://developers.openai.com/codex/plugins`
- OpenAI 构建插件文档：`https://developers.openai.com/codex/plugins/build`
- OpenAI MCP 文档：`https://developers.openai.com/codex/mcp`
- OpenAI Skill 文档：`https://developers.openai.com/codex/skills`

结论：

- Codex 的长期方向是把可复用能力打包成插件、skill、MCP server 或 MCP-backed app。
- 普通用户不应该手动理解 `.codex` 目录、MCP 配置、skill 目录和本地开发源目录。
- Codex Praetor 应该最终走插件入口；在公开插件分发完全稳定前，GitHub Release 需要承担“用户拿到安装包”的职责。

对我们的影响：

- README 和 Release 不能写得像源码工程说明，必须先回答“下载哪个、点哪个、成功长什么样”。
- 安装或更新后，Codex 任务里的工具上下文可能需要刷新，这应该作为安装后一次性动作说明，不应该写成每次使用前都要重开。

### E2. GitHub 的职责：README 是门面，Release 是交付入口

来源：

- GitHub Release 文档：`https://docs.github.com/en/repositories/releasing-projects-on-github/managing-releases-in-a-repository`
- GitHub README 文档：`https://docs.github.com/en/repositories/managing-your-repositorys-settings-and-features/customizing-your-repository/about-readmes`
- GitHub 翻译友好写作指南：`https://github.com/github/docs/blob/main/content/contributing/writing-for-github-docs/writing-content-to-be-translated.md`

结论：

- README 是用户进入仓库后最先判断“这是什么、我该怎么开始”的地方。
- Release 是用户拿到可交付软件和发布说明的地方，不应该让普通用户在 source code 和安装包之间猜。
- 中文用户为主时，Release 页面也应该中文为主，英文可以保留为切换入口或附加段落。

对我们的影响：

- 首页第一屏要把“普通用户下载这个”放在架构说明前面。
- Release 资产命名要清楚，例如 `CodexPraetor-Setup.zip` 或 `codex-praetor-setup-0.1.0-alpha.zip`，不要让用户误以为 GitHub 自动生成的 source code 就是安装包。
- 英文版可以保留，但不能抢走中文主链路。

### E3. Windows 安装的正确思路：轻量 bootstrapper

来源：

- Microsoft Bootstrapping 文档：`https://learn.microsoft.com/en-us/windows/win32/msi/bootstrapping`
- Microsoft 应用部署前置条件文档：`https://learn.microsoft.com/en-us/visualstudio/deployment/application-deployment-prerequisites?view=vs-2022`
- Microsoft WinGet 文档：`https://learn.microsoft.com/en-us/windows/package-manager/winget/`
- WinGet install 文档：`https://learn.microsoft.com/en-us/windows/package-manager/winget/install`
- WinGet Configuration 文档：`https://learn.microsoft.com/en-us/windows/package-manager/configuration/`
- PowerShell 执行策略文档：`https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.core/about/about_execution_policies?view=powershell-7.6`

结论：

- “先检查前置条件，再安装缺失组件或引导用户安装”是 Windows 安装器里成熟的 bootstrapper 思路。
- WinGet 可以作为官方 Windows 包管理器通道，但不能假设每台机器都有，也不能把它作为唯一方案。
- PowerShell 执行策略是安全功能。安装入口可以用本次进程临时 `-ExecutionPolicy Bypass`，但不应该永久修改用户系统策略。
- 如果企业组策略阻止脚本运行，向导应该告诉用户“电脑策略阻止运行，请联系管理员或走手动安装”，而不是继续重试。

对我们的影响：

- 安装包不需要臃肿离线化，应该做一个轻量向导。
- 向导可以检测 WinGet、Node、PowerShell、Codex、provider 命令是否存在。
- 向导不应该要求用户先理解执行策略、PATH、管理员权限。

### E4. Node.js 和 npm：不能假设用户已经有

来源：

- Node.js 官方下载页：`https://nodejs.org/en/download`
- Microsoft Windows Node.js 安装指南：`https://learn.microsoft.com/en-us/windows/dev-environment/javascript/nodejs-on-windows`
- npm 下载和安装 Node.js/npm 文档：`https://docs.npmjs.com/downloading-and-installing-node-js-and-npm/`

结论：

- Node.js 是 CodeBuddy 和 MiMo npm 安装路径的重要前置条件；如果走 MiMo 官方 PowerShell 安装脚本，是否需要 Node 以官方脚本当前行为为准。
- npm 官方说明里也提醒，Node/npm 安装和全局包权限可能带来问题。
- 对普通 Windows 用户来说，“先安装 Node，再验证 npm，再 npm 全局安装 provider”已经是一条比较长的路径。

对我们的影响：

- 安装向导要先检查 Node/npm，不存在时给官方安装入口或 WinGet 引导。
- 不要把 Node.js 打进 Codex Praetor 安装包。
- 也不要在用户不知情的情况下静默安装 Node。

### E5. Qoder 官方边界

来源：

- Qoder CLI Quick Start：`https://docs.qoder.com/en/cli/quick-start`
- Qoder CLI 使用文档：`https://docs.qoder.com/en/cli/using-cli`
- Qoder SDK Authentication：`https://docs.qoder.com/en/cli/sdk/authentication`

官方页面确认：

- 支持 macOS、Linux、Windows Terminal。
- 支持 arm64、amd64，但 Windows on Arm 暂不支持。
- Windows PowerShell 安装命令是 `irm https://qoder.com/install.ps1 | iex`。
- Windows CMD 也有安装方式。
- 安装后用 `qodercli --version` 验证。
- 首次使用需要认证。
- 推荐交互登录，也支持 Personal Access Token 和环境变量用于脚本/自动化场景。

对我们的影响：

- Codex Praetor 向导可以检测 `qodercli --version`。
- 向导可以打开 Qoder 登录说明或提示用户在 Qoder TUI 里输入 `/login`。
- 向导不应该要求小白粘贴 PAT。PAT 更适合脚本、CI、宿主集成，不适合作为普通安装主链路。
- Windows on Arm 不支持要写进 provider 页面，避免用户误判为 Codex Praetor 坏了。

### E6. CodeBuddy 官方边界

来源：

- CodeBuddy CLI Quick Start：`https://www.codebuddy.ai/docs/cli/quickstart`
- CodeBuddy 安装文档：`https://www.codebuddy.ai/docs/cli/installation`

官方页面确认：

- Node.js 18.20 或更高是 npm 路径前置条件。
- npm 全局安装命令是 `npm install -g @tencent-ai/codebuddy-code`。
- 安装后用 `codebuddy --version` 验证。
- 官方提供 Native Binary Beta。
- Native Binary Beta 支持 Windows x86_64，目标是单文件、无需 Node.js、自动更新更好。
- Windows 脚本安装命令是 `irm https://www.codebuddy.cn/cli/install.ps1 | iex`。
- 配置目录默认在 `%USERPROFILE%\.codebuddy`。
- 官方文档已经覆盖 PATH、命令找不到、旧版本、网络问题、npm 镜像等问题。

对我们的影响：

- CodeBuddy 是最适合被一体化向导“可选安装引导”的 provider，因为它同时有 npm 路径和原生安装器方向。
- 现阶段向导应该优先检测本机已有 `codebuddy`，再让用户选择 npm 或官方脚本。
- 登录、企业域、国内版/国际版、账号额度不应该放到主 README 第一屏，只放 provider 页面和向导详情。
- 如果用户装了 WorkBuddy 或其它变体，Codex Praetor 需要允许用户填 CLI 路径，不能只靠 PATH 猜。

### E7. MiMo 官方边界：区分免费 Auto 通道和自配 provider

来源：

- MiMo Code 安装页：`https://mimo.xiaomi.com/mimocode/install`
- MiMo Code models/provider 页面：`https://mimo.xiaomi.com/mimocode/models-provider`
- MiMo Code 官方 GitHub 仓库：`https://github.com/XiaomiMiMo/MiMo-Code`
- MiMo Code CLI subcommands：`https://mimo.xiaomi.com/mimocode/cli-subcommands`
- MiMo Code models 页面：`https://mimo.xiaomi.com/mimocode/models`
- MiMo Token Plan 页面线索：`https://platform.xiaomimimo.com/token-plan`

官方页面确认：

- MiMo Code 需要现代终端。
- Windows 推荐安装命令是 `powershell -ep Bypass -c "irm https://mimo.xiaomi.com/install.ps1 | iex"`。
- 官方 GitHub README 明确写到 MiMo Auto 是内置的“限时免费”通道，可以零配置开始使用；首次启动会自动引导配置，支持 MiMo Auto、Xiaomi MiMo Platform、从 Claude Code 导入认证、自定义 provider。
- MiMo Auto 的定位是“free for a limited time / anonymous channel / zero configuration”，对应我们配置里的 `mimo/mimo-auto`。
- models/provider 页面仍然说明：如果用户要连接任意 LLM provider，或者使用 MiMo Platform，需要配置 API key。
- MiMo 推荐新用户使用 MiMo Token Plan，但这是 MiMo Platform/API key 路线，不是 MiMo Auto 免费匿名路线。
- 用户需要在 TUI 里运行 `/connect`，选择 Xiaomi MiMo，登录平台，添加账单信息，复制 API key，再粘贴回工具。
- MiMo Platform 使用 OpenAI-compatible 方式，也支持配置 `MIMO_API_KEY`。
- GitHub issue 里出现过旧版 `mimo providers login` 选择 “MiMo Auto (free)” 后提示“无需登录，直接运行 mimo”的输出，同时也暴露过旧版 0.1.0 的凭据持久化 bug；这说明免费通道真实存在，但稳定性和策略要以当前官方版本为准。
- 本机当前 PATH 中 MiMo 来自一个本地 npm-global 安装，版本是 `0.1.0`；本仓库默认只允许 `mimo/mimo-auto`，并把它作为 `mimo-auto-readonly` 和 `mimo-auto-edit` 两个受控 tier。

对我们的影响：

- MiMo 不能再简单写成“必须登录或必须 API key”。更准确的说法是：优先尝试官方 `MiMo Auto` 免费匿名通道；如果免费通道不可用、过期、额度变化或用户要指定其它模型，再引导 `/connect`、MiMo Platform、Token Plan 或自定义 provider。
- Codex Praetor 可以检测 MiMo 命令存在，并默认使用 `mimo/mimo-auto` 做只读 canary。
- Codex Praetor 不能承诺 MiMo Auto 永久免费，也不能承诺任何地区、版本、账号状态下都一定可用。
- 当 MiMo Auto 失败时，安装向导应把失败归类为“MiMo 免费通道/版本/网络/官方策略问题”，而不是直接归类为 Codex Praetor 本体失败。
- 如果用户选择 MiMo Platform 或其它 provider，API key、账单、Token Plan 必须用户自己处理，Codex Praetor 不能保存或读取密钥。
- 报告和文档中不能继续只写“Windows 主要 npm 安装”，因为本轮官方页面显示当前推荐已经有 PowerShell install script；旧 npm 路径只能作为历史或 fallback，最终以官方页面为准。

### E8. 中文用户卡点：大家需要的是清楚步骤，不是术语

来源：

- B 站搜索：`Codex Qoder CodeBuddy MiMo 安装 配置 Windows 小白 教程`
- 知乎搜索：`Codex Qoder CodeBuddy MiMo Windows 安装 配置 小白 教程`
- 微信公众号搜索：`Codex Qoder CodeBuddy MiMo 安装 配置 Windows 小白 教程`
- 小红书搜索：`Codex Qoder CodeBuddy MiMo 安装 配置 Windows 小白 教程`

观察结果：

- B 站结果里有“Qoder 保姆级教程”“CodeBuddy 配置教程”“Codex 配置教程”。
- 知乎结果里出现“折腾 2 小时安装 Codex”“手把手支付、安装 Codex”“mimo code 安装教程”等内容。
- 微信公众号文章常见写法是：先装 Node.js，再检查版本，再打开终端，再执行安装命令，再登录或配置账号。
- 小红书结果大量用“小白友好”“保姆级”“1 分钟速通”“两步就能用上”这类表达。

结论：

- 中文用户不是完全不愿意跟步骤，而是不想在第一步就被 PowerShell、Node、PATH、MCP、Skill、provider、Token Plan 这些词淹没。
- 对我们来说，最重要的是把步骤变成“导航”，让用户每一步知道自己在做什么、做完看到什么、失败时该点哪里。
- 社区内容只能证明“用户卡点存在”，不能替代官方安装事实。

### E9. CLI 可用性证据：命令行不是天然友好

来源：

- `Accessibility of Command Line Interfaces`，CHI 2021，DOI：`10.1145/3411764.3445544`
- KnowledgeRadar 学术搜索结果显示该论文为开放访问，摘要指出 CLI 是非结构化文本界面，会带来可访问性问题。

结论：

- CLI 对开发者很强，但对普通用户不是天然友好的产品入口。
- “复制一条命令”对熟练开发者很方便，对普通 Windows 用户可能意味着执行策略、管理员权限、PATH、Node、网络代理、终端选择等一串未知问题。

对我们的影响：

- README 可以保留命令，但命令不应该是唯一主入口。
- 普通用户主路径应该是双击安装向导。
- 安装向导里的文字要告诉用户“你不用知道文件最终放在哪里，向导会放好”。

## 当前项目已经做到什么程度

从本地仓库看，项目已经具备这些基础：

1. 中文主 README 已存在，并有英文切换。
2. `docs/user/installation.zh.md` 已有 Windows 安装说明。
3. `docs/user/troubleshooting.zh.md` 已区分插件不可见、MCP 工具不可见、`Transport closed`、provider 缺失等问题。
4. `docs/user/privacy.zh.md` 已说明不读取 token、cookie、账号数据库和本机私有配置。
5. `docs/provider-notes/qoder.md`、`docs/provider-notes/codebuddy.md`、`docs/provider-notes/mimo.md` 已存在。
6. `scripts/install/install-user.ps1` 已有用户安装脚本。
7. `scripts/verify/doctor-codex-praetor.ps1` 已有 provider 检测和状态提示基础。
8. `scripts/release/build-codex-praetor-release.ps1` 已有发布包构建和部分私有痕迹排除逻辑。
9. `plugin/` 已有插件包形态。
10. `mcp/` 已有 MCP 源码和 self-test。
11. `docs/release/release-gate-checklist.md`、`docs/architecture/fresh-context-native-mcp-canary.md`、`docs/user/user-acceptance-checklist.zh.md` 已覆盖发布和验收思路。

这说明项目不是从零开始。下一阶段不是先开发更多派工能力，而是把“一个陌生用户如何顺利装好并知道下一步”补齐。

## 真实普通用户完整链路

下面用小白视角重写从打开 GitHub 到真正使用的完整路径。

### 第 1 步：打开仓库首页

用户看到的第一屏应该先告诉他：

1. 这是给 Codex 用的外部 agent 派工插件。
2. Windows 用户点这里下载。
3. 不用先安装三家 provider，也能先验证本体。
4. 真实派工至少需要 Qoder、CodeBuddy、MiMo 其中一个可用。
5. 英文说明在旁边可切换。

用户不应该第一眼看到大段架构、MCP、Skill、目录结构。

### 第 2 步：下载正确的安装包

README 的按钮或链接应该指向 Release 中的普通用户包，例如：

```text
CodexPraetor-Setup.zip
```

或：

```text
codex-praetor-setup-0.1.0-alpha.zip
```

Release 页面要明确：

- 普通用户下载 `Setup.zip`。
- `Source code` 是 GitHub 自动生成的源码包，不是安装入口。
- 开发者才需要 clone 仓库。

### 第 3 步：解压到哪里

用户最自然的问题是：解压到哪里？

推荐文案：

```text
可以先解压到桌面、下载目录或任意临时文件夹。安装向导会把 Codex Praetor 放到 Codex 能识别的位置，解压目录不是长期安装目录。
```

不要让用户手动解压到 `%USERPROFILE%\.codex`。这个路径应该由安装向导处理。

### 第 4 步：双击安装入口

解压后的根目录应该有一个显眼入口，例如：

```text
setup.cmd
```

或者后续做成：

```text
codex-praetor-setup.exe
```

第一版不必立刻做完整图形界面。更合理的顺序是：

1. 先做 `setup.cmd` 启动器，文件名保持 ASCII，降低执行策略门槛。
2. 复用现有 `scripts/install/install-user.ps1`。
3. 启动器打开后显示中文标题和中文向导。
4. 等流程稳定后再考虑小型 GUI。

### 第 5 步：安装向导先讲人话

启动后先显示：

```text
这个向导会安装 Codex Praetor 本体，并检查 Qoder、CodeBuddy、MiMo 是否可用。
它不会读取你的账号、token、cookie，也不会替你登录任何 provider。
如果你还没安装 provider，也可以先完成本体安装并在 Codex 里做 dry-run。
```

用户确认后再继续。

### 第 6 步：检查基础环境

向导检查：

1. Windows 版本和架构。
2. PowerShell 是否可运行。
3. 当前脚本是否被组策略阻止。
4. Codex Desktop 或 Codex CLI 是否存在，若无法检测则给手动确认入口。
5. Node/npm 是否存在。
6. WinGet 是否存在。
7. 当前网络是否能访问 GitHub 和 provider 官方安装地址。
8. PATH 中是否已有 `qodercli`、`codebuddy`、`mimo`。

检查只做“状态展示”，不要一开始就跑重型 doctor。

### 第 7 步：安装 Codex Praetor 本体

向导把 release 包中的内容复制到 Codex 能识别的位置，重点包括：

1. 插件包。
2. skill。
3. MCP server。
4. 个人 marketplace 入口或 Codex 可发现的插件入口。

它不能做：

1. 不软链接到 D 盘源码。
2. 不自动同步开发目录。
3. 不写入本机开发路径。
4. 不保留旧版本同时活跃造成冲突。

对用户来说，只显示：

```text
Codex Praetor 本体已安装。
```

内部路径只在“详情”里显示，避免吓到小白。

### 第 8 步：选择是否安装 provider

安装本体后，向导询问：

```text
你想现在配置真实派工能力吗？

1. 先不配置，只验证 Codex Praetor 本体。
2. 配置 Qoder。
3. 配置 CodeBuddy。
4. 配置 MiMo。
```

默认推荐第 1 项。这样用户不会被三家 provider 的安装和登录卡住本体安装。

### 第 9 步：按官方方式引导 provider

如果用户选择 provider，向导应该这样做：

1. 先检测是否已安装。
2. 已安装则显示版本。
3. 未安装则展示官方安装方式。
4. 询问用户是否现在打开或执行官方安装。
5. 安装后重新检测版本。
6. 到登录或授权步骤时停下来，让用户自己完成。

向导不应该：

1. 替用户输入密码。
2. 替用户粘贴 token。
3. 读取 provider 数据库判断登录状态。
4. 自动购买套餐或确认账单。
5. 自动切换企业域或国内/国际站点。

### 第 10 步：显示状态总览

安装结束后给一张人话总览：

| 项目 | 状态 | 说明 |
| --- | --- | --- |
| Codex Praetor 本体 | 已安装 | 可以在 Codex 新任务中 dry-run |
| Codex 插件 | 已写入 | 重启 Codex 或打开新任务后刷新 |
| MCP server | 已安装 | 新任务中应能看到工具 |
| Qoder | 未安装/已安装/登录未知 | 真实派工前需可用 |
| CodeBuddy | 未安装/已安装/登录未知 | 真实派工前需可用 |
| MiMo | 未安装/已安装/Auto 未验证/Auto 可尝试/需连接 provider | 优先尝试 `mimo/mimo-auto`，失败再走 `/connect` 或 API key |
| Node.js | 已安装/未安装 | 影响 npm 类 provider |

底部写：

```text
下一步：重启 Codex 或打开一个新任务，然后输入下面这句话测试。
```

### 第 11 步：回 Codex 验证

给用户一条固定 dry-run 提示词：

```text
拆分一下任务，分配给其他 agent 做 dry-run，不要真实修改文件。
```

成功标志：

1. Codex 能识别这是 Codex Praetor 外部 worker 路线。
2. 不创建 Codex 原生 subagent。
3. 能给出派工计划或 dry-run 结果。
4. 没有 provider 时说明“本体可用，真实派工需要配置 provider”。

### 第 12 步：真实派工前的只读验收

真实派工前，用户只需要至少一个 provider 可用。验收顺序：

1. 检测命令版本。
2. 检查登录或授权提示。
3. 运行 readonly canary。
4. 只读成功后再允许真实派工。

不要求用户三家都装。

## 安装向导每一步到底做什么

### 检查层

向导要做检查，但不能像开发者 doctor 一样一上来跑一大串，让用户觉得“还没安装就已经出错”。建议分成两层：

第一层是必须检查，只有这些会影响本体安装：

- Windows 版本和 CPU 架构。
- PowerShell 可用性。
- 当前脚本是否能在本进程临时运行。
- Codex 用户目录和插件目录是否能写入。
- 旧版同名安装是否存在，以及能否无损替换。

第二层是可选能力检查，只影响 provider 引导或后续真实派工：

- WinGet 是否可用。
- Node/npm 是否可用。
- GitHub 和 provider 官方地址是否可访问。
- PATH 中 provider 命令是否可见。

检查结果要用人话显示：

```text
Node.js 没找到。这不影响安装 Codex Praetor 本体，但会影响使用 npm 安装 CodeBuddy 或某些 provider。
```

### 本体安装层

向导做这些事：

- 从 release 包复制插件、skill、MCP。
- 写入 Codex 可发现的插件入口。
- 清理旧的同名活跃入口，避免新旧同时存在。
- 保留必要备份和回滚点。
- 不保留 D 盘开发路径。
- 不创建软链接、硬链接、junction 或快捷方式伪装安装。

### Provider 选择层

向导允许用户选择：

```text
1. 配置全部 provider
2. 先不配置 provider，只验证 Codex Praetor 本体
3. 只配置 Qoder
4. 只配置 CodeBuddy
5. 只配置 MiMo
```

界面第一项可以是“配置全部”，因为很多用户会自然想一次配齐；但推荐提示应该说清楚：“如果你只是想先确认安装成功，选 2 最稳。”这样既不把“只验证本体”藏起来，也不默认让三家 provider 的登录和授权拖慢本体安装。

### Provider 安装层

向导只使用官方方式：

- Qoder：官方 Windows PowerShell 或 CMD 安装。
- CodeBuddy：官方 npm 路径或 Native Binary Beta 官方脚本。
- MiMo：官方 PowerShell install script；默认验收走 `mimo/mimo-auto` 免费匿名通道。
- Node：官方 Node.js 安装页、Microsoft 指南或 WinGet 候选路径。

不使用来路不明的第三方包，不把 provider 复制进 Codex Praetor。

### 登录授权层

向导只做引导：

- 提示用户运行 `/login`、`/connect`、MiMo Auto 初始化或 provider 官方登录流程。
- 打开官方页面。
- 进入等待页，提示“请在官方窗口里完成登录或授权”。
- 提供“我已完成，继续检测”和“跳过这个 provider”两个动作。
- 用户继续后，先做命令检测，再做安全的只读 canary。
- 检测失败时给下一步，例如“重新打开官方登录”“换成手动填 CLI 路径”“先跳过这个 provider”，不要直接结束。

这个设计和 OAuth device flow 的思路一致：程序负责展示授权入口和等待状态，用户在浏览器或官方 TUI 完成账号动作，程序轮询或在用户点击继续后复检。区别是 Codex Praetor 不自己实现 provider 的 OAuth，只尊重各 provider 官方 CLI 暴露的登录流程。

不做：

- 不读取 token。
- 不读取 cookie。
- 不读取 provider 账号数据库。
- 不保存 API key。
- 不替用户完成账单或套餐动作。

### 配置层

向导可生成本地 ignored 配置，例如：

- provider CLI 路径。
- 用户选择的默认 provider。
- 是否跳过某个 provider。

配置必须留在用户本机，不进 Git，不进 release，不上传 GitHub。

### 验证层

验证分三层：

1. 本体验证：插件、skill、MCP 是否可被 Codex 新任务识别。
2. dry-run 验证：自然语言能否走 Codex Praetor 路由，不创建 Codex 原生 subagent。
3. provider 验证：至少一个 provider 的 readonly canary 通过。

### 汇总层

结束时告诉用户：

- 已经完成什么。
- 还差什么。
- 下一步该打开 Codex 做什么。
- 如果失败，去哪个排错页面。

## 三家 provider 决策表

| Provider | 最轻安装方式 | 依赖 | 授权方式 | 向导能做什么 | 用户必须自己做什么 | 失败兜底 |
| --- | --- | --- | --- | --- | --- | --- |
| Qoder | 官方 PowerShell：`irm https://qoder.com/install.ps1 | iex`；CMD 也可 | Windows Terminal；Windows on Arm 暂不支持 | TUI `/login`，浏览器登录，或 PAT/环境变量 | 检测 `qodercli --version`，打开官方登录说明，引导用户登录 | 登录账号、选择浏览器登录或 PAT、确认授权 | 提示 Windows on Arm 边界，回到官方安装页，允许手动填 CLI 路径 |
| CodeBuddy | npm：`npm install -g @tencent-ai/codebuddy-code`；Native Binary Beta 官方脚本 | npm 路径需要 Node.js 18.20+；Native Binary Beta 不需要 Node | 官方登录流程，可能涉及国内/国际站点、企业域或账号权益 | 检测 `codebuddy --version`，检测 Node/npm，引导官方安装 | 登录账号、选择站点/企业域、确认账号权益 | 提示 PATH、旧版本、网络、npm 镜像；允许手动填 CLI 路径 |
| MiMo | 官方 PowerShell：`powershell -ep Bypass -c "irm https://mimo.xiaomi.com/install.ps1 | iex"`；npm 可作为 fallback | 现代终端；MiMo Auto 免费匿名通道不需要 API key；自配 provider 需要 API key | 优先 `mimo/mimo-auto`；失败或要指定模型时再用 `/connect`、MiMo Platform、Token Plan、API key | 检测 MiMo 命令，默认跑 MiMo Auto 只读 canary，失败后打开模型 provider 页面 | 如果选择 MiMo Platform 或其它 provider，需要用户自己登录、配置账单或 Token Plan、复制 API key | 提示 MiMo Auto 限时免费且可能变更；失败不等于 Codex Praetor 本体失败 |

## 哪些事情不能自动化

这些动作不能也不应该由 Codex Praetor 自动完成：

1. 登录 Qoder、CodeBuddy 账号；MiMo Auto 优先不要求账号，只有切到 MiMo Platform 或其它 provider 时才需要用户登录或配置。
2. 输入密码、扫码、浏览器授权确认。
3. 选择企业域、国内站、国际站。
4. 申请 Token Plan、充值、购买套餐、确认账单。
5. 复制或保存 PAT/API key。
6. 读取 provider 账号数据库、cookie、auth 文件。
7. 绕过企业组策略、杀毒拦截、系统执行策略。
8. 在旧 Codex 任务里 100% 热加载新工具。
9. 静默安装 Node、provider 或其它第三方软件。

正确说法应该是：

```text
安装向导可以把你带到正确位置，但账号授权必须由你本人完成。
```

## 低成本额度策略应该怎么讲

Codex Praetor 的真实产品目的不是把外部 agent 神秘化，而是把各家官方公开可用的免费、试用、低价时段或固定低成本模型，用在边界清楚的小任务上。用户口语里可以说“薅羊毛”，但公开 README 和 Release 建议写成：

```text
Codex Praetor 会优先使用你已合法获得的免费额度、试用额度、低价时段或低成本模型，把适合外包的小任务交给本机外部 CLI agent。它不会绕过 provider 的规则，也不会替你注册、登录、充值或保存密钥。
```

三家 provider 的低成本口径应该这样写：

| Provider | 推荐低成本入口 | 为什么这么配 | 用户要注意什么 |
| --- | --- | --- | --- |
| MiMo | `mimo/mimo-auto` | 官方 README 写明 MiMo Auto 是限时免费、匿名、零配置；本仓库默认允许的 MiMo tier 也是 `mimo/mimo-auto` | 免费通道可能按官方策略变化；失败时再走 `/connect` 或 API key 路线 |
| CodeBuddy | `hy3` | 本项目历史验证和策略文档已把 `hy3` 定为默认固定低成本路线；`auto` 和预览/强模型不作为默认 | 用户仍需完成 CodeBuddy 官方登录；账号权益和模型可用性以自己账号为准 |
| Qoder | 夜间便宜 tier | 本项目配置里把 Qoder 分成白天/夜间、便宜/强模型；夜间便宜模型适合普通 worker 任务 | 用户需要登录 Qoder，并按 Qoder 当前账号权益和积分/额度规则使用；如有每日领取积分或权益，应在 provider 官方页面完成 |

产品页不要承诺“永久免费”“一定免费”或“自动帮你领取积分”。更好的写法是：Codex Praetor 负责把任务送到合适的低成本路线；账号、积分、额度、活动领取和账单确认由用户在 provider 官方页面完成。

## GitHub 仓库应该怎么改

### README 第一屏

当前 README 已经比早期好很多，但还可以更像产品首页。第一屏建议变成：

```text
# Codex Praetor

让 Codex 把一部分明确边界的工作交给本机外部 CLI agent。

适合你，如果：
- 你在 Windows 上使用 Codex。
- 你希望 Codex 规划和验收，外部 worker 执行一部分任务。
- 你愿意至少配置 Qoder、CodeBuddy、MiMo 中的一种作为真实派工 provider。

三步开始：
1. 下载 CodexPraetor-Setup.zip
2. 解压后双击“安装 Codex 执政官”
3. 重启 Codex 或打开新任务，输入 dry-run 测试句

还没有 provider？没关系，可以先验证本体。

English documentation: README.en.md
```

架构、MCP、目录结构、开发者命令放到后面。

### Release 页面

Release notes 应中文为主：

```text
这是 Codex Praetor 的首个 alpha 安装包，面向 Windows + Codex 用户。

普通用户下载：
- CodexPraetor-Setup.zip

不要下载：
- Source code(zip)
- Source code(tar.gz)

安装：
1. 解压到桌面或下载目录。
2. 双击“安装 Codex 执政官”。
3. 按向导提示完成安装。
4. 重启 Codex 或打开新任务做 dry-run。

重要边界：
- 不包含 Qoder、CodeBuddy、MiMo。
- 不替你登录 provider。
- 没有 provider 也能先验证本体，真实派工需要至少一个 provider。
```

英文说明可以放在同一页面下方：

```text
English notes: see README.en.md
```

GitHub Release 本身不提供“语言切换按钮”这种产品 UI，所以最稳妥的是中文为主，英文用链接或下方段落承接。

### 资产命名

推荐：

- `CodexPraetor-Setup.zip`：普通用户入口。
- `codex-praetor-setup-0.1.0-alpha.zip`：带版本的正式资产名。
- `SHA256SUMS.txt`：高级用户校验。
- GitHub 自动生成的 source code 保留，但在 release notes 明确“不是安装包”。

不要只放：

- `codex-praetor-0.1.0-alpha.zip`

这个名字对开发者清楚，对小白不够清楚。

### docs 首页

`docs/README.md` 应像帮助中心：

1. 第一次安装。
2. 安装后怎么验证。
3. 没有 provider 怎么办。
4. 配置 Qoder。
5. 配置 CodeBuddy。
6. 配置 MiMo。
7. 看不到插件。
8. 看不到 MCP 工具。
9. provider 登录失败。
10. 卸载和清理。
11. 反馈问题。

### Provider 页面

每个 provider 页面都按同一模板写：

```text
这个 provider 是什么
什么时候需要它
官方安装方式
安装后如何验证
登录或授权怎么做
Codex Praetor 只会读取什么
哪些问题不属于 Codex Praetor
常见失败和下一步
```

不要把 provider 页面写成纯命令集合。

### 排错页面

排错页面按现象写，不按内部模块写：

- 我安装完看不到 Codex Praetor。
- 我看到了插件，但没有 MCP 工具。
- 我说“拆分任务”，Codex 还是创建了原生 subagent。
- 我没有 Qoder/CodeBuddy/MiMo。
- provider 命令找不到。
- provider 要我登录。
- provider 说余额或 Token Plan 不够。
- `Transport closed`。
- 我想卸载。

每个现象都回答三件事：

1. 这通常是什么意思。
2. 你现在该做什么。
3. 什么时候需要提交 issue。

### 公开文档和发布包清理

公开包里不应该出现：

- 本机开发源绝对路径
- `C:\Users\<你的用户名>`
- 本机 C 盘 skill 安装细节作为普通用户主路径
- D 盘开发源同步机制
- 交接包
- 截图临时路径
- provider 账号页面
- token、cookie、auth 文件
- `.local.json`
- runtime 数据库、任务日志、缓存
- 只服务开发阶段的 handoff、internal evidence、临时验收提示词

公开文档如果必须提 Windows 用户目录，只写：

```text
%USERPROFILE%
```

开发者文档可以保留内部实现说明，但普通用户主文档不要出现 C/D 盘同步、个人安装版 skill、本机缓存等开发阶段问题。

## 本地仓库下一阶段要改哪些文件

本报告不直接改这些文件，但下一阶段建议按这个顺序改：

1. `docs/codex-praetor-windows-setup-ux-followup-2026-07-11.zh.md`
   作为后续公开友好文件名的报告承接稿；中文文件名旧稿可以继续作为本轮考古记录，但最终公开文档建议全部使用 ASCII 文件名。

2. `README.md`  
   改第一屏，中文主链路更清楚。

3. `docs/user/installation.zh.md`
   从 PowerShell 脚本说明升级成“普通用户安装指南”，把命令放到高级路径。

4. `docs/provider-notes/README.md`  
   改成 provider 选择页，告诉用户只装一个也可以。

5. `docs/provider-notes/qoder.md`  
   补 Windows on Arm 边界、`/login`、PAT 不适合作为小白主路径。

6. `docs/provider-notes/codebuddy.md`  
   补 Node.js 18.20+、Native Binary Beta、PATH、旧版本、配置目录。

7. `docs/provider-notes/mimo.md`  
   修正当前官方 Windows 安装脚本、`mimo/mimo-auto` 免费匿名通道、`/connect`、Token Plan、API key、账单边界。

8. `docs/user/troubleshooting.zh.md`
   按“用户看到的现象”重排。

9. `docs/release/release-notes-0.1.0-alpha.md`
   改成中文 Release 主说明，明确下载资产。

10. `scripts/release/build-codex-praetor-release.ps1`
    后续实现时加强公开痕迹扫描，但本轮不修改。

11. 新增安装入口  
    后续新增 `setup.cmd` 和 `setup.ps1`。文件名用 ASCII，窗口标题和正文用中文。第一版调用现有 `scripts/install/install-user.ps1`，不复制主安装逻辑。

12. 后续可新增安装向导设计文档  
    例如 `docs/setup-wizard-design.zh.md`，把本报告中向导细节拆成实现规格。

## 产品路线图

### P0：报告确认

目标：确认方向，不动代码。

交付物：

- 本报告。

验收：

- 只做调研和报告。
- 不执行安装。
- 不改本机 Codex。
- 不操作 GitHub。

### P1：公开仓库文案收口

目标：让用户打开 GitHub 后 30 秒内知道该做什么。

任务：

1. README 第一屏改成中文产品入口。
2. Release notes 改成中文为主。
3. 明确普通用户下载哪个资产。
4. 英文保留为切换入口。
5. 把架构和开发者说明后移。

验收：

- 不懂 MCP 的用户也能知道先下载哪个文件。
- 用户知道 source code 不是安装包。
- 中文主界面完整，英文不抢主流程。

### P2：Release 包双击入口

目标：用户下载 zip 后能点一个稳定入口，打开后看到中文向导。

任务：

1. 新增 `setup.cmd`。
2. 新增 `setup.ps1`。
3. 文件名、release 资产名、根目录入口全部使用 ASCII。
4. 窗口标题、菜单、说明文字全部中文优先。
5. 入口调用现有安装脚本，不复制主逻辑。
6. 启动时中文说明会做什么和不会做什么。
7. 安装完成后显示下一步 Codex dry-run 提示词。

验收：

- zip 解压到桌面或下载目录都能运行。
- 不要求用户手动放到 `.codex`。
- 不要求管理员权限，除非系统策略阻止。
- 安装器不暴露 D 盘开发路径。
- 根目录没有中文命名的可执行入口作为主路径。

### P3：安装状态总览

目标：安装完成后用户知道“现在能做什么”。

任务：

1. 显示 Codex Praetor 本体状态。
2. 显示插件和 MCP 写入状态。
3. 显示 Node/npm 状态。
4. 显示 provider 检测状态。
5. 显示下一步提示词。

验收：

- 没装 provider 不算安装失败。
- Node 缺失只影响相关 provider，不影响本体安装。
- 输出没有 token、cookie、账号路径。

### P4：Provider 引导

目标：用户只装一个 provider 也能进入真实派工。

任务：

1. Qoder 页面按官方文档更新。
2. CodeBuddy 页面按官方文档更新。
3. MiMo 页面按官方文档更新。
4. 向导里加入五项 provider 菜单：配置全部、先不配置、只配置 Qoder、只配置 CodeBuddy、只配置 MiMo。
5. provider 状态统一为：未安装、已安装、登录未知、可尝试、失败。
6. 每个 provider 都有“等待用户完成官方授权”的中间页，并提供继续检测和跳过。

验收：

- 三家都没装时，本体仍能 dry-run。
- 装一家并登录后，可跑 readonly canary。
- provider 账号问题不会被误报为 Codex Praetor 本体失败。
- 用户不需要在安装器和文档之间来回猜下一步。

### P5：轻量失败恢复

目标：正常使用不吵，失败时快速知道哪里坏了。

任务：

1. 正常调用不跑 doctor。
2. `Transport closed` 时先给 reload/probe。
3. 插件不可见时提示重启 Codex 或打开新任务。
4. provider 不可用时给 provider 专属下一步。
5. doctor 只用于发布前、验收、提交 issue 前或用户主动要求。

验收：

- 失败信息能区分插件、MCP、provider、登录、路径、Codex 工具上下文。
- 不让用户每次使用前都检查一大堆。

### P6：公开痕迹和隐私清理

目标：发布包不给别人看到本机开发痕迹。

任务：

1. 加强 release 包扫描。
2. 检查 C/D 盘路径。
3. 检查用户名。
4. 检查 token、cookie、auth、数据库、缓存。
5. 检查 handoff/internal/development 是否误入普通用户包。
6. 检查 README、docs、Release notes 是否出现开发同步问题。

验收：

- 普通用户包只包含安装和使用所需内容。
- 源码仓库可以保留开发文档，但明确“普通用户不用看”。
- 发布包不包含个人数据。

### P7：干净 Windows 全链路验收

目标：用陌生用户视角完整跑通。

验收链路：

1. 打开 GitHub 仓库。
2. 找到中文下载入口。
3. 进入 Release。
4. 下载 `Setup.zip`。
5. 解压到普通目录。
6. 双击安装入口。
7. 完成本体安装。
8. 不安装 provider 时做 dry-run。
9. 安装一个 provider。
10. 完成 provider 官方登录或授权。
11. 运行 readonly canary。
12. 在 Codex 中确认自然语言派工走 Codex Praetor，而不是 Codex 原生 subagent。
13. 检查失败路径。
14. 检查卸载路径。

这一步适合新开一个干净 Codex 任务做最终验收。不要每个小修改都新开任务。

## 推荐的最终用户话术

### 首页一句话

```text
Codex Praetor 是一个给 Codex 用的 Windows 插件：Codex 负责规划和验收，Qoder、CodeBuddy、MiMo 等本机外部 agent 负责执行边界清楚的小任务。
```

### 安装包说明

```text
普通用户下载 Setup.zip，解压后双击“安装 Codex 执政官”。你可以先不安装任何 provider，先在 Codex 里验证本体是否工作。
```

### Provider 说明

```text
真实派工至少需要一个 provider。Qoder、CodeBuddy、MiMo 都是第三方/外部 CLI 工具，需要按各自官方流程安装和配置。Qoder、CodeBuddy 通常需要官方登录；MiMo 优先使用 `mimo/mimo-auto` 免费匿名通道，失败或要指定其它模型时再走 `/connect`、Token Plan 或 API key。Codex Praetor 只负责发现和调用它们，不保存你的账号和密钥。
```

### 安装成功说明

```text
安装完成后，请重启 Codex 或打开一个新任务，输入：“拆分一下任务，分配给其他 agent 做 dry-run，不要真实修改文件。”
```

### 没装 provider 时的说明

```text
Codex Praetor 本体已经可用，但还不能真实派工。你可以先 dry-run；等你安装并配置 Qoder、CodeBuddy 或 MiMo 中的任意一个，再运行只读验收。MiMo 可以先尝试 `mimo/mimo-auto`，不必一开始就配置 API key。
```

## 不建议做的事

1. 不建议把 Qoder、CodeBuddy、MiMo 打进 Codex Praetor 安装包。
2. 不建议默认静默安装 Node.js。
3. 不建议让小白主路径从 PowerShell 命令开始。
4. 不建议用户手动复制到 `.codex` 或 `.agents`。
5. 不建议安装时要求用户粘贴 token。
6. 不建议读取 provider 账号数据库判断登录。
7. 不建议每次调用 Codex Praetor 前运行 doctor。
8. 不建议把 C 盘 skill 和 D 盘开发源同步问题写进普通用户文档。
9. 不建议为了显得自动化做常驻监控。
10. 不建议把社区教程内容当成官方事实。

## 最终目标

Codex Praetor 的目标不是做一个复杂的多 agent 平台，而是做一个 Windows-first、中文友好、服务 Codex 的轻量插件产品：

- 用户从 GitHub 或 Codex 插件入口能装好。
- 用户不需要理解 MCP、Skill、插件目录和源码目录。
- 用户可以不装 provider 先验证本体。
- 用户只装一个 provider 也能真实使用。
- Codex 保持规划、监督和验收。
- 外部 CLI worker 只执行边界清楚的任务。
- 失败时能快速知道是插件、MCP、provider、登录、路径、网络还是 Codex 工具上下文问题。
- 发布包不包含个人数据、本机路径、账号信息和开发交接材料。

下一步不是继续加派工功能，而是按 P1 到 P4 先把公开仓库、Release、安装入口和 provider 引导做到一个陌生 Windows 用户能顺利走完。随后再做 P5 到 P7，把失败恢复、隐私清理和干净环境验收补齐。

## 本轮证据登记

| 编号 | 来源 | 工具路径 | 证据强度 | 用途 |
| --- | --- | --- | --- | --- |
| E1 | OpenAI Codex 插件/MCP/Skill 文档 | 官方开放网页 | 强 | 确认插件和 MCP 是长期分发方向 |
| E2 | GitHub README/Release 文档 | 官方开放网页 | 强 | 确认 README 和 Release 的用户职责 |
| E3 | Microsoft Bootstrapping、WinGet、PowerShell 文档 | `kr_web_search` | 强 | 支撑轻量 bootstrapper 方案 |
| E4 | Node.js、npm、Microsoft Node on Windows 文档 | `kr_web_search` | 强 | 支撑 Node/npm 不能默认假设 |
| E5 | Qoder CLI Quick Start | `extract_web_page` | 强 | 确认 Qoder Windows 安装、版本验证和登录边界 |
| E6 | CodeBuddy Installation | `extract_web_page` | 强 | 确认 CodeBuddy npm、Native Binary Beta、PATH、配置目录 |
| E7 | MiMo Install、Models Provider、官方 GitHub README、GitHub issue #306、本地 CLI help | `extract_web_page`、`search_github_repositories`、本地命令 | 强 | 确认 MiMo Windows 安装脚本、`mimo/mimo-auto` 限时免费匿名通道、`/connect`、Token Plan/API key 边界 |
| E8 | B站、知乎、公众号、小红书搜索 | KR 平台搜索工具 | 弱到中 | 说明中文用户更需要步骤化安装和小白文案 |
| E9 | CLI 可用性学术论文 | `search_academic` | 中到强 | 支撑命令行不是普通用户最佳入口 |
| E10 | 本地仓库文件 | `rg`、文件读取 | 强 | 确认当前项目已有骨架和待改文件 |
| E11 | RFC 8628 OAuth Device Authorization Grant | `extract_web_page` | 强 | 支撑“程序等待，用户在官方页面完成授权，再复检”的交接模式 |
