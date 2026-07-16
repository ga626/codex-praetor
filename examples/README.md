# 示例

## Dry-run

在 Codex Praetor 仓库根目录运行：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\examples\dry-run.ps1 -Repo "<你的仓库路径>"
```

等价 wrapper 调用：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\dispatch\invoke-codex-praetor.ps1 `
  -Provider mimo `
  -Tier mimo-isolated-audit `
  -Repo "<你的仓库路径>" `
  -Mode readonly `
  -Task "只读取 README.md 并总结项目，不要修改文件。" `
  -DryRun `
  -NoNotify
```

预期结果：wrapper 会打印选中的 provider、tier、model、artifact root 和将要执行的外部 worker 命令。dry-run 不会启动真实 worker。

## 只读 canary

`doctor` 通过、provider 已安装并登录、目标仓库至少有一个 commit 后，可以先预览只读 canary：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\examples\readonly-canary.ps1 -Repo "<你的仓库路径>"
```

确认命令无误后，再加 `-Apply` 真实调用 provider：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\examples\readonly-canary.ps1 -Repo "<你的仓库路径>" -Apply
```

这个入口会调用 `scripts\verify\test-provider-readonly-canary.ps1`。它只要求 worker 读取 `README.md`，返回 `CODEX_PRAETOR_CANARY_OK`，并检查主仓库 Git 状态保持不变。
