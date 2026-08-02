import { createHash } from "node:crypto";
import { existsSync, readFileSync } from "node:fs";
import path from "node:path";
import { capabilityProfilesTool } from "./capability-profiles.js";
import { getRuntimeContractPath, getRuntimeDataPath } from "./paths.js";

type RecordValue = Record<string, unknown>;
type TaskFamily = "read_only_diagnosis" | "bounded_code_change" | "fixed_test_execution" | "failure_recovery";

function asRecord(value: unknown): RecordValue { return value && typeof value === "object" && !Array.isArray(value) ? value as RecordValue : {}; }
function asRecords(value: unknown): RecordValue[] { return Array.isArray(value) ? value.map(asRecord) : []; }
function asString(value: unknown): string { return typeof value === "string" ? value : ""; }
function hasCanaryEvidence(entry: RecordValue): boolean {
  const evidence = asRecord(entry.evidence);
  return asString(evidence.schema) === "codex-praetor-canary-evidence/v1"
    && asString(evidence.job_id) !== ""
    && asString(evidence.worker_stdout_sha256) !== ""
    && asString(evidence.completion_sha256) !== ""
    && asString(evidence.completion_status) === "process_exited"
    && evidence.worker_exit_code === 0
    && asString(evidence.failure_class) === "";
}

function readJson(pathname: string): RecordValue {
  if (!existsSync(pathname)) return {};
  try { return asRecord(JSON.parse(readFileSync(pathname, "utf8").replace(/^\uFEFF/, ""))); } catch { return {}; }
}

function readReadiness(): RecordValue[] {
  const home = process.env.USERPROFILE || process.env.HOME || "";
  if (!home) return [];
  return asRecords(readJson(path.join(home, ".codex", "codex-praetor-readiness.json")).entries);
}

function statusFor(profile: RecordValue | undefined, readiness: RecordValue[]) {
  const failure = asString(asRecords(profile?.evidence).at(-1)?.failure_class);
  const profileStatus = asString(profile?.status) || "unknown";
  const currentReadiness = readiness.length > 0;
  if (profileStatus === "blocked" && failure === "provider_auth_required") return { status: "需要登录", next_action: "按 provider 官方流程完成登录或授权后，重新运行对应 tuple 的 canary。" };
  if (profileStatus === "blocked") return { status: "暂不可派", next_action: "先处理最近的明确阻断原因，再重新 canary；不得自动重试。" };
  if (profileStatus === "cooling_down") return { status: "冷却中", next_action: "等待冷却结束；仅对短暂故障执行有界重试，不能改为无限重派。" };
  if (profileStatus === "stale") return { status: "证据过期", next_action: "重新运行当前 generation 的 canary 和小型同任务族验证。" };
  if (currentReadiness) return { status: "能派", next_action: "可直接派发完整、受控的真实用户任务；仍须逐项检查范围、预算、权限和验收。" };
  return { status: "待就绪", next_action: "先完成当前 worker 身份的无付费 readiness 检查；不要为凑历史记录创建额外真实任务。" };
}

export function providerOperationsTool(input: { repo: string; task_family?: TaskFamily; readiness_entries?: RecordValue[] }) {
  const checklist = readJson(getRuntimeDataPath("provider-onboarding-checklist.json"));
  const contractPath = getRuntimeContractPath();
  const contractHash = existsSync(contractPath) ? createHash("sha256").update(readFileSync(contractPath)).digest("hex") : "";
  const profiles = capabilityProfilesTool({ repo: input.repo }).profiles;
  const readiness = input.readiness_entries ?? readReadiness();
  const providers = ["qoder", "codebuddy"].map((provider) => {
    const adapter = readJson(getRuntimeDataPath(path.join("provider-adapters", `${provider}.json`)));
    const providerProfiles = profiles.filter((profile) => asString(profile.provider_tuple.provider) === provider && (!input.task_family || profile.task_family === input.task_family));
    const profile = [...providerProfiles].sort((left, right) => asString(right.evidence.at(-1)?.recorded_at).localeCompare(asString(left.evidence.at(-1)?.recorded_at))).at(0);
    const matchingReadiness = readiness.filter((entry) => asString(entry.provider) === provider && asString(entry.status) === "passed" && asString(entry.runtime_contract_sha256) === contractHash && hasCanaryEvidence(entry));
    const status = statusFor(profile, matchingReadiness);
    const accepted = asRecords(profile?.evidence).filter((item) => asString(item.verdict) === "accepted").length;
    return {
      provider,
      display_name: asString(adapter.display_name) || provider,
      user_status: status.status,
      next_action: status.next_action,
      task_family: input.task_family ?? "all",
      current_readiness_count: matchingReadiness.length,
      evidence_status: asString(profile?.status) || "unknown",
      accepted_attempt_count: accepted,
      recent_failure_class: asString(asRecords(profile?.evidence).at(-1)?.failure_class),
      adapter_contract_present: Object.keys(adapter).length > 0
    };
  });
  return {
    schema: "codex-praetor-provider-operations/v1",
    repo: input.repo,
    providers,
    onboarding_checklist: asRecords(checklist.required_checks).map((check) => ({ id: asString(check.id), label: asString(check.label), evidence: asString(check.evidence) })),
    extension_policy: asRecord(checklist.extension_policy),
    policy: { no_authentication_material_read: true, adapter_is_not_route_authorization: true, future_provider_requires_all_checks: true }
  };
}
