# Provider capability matrix

This file records local CLI capability evidence used by the codex-praetor wrapper.

Full local help/model/stat snapshots should be kept outside the public repository when they include user paths, account names, usage pages, or screenshots.

```text
docs/internal/ or another private evidence folder
```

## CodeBuddy

Primary wrapper fields:

- model: `--model`
- reasoning effort: `--effort`
- max turns: `--max-turns`
- output: `--output-format`
- structured output: `--json-schema`
- tools: `--tools`, `--allowedTools`, `--disallowedTools`
- permissions: `--permission-mode`, `--subagent-permission-mode`
- agent: `--agent`, `--agents`

Keep disabled by default:

- `--model auto`
- `--continue`, `--resume`
- provider-native `--bg` / `--background`
- `--swarm`
- `--fallback-model`

## Qoder

Primary wrapper fields:

- model: `--model`
- reasoning effort: `--reasoning-effort`
- context window: `--context-window`
- output: `--output-format`
- max output: `--max-output-tokens`
- permissions: `--permission-mode`
- tools: `--tools`, `--allowed-tools`, `--disallowed-tools`
- agent: `--agent`, `--agents`
- cwd: `--cwd` / `-w`

Keep disabled by default:

- `--model Auto`
- `--continue`, `--resume`
- `--remote`, `--remote-control`, `--teleport`
- `--dangerously-skip-permissions` outside disposable worktrees

## MiMo Code

Primary wrapper fields:

- model: `--model`
- reasoning variant: `--variant`
- agent: `--agent`
- output: `--format json`
- cwd: `--dir`
- profile: `MIMOCODE_HOME`
- permissions: `MIMOCODE_PERMISSION` after separate validation

Keep disabled by default:

- `--continue`, `--session`
- `--share`
- `--attach`
- `--dangerously-skip-permissions`
- `mimo serve`, `mimo web`
- WezTerm launch path for automatic jobs


