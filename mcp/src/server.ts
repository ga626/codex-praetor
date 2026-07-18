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
import {
  detectConflictsTool,
  cancelJobTool,
  dispatchPlanTaskTool,
  dispatchDryRunTool,
  dispatchTool,
  getLaneTool,
  healthTool,
  jobTimelineTool,
  nextReadyTool,
  resultTool,
  listJobsTool,
  listLanesTool,
  planTool,
  routeIntentTool,
  runtimeInfoTool,
  statusTool,
  verifyTaskTool
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
    version: "0.4.2-alpha"
  });

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
        provider: z.enum(["auto", "qoder", "codebuddy", "mimo"]),
        tier: z.string().optional(),
        mode: z.enum(["readonly", "edit"]).optional(),
        run_mode: z.enum(["blocking", "background"]).optional(),
        task_kind: z.enum(["local_audit", "code_change", "external_research_support"]).optional(),
        research_contract: researchContractSchema.optional()
      }
    },
    async (input) => asJsonContent(await dispatchDryRunTool(input))
  );

  server.registerTool(
    "codex_praetor_dispatch",
    {
      title: "Dispatch Codex Praetor Worker",
      description: "Start a real Codex Praetor worker job through the existing dispatcher and return job metadata for later Codex verification.",
      annotations: additiveProjectLocalWrite,
      inputSchema: {
        repo: z.string().min(1),
        task: z.string().min(1),
        provider: z.enum(["auto", "qoder", "codebuddy", "mimo"]).optional(),
        tier: z.string().optional(),
        mode: z.enum(["readonly", "edit"]).optional(),
        run_mode: z.enum(["blocking", "background"]).optional(),
        task_kind: z.enum(["local_audit", "code_change", "external_research_support"]).optional(),
        research_contract: researchContractSchema.optional(),
        plan_id: z.string().optional(),
        task_id: z.string().optional(),
        depends_on: z.string().optional(),
        acceptance: z.string().optional(),
        worktree_name: z.string().optional(),
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
      description: "Create a small durable Codex Praetor plan under the project-local artifact root.",
      annotations: additiveProjectLocalWrite,
      inputSchema: {
        repo: z.string().min(1),
        title: z.string().min(1),
        tasks: z.array(z.string().min(1)).min(1),
        mode: z.enum(["readonly", "edit"]).optional(),
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
        provider: z.enum(["auto", "qoder", "codebuddy", "mimo"]).optional(),
        tier: z.string().optional(),
        mode: z.enum(["readonly", "edit"]).optional(),
        run_mode: z.enum(["blocking", "background"]).optional(),
        max_turns: z.number().int().positive().max(80).optional(),
        no_notify: z.boolean().optional()
      }
    },
    async (input) => asJsonContent(await dispatchPlanTaskTool(input))
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
