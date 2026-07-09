# CodeBuddy Setup Notes

Use these notes when CodeBuddy or WorkBuddy CLI setup, login, or non-interactive worker runs are in scope.

Do not store or print full secrets. Keep API keys, auth tokens, desktop account state, local app databases, and credential-manager data outside this repository.

## Public Rules

- Install CodeBuddy or WorkBuddy through the provider's official channel.
- Complete the provider's normal login flow before asking Codex Praetor to dispatch real work.
- Non-interactive worker calls may require provider-supported environment variables or existing platform login state.
- China edition users may need the provider's China-network environment setting. Confirm this in the official CodeBuddy documentation for the installed edition.
- Tool approval and directory trust are separate from authentication. A logged-in CLI can still refuse file reads or edits if the tool permission mode is too strict.

## Codex Praetor Defaults

- The default CodeBuddy tier uses a fixed model id, not `auto`.
- The wrapper blocks provider `auto` by default so the provider cannot silently route to an unknown or paid model.
- Current default-routable model ids are configured in `codex-praetor-tiers.json`.
- For readonly checks on Windows, the wrapper uses a small tool allowlist.
- Edit tasks should run in a Codex-created Git worktree, followed by Codex review and tests.

## User Checklist

1. Install CodeBuddy or WorkBuddy CLI.
2. Confirm the CLI can run from PowerShell.
3. Complete login or configure provider-supported authentication outside this repo.
4. Copy `config/codex-praetor-tiers.example.json` to a local ignored config.
5. Set `providers.codebuddy.nodePath` and `providers.codebuddy.cliPath` for your machine.
6. Run `scripts/doctor-codex-praetor.ps1`.
7. Run a dry-run before any real worker call.

## Sources

- https://www.codebuddy.cn/docs/cli/iam
- https://www.codebuddy.ai/docs/zh/cli/env-vars
