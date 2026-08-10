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
  // Turn limits are accepted for historical task contracts only. Current
  // adapters supervise structured progress and a stall timeout instead.
  max_turns: z.number().int().positive().max(80).optional(),
  max_stall_seconds: z.number().int().min(30).max(86400).optional(),
  max_wall_seconds: z.number().int().positive().max(3600),
  max_attempts: z.number().int().positive().max(10).optional()
});

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
  evidence_context: z.record(z.string(), z.unknown()).optional(),
  validation_only: z.boolean().optional(),
  validation_reason: z.string().min(1).optional()
});

const decisionReceiptSchema = z.object({
  schema: z.literal("codex-praetor-decision-receipt/v1"),
  decision_receipt_id: z.string().min(1),
  executive_mode: z.enum(["active", "inactive"]),
  dispatch_state: z.enum(["not_required", "not_dispatched"]),
  selection_reason: z.string().min(1),
  next_required_tool: z.enum(["codex_praetor_plan", "codex_praetor_dispatch_dry_run", "codex_kr_primary_research", "codex_direct", "clarify"]),
  blocking_reason: z.string().optional()
});
import {
  detectConflictsTool,
  cancelJobTool,
  capabilityProfilesTool,
  prepareEvaluationTool,
  evaluationSuiteTool,
  executiveModeStatusTool,
  explainableRouteTool,
  providerOperationsTool,
  dispatchReadinessTool,
  dispatchPlanTaskTool,
  recoverPlanTaskWithAlternateProviderTool,
  dispatchDryRunTool,
  dispatchTool,
  getLaneTool,
  healthTool,
  governanceSummaryTool,
  jobTimelineTool,
  nextReadyTool,
  resultTool,
  listJobsTool,
  listLanesTool,
  modelRoutingCatalogTool,
  planTool,
  preparePlanTaskTool,
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

const structuredToolOutputSchema = z.object({}).passthrough();

function asJsonContent(value: unknown) {
  const structuredContent = value && typeof value === "object" && !Array.isArray(value)
    ? value as Record<string, unknown>
    : { result: value };
  const display = structuredContent.display && typeof structuredContent.display === "object" && !Array.isArray(structuredContent.display)
    ? structuredContent.display as Record<string, unknown>
    : {};
  const stage = String(display.阶段 ?? display.当前动作 ?? "操作结果");
  const state = String(display.状态 ?? structuredContent.ok ?? "已返回");
  const lines = [`【Codex 执政官｜${stage}】`, `状态：${state}`];
  for (const field of ["执行者", "模型", "连接", "模型依据", "原因", "下一步"]) {
    const value = display[field];
    if (typeof value === "string" && value.trim()) lines.push(`${field}：${value.trim()}`);
  }
  return {
    content: [
      {
        type: "text" as const,
        text: lines.join("\n")
      }
    ],
    structuredContent
  };
}

export function createServer(): McpServer {
  const server = new McpServer({
    name: "codex-praetor",
    version: "0.16.39-alpha",
    description: "Codex Praetor 让 Codex 监督 Qoder 和 CodeBuddy 外部 worker；对话中的执政官模式由 Skill 工作规范维护，Codex 始终负责拆分、验收与整合。"
  });

  server.registerTool(
    "codex_praetor_capability_profiles",
    {
      title: "读取 Codex Praetor 能力档案",
      description: "根据不可变的本地记录和 Codex 验收结论，读取保守的 provider tuple 与任务族能力档案；不会改变路由。",
      annotations: readOnlyClosedWorld,
      outputSchema: structuredToolOutputSchema,
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
      title: "读取 Codex Praetor 真实任务评测集",
      description: "读取用于准备一次性评测 worktree 的真实任务合同；不会派工或改变路由。",
      annotations: readOnlyClosedWorld,
      outputSchema: structuredToolOutputSchema,
      inputSchema: {}
    },
    async () => asJsonContent(evaluationSuiteTool())
  );

  server.registerTool(
    "codex_praetor_prepare_evaluation",
    {
      title: "准备 Codex Praetor 真实任务评测",
      description: "从内置评测集创建分类的项目内评测计划；不会派工或改变路由。",
      annotations: additiveProjectLocalWrite,
      outputSchema: structuredToolOutputSchema,
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
      title: "解释 Codex Praetor 路由建议",
      description: "依据当前硬门与精确能力证据解释外部 worker 建议；仅提供 dry-run 建议，不会派工、合并或发布。",
      annotations: readOnlyClosedWorld,
      outputSchema: structuredToolOutputSchema,
      inputSchema: {
        repo: z.string().min(1),
        task_family: z.enum(["read_only_diagnosis", "bounded_code_change", "fixed_test_execution", "failure_recovery"]),
        failure_class: z.enum(["provider_risk_control", "provider_auth_required", "provider_cli_missing", "provider_rejected", "provider_output_unparseable", "worker_process_failed", "worker_exit_code_unavailable", "permission_denied", "worker_timed_out", "network_timeout", "rate_limited", "provider_unavailable", "max_turns_exceeded", "progress_saturated", "test_failed", "scope_violation", "unknown"]).optional(),
        candidates: z.array(z.object({
          provider: z.enum(["qoder", "codebuddy"]),
          distribution: z.enum(["qoder_cn", "qoder_global", "codebuddy_cn"]),
          model: z.string().min(1),
          cli_path: z.string().min(1),
          cli_hash: z.string().min(1),
          permission_profile: z.string().min(1),
          task_kind: z.string().min(1),
          connection_mode: z.string().min(1),
          runner_identity: z.string().min(1),
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
      title: "读取 Codex Praetor provider 状态",
      description: "显示 Qoder 与 CodeBuddy 的可用性、证据新鲜度、恢复动作和接入清单；不会读取认证资料或派工。",
      annotations: readOnlyClosedWorld,
      outputSchema: structuredToolOutputSchema,
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
      title: "路由 Codex Praetor 任务意图",
      description: "判断任务意图并返回结构化继续合同。外部 worker 路由不是终点：除非存在明确 blocking_reason，否则必须按 next_required_tool 继续计划、预演和派工。",
      annotations: readOnlyClosedWorld,
      outputSchema: structuredToolOutputSchema,
      inputSchema: {
        request: z.string().min(1),
        repo: z.string().optional(),
        allow_native_codex_subagents: z.boolean().optional(),
        executive_mode: z.enum(["active", "inactive"]).optional()
      }
    },
    async (input) => asJsonContent(routeIntentTool(input))
  );

  server.registerTool(
    "codex_praetor_model_routing_catalog",
    {
      title: "读取 Codex Praetor 模型路由目录",
      description: "读取受跟踪的固定模型、价格快照状态和候选边界；不会读取账号余额、认证或自动切换模型。",
      annotations: readOnlyClosedWorld,
      outputSchema: structuredToolOutputSchema,
      inputSchema: {}
    },
    async () => asJsonContent(modelRoutingCatalogTool())
  );

  server.registerTool(
    "codex_praetor_prepare_plan_task",
    {
      title: "准备 Codex 执政官派工计划",
      description: "将 route receipt 与明确范围、预算、检查、验收标准写为一项 durable plan；只创建计划，不启动 worker。",
      annotations: additiveProjectLocalWrite,
      outputSchema: structuredToolOutputSchema,
      inputSchema: {
        repo: z.string().min(1),
        title: z.string().min(1),
        task_id: z.string().regex(/^[A-Za-z0-9][A-Za-z0-9_.-]*$/).optional(),
        task_family: z.enum(["read_only_diagnosis", "bounded_code_change", "fixed_test_execution", "failure_recovery"]),
        task_kind: z.enum(["local_audit", "test_execution", "code_change", "external_research_support"]),
        mode: z.enum(["readonly", "edit"]),
        acceptance: z.string().min(1),
        allowed_paths: z.array(z.string().min(1)).min(1),
        forbidden_paths: z.array(z.string().min(1)).min(1),
        required_checks: z.array(z.string().min(1)).min(1),
        budget: boundedTaskBudgetSchema,
        base_commit: z.string().regex(/^[0-9a-f]{40}$/i).optional(),
        immutable_paths: z.array(z.string().min(1)).optional(),
        failure_injection: z.string().optional(),
        sensitivity: z.string().optional(),
        decision_receipt: decisionReceiptSchema,
        plan_id: z.string().regex(/^[A-Za-z0-9][A-Za-z0-9_.-]*$/).optional()
      }
    },
    async (input) => asJsonContent(await preparePlanTaskTool(input))
  );

  server.registerTool(
    "codex_praetor_executive_mode_status",
    {
      title: "读取 Codex 执政官模式派工状态",
      description: "根据 route receipt 与可选 durable plan 显示尚未派工、worker 已启动或待验收状态；不会伪称 route 已完成就是派工。",
      annotations: readOnlyClosedWorld,
      outputSchema: structuredToolOutputSchema,
      inputSchema: {
        repo: z.string().min(1),
        decision_receipt: decisionReceiptSchema,
        plan_id: z.string().optional(),
        task_id: z.string().optional()
      }
    },
    async (input) => asJsonContent(executiveModeStatusTool(input))
  );

  server.registerTool(
    "codex_praetor_runtime_info",
    {
      title: "读取 Codex Praetor 运行时合同",
      description: "显示已安装的运行时合同版本和预期 MCP 工具面。",
      annotations: readOnlyClosedWorld,
      outputSchema: structuredToolOutputSchema,
      inputSchema: {}
    },
    async () => asJsonContent(runtimeInfoTool())
  );

  server.registerTool(
    "codex_praetor_health",
    {
      title: "检查 Codex Praetor 健康状态",
      description: "检查安装代际、插件缓存、provider readiness 与运行时合同；不会派工。",
      annotations: readOnlyClosedWorld,
      outputSchema: structuredToolOutputSchema,
      inputSchema: {
        repo: z.string().min(1)
      }
    },
    async (input) => asJsonContent(await healthTool(input))
  );

  server.registerTool(
    "codex_praetor_dispatch_dry_run",
    {
      title: "预演或预检 Codex Praetor 派工合同",
      description: "只读任务返回普通派工预演；代码修改任务可验证完整的真实 worktree 合同。两者都不会启动 worker。",
      annotations: readOnlyClosedWorld,
      outputSchema: structuredToolOutputSchema,
      inputSchema: {
        repo: z.string().min(1),
        task: z.string().min(1),
        provider: z.enum(["auto", "qoder", "codebuddy"]),
        tier: z.string().optional(),
        mode: z.enum(["readonly", "edit"]).optional(),
        run_mode: z.enum(["blocking", "background"]).optional(),
        task_kind: z.enum(["local_audit", "test_execution", "code_change", "external_research_support"]).optional(),
        task_family: z.enum(["read_only_diagnosis", "bounded_code_change", "fixed_test_execution", "failure_recovery"]).optional(),
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
        sensitivity: z.string().optional(),
        max_turns: z.number().int().positive().max(80).optional(),
        max_stall_seconds: z.number().int().min(30).max(86400).optional(),
        timeout_seconds: z.number().int().min(30).max(86400).optional()
      }
    },
    async (input) => asJsonContent(await dispatchDryRunTool(input))
  );

  server.registerTool(
    "codex_praetor_dispatch_readiness",
    {
      title: "检查本任务的精确派工就绪状态",
      description: "解析本次任务实际会使用的 provider、模型和连接，并只读判断它可直接派工、可由同一真实任务建立首用证据，还是被合同、认证或传输问题阻断；不会创建 job、worktree 或 worker。",
      annotations: readOnlyClosedWorld,
      outputSchema: structuredToolOutputSchema,
      inputSchema: {
        repo: z.string().min(1),
        task: z.string().min(1),
        provider: z.enum(["auto", "qoder", "codebuddy"]).optional(),
        tier: z.string().optional(),
        mode: z.enum(["readonly", "edit"]),
        task_kind: z.enum(["local_audit", "test_execution", "code_change", "external_research_support"]),
        task_family: z.enum(["read_only_diagnosis", "bounded_code_change", "fixed_test_execution", "failure_recovery"]),
        acceptance: z.string().min(1),
        allowed_paths: z.array(z.string().min(1)).min(1),
        forbidden_paths: z.array(z.string().min(1)).min(1),
        required_checks: z.array(z.string().min(1)).min(1),
        budget: boundedTaskBudgetSchema,
        base_commit: z.string().regex(/^[0-9a-f]{40}$/i).optional(),
        immutable_paths: z.array(z.string().min(1)).optional()
      }
    },
    async (input) => asJsonContent(await dispatchReadinessTool(input))
  );

  server.registerTool(
    "codex_praetor_dispatch",
    {
      title: "派发 Codex Praetor worker",
      description: "兼容的低层派工入口：真实 worker 必须已绑定 durable plan task。未绑定计划的调用会返回 use_dispatch_plan_task，绝不会把模式首用任务卡在通用 readiness gate。",
      annotations: additiveProjectLocalWrite,
      outputSchema: structuredToolOutputSchema,
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
        max_stall_seconds: z.number().int().min(30).max(86400).optional(),
        no_notify: z.boolean().optional()
      }
    },
    async (input) => asJsonContent(await dispatchTool(input))
  );

  server.registerTool(
    "codex_praetor_plan",
    {
      title: "创建 Codex Praetor 计划",
      description: "创建可持久化、可派发的 Codex Praetor 计划；每项任务都带明确范围、检查、预算和验收合同。",
      annotations: additiveProjectLocalWrite,
      outputSchema: structuredToolOutputSchema,
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
      title: "列出 Codex Praetor 任务",
      description: "从项目内 Codex Praetor 任务根目录读取精简任务元数据。",
      annotations: readOnlyClosedWorld,
      outputSchema: structuredToolOutputSchema,
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
      title: "列出 Codex Praetor 执行通道",
      description: "读取项目内任务、计划和仓库编辑锁推导出的精简通道状态。",
      annotations: readOnlyClosedWorld,
      outputSchema: structuredToolOutputSchema,
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
      title: "读取 Codex Praetor worker 结果",
      description: "读取一个 worker 任务的精简结果、日志尾部和失败分类，不倾倒完整日志。",
      annotations: readOnlyClosedWorld,
      outputSchema: structuredToolOutputSchema,
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
      title: "读取 Codex Praetor 任务时间线",
      description: "显示一个任务的 worker、任务合同、持久生命周期状态和 Codex 下一步。",
      annotations: readOnlyClosedWorld,
      outputSchema: structuredToolOutputSchema,
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
      title: "取消 Codex Praetor 任务",
      description: "按任务标识正式取消一个持久 worker 任务，并终止其进程树。",
      annotations: additiveProjectLocalWrite,
      outputSchema: structuredToolOutputSchema,
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
      title: "读取 Codex Praetor 执行通道",
      description: "按通道标识读取一条精简 Codex Praetor 执行通道。",
      annotations: readOnlyClosedWorld,
      outputSchema: structuredToolOutputSchema,
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
      title: "检测 Codex Praetor 冲突",
      description: "检查拟议的只读或编辑通道是否与项目内活跃通道或编辑锁冲突。",
      annotations: readOnlyClosedWorld,
      outputSchema: structuredToolOutputSchema,
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
      title: "读取 Codex Praetor 状态",
      description: "读取一个 Codex Praetor 任务或计划的精简状态，不倾倒完整日志。",
      annotations: readOnlyClosedWorld,
      outputSchema: structuredToolOutputSchema,
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
      title: "读取治理摘要",
      description: "读取任务、结果、进展、发布状态和待决事项的精简摘要，不倾倒 ledger 或日志。",
      annotations: readOnlyClosedWorld,
      outputSchema: structuredToolOutputSchema,
      inputSchema: {
        repo: z.string().min(1),
        plan_id: z.string().min(1)
      }
    },
    async (input) => asJsonContent(governanceSummaryTool(input))
  );

  server.registerTool(
    "codex_praetor_next_ready",
    {
      title: "列出 Codex Praetor 就绪计划任务",
      description: "读取依赖已通过 Codex 验收、可以派发的待执行计划任务。",
      annotations: readOnlyClosedWorld,
      outputSchema: structuredToolOutputSchema,
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
      title: "派发 Codex Praetor 计划任务",
      description: "为一个待执行计划任务启动真实 worker，并把结果任务关联回持久计划。",
      annotations: additiveProjectLocalWrite,
      outputSchema: structuredToolOutputSchema,
      inputSchema: {
        repo: z.string().min(1),
        plan_id: z.string().min(1),
        task_id: z.string().min(1),
        provider: z.enum(["auto", "qoder", "codebuddy"]).optional(),
        tier: z.string().optional(),
        run_mode: z.enum(["blocking", "background"]).optional(),
        max_turns: z.number().int().positive().max(80).optional(),
        max_stall_seconds: z.number().int().min(30).max(86400).optional(),
        no_notify: z.boolean().optional(),
        dry_run: z.boolean().optional()
      }
    },
    async (input) => asJsonContent(await dispatchPlanTaskTool(input))
  );

  server.registerTool(
    "codex_praetor_recover_plan_task",
    {
      title: "受控转交 Codex Praetor 计划任务",
      description: "仅对无 diff、无副作用且已记录为 provider_refusal_before_tool_use 的任务，透明记录一次 alternate-provider 转交；超时、网络不明或已有改动绝不自动重放。",
      annotations: additiveProjectLocalWrite,
      outputSchema: structuredToolOutputSchema,
      inputSchema: {
        repo: z.string().min(1),
        plan_id: z.string().min(1),
        task_id: z.string().min(1),
        run_mode: z.enum(["blocking", "background"]).optional(),
        max_turns: z.number().int().positive().max(80).optional(),
        max_stall_seconds: z.number().int().min(30).max(86400).optional(),
        no_notify: z.boolean().optional()
      }
    },
    async (input) => asJsonContent(await recoverPlanTaskWithAlternateProviderTool(input))
  );

  server.registerTool(
    "codex_praetor_verify_evaluation_task",
    {
      title: "独立验证 Codex Praetor 评测任务",
      description: "在 worker worktree 中验证任务材料、不可变文件、写入范围和必需检查；只返回证据，不记录 Codex 验收。",
      annotations: readOnlyClosedWorld,
      outputSchema: structuredToolOutputSchema,
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
      title: "记录 Codex Praetor 任务验收",
      description: "记录 Codex 对 worker 完成计划任务的验收结论；只有 accepted 才会推进依赖。",
      annotations: additiveProjectLocalWrite,
      outputSchema: structuredToolOutputSchema,
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
