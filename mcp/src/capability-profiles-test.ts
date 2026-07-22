import assert from "node:assert/strict";
import { mkdtempSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import os from "node:os";
import path from "node:path";
import { capabilityProfilesTool } from "./capability-profiles.js";

type AttemptInput = {
  id: string;
  model: string;
  family: string;
  verdict?: string;
  failure?: string;
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
    created_at: now,
    finished_at: now
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
    { task_id: "blocked", task_family: "bounded_code_change", governance_state: "blocked", attempts: [attempt({ id: "b1", model: "blocked", family: "bounded_code_change", failure: "provider_risk_control" })] },
    { task_id: "cooldown", task_family: "bounded_code_change", governance_state: "rejected", attempts: [attempt({ id: "c1", model: "cooldown", family: "bounded_code_change", failure: "network_timeout" })] },
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
  assert.equal(withoutUnclassified.profiles.some((item) => item.provider_tuple.model === "unclassified"), false);
  assert.equal(readFileSync(planPath, "utf8"), initial, "profile projection must not rewrite the ledger");

  const withUnclassified = capabilityProfilesTool({ repo: root, include_unclassified: true });
  assert.equal(profileFor(withUnclassified, "unclassified").status, "observed");
  assert.equal(withUnclassified.profiles.length, 6);

  const projectRoot = path.resolve(process.cwd(), "..");
  for (const name of ["qoder", "codebuddy", "mimo"]) {
    const adapter = JSON.parse(readFileSync(path.join(projectRoot, "config", "provider-adapters", `${name}.json`), "utf8"));
    assert.equal(adapter.schema, "codex-praetor-provider-adapter/v1");
    assert.equal(adapter.provider_id, name);
    assert.ok(Array.isArray(adapter.models.allowed) && adapter.models.allowed.length > 0);
    assert.ok(Array.isArray(adapter.permissions.mappings) && adapter.permissions.mappings.length > 0);
    assert.deepEqual(adapter.permissions.minimum_canaries, ["local_audit", "code_change"]);
    assert.ok(adapter.lifecycle.launch && adapter.lifecycle.parse_terminal_state && adapter.lifecycle.cleanup);
    assert.ok(adapter.evidence.fixture && adapter.evidence.end_to_end && adapter.evidence.documentation);
  }
  assert.equal(withoutUnclassified.profiles.some((item) => item.provider_tuple.provider === "qoder"), false, "adapter presence must not imply route eligibility");
  console.log("codex-praetor capability profile contract test ok");
} finally {
  rmSync(root, { recursive: true, force: true });
}
