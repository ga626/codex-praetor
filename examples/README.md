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
  -Tier mimo-auto-readonly `
  -Repo "<你的仓库路径>" `
  -Mode readonly `
  -Task "只读取 README.md 并总结项目，不要修改文件。" `
  -DryRun `
  -NoNotify
```

预期结果：wrapper 会打印选中的 provider、tier、model、artifact root 和将要执行的外部 worker 命令。dry-run 不会启动真实 worker。

## 只读 canary

`doctor` 通过、目标仓库至少有一个 commit 后，可以做一个很小的只读任务：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\examples\readonly-canary.ps1 -Repo "<你的仓库路径>"
```

等价 wrapper 调用：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\dispatch\invoke-codex-praetor.ps1 `
  -Provider mimo `
  -Tier mimo-auto-readonly `
  -Repo "<你的仓库路径>" `
  -Mode readonly `
  -RunMode blocking `
  -Task "只读取 README.md。最终回答必须以 CODEX_PRAETOR_CANARY_OK 开头。不要修改文件。" `
  -NoNotify
```

Codex 仍然必须在任务结束后检查 worker 输出和 git 状态。
