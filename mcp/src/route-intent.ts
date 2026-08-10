import { createHash } from "node:crypto";
import type { RouteDecision } from "./types.js";

const codexSubagentTerms = [
  "codex subagent",
  "codex sub-agent",
  "native codex subagent",
  "codex 子智能体",
  "codex子智能体",
  "codex 的 subagent",
  "codex自己的 sub agent",
  "codex 自己的 sub agent"
];

const codexPraetorTerms = [
  "codex praetor",
  "执政官模式",
  "执政官",
  "codex 执政官",
  "codex 执行官",
  "codex-praetor",
  "external worker",
  "external workers",
  "qoder",
  "codebuddy",
  "workbuddy",
];

const codexRetainTerms = [
  "不要外派",
  "不外派",
  "不要派工",
  "不派工",
  "自己做",
  "codex 自己做",
  "do not delegate",
  "keep this in codex"
];

const delegationTerms = [
  "split",
  "split up",
  "delegate",
  "assign",
  "dispatch",
  "distribute",
  "multi-agent",
  "multi agent",
  "other agent",
  "other agents",
  "拆分",
  "拆一下",
  "拆一下任务",
  "把任务拆一下",
  "拆分一下任务",
  "分配",
  "派给",
  "交给",
  "其他 agent",
  "其它 agent",
  "别的 agent",
  "外部 agent",
  "多个 agent",
  "多 agent",
  "多agent",
  "分工",
  "分派"
];

const externalResearchTerms = [
  "联网搜索",
  "外部调研",
  "事实核查",
  "来源发现",
  "knowledge radar",
  "knowledgeradar",
  "外网研究",
  "web research",
  "fact check"
];

function collectMatches(value: string, terms: string[]): string[] {
  const lower = value.toLowerCase();
  return terms.filter((term) => lower.includes(term.toLowerCase()));
}

function rejectsNativeCodexSubagents(value: string): boolean {
  const lower = value.toLowerCase();
  return [
    /不要.{0,16}codex.{0,8}sub-?\s*agent/i,
    /不.{0,8}(创建|使用|走|开).{0,16}codex.{0,8}sub-?\s*agent/i,
    /别.{0,8}(创建|使用|走|开).{0,16}codex.{0,8}sub-?\s*agent/i,
    /不要.{0,16}codex.{0,8}(子智能体|原生)/i,
    /do not.{0,16}codex.{0,8}sub-?\s*agent/i,
    /don't.{0,16}codex.{0,8}sub-?\s*agent/i,
    /not.{0,16}codex.{0,8}sub-?\s*agent/i
  ].some((pattern) => pattern.test(lower));
}

export function routeIntent(
  request: string,
  allowNativeCodexSubagents = false,
  executiveMode: "active" | "inactive" = "inactive"
): RouteDecision {
  // MCP stdio processes cannot inspect the host conversation.  The Skill
  // owns continuity and passes the explicit state on every substantive turn.
  const modeContext = executiveMode;
  const trimmed = request.trim();
  const withReceipt = (decision: Omit<RouteDecision, "decision_receipt">): RouteDecision => {
    const receiptSource = JSON.stringify({
      request: trimmed,
      executive_mode: executiveMode,
      route: decision.route,
      dispatch_required: decision.dispatch_required,
      next_required_tool: decision.next_required_tool,
      blocking_reason: decision.blocking_reason ?? ""
    });
    const decisionReceiptId = `route-${createHash("sha256").update(receiptSource).digest("hex").slice(0, 16)}`;
    return {
      ...decision,
      decision_receipt: {
        schema: "codex-praetor-decision-receipt/v1",
        decision_receipt_id: decisionReceiptId,
        executive_mode: executiveMode,
        dispatch_state: decision.dispatch_required ? "not_dispatched" : "not_required",
        selection_reason: decision.reason,
        next_required_tool: decision.next_required_tool,
        ...(decision.blocking_reason ? { blocking_reason: decision.blocking_reason } : {})
      }
    };
  };

  if (!trimmed) {
    return withReceipt({
      route: "needs_clarification",
      confidence: "high",
      reason: "The request is empty, so no delegation intent can be classified.",
      suggested_next_action: "Ask for the task and delegation goal.",
      dispatch_required: false,
      next_required_tool: "clarify",
      delegable_subtasks: [],
      codex_reserved_tasks: [],
      blocking_reason: "empty_request",
      matched_terms: [],
      native_codex_subagents_allowed: allowNativeCodexSubagents,
      mode_context: modeContext
    });
  }

  const subagentMatches = collectMatches(trimmed, codexSubagentTerms);
  const praetorMatches = collectMatches(trimmed, codexPraetorTerms);
  const delegationMatches = collectMatches(trimmed, delegationTerms);
  const researchMatches = collectMatches(trimmed, externalResearchTerms);
  const retainMatches = collectMatches(trimmed, codexRetainTerms);
  const allMatches = [...new Set([...subagentMatches, ...praetorMatches, ...delegationMatches, ...researchMatches, ...retainMatches])];
  const rejectsNative = subagentMatches.length > 0 && rejectsNativeCodexSubagents(trimmed);

  if (retainMatches.length > 0 && praetorMatches.length === 0 && delegationMatches.length === 0 && researchMatches.length === 0) {
    return withReceipt({
      route: "codex_retains_ineligible_work",
      confidence: "high",
      reason: "The request explicitly keeps the work in Codex, so Codex Praetor must not create a worker.",
      suggested_next_action: "Handle the task directly in Codex and do not call a dispatch tool.",
      dispatch_required: false,
      next_required_tool: "codex_direct",
      delegable_subtasks: [],
      codex_reserved_tasks: ["用户明确要求由 Codex 自己处理"],
      blocking_reason: "user_requested_codex_only",
      matched_terms: allMatches,
      native_codex_subagents_allowed: allowNativeCodexSubagents,
      mode_context: modeContext
    });
  }

  if (researchMatches.length > 0) {
    const workerEligible = delegationMatches.length > 0 || praetorMatches.length > 0;
    return withReceipt({
      route: "codex_kr_primary_research",
      confidence: "high",
      reason:
        "Codex and KnowledgeRadar own the research route, evidence authority, conflict resolution, and final synthesis. External workers may only provide bounded candidate discovery or independent replication under a Codex research contract.",
      suggested_next_action: workerEligible
        ? "Create a Codex/KR research route first, then dispatch only a readonly worker research-support contract with supervisor-verified evidence acceptance."
        : "Use KnowledgeRadar from Codex to establish the primary evidence route before considering any worker support.",
      dispatch_required: workerEligible,
      next_required_tool: "codex_kr_primary_research",
      delegable_subtasks: workerEligible ? ["只读候选来源发现或独立复核"] : [],
      codex_reserved_tasks: ["主证据检索、证据核验、冲突裁决和最终结论"],
      ...(workerEligible ? {} : { blocking_reason: "research_authority_must_remain_with_codex_kr" }),
      matched_terms: allMatches,
      native_codex_subagents_allowed: allowNativeCodexSubagents,
      mode_context: modeContext,
      research_authority: "codex_kr_primary",
      worker_research_eligible: workerEligible,
      suggested_worker_research_mode: workerEligible ? "candidate_discovery" : "none"
    });
  }

  if (rejectsNative && (praetorMatches.length > 0 || delegationMatches.length > 0)) {
    return withReceipt({
      route: "codex_praetor_external_worker",
      confidence: "high",
      reason:
        "The request asks for delegation while explicitly rejecting native Codex subagents, so Codex Praetor external workers are the intended route.",
      suggested_next_action: "Run codex_praetor_dispatch_dry_run before any real worker dispatch.",
      dispatch_required: true,
      next_required_tool: "codex_praetor_plan",
      delegable_subtasks: ["只读考古、固定测试、局部代码修改或受监督的研究辅助"],
      codex_reserved_tasks: ["任务拆分、敏感操作、结果整合和最终验收"],
      matched_terms: allMatches,
      native_codex_subagents_allowed: allowNativeCodexSubagents,
      mode_context: modeContext
    });
  }

  if (subagentMatches.length > 0 && allowNativeCodexSubagents) {
    return withReceipt({
      route: "native_codex_subagent",
      confidence: "high",
      reason: "The user explicitly mentioned native Codex subagents and allowed that route.",
      suggested_next_action: "Use native Codex subagents only if the task benefits from Codex-token parallelism.",
      dispatch_required: false,
      next_required_tool: "codex_direct",
      delegable_subtasks: [],
      codex_reserved_tasks: ["原生 Codex subagent 路线不由 Codex Praetor MCP 启动"],
      blocking_reason: "native_codex_subagent_is_outside_codex_praetor",
      matched_terms: allMatches,
      native_codex_subagents_allowed: allowNativeCodexSubagents,
      mode_context: modeContext
    });
  }

  if (subagentMatches.length > 0 && praetorMatches.length === 0) {
    return withReceipt({
      route: "needs_clarification",
      confidence: "medium",
      reason: "The request mentions Codex subagents, but this tool does not dispatch native Codex subagents.",
      suggested_next_action: "Ask whether the user wants native Codex subagents or Codex Praetor external CLI workers.",
      dispatch_required: false,
      next_required_tool: "clarify",
      delegable_subtasks: [],
      codex_reserved_tasks: [],
      blocking_reason: "native_route_not_authorized",
      matched_terms: allMatches,
      native_codex_subagents_allowed: allowNativeCodexSubagents,
      mode_context: modeContext
    });
  }

  if (executiveMode === "active" || praetorMatches.length > 0 || delegationMatches.length > 0) {
    const confidence = executiveMode === "active" || praetorMatches.length > 0 ? "high" : "medium";
    return withReceipt({
      route: "codex_praetor_external_worker",
      confidence,
      reason:
        executiveMode === "active"
          ? "执政官模式已显式开启。这个请求没有要求 Codex 独自处理，因此必须先把可独立验收的部分建立为计划并继续预演、派工；route 不能在这里结束。"
          : praetorMatches.length > 0
          ? "The request contains Codex Praetor, cost-saving, provider, or external-worker terms."
          : "The request asks for delegation to other agents; without explicit native Codex subagent wording, Codex Praetor is the safer cost-control route.",
      suggested_next_action: "Run codex_praetor_dispatch_dry_run before any real worker dispatch.",
      dispatch_required: true,
      next_required_tool: "codex_praetor_plan",
      delegable_subtasks: ["只读考古、固定测试、局部代码修改或受监督的研究辅助"],
      codex_reserved_tasks: ["任务拆分、敏感操作、结果整合和最终验收"],
      matched_terms: allMatches,
      native_codex_subagents_allowed: allowNativeCodexSubagents,
      mode_context: modeContext
    });
  }

  return withReceipt({
    route: "no_delegation",
    confidence: "medium",
    reason: "No cost-saving, external-worker, or delegation terms were detected.",
    suggested_next_action: "Handle the task directly, or ask whether the user wants Codex Praetor delegation.",
    dispatch_required: false,
    next_required_tool: "codex_direct",
    delegable_subtasks: [],
    codex_reserved_tasks: ["当前请求未表达外派意图"],
    blocking_reason: "no_delegation_intent",
    matched_terms: allMatches,
    native_codex_subagents_allowed: allowNativeCodexSubagents,
    mode_context: modeContext
  });
}

export function classifySessionModeCommand(request: string): "enable" | "disable" | undefined {
  const normalized = request.trim().toLowerCase();
  if (!normalized || /[?？]|什么是|如何|为什么|讨论|设计|介绍/.test(normalized)) return undefined;
  const modeMentioned = /codex\s*(执行官|执政官)模式|(执行官|执政官)模式/.test(normalized);
  if (!modeMentioned) return undefined;
  if (/^(请\s*)?(开启|打开|进入|启用)|接下来.*(使用|用).*(执行官|执政官)模式/.test(normalized)) return "enable";
  if (/^(请\s*)?(关闭|退出|停止|禁用)|不用.*(执行官|执政官)模式/.test(normalized)) return "disable";
  return undefined;
}
