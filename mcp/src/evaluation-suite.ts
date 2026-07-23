import { readFileSync } from "node:fs";
import { getEvaluationInitializerPath, getEvaluationVerifierPath, getPlanRoot, getPlanScriptPath, getRuntimeDataPath, resolveExistingRepo } from "./paths.js";
import { runPowerShell } from "./powershell.js";

type RecordValue = Record<string, unknown>;

function asRecord(value: unknown): RecordValue {
  return value && typeof value === "object" && !Array.isArray(value) ? value as RecordValue : {};
}

export function evaluationSuiteTool() {
  const suitePath = getRuntimeDataPath("evaluation-suite.json");
  const templateRoot = getRuntimeDataPath("evaluation-task-templates");
  const suite = asRecord(JSON.parse(readFileSync(suitePath, "utf8")));
  const tasks = Array.isArray(suite.tasks) ? suite.tasks.map(asRecord) : [];
  return {
    schema: "codex-praetor-evaluation-suite-view/v1",
    suite_path: suitePath,
    suite_id: String(suite.suite_id ?? ""),
    tasks: tasks.map((task) => ({
      task_id: String(task.task_id ?? ""),
      task_family: String(task.task_family ?? ""),
      mode: String(task.mode ?? ""),
      task_kind: String(task.task_kind ?? ""),
      provider_candidates: Array.isArray(task.provider_candidates) ? task.provider_candidates.map(String) : [],
      allowed_paths: Array.isArray(task.allowed_paths) ? task.allowed_paths.map(String) : [],
      forbidden_paths: Array.isArray(task.forbidden_paths) ? task.forbidden_paths.map(String) : [],
      acceptance: String(task.acceptance ?? ""),
      required_checks: Array.isArray(task.required_checks) ? task.required_checks.map(String) : [],
      budget: asRecord(task.budget)
    })),
    policy: {
      prepared_plan_is_not_evidence: true,
      workers_must_run_in_disposable_worktrees: true,
      one_task_at_a_time: true,
      default_routing_changed: false
    }
  };
}

/** Prepare the bundled evaluation suite without dispatching a worker. */
export async function prepareEvaluationTool(input: { repo: string; plan_id?: string }) {
  const repo = resolveExistingRepo(input.repo);
  const suitePath = getRuntimeDataPath("evaluation-suite.json");
  const templateRoot = getRuntimeDataPath("evaluation-task-templates");
  const initializerPath = getEvaluationInitializerPath();
  const planRoot = getPlanRoot(repo);
  const planScript = getPlanScriptPath();
  const planId = input.plan_id?.trim() || "";
  const prepared = await runPowerShell(
    ["-NoProfile", "-ExecutionPolicy", "Bypass", "-File", initializerPath, "-ProjectRoot", repo, "-SuitePath", suitePath, "-TemplateRoot", templateRoot, "-PlanRoot", planRoot, "-PlanScript", planScript, "-PlanId", planId, "-Action", "Prepare", "-Apply"],
    { timeoutMs: 30_000 }
  );
  if (prepared.exitCode !== 0) {
    return { ok: false, exit_code: prepared.exitCode, stderr: prepared.stderr, stdout: prepared.stdout };
  }
  const summary = asRecord(JSON.parse(prepared.stdout.replace(/^\uFEFF/, "")));
  const tasks = Array.isArray(summary.tasks) ? summary.tasks.map(asRecord) : [];
  const taskIds = tasks.map((task) => String(task.task_id ?? "")).filter(Boolean);
  if (!String(summary.plan_path ?? "") || taskIds.length === 0) {
    throw new Error("Evaluation initializer returned an incomplete prepared plan.");
  }
  return { ok: true, repo, suite_path: suitePath, plan_id: String(summary.plan_id ?? ""), plan_path: String(summary.plan_path), task_ids: taskIds, policy: "Preparation writes only a project-local plan. It does not dispatch a worker or count as capability evidence." };
}

/** Independently verify material and checks; this never records final Codex acceptance. */
export async function verifyEvaluationTaskTool(input: { repo: string; plan_id: string; task_id: string; worktree: string }) {
  const repo = resolveExistingRepo(input.repo);
  const planPath = `${getPlanRoot(repo)}\\${input.plan_id}\\plan.json`;
  const plan = asRecord(JSON.parse(readFileSync(planPath, "utf8")));
  const tasks = Array.isArray(plan.tasks) ? plan.tasks.map(asRecord) : [];
  const task = tasks.find((candidate) => String(candidate.task_id ?? "") === input.task_id.trim());
  if (!task || String(task.task_kind ?? "") !== "code_change") {
    return { ok: false, repo, plan_id: input.plan_id, task_id: input.task_id, message: "Only a prepared code-change task can use material verification." };
  }
  const material = asRecord(task.task_material);
  const completion = asRecord(task.completion_definition);
  const checks = Array.isArray(completion.required_checks) ? completion.required_checks.map(String) : [];
  if (Object.keys(material).length === 0 || checks.length === 0) {
    return { ok: false, repo, plan_id: input.plan_id, task_id: input.task_id, message: "Prepared task lacks immutable material or required checks." };
  }
  const result = await runPowerShell([
    "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", getEvaluationVerifierPath(),
    "-Worktree", input.worktree,
    "-TaskMaterialJson", JSON.stringify(material),
    "-RequiredChecksJson", JSON.stringify(checks)
  ], { timeoutMs: 120_000 });
  if (result.exitCode !== 0) {
    return { ok: false, repo, plan_id: input.plan_id, task_id: input.task_id, exit_code: result.exitCode, stdout: result.stdout, stderr: result.stderr };
  }
  const verification = asRecord(JSON.parse(result.stdout.replace(/^\uFEFF/, "")));
  return { ok: true, repo, plan_id: input.plan_id, task_id: input.task_id, verification, policy: "This is independent evidence only. Codex must still record the final accepted or rejected verdict." };
}
