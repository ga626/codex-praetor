#!/usr/bin/env node
import { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { StdioServerTransport } from "@modelcontextprotocol/sdk/server/stdio.js";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { z } from "zod";

const researchContractSchema = z.object({
  research_authority: z.literal("codex_kr_primary"),
  worker_research_mode: z.enum(["candidate_discovery", "independent_replication"]),
  claim_scope: z.array(z.string().min(1)).min(1),
  source_scope: z.array(z.string().min(1)).min(1),
  evidence_acceptance: z.literal("supervisor_verified"),
  freshness: z.enum(["", "day", "week", "month", "year"]).optional()
});

const boundedTaskBudgetSchema = z.object({
  max_turns: z.number().int().positive().max(80).optional(),
  max_wall_seconds: z.number().int().positive().max(86400).optional(),
  max_attempts: z.number().int().positive().max(10).optional(),
  max_cost: z.number().nonnegative().optional()
}).refine((budget) => Object.keys(budget).length > 0, "Budget must contain at least one explicit hard limit.");

const plannedTaskContractSchema = z.object({
  task_id: z.string().regex(/^[A-Za-z0-9][A-Za-z0-9_.-]*$/).optional(),
  title: z.string().min(1),
  task_family: z.enum(["read_only_diagnosis", "bounded_code_change", "fixed_test_execution", "failure_recovery"]),
  task_kind: z.enum(["local_audit", "test_execution", "code_change", "external_research_support"]),
  mode: z.enum(["readonly", "edit"]),
  acceptance: z.string().min(1),
  allowed_paths: z.array(z.string().min(1)).min(1),
  forbidden_paths: z.array(z.string().min(1)).min(1),
  required_checks: z.array(z.string().min(1)).min(1),
  budget: boundedTaskBudgetSchema,
  depends_on: z.array(z.string().regex(/^[A-Za-z0-9][A-Za-z0-9_.-]*$/)).optional(),
  failure_injection: z.string().optional(),
  sensitivity: z.string().optional(),
  base_commit: z.string().regex(/^[0-9a-f]{40}$/i).optional(),
  immutable_paths: z.array(z.string().min(1)).optional(),
  evidence_context: z.record(z.string(), z.unknown()).optional()
});
import {
  detectConflictsTool,
  cancelJobTool,
  capabilityProfilesTool,
  prepareEvaluationTool,
  evaluationSuiteTool,
  explainableRouteTool,
  providerOperationsTool,
  dispatchPlanTaskTool,
  dispatchDryRunTool,
  dispatchTool,
  getLaneTool,
  healthTool,
  governanceSummaryTool,
  supervisionTool,
  startStageTool,
  recordProgressTool,
  requestHandoverTool,
  setReadinessLeaseTool,
  recordObservationTool,
  jobTimelineTool,
  nextReadyTool,
  resultTool,
  listJobsTool,
  listLanesTool,
  planTool,
  routeIntentTool,
  runtimeInfoTool,
  statusTool,
  verifyTaskTool,
  verifyEvaluationTaskTool
} from "./tools.js";

const readOnlyClosedWorld = {
  readOnlyHint: true,
  destructiveHint: false,
  idempotentHint: true,
  openWorldHint: false
};

const additiveProjectLocalWrite = {
  readOnlyHint: false,
  destructiveHint: false,
  idempotentHint: false,
  openWorldHint: false
};

function asJsonContent(value: unknown) {
  return {
    content: [
      {
        type: "text" as const,
        text: JSON.stringify(value, null, 2)
      }
    ]
  };
}

export function createServer(): McpServer {
  const server = new McpServer({
    name: "codex-praetor",
    version: "0.16.4-alpha"
  });

  server.registerTool(
    "codex_praetor_capability_profiles",
    {
      title: "Read Codex Praetor Capability Profiles",
      description: "Derive conservative provider-tuple and task-family capability profiles from immutable local attempts and Codex verdicts. This does not change routing.",
      annotations: readOnlyClosedWorld,
      inputSchema: {
        repo: z.string().min(1),
        include_unclassified: z.boolean().optional()
      }
    },
    async (input) => asJsonContent(capabilityProfilesTool(input))
  );

  server.registerTool(
    "codex_praetor_evaluation_suite",
    {
      title: "Read Codex Praetor Real Task Evaluation Suite",
      description: "Read the bounded real-task contracts used to prepare disposable evaluation worktrees. This does not dispatch a worker or change routing.",
      annotations: readOnlyClosedWorld,
      inputSchema: {}
    },
    async () => asJsonContent(evaluationSuiteTool())
  );

  server.registerTool(
    "codex_praetor_prepare_evaluation",
    {
      title: "Prepare Codex Praetor Real Task Evaluation",
      description: "Create a classified, project-local evaluation plan from the bundled suite. This does not dispatch a worker or change routing.",
      annotations: additiveProjectLocalWrite,
      inputSchema: {
        repo: z.string().min(1),
        plan_id: z.string().min(1).optional()
      }
    },
    async (input) => asJsonContent(await prepareEvaluationTool(input))
  );

  server.registerTool(
    "codex_praetor_explainable_route",
    {
      title: "Explain Codex Praetor Route Recommendation",
      description: "Explain a conservative external-worker recommendation from current hard gates and exact capability evidence. This is dry-run advice only and never dispatches, merges, or publishes.",
      annotations: readOnlyClosedWorld,
      inputSchema: {
        repo: z.string().min(1),
        task_family: z.enum(["read_only_diagnosis", "bounded_code_change", "fixed_test_execution", "failure_recovery"]),
        failure_class: z.enum(["provider_risk_control", "provider_auth_required", "provider_cli_missing", "provider_rejected", "provider_output_unparseable", "worker_process_failed", "worker_exit_code_unavailable", "permission_denied", "worker_timed_out", "network_timeout", "rate_limited", "provider_unavailable", "max_turns_exceeded", "test_failed", "scope_violation", "unknown"]).optional(),
        candidates: z.array(z.object({
          provider: z.enum(["qoder", "codebuddy"]),
          model: z.string().min(1),
          cli_path: z.string().min(1),
          cli_hash: z.string().min(1),
          permission_profile: z.string().min(1),
          task_kind: z.string().min(1),
          generation_id: z.string().min(1),
          runtime_contract_sha256: z.string().min(1),
          task_contract_schema: z.string().min(1),
          hard_gates: z.object({
            model_allowed: z.boolean(),
            permission_granted: z.boolean(),
            scope_allowed: z.boolean(),
            readiness_current: z.boolean(),
            user_authorized: z.boolean(),
            budget_allowed: z.boolean()
          }),
          estimated_cost: z.number().nonnegative().optional(),
          estimated_minutes: z.number().nonnegative().optional()
        })).min(1)
      }
    },
    async (input) => asJsonContent(explainableRouteTool(input))
  );

  server.registerTool(
    "codex_praetor_provider_operations",
    {
      title: "Read Codex Praetor Provider Operations",
      description: "Show user-readable Qoder and CodeBuddy availability, evidence freshness, next recovery action and the provider onboarding checklist. This never reads authentication material or dispatches a worker.",
      annotations: readOnlyClosedWorld,
      inputSchema: {
        repo: z.string().min(1),
        task_family: z.enum(["read_only_diagnosis", "bounded_code_change", "fixed_test_execution", "failure_recovery"]).optional()
      }
    },
    async (input) => asJsonContent(providerOperationsTool(input))
  );

  server.registerTool(
    "codex_praetor_route_intent",
    {
      title: "Route Codex Praetor Intent",
      description: "Classify whether a delegation request should use Codex Praetor external workers or native Codex subagents.",
      annotations: readOnlyClosedWorld,
      inputSchema: {
        request: z.string().min(1),
        repo: z.string().optional(),
        allow_native_codex_subagents: z.boolean().optional()
      }
    },
    async (input) => asJsonContent(routeIntentTool(input))
  );

  server.registerTool(
    "codex_praetor_runtime_info",
    {
      title: "Read Codex Praetor Runtime Contract",
      description: "Show the installed runtime contract version and expected MCP surface before dispatch.",
      annotations: readOnlyClosedWorld,
      inputSchema: {}
    },
    async () => asJsonContent(runtimeInfoTool())
  );

  server.registerTool(
    "codex_praetor_health",
    {
      title: "Check Codex Praetor Health",
      description: "Check install generation, plugin cache, provider readiness, and runtime contract without dispatching a worker.",
      annotations: readOnlyClosedWorld,
      inputSchema: {
        repo: z.string().min(1)
      }
    },
    async (input) => asJsonContent(await healthTool(input))
  );

  server.registerTool(
    "codex_praetor_dispatch_dry_run",
    {
      title: "Dry-Run Codex Praetor Dispatch",
      description: "Call the existing PowerShell wrapper in dry-run mode and return the selected worker command and artifact paths.",
      annotations: readOnlyClosedWorld,
      inputSchema: {
        repo: z.string().min(1),
        task: z.string().min(1),
        provider: z.enum(["auto", "qoder", "codebuddy"]),
        tier: z.string().optional(),
        mode: z.enum(["readonly", "edit"]).optional(),
        run_mode: z.enum(["blocking", "background"]).optional(),
        task_kind: z.enum(["local_audit", "test_execution", "code_change", "external_research_support"]).optional(),
        research_contract: researchContractSchema.optional()
      }
    },
    async (input) => asJsonContent(await dispatchDryRunTool(input))
  );

  server.registerTool(
    "codex_praetor_dispatch",
    {
      title: "Dispatch Codex Praetor Worker",
      description: "Start a real Codex Praetor worker job only after the exact task family has qualified capability evidence; return job metadata for later Codex verification.",
      annotations: additiveProjectLocalWrite,
      inputSchema: {
        repo: z.string().min(1),
        task: z.string().min(1),
        provider: z.enum(["auto", "qoder", "codebuddy"]).optional(),
        tier: z.string().optional(),
        mode: z.enum(["readonly", "edit"]).optional(),
        run_mode: z.enum(["blocking", "background"]).optional(),
        task_kind: z.enum(["local_audit", "test_execution", "code_change", "external_research_support"]).optional(),
        task_family: z.enum(["read_only_diagnosis", "bounded_code_change", "fixed_test_execution", "failure_recovery"]),
        research_contract: researchContractSchema.optional(),
        plan_id: z.string().optional(),
        task_id: z.string().optional(),
        depends_on: z.string().optional(),
        acceptance: z.string().optional(),
        worktree_name: z.string().optional(),
        real_worktree: z.boolean().optional(),
        base_commit: z.string().regex(/^[0-9a-f]{40}$/i).optional(),
        immutable_paths: z.array(z.string().min(1)).optional(),
        allowed_paths: z.array(z.string().min(1)).min(1).optional(),
        forbidden_paths: z.array(z.string().min(1)).min(1).optional(),
        required_checks: z.array(z.string().min(1)).min(1).optional(),
        budget: boundedTaskBudgetSchema.optional(),
        failure_injection: z.string().optional(),
        max_turns: z.number().int().positive().max(80).optional(),
        no_notify: z.boolean().optional()
      }
    },
    async (input) => asJsonContent(await dispatchTool(input))
  );

  server.registerTool(
    "codex_praetor_plan",
    {
      title: "Create Codex Praetor Plan",
      description: "Create a durable, dispatchable Codex Praetor plan whose tasks carry explicit scope, checks, budget, and acceptance contracts.",
      annotations: additiveProjectLocalWrite,
      inputSchema: {
        repo: z.string().min(1),
        title: z.string().min(1),
        tasks: z.array(plannedTaskContractSchema).min(1),
        plan_id: z.string().optional()
      }
    },
    async (input) => asJsonContent(await planTool(input))
  );

  server.registerTool(
    "codex_praetor_list_jobs",
    {
      title: "List Codex Praetor Jobs",
      description: "List compact job metadata from the project-local Codex Praetor job root.",
      annotations: readOnlyClosedWorld,
      inputSchema: {
        repo: z.string().min(1),
        status: z.enum(["active", "completed", "failed", "all"]).optional(),
        limit: z.number().int().positive().max(100).optional()
      }
    },
    async (input) => asJsonContent(listJobsTool(input))
  );

  server.registerTool(
    "codex_praetor_list_lanes",
    {
      title: "List Codex Praetor Lanes",
      description: "List compact derived lane state from project-local jobs, plans, and repo edit locks.",
      annotations: readOnlyClosedWorld,
      inputSchema: {
        repo: z.string().min(1),
        status: z.enum(["active", "completed", "failed", "blocked", "all"]).optional(),
        limit: z.number().int().positive().max(100).optional()
      }
    },
    async (input) => asJsonContent(listLanesTool(input))
  );

  server.registerTool(
    "codex_praetor_result",
    {
      title: "Read Codex Praetor Worker Result",
      description: "Read one worker job's compact result, log tails, and failure classification without dumping full logs.",
      annotations: readOnlyClosedWorld,
      inputSchema: {
        repo: z.string().min(1),
        job_id: z.string().min(1),
        include_log_tails: z.boolean().optional(),
        max_log_chars: z.number().int().positive().max(60000).optional()
      }
    },
    async (input) => asJsonContent(resultTool(input))
  );

  server.registerTool(
    "codex_praetor_job_timeline",
    {
      title: "Read Codex Praetor Job Timeline",
      description: "Show the worker, task contract, durable lifecycle state, and next Codex action for one job.",
      annotations: readOnlyClosedWorld,
      inputSchema: {
        repo: z.string().min(1),
        job_id: z.string().min(1)
      }
    },
    async (input) => asJsonContent(jobTimelineTool(input))
  );

  server.registerTool(
    "codex_praetor_cancel_job",
    {
      title: "Cancel Codex Praetor Job",
      description: "Cancel one durable worker job by its job identity and terminate its worker process tree.",
      annotations: additiveProjectLocalWrite,
      inputSchema: {
        repo: z.string().min(1),
        job_id: z.string().min(1)
      }
    },
    async (input) => asJsonContent(await cancelJobTool(input))
  );

  server.registerTool(
    "codex_praetor_get_lane",
    {
      title: "Read Codex Praetor Lane",
      description: "Read one compact Codex Praetor lane by lane id.",
      annotations: readOnlyClosedWorld,
      inputSchema: {
        repo: z.string().min(1),
        lane_id: z.string().min(1)
      }
    },
    async (input) => asJsonContent(getLaneTool(input))
  );

  server.registerTool(
    "codex_praetor_detect_conflicts",
    {
      title: "Detect Codex Praetor Conflicts",
      description: "Check whether a proposed readonly or edit lane conflicts with active project-local lanes or edit locks.",
      annotations: readOnlyClosedWorld,
      inputSchema: {
        repo: z.string().min(1),
        mode: z.enum(["readonly", "edit"]).optional(),
        lane_id: z.string().optional(),
        file_scope: z.array(z.string().min(1)).optional()
      }
    },
    async (input) => asJsonContent(detectConflictsTool(input))
  );

  server.registerTool(
    "codex_praetor_status",
    {
      title: "Read Codex Praetor Status",
      description: "Read compact status for a Codex Praetor job or plan without dumping full logs.",
      annotations: readOnlyClosedWorld,
      inputSchema: {
        repo: z.string().min(1),
        job_id: z.string().optional(),
        plan_id: z.string().optional()
      }
    },
    async (input) => asJsonContent(statusTool(input))
  );

  server.registerTool(
    "codex_praetor_governance_summary",
    {
      title: "Read Governance Summary",
      description: "Read a compact task, outcome, progress, release-state, and needs-decision summary without dumping the ledger or logs.",
      annotations: readOnlyClosedWorld,
      inputSchema: {
        repo: z.string().min(1),
        plan_id: z.string().min(1)
      }
    },
    async (input) => asJsonContent(governanceSummaryTool(input))
  );

  server.registerTool(
    "codex_praetor_supervision",
    {
      title: "Read Codex Praetor Supervision State",
      description: "Read stages, readiness leases, handovers, and low-frequency lifecycle observations for a plan. This never starts or monitors a worker.",
      annotations: readOnlyClosedWorld,
      inputSchema: { repo: z.string().min(1), plan_id: z.string().min(1) }
    },
    async (input) => asJsonContent(supervisionTool(input))
  );

  server.registerTool(
    "codex_praetor_start_stage",
    {
      title: "Start a Codex Praetor Stage",
      description: "Record a Codex-defined stage and checkpoint boundary in the durable plan. This does not dispatch a worker.",
      annotations: additiveProjectLocalWrite,
      inputSchema: { repo: z.string().min(1), plan_id: z.string().min(1), stage_id: z.string().min(1), title: z.string().min(1) }
    },
    async (input) => asJsonContent(await startStageTool(input))
  );

  server.registerTool(
    "codex_praetor_record_progress",
    {
      title: "Record Material Progress",
      description: "Record a material evidence checkpoint, saturation, input wait, safety stop, or verification transition. This is a durable supervisor record, not high-frequency worker polling.",
      annotations: additiveProjectLocalWrite,
      inputSchema: {
        repo: z.string().min(1), plan_id: z.string().min(1), task_id: z.string().min(1), stage_id: z.string().min(1),
        kind: z.enum(["evidence_added", "progress_saturated", "awaiting_input", "safety_stop", "verification_started", "verification_finished"]),
        summary: z.string().min(1), checkpoint: z.record(z.string(), z.unknown()).optional()
      }
    },
    async (input) => asJsonContent(await recordProgressTool(input))
  );

  server.registerTool(
    "codex_praetor_request_handover",
    {
      title: "Request Codex Praetor Handover",
      description: "Put one task into needs-decision with a durable reason and checkpoint. It does not cancel a running worker; cancellation remains a separate formal action.",
      annotations: additiveProjectLocalWrite,
      inputSchema: { repo: z.string().min(1), plan_id: z.string().min(1), task_id: z.string().min(1), reason: z.string().min(1), checkpoint: z.record(z.string(), z.unknown()).optional() }
    },
    async (input) => asJsonContent(await requestHandoverTool(input))
  );

  server.registerTool(
    "codex_praetor_set_readiness_lease",
    {
      title: "Record Codex Praetor Readiness Lease",
      description: "Project an already verified readiness tuple into the plan so the supervisor can reuse it until expiry. This never reads or changes provider authentication.",
      annotations: additiveProjectLocalWrite,
      inputSchema: {
        repo: z.string().min(1), plan_id: z.string().min(1),
        lease: z.object({ lease_id: z.string().min(1), provider: z.string().min(1), cli_hash: z.string().min(1), permission_profile: z.string().min(1), workspace: z.string().min(1), generation_id: z.string().min(1), expires_at: z.string().datetime(), state: z.enum(["ready", "stale", "blocked"]) }).passthrough()
      }
    },
    async (input) => asJsonContent(await setReadinessLeaseTool(input))
  );

  server.registerTool(
    "codex_praetor_record_observation",
    {
      title: "Record Codex Praetor Lifecycle Observation",
      description: "Record one lifecycle timestamp and evidence pointer for paired Codex-direct or supervised worker work. It never dispatches a worker or polls logs.",
      annotations: additiveProjectLocalWrite,
      inputSchema: {
        repo: z.string().min(1), plan_id: z.string().min(1), task_id: z.string().min(1),
        phase: z.enum(["codex_direct_started", "codex_direct_evidence", "route_completed", "plan_completed", "dry_run_completed", "dispatch_submitted", "worker_started", "worker_terminal", "verification_finished", "recovery_started", "recovery_finished"]),
        pair_id: z.string().optional(), transport_mode: z.enum(["", "codex_direct", "supervised_cli_text", "supervised_cli_json", "supervised_cli_stream_json", "qoder_acp", "qoder_sdk", "codebuddy_daemon"]).optional(),
        evidence: z.record(z.string(), z.unknown()).optional(), observed_at: z.string().datetime().optional()
      }
    },
    async (input) => asJsonContent(await recordObservationTool(input))
  );

  server.registerTool(
    "codex_praetor_next_ready",
    {
      title: "List Codex Praetor Ready Plan Tasks",
      description: "Read pending plan tasks whose dependencies have passed Codex verification.",
      annotations: readOnlyClosedWorld,
      inputSchema: {
        repo: z.string().min(1),
        plan_id: z.string().min(1),
        limit: z.number().int().positive().max(100).optional()
      }
    },
    async (input) => asJsonContent(await nextReadyTool(input))
  );

  server.registerTool(
    "codex_praetor_dispatch_plan_task",
    {
      title: "Dispatch Codex Praetor Plan Task",
      description: "Start a real worker for one pending plan task and connect the resulting job back to the durable plan.",
      annotations: additiveProjectLocalWrite,
      inputSchema: {
        repo: z.string().min(1),
        plan_id: z.string().min(1),
        task_id: z.string().min(1),
        provider: z.enum(["auto", "qoder", "codebuddy"]).optional(),
        tier: z.string().optional(),
        run_mode: z.enum(["blocking", "background"]).optional(),
        max_turns: z.number().int().positive().max(80).optional(),
        no_notify: z.boolean().optional(),
        dry_run: z.boolean().optional()
      }
    },
    async (input) => asJsonContent(await dispatchPlanTaskTool(input))
  );

  server.registerTool(
    "codex_praetor_verify_evaluation_task",
    {
      title: "Independently Verify Codex Praetor Evaluation Task",
      description: "Verify supplied task material, immutable files, write-set boundaries, and required checks in a worker worktree. This returns evidence only and never records Codex acceptance.",
      annotations: readOnlyClosedWorld,
      inputSchema: {
        repo: z.string().min(1),
        plan_id: z.string().min(1),
        task_id: z.string().min(1),
        worktree: z.string().min(1)
      }
    },
    async (input) => asJsonContent(await verifyEvaluationTaskTool(input))
  );

  server.registerTool(
    "codex_praetor_verify_task",
    {
      title: "Record Codex Praetor Task Verification",
      description: "Record Codex's verification verdict for a worker-completed plan task; dependencies advance only after accepted.",
      annotations: additiveProjectLocalWrite,
      inputSchema: {
        repo: z.string().min(1),
        plan_id: z.string().min(1),
        task_id: z.string().min(1),
        verdict: z.enum(["accepted", "rejected", "retry", "human_required", "skipped"]),
        summary: z.string().min(1),
        next_action: z.string().optional()
      }
    },
    async (input) => asJsonContent(await verifyTaskTool(input))
  );

  return server;
}

async function main() {
  const server = createServer();
  await server.connect(new StdioServerTransport());
}

const currentModulePath = fileURLToPath(import.meta.url);
const invokedModulePath = process.argv[1] ? path.resolve(process.argv[1]) : "";

if (currentModulePath === invokedModulePath) {
  main().catch((error) => {
    console.error(error);
    process.exit(1);
  });
}
