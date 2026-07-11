# 贡献说明

Codex Praetor 在 alpha 阶段优先面向 Windows 和 Codex。

提交修改前请确认：

1. Codex 仍然是规划者、监督者和最终验收者，不要把外部 worker 派工改成默认创建 Codex 原生 subagent。
2. 源码目录和本机安装目录保持分离，不要加入软链接、目录联接或自动同步。
3. 不要提交 provider 凭据、账号文件、本地缓存、使用截图或个人日志。
4. 运行：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\doctor-codex-praetor.ps1 -RequireHead -PublicRelease
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\test-codex-praetor.ps1
```

涉及 provider 的真实派工测试必须先使用隔离 worktree，并从小型只读 canary 开始。
