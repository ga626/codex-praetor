# Examples

## Dry Run

From the Codex Praetor repository root:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\examples\dry-run.ps1 -Repo "D:\Projects\YourRepo"
```

Equivalent wrapper call:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\invoke-codex-praetor.ps1 `
  -Provider mimo `
  -Tier mimo-auto-readonly `
  -Repo "D:\Projects\YourRepo" `
  -Mode readonly `
  -Task "Read README.md only and summarize the project. Do not modify files." `
  -DryRun `
  -NoNotify
```

Expected result: the wrapper prints the selected provider, tier, model, artifact roots, and the exact external worker command. Dry-run does not start the worker.

## Readonly Canary

After `doctor` passes and the repo has at least one commit, remove `-DryRun` for a tiny readonly task:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\examples\readonly-canary.ps1 -Repo "D:\Projects\YourRepo"
```

Equivalent wrapper call:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\invoke-codex-praetor.ps1 `
  -Provider mimo `
  -Tier mimo-auto-readonly `
  -Repo "D:\Projects\YourRepo" `
  -Mode readonly `
  -RunMode blocking `
  -Task "Read README.md only. Final answer must start with CODEX_PRAETOR_CANARY_OK. Do not modify files." `
  -NoNotify
```

Codex must still verify the worker output and the git status afterward.
