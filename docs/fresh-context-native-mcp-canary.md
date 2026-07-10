# Fresh-Context Native MCP Canary

Date: 2026-07-10

This is the final native MCP acceptance gate for Codex Praetor before a public alpha release. It proves that a fresh Codex tool context can see and call the packaged Codex Praetor MCP tools, rather than only proving the Node protocol smoke path.

Do not run this as a substitute for local validation. Run it after the public-release doctor, minimal validation, MCP protocol smoke, final URL replacement, and release package build have passed.

## Preconditions

- Final GitHub owner/repo URL is confirmed and applied to plugin metadata.
- `scripts/doctor-codex-praetor.ps1 -RequireHead -PublicRelease` passes with the public template.
- `scripts/test-codex-praetor.ps1` passes.
- MCP source tests and packaged protocol smoke pass.
- Local plugin package has been republished or the release package has been installed into a fresh Codex plugin context.
- Duplicate same-name `codex-praetor` MCP registrations have been removed.
- The current stale development thread is not used as the final proof point.

## Fresh Context

Use one of these fresh contexts:

- A newly opened Codex Desktop thread after plugin reload.
- A fresh Codex CLI or ephemeral execution context that exposes native MCP tools.

The proof must use native Codex Praetor MCP tool calls. A PowerShell script, SDK client, or direct Node stdio smoke test is useful support evidence, but it is not the final native MCP canary.

## Required Calls

The fresh context must show the native Codex Praetor MCP tools and successfully call at least:

- `codex_praetor_route_intent`

- `codex_praetor_dispatch_dry_run`

- `codex_praetor_list_lanes` or `codex_praetor_detect_conflicts`

Use a harmless readonly prompt such as:

```text
Route a readonly release canary for the current repository. Do not dispatch a real worker. Return the selected provider tier and the command that would be used.
```

The dry-run call must not create a real worker job, mutate repository files, or require provider credentials.

## Pass Criteria

- Tools are visible by their native MCP names in the fresh context.
- Route-intent returns a structured route decision without `Transport closed`, cancellation, or schema errors.
- Dispatch dry-run returns a dry-run plan and does not create a worker job.
- Lane or conflict read calls return structured state instead of transport errors.
- The main repository remains clean except for intentional release-documentation edits and ignored runtime/output directories.

## Failure Classification

- Tools absent: plugin discovery, packaging, installation, or reload failure.
- `Transport closed`: stale context, duplicate registration, packaged runtime failure, or host reload/cache issue. Re-run protocol smoke, remove duplicate registrations, republish, then try a new context.
- Tool returns schema errors: MCP tool contract or argument regression.
- Dry-run creates a job or mutates files: release blocker in the dispatch wrapper or MCP adapter.

## Evidence To Record

Record the exact fresh-context used, the tool names seen, the required call outcomes, and the final git status in the release-readiness audit or release notes before public publication. Do not paste provider tokens, account pages, local auth databases, or private path-heavy logs into public docs.
