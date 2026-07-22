import { capabilityProfilesTool } from "./capability-profiles.js";

type TaskFamily = "read_only_diagnosis" | "bounded_code_change" | "fixed_test_execution" | "failure_recovery";
type FailureClass = "provider_risk_control" | "provider_auth_required" | "provider_cli_missing" | "provider_rejected" | "provider_output_unparseable" | "permission_denied" | "worker_timed_out" | "network_timeout" | "rate_limited" | "provider_unavailable" | "max_turns_exceeded" | "test_failed" | "scope_violation" | "unknown";

export type ExplainableRouteCandidate = {
  provider: string;
  model: string;
  cli_path: string;
  cli_hash: string;
  permission_profile: string;
  task_kind: string;
  generation_id: string;
  runtime_contract_sha256: string;
  task_contract_schema: string;
  hard_gates: {
    model_allowed: boolean;
    permission_granted: boolean;
    scope_allowed: boolean;
    readiness_current: boolean;
    user_authorized: boolean;
    budget_allowed: boolean;
  };
  estimated_cost?: number;
  estimated_minutes?: number;
};

function asString(value: unknown): string {
  return typeof value === "string" ? value : "";
}

function sameTuple(left: Record<string, unknown>, right: ExplainableRouteCandidate): boolean {
  return ["provider", "model", "cli_path", "cli_hash", "permission_profile", "task_kind", "generation_id", "runtime_contract_sha256", "task_contract_schema"]
    .every((key) => asString(left[key]) === right[key as keyof ExplainableRouteCandidate]);
}

function recoveryFor(failureClass: FailureClass) {
  if (["provider_risk_control", "provider_auth_required", "provider_cli_missing", "provider_rejected", "provider_output_unparseable"].includes(failureClass)) {
    return { state: "blocked", automatic_retry: false, action: "停止自动重试；等待官方登录、风控解除、CLI 修复或重新 canary。", preserve_worktree: false };
  }
  if (["network_timeout", "rate_limited", "provider_unavailable", "worker_timed_out"].includes(failureClass)) {
    return { state: "cooling_down", automatic_retry: "at_most_2", backoff_minutes: [5, 15], action: "仅对明确短暂故障做两次有界退避；仍失败则冷却并交回 Codex。", preserve_worktree: false };
  }
  if (failureClass === "permission_denied") {
    return { state: "needs_smaller_packet", automatic_retry: false, action: "缩小工作包或修正最小权限后重新 canary；不得一键放宽权限。", preserve_worktree: false };
  }
  if (failureClass === "max_turns_exceeded") {
    return { state: "needs_codex_decision", automatic_retry: false, action: "保留 worktree；由 Codex 决定缩小任务、合理加预算、换合格候选或接管。", preserve_worktree: true };
  }
  if (["test_failed", "scope_violation"].includes(failureClass)) {
    return { state: "rejected", automatic_retry: false, action: "测试或范围检查失败，拒绝该结果并计入任务族质量证据；不得用 worker 解释覆盖检查。", preserve_worktree: true };
  }
  return { state: "human_review", automatic_retry: false, action: "未知失败先由 Codex 读取证据并归类，不自动改派。", preserve_worktree: true };
}

export function explainableRouteTool(input: {
  repo: string;
  task_family: TaskFamily;
  candidates: ExplainableRouteCandidate[];
  failure_class?: FailureClass;
}) {
  const profileSet = capabilityProfilesTool({ repo: input.repo });
  const evaluations = input.candidates.map((candidate) => {
    const profile = profileSet.profiles.find((item) => item.task_family === input.task_family && sameTuple(item.provider_tuple, candidate));
    const failedGates = Object.entries(candidate.hard_gates).filter(([, passed]) => !passed).map(([name]) => name);
    const profileStatus = profile?.status ?? "unknown";
    const profileEligible = ["provisional", "qualified"].includes(profileStatus);
    const profileBlocked = ["blocked", "cooling_down", "stale"].includes(profileStatus);
    const acceptedEvidence = (profile?.evidence ?? []).filter((item) => item.verdict === "accepted");
    const viable = failedGates.length === 0 && profileEligible && !profileBlocked;
    const score = viable
      ? (profileStatus === "qualified" ? 300 : 200) + acceptedEvidence.length * 10 - (candidate.estimated_cost ?? 0) - (candidate.estimated_minutes ?? 0) / 100
      : -1;
    const reasons: string[] = [];
    if (failedGates.length > 0) reasons.push(`硬门未通过：${failedGates.join("、")}。`);
    if (!profile) reasons.push("没有与当前 provider tuple 完全一致的任务族证据。")
    else {
      reasons.push(`画像为 ${profileStatus}：${profile.status_reason}`);
      if (acceptedEvidence.length > 0) reasons.push(`最近可采信证据：${acceptedEvidence.at(-1)?.attempt_id ?? "未知 attempt"}。`);
    }
    if (!profileEligible && !profileBlocked && failedGates.length === 0) reasons.push("证据不足，只能建议小而可回退的验证任务。")
    return {
      candidate,
      profile_id: profile?.profile_id ?? "",
      profile_status: profileStatus,
      evidence: profile?.evidence ?? [],
      hard_gate_result: { passed: failedGates.length === 0, failed: failedGates },
      viable,
      score,
      explanation: reasons
    };
  });

  const ranked = [...evaluations].sort((left, right) => right.score - left.score || left.candidate.provider.localeCompare(right.candidate.provider));
  const primary = ranked.find((item) => item.viable) ?? null;
  const fallbacks = ranked.filter((item) => item.viable && item !== primary);
  const boundedValidation = primary === null && evaluations.some((item) => item.hard_gate_result.passed && !["blocked", "cooling_down", "stale"].includes(item.profile_status));
  const decision = primary ? "recommend_existing" : boundedValidation ? "bounded_validation" : "stop";

  return {
    schema: "codex-praetor-explainable-route/v1",
    repo: profileSet.repo,
    task_family: input.task_family,
    decision,
    recommendation: primary ? {
      provider_tuple: primary.candidate,
      why: primary.explanation,
      fallback_profile_ids: fallbacks.map((item) => item.profile_id),
      note: "这是一项建议，不会自动派工、合并或发布。"
    } : null,
    bounded_validation: boundedValidation ? "没有足够的新鲜采信证据；先执行一个小、可回退、同任务族的 canary。" : "不适用",
    candidates: ranked,
    recovery: recoveryFor(input.failure_class ?? "unknown"),
    policy: {
      hard_gates_authoritative: true,
      fallback_requires_same_task_family_and_current_evidence: true,
      automatic_merge_or_publish: false,
      profile_projection_is_not_authorization: true
    }
  };
}
