# Qoder provider setup

Codex Praetor can dispatch Qoder only when the user has installed and signed in to Qoder CLI or QoderWork CLI on the same Windows machine.

Codex Praetor does not install Qoder, sign in for the user, read Qoder account files, or promise that a model is free. It only calls the configured CLI path with the model allowlist from the local config.

普通用户只需要记住一句：Codex Praetor 可以发现并调用 Qoder，但 Qoder 账号登录、浏览器授权、Personal Access Token 和额度状态都属于 Qoder 自己的流程。

## Install

Use Qoder's official installation path for your region and edition.

Official Qoder CLI quick start:

https://docs.qoder.com/en/cli/quick-start

The official quick start currently documents Windows PowerShell installation through:

```powershell
irm https://qoder.com/install.ps1 | iex
```

Verify installation:

```powershell
qodercli --version
```

The official quick start also notes that Windows on Arm is not supported yet. If installation fails on that platform, treat it as a Qoder platform boundary, not as a Codex Praetor failure.

## Sign in

Qoder requires authentication before use. The official docs describe interactive sign-in by starting the CLI and running `/login`, and also describe a personal access token environment variable for automation.

For Codex Praetor, prefer the normal interactive provider login first. Do not put access tokens into this repository, README examples, screenshots, Git history, or local config files.

## Configure Codex Praetor

Copy the public template to an ignored local config:

```powershell
Copy-Item .\config\codex-praetor-tiers.example.json .\config\codex-praetor.local.json
```

Then edit only your local config:

```json
{
  "providers": {
    "qoder": {
      "cliPath": "C:\\Path\\To\\qodercli.exe"
    }
  }
}
```

If `qodercli` is on `PATH`, you may use `qodercli` as the path.

## Verify

Run doctor:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\verify\doctor-codex-praetor.ps1 -RequireHead -PublicRelease
```

Expected doctor states:

- `provider:qoder:cli` ready: the CLI path exists or resolves from `PATH`.
- `provider:qoder:version` ready or info: version probing succeeded, or doctor could not prove compatibility.
- `provider:qoder:auth` info: doctor intentionally does not inspect Qoder login state.

Before real dispatch, run the readonly canary from a Git repository with a valid `HEAD`.

Preview only:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\verify\test-provider-readonly-canary.ps1 -Provider qoder
```

Real readonly canary:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\verify\test-provider-readonly-canary.ps1 -Provider qoder -Apply
```

The canary asks Qoder to read `README.md`, return `CODEX_PRAETOR_CANARY_OK`, and leave the main repository status unchanged.

## Cost and model boundary

Default-routable Qoder models are configured in `codex-praetor-tiers.json`. Provider `Auto` is blocked by default because it gives model choice back to the provider.

Credits, discounts, daily check-in rewards, expiration, and account balance are Qoder platform facts. Confirm them in your own Qoder account before large runs.

## If Qoder is missing

Nothing is broken. Qoder real dispatch is disabled, but Codex Praetor can still use local planning, route-intent, dry-run for configured providers, status, and MCP visibility tools.
