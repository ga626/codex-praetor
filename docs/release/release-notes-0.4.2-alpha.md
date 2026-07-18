# Codex Praetor 0.4.2-alpha

## This release fixes

`0.4.1-alpha` could write an active release receipt after Windows rejected the maintenance task registration. That made activation look complete while health correctly remained degraded.

## Main changes

- The maintenance installer treats `Register-ScheduledTask` access failures as real failures and attempts an equivalent user-level `schtasks.exe` XML registration.
- Registration is checked after creation for existence, enabled state, executable, and arguments.
- If both Windows registration paths fail, the installer exits nonzero and leaves activation incomplete.
- Stable activation installs and verifies maintenance before writing the active receipt.

## User impact

Users do not need elevation for the intended user-level task. On managed Windows systems that block both registration backends, setup reports a real failure instead of claiming that automatic retirement is enabled.

## Release acceptance

After merge, publish `v0.4.2-alpha` as a new immutable tag with its zip and `.sha256`. Stage from the downloaded asset, validate the native runtime generation and provider readiness, activate, then require `get-codex-praetor-health.ps1 -Json` to return `ready`.
