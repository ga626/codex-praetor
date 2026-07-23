import { readFileSync } from "node:fs";
import { getRuntimeDataPath } from "./paths.js";

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
