# Codex Praetor Scripts

这个目录是项目源码脚本区。为了让根目录不再堆满一长串脚本，脚本按角色分成五组：

- `dispatch/`：Codex Praetor 的派工入口和 job 管理脚本。这里的核心脚本会同步到 skill/plugin 包里。
- `install/`：用户安装和 Git hook 安装脚本。
- `verify/`：doctor、自测、公开入口一致性、发布包确定性、Desktop runtime identity 与独立 host 诊断脚本。
- `release/`：发布包构建、公开元数据更新和本机发布缓存脚本。
- `maintenance/`：一次性或低频维护脚本，例如运行目录迁移和运行态清理。

常用命令：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\verify\invoke-release-candidate-preflight.ps1 -BaseRef origin/main -CheckRemote -AllowDraftMetadataPlaceholders
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\maintenance\clean-codex-praetor-runtime.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\dispatch\invoke-codex-praetor.ps1 -Provider codebuddy -Tier codebuddy-free -Repo "<repo>" -Task "Dry run only." -Mode readonly -DryRun
```

`invoke-release-candidate-preflight.ps1` 必须在已提交、干净的隔离候选 worktree 运行；它从最终 zip 验收并写入绑定 HEAD 与 artifact SHA 的回执。`test-codex-praetor.ps1` 仍是产品快速验证；本机 Codex 环境另用 `scripts\verify\test-codex-praetor-dev-env.ps1`。

`clean-codex-praetor-runtime.ps1` 默认只预览，不删除文件。确认输出只包含已合并、干净、过期或可归档的运行态内容后，再显式加 `-Apply`。
