# Codex Praetor Windows 安装体验补充审查

日期：2026-07-11

## 开头必须说清楚的边界

Codex Praetor 的安装向导可以解决“用户不知道下载哪个包、点哪个入口、装到哪里、装完如何验证”的问题，但不能解决第三方 provider 的账号登录、浏览器授权、企业域选择、账单、Token Plan、API key 或套餐权益确认。

因此，公开文案和安装向导第一屏都应该明确：

```text
这个向导会安装 Codex Praetor 本体，并检查 Qoder、CodeBuddy、MiMo 是否可用。
它不会替你登录任何 provider，不会读取 token、cookie、账号数据库，也不会替你确认账单或套餐。
没有 provider 也可以先验证 Codex Praetor 本体；真实派工至少需要一个 provider 可用。Qoder、CodeBuddy 通常需要官方登录或授权；MiMo 可以先尝试官方 `mimo/mimo-auto` 免费匿名通道。
```

这不是产品缺口，而是安全边界。Codex Praetor 应该把用户带到正确流程，但不能越过 provider 自己的账号边界。MiMo 是特殊情况：优先尝试官方 `mimo/mimo-auto` 免费匿名通道；如果该通道不可用、过期或用户要指定其它模型，再引导用户走 `/connect`、Token Plan 或 API key。

## 本轮补查结论

### 1. CodeBuddy 首次使用确实需要登录

CodeBuddy 官方 Quick Start 明确写到：首次使用 CodeBuddy Code 时需要完成登录认证。启动后会出现登录方式选择：

```text
Select login method:
› Log in via Chinese Site
  Log in via International Site
  Log in via Enterprise Domain
  Log in via iOA (Tencent only)
```

官方说明还要求用户用方向键选择登录方式，回车确认后浏览器会自动打开完成认证。

对安装向导的影响：

- 向导可以检测 `codebuddy --version`。
- 向导可以启动或提示用户启动 `codebuddy`，让用户在官方 TUI 中选择中国站、国际站、企业域或 iOA。
- 向导不能替用户选择站点、输入账号、读取登录数据库或判断账号权益。
- 状态文案应是“CodeBuddy 已安装，登录状态需由官方 CLI 确认”，不要写成“已可真实派工”。

### 2. MiMo 要区分 Auto 免费通道和自配 provider

MiMo 官方安装页说明 Windows 推荐安装命令是：

```powershell
powershell -ep Bypass -c "irm https://mimo.xiaomi.com/install.ps1 | iex"
```

MiMo 官方 GitHub README 明确写到：MiMo Auto 是内置的限时免费通道，可以零配置开始使用；首次启动会自动引导配置，支持 MiMo Auto、Xiaomi MiMo Platform、从 Claude Code 导入认证、自定义 provider。

MiMo models/provider 页面说明的是另一条路线：

- 在 TUI 中运行 `/connect`。
- 选择 Xiaomi MiMo 或其它 provider。
- 如果使用 MiMo Platform，需要登录平台、添加账单信息、复制 API key，再粘贴回工具。
- MiMo Platform 使用 OpenAI-compatible endpoint，并通过 `api-key` header 或 `MIMO_API_KEY` 配置。

所以更准确的说法是：

- MiMo 的第一推荐路线是 `mimo/mimo-auto`。这是官方免费匿名通道，不应该被写成“必须登录”或“必须 API key”。
- MiMo Auto 是“限时免费”和官方策略型通道，不能承诺永久免费，也不能保证所有版本、地区、网络状态下一定可用。
- 如果 MiMo Auto 不可用，或者用户要使用 MiMo Platform/其它 provider，才需要 `/connect`、Token Plan、API key 或账单配置。
- 本仓库配置样例默认只允许 `mimo/mimo-auto`，并把它用于 `mimo-auto-readonly` 和 `mimo-auto-edit` 两个受控 tier。

对安装向导的影响：

- 向导可以检测 MiMo 命令是否存在。
- 向导应该先尝试 `mimo/mimo-auto` 的只读 canary。
- 如果 Auto 失败，再提示用户运行 `/connect` 并打开 MiMo provider 文档。
- 向导不能保存或读取 API key，也不能替用户确认账单。
- 状态文案应区分“MiMo CLI 已安装”“MiMo Auto 可尝试”“MiMo Auto 失败，需连接 provider/API key”。

### 3. 根目录入口不要用中文文件名

Windows 和 PowerShell 支持 Unicode 路径，但公开 release 包的根目录入口建议使用 ASCII 文件名。原因不是“中文一定不能运行”，而是发布包会经过浏览器下载、压缩/解压、终端编码、企业杀软、PowerShell/cmd、日志、issue 粘贴、CI、自动化脚本和远程协助等多条链路。ASCII 文件名在这些链路里更稳，也更便于用户和维护者复制命令。

推荐做法：

- 根目录入口使用 ASCII：`setup.cmd`、`setup.ps1`、`README.md`、`README.zh.md`。
- Release 资产使用 ASCII：`codex-praetor-setup-0.1.0-alpha.zip`。
- 安装窗口标题、菜单文案、向导正文使用中文：`Codex 执政官安装向导`。
- 不建议根目录放 `安装 Codex 执政官.cmd` 作为唯一入口。

如果想照顾小白用户，可以在 README 和 release notes 中写：

```text
解压后双击 setup.cmd。打开后会显示中文安装向导。
```

这样既保留中文体验，又避免把兼容性风险压到文件名上。

### 4. 安装向导应该分成“本体安装”和“provider 引导”

最稳的用户路径不是“一次运行后全部可用”，而是两段式：

1. 安装 Codex Praetor 本体。
2. 可选引导安装并授权一个 provider。

第一段必须尽量短：

- 检查 PowerShell、Node、Codex 插件目录、现有安装。
- 复制插件包到用户目录。
- 写入 marketplace 入口。
- 显示“重启 Codex 或打开新任务”的 dry-run 验证语句。

第二段是可选项：

- Qoder：打开官方安装/登录说明，检测 `qodercli --version`，提示 `/login`。
- CodeBuddy：检测 Node/npm 或 Native Binary，检测 `codebuddy --version`，提示首次启动后选择登录站点。
- MiMo：检测 MiMo 命令，优先尝试 `mimo/mimo-auto`；失败后再提示 `/connect` 和 provider/API key 配置。

Provider 菜单建议固定为五项：

```text
1. 配置全部 provider
2. 先不配置 provider，只验证 Codex Praetor 本体
3. 只配置 Qoder
4. 只配置 CodeBuddy
5. 只配置 MiMo
```

界面第一项可以给“配置全部”，因为它符合用户“一次弄好”的直觉；但推荐提示应该告诉新用户：“如果你只是想确认安装成功，先选 2 最稳。”这样不会因为第三方账号流程卡住本体安装。

每个 provider 进入授权步骤时，都应该出现一个中间页：

```text
请在官方窗口里完成登录或授权。

[我已完成，继续检测]
[跳过这个 provider]
```

用户点继续后，向导再检测命令是否可用，并做安全的只读 canary。检测失败时给下一步，而不是直接结束。

## 建议的 release 包根目录

```text
codex-praetor-setup-0.1.0-alpha/
  setup.cmd
  setup.ps1
  README.md
  README.en.md
  LICENSE
  scripts/
  plugin/
  skill/
  mcp/
  docs/
```

`setup.cmd` 只做很薄的一层：

```bat
@echo off
setlocal
title Codex Praetor Setup
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0setup.ps1"
pause
```

`setup.ps1` 再调用现有 `scripts/install/install-user.ps1`，并在前后显示中文说明、provider 状态和下一步 dry-run 语句。主安装逻辑仍留在现有脚本里，避免复制两套逻辑。

## README 和安装指南应该调整的措辞

当前文档里“安装前准备”把 Node.js 写成必须项。更准确的用户文案应是：

```text
Codex Praetor 本体安装需要 Windows、PowerShell 和 Codex。
MCP server 运行需要 Node.js；如果未检测到 Node.js，向导会提示你安装。
CodeBuddy 的 npm 安装路径需要 Node.js 18.20+。
没有 Qoder、CodeBuddy、MiMo 也可以先做 dry-run；真实派工至少需要一个 provider 完成官方安装和授权。
```

Provider 页面也应统一状态词：

- `未安装`：命令不存在。
- `已安装，授权未知`：版本检测通过，但不读取登录状态。
- `需要官方登录/连接 provider`：首次使用时需要用户完成 provider 流程。
- `MiMo Auto 可尝试`：MiMo 命令存在，可先跑免费匿名通道 canary。
- `MiMo Auto 失败，需连接 provider`：免费通道不可用，转 `/connect` 或 API key 路线。
- `可尝试只读验收`：命令存在，用户确认已登录或已配置 API key。

不要写：

- `已安装 = 可真实派工`。
- `MiMo 永久免费`。
- `MiMo 一定不需要登录`。
- `CodeBuddy 安装后直接可用`。
- `Codex Praetor 会帮你配置 provider`。

## 低成本额度和“羊毛”怎么写

用户口语里可以说“薅羊毛”，但公开产品页不要把这句话当主标语。更稳妥的产品表达是：

```text
Codex Praetor 会优先使用你已合法获得的免费额度、试用额度、低价时段或低成本模型，把适合外包的小任务交给本机外部 CLI agent。它不会绕过 provider 的规则，也不会替你注册、登录、充值或保存密钥。
```

三家 provider 应该这样解释：

- MiMo：优先 `mimo/mimo-auto`。官方 GitHub README 说明这是限时免费、匿名、零配置通道；失败后再走 `/connect`、Token Plan 或 API key。
- CodeBuddy：默认固定 `hy3`。本项目历史验证把 `hy3` 定成默认低成本路线，不用 `auto`，也不默认走预览或强模型。
- Qoder：按本项目的白天/夜间、便宜/强模型 tier 使用。夜间便宜 tier 适合普通 worker 任务；积分、额度、每日领取和账号权益以 Qoder 官方页面为准。

公开文档不要承诺“永久免费”“一定免费”“自动领取积分”。要说清楚：Codex Praetor 负责选择低成本路线和派工边界，provider 账号、活动、积分、额度、账单都由用户在官方流程里处理。

## 下一步建议

P1：新增 ASCII 入口设计，不把中文文件名作为根目录入口。

- 新增 `setup.cmd`。
- 新增 `setup.ps1`。
- `setup.ps1` 复用 `scripts/install/install-user.ps1`。
- release notes 写“解压后双击 setup.cmd，会出现中文向导”。
- 不新增 `安装 Codex 执政官.cmd` 作为主入口；中文体验放在窗口标题和正文里。

P2：修正文档中的 provider 授权边界。

- CodeBuddy 页面补首次登录方式选择。
- MiMo 页面改成当前官方 `install.ps1`、`mimo/mimo-auto` 免费匿名通道、`/connect`、Token Plan/API key。
- 安装指南把“provider 登录不是 Codex Praetor 能自动完成的事”放到开头。
- provider 选择菜单按五项固定：配置全部、先不配置、只配置 Qoder、只配置 CodeBuddy、只配置 MiMo。

P3：把 release 资产命名改成 setup 语义。

- 推荐 `codex-praetor-setup-0.1.0-alpha.zip`。
- 保留 `SHA256SUMS.txt` 或 `.sha256`。
- Release notes 明确 GitHub 自动生成的 Source code 不是普通用户安装包。

## 本轮引用来源

- CodeBuddy Quick Start: `https://www.codebuddy.ai/docs/cli/quickstart`
- CodeBuddy Installation: `https://www.codebuddy.ai/docs/cli/installation`
- MiMo Install: `https://mimo.xiaomi.com/mimocode/install`
- MiMo Models Provider: `https://mimo.xiaomi.com/mimocode/models-provider`
- MiMo GitHub: `https://github.com/XiaomiMiMo/MiMo-Code`
- MiMo issue #306: `https://github.com/XiaomiMiMo/MiMo-Code/issues/306`
- Qoder CLI Quick Start: `https://docs.qoder.com/en/cli/quick-start`
- Microsoft PowerShell execution policy: `https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.core/about/about_execution_policies`
- Microsoft WinGet docs: `https://learn.microsoft.com/en-us/windows/package-manager/winget/`
