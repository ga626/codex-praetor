import assert from "node:assert/strict";
import { existsSync } from "node:fs";
import { resolve } from "node:path";
import { getInvokeScriptPath } from "./paths.js";
import { decodeUtf8Chunks } from "./powershell.js";
import {
  classifyWorkerOutcome,
  detectConflictsTool,
  isActiveStatus,
  jobTimelineTool,
  dispatchPlanTaskTool,
  dispatchDryRunTool,
  dispatchTool,
  getLaneTool,
  nextReadyTool,
  resultTool,
  listJobsTool,
  listLanesTool,
  planTool,
  routeIntentTool,
  runtimeInfoTool,
  statusTool,
  verifyTaskTool
} from "./tools.js";

const repo = process.env.CODEX_PRAETOR_TEST_REPO ?? resolve(process.cwd(), "..");

assert.equal(routeIntentTool({ request: "把这个任务拆一下，分配给其他 agent 做" }).route, "codex_praetor_external_worker");
assert.equal(routeIntentTool({ request: "拆分一下任务，分配给其他 agent 做只读验收" }).route, "codex_praetor_external_worker");
assert.equal(
  routeIntentTool({ request: "拆分一下任务，分配给其他 agent 做只读验收，不要创建 Codex subagent。" }).route,
  "codex_praetor_external_worker"
);
assert.equal(
  routeIntentTool({ request: "做一次外部调研并联网搜索官方资料" }).route,
  "codex_kr_primary_research"
);
const researchRoute = routeIntentTool({ request: "拆分外部调研，分配给其他 agent 找官方资料" });
assert.equal(researchRoute.worker_research_eligible, true);
assert.equal(researchRoute.research_authority, "codex_kr_primary");
const runtimeInfo = runtimeInfoTool();
assert.equal(runtimeInfo.runtime_contract !== null, true);
assert.match(runtimeInfo.runtime_identity.runtime_contract_sha256, /^[0-9a-f]{64}$/);
assert.ok(runtimeInfo.runtime_identity.process_id > 0);
assert.ok(runtimeInfo.runtime_identity.project_root.length > 0);
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

const missingResult = resultTool({ repo, job_id: "missing-job-for-self-test" });
assert.equal(missingResult.found, false);

const missingTimeline = jobTimelineTool({ repo, job_id: "missing-job-for-self-test" });
assert.equal(missingTimeline.found, false);

assert.equal(typeof dispatchTool, "function");
assert.equal(typeof dispatchPlanTaskTool, "function");
const chinese = Buffer.from("当前运行 generation", "utf8");
assert.equal(decodeUtf8Chunks([chinese.subarray(0, 4), chinese.subarray(4, 7), chinese.subarray(7)]), "当前运行 generation");
assert.equal(isActiveStatus("running"), true);
assert.equal(isActiveStatus("process_exited"), false);
assert.equal(isActiveStatus("timed_out"), false);
assert.equal(isActiveStatus("watcher_failed"), false);
assert.equal(isActiveStatus("unknown"), false);
assert.equal(
  classifyWorkerOutcome({
    meta: { status: "process_exited" },
    completion: { status: "process_exited", exit_code: 0 },
    stdout_tail: "worker report",
    stderr_tail: ""
  }).class,
  "awaiting_codex_verification"
);
assert.equal(
  classifyWorkerOutcome({
    meta: { status: "timed_out" },
    completion: { status: "timed_out", exit_code: 124 },
    stdout_tail: "",
    stderr_tail: ""
  }).class,
  "worker_timed_out"
);
assert.equal(
  classifyWorkerOutcome({
    meta: { status: "process_exited" },
    completion: { status: "process_exited", exit_code: 0, failure_class: "provider_risk_control", evidence_state: "evidence_missing" },
    stdout_tail: '{"type":"error"}',
    stderr_tail: ""
  }).class,
  "provider_risk_control"
);
assert.equal(
  classifyWorkerOutcome({
    meta: { status: "process_exited" },
    completion: { status: "process_exited", exit_code: 0, failure_class: "max_turns_exceeded", artifact_state: "partial_worktree_diff" },
    stdout_tail: "",
    stderr_tail: "Max turns (16) exceeded"
  }).class,
  "worker_max_turns_exceeded"
);

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

const readyBeforeVerification = await nextReadyTool({ repo, plan_id: planId });
assert.equal(readyBeforeVerification.ok, true);
assert.ok(readyBeforeVerification.ready_tasks.length >= 1);

const lanes = listLanesTool({ repo, status: "all", limit: 20 });
assert.equal(Array.isArray(lanes.lanes), true);
assert.ok(lanes.lanes.some((lane) => lane.lane_id === `plan:${planId}:task-01`));

const laneStatus = getLaneTool({ repo, lane_id: `plan:${planId}:task-01` });
assert.equal(laneStatus.found, true);

const readonlyConflict = detectConflictsTool({ repo, mode: "readonly" });
assert.equal(readonlyConflict.ok, true);

const editConflict = detectConflictsTool({ repo, mode: "edit", file_scope: ["mcp/src/tools.ts"] });
assert.equal(Array.isArray(editConflict.conflicts), true);

const verification = await verifyTaskTool({
  repo,
  plan_id: planId,
  task_id: "task-01",
  verdict: "accepted",
  summary: "Self-test verification accepted without dispatching a real worker.",
  next_action: "No next action."
});
assert.equal(verification.ok, true);

const readyAfterVerification = await nextReadyTool({ repo, plan_id: planId });
assert.equal(readyAfterVerification.ok, true);

if (process.env.CODEX_PRAETOR_SELF_TEST_DRY_RUN === "1") {
  const dryRun = await dispatchDryRunTool({
    repo,
    task: "Dry run only. MCP self-test.",
    provider: "mimo",
    tier: "mimo-isolated-audit",
    mode: "readonly",
    run_mode: "blocking"
  });
  assert.equal(dryRun.ok, true);
  assert.equal(dryRun.provider, "mimo");
  assert.equal(dryRun.tier, "mimo-isolated-audit");
  assert.match(dryRun.command, /mimo/);
}

console.log("codex-praetor-mcp self-test ok");
