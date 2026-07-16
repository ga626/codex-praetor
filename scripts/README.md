# Codex Praetor Scripts

这个目录是项目源码脚本区。为了让根目录不再堆满一长串脚本，脚本按角色分成五组：

- `dispatch/`：Codex Praetor 的派工入口和 job 管理脚本。这里的核心脚本会同步到 skill/plugin 包里。
- `install/`：用户安装和 Git hook 安装脚本。
- `verify/`：doctor、自测、公开入口一致性、发布包确定性、MCP reload/probe 等验证脚本。
- `release/`：发布包构建、公开元数据更新和本机发布缓存脚本。
- `maintenance/`：一次性或低频维护脚本，例如运行目录迁移和运行态清理。

常用命令：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\verify\doctor-codex-praetor.ps1 -RequireHead -PublicRelease
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\verify\test-codex-praetor.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\verify\test-public-entry-consistency.ps1 -SkipRemoteRelease
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\verify\test-release-package-determinism.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\maintenance\clean-codex-praetor-runtime.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\dispatch\invoke-codex-praetor.ps1 -Provider mimo -Tier mimo-isolated-audit -Repo "<repo>" -Task "Dry run only." -Mode readonly -DryRun
```

`test-codex-praetor.ps1` 默认是产品验证，不依赖当前电脑的全局 Codex 规则、已安装 skill 或 provider 登录态。需要检查本机 Codex 环境时，运行 `scripts\verify\test-codex-praetor-dev-env.ps1`。

`clean-codex-praetor-runtime.ps1` 默认只预览，不删除文件。确认输出只包含已合并、干净、过期或可归档的运行态内容后，再显式加 `-Apply`。
