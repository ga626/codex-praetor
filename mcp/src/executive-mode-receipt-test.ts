import assert from "node:assert/strict";
import { execFileSync } from "node:child_process";
import { mkdtempSync, rmSync, writeFileSync } from "node:fs";
import os from "node:os";
import path from "node:path";
import { executiveModeStatusTool, modelRoutingCatalogTool, preparePlanTaskTool, routeIntentTool } from "./tools.js";

const root = mkdtempSync(path.join(os.tmpdir(), "codex-praetor-executive-receipt-"));
const repo = path.join(root, "repo");

function run(args: string[]) {
  return execFileSync("git", args, { cwd: repo, encoding: "utf8", stdio: ["ignore", "pipe", "pipe"] });
}

try {
  execFileSync("git", ["init", "-q", repo], { encoding: "utf8" });
  run(["config", "user.email", "executive-receipt@example.invalid"]);
  run(["config", "user.name", "Codex Praetor test"]);
  writeFileSync(path.join(repo, "README.md"), "fixture\n", "utf8");
  run(["add", "README.md"]);
  run(["commit", "-qm", "fixture"]);
  const baseCommit = run(["rev-parse", "HEAD"]).trim();

  const active = routeIntentTool({ request: "修复 README 的错别字并验证。", executive_mode: "active" });
  assert.equal(active.route, "codex_praetor_external_worker");
  assert.equal(active.dispatch_required, true);
  assert.equal(active.decision_receipt.executive_mode, "active");
  assert.equal(active.decision_receipt.dispatch_state, "not_dispatched");

  const beforePlan = executiveModeStatusTool({ repo, decision_receipt: active.decision_receipt });
  assert.equal(beforePlan.status, "incomplete_before_dispatch");

  const prepared = await preparePlanTaskTool({
    repo,
    title: "Fix a bounded README typo",
    task_id: "fix-readme",
    task_family: "bounded_code_change",
    task_kind: "code_change",
    mode: "edit",
    acceptance: "The README edit is limited to the declared file and git diff --check passes.",
    allowed_paths: ["README.md"],
    forbidden_paths: [".git", "**/*auth*"],
    required_checks: ["git diff --check"],
    budget: { max_wall_seconds: 300 },
    base_commit: baseCommit,
    immutable_paths: ["README.md"],
    decision_receipt: active.decision_receipt,
    plan_id: "executive-receipt-fixture"
  });
  const preparedRecord = prepared as Record<string, unknown>;
  assert.equal(prepared.ok, true, String(preparedRecord.stderr ?? preparedRecord.message ?? ""));
  assert.equal(preparedRecord.dispatch_state, "plan_created_not_dispatched");

  const afterPlan = executiveModeStatusTool({ repo, decision_receipt: active.decision_receipt, plan_id: "executive-receipt-fixture", task_id: "fix-readme" });
  assert.equal(afterPlan.status, "incomplete_before_dispatch");

  const catalog = modelRoutingCatalogTool();
  assert.equal(catalog.schema, "codex-praetor-model-routing-catalog/v1");
  assert.ok(catalog.models.some((item) => item.model === "Qwen3.7-Plus" && item.status === "default"));
  assert.ok(catalog.models.some((item) => item.model === "Qwen3.8-Max" && item.status === "candidate"));
  assert.ok(catalog.models.some((item) => item.model === "Auto" && item.status === "blocked"));
  console.log("executive mode receipt regression ok");
} finally {
  rmSync(root, { recursive: true, force: true });
}
