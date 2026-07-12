# Codex Praetor Scripts

这个目录是项目源码脚本区。为了让根目录不再堆满一长串脚本，脚本按角色分成五组：

- `dispatch/`：Codex Praetor 的派工入口和 job 管理脚本。这里的核心脚本会同步到 skill/plugin 包里。
- `install/`：用户安装和 Git hook 安装脚本。
- `verify/`：doctor、自测、MCP reload/probe 等验证脚本。
- `release/`：发布包构建、公开元数据更新和本机发布缓存脚本。
- `maintenance/`：一次性或低频维护脚本，例如运行目录迁移。

常用命令：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\verify\doctor-codex-praetor.ps1 -RequireHead -PublicRelease
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\verify\test-codex-praetor.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\dispatch\invoke-codex-praetor.ps1 -Provider mimo -Tier mimo-auto-readonly -Repo "<repo>" -Task "Dry run only." -Mode readonly -DryRun
```
