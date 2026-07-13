# Provider 说明

Codex Praetor 支持以下可选外部 CLI provider：

- [Qoder](qoder.md)
- [CodeBuddy](codebuddy.md)
- [MiMo](mimo.md)

这些 provider 不随 Codex Praetor 附带。安装向导会帮用户检查本机命令、打开官方安装/登录说明、等待用户完成授权、复检，并把已发现的 CLI 路径写入不会提交的本机配置。

它不会静默安装 provider，不会替用户登录，不会读取 token、cookie、账号数据库、余额页或个人截图。

没有配置 provider 时，Codex Praetor 仍然可以做意图识别、计划、dry-run、状态查询、lane/冲突可见性和 MCP 工具发现。真实派工需要至少一个 provider CLI 已安装、已登录或已处在 provider 允许的匿名路线，并通过只读 canary。

只读 canary 统一入口：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\verify\test-provider-readonly-canary.ps1 -Provider mimo
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\verify\test-provider-readonly-canary.ps1 -Provider mimo -Apply
```

第一条只预览命令；第二条才会真实调用 provider。把 `mimo` 换成 `qoder` 或 `codebuddy` 可以验证其它 provider。

返回安装入口：[README](../../README.md)。
