import assert from "node:assert/strict";
import { existsSync } from "node:fs";
import { getInvokeScriptPath } from "./paths.js";
import {
  detectConflictsTool,
  dispatchDryRunTool,
  getLaneTool,
  listJobsTool,
  listLanesTool,
  planTool,
  routeIntentTool,
  statusTool
} from "./tools.js";

const repo = process.env.CODEX_PRAETOR_TEST_REPO ?? "D:\\Projects\\CodexPraetor";

assert.equal(routeIntentTool({ request: "把这个任务拆一下，分配给其他 agent 做" }).route, "codex_praetor_external_worker");
assert.equal(routeIntentTool({ request: "开省钱模式，分配给其他 agent" }).route, "codex_praetor_external_worker");
assert.equal(
  routeIntentTool({ request: "Use Codex subagent for parallel review", allow_native_codex_subagents: true }).route,
  "native_codex_subagent"
);
assert.equal(routeIntentTool({ request: "Use Codex subagent for parallel review" }).route, "needs_clarification");

assert.ok(existsSync(getInvokeScriptPath()), "invoke script should exist");

const listResult = listJobsTool({ repo, status: "all", limit: 5 });
assert.equal(listResult.repo.length > 0, true);
assert.ok(Array.isArray(listResult.jobs));

const missingStatus = statusTool({ repo, job_id: "missing-job-for-self-test" });
assert.equal(missingStatus.found, false);

const planId = "mcp-self-test";
const plan = await planTool({
  repo,
  title: "MCP self-test plan",
  tasks: ["Dry-run route and status verification only."],
  mode: "readonly",
  plan_id: planId
});
assert.equal(plan.ok, true);
assert.equal(plan.plan_id, planId);
assert.equal(plan.task_ids.length, 1);

const planStatus = statusTool({ repo, plan_id: planId });
assert.equal(planStatus.found, true);

const lanes = listLanesTool({ repo, status: "all", limit: 20 });
assert.equal(Array.isArray(lanes.lanes), true);
assert.ok(lanes.lanes.some((lane) => lane.lane_id === `plan:${planId}:task-01`));

const laneStatus = getLaneTool({ repo, lane_id: `plan:${planId}:task-01` });
assert.equal(laneStatus.found, true);

const readonlyConflict = detectConflictsTool({ repo, mode: "readonly" });
assert.equal(readonlyConflict.ok, true);

const editConflict = detectConflictsTool({ repo, mode: "edit", file_scope: ["mcp/src/tools.ts"] });
assert.equal(Array.isArray(editConflict.conflicts), true);

const dryRun = await dispatchDryRunTool({
  repo,
  task: "Dry run only. MCP self-test.",
  provider: "mimo",
  tier: "mimo-auto-readonly",
  mode: "readonly",
  run_mode: "blocking"
});
assert.equal(dryRun.ok, true);
assert.equal(dryRun.provider, "mimo");
assert.equal(dryRun.tier, "mimo-auto-readonly");
assert.match(dryRun.command, /mimo/);

console.log("codex-praetor-mcp self-test ok");
