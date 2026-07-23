import { readFileSync } from "node:fs";
import { getPlanRoot, getPlanScriptPath, getRuntimeDataPath, resolveExistingRepo } from "./paths.js";
import { runPowerShell } from "./powershell.js";

type RecordValue = Record<string, unknown>;

function asRecord(value: unknown): RecordValue {
  return value && typeof value === "object" && !Array.isArray(value) ? value as RecordValue : {};
}

export function evaluationSuiteTool() {
  const suitePath = getRuntimeDataPath("evaluation-suite.json");
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

function getEvaluationTasks() {
  const suitePath = getRuntimeDataPath("evaluation-suite.json");
  const suite = asRecord(JSON.parse(readFileSync(suitePath, "utf8")));
  if (String(suite.schema ?? "") !== "codex-praetor-evaluation-suite/v1") {
    throw new Error(`Evaluation suite schema is invalid: ${suitePath}`);
  }
  const tasks = Array.isArray(suite.tasks) ? suite.tasks.map(asRecord) : [];
  if (tasks.length < 4) {
    throw new Error("Evaluation suite must contain at least four tasks.");
  }
  return { suitePath, suite, tasks };
}

function requiredString(task: RecordValue, name: string): string {
  const value = String(task[name] ?? "").trim();
  if (!value) {
    throw new Error(`Evaluation task is missing ${name}.`);
  }
  return value;
}

function requiredStrings(task: RecordValue, name: string): string[] {
  const value = Array.isArray(task[name]) ? task[name].map(String).filter(Boolean) : [];
  if (value.length === 0) {
    throw new Error(`Evaluation task is missing ${name}.`);
  }
  return value;
}

/** Prepare the bundled evaluation suite without dispatching a worker. */
export async function prepareEvaluationTool(input: { repo: string; plan_id?: string }) {
  const repo = resolveExistingRepo(input.repo);
  const { suitePath, suite, tasks } = getEvaluationTasks();
  const planId = input.plan_id?.trim() || `evaluation-${String(suite.suite_id ?? "suite")}`;
  const planRoot = getPlanRoot(repo);
  const planScript = getPlanScriptPath();
  const taskIds = new Set<string>();

  const init = await runPowerShell(
    ["-NoProfile", "-ExecutionPolicy", "Bypass", "-File", planScript, "-Action", "Init", "-PlanId", planId, "-PlanRoot", planRoot, "-Title", `Evaluation ${String(suite.suite_id ?? "")}`, "-Repo", repo, "-OutputJson"],
    { timeoutMs: 30_000 }
  );
  if (init.exitCode !== 0) {
    return { ok: false, exit_code: init.exitCode, stderr: init.stderr, stdout: init.stdout };
  }

  for (const task of tasks) {
    const taskId = requiredString(task, "task_id");
    if (taskIds.has(taskId)) {
      throw new Error(`Evaluation task ids must be unique: ${taskId}`);
    }
    taskIds.add(taskId);
    const budget = asRecord(task.budget);
    const maxTurns = Number(budget.max_turns ?? 0);
    const maxWallSeconds = Number(budget.max_wall_seconds ?? 0);
    if (!Number.isInteger(maxTurns) || maxTurns <= 0 || !Number.isInteger(maxWallSeconds) || maxWallSeconds < 60) {
      throw new Error(`Evaluation task ${taskId} has an invalid budget.`);
    }
    const upsert = await runPowerShell(
      [
        "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", planScript, "-Action", "UpsertTask",
        "-PlanId", planId, "-PlanRoot", planRoot, "-TaskId", taskId,
        "-TaskTitle", requiredString(task, "goal"), "-TaskFamily", requiredString(task, "task_family"),
        "-TaskKind", requiredString(task, "task_kind"), "-Status", "pending", "-Mode", requiredString(task, "mode"),
        "-AllowedPath", ...requiredStrings(task, "allowed_paths"), "-ForbiddenPath", ...requiredStrings(task, "forbidden_paths"),
        "-RequiredCheck", ...requiredStrings(task, "required_checks"), "-BudgetJson", JSON.stringify(budget),
        "-FailureInjection", requiredString(task, "failure_injection"), "-Sensitivity", String(task.sensitivity ?? ""),
        "-Acceptance", requiredString(task, "acceptance"), "-Summary", "Prepared from the bundled evaluation suite.", "-OutputJson"
      ],
      { timeoutMs: 30_000 }
    );
    if (upsert.exitCode !== 0) {
      return { ok: false, exit_code: upsert.exitCode, failed_task_id: taskId, stderr: upsert.stderr, stdout: upsert.stdout };
    }
  }

  return {
    ok: true,
    repo,
    suite_path: suitePath,
    plan_id: planId,
    plan_path: `${planRoot}\\${planId}\\plan.json`,
    task_ids: [...taskIds],
    policy: "Preparation writes only a project-local plan. It does not dispatch a worker or count as capability evidence."
  };
}
