import { createHash } from "node:crypto";
import { existsSync, readdirSync, readFileSync } from "node:fs";
import path from "node:path";
import { getCapabilityEvidenceRoot, getPlanRoot, resolveExistingRepo } from "./paths.js";

export type CapabilityProfileStatus = "unknown" | "observed" | "provisional" | "qualified" | "cooling_down" | "blocked" | "stale";

type JsonRecord = Record<string, unknown>;

const taskFamilies = new Set(["read_only_diagnosis", "bounded_code_change", "fixed_test_execution", "failure_recovery"]);
const hardBlockedFailures = new Set(["provider_risk_control", "provider_auth_required", "provider_cli_missing", "provider_rejected", "provider_output_unparseable", "worker_process_failed", "worker_exit_code_unavailable", "tool_denied", "permission_denied"]);
const transientFailures = new Set(["worker_timed_out", "network_timeout", "rate_limited", "provider_unavailable"]);
const profileEvidenceMaxAgeMs = 30 * 24 * 60 * 60 * 1000;
const transientCooldownMs = 60 * 60 * 1000;
const requiredTupleFields = ["provider", "cli_path", "cli_hash", "model", "permission_profile", "task_kind", "generation_id", "runtime_contract_sha256", "task_contract_schema"];

function asRecord(value: unknown): JsonRecord {
  return value && typeof value === "object" && !Array.isArray(value) ? value as JsonRecord : {};
}

function asString(value: unknown): string {
  return typeof value === "string" ? value : "";
}

function arrayOfRecords(value: unknown): JsonRecord[] {
  return Array.isArray(value) ? value.map(asRecord) : [];
}

function tupleFrom(attempt: JsonRecord, task: JsonRecord): JsonRecord {
  const tuple = asRecord(attempt.provider_tuple);
  return {
    provider: asString(tuple.provider) || asString(attempt.provider) || asString(task.provider),
    cli_path: asString(tuple.cli_path),
    cli_hash: asString(tuple.cli_hash),
    model: asString(tuple.model) || asString(attempt.model) || asString(task.model),
    permission_profile: asString(tuple.permission_profile),
    task_kind: asString(tuple.task_kind) || asString(attempt.task_kind) || "",
    generation_id: asString(tuple.generation_id),
    runtime_contract_sha256: asString(tuple.runtime_contract_sha256),
    task_contract_schema: asString(tuple.task_contract_schema)
  };
}

function tupleKey(tuple: JsonRecord): string {
  return ["provider", "cli_path", "cli_hash", "model", "permission_profile", "task_kind", "generation_id", "runtime_contract_sha256", "task_contract_schema"].map((key) => asString(tuple[key])).join("\u001f");
}

function profileId(tuple: JsonRecord, taskFamily: string): string {
  return createHash("sha256").update(`${taskFamily}\u001f${tupleKey(tuple)}`).digest("hex").slice(0, 20);
}

function familyFrom(task: JsonRecord, attempt: JsonRecord): string {
  const candidate = asString(task.task_family) || asString(attempt.task_family);
  return taskFamilies.has(candidate) ? candidate : "unclassified";
}

function verdictFrom(task: JsonRecord, attempt: JsonRecord): "accepted" | "rejected" | "blocked" | "unknown" {
  const supervisorVerdict = asString(attempt.supervisor_verdict);
  if (supervisorVerdict === "accepted") return "accepted";
  if (["rejected", "skipped"].includes(supervisorVerdict)) return "rejected";
  if (["blocked", "human_required"].includes(supervisorVerdict)) return "blocked";
  // v2 ledgers written before the per-attempt verdict field existed only have
  // a task-level decision. It is safe to inherit that decision only when the
  // task contains one attempt; otherwise the decision cannot identify which
  // immutable attempt Codex accepted.
  if (arrayOfRecords(task.attempts).length === 1 && asString(task.governance_state) === "accepted") return "accepted";
  if (["blocked", "needs_decision"].includes(asString(task.governance_state))) return "blocked";
  if (["rejected", "retryable"].includes(asString(task.governance_state)) || asString(attempt.failure_class)) return "rejected";
  return "unknown";
}

function recordedAt(attempt: JsonRecord, task: JsonRecord): string {
  return asString(attempt.finished_at) || asString(attempt.created_at) || asString(task.verified_at) || asString(task.updated_at) || "";
}

function readPlanFiles(repo: string): Array<{ planId: string; plan: JsonRecord }> {
  const planRoot = getPlanRoot(resolveExistingRepo(repo));
  if (!existsSync(planRoot)) return [];
  const plans: Array<{ planId: string; plan: JsonRecord }> = [];
  for (const entry of readdirSync(planRoot, { withFileTypes: true })) {
    if (!entry.isDirectory()) continue;
    const planPath = path.join(planRoot, entry.name, "plan.json");
    if (!existsSync(planPath)) continue;
    try {
      const plan = asRecord(JSON.parse(readFileSync(planPath, "utf8")));
      plans.push({ planId: asString(plan.plan_id) || entry.name, plan });
    } catch {
      // A malformed historical plan is not capability evidence. The caller
      // receives the skipped plan id rather than treating it as success.
      plans.push({ planId: entry.name, plan: { malformed: true } });
    }
  }
  return plans;
}

function readAcceptedEvidence(root: string): JsonRecord[] {
  if (!existsSync(root)) return [];
  const receipts: JsonRecord[] = [];
  for (const entry of readdirSync(root, { withFileTypes: true })) {
    if (!entry.isFile() || !entry.name.endsWith(".json")) continue;
    try {
      const receipt = asRecord(JSON.parse(readFileSync(path.join(root, entry.name), "utf8")));
      const tuple = asRecord(receipt.provider_tuple);
      if (asString(receipt.schema) !== "codex-praetor-capability-evidence/v1" || asString(receipt.supervisor_verdict) !== "accepted" || !asString(receipt.evidence_id) || !asString(receipt.task_family) || requiredTupleFields.some((field) => !asString(tuple[field]))) continue;
      receipts.push(receipt);
    } catch {
      // A corrupt local receipt is never evidence and must not block unrelated profiles.
    }
  }
  return receipts;
}

export function capabilityProfilesTool(input: { repo: string; include_unclassified?: boolean; evidence_root?: string }) {
  const repo = resolveExistingRepo(input.repo);
  const buckets = new Map<string, { tuple: JsonRecord; taskFamily: string; evidence: JsonRecord[] }>();
  const malformedPlans: string[] = [];
  for (const { planId, plan } of readPlanFiles(repo)) {
    if (plan.malformed === true) {
      malformedPlans.push(planId);
      continue;
    }
    for (const task of arrayOfRecords(plan.tasks)) {
      for (const attempt of arrayOfRecords(task.attempts)) {
        const tuple = tupleFrom(attempt, task);
        if (!asString(tuple.provider) || !asString(tuple.model)) continue;
        const taskFamily = familyFrom(task, attempt);
        if (taskFamily === "unclassified" && !input.include_unclassified) continue;
        const key = `${taskFamily}\u001e${tupleKey(tuple)}`;
        const bucket = buckets.get(key) ?? { tuple, taskFamily, evidence: [] };
        bucket.evidence.push({
          plan_id: planId,
          task_id: asString(task.task_id),
          attempt_id: asString(attempt.attempt_id),
          verdict: verdictFrom(task, attempt),
          recorded_at: recordedAt(attempt, task),
          failure_class: asString(attempt.failure_class),
          supervisor_verdict: asString(attempt.supervisor_verdict),
          evidence_state: asString(attempt.evidence_state),
          completion_path: asString(attempt.completion),
          evidence_source: "legacy_plan"
        });
        buckets.set(key, bucket);
      }
    }
  }
  const evidenceRoot = input.evidence_root ? path.resolve(input.evidence_root) : getCapabilityEvidenceRoot();
  for (const receipt of readAcceptedEvidence(evidenceRoot)) {
    const tuple = asRecord(receipt.provider_tuple);
    const taskFamily = asString(receipt.task_family);
    if (taskFamily === "unclassified" && !input.include_unclassified) continue;
    if (!taskFamilies.has(taskFamily) && taskFamily !== "unclassified") continue;
    const key = `${taskFamily}\u001e${tupleKey(tuple)}`;
    const bucket = buckets.get(key) ?? { tuple, taskFamily, evidence: [] };
    bucket.evidence.push({
      plan_id: "durable-evidence",
      task_id: asString(receipt.evidence_id),
      attempt_id: asString(receipt.evidence_id),
      verdict: "accepted",
      recorded_at: asString(receipt.accepted_at),
      failure_class: "",
      supervisor_verdict: "accepted",
      evidence_state: "artifact_valid",
      completion_path: asString(receipt.completion_sha256),
      evidence_source: "durable_receipt"
    });
    buckets.set(key, bucket);
  }

  const profiles = [...buckets.values()].map((bucket) => {
    const evidence = [...bucket.evidence].sort((a, b) => asString(a.recorded_at).localeCompare(asString(b.recorded_at)));
    const latest = evidence.at(-1) ?? {};
    const accepted = evidence.filter((item) => item.verdict === "accepted");
    const durableAccepted = accepted.filter((item) => item.evidence_source === "durable_receipt");
    const latestDurable = durableAccepted.at(-1) ?? {};
    const failureClass = asString(latest.failure_class);
    let status: CapabilityProfileStatus = "unknown";
    let statusReason = "尚无被 Codex 采信的有效证据。";
    let cooldownUntil = "";
    const latestRecordedAt = Date.parse(asString(latest.recorded_at));
    const latestDurableRecordedAt = Date.parse(asString(latestDurable.recorded_at));
    const hasFreshEvidence = !Number.isNaN(latestDurableRecordedAt) && Date.now() - latestDurableRecordedAt <= profileEvidenceMaxAgeMs;
    if (hardBlockedFailures.has(failureClass)) {
      status = "blocked";
      statusReason = `最近一次尝试为不可自动重试的 ${failureClass || "provider"} 失败。`;
    } else if (transientFailures.has(failureClass)) {
      if (!Number.isNaN(latestRecordedAt) && latestRecordedAt + transientCooldownMs > Date.now()) {
        status = "cooling_down";
        cooldownUntil = new Date(latestRecordedAt + transientCooldownMs).toISOString();
        statusReason = `最近一次尝试为可恢复的 ${failureClass}，冷却结束前不得自动重试。`;
      } else {
        status = "stale";
        statusReason = `最近一次 ${failureClass} 已过冷却窗口；必须重新 canary，旧结果不能用于路由。`;
      }
    } else if (durableAccepted.length === 0) {
      status = "unknown";
      statusReason = accepted.length > 0 ? "历史 plan 记录只能用于追溯；正常派工必须重新获得完整、可携带的 accepted 证据。" : "尚无被 Codex 采信的有效证据。";
    } else if (Object.keys(latestDurable).length > 0 && !hasFreshEvidence) {
      status = "stale";
      statusReason = "最近能力证据已超过 30 天；必须重新 canary，旧结果不能用于路由。";
    } else if (durableAccepted.length >= 3) {
      status = "qualified";
      statusReason = "至少三次独立 attempt 已被 Codex 采信；仍须通过当前硬门。";
    } else if (durableAccepted.length >= 2) {
      status = "provisional";
      statusReason = "已有少量独立采信，只能在低风险工作包中保守建议。";
    } else if (durableAccepted.length === 1) {
      status = "observed";
      statusReason = "只有一次被采信的观察，不能作为默认路由依据。";
    }
    return {
      profile_id: profileId(bucket.tuple, bucket.taskFamily),
      provider_tuple: bucket.tuple,
      task_family: bucket.taskFamily,
      status,
      status_reason: statusReason,
      cooldown_until: cooldownUntil,
      evidence
    };
  }).sort((left, right) => `${left.task_family}:${left.profile_id}`.localeCompare(`${right.task_family}:${right.profile_id}`));

  return {
    schema: "codex-praetor-capability-profile-set/v1",
    generated_at: new Date().toISOString(),
    repo,
    evidence_root: evidenceRoot,
    profiles,
    malformed_plan_ids: malformedPlans,
    policy: {
      profile_is_projection: true,
      default_routing_changed: false,
      hard_gates_remain_authoritative: true,
      normal_dispatch_requires_durable_exact_tuple_evidence: true,
      qualified_minimum_accepted_attempts: 3
    }
  };
}
