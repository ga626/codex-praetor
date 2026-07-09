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
  "codex 执政官",
  "codex-praetor",
  "省钱模式",
  "便宜工人",
  "低成本派工",
  "薅羊毛模式",
  "免费 agent",
  "免费的 agent",
  "cheap worker",
  "cheap workers",
  "free agent",
  "free agents",
  "external worker",
  "external workers",
  "qoder",
  "codebuddy",
  "workbuddy",
  "mimo",
  "腾讯",
  "阿里",
  "小米"
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

function collectMatches(value: string, terms: string[]): string[] {
  const lower = value.toLowerCase();
  return terms.filter((term) => lower.includes(term.toLowerCase()));
}

export function routeIntent(
  request: string,
  allowNativeCodexSubagents = false
): RouteDecision {
  const trimmed = request.trim();
  if (!trimmed) {
    return {
      route: "needs_clarification",
      confidence: "high",
      reason: "The request is empty, so no delegation intent can be classified.",
      suggested_next_action: "Ask for the task and delegation goal.",
      matched_terms: [],
      native_codex_subagents_allowed: allowNativeCodexSubagents
    };
  }

  const subagentMatches = collectMatches(trimmed, codexSubagentTerms);
  const praetorMatches = collectMatches(trimmed, codexPraetorTerms);
  const delegationMatches = collectMatches(trimmed, delegationTerms);
  const allMatches = [...new Set([...subagentMatches, ...praetorMatches, ...delegationMatches])];

  if (subagentMatches.length > 0 && allowNativeCodexSubagents) {
    return {
      route: "native_codex_subagent",
      confidence: "high",
      reason: "The user explicitly mentioned native Codex subagents and allowed that route.",
      suggested_next_action: "Use native Codex subagents only if the task benefits from Codex-token parallelism.",
      matched_terms: allMatches,
      native_codex_subagents_allowed: allowNativeCodexSubagents
    };
  }

  if (subagentMatches.length > 0 && praetorMatches.length === 0) {
    return {
      route: "needs_clarification",
      confidence: "medium",
      reason: "The request mentions Codex subagents, but this tool does not dispatch native Codex subagents.",
      suggested_next_action: "Ask whether the user wants native Codex subagents or Codex Praetor external CLI workers.",
      matched_terms: allMatches,
      native_codex_subagents_allowed: allowNativeCodexSubagents
    };
  }

  if (praetorMatches.length > 0 || delegationMatches.length > 0) {
    const confidence = praetorMatches.length > 0 ? "high" : "medium";
    return {
      route: "codex_praetor_external_worker",
      confidence,
      reason:
        praetorMatches.length > 0
          ? "The request contains Codex Praetor, cost-saving, provider, or external-worker terms."
          : "The request asks for delegation to other agents; without explicit native Codex subagent wording, Codex Praetor is the safer cost-control route.",
      suggested_next_action: "Run codex_praetor_dispatch_dry_run before any real worker dispatch.",
      matched_terms: allMatches,
      native_codex_subagents_allowed: allowNativeCodexSubagents
    };
  }

  return {
    route: "no_delegation",
    confidence: "medium",
    reason: "No cost-saving, external-worker, or delegation terms were detected.",
    suggested_next_action: "Handle the task directly, or ask whether the user wants Codex Praetor delegation.",
    matched_terms: allMatches,
    native_codex_subagents_allowed: allowNativeCodexSubagents
  };
}
