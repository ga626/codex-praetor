import { createHash } from "node:crypto";
import { existsSync, readdirSync, readFileSync, statSync } from "node:fs";
import path from "node:path";
import {
  getInvokeScriptPath,
  getCancelScriptPath,
  getHealthScriptPath,
  getJobRoot,
  getLockRoot,
  getMcpRoot,
  getPlanRoot,
  getPlanScriptPath,
  getProjectArtifactRoot,
  getProjectRoot,
  getRuntimeContractPath,
  resolveExistingRepo
} from "./paths.js";
import { parseKeyValueOutput } from "./parse-key-value.js";
import { runPowerShell } from "./powershell.js";
import { routeIntent } from "./route-intent.js";
import { capabilityProfilesTool as buildCapabilityProfiles } from "./capability-profiles.js";
import { evaluationSuiteTool as buildEvaluationSuite } from "./evaluation-suite.js";
import { explainableRouteTool as buildExplainableRoute } from "./explainable-routing.js";
import { providerOperationsTool as buildProviderOperations } from "./provider-operations.js";
import type { JobSummary, LaneSummary, ResearchContract } from "./types.js";

function assertResearchContract(input: {
  task_kind?: "local_audit" | "code_change" | "external_research_support";
  mode?: "readonly" | "edit";
  research_contract?: ResearchContract;
}) {
  if (input.task_kind !== "external_research_support") {
    return;
  }
  if (input.mode === "edit") {
    throw new Error("external_research_support requires readonly mode.");
  }
  const contract = input.research_contract;
  if (!contract || contract.research_authority !== "codex_kr_primary" || contract.evidence_acceptance !== "supervisor_verified") {
    throw new Error("external_research_support requires a Codex/KR primary research contract with supervisor-verified evidence acceptance.");
  }
  if (contract.claim_scope.length === 0 || contract.source_scope.length === 0) {
    throw new Error("external_research_support requires non-empty claim_scope and source_scope.");
  }
}

function appendResearchContract(task: string, contract?: ResearchContract): string {
  if (!contract) {
    return task;
  }
  return `${task}\n\nResearch authority: Codex/KR is primary. You are a bounded supporting worker.\nMode: ${contract.worker_research_mode}\nClaims: ${contract.claim_scope.join("; ")}\nSource scope: ${contract.source_scope.join("; ")}\nEvidence acceptance: supervisor verified only.\nOutput every candidate with URL, retrieval time, excerpt, claim, and uncertainty. Do not present final conclusions.`;
}

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

export function runtimeInfoTool() {
  const contractPath = getRuntimeContractPath();
  const contract = existsSync(contractPath) ? readJsonFile(contractPath) : null;
  const startedAt = new Date(Date.now() - process.uptime() * 1_000).toISOString();
  const runtimeContractSha256 = contract
    ? createHash("sha256").update(readFileSync(contractPath)).digest("hex")
    : "";
  return {
    display: {
      阶段: "运行时合同",
      状态: contract ? "已加载" : "缺失",
      下一步: contract ? "可继续检查安装态和 provider readiness。" : "修复发布包后重试。"
    },
    runtime_contract: contract,
    contract_path: contractPath,
    runtime_identity: {
      schema: "codex-praetor-runtime-identity/v1",
      runtime_contract_sha256: runtimeContractSha256,
      project_root: getProjectRoot(),
      mcp_root: getMcpRoot(),
      process_id: process.pid,
      process_started_at: startedAt
    }
  };
}

export function capabilityProfilesTool(input: { repo: string; include_unclassified?: boolean }) {
  return buildCapabilityProfiles(input);
}

export function evaluationSuiteTool() {
  return buildEvaluationSuite();
}

export function explainableRouteTool(input: Parameters<typeof buildExplainableRoute>[0]) {
  return buildExplainableRoute(input);
}

export function providerOperationsTool(input: Parameters<typeof buildProviderOperations>[0]) {
  return buildProviderOperations(input);
}

export async function healthTool(input: { repo: string }) {
  const repo = resolveExistingRepo(input.repo);
  const result = await runPowerShell(
    ["-NoProfile", "-ExecutionPolicy", "Bypass", "-File", getHealthScriptPath(), "-Repo", repo, "-Json"],
    { timeoutMs: 30_000 }
  );
  const health = result.stdout.trim() ? JSON.parse(result.stdout) : null;
  return {
    display: {
      阶段: "健康检测",
      状态: health?.status ?? "unknown",
      诊断状态: health?.diagnostic_status ?? health?.status ?? "unknown",
      下一步:
        health?.status === "ready"
          ? health?.diagnostic_status === "degraded"
            ? "当前运行代际和 readiness 已可派工；历史收据或库存诊断可单独维护，不要误当成派工阻断。"
            : "可以检查匹配 task contract 的 provider readiness。"
          : "先处理 authoritative blocked 检查项。"
    },
    health,
    exit_code: result.exitCode,
    stderr: result.stderr
  };
}

export function jobTimelineTool(input: { repo: string; job_id: string }) {
  const repo = resolveExistingRepo(input.repo);
  const jobDir = path.join(getJobRoot(repo), input.job_id);
  const metaPath = path.join(jobDir, "job.json");
  const completionPath = path.join(jobDir, "completion.json");
  if (!existsSync(metaPath)) {
    return { found: false, repo, job_id: input.job_id };
  }
  const meta = readJsonFile(metaPath);
  const completion = existsSync(completionPath) ? readJsonFile(completionPath) : null;
  return {
    found: true,
    display: {
      阶段: String(meta.status ?? "unknown"),
      执行者: String(meta.provider ?? ""),
      任务类别: String(meta.task_kind ?? ""),
      下一步: completion ? "由 Codex 读取结果并记录验收结论。" : "等待 worker 到达终态。"
    },
    job_id: input.job_id,
    contract_hash: String(meta.contract_hash ?? ""),
    events: Array.isArray(meta.events) ? meta.events : [],
    meta,
    completion
  };
}

export async function cancelJobTool(input: { repo: string; job_id: string }) {
  const repo = resolveExistingRepo(input.repo);
  const jobDir = path.join(getJobRoot(repo), input.job_id);
  const result = await runPowerShell(
    ["-NoProfile", "-ExecutionPolicy", "Bypass", "-File", getCancelScriptPath(), "-JobDir", jobDir],
    { timeoutMs: 30_000 }
  );
  return {
    display: {
      阶段: "取消任务",
      状态: result.exitCode === 0 ? "cancelled" : "failed",
      下一步: result.exitCode === 0 ? "读取 completion 并检查 worktree 是否可清理。" : "读取 job metadata 后人工处理。"
    },
    repo,
    job_id: input.job_id,
    ok: result.exitCode === 0,
    exit_code: result.exitCode,
    stdout: result.stdout,
    stderr: result.stderr
  };
}

export async function dispatchDryRunTool(input: {
  repo: string;
  task: string;
  provider: "auto" | "qoder" | "codebuddy" | "mimo";
  tier?: string;
  mode?: "readonly" | "edit";
  run_mode?: "blocking" | "background";
  task_kind?: "local_audit" | "code_change" | "external_research_support";
  research_contract?: ResearchContract;
}) {
  const repo = resolveExistingRepo(input.repo);
  assertResearchContract(input);
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
    appendResearchContract(input.task, input.research_contract),
    "-Mode",
    input.mode ?? "readonly",
    "-RunMode",
    input.run_mode ?? "blocking",
    "-DryRun",
    "-NoNotify"
  ];

  if (input.task_kind) {
    args.push("-TaskKind", input.task_kind === "external_research_support" ? "external_research" : input.task_kind);
  }
  if (input.task_kind === "external_research_support") {
    args.push("-AllowWorkerNetwork");
    args.push("-ResearchContractJson", JSON.stringify(input.research_contract));
  }

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

function appendOptionalStringArg(args: string[], name: string, value?: string) {
  if (value?.trim()) {
    args.push(name, value.trim());
  }
}

function appendOptionalNumberArg(args: string[], name: string, value?: number) {
  if (Number.isFinite(value) && (value ?? 0) > 0) {
    args.push(name, String(value));
  }
}

function buildDispatchArgs(input: {
  repo: string;
  task: string;
  provider: "auto" | "qoder" | "codebuddy" | "mimo";
  tier?: string;
  mode?: "readonly" | "edit";
  run_mode?: "blocking" | "background";
  task_kind?: "local_audit" | "code_change" | "external_research_support";
  research_contract?: ResearchContract;
  dry_run?: boolean;
  plan_id?: string;
  task_id?: string;
  depends_on?: string;
  acceptance?: string;
  worktree_name?: string;
  max_turns?: number;
  no_notify?: boolean;
}) {
  const args = [
    "-NoProfile",
    "-ExecutionPolicy",
    "Bypass",
    "-File",
    getInvokeScriptPath(),
    "-Provider",
    input.provider,
    "-Repo",
    input.repo,
    "-Task",
    input.task,
    "-Mode",
    input.mode ?? "readonly",
    "-RunMode",
    input.run_mode ?? "background"
  ];

  if (input.task_kind) {
    args.push("-TaskKind", input.task_kind === "external_research_support" ? "external_research" : input.task_kind);
  }
  if (input.task_kind === "external_research_support") {
    args.push("-AllowWorkerNetwork");
    args.push("-ResearchContractJson", JSON.stringify(input.research_contract));
  }

  appendOptionalStringArg(args, "-Tier", input.tier);
  appendOptionalStringArg(args, "-PlanId", input.plan_id);
  appendOptionalStringArg(args, "-TaskId", input.task_id);
  appendOptionalStringArg(args, "-DependsOn", input.depends_on);
  appendOptionalStringArg(args, "-Acceptance", input.acceptance);
  appendOptionalStringArg(args, "-WorktreeName", input.worktree_name);
  appendOptionalNumberArg(args, "-MaxTurns", input.max_turns);

  if (input.dry_run) {
    args.push("-DryRun");
  }
  if (input.no_notify ?? true) {
    args.push("-NoNotify");
  }
  return args;
}

function readTextTail(filePath: string, maxChars = 12_000): string {
  if (!existsSync(filePath)) {
    return "";
  }
  const text = readFileSync(filePath, "utf8").replace(/^\uFEFF/, "");
  if (text.length <= maxChars) {
    return text;
  }
  return text.slice(text.length - maxChars);
}

export function classifyWorkerOutcome(input: {
  meta: Record<string, unknown>;
  completion: Record<string, unknown> | null;
  stdout_tail: string;
  stderr_tail: string;
}) {
  const completion = input.completion;
  const metaStatus = String(input.meta.status ?? "");
  const status = String(completion?.status ?? metaStatus ?? "");
  const exitCode = completion?.exit_code ?? input.meta.exit_code;
  const failureClass = String(completion?.failure_class ?? input.meta.failure_class ?? "");
  const artifactState = String(completion?.artifact_state ?? input.meta.artifact_state ?? "");
  const combined = `${input.stdout_tail}\n${input.stderr_tail}`.toLowerCase();

  if (!completion) {
    if (["starting", "running"].includes(metaStatus)) {
      return {
        class: "worker_running",
        explanation: "worker 还在运行，尚未产生 completion.json。",
        next_action: "等待 watcher 完成，稍后再读取结果。"
      };
    }
    return {
      class: "missing_completion",
      explanation: "job 元数据存在，但没有 completion.json。",
      next_action: "检查 watcher 日志；如果 watcher 已退出但没有 completion，需要按 watcher 失败处理。"
    };
  }

  if (status === "watcher_failed") {
    return {
      class: "watcher_failed",
      explanation: "本地 watcher 没能完成 worker 等待或结果记录。",
      next_action: "先修复本地 watcher/进程启动问题，再重派任务。"
    };
  }
  if (failureClass === "provider_risk_control") {
    return {
      class: "provider_risk_control",
      explanation: "MiMo provider 已因风控拒绝本次请求；这不是成功结果，也不是本地 worktree 问题。",
      next_action: "停止重试同一请求，等待 provider 解除限制或改用已通过 canary 的 provider。"
    };
  }
  if (failureClass === "provider_rejected" || failureClass === "provider_output_unparseable") {
    return {
      class: failureClass,
      explanation: "provider 已拒绝请求或未提供可解析的完成事件，不能作为 worker 报告或成功证据。",
      next_action: "保留日志作为诊断证据；检查 provider 状态后再决定改派或重试。"
    };
  }
  if (failureClass === "max_turns_exceeded") {
    return {
      class: "worker_max_turns_exceeded",
      explanation: artifactState === "partial_worktree_diff" ? "worker 超轮数且留下了半成品改动，不能直接验收或合并。" : "worker 超轮数且没有完成任务，不能把进程退出当作有效结果。",
      next_action: "保留 worktree 供 Codex 检查；缩小任务、提高 MaxTurns、换 provider，或由 Codex 接管并记录原因。"
    };
  }
  if (combined.includes("max turns") || combined.includes("maximum turns") || combined.includes("turns exceeded")) {
    return {
      class: "worker_max_turns_exceeded",
      explanation: "worker 在轮数上限内没有完成任务，不能把它当作有效结果。",
      next_action: "缩小任务、提高 MaxTurns、换 provider，或由 Codex 接管并记录原因。"
    };
  }
  if (combined.includes("cli not found") || combined.includes("not recognized") || combined.includes("cannot find path")) {
    return {
      class: "provider_cli_missing",
      explanation: "外部 provider CLI 不可用或路径不正确。",
      next_action: "回到安装向导或本机配置，修复 provider CLI 路径后重试。"
    };
  }
  if (combined.includes("login") || combined.includes("not logged") || combined.includes("unauthorized") || combined.includes("auth")) {
    return {
      class: "provider_auth_required",
      explanation: "provider 需要用户完成登录、扫码、授权或账号配置。",
      next_action: "让用户按 provider 官方流程完成账号动作，再重跑 canary 或重派任务。"
    };
  }
  if (combined.includes("permission") || combined.includes("denied") || combined.includes("sandbox")) {
    return {
      class: "permission_denied",
      explanation: "worker 被权限、沙箱或工具白名单拦住。",
      next_action: "检查任务模式、工具白名单和 worktree 权限；不要直接放宽到不受控权限。"
    };
  }
  if (status === "timed_out") {
    return {
      class: "worker_timed_out",
      explanation: "worker 已超时并进入终态，不再占用执行 lane。",
      next_action: "检查任务范围、超时和 provider 输出后，再决定重派或由 Codex 接管。"
    };
  }
  if (status === "unknown") {
    return {
      class: "worker_terminal_state_unknown",
      explanation: "watcher 已结束，但无法可靠判定 worker 的最终执行状态。",
      next_action: "检查 watcher 日志和 completion 后人工处理；不要把它当作仍在运行。"
    };
  }
  if (status === "failed" || (typeof exitCode === "number" && exitCode !== 0)) {
    return {
      class: "worker_failed",
      explanation: "worker 进程失败退出。",
      next_action: "读取 stdout/stderr 摘要，判断是重派、换 provider，还是由 Codex 接管。"
    };
  }
  if (status === "process_exited") {
    return {
      class: "awaiting_codex_verification",
      explanation: "worker 进程已退出，执行证据已记录，但仍需要 Codex 检查报告、diff 和业务结果。",
      next_action: "调用验收工具记录 accepted/rejected/retry/human_required。"
    };
  }
  if (status === "completed") {
    return {
      class: "awaiting_codex_verification",
      explanation: "worker 已完成进程层任务，但还需要 Codex 检查报告、diff 和验证结果。",
      next_action: "调用验收工具记录 accepted/rejected/retry/human_required。"
    };
  }

  return {
    class: "unknown_worker_state",
    explanation: "worker 状态无法归入已知分类。",
    next_action: "读取 job 元数据、completion 和日志摘要后人工判断。"
  };
}

export async function dispatchTool(input: {
  repo: string;
  task: string;
  provider?: "auto" | "qoder" | "codebuddy" | "mimo";
  tier?: string;
  mode?: "readonly" | "edit";
  run_mode?: "blocking" | "background";
  task_kind?: "local_audit" | "code_change" | "external_research_support";
  research_contract?: ResearchContract;
  plan_id?: string;
  task_id?: string;
  depends_on?: string;
  acceptance?: string;
  worktree_name?: string;
  max_turns?: number;
  no_notify?: boolean;
}) {
  const repo = resolveExistingRepo(input.repo);
  assertResearchContract(input);
  const runMode = input.run_mode ?? "background";
  const result = await runPowerShell(
    buildDispatchArgs({
      ...input,
      task: appendResearchContract(input.task, input.research_contract),
      repo,
      provider: input.provider ?? "auto",
      run_mode: runMode,
      no_notify: input.no_notify ?? true
    }),
    { timeoutMs: runMode === "blocking" ? 1_800_000 : 120_000, maxOutputBytes: 512_000 }
  );
  const fields = parseKeyValueOutput(result.stdout);
  const completionPath = fields.completion ?? "";
  const completion =
    completionPath && existsSync(completionPath) ? (readJsonFile(completionPath) as Record<string, unknown>) : null;

  return {
    ok: result.exitCode === 0,
    exit_code: result.exitCode,
    repo,
    task: input.task,
    provider: fields.provider ?? input.provider ?? "auto",
    tier: fields.tier ?? input.tier ?? "",
    model: fields.model ?? "",
    mode: input.mode ?? "readonly",
    run_mode: fields.run_mode ?? runMode,
    task_kind: fields.task_kind ?? input.task_kind ?? "",
    research_contract: input.research_contract ?? null,
    job_id: fields.job_id ?? "",
    job_dir: fields.job_dir ?? "",
    watcher_pid: fields.watcher_pid ?? "",
    stdout_path: fields.stdout ?? "",
    stderr_path: fields.stderr ?? "",
    completion_path: completionPath,
    completion,
    command: fields.command ?? "",
    status_note:
      runMode === "background"
        ? "worker 已交给本地 watcher；等待 completion.json 后再由 Codex 验收。"
        : "blocking worker 已退出；仍需 Codex 验收输出和改动。",
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
      "Summary",
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
    // A durable ledger may contain extensive history. Return its compact
    // projection here so the transport limit cannot turn a successful plan
    // creation into an unparseable truncated JSON response.
    plan_summary: getResult.stdout.trim() ? JSON.parse(getResult.stdout) : null,
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

export function isActiveStatus(status: string): boolean {
  // A supervisor verdict may still be required after a process exit, but it
  // must never keep an execution lane active or create a false edit conflict.
  return ["starting", "queued", "running", "cancel_requested"].includes(status);
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

export function governanceSummaryTool(input: { repo: string; plan_id: string }) {
  const repo = resolveExistingRepo(input.repo);
  const planPath = path.join(getPlanRoot(repo), input.plan_id.trim(), "plan.json");
  if (!existsSync(planPath)) {
    return { found: false, repo, plan_id: input.plan_id, plan_path: planPath };
  }
  const plan = readJsonFile(planPath) as Record<string, unknown>;
  const tasks = Array.isArray(plan.tasks) ? (plan.tasks as Record<string, unknown>[]) : [];
  const outcomes = Array.isArray(plan.outcomes) ? plan.outcomes as Record<string, unknown>[] : [];
  const counts = {
    total: tasks.length,
    accepted: tasks.filter((task) => task.governance_state === "accepted").length,
    awaiting_supervisor: tasks.filter((task) => task.governance_state === "awaiting_supervisor").length,
    needs_decision: tasks.filter((task) => task.governance_state === "needs_decision").length,
    retryable: tasks.filter((task) => task.governance_state === "retryable").length,
    blocked: tasks.filter((task) => task.governance_state === "blocked").length,
    outcomes: outcomes.length
  };
  return {
    found: true,
    repo,
    plan_id: String(plan.plan_id ?? input.plan_id),
    revision: Number(plan.revision ?? 0),
    release_state: String(plan.release_state ?? "draft"),
    counts,
    needs_decision: tasks.filter((task) => task.governance_state === "needs_decision").map((task) => ({ task_id: task.task_id, next_action: task.next_action, summary: task.summary })),
    tasks: tasks.map((task) => ({ task_id: task.task_id, status: task.status, governance_state: task.governance_state, progress: task.progress, next_action: task.next_action })),
    plan_path: planPath
  };
}

export function resultTool(input: {
  repo: string;
  job_id: string;
  include_log_tails?: boolean;
  max_log_chars?: number;
}) {
  const repo = resolveExistingRepo(input.repo);
  const jobId = input.job_id.trim();
  const jobDir = path.join(getJobRoot(repo), jobId);
  if (!existsSync(jobDir)) {
    return {
      found: false,
      repo,
      job_id: jobId,
      path: jobDir,
      message: "Job not found."
    };
  }

  const metaPath = path.join(jobDir, "job.json");
  const completionPath = path.join(jobDir, "completion.json");
  const stdoutPath = path.join(jobDir, "stdout.log");
  const stderrPath = path.join(jobDir, "stderr.log");
  const meta = existsSync(metaPath) ? readJsonFile(metaPath) : {};
  const completion = existsSync(completionPath) ? readJsonFile(completionPath) : null;
  const includeLogTails = input.include_log_tails ?? true;
  const maxLogChars = Math.max(1_000, Math.min(input.max_log_chars ?? 12_000, 60_000));
  const stdoutTail = includeLogTails ? readTextTail(stdoutPath, maxLogChars) : "";
  const stderrTail = includeLogTails ? readTextTail(stderrPath, maxLogChars) : "";
  const classification = classifyWorkerOutcome({
    meta,
    completion,
    stdout_tail: stdoutTail,
    stderr_tail: stderrTail
  });

  return {
    found: true,
    repo,
    job_id: jobId,
    job_dir: jobDir,
    meta,
    completion,
    classification,
    log_paths: {
      stdout: stdoutPath,
      stderr: stderrPath,
      watcher: path.join(jobDir, "watcher.log")
    },
    stdout_tail: stdoutTail,
    stderr_tail: stderrTail
  };
}

export async function nextReadyTool(input: {
  repo: string;
  plan_id: string;
  limit?: number;
}) {
  const repo = resolveExistingRepo(input.repo);
  const planRoot = getPlanRoot(repo);
  const result = await runPowerShell(
    [
      "-NoProfile",
      "-ExecutionPolicy",
      "Bypass",
      "-File",
      getPlanScriptPath(),
      "-Action",
      "NextReady",
      "-PlanId",
      input.plan_id,
      "-PlanRoot",
      planRoot,
      "-OutputJson"
    ],
    { timeoutMs: 30_000 }
  );
  const raw = result.stdout.trim();
  let parsed: unknown[] = [];
  if (raw) {
    const value = JSON.parse(raw) as unknown;
    parsed = Array.isArray(value) ? value : [value];
  }
  const limit = Math.max(1, Math.min(input.limit ?? 20, 100));
  return {
    ok: result.exitCode === 0,
    exit_code: result.exitCode,
    repo,
    plan_id: input.plan_id,
    plan_root: planRoot,
    ready_tasks: parsed.slice(0, limit),
    count: Math.min(parsed.length, limit),
    stderr: result.stderr
  };
}

function getPlanTask(repo: string, planId: string, taskId: string) {
  const planDir = path.join(getPlanRoot(repo), planId);
  const planPath = path.join(planDir, "plan.json");
  if (!existsSync(planPath)) {
    throw new Error(`Plan not found: ${planPath}`);
  }
  const plan = readJsonFile(planPath);
  const tasks = Array.isArray(plan.tasks) ? (plan.tasks as Record<string, unknown>[]) : [];
  const task = tasks.find((candidate) => String(candidate.task_id ?? "") === taskId);
  if (!task) {
    throw new Error(`Task not found in plan ${planId}: ${taskId}`);
  }
  return { plan, task };
}

export async function dispatchPlanTaskTool(input: {
  repo: string;
  plan_id: string;
  task_id: string;
  provider?: "auto" | "qoder" | "codebuddy" | "mimo";
  tier?: string;
  mode?: "readonly" | "edit";
  run_mode?: "blocking" | "background";
  max_turns?: number;
  no_notify?: boolean;
}) {
  const repo = resolveExistingRepo(input.repo);
  const taskId = input.task_id.trim();
  const { task } = getPlanTask(repo, input.plan_id, taskId);
  const status = String(task.status ?? "");
  if (status !== "pending") {
    return {
      ok: false,
      repo,
      plan_id: input.plan_id,
      task_id: taskId,
      status,
      message: "Only pending plan tasks can be dispatched."
    };
  }

  const title = String(task.title ?? "");
  const acceptance = String(task.acceptance ?? "");
  const dependsOn = Array.isArray(task.depends_on) ? (task.depends_on as unknown[]).map(String).join(",") : "";
  return dispatchTool({
    repo,
    task: title,
    provider: input.provider ?? "auto",
    tier: input.tier,
    mode: input.mode ?? (String(task.mode ?? "") === "edit" ? "edit" : "readonly"),
    run_mode: input.run_mode ?? "background",
    plan_id: input.plan_id,
    task_id: taskId,
    depends_on: dependsOn,
    acceptance,
    max_turns: input.max_turns,
    no_notify: input.no_notify ?? true
  });
}

export async function verifyTaskTool(input: {
  repo: string;
  plan_id: string;
  task_id: string;
  verdict: "accepted" | "rejected" | "retry" | "human_required" | "skipped";
  summary: string;
  next_action?: string;
}) {
  const repo = resolveExistingRepo(input.repo);
  const result = await runPowerShell(
    [
      "-NoProfile",
      "-ExecutionPolicy",
      "Bypass",
      "-File",
      getPlanScriptPath(),
      "-Action",
      "VerifyTask",
      "-PlanId",
      input.plan_id,
      "-PlanRoot",
      getPlanRoot(repo),
      "-TaskId",
      input.task_id,
      "-VerificationVerdict",
      input.verdict,
      "-VerificationSummary",
      input.summary,
      "-NextAction",
      input.next_action ?? "",
      "-OutputJson"
    ],
    { timeoutMs: 30_000 }
  );

  return {
    ok: result.exitCode === 0,
    exit_code: result.exitCode,
    repo,
    plan_id: input.plan_id,
    task_id: input.task_id,
    verdict: input.verdict,
    plan: result.stdout.trim() ? JSON.parse(result.stdout) : null,
    stderr: result.stderr
  };
}
