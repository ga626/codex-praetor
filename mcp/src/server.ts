#!/usr/bin/env node
import { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { StdioServerTransport } from "@modelcontextprotocol/sdk/server/stdio.js";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { z } from "zod";
import {
  detectConflictsTool,
  dispatchDryRunTool,
  getLaneTool,
  listJobsTool,
  listLanesTool,
  planTool,
  routeIntentTool,
  statusTool
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
    version: "0.1.0-alpha"
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
    "codex_praetor_dispatch_dry_run",
    {
      title: "Dry-Run Codex Praetor Dispatch",
      description: "Call the existing PowerShell wrapper in dry-run mode and return the selected worker command and artifact paths.",
      annotations: readOnlyClosedWorld,
      inputSchema: {
        repo: z.string().min(1),
        task: z.string().min(1),
        provider: z.enum(["qoder", "codebuddy", "mimo"]),
        tier: z.string().optional(),
        mode: z.enum(["readonly", "edit"]).optional(),
        run_mode: z.enum(["blocking", "background"]).optional()
      }
    },
    async (input) => asJsonContent(await dispatchDryRunTool(input))
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
