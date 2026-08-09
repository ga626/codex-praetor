export type RouteKind =
  | "codex_praetor_external_worker"
  | "codex_retains_ineligible_work"
  | "codex_kr_primary_research"
  | "native_codex_subagent"
  | "no_delegation"
  | "needs_clarification";

export interface DecisionReceipt {
  schema: "codex-praetor-decision-receipt/v1";
  decision_receipt_id: string;
  executive_mode: "active" | "inactive";
  dispatch_state: "not_required" | "not_dispatched";
  selection_reason: string;
  next_required_tool: RouteDecision["next_required_tool"];
  blocking_reason?: string;
}

export interface RouteDecision {
  route: RouteKind;
  confidence: "high" | "medium" | "low";
  reason: string;
  suggested_next_action: string;
  /** Structured continuation contract: route is never the terminal state. */
  dispatch_required: boolean;
  next_required_tool:
    | "codex_praetor_plan"
    | "codex_praetor_dispatch_dry_run"
    | "codex_kr_primary_research"
    | "codex_direct"
    | "clarify";
  delegable_subtasks: string[];
  codex_reserved_tasks: string[];
  blocking_reason?: string;
  matched_terms: string[];
  native_codex_subagents_allowed: boolean;
  mode_context?: "inactive" | "active" | "unavailable";
  /**
   * A route receipt is deliberately transportable: the caller persists it in
   * the durable plan instead of pretending that an MCP stdio process has
   * access to the host conversation's memory.
   */
  decision_receipt: DecisionReceipt;
  research_authority?: "codex_kr_primary";
  worker_research_eligible?: boolean;
  suggested_worker_research_mode?: "none" | "candidate_discovery" | "independent_replication";
}

export interface ResearchContract {
  research_authority: "codex_kr_primary";
  worker_research_mode: "candidate_discovery" | "independent_replication";
  claim_scope: string[];
  source_scope: string[];
  evidence_acceptance: "supervisor_verified";
  freshness?: "" | "day" | "week" | "month" | "year";
}

export interface PowerShellResult {
  exitCode: number | null;
  stdout: string;
  stderr: string;
}

export interface JobSummary {
  job_id: string;
  provider: string;
  tier: string;
  model: string;
  mode: string;
  task_kind?: string;
  run_mode: string;
  status: string;
  created_at: string;
  updated_at: string;
  path: string;
  completion_path?: string;
}

export type LaneKind = "job" | "plan_task" | "lock";

export interface LaneSummary {
  lane_id: string;
  kind: LaneKind;
  repo: string;
  mode: string;
  provider: string;
  tier: string;
  model: string;
  status: string;
  title: string;
  job_id: string;
  plan_id: string;
  task_id: string;
  owner_thread_id: string;
  path: string;
  created_at: string;
  updated_at: string;
  active: boolean;
}
