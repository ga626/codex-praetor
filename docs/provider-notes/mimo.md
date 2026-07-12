# MiMo provider setup

Codex Praetor can dispatch MiMo only when the user has installed MiMo Code CLI on the same Windows machine.

Codex Praetor does not install MiMo, authorize an account for the user, read MiMo account files, or promise that a route is permanently free. It only calls the configured CLI path and keeps MiMo runs inside Codex-created Git worktrees.

普通用户只需要记住一句：MiMo 的第一推荐路线是 `mimo/mimo-auto`，这是官方限时免费、匿名、零配置通道；如果它不可用，或者你要使用 MiMo Platform / Token Plan / 自定义 provider，才进入 `/connect`、API key 或账单流程。

## Install

Use Xiaomi MiMo's official installation path.

Official MiMo Code README:

https://github.com/XiaomiMiMo/MiMo-Code

For Windows, the official README currently documents a PowerShell installer:

```powershell
powershell -ep Bypass -c "irm https://mimo.xiaomi.com/install.ps1 | iex"
```

It also documents npm installation as a cross-platform route:

```powershell
npm install -g @mimo-ai/cli
```

Verify installation:

```powershell
mimo --version
```

## MiMo Auto and provider connection

MiMo Code can start through MiMo Auto without the user pasting an API key. This is the route Codex Praetor should try first for MiMo readonly canaries.

If MiMo Auto fails, is unavailable, or the user wants a specific MiMo Platform / Token Plan / custom provider route, use MiMo's own connection flow:

```powershell
/connect
```

Follow MiMo's own account and Token Plan guidance. Codex Praetor will not inspect or copy MiMo API keys, provider cache, account balance, or local authorization files.

## Configure Codex Praetor

Copy the public template to an ignored local config:

```powershell
Copy-Item .\config\codex-praetor-tiers.example.json .\config\codex-praetor.local.json
```

Then edit only your local config:

```json
{
  "providers": {
    "mimo": {
      "cliPath": "C:\\Path\\To\\mimo.cmd"
    }
  }
}
```

If `mimo` is on `PATH`, you may use `mimo` or `mimo.cmd`.

## Verify

Run doctor:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\verify\doctor-codex-praetor.ps1 -RequireHead -PublicRelease
```

Expected doctor states:

- `provider:mimo:cli` ready: the CLI path exists or resolves from `PATH`.
- `provider:mimo:version` ready or info: version probing succeeded, timed out, or doctor could not prove compatibility.
- `provider:mimo:auth` info: doctor intentionally does not inspect login state.

Before real dispatch, run a dry-run or readonly canary from a Git repository with a valid `HEAD`.

## Worktree boundary

MiMo can write `.mimocode` session or plan files even for tasks that look readonly. Codex Praetor therefore runs MiMo inside an isolated Git worktree for both readonly and edit tasks.

The main repository should remain clean after the worker exits. Codex must still inspect completion files, stdout/stderr summaries, and the final git state before accepting the worker result.

## Cost and model boundary

The default MiMo route is configured as `mimo/mimo-auto`. Treat it as a limited-time official free anonymous channel, not as a permanent guarantee. Any free, discounted, paid, Token Plan, or API-key status depends on current MiMo product policy and the user's chosen route.

## If MiMo is missing

Nothing is broken. MiMo real dispatch is disabled, but Codex Praetor can still use local planning, route-intent, status, MCP visibility tools, and any other configured provider.
