import assert from "node:assert/strict";
import { buildWorkerTaskEnvelope, renderWorkerTaskEnvelope } from "./tools.js";

const input = {
  task_id: "label-only-regression",
  title: "候选验收：最小隔离代码改动",
  objective: "在 fixtures/answer.txt 写入 exactly: repaired，并运行 node test.js。",
  task_family: "bounded_code_change" as const,
  task_kind: "code_change" as const,
  mode: "edit" as const,
  acceptance: "answer.txt contains repaired and node test.js exits 0.",
  allowed_paths: ["fixtures/answer.txt"],
  forbidden_paths: [".git", "config"],
  required_checks: ["node test.js"],
  depends_on: [],
  base_commit: "a".repeat(40),
  immutable_paths: ["fixtures/test.js"],
  budget: { max_wall_seconds: 300 }
};

const first = buildWorkerTaskEnvelope(input);
const second = buildWorkerTaskEnvelope(input);
assert.equal(first.idempotency_key, second.idempotency_key, "same frozen contract must retain one idempotency key");
assert.equal(first.sha256, second.sha256, "same frozen contract must retain one envelope hash");
const rendered = renderWorkerTaskEnvelope(first);
assert.match(rendered, /OBJECTIVE:\n在 fixtures\/answer\.txt 写入 exactly: repaired/, "worker packet must contain the executable objective, not only the UI title");
assert.match(rendered, /ACCEPTANCE:\nanswer\.txt contains repaired/, "worker packet must retain acceptance");
assert.match(rendered, /ALLOWED PATHS: fixtures\/answer\.txt/, "worker packet must retain path boundaries");
assert.match(rendered, /REQUIRED CHECKS: node test\.js/, "worker packet must retain required checks");
assert.match(rendered, /DISPLAY TITLE \(not a substitute for the objective\):\n候选验收：最小隔离代码改动/, "title is present only as display metadata");
console.log("worker task envelope contract ok");
