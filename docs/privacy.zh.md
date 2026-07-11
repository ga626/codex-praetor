# Codex Praetor 隐私与本地数据边界

Codex Praetor 是本机插件和脚本工具，不托管账号服务，不替用户登录 provider，也不读取 provider 的账号数据库。

## 它会读取什么

- Codex Praetor 自己的插件文件、MCP 配置和脚本。
- 你明确传给它的仓库路径和任务文本。
- 公开的 provider 配置模板。
- 你自己创建的本地配置，例如 `config\codex-praetor.local.json`。

## 它不会读取什么

- GitHub Personal Access Token。
- provider token、cookie、账号数据库、桌面端数据库。
- Qoder、CodeBuddy、MiMo 的账号页面和余额截图。
- 浏览器 cookie。
- 本机其他项目的私有文件，除非你明确把那个路径作为任务仓库传入。

## 它不会做什么

- 不自动安装 Qoder、CodeBuddy、MiMo。
- 不替用户登录 provider。
- 不把源码目录和本机安装目录做软链接或自动同步。
- 不默认创建 Codex 原生 subagent。
- 不默认把 worker 输出合并进主仓库。

## 发布包不会包含什么

- `handoff/`
- `docs/internal/`
- `node_modules/`
- `*.local.json`
- `.env*`
- token、auth、secret、cookie 文件
- provider 账号数据库
- 本地 runtime、jobs、worktrees、cache
- 个人截图或使用记录

## 提交 issue 时不要贴什么

- token、cookie、API key。
- provider 登录页、余额页、账号页截图。
- provider 本地数据库。
- 完整本机路径过多的长日志。
- 可能包含私有 prompt 或客户代码的 worker 输出全文。

只贴精简错误、命令、版本和复现步骤即可。
