# MiMo Code worker notes

MiMo Code is a terminal-native worker agent. Use the CLI directly; do not launch WezTerm for automatic worker jobs.

## Local facts

- The user must install MiMo Code locally and point Codex Praetor at the real `mimo` command or `mimo.cmd` path in their local config.
- Verified model for the default route: `mimo/mimo-auto`.

## Free-route evidence

In local validation, a smoke run forced `--model mimo/mimo-auto`, temporarily removed provider API-key influence from that process environment, returned a success marker, and the JSON event included `cost: 0`.

`mimo stats --models 10` showed `mimo/mimo-auto` with `Cost $0.0000`.

This proves the current local route is free at verification time. It does not prove permanent free availability; official wording describes MiMo Auto as limited-time free.

## Routing

Default-routable:

- `mimo/mimo-auto`

Known but not default-routable:

- `xiaomi/mimo-v2.5`
- `xiaomi/mimo-v2.5-pro`

Blocked/default-denied:

- `openai/*`
- old MiMo V2 models
- `xiaomi/mimo-v2.5-pro-ultraspeed`
- `auto`

## CLI shape

Readonly/planning:

```powershell
mimo run --model "mimo/mimo-auto" --format json --dir <repo>.worktrees\<name> "<task packet>"
```

Edit worktree:

```powershell
mimo run --model "mimo/mimo-auto" --agent build --format json --dir <worktree> "<task packet>"
```

Use `--variant <level>` only when Codex has selected a reasoning effort for the task.

## Worktree requirement

Local wrapper validation showed that MiMo can create `.mimocode` files in the target project even when the user asks for a readonly smoke. Therefore the wrapper runs MiMo inside a Codex-created worktree for both readonly and edit tasks. Treat MiMo as agentic and useful, but not filesystem-readonly by default.

Do not force `--agent plan` for readonly tasks. Validation on 2026-07-10 showed that the current MiMo plan agent can treat the task packet as plan-mode instructions and ignore the actual task. The default MiMo agent completed a minimal README canary correctly.

Background watcher validation later confirmed this design: MiMo generated `.mimocode` inside the disposable worktree, the main repo stayed clean, `completion.json` recorded exit code `0`, and the watcher parsed `provider_cost=0` from the JSON event stream.

## Output parsing

`--format json` is JSON event stream output. Parse:

- `type=text` / `part.text` as the worker answer.
- `type=step_finish` / `cost` and `tokens` for billing validation.

