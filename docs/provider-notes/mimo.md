# MiMo provider setup

Codex Praetor can dispatch MiMo only when the user has installed and authorized MiMo Code CLI on the same Windows machine.

Codex Praetor does not install MiMo, authorize an account for the user, read MiMo account files, or promise that a route is permanently free. It only calls the configured CLI path and keeps MiMo runs inside Codex-created Git worktrees.

## Install

Use Xiaomi MiMo's official installation path.

Official MiMo Code configuration:

https://mimo.mi.com/docs/en-US/tokenplan/integration/mimo-code

For Windows, the official docs currently describe npm installation with Node.js 18 or later:

```powershell
npm install -g @mimo-ai/cli
```

Verify installation:

```powershell
mimo --version
```

## Sign in

The official docs describe authorization through MiMo Code. A common terminal path is:

```powershell
mimo auth login
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
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\doctor-codex-praetor.ps1 -RequireHead -PublicRelease
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

The default MiMo route is configured as `mimo/mimo-auto`. Any free or discounted status depends on the user's MiMo account and current MiMo product policy. Confirm cost in your own account before large runs.

## If MiMo is missing

Nothing is broken. MiMo real dispatch is disabled, but Codex Praetor can still use local planning, route-intent, status, MCP visibility tools, and any other configured provider.
