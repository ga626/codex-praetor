import { existsSync, readdirSync, readFileSync, statSync } from "node:fs";
import path from "node:path";
import {
  getInvokeScriptPath,
  getJobRoot,
  getLockRoot,
  getPlanRoot,
  getPlanScriptPath,
  getProjectArtifactRoot,
  resolveExistingRepo
} from "./paths.js";
import { parseKeyValueOutput } from "./parse-key-value.js";
import { runPowerShell } from "./powershell.js";
import { routeIntent } from "./route-intent.js";
import type { JobSummary, LaneSummary } from "./types.js";

export function routeIntentTool(input: {
  request: string;
  repo?: string;
  allow_native_codex_subagents?: boolean;
}) {
  const decision = routeIntent(input.request, input.allow_native_codex_subagents ?? false);
  return {
    ...decision,
    repo: input.repo ? path.resolve(input.repo) : ""
  };
}

export async function dispatchDryRunTool(input: {
  repo: string;
  task: string;
  provider: "qoder" | "codebuddy" | "mimo";
  tier?: string;
  mode?: "readonly" | "edit";
  run_mode?: "blocking" | "background";
}) {
  const repo = resolveExistingRepo(input.repo);
  const args = [
    "-NoProfile",
    "-ExecutionPolicy",
    "Bypass",
    "-File",
    getInvokeScriptPath(),
    "-Provider",
    input.provider,
    "-Repo",
    repo,
    "-Task",
    input.task,
    "-Mode",
    input.mode ?? "readonly",
    "-RunMode",
    input.run_mode ?? "blocking",
    "-DryRun",
    "-NoNotify"
  ];

  if (input.tier?.trim()) {
    args.push("-Tier", input.tier.trim());
  }

  const result = await runPowerShell(args, { timeoutMs: 120_000 });
  const fields = parseKeyValueOutput(result.stdout);
  return {
    ok: result.exitCode === 0,
    exit_code: result.exitCode,
    repo,
    task: input.task,
    fields,
    provider: fields.provider ?? input.provider,
    tier: fields.tier ?? input.tier ?? "",
    model: fields.model ?? "",
    model_policy: fields.model_policy ?? "",
    mode: input.mode ?? "readonly",
    run_mode: fields.run_mode ?? input.run_mode ?? "blocking",
    project_artifact_root: fields.project_artifact_root ?? "",
    job_root: fields.job_root ?? "",
    lock_root: fields.lock_root ?? "",
    plan_root: fields.plan_root ?? "",
    scratch_root: fields.scratch_root ?? "",
    command: fields.command ?? "",
    stdout: result.stdout,
    stderr: result.stderr
  };
}

export async function planTool(input: {
  repo: string;
  title: string;
  tasks: string[];
  mode?: "readonly" | "edit";
  plan_id?: string;
}) {
  const repo = resolveExistingRepo(input.repo);
  const planId = input.plan_id?.trim() || `plan-${new Date().toISOString().replace(/[:.]/g, "-")}`;
  const planRoot = getPlanRoot(repo);
  const mode = input.mode ?? "readonly";

  const initResult = await runPowerShell(
    [
      "-NoProfile",
      "-ExecutionPolicy",
      "Bypass",
      "-File",
      getPlanScriptPath(),
      "-Action",
      "Init",
      "-PlanId",
      planId,
      "-PlanRoot",
      planRoot,
      "-Title",
      input.title,
      "-Repo",
      repo,
      "-OutputJson"
    ],
    { timeoutMs: 30_000 }
  );

  if (initResult.exitCode !== 0) {
    return {
      ok: false,
      exit_code: initResult.exitCode,
      stderr: initResult.stderr,
      stdout: initResult.stdout
    };
  }

  for (const [index, task] of input.tasks.entries()) {
    const taskId = `task-${String(index + 1).padStart(2, "0")}`;
    const upsertResult = await runPowerShell(
      [
        "-NoProfile",
        "-ExecutionPolicy",
        "Bypass",
        "-File",
        getPlanScriptPath(),
        "-Action",
        "UpsertTask",
        "-PlanId",
        planId,
        "-PlanRoot",
        planRoot,
        "-TaskId",
        taskId,
        "-TaskTitle",
        task,
        "-Status",
        "pending",
        "-Mode",
        mode,
        "-OutputJson"
      ],
      { timeoutMs: 30_000 }
    );

    if (upsertResult.exitCode !== 0) {
      return {
        ok: false,
        exit_code: upsertResult.exitCode,
        failed_task_id: taskId,
        stderr: upsertResult.stderr,
        stdout: upsertResult.stdout
      };
    }
  }

  const getResult = await runPowerShell(
    [
      "-NoProfile",
      "-ExecutionPolicy",
      "Bypass",
      "-File",
      getPlanScriptPath(),
      "-Action",
      "Get",
      "-PlanId",
      planId,
      "-PlanRoot",
      planRoot,
      "-OutputJson"
    ],
    { timeoutMs: 30_000 }
  );

  const planPath = path.join(planRoot, planId, "plan.json");
  return {
    ok: getResult.exitCode === 0,
    exit_code: getResult.exitCode,
    repo,
    plan_id: planId,
    plan_root: planRoot,
    plan_path: planPath,
    task_ids: input.tasks.map((_, index) => `task-${String(index + 1).padStart(2, "0")}`),
    plan: getResult.stdout.trim() ? JSON.parse(getResult.stdout) : null,
    stderr: getResult.stderr
  };
}

function readJsonFile(filePath: string): Record<string, unknown> {
  const text = readFileSync(filePath, "utf8").replace(/^\uFEFF/, "");
  return JSON.parse(text) as Record<string, unknown>;
}

function summarizeJob(jobDir: string): JobSummary {
  const metaPath = path.join(jobDir, "job.json");
  const completionPath = path.join(jobDir, "completion.json");
  const meta = existsSync(metaPath) ? readJsonFile(metaPath) : {};
  const completion = existsSync(completionPath) ? readJsonFile(completionPath) : {};
  const stats = statSync(jobDir);

  return {
    job_id: String(meta.job_id ?? path.basename(jobDir)),
    provider: String(meta.provider ?? completion.provider ?? ""),
    tier: String(meta.tier ?? completion.tier ?? ""),
    model: String(meta.model ?? completion.model ?? ""),
    mode: String(meta.mode ?? completion.mode ?? ""),
    run_mode: String(meta.run_mode ?? ""),
    status: String(completion.status ?? meta.status ?? "unknown"),
    created_at: String(meta.created_at ?? stats.birthtime.toISOString()),
    updated_at: String(meta.exited_at ?? completion.exited_at ?? stats.mtime.toISOString()),
    path: jobDir,
    completion_path: existsSync(completionPath) ? completionPath : undefined
  };
}

function isActiveStatus(status: string): boolean {
  return !["completed", "failed", "blocked", "skipped", "cancelled"].includes(status);
}

function isProcessAlive(pid: number): boolean {
  if (!Number.isFinite(pid) || pid <= 0) {
    return false;
  }
  try {
    process.kill(pid, 0);
    return true;
  } catch {
    return false;
  }
}

function summarizeJobLane(repo: string, jobDir: string): LaneSummary {
  const summary = summarizeJob(jobDir);
  const metaPath = path.join(jobDir, "job.json");
  const meta = existsSync(metaPath) ? readJsonFile(metaPath) : {};
  return {
    lane_id: `job:${summary.job_id}`,
    kind: "job",
    repo,
    mode: summary.mode,
    provider: summary.provider,
    tier: summary.tier,
    model: summary.model,
    status: summary.status,
    title: String(meta.task_title ?? meta.task ?? ""),
    job_id: summary.job_id,
    plan_id: String(meta.plan_id ?? ""),
    task_id: String(meta.task_id ?? ""),
    owner_thread_id: String(meta.notify_thread_id ?? ""),
    path: jobDir,
    created_at: summary.created_at,
    updated_at: summary.updated_at,
    active: isActiveStatus(summary.status)
  };
}

function summarizePlanTaskLane(repo: string, planDir: string, plan: Record<string, unknown>, task: Record<string, unknown>): LaneSummary {
  const stats = statSync(planDir);
  const planId = String(plan.plan_id ?? path.basename(planDir));
  const taskId = String(task.task_id ?? "");
  const status = String(task.status ?? "unknown");
  return {
    lane_id: `plan:${planId}:${taskId}`,
    kind: "plan_task",
    repo: String(plan.repo ?? repo),
    mode: String(task.mode ?? ""),
    provider: String(task.provider ?? ""),
    tier: String(task.tier ?? ""),
    model: String(task.model ?? ""),
    status,
    title: String(task.title ?? ""),
    job_id: String(task.job_id ?? ""),
    plan_id: planId,
    task_id: taskId,
    owner_thread_id: "",
    path: path.join(planDir, "plan.json"),
    created_at: String(task.created_at ?? plan.created_at ?? stats.birthtime.toISOString()),
    updated_at: String(task.updated_at ?? plan.updated_at ?? stats.mtime.toISOString()),
    active: isActiveStatus(status)
  };
}

function summarizeLockLane(repo: string, lockPath: string): LaneSummary {
  const stats = statSync(lockPath);
  const lock = readJsonFile(lockPath);
  const pid = Number(lock.holder_pid ?? lock.pid ?? 0);
  const active = isProcessAlive(pid);
  return {
    lane_id: `lock:${path.basename(lockPath, path.extname(lockPath))}`,
    kind: "lock",
    repo: String(lock.repo ?? repo),
    mode: "edit",
    provider: String(lock.provider ?? ""),
    tier: String(lock.tier ?? ""),
    model: "",
    status: active ? "active" : "stale",
    title: String(lock.note ?? "Repo edit lock"),
    job_id: String(lock.job_id ?? ""),
    plan_id: "",
    task_id: "",
    owner_thread_id: "",
    path: lockPath,
    created_at: String(lock.created_at ?? stats.birthtime.toISOString()),
    updated_at: String(lock.updated_at ?? stats.mtime.toISOString()),
    active
  };
}

function collectLanes(repo: string): LaneSummary[] {
  const lanes: LaneSummary[] = [];
  const jobRoot = getJobRoot(repo);
  if (existsSync(jobRoot)) {
    for (const entry of readdirSync(jobRoot, { withFileTypes: true })) {
      if (entry.isDirectory()) {
        lanes.push(summarizeJobLane(repo, path.join(jobRoot, entry.name)));
      }
    }
  }

  const planRoot = getPlanRoot(repo);
  if (existsSync(planRoot)) {
    for (const entry of readdirSync(planRoot, { withFileTypes: true })) {
      if (!entry.isDirectory()) {
        continue;
      }
      const planDir = path.join(planRoot, entry.name);
      const planPath = path.join(planDir, "plan.json");
      if (!existsSync(planPath)) {
        continue;
      }
      const plan = readJsonFile(planPath);
      const tasks = Array.isArray(plan.tasks) ? (plan.tasks as Record<string, unknown>[]) : [];
      for (const task of tasks) {
        lanes.push(summarizePlanTaskLane(repo, planDir, plan, task));
      }
    }
  }

  const lockRoot = getLockRoot(repo);
  if (existsSync(lockRoot)) {
    for (const entry of readdirSync(lockRoot, { withFileTypes: true })) {
      if (entry.isFile() && entry.name.endsWith(".json")) {
        lanes.push(summarizeLockLane(repo, path.join(lockRoot, entry.name)));
      }
    }
  }

  return lanes.sort((a, b) => b.updated_at.localeCompare(a.updated_at));
}

function filterLanes(lanes: LaneSummary[], status: "active" | "completed" | "failed" | "blocked" | "all"): LaneSummary[] {
  if (status === "all") {
    return lanes;
  }
  if (status === "active") {
    return lanes.filter((lane) => lane.active);
  }
  return lanes.filter((lane) => lane.status === status);
}

export function listJobsTool(input: {
  repo: string;
  status?: "active" | "completed" | "failed" | "all";
  limit?: number;
}) {
  const repo = resolveExistingRepo(input.repo);
  const jobRoot = getJobRoot(repo);
  const statusFilter = input.status ?? "all";
  const limit = Math.max(1, Math.min(input.limit ?? 20, 100));

  if (!existsSync(jobRoot)) {
    return {
      repo,
      project_artifact_root: getProjectArtifactRoot(repo),
      job_root: jobRoot,
      jobs: [],
      count: 0
    };
  }

  const jobs = readdirSync(jobRoot, { withFileTypes: true })
    .filter((entry) => entry.isDirectory())
    .map((entry) => summarizeJob(path.join(jobRoot, entry.name)))
    .filter((job) => {
      if (statusFilter === "all") {
        return true;
      }
      if (statusFilter === "active") {
        return !["completed", "failed", "blocked"].includes(job.status);
      }
      return job.status === statusFilter;
    })
    .sort((a, b) => b.updated_at.localeCompare(a.updated_at))
    .slice(0, limit);

  return {
    repo,
    project_artifact_root: getProjectArtifactRoot(repo),
    job_root: jobRoot,
    jobs,
    count: jobs.length
  };
}

export function listLanesTool(input: {
  repo: string;
  status?: "active" | "completed" | "failed" | "blocked" | "all";
  limit?: number;
}) {
  const repo = resolveExistingRepo(input.repo);
  const status = input.status ?? "active";
  const limit = Math.max(1, Math.min(input.limit ?? 20, 100));
  const lanes = filterLanes(collectLanes(repo), status).slice(0, limit);
  return {
    repo,
    project_artifact_root: getProjectArtifactRoot(repo),
    lane_roots: {
      jobs: getJobRoot(repo),
      plans: getPlanRoot(repo),
      locks: getLockRoot(repo)
    },
    status,
    lanes,
    count: lanes.length
  };
}

export function getLaneTool(input: {
  repo: string;
  lane_id: string;
}) {
  const repo = resolveExistingRepo(input.repo);
  const laneId = input.lane_id.trim();
  const lane = collectLanes(repo).find((candidate) => candidate.lane_id === laneId);
  if (!lane) {
    return {
      found: false,
      repo,
      lane_id: laneId,
      message: "Lane not found."
    };
  }

  return {
    found: true,
    repo,
    lane
  };
}

export function detectConflictsTool(input: {
  repo: string;
  mode?: "readonly" | "edit";
  lane_id?: string;
  file_scope?: string[];
}) {
  const repo = resolveExistingRepo(input.repo);
  const mode = input.mode ?? "readonly";
  const laneId = input.lane_id?.trim() ?? "";
  const fileScope = input.file_scope ?? [];
  const activeLanes = filterLanes(collectLanes(repo), "active").filter((lane) => lane.lane_id !== laneId);

  const conflicts =
    mode === "edit"
      ? activeLanes.filter((lane) => lane.mode === "edit" || lane.kind === "lock")
      : [];

  return {
    ok: conflicts.length === 0,
    repo,
    mode,
    lane_id: laneId,
    file_scope: fileScope,
    conflict_count: conflicts.length,
    conflicts,
    policy:
      mode === "readonly"
        ? "Readonly lanes can coexist in the same repo."
        : "Edit lanes must use isolated worktrees and should not overlap file scope. Current v0 conflict detection treats an active repo edit lock as a conflict.",
    scope_note:
      fileScope.length > 0
        ? "File-scope comparison is accepted but not yet persisted in lane metadata; repo edit locks are authoritative in v0."
        : "No file scope was provided; conflict detection uses repo-level active edit lanes and locks."
  };
}

export function statusTool(input: {
  repo: string;
  job_id?: string;
  plan_id?: string;
}) {
  const repo = resolveExistingRepo(input.repo);
  if (input.job_id?.trim()) {
    const jobDir = path.join(getJobRoot(repo), input.job_id.trim());
    if (!existsSync(jobDir)) {
      return {
        found: false,
        kind: "job",
        repo,
        job_id: input.job_id,
        path: jobDir,
        message: "Job not found."
      };
    }
    const summary = summarizeJob(jobDir);
    const completionPath = path.join(jobDir, "completion.json");
    return {
      found: true,
      kind: "job",
      repo,
      summary,
      completion: existsSync(completionPath) ? readJsonFile(completionPath) : null
    };
  }

  if (input.plan_id?.trim()) {
    const planDir = path.join(getPlanRoot(repo), input.plan_id.trim());
    const planPath = path.join(planDir, "plan.json");
    if (!existsSync(planPath)) {
      return {
        found: false,
        kind: "plan",
        repo,
        plan_id: input.plan_id,
        path: planPath,
        message: "Plan not found."
      };
    }
    return {
      found: true,
      kind: "plan",
      repo,
      path: planPath,
      plan: readJsonFile(planPath)
    };
  }

  return {
    found: false,
    kind: "none",
    repo,
    message: "Provide job_id or plan_id."
  };
}
