export type RouteKind =
  | "codex_praetor_external_worker"
  | "codex_kr_primary_research"
  | "native_codex_subagent"
  | "no_delegation"
  | "needs_clarification";

export interface RouteDecision {
  route: RouteKind;
  confidence: "high" | "medium" | "low";
  reason: string;
  suggested_next_action: string;
  matched_terms: string[];
  native_codex_subagents_allowed: boolean;
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
