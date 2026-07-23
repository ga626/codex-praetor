#!/usr/bin/env node
import { Client } from "@modelcontextprotocol/sdk/client/index.js";
import { StdioClientTransport } from "@modelcontextprotocol/sdk/client/stdio.js";
import { createHash } from "node:crypto";
import { readFileSync, writeFileSync } from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const scriptDir = path.dirname(fileURLToPath(import.meta.url));
const mcpRoot = path.resolve(scriptDir, "..");
const projectRoot = path.resolve(mcpRoot, "..");
const runtimePath = path.resolve(process.argv[2] ?? path.join(projectRoot, "plugin", "mcp", "dist", "server.js"));
const repo = path.resolve(process.argv[3] ?? projectRoot);
const expectedVersionIndex = process.argv.indexOf("--expected-version");
const expectedVersion = expectedVersionIndex >= 0 ? process.argv[expectedVersionIndex + 1] : "";
const expectedContractIndex = process.argv.indexOf("--expected-contract");
const expectedContractPath = expectedContractIndex >= 0 ? path.resolve(process.argv[expectedContractIndex + 1]) : "";
const expectedGenerationIndex = process.argv.indexOf("--expected-generation");
const expectedGenerationPath = expectedGenerationIndex >= 0 ? path.resolve(process.argv[expectedGenerationIndex + 1]) : "";
const observedOutputIndex = process.argv.indexOf("--observed-tools-output");
const observedOutputPath = observedOutputIndex >= 0 ? path.resolve(process.argv[observedOutputIndex + 1]) : "";
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

function sameSet(left, right) {
  return left.length === right.length && left.every((item) => right.includes(item));
}

function readExpectedContract() {
  if (!expectedContractPath) return null;
  const bytes = readFileSync(expectedContractPath);
  return {
    path: expectedContractPath,
    sha256: createHash("sha256").update(bytes).digest("hex"),
    payload: JSON.parse(bytes.toString("utf8"))
  };
}

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
  const expectedContract = readExpectedContract();
  const expectedToolNames = expectedContract ? expectedContract.payload.requiredMcpTools : requiredTools;
  const missingTools = expectedToolNames.filter((toolName) => !toolNames.includes(toolName));
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
  if (expectedContract) {
    const contractTools = expectedContract.payload.requiredMcpTools;
    if (!sameSet([...toolNames].sort(), [...contractTools].sort())) {
      const missing = contractTools.filter((name) => !toolNames.includes(name));
      const extra = toolNames.filter((name) => !contractTools.includes(name));
      throw new Error(`MCP tool contract mismatch: missing=${missing.join(",")} extra=${extra.join(",")}`);
    }
    if (runtimeInfoPayload.runtime_identity?.runtime_contract_sha256 !== expectedContract.sha256) {
      throw new Error(`Runtime contract SHA256 mismatch: runtime=${runtimeInfoPayload.runtime_identity?.runtime_contract_sha256} expected=${expectedContract.sha256}`);
    }
    if (JSON.stringify(runtimeInfoPayload.runtime_contract) !== JSON.stringify(expectedContract.payload)) {
      throw new Error("Runtime contract payload differs from the canonical contract.");
    }
    if (expectedGenerationPath) {
      const generation = JSON.parse(readFileSync(expectedGenerationPath, "utf8"));
      if (generation.runtime_contract_sha256 !== expectedContract.sha256 || !sameSet([...(generation.required_mcp_tools ?? [])].sort(), [...contractTools].sort())) {
        throw new Error("Release generation manifest differs from the canonical runtime contract.");
      }
    }
  }

  const providerOperationsResult = await client.callTool({
    name: "codex_praetor_provider_operations",
    arguments: {
      repo,
      task_family: "bounded_code_change"
    }
  });
  const providerOperationsPayload = JSON.parse(providerOperationsResult.content?.[0]?.text ?? "{}");
  const expectedProviders = ["qoder", "codebuddy"];
  if (
    providerOperationsPayload.schema !== "codex-praetor-provider-operations/v1" ||
    !Array.isArray(providerOperationsPayload.providers) ||
    providerOperationsPayload.providers.length !== expectedProviders.length ||
    expectedProviders.some((provider) => !providerOperationsPayload.providers.some((item) => item?.provider === provider && item?.adapter_contract_present === true)) ||
    !Array.isArray(providerOperationsPayload.onboarding_checklist) ||
    providerOperationsPayload.onboarding_checklist.length < 6
  ) {
    throw new Error(`Packaged provider operations data is missing or invalid: ${JSON.stringify(providerOperationsPayload)}`);
  }

  const evaluationSuiteResult = await client.callTool({
    name: "codex_praetor_evaluation_suite",
    arguments: {}
  });
  const evaluationSuitePayload = JSON.parse(evaluationSuiteResult.content?.[0]?.text ?? "{}");
  if (
    evaluationSuitePayload.schema !== "codex-praetor-evaluation-suite-view/v1" ||
    !Array.isArray(evaluationSuitePayload.tasks) ||
    evaluationSuitePayload.tasks.length < 4 ||
    !String(evaluationSuitePayload.suite_path ?? "").replace(/\\/g, "/").endsWith("/data/evaluation-suite.json")
  ) {
    throw new Error(`Packaged evaluation suite data is missing or invalid: ${JSON.stringify(evaluationSuitePayload)}`);
  }
  if (observedOutputPath) {
    writeFileSync(observedOutputPath, `${JSON.stringify({
      schema: "codex-praetor-observed-runtime/v1",
      source: "final-artifact-bundled-mcp",
      tool_names: toolNames,
      runtime_info: runtimeInfoPayload
    }, null, 2)}\n`, "utf8");
  }

  if (!skipDryRun) {
    const dryRunResult = await client.callTool({
      name: "codex_praetor_dispatch_dry_run",
      arguments: {
        repo,
        task: "Plugin MCP smoke dry-run. Do not modify files.",
        provider: "qoder",
        tier: "qoder-day-cheap",
        mode: "readonly",
        run_mode: "blocking"
      }
    });
    const dryRunPayload = JSON.parse(dryRunResult.content?.[0]?.text ?? "{}");
    if (dryRunPayload.ok !== true || dryRunPayload.provider !== "qoder") {
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
