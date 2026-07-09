# Reasoning effort policy

Reasoning effort is a soft choice: Codex decides per task, inside hard model and cost rails.

## Provider mapping

- CodeBuddy: `--effort <level>`
- Qoder: `--reasoning-effort <level>`
- MiMo Code: `--variant <level>`

## Default choices

- `low`: tiny, low-risk tasks.
- `medium`: normal default for bounded worker tasks.
- `high`: complex cross-file or ambiguous tasks.
- `xhigh` / `max`: do not use by default; require explicit user approval via wrapper override.

## Selection rule

Before dispatching, Codex should state:

```text
task difficulty:
risk:
chosen worker/model:
chosen effort:
why this effort:
why not a higher-cost option:
acceptance check:
```

Do not encode every effort/model combination as a separate tier. The tier defines the cost/model lane; Codex chooses effort within the lane.


