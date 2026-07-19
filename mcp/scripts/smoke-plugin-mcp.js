#!/usr/bin/env node
import { Client } from "@modelcontextprotocol/sdk/client/index.js";
import { StdioClientTransport } from "@modelcontextprotocol/sdk/client/stdio.js";
import path from "node:path";
import { fileURLToPath } from "node:url";

const scriptDir = path.dirname(fileURLToPath(import.meta.url));
const mcpRoot = path.resolve(scriptDir, "..");
const projectRoot = path.resolve(mcpRoot, "..");
const runtimePath = path.resolve(process.argv[2] ?? path.join(projectRoot, "plugin", "mcp", "dist", "server.js"));
const repo = path.resolve(process.argv[3] ?? projectRoot);
const expectedVersionIndex = process.argv.indexOf("--expected-version");
const expectedVersion = expectedVersionIndex >= 0 ? process.argv[expectedVersionIndex + 1] : "";
const skipDryRun =
  process.argv.includes("--skip-dry-run") || process.env.CODEX_PRAETOR_SKIP_PROVIDER_DRY_RUN === "1";

const requiredTools = [
  "codex_praetor_route_intent",
  "codex_praetor_runtime_info",
  "codex_praetor_dispatch_dry_run",
  "codex_praetor_dispatch",
  "codex_praetor_plan",
  "codex_praetor_list_jobs",
  "codex_praetor_list_lanes",
  "codex_praetor_get_lane",
  "codex_praetor_result",
  "codex_praetor_detect_conflicts",
  "codex_praetor_status",
  "codex_praetor_next_ready",
  "codex_praetor_dispatch_plan_task",
  "codex_praetor_verify_task"
];

const expectedReadOnlyTools = [
  "codex_praetor_route_intent",
  "codex_praetor_dispatch_dry_run",
  "codex_praetor_list_jobs",
  "codex_praetor_list_lanes",
  "codex_praetor_get_lane",
  "codex_praetor_result",
  "codex_praetor_detect_conflicts",
  "codex_praetor_status",
  "codex_praetor_next_ready"
];

const client = new Client({
  name: "codex-praetor-plugin-smoke",
  version: "0.0.0"
});

const transport = new StdioClientTransport({
  command: "node",
  args: [runtimePath],
  cwd: path.dirname(path.dirname(runtimePath))
});

try {
  await client.connect(transport);

  const tools = await client.listTools();
  const toolNames = tools.tools.map((tool) => tool.name);
  const missingTools = requiredTools.filter((toolName) => !toolNames.includes(toolName));
  if (missingTools.length > 0) {
    throw new Error(`Missing MCP tools: ${missingTools.join(", ")}`);
  }

  for (const toolName of expectedReadOnlyTools) {
    const tool = tools.tools.find((candidate) => candidate.name === toolName);
    if (tool?.annotations?.readOnlyHint !== true || tool.annotations.openWorldHint !== false) {
      throw new Error(`Missing safe read-only annotations on MCP tool: ${toolName}`);
    }
  }

  const planTool = tools.tools.find((candidate) => candidate.name === "codex_praetor_plan");
  if (planTool?.annotations?.readOnlyHint !== false || planTool.annotations.destructiveHint !== false) {
    throw new Error("Missing additive non-destructive annotations on MCP tool: codex_praetor_plan");
  }
  for (const toolName of ["codex_praetor_dispatch", "codex_praetor_dispatch_plan_task", "codex_praetor_verify_task"]) {
    const tool = tools.tools.find((candidate) => candidate.name === toolName);
    if (tool?.annotations?.readOnlyHint !== false || tool.annotations.destructiveHint !== false) {
      throw new Error(`Missing additive non-destructive annotations on MCP tool: ${toolName}`);
    }
  }

  const routeResult = await client.callTool({
    name: "codex_praetor_route_intent",
    arguments: {
      request: "开省钱模式，把任务分配给其他便宜 agent",
      repo
    }
  });
  const routePayload = JSON.parse(routeResult.content?.[0]?.text ?? "{}");
  if (routePayload.route !== "codex_praetor_external_worker") {
    throw new Error(`Unexpected route intent: ${routePayload.route}`);
  }

  const runtimeInfoResult = await client.callTool({
    name: "codex_praetor_runtime_info",
    arguments: {}
  });
  const runtimeInfoPayload = JSON.parse(runtimeInfoResult.content?.[0]?.text ?? "{}");
  if (
    !runtimeInfoPayload.runtime_contract ||
    !/^[0-9a-f]{64}$/.test(runtimeInfoPayload.runtime_identity?.runtime_contract_sha256 ?? "") ||
    !Number.isInteger(runtimeInfoPayload.runtime_identity?.process_id) ||
    runtimeInfoPayload.runtime_identity.process_id <= 0 ||
    !runtimeInfoPayload.contract_path ||
    !runtimeInfoPayload.runtime_identity?.project_root
  ) {
    throw new Error(`Runtime identity is incomplete: ${JSON.stringify(runtimeInfoPayload)}`);
  }
  if (expectedVersion) {
    const contractVersion = runtimeInfoPayload.runtime_contract?.version;
    const serverVersion = typeof client.getServerVersion === "function" ? client.getServerVersion()?.version : "";
    if (contractVersion !== expectedVersion || serverVersion !== expectedVersion) {
      throw new Error(`Packaged MCP version mismatch: contract=${contractVersion} server=${serverVersion} expected=${expectedVersion}`);
    }
  }

  if (!skipDryRun) {
    const dryRunResult = await client.callTool({
      name: "codex_praetor_dispatch_dry_run",
      arguments: {
        repo,
        task: "Plugin MCP smoke dry-run. Do not modify files.",
        provider: "mimo",
        tier: "mimo-isolated-audit",
        mode: "readonly",
        run_mode: "blocking"
      }
    });
    const dryRunPayload = JSON.parse(dryRunResult.content?.[0]?.text ?? "{}");
    if (dryRunPayload.ok !== true || dryRunPayload.provider !== "mimo") {
      throw new Error(`Unexpected dispatch dry-run result: ${JSON.stringify(dryRunPayload)}`);
    }
  }

  const lanesResult = await client.callTool({
    name: "codex_praetor_list_lanes",
    arguments: {
      repo,
      status: "all",
      limit: 10
    }
  });
  const lanesPayload = JSON.parse(lanesResult.content?.[0]?.text ?? "{}");
  if (!Array.isArray(lanesPayload.lanes)) {
    throw new Error(`Unexpected list lanes result: ${JSON.stringify(lanesPayload)}`);
  }

  const readonlyConflictResult = await client.callTool({
    name: "codex_praetor_detect_conflicts",
    arguments: {
      repo,
      mode: "readonly"
    }
  });
  const readonlyConflictPayload = JSON.parse(readonlyConflictResult.content?.[0]?.text ?? "{}");
  if (readonlyConflictPayload.ok !== true || readonlyConflictPayload.conflict_count !== 0) {
    throw new Error(`Unexpected readonly conflict result: ${JSON.stringify(readonlyConflictPayload)}`);
  }

  const editConflictResult = await client.callTool({
    name: "codex_praetor_detect_conflicts",
    arguments: {
      repo,
      mode: "edit",
      file_scope: ["mcp/src/tools.ts"]
    }
  });
  const editConflictPayload = JSON.parse(editConflictResult.content?.[0]?.text ?? "{}");
  if (typeof editConflictPayload.conflict_count !== "number" || !Array.isArray(editConflictPayload.conflicts)) {
    throw new Error(`Unexpected edit conflict result: ${JSON.stringify(editConflictPayload)}`);
  }

  console.log("plugin mcp protocol smoke ok");
} finally {
  await client.close();
}
