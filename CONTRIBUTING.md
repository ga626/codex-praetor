# Contributing

Codex Praetor is Windows-first and Codex-first for the alpha phase.

Before sending changes:

1. Keep Codex as planner, supervisor, and verifier. Do not replace external worker delegation with native Codex subagents.
2. Keep source and install paths separate. Do not add symlinks, junctions, or automatic C-drive/D-drive sync.
3. Do not commit provider credentials, account files, local caches, usage screenshots, or personal logs.
4. Run:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\doctor-codex-praetor.ps1 -RequireHead -PublicRelease
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\test-codex-praetor.ps1
```

Provider-specific real dispatch tests should use isolated worktrees and a small readonly canary first.
