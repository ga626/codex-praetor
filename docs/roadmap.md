# Codex Praetor Roadmap

## Current Status: 2026-07-10 07:20

- Repository now has a clean alpha baseline and a second commit for MiMo readonly dispatch fixes.
- `doctor -RequireHead -PublicRelease` passes.
- `scripts/test-codex-praetor.ps1` passes with 0 warnings and 0 failures.
- The C-drive installed skill is a real copied directory and matches the D-drive source skill.
- The duplicate global `mcp_servers.codex-praetor` entry was removed from local Codex config; the personal plugin entry remains enabled.
- Current thread native MCP calls still fail with `Transport closed`, which now points to stale current-thread transport state rather than bundled MCP server failure.
- A real MiMo readonly release audit completed in an isolated worktree and did not dirty the main repo.
- Public release files now include MIT license, changelog, security policy, contributing notes, examples, and a release-readiness audit.

Next: improve doctor provider UX, republish the personal plugin once, and verify native MCP in a refreshed Codex tool context.

## Current Status: 2026-07-09 22:41

- Source MCP v0 works and exposes eight tools.
- C-drive installed skill is still a real copied directory, not a link.
- Personal plugin source/cache were republished as `0.1.0-alpha+codex.20260709224130`.
- Plugin `.mcp.json` now sets `cwd = "."` so bundled relative runtime paths resolve from the plugin root.
- The publish script now writes cachebuster `plugin.json` as UTF-8 without BOM; Codex's plugin parser rejected the prior BOM file.
- Latest cache `plugin.json` starts with `{` (`7B 0D 0A`), not a BOM.
- MCP tools now carry safety annotations:
  - route-intent, dry-run, list-jobs, list-lanes, get-lane, detect-conflicts, and status are marked read-only, non-destructive, closed-world.
  - plan is marked non-destructive additive project-local write.
- The plugin MCP smoke test now asserts these annotations so future regressions are caught.
- Local Codex config can use a direct `[mcp_servers.codex-praetor]` registration pointing to `%USERPROFILE%\plugins\codex-praetor\mcp\dist\server.js` during development.
- Local Codex config can set Codex Praetor MCP tool approval to `auto` for the direct MCP server and the personal plugin MCP server during canary testing.
- Direct MCP protocol smoke against the C-drive runtime passes.
- Fresh `codex debug prompt-input` now lists `Codex Praetor` under Available plugins.
- On some Windows installs, the WindowsApps `codex.exe` alias may return `Access is denied` from PowerShell; use the real Codex binary path reported by the local Codex environment when running canaries.
- A fresh `codex exec --ephemeral` canary successfully called `codex_praetor_route_intent` and `codex_praetor_dispatch_dry_run` through native MCP.
- The canary did not create a native Codex subagent and did not launch a real worker.
- Dry-run stdout now preserves Chinese task text after the PowerShell wrapper was forced to UTF-8.
- `codex_praetor_dispatch_dry_run` now returns structured `repo`, `task`, and `mode` fields so callers do not need to parse a multi-line shell command.
- Added lane/conflict tools:
  - `codex_praetor_list_lanes`
  - `codex_praetor_get_lane`
  - `codex_praetor_detect_conflicts`
- Lane state is derived from project-local jobs, plans, and repo edit locks. It does not introduce a hidden global queue.
- Protocol smoke now actually calls lane/conflict tools; current result: lane count 3, readonly conflict count 0, edit conflict count 0.
- A fresh `codex exec --ephemeral` verification attempt for the new lane tools did not use native MCP tool cards; it fell back to an SDK client. Treat that as protocol evidence only, not native UI/tool-card evidence.
- This already-open thread still does not expose `codex_praetor_*` via tool discovery, so live native calls should be verified in a refreshed tool context.

Interpretation: plugin discovery, installed MCP protocol, native fresh-context route/dry-run calls, and the lane/conflict protocol layer are now repaired. The next implementation task is the first controlled real-worker canary, starting with MiMo readonly and no file modifications.

## Phase 0: Migration

- Create `D:\Projects\CodexPraetor`.
- Move skill, scripts, references, and reports into product-shaped folders.
- Rename user-facing `codex-praetor` labels to `Codex Praetor`.
- Keep compatibility with prior local validation where practical.
- Validate dry-run.

## Phase 1: Skill Stabilization

- Keep the installed `codex-praetor` skill as a real copied directory, not a link.
- Add a short global routing rule that task-splitting or "other agent" requests mean Codex Praetor external workers, not native Codex subagents.
- Test natural-language triggers:
  - "把任务拆一下"
  - "拆分任务给其他 agent"
  - "交给其他 agent 做一部分"
- Confirm Codex does not satisfy these prompts by spawning Codex subagents.
- Confirm the first visible action is a route decision, dry-run command, or MCP route-intent tool once MCP exists.

## Phase 2: Native Plugin Discovery

- Fix personal plugin discovery until fresh Codex sessions can see Codex Praetor.
- Compare the personal plugin and cache layout against the working KnowledgeRadar plugin.
- Verify `tool_search` can discover `codex_praetor_route_intent`.
- Keep direct global MCP registration as the development/runtime canary until plugin-card discovery is fixed.
- Fix native MCP tool-call cancellation for dry-run/read-only tools.
- Add a reliable fresh-context canary path that does not depend on a blocked WindowsApps CLI entrypoint.
- Status: done for route-intent and dry-run in `codex exec --ephemeral`.

## Phase 3: Minimal MCP Tool Cards

- Implement a thin MCP server.
- Start with route-intent, status, and dry-run tools only.
- Verify Codex UI tool cards.
- Keep script dispatch as source of truth.

## Phase 4: Multi-Conversation Lane State

- Support up to about five independent conversation lanes.
- Use project-local job/plan state plus a light global metadata index.
- Detect edit conflicts instead of hiding work in a central queue.
- Keep Codex as the only merger and final verifier.
- Status: first thin MCP layer done for project-local jobs/plans/locks.
- Next: persist file-scope metadata when real dispatch starts so conflict detection can become more precise than repo-level edit locks.

## Phase 5: Real Worker Dispatch Through MCP

- Add CodeBuddy dispatch.
- Add Qoder dispatch.
- Add MiMo dispatch.
- Support blocking and background modes.
- Read completion files through MCP.
- Next canary: one MiMo readonly real dispatch with a tiny, inspectable task and no file modifications.

## Phase 6: Product Hardening

- Finalize plugin manifest.
- Bundle skill and MCP config.
- Add local marketplace entry for testing.
- Verify plugin install in Codex.
- Replace local absolute Node paths with a portable launcher/runtime strategy.

## Phase 7: GitHub Release

- Clean local-only paths and secrets.
- Add license.
- Add installation guide.
- Add example tasks.
- Mark first release as `0.1.0-alpha`.


