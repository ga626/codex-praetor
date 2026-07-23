import assert from "node:assert/strict";
import { createHash } from "node:crypto";
import { mkdtempSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import os from "node:os";
import path from "node:path";
import { capabilityProfilesTool } from "./capability-profiles.js";
import { explainableRouteTool } from "./explainable-routing.js";
import { providerOperationsTool } from "./provider-operations.js";

type AttemptInput = {
  id: string;
  model: string;
  family: string;
  verdict?: string;
  failure?: string;
  recordedAt?: string;
};

const now = "2026-07-22T00:00:00.000Z";

function attempt(input: AttemptInput) {
  return {
    attempt_id: input.id,
    provider_tuple: {
      provider: "fixture",
      cli_path: "fixture-cli",
      cli_hash: "fixture-hash",
      model: input.model,
      permission_profile: "fixture-worktree-v1",
      task_kind: "code_change",
      generation_id: "fixture-generation",
      runtime_contract_sha256: "a".repeat(64),
      task_contract_schema: "fixture/v1"
    },
    supervisor_verdict: input.verdict ?? "",
    failure_class: input.failure ?? "",
    evidence_state: input.failure ? "evidence_missing" : "tests_passed",
    created_at: input.recordedAt ?? now,
    finished_at: input.recordedAt ?? now
  };
}

function profileFor(result: ReturnType<typeof capabilityProfilesTool>, model: string) {
  const profile = result.profiles.find((item) => item.provider_tuple.model === model);
  assert.ok(profile, `profile missing for ${model}`);
  return profile;
}

const root = mkdtempSync(path.join(os.tmpdir(), "codex-praetor-capability-profile-"));
const planDir = path.join(root, ".codex-praetor", "plans", "fixture");
const planPath = path.join(planDir, "plan.json");

try {
  const tasks = [
    { task_id: "observed", task_family: "bounded_code_change", governance_state: "accepted", attempts: [attempt({ id: "o1", model: "observed", family: "bounded_code_change", verdict: "accepted" })] },
    { task_id: "provisional", task_family: "bounded_code_change", governance_state: "accepted", attempts: [attempt({ id: "p1", model: "provisional", family: "bounded_code_change", verdict: "accepted" }), attempt({ id: "p2", model: "provisional", family: "bounded_code_change", verdict: "accepted" })] },
    { task_id: "qualified", task_family: "bounded_code_change", governance_state: "accepted", attempts: [attempt({ id: "q1", model: "qualified", family: "bounded_code_change", verdict: "accepted" }), attempt({ id: "q2", model: "qualified", family: "bounded_code_change", verdict: "accepted" }), attempt({ id: "q3", model: "qualified", family: "bounded_code_change", verdict: "accepted" })] },
    { task_id: "blocked", task_family: "bounded_code_change", governance_state: "blocked", attempts: [attempt({ id: "b1", model: "blocked", family: "bounded_code_change", failure: "provider_rejected" })] },
    { task_id: "cooldown", task_family: "bounded_code_change", governance_state: "rejected", attempts: [attempt({ id: "c1", model: "cooldown", family: "bounded_code_change", failure: "network_timeout", recordedAt: new Date().toISOString() })] },
    { task_id: "stale", task_family: "bounded_code_change", governance_state: "accepted", attempts: [attempt({ id: "s1", model: "stale", family: "bounded_code_change", verdict: "accepted", recordedAt: "2025-01-01T00:00:00.000Z" })] },
    { task_id: "unclassified", governance_state: "accepted", attempts: [attempt({ id: "u1", model: "unclassified", family: "unclassified", verdict: "accepted" })] }
  ];
  const plan = { schema: "codex-praetor-task-ledger/v2", plan_id: "fixture", tasks };
  const initial = JSON.stringify(plan, null, 2);
  await import("node:fs/promises").then(({ mkdir }) => mkdir(planDir, { recursive: true }));
  writeFileSync(planPath, initial, "utf8");

  const withoutUnclassified = capabilityProfilesTool({ repo: root });
  assert.equal(withoutUnclassified.schema, "codex-praetor-capability-profile-set/v1");
  assert.equal(withoutUnclassified.policy.default_routing_changed, false);
  assert.equal(profileFor(withoutUnclassified, "observed").status, "observed");
  assert.equal(profileFor(withoutUnclassified, "provisional").status, "provisional");
  assert.equal(profileFor(withoutUnclassified, "qualified").status, "qualified");
  assert.equal(profileFor(withoutUnclassified, "blocked").status, "blocked");
  assert.equal(profileFor(withoutUnclassified, "cooldown").status, "cooling_down");
  assert.equal(profileFor(withoutUnclassified, "stale").status, "stale");
  assert.equal(withoutUnclassified.profiles.some((item) => item.provider_tuple.model === "unclassified"), false);
  assert.equal(readFileSync(planPath, "utf8"), initial, "profile projection must not rewrite the ledger");

  const withUnclassified = capabilityProfilesTool({ repo: root, include_unclassified: true });
  assert.equal(profileFor(withUnclassified, "unclassified").status, "observed");
  assert.equal(withUnclassified.profiles.length, 7);

  const candidateFor = (model: string) => ({
    provider: "fixture",
    model,
    cli_path: "fixture-cli",
    cli_hash: "fixture-hash",
    permission_profile: "fixture-worktree-v1",
    task_kind: "code_change",
    generation_id: "fixture-generation",
    runtime_contract_sha256: "a".repeat(64),
    task_contract_schema: "fixture/v1",
    hard_gates: { model_allowed: true, permission_granted: true, scope_allowed: true, readiness_current: true, user_authorized: true, budget_allowed: true }
  });
  const explained = explainableRouteTool({
    repo: root,
    task_family: "bounded_code_change",
    candidates: [candidateFor("qualified"), candidateFor("blocked"), candidateFor("observed")],
    failure_class: "network_timeout"
  });
  assert.equal(explained.decision, "recommend_existing");
  assert.equal(explained.recommendation?.provider_tuple.model, "qualified");
  assert.equal(explained.recovery.state, "cooling_down");
  assert.equal(explained.candidates.some((item) => item.candidate.model === "blocked" && item.viable), false);
  const validationOnly = explainableRouteTool({ repo: root, task_family: "bounded_code_change", candidates: [candidateFor("observed")], failure_class: "test_failed" });
  assert.equal(validationOnly.decision, "bounded_validation");
  assert.equal(validationOnly.recovery.state, "rejected");
  const processFailed = explainableRouteTool({ repo: root, task_family: "bounded_code_change", candidates: [candidateFor("observed")], failure_class: "worker_process_failed" });
  assert.equal(processFailed.recovery.state, "blocked");

  const operations = providerOperationsTool({ repo: root, task_family: "bounded_code_change", readiness_entries: [] });
  assert.equal(operations.schema, "codex-praetor-provider-operations/v1");
  assert.deepEqual(operations.providers.map((item) => item.provider), ["qoder", "codebuddy"]);
  assert.equal(operations.policy.adapter_is_not_route_authorization, true);
  assert.ok(operations.onboarding_checklist.length >= 6);

  const projectRoot = path.resolve(process.cwd(), "..");
  const contractHash = createHash("sha256").update(readFileSync(path.join(projectRoot, "config", "runtime-contract.json"))).digest("hex");
  const legacyReadiness = providerOperationsTool({ repo: root, readiness_entries: [{ provider: "qoder", status: "passed", runtime_contract_sha256: contractHash }] });
  assert.equal(legacyReadiness.providers.find((item) => item.provider === "qoder")?.current_readiness_count, 0, "legacy readiness without a worker receipt must not authorize a provider");
  const evidencedReadiness = providerOperationsTool({ repo: root, readiness_entries: [{ provider: "qoder", status: "passed", runtime_contract_sha256: contractHash, evidence: { schema: "codex-praetor-canary-evidence/v1", job_id: "fixture", worker_stdout_sha256: "a", completion_sha256: "b", completion_status: "process_exited", worker_exit_code: 0, failure_class: "" } }] });
  assert.equal(evidencedReadiness.providers.find((item) => item.provider === "qoder")?.current_readiness_count, 1, "a complete canary receipt must remain observable");
  for (const name of ["qoder", "codebuddy"]) {
    const adapter = JSON.parse(readFileSync(path.join(projectRoot, "config", "provider-adapters", `${name}.json`), "utf8"));
    assert.equal(adapter.schema, "codex-praetor-provider-adapter/v1");
    assert.equal(adapter.provider_id, name);
    assert.ok(Array.isArray(adapter.models.allowed) && adapter.models.allowed.length > 0);
    assert.ok(Array.isArray(adapter.permissions.mappings) && adapter.permissions.mappings.length > 0);
    assert.deepEqual(adapter.permissions.minimum_canaries, ["local_audit", "test_execution", "code_change"]);
    assert.ok(adapter.lifecycle.launch && adapter.lifecycle.parse_terminal_state && adapter.lifecycle.cleanup);
    assert.ok(adapter.evidence.fixture && adapter.evidence.end_to_end && adapter.evidence.documentation);
  }
  assert.equal(withoutUnclassified.profiles.some((item) => item.provider_tuple.provider === "qoder"), false, "adapter presence must not imply route eligibility");
  console.log("codex-praetor capability profile contract test ok");
} finally {
  rmSync(root, { recursive: true, force: true });
}
