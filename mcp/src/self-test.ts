import assert from "node:assert/strict";
import { existsSync, readFileSync } from "node:fs";
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
  verifyTaskTool
} from "./tools.js";

const repo = process.env.CODEX_PRAETOR_TEST_REPO ?? resolve(process.cwd(), "..");

assert.deepEqual(
  parseJsonDocument("\r\n\uFEFF{\"windows\":true}", "BOM regression fixture"),
  { windows: true },
  "PowerShell JSON with leading whitespace and a BOM must remain parseable."
);

const delegatedRoute = routeIntentTool({ request: "把这个任务拆一下，分配给其他 agent 做" });
assert.equal(delegatedRoute.route, "codex_praetor_external_worker");
assert.equal(delegatedRoute.dispatch_required, true);
assert.equal(delegatedRoute.next_required_tool, "codex_praetor_plan");
assert.ok(delegatedRoute.delegable_subtasks.length > 0);
assert.ok(delegatedRoute.codex_reserved_tasks.length > 0);
assert.equal(delegatedRoute.blocking_reason, undefined);
assert.equal(routeIntentTool({ request: "拆分一下任务，分配给其他 agent 做只读验收" }).dispatch_required, true);
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
assert.equal(researchRoute.dispatch_required, true);
assert.equal(researchRoute.next_required_tool, "codex_kr_primary_research");
const runtimeInfo = runtimeInfoTool();
assert.equal(runtimeInfo.runtime_contract !== null, true);
assert.match(runtimeInfo.runtime_identity.runtime_contract_sha256, /^[0-9a-f]{64}$/);
assert.equal(runtimeInfo.runtime_identity.version, runtimeInfo.runtime_contract?.version ?? "");
assert.ok(runtimeInfo.runtime_identity.process_id > 0);
assert.ok(runtimeInfo.runtime_identity.project_root.length > 0);
assert.equal(
  routeIntentTool({ request: "Use Codex subagent for parallel review", allow_native_codex_subagents: true }).route,
  "native_codex_subagent"
);
assert.equal(routeIntentTool({ request: "Use Codex subagent for parallel review" }).route, "needs_clarification");
assert.equal(routeIntentTool({ request: "普通本地检查" }).dispatch_required, false);
assert.equal(routeIntentTool({ request: "普通本地检查" }).next_required_tool, "codex_direct");
const retainedRoute = routeIntentTool({ request: "这个任务不要外派，Codex 自己做" });
assert.equal(retainedRoute.route, "codex_retains_ineligible_work");
assert.equal(retainedRoute.dispatch_required, false);
assert.equal(retainedRoute.blocking_reason, "user_requested_codex_only");
assert.equal(routeIntentTool({ request: "开启执政官模式后拆分这个任务" }).dispatch_required, true);

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
    meta: { status: "process_exited" },
    completion: { status: "process_exited", exit_code: 0 },
    stdout_tail: "worker report completed after an out-of-contract request was permission denied.",
    stderr_tail: "permission denied by declared ACP boundary"
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

const planId = `mcp-self-test-${process.pid}-${Date.now()}`;
const plan = await planTool({
  repo,
  title: "MCP self-test plan",
  tasks: [{
    task_id: "contract-scope-round-trip",
    title: "Dry-run route and status verification only.",
    task_family: "read_only_diagnosis",
    task_kind: "local_audit",
    mode: "readonly",
    acceptance: "The worker reports the requested route evidence and leaves no diff.",
    allowed_paths: ["README.md", "mcp/src"],
    forbidden_paths: [".git", "**/*auth*", "plugin"],
    required_checks: ["git diff --exit-code", "git status --short"],
    immutable_paths: ["README.md", "mcp/src"],
    budget: { max_turns: 4, max_wall_seconds: 300 }
  }, {
    task_id: "contract-dependent-task",
    title: "Contract dependency projection verification.",
    task_family: "read_only_diagnosis",
    task_kind: "local_audit",
    mode: "readonly",
    acceptance: "The task remains pending until the prerequisite is accepted.",
    depends_on: ["contract-scope-round-trip"],
    allowed_paths: ["README.md"],
    forbidden_paths: [".git"],
    required_checks: ["git status --short"],
    immutable_paths: [],
    budget: { max_wall_seconds: 300 }
  }],
  plan_id: planId
});
assert.equal(plan.ok, true);
assert.equal(plan.plan_id, planId);
assert.deepEqual(plan.task_ids, ["contract-scope-round-trip", "contract-dependent-task"]);
const persistedPlan = parseJsonDocument(readFileSync(String(plan.plan_path), "utf8"), "Persisted plan round-trip fixture") as {
  tasks: Array<{
    task_id: string;
    depends_on: string[];
    allowed_paths: string[];
    forbidden_paths: string[];
    immutable_paths: string[];
    completion_definition: { required_checks: string[] };
  }>;
};
const persistedTask = persistedPlan.tasks.find((task) => task.task_id === "contract-scope-round-trip");
assert.ok(persistedTask);
const dependentTask = persistedPlan.tasks.find((task) => task.task_id === "contract-dependent-task");
assert.ok(dependentTask);
assert.deepEqual(persistedTask.allowed_paths, ["README.md", "mcp/src"]);
assert.deepEqual(persistedTask.forbidden_paths, [".git", "**/*auth*", "plugin"]);
assert.deepEqual(persistedTask.immutable_paths, ["README.md", "mcp/src"]);
assert.deepEqual(persistedTask.completion_definition.required_checks, ["git diff --exit-code", "git status --short"]);
assert.deepEqual(persistedTask.depends_on, []);
assert.deepEqual(dependentTask.depends_on, ["contract-scope-round-trip"]);
assert.deepEqual(dependentTask.immutable_paths, []);

const planDispatchPreview = await dispatchPlanTaskTool({ repo, plan_id: planId, task_id: "contract-scope-round-trip", provider: "qoder", tier: "qoder-day-cheap", dry_run: true });
assert.equal(planDispatchPreview.ok, true, String((planDispatchPreview as Record<string, unknown>).stderr ?? (planDispatchPreview as Record<string, unknown>).message ?? ""));
const planPreviewRecord = planDispatchPreview as { display: { 阶段: string; 状态: string }; job_id: string };
assert.equal(planPreviewRecord.display.阶段, "预演 worker 派工", "A plan dry-run must never claim to have dispatched a worker.");
assert.equal(planPreviewRecord.display.状态, "预演通过，未启动");
assert.equal(planPreviewRecord.job_id, "", "A dry-run must not create a worker job.");

const planStatus = statusTool({ repo, plan_id: planId });
assert.equal(planStatus.found, true);

const readyBeforeVerification = await nextReadyTool({ repo, plan_id: planId });
assert.equal(readyBeforeVerification.ok, true);
assert.deepEqual(readyBeforeVerification.ready_tasks.map((task) => String((task as { task_id?: unknown }).task_id ?? "")), ["contract-scope-round-trip"]);

const lanes = listLanesTool({ repo, status: "all", limit: 20 });
assert.equal(Array.isArray(lanes.lanes), true);
assert.ok(lanes.lanes.some((lane) => lane.lane_id === `plan:${planId}:contract-scope-round-trip`));

const laneStatus = getLaneTool({ repo, lane_id: `plan:${planId}:contract-scope-round-trip` });
assert.equal(laneStatus.found, true);

const readonlyConflict = detectConflictsTool({ repo, mode: "readonly" });
assert.equal(readonlyConflict.ok, true);

const editConflict = detectConflictsTool({ repo, mode: "edit", file_scope: ["mcp/src/tools.ts"] });
assert.equal(Array.isArray(editConflict.conflicts), true);

const forgedAcceptance = await verifyTaskTool({
  repo,
  plan_id: planId,
  task_id: "contract-scope-round-trip",
  verdict: "accepted",
  summary: "Self-test attempts acceptance without dispatching a real worker.",
  next_action: "No next action."
});
assert.equal(forgedAcceptance.ok, false);
assert.match(forgedAcceptance.stderr, /Accepted verification requires a recorded job directory/);

const readyAfterRejectedAcceptance = await nextReadyTool({ repo, plan_id: planId });
assert.equal(readyAfterRejectedAcceptance.ok, true);
assert.deepEqual(readyAfterRejectedAcceptance.ready_tasks.map((task) => String((task as { task_id?: unknown }).task_id ?? "")), ["contract-scope-round-trip"]);

const invalidPlanId = `mcp-invalid-plan-${process.pid}-${Date.now()}`;
const invalidPlan = await planTool({
  repo,
  title: "Invalid plan contract",
  plan_id: invalidPlanId,
  tasks: [{
    task_id: "invalid task id",
    title: "Invalid task identifier",
    task_family: "read_only_diagnosis",
    task_kind: "local_audit",
    mode: "readonly",
    acceptance: "Must be rejected before durable state is written.",
    allowed_paths: ["README.md"],
    forbidden_paths: [".git"],
    required_checks: ["git status --short"],
    budget: { max_wall_seconds: 300 }
  }]
});
assert.equal(invalidPlan.ok, false);
assert.equal(existsSync(resolve(repo, ".codex-praetor", "plans", invalidPlanId, "plan.json")), false);

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
