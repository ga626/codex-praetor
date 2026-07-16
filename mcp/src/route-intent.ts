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
  const researchMatches = collectMatches(trimmed, externalResearchTerms);
  const allMatches = [...new Set([...subagentMatches, ...praetorMatches, ...delegationMatches, ...researchMatches])];
  const rejectsNative = subagentMatches.length > 0 && rejectsNativeCodexSubagents(trimmed);

  if (researchMatches.length > 0) {
    const workerEligible = delegationMatches.length > 0 || praetorMatches.length > 0;
    return {
      route: "codex_kr_primary_research",
      confidence: "high",
      reason:
        "Codex and KnowledgeRadar own the research route, evidence authority, conflict resolution, and final synthesis. External workers may only provide bounded candidate discovery or independent replication under a Codex research contract.",
      suggested_next_action: workerEligible
        ? "Create a Codex/KR research route first, then dispatch only a readonly worker research-support contract with supervisor-verified evidence acceptance."
        : "Use KnowledgeRadar from Codex to establish the primary evidence route before considering any worker support.",
      matched_terms: allMatches,
      native_codex_subagents_allowed: allowNativeCodexSubagents,
      research_authority: "codex_kr_primary",
      worker_research_eligible: workerEligible,
      suggested_worker_research_mode: workerEligible ? "candidate_discovery" : "none"
    };
  }

  if (rejectsNative && (praetorMatches.length > 0 || delegationMatches.length > 0)) {
    return {
      route: "codex_praetor_external_worker",
      confidence: "high",
      reason:
        "The request asks for delegation while explicitly rejecting native Codex subagents, so Codex Praetor external workers are the intended route.",
      suggested_next_action: "Run codex_praetor_dispatch_dry_run before any real worker dispatch.",
      matched_terms: allMatches,
      native_codex_subagents_allowed: allowNativeCodexSubagents
    };
  }

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
