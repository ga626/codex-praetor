import assert from "node:assert/strict";
import { existsSync } from "node:fs";
import { resolve } from "node:path";
import { getInvokeScriptPath } from "./paths.js";
import { decodeUtf8Chunks } from "./powershell.js";
import { parseJsonDocument } from "./evaluation-suite.js";
import {
  classifyWorkerOutcome,
  capabilityProfilesTool,
  detectConflictsTool,
  isActiveStatus,
  jobTimelineTool,
  dispatchPlanTaskTool,
  dispatchDryRunTool,
  dispatchTool,
  evaluationSuiteTool,
  getLaneTool,
  nextReadyTool,
  resultTool,
  listJobsTool,
  listLanesTool,
  planTool,
  routeIntentTool,
  runtimeInfoTool,
  statusTool,
  supervisionTool,
  startStageTool,
  recordProgressTool,
  requestHandoverTool,
  setReadinessLeaseTool,
  recordObservationTool,
  verifyTaskTool
} from "./tools.js";

const repo = process.env.CODEX_PRAETOR_TEST_REPO ?? resolve(process.cwd(), "..");

assert.deepEqual(
  parseJsonDocument("\r\n\uFEFF{\"windows\":true}", "BOM regression fixture"),
  { windows: true },
  "PowerShell JSON with leading whitespace and a BOM must remain parseable."
);

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

const profileResult = capabilityProfilesTool({ repo, include_unclassified: true });
assert.equal(profileResult.schema, "codex-praetor-capability-profile-set/v1");
assert.ok(Array.isArray(profileResult.profiles));
const evaluationSuite = evaluationSuiteTool();
assert.equal(evaluationSuite.schema, "codex-praetor-evaluation-suite-view/v1");
assert.ok(evaluationSuite.tasks.length >= 4);

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
    stdout_tail: "worker report: no auth material was accessed.",
    stderr_tail: ""
  }).class,
  "awaiting_codex_verification"
);
assert.equal(
  classifyWorkerOutcome({
    meta: { status: "process_exited" },
    completion: { status: "process_exited", exit_code: 0 },
    stdout_tail: "login required before the worker can start.",
    stderr_tail: ""
  }).class,
  "provider_auth_required"
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

const planId = `mcp-self-test-${process.pid}-${Date.now()}`;
const plan = await planTool({
  repo,
  title: "MCP self-test plan",
  tasks: [{
    title: "Dry-run route and status verification only.",
    task_family: "read_only_diagnosis",
    task_kind: "local_audit",
    mode: "readonly",
    acceptance: "The worker reports the requested route evidence and leaves no diff.",
    allowed_paths: ["README.md"],
    forbidden_paths: [".git", "**/*auth*"],
    required_checks: ["git diff --exit-code"],
    budget: { max_turns: 4, max_wall_seconds: 300 }
  }],
  plan_id: planId
});
assert.equal(plan.ok, true);
assert.equal(plan.plan_id, planId);
assert.equal(plan.task_ids?.length, 1);

const planDispatchPreview = await dispatchPlanTaskTool({ repo, plan_id: planId, task_id: "task-01", provider: "qoder", tier: "qoder-day-cheap", dry_run: true });
assert.equal(planDispatchPreview.ok, true, String((planDispatchPreview as Record<string, unknown>).stderr ?? (planDispatchPreview as Record<string, unknown>).message ?? ""));

const planStatus = statusTool({ repo, plan_id: planId });
assert.equal(planStatus.found, true);

assert.equal((await startStageTool({ repo, plan_id: planId, stage_id: "inspect", title: "Inspect evidence" })).ok, true);
assert.equal((await recordProgressTool({ repo, plan_id: planId, task_id: "task-01", stage_id: "inspect", kind: "evidence_added", summary: "A deterministic check completed.", checkpoint: { check: "git diff --exit-code" } })).ok, true);
assert.equal((await setReadinessLeaseTool({ repo, plan_id: planId, lease: { lease_id: "self-test-lease", provider: "qoder", cli_hash: "fixture", permission_profile: "readonly", workspace: repo, generation_id: "fixture", expires_at: "2026-12-31T00:00:00.000Z", state: "ready" } })).ok, true);
assert.equal((await recordObservationTool({ repo, plan_id: planId, task_id: "task-01", phase: "route_completed", pair_id: "self-test-pair", transport_mode: "supervised_cli_text", evidence: { route: "fixture" }, observed_at: "2026-07-27T00:00:00.000Z" })).ok, true);
const supervision = supervisionTool({ repo, plan_id: planId });
assert.equal(supervision.found, true);
if (!supervision.found || !supervision.supervision || !supervision.observations) throw new Error("Supervision record was not found after it was written.");
assert.equal(supervision.supervision.stages.length, 1);
assert.equal(supervision.supervision.readiness_leases.length, 1);
assert.equal(supervision.observations.length, 1);

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

const forgedAcceptance = await verifyTaskTool({
  repo,
  plan_id: planId,
  task_id: "task-01",
  verdict: "accepted",
  summary: "Self-test attempts acceptance without dispatching a real worker.",
  next_action: "No next action."
});
assert.equal(forgedAcceptance.ok, false);
assert.match(forgedAcceptance.stderr, /Accepted verification requires a recorded job directory/);

const readyAfterRejectedAcceptance = await nextReadyTool({ repo, plan_id: planId });
assert.equal(readyAfterRejectedAcceptance.ok, true);
assert.ok(readyAfterRejectedAcceptance.ready_tasks.length >= 1);

if (process.env.CODEX_PRAETOR_SELF_TEST_DRY_RUN === "1") {
  const dryRun = await dispatchDryRunTool({
    repo,
    task: "Dry run only. MCP self-test.",
    provider: "qoder",
    tier: "qoder-day-cheap",
    mode: "readonly",
    run_mode: "blocking"
  });
  assert.equal(dryRun.ok, true);
  assert.equal(dryRun.provider, "qoder");
  assert.equal(dryRun.tier, "qoder-day-cheap");
  assert.match(dryRun.command, /qoder/i);
}

console.log("codex-praetor-mcp self-test ok");
