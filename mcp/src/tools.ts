import { createHash } from "node:crypto";
import { execFileSync } from "node:child_process";
import { existsSync, readdirSync, readFileSync, statSync } from "node:fs";
import path from "node:path";
import {
  getInvokeScriptPath,
  getCancelScriptPath,
  getCapabilityEvidenceRoot,
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
import { evaluationSuiteTool as buildEvaluationSuite, prepareEvaluationTool as buildPrepareEvaluation, verifyEvaluationTaskTool as buildVerifyEvaluationTask } from "./evaluation-suite.js";
import { explainableRouteTool as buildExplainableRoute } from "./explainable-routing.js";
import { providerOperationsTool as buildProviderOperations } from "./provider-operations.js";
import type { JobSummary, LaneSummary, ResearchContract } from "./types.js";

type WorkerTaskKind = "local_audit" | "test_execution" | "code_change" | "external_research_support";
type CapabilityTaskFamily = "read_only_diagnosis" | "bounded_code_change" | "fixed_test_execution" | "failure_recovery";

function providerDisplayName(value: unknown): string {
  const provider = String(value ?? "").trim().toLowerCase();
  if (provider === "qoder") return "Qoder";
  if (provider === "codebuddy") return "CodeBuddy";
  return provider;
}

function connectionDisplayName(value: unknown): string {
  const connection = String(value ?? "").trim();
  if (connection === "qoder_agent_sdk") return "Qoder Agent SDK";
  if (connection === "supervised_cli_stream_json") return "Qoder CLI（stream-json）";
  if (connection === "codebuddy_acp") return "ACP";
  return connection;
}

function assertResearchContract(input: {
  task_kind?: WorkerTaskKind;
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
  const repo = input.repo ? resolveExistingRepo(input.repo) : "";
  const decision = routeIntent(input.request, input.allow_native_codex_subagents ?? false);
  return {
    ...decision,
    repo
  };
}

export function runtimeInfoTool() {
  const contractPath = getRuntimeContractPath();
  const contract = existsSync(contractPath) ? readJsonFile(contractPath) : null;
  const generationPath = path.join(getProjectRoot(), "release-generation.json");
  const generation = existsSync(generationPath) ? readJsonFile(generationPath) : null;
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
      version: typeof contract?.version === "string" ? contract.version : "",
      generation_id: typeof generation?.generation_id === "string" ? generation.generation_id : "",
      runtime_contract_sha256: runtimeContractSha256,
      project_root: getProjectRoot(),
      mcp_root: getMcpRoot(),
      process_id: process.pid,
      process_started_at: startedAt
    }
  };
}

export function capabilityProfilesTool(input: { repo: string; include_unclassified?: boolean; evidence_root?: string }) {
  return buildCapabilityProfiles(input);
}

export function evaluationSuiteTool() {
  return buildEvaluationSuite();
}

export async function prepareEvaluationTool(input: { repo: string; plan_id?: string }) {
  return buildPrepareEvaluation(input);
}

export async function verifyEvaluationTaskTool(input: { repo: string; plan_id: string; task_id: string; worktree: string }) {
  return buildVerifyEvaluationTask(input);
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
  const connectionMode = String(meta.connection_mode ?? "");
  const sessionPath =
    connectionMode === "qoder_agent_sdk"
      ? String(meta.qoder_sdk_session ?? "")
      : connectionMode === "codebuddy_acp"
        ? String(meta.codebuddy_acp_session ?? "")
        : "";
  const connectionState = sessionPath && existsSync(sessionPath) ? readJsonFile(sessionPath) : null;
  const connectionStage = String(connectionState?.state ?? meta.status ?? "unknown");
  return {
    found: true,
    display: {
      阶段: connectionStage,
      执行者: providerDisplayName(meta.provider),
      模型: String(meta.model ?? ""),
      连接: connectionDisplayName(connectionMode),
      任务类别: String(meta.task_kind ?? ""),
      下一步: completion ? "由 Codex 读取结果并记录验收结论；宿主断线后可用同一 job_id 重新读取。" : "等待 worker 到达终态；宿主断线后用同一 job_id 重新读取，不要重派。"
    },
    job_id: input.job_id,
    contract_hash: String(meta.contract_hash ?? ""),
    events: Array.isArray(meta.events) ? meta.events : [],
    connection_state: connectionState,
    meta: redactJobMeta(meta),
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
  provider: "auto" | "qoder" | "codebuddy";
  tier?: string;
  mode?: "readonly" | "edit";
  run_mode?: "blocking" | "background";
  task_kind?: WorkerTaskKind;
  task_family?: CapabilityTaskFamily;
  research_contract?: ResearchContract;
  plan_id?: string;
  task_id?: string;
  depends_on?: string;
  acceptance?: string;
  worktree_name?: string;
  max_turns?: number;
  max_stall_seconds?: number;
  timeout_seconds?: number;
  allowed_paths?: string[];
  forbidden_paths?: string[];
  required_checks?: string[];
  budget?: Record<string, unknown>;
  failure_injection?: string;
  sensitivity?: string;
  real_worktree?: boolean;
  base_commit?: string;
  immutable_paths?: string[];
}) {
  const repo = resolveExistingRepo(input.repo);
  assertResearchContract(input);
  const realWorktree = input.real_worktree ?? input.task_kind === "code_change";
  const isCodeChangePreflight = input.task_kind === "code_change" && realWorktree;
  const result = await runPowerShell(
    buildDispatchArgs({
      ...input,
      repo,
      task: appendResearchContract(input.task, input.research_contract),
      mode: input.mode ?? (isCodeChangePreflight ? "edit" : "readonly"),
      run_mode: input.run_mode ?? "blocking",
      real_worktree: realWorktree,
      dry_run: true,
      no_notify: true
    }),
    { timeoutMs: 120_000 }
  );
  const fields = parseKeyValueOutput(result.stdout);
  return {
    display: {
      阶段: isCodeChangePreflight ? "真实代码任务合同预检" : "派工预演",
      状态: result.exitCode === 0 ? "可继续，未启动 worker" : "未启动 worker，预检失败",
      执行者: providerDisplayName(fields.provider ?? input.provider),
      模型: String(fields.model ?? ""),
      连接: connectionDisplayName(fields.connection_mode ?? ""),
      下一步: result.exitCode === 0
        ? "合同已检查；Codex 仍需决定是否启动真实 worker。"
        : "修复任务合同、基线或范围后重试；此结果不代表 worker 已启动或 provider 已失败。"
    },
    ok: result.exitCode === 0,
    exit_code: result.exitCode,
    repo,
    task: input.task,
    fields,
    provider: fields.provider ?? input.provider,
    tier: fields.tier ?? input.tier ?? "",
    model: fields.model ?? "",
    connection_mode: fields.connection_mode ?? "",
    model_policy: fields.model_policy ?? "",
    mode: input.mode ?? (isCodeChangePreflight ? "edit" : "readonly"),
    run_mode: fields.run_mode ?? input.run_mode ?? "blocking",
    preflight_kind: isCodeChangePreflight ? "real_code_change" : "standard",
    // This is the wrapper-validated contract, not evidence that a worktree
    // exists. A dry-run must never be represented as a real dispatch.
    real_worktree: realWorktree,
    base_commit: input.base_commit ?? "",
    immutable_paths: input.immutable_paths ?? [],
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
  provider: "auto" | "qoder" | "codebuddy";
  tier?: string;
  mode?: "readonly" | "edit";
  run_mode?: "blocking" | "background";
  task_kind?: WorkerTaskKind;
  research_contract?: ResearchContract;
  dry_run?: boolean;
  plan_id?: string;
  task_id?: string;
  task_family?: CapabilityTaskFamily;
  depends_on?: string;
  acceptance?: string;
  worktree_name?: string;
  max_turns?: number;
  max_stall_seconds?: number;
  timeout_seconds?: number;
  allowed_paths?: string[];
  forbidden_paths?: string[];
  required_checks?: string[];
  budget?: Record<string, unknown>;
  failure_injection?: string;
  sensitivity?: string;
  task_material?: Record<string, unknown>;
  real_worktree?: boolean;
  base_commit?: string;
  immutable_paths?: string[];
  evidence_bootstrap?: boolean;
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
  appendOptionalStringArg(args, "-TaskFamily", input.task_family);
  appendOptionalStringArg(args, "-DependsOn", input.depends_on);
  appendOptionalStringArg(args, "-Acceptance", input.acceptance);
  appendOptionalStringArg(args, "-WorktreeName", input.worktree_name);
  appendOptionalNumberArg(args, "-MaxTurns", input.max_turns);
  appendOptionalNumberArg(args, "-MaxStallSeconds", input.max_stall_seconds);
  appendOptionalNumberArg(args, "-TimeoutSeconds", input.timeout_seconds);
  if ((input.allowed_paths?.length ?? 0) > 0) args.push("-AllowedPathsJson", JSON.stringify(input.allowed_paths));
  if ((input.forbidden_paths?.length ?? 0) > 0) args.push("-ForbiddenPathsJson", JSON.stringify(input.forbidden_paths));
  if ((input.required_checks?.length ?? 0) > 0) args.push("-RequiredChecksJson", JSON.stringify(input.required_checks));
  if (input.budget) args.push("-BudgetJson", JSON.stringify(input.budget));
  appendOptionalStringArg(args, "-FailureInjection", input.failure_injection);
  appendOptionalStringArg(args, "-Sensitivity", input.sensitivity);
  appendOptionalStringArg(args, "-BaseCommit", input.base_commit);
  if (input.real_worktree) {
    args.push("-RealWorktree");
    if ((input.immutable_paths?.length ?? 0) > 0) args.push("-ImmutablePathsJson", JSON.stringify(input.immutable_paths));
  }
  if (input.task_material) {
    const sourceRoot = String(input.task_material.source_root ?? "").trim();
    if (!sourceRoot) {
      throw new Error("Code-change task material lacks its durable source root.");
    }
    args.push("-TaskMaterialPath", path.join(sourceRoot, "task-material.json"));
  }
  if (input.evidence_bootstrap) {
    args.push("-EvidenceBootstrap");
  }

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
      explanation: "provider 已因风控拒绝本次请求；这不是成功结果，也不是本地 worktree 问题。",
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
  if (String(completion?.readiness_bootstrap_status ?? input.meta.readiness_bootstrap_status ?? "") === "failed") {
    return {
      class: "readiness_bootstrap_failed",
      explanation: "真实任务完成了，但当前 provider 的首用 readiness 没能持久记录，不能把本次能力状态当作已就绪。",
      next_action: "保留本次 job 证据，检查 readiness 文件写入权限后，从同一任务结果恢复记录；不要重复执行原任务。"
    };
  }
  if (failureClass === "max_turns_exceeded") {
    return {
      class: "worker_max_turns_exceeded",
      explanation: artifactState === "partial_worktree_diff" ? "worker 超轮数且留下了半成品改动，不能直接验收或合并。" : "worker 超轮数且没有完成任务，不能把进程退出当作有效结果。",
      next_action: "保留 worktree 供 Codex 检查；缩小任务、补充上下文、走冷恢复、换已合格 provider，或由 Codex 接管。不要把普通派工变成盲目提高固定轮数。"
    };
  }
  if (failureClass === "progress_saturated") {
    return {
      class: "progress_saturated",
      explanation: "worker 已在持续缺少结构化进展后被正式收束；这不是可验收结果。",
      next_action: "保留 worktree 与事件证据，由 Codex 判断是否补充任务上下文、冷恢复，或接管剩余工作。"
    };
  }
  if (combined.includes("max turns") || combined.includes("maximum turns") || combined.includes("turns exceeded")) {
    return {
      class: "worker_max_turns_exceeded",
      explanation: "worker 在轮数上限内没有完成任务，不能把它当作有效结果。",
      next_action: "缩小任务、补充上下文、走冷恢复、换已合格 provider，或由 Codex 接管。不要把普通派工变成盲目提高固定轮数。"
    };
  }
  if (combined.includes("cli not found") || combined.includes("not recognized") || combined.includes("cannot find path")) {
    return {
      class: "provider_cli_missing",
      explanation: "外部 provider CLI 不可用或路径不正确。",
      next_action: "回到安装向导或本机配置，修复 provider CLI 路径后重试。"
    };
  }
  if (
    combined.includes("login required") ||
    combined.includes("not logged in") ||
    combined.includes("unauthorized") ||
    combined.includes("authentication required") ||
    combined.includes("authentication failed") ||
    combined.includes("authorization required") ||
    combined.includes("auth required") ||
    combined.includes("invalid token") ||
    combined.includes("token expired")
  ) {
    return {
      class: "provider_auth_required",
      explanation: "provider 需要用户完成登录、扫码、授权或账号配置。",
      next_action: "让用户按 provider 官方流程完成账号动作，再重跑 canary 或重派任务。"
    };
  }
  // An ACP client can correctly deny an out-of-contract request and still
  // complete the bounded task through an allowed path. The watcher records
  // those denials as evidence; a successful process must remain available for
  // Codex's independent verification rather than being downgraded by a word
  // that happens to occur in its diagnostics.
  const completedWithoutSemanticFailure = status === "process_exited" && exitCode === 0 && !failureClass;
  if (!completedWithoutSemanticFailure && (combined.includes("permission") || combined.includes("denied") || combined.includes("sandbox"))) {
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
  provider?: "auto" | "qoder" | "codebuddy";
  tier?: string;
  mode?: "readonly" | "edit";
  run_mode?: "blocking" | "background";
  task_kind?: WorkerTaskKind;
  research_contract?: ResearchContract;
  plan_id?: string;
  task_id?: string;
  task_family?: CapabilityTaskFamily;
  depends_on?: string;
  acceptance?: string;
  worktree_name?: string;
  max_turns?: number;
  max_stall_seconds?: number;
  timeout_seconds?: number;
  allowed_paths?: string[];
  forbidden_paths?: string[];
  required_checks?: string[];
  budget?: Record<string, unknown>;
  failure_injection?: string;
  sensitivity?: string;
  task_material?: Record<string, unknown>;
  real_worktree?: boolean;
  base_commit?: string;
  immutable_paths?: string[];
  evidence_bootstrap?: boolean;
  dry_run?: boolean;
  no_notify?: boolean;
}) {
  const repo = resolveExistingRepo(input.repo);
  const isDryRun = input.dry_run === true;
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
    display: {
      阶段: isDryRun ? "预演 worker 派工" : "已派发 worker",
      状态: result.exitCode === 0 ? (isDryRun ? "预演通过，未启动" : fields.job_id ? (fields.pid === "pending" ? "job 已创建，等待 watcher 启动" : "worker 已启动") : "未确认 job") : "失败",
      执行者: providerDisplayName(fields.provider ?? input.provider ?? "auto"),
      模型: String(fields.model ?? ""),
      连接: connectionDisplayName(fields.connection_mode ?? ""),
      下一步: result.exitCode === 0 ? (isDryRun ? "未创建 job；Codex 可据此决定是否真实派工。" : "worker 终态后由 Codex 检查 diff、范围和测试。") : "读取失败分类后决定恢复、改派或由 Codex 接管。"
    },
    ok: result.exitCode === 0,
    exit_code: result.exitCode,
    repo,
    task: input.task,
    provider: fields.provider ?? input.provider ?? "auto",
    tier: fields.tier ?? input.tier ?? "",
    model: fields.model ?? "",
    connection_mode: fields.connection_mode ?? "",
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
    status_note: isDryRun
      ? "预演通过：未启动 worker，未创建 job。"
      : runMode === "background"
        ? "worker 已交给本地 watcher；等待 completion.json 后再由 Codex 验收。"
        : "blocking worker 已退出；仍需 Codex 验收输出和改动。",
    job_created: !isDryRun && Boolean(fields.job_id),
    worker_started: !isDryRun && fields.pid !== "pending" && Boolean(fields.pid),
    transport_recovery: !isDryRun && Boolean(fields.job_id) ? `宿主断线时调用 codex_praetor_job_timeline，job_id=${fields.job_id}；不要重复创建任务。` : "",
    stdout: result.stdout,
    stderr: result.stderr
  };
}

export type PlannedTaskContract = {
  task_id?: string;
  title: string;
  task_family: CapabilityTaskFamily;
  task_kind: WorkerTaskKind;
  mode: "readonly" | "edit";
  acceptance: string;
  allowed_paths: string[];
  forbidden_paths: string[];
  required_checks: string[];
  budget: Record<string, unknown>;
  depends_on?: string[];
  failure_injection?: string;
  sensitivity?: string;
  base_commit?: string;
  immutable_paths?: string[];
  evidence_context?: Record<string, unknown>;
  validation_only?: boolean;
  validation_reason?: string;
};

function validatePlannedTaskContract(task: PlannedTaskContract, taskId: string): string | undefined {
  if (!task.title.trim() || !task.acceptance.trim()) return `Task '${taskId}' needs both title and acceptance.`;
  if (!task.task_family || !task.task_kind || !task.mode) return `Task '${taskId}' needs task_family, task_kind, and mode.`;
  if (task.allowed_paths.length === 0 || task.forbidden_paths.length === 0 || task.required_checks.length === 0) return `Task '${taskId}' needs non-empty allowed_paths, forbidden_paths, and required_checks.`;
  if (Object.keys(task.budget).length === 0) return `Task '${taskId}' needs a non-empty budget.`;
  if ((task.task_kind === "code_change") !== (task.mode === "edit")) return `Task '${taskId}' has conflicting task_kind and mode.`;
  if (task.task_kind === "test_execution" && task.mode !== "readonly") return `Task '${taskId}' must be readonly.`;
  return undefined;
}

export async function planTool(input: {
  repo: string;
  title: string;
  tasks: PlannedTaskContract[];
  plan_id?: string;
}) {
  const repo = resolveExistingRepo(input.repo);
  const planId = input.plan_id?.trim() || `plan-${new Date().toISOString().replace(/[:.]/g, "-")}`;
  const planRoot = getPlanRoot(repo);
  const taskIds = input.tasks.map((task, index) => task.task_id?.trim() || `task-${String(index + 1).padStart(2, "0")}`);
  if (new Set(taskIds).size !== taskIds.length || taskIds.some((taskId) => !/^[A-Za-z0-9][A-Za-z0-9_.-]*$/.test(taskId))) {
    return { ok: false, repo, plan_id: planId, message: "Plan task IDs must be unique ASCII identifiers." };
  }
  for (const [index, task] of input.tasks.entries()) {
    const validationError = validatePlannedTaskContract(task, taskIds[index]);
    if (validationError) return { ok: false, repo, plan_id: planId, message: validationError };
  }

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
    const taskId = taskIds[index];
    const upsertArgs = [
      "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", getPlanScriptPath(),
      "-Action", "UpsertTask", "-PlanId", planId, "-PlanRoot", planRoot,
      "-TaskId", taskId, "-TaskTitle", task.title, "-TaskFamily", task.task_family,
      "-TaskKind", task.task_kind, "-Status", "pending", "-Mode", task.mode,
      "-Acceptance", task.acceptance, "-DependsOnJson", JSON.stringify(task.depends_on ?? []),
      "-BudgetJson", JSON.stringify(task.budget), "-FailureInjection", task.failure_injection ?? "",
      "-Sensitivity", task.sensitivity ?? "", "-BaseCommit", task.base_commit ?? "",
      "-ImmutablePathsJson", JSON.stringify(task.immutable_paths ?? []), "-OutputJson"
    ];
    if (task.validation_only) {
      upsertArgs.push("-ValidationOnly", "-ValidationReason", task.validation_reason?.trim() || "validation_only plan task");
    }
    upsertArgs.push("-AllowedPathsJson", JSON.stringify(task.allowed_paths));
    upsertArgs.push("-ForbiddenPathsJson", JSON.stringify(task.forbidden_paths));
    upsertArgs.push("-RequiredChecksJson", JSON.stringify(task.required_checks));
    const upsertResult = await runPowerShell(
      upsertArgs,
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
    if (task.evidence_context) {
      const contextResult = await runPowerShell(
        ["-NoProfile", "-ExecutionPolicy", "Bypass", "-File", getPlanScriptPath(), "-Action", "SetEvidenceContext", "-PlanId", planId, "-PlanRoot", planRoot, "-TaskId", taskId, "-EvidenceContextJson", JSON.stringify(task.evidence_context), "-OutputJson"],
        { timeoutMs: 30_000 }
      );
      if (contextResult.exitCode !== 0) return { ok: false, exit_code: contextResult.exitCode, failed_task_id: taskId, stderr: contextResult.stderr, stdout: contextResult.stdout };
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
    task_ids: taskIds,
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

function redactJobMeta(meta: Record<string, unknown>): Record<string, unknown> {
  const { notify_thread_id: _notifyThreadId, ...safe } = meta;
  return safe;
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
    owner_thread_id: "",
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
    meta: redactJobMeta(meta),
    completion,
    stdout_tail: stdoutTail,
    stderr_tail: stderrTail
  });

  return {
    found: true,
    repo,
    job_id: jobId,
    job_dir: jobDir,
    meta: redactJobMeta(meta),
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

function currentCommitOrPlanRef(repo: string, planId: string): string {
  try {
    const value = execFileSync("git", ["-C", repo, "rev-parse", "HEAD"], { encoding: "utf8", stdio: ["ignore", "pipe", "ignore"] }).trim();
    return /^[0-9a-f]{40}$/i.test(value) ? value : `plan:${planId}`;
  } catch {
    return `plan:${planId}`;
  }
}

function automaticUserRequestEvidenceContext(input: { repo: string; planId: string; taskId: string; title: string; acceptance: string; requiredChecks: string[]; connectionMode: string }) {
  const inputSha = createHash("sha256").update(JSON.stringify({ title: input.title, acceptance: input.acceptance, required_checks: input.requiredChecks })).digest("hex");
  const verifierSha = createHash("sha256").update(input.requiredChecks.join("\n")).digest("hex");
  return {
    source_category: "real_user_request",
    source_ref: `plan:${input.planId}:task:${input.taskId}`,
    source_commit: currentCommitOrPlanRef(input.repo, input.planId),
    input_sha256: inputSha,
    connection_mode: input.connectionMode,
    verifier_id: "codex-praetor-plan-acceptance",
    verifier_version: "v1",
    verifier_sha256: verifierSha
  };
}

export async function dispatchPlanTaskTool(input: {
  repo: string;
  plan_id: string;
  task_id: string;
  provider?: "auto" | "qoder" | "codebuddy";
  tier?: string;
  run_mode?: "blocking" | "background";
  max_turns?: number;
  max_stall_seconds?: number;
  no_notify?: boolean;
  dry_run?: boolean;
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
  const taskKind = String(task.task_kind ?? "") as WorkerTaskKind;
  const taskFamily = String(task.task_family ?? "") as CapabilityTaskFamily;
  const mode = String(task.mode ?? "");
  const allowedPaths = Array.isArray(task.allowed_paths) ? task.allowed_paths.map(String) : [];
  const forbiddenPaths = Array.isArray(task.forbidden_paths) ? task.forbidden_paths.map(String) : [];
  const completion = task.completion_definition && typeof task.completion_definition === "object" ? task.completion_definition as Record<string, unknown> : {};
  const requiredChecks = Array.isArray(completion.required_checks) ? completion.required_checks.map(String) : [];
  const budget = task.budget && typeof task.budget === "object" ? task.budget as Record<string, unknown> : {};
  const taskMaterial = task.task_material && typeof task.task_material === "object" && !Array.isArray(task.task_material) ? task.task_material as Record<string, unknown> : undefined;
  const baseCommit = String(task.base_commit ?? "").trim();
  const immutablePaths = Array.isArray(task.immutable_paths) ? task.immutable_paths.map(String) : [];
  let evidenceContext = task.evidence_context && typeof task.evidence_context === "object" && !Array.isArray(task.evidence_context) ? task.evidence_context as Record<string, unknown> : undefined;
  const validationOnly = task.validation_only === true;
  if (!title || !acceptance || !["local_audit", "test_execution", "code_change", "external_research_support"].includes(taskKind) || !["readonly", "edit"].includes(mode) || !["read_only_diagnosis", "bounded_code_change", "fixed_test_execution", "failure_recovery"].includes(taskFamily) || allowedPaths.length === 0 || forbiddenPaths.length === 0 || requiredChecks.length === 0 || Object.keys(budget).length === 0) {
    return { ok: false, repo, plan_id: input.plan_id, task_id: taskId, status, message: "Plan task is missing its dispatch contract; repair the plan instead of inferring task kind or permissions." };
  }
  if ((taskKind === "code_change") !== (mode === "edit") || (taskKind === "test_execution" && mode !== "readonly")) {
    return { ok: false, repo, plan_id: input.plan_id, task_id: taskId, status, message: "Plan task mode and task kind conflict; dispatch is blocked before worker launch." };
  }
  if (taskKind === "code_change" && (!/^[0-9a-f]{40}$/i.test(baseCommit) || immutablePaths.length === 0)) {
    return { ok: false, repo, plan_id: input.plan_id, task_id: taskId, status, message: "Real code-change task lacks a frozen base commit or immutable paths; dispatch is blocked before worker launch." };
  }
  if (validationOnly) {
    return { ok: false, repo, plan_id: input.plan_id, task_id: taskId, status, message: "This task is marked validation_only and cannot spend provider credits through normal plan dispatch. Use local fixtures or explicitly create a user task instead." };
  }
  const requiredEvidenceContext = ["source_category", "source_ref", "source_commit", "input_sha256", "connection_mode", "verifier_id", "verifier_version", "verifier_sha256"];
  const existingEvidenceContext = evidenceContext;
  let evidenceBootstrap = !!existingEvidenceContext
    && !requiredEvidenceContext.some((field) => !String(existingEvidenceContext[field] ?? "").trim())
    && ["real_historical_issue", "real_user_request"].includes(String(existingEvidenceContext?.source_category))
    && ["supervised_cli_text", "supervised_cli_stream_json", "qoder_agent_sdk", "codebuddy_acp"].includes(String(existingEvidenceContext?.connection_mode));
  if (String(task.task_family ?? "") === "fixed_test_execution" && taskKind !== "test_execution") {
    return { ok: false, repo, plan_id: input.plan_id, task_id: taskId, status, message: "A fixed-test task was downgraded to local_audit; dispatch is blocked before worker launch." };
  }
  if (!input.dry_run && !evidenceContext) {
    const bootstrapConnection = input.provider === "qoder" ? "supervised_cli_stream_json" : input.provider === "codebuddy" ? "codebuddy_acp" : "supervised_cli_text";
    evidenceContext = automaticUserRequestEvidenceContext({
      repo,
      planId: input.plan_id,
      taskId,
      title,
      acceptance,
      requiredChecks,
      connectionMode: bootstrapConnection
    });
    const contextResult = await runPowerShell(
      ["-NoProfile", "-ExecutionPolicy", "Bypass", "-File", getPlanScriptPath(), "-Action", "SetEvidenceContext", "-PlanId", input.plan_id, "-PlanRoot", getPlanRoot(repo), "-TaskId", taskId, "-EvidenceContextJson", JSON.stringify(evidenceContext), "-OutputJson"],
      { timeoutMs: 30_000 }
    );
    if (contextResult.exitCode !== 0) {
      return { ok: false, repo, plan_id: input.plan_id, task_id: taskId, status, message: "无法为真实用户任务记录首用 evidence context，worker 尚未启动。", stderr: contextResult.stderr };
    }
    evidenceBootstrap = true;
  }
  const dispatched = await dispatchTool({
    repo,
    task: title,
    provider: input.provider ?? "auto",
    tier: input.tier,
    mode: mode as "readonly" | "edit",
    task_kind: taskKind,
    task_family: taskFamily,
    run_mode: input.run_mode ?? "background",
    plan_id: input.plan_id,
    task_id: taskId,
    depends_on: dependsOn,
    acceptance,
    max_turns: input.max_turns ?? (Number(budget.max_turns ?? 0) || undefined),
    max_stall_seconds: input.max_stall_seconds ?? (Number(budget.max_stall_seconds ?? 0) || undefined),
    timeout_seconds: Number(budget.max_wall_seconds ?? 0) || undefined,
    allowed_paths: allowedPaths,
    forbidden_paths: forbiddenPaths,
    required_checks: requiredChecks,
    budget,
    failure_injection: String(task.failure_injection ?? ""),
    sensitivity: String(task.sensitivity ?? ""),
    real_worktree: taskKind === "code_change",
    base_commit: baseCommit || undefined,
    immutable_paths: immutablePaths,
    evidence_bootstrap: evidenceBootstrap,
    no_notify: input.no_notify ?? true,
    dry_run: input.dry_run ?? false
  });
  if (dispatched.ok && !input.dry_run && evidenceContext && dispatched.job_id && String(dispatched.connection_mode ?? "") && String(evidenceContext.connection_mode ?? "") !== String(dispatched.connection_mode)) {
    const context = automaticUserRequestEvidenceContext({
      repo,
      planId: input.plan_id,
      taskId,
      title,
      acceptance,
      requiredChecks,
      connectionMode: dispatched.connection_mode || (dispatched.provider === "qoder" ? "qoder_agent_sdk" : "codebuddy_acp")
    });
    const contextResult = await runPowerShell(
      ["-NoProfile", "-ExecutionPolicy", "Bypass", "-File", getPlanScriptPath(), "-Action", "SetEvidenceContext", "-PlanId", input.plan_id, "-PlanRoot", getPlanRoot(repo), "-TaskId", taskId, "-EvidenceContextJson", JSON.stringify(context), "-OutputJson"],
      { timeoutMs: 30_000 }
    );
    if (contextResult.exitCode !== 0) {
      return { ...dispatched, ok: false, message: "Worker started but its automatic evidence context could not be recorded; do not accept this task until the ledger is repaired.", stderr: `${dispatched.stderr}\n${contextResult.stderr}` };
    }
  }
  return dispatched;
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
      "-CapabilityEvidenceRoot",
      getCapabilityEvidenceRoot(),
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
