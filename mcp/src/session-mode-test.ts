import assert from "node:assert/strict";
import { mkdirSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import path from "node:path";
import { tmpdir } from "node:os";
import { spawnSync } from "node:child_process";
import { classifySessionModeCommand, routeIntent } from "./route-intent.js";
import { beginSessionModeClose, enableSessionMode, getSessionMode, resumeSessionMode, revokeSessionMode } from "./session-mode.js";
import { jobTimelineTool, resultTool } from "./tools.js";

const temporaryRoot = mkdtempSync(path.join(tmpdir(), "codex-praetor-session-mode-"));
const repo = path.join(temporaryRoot, "repo");
const previousThread = process.env.CODEX_THREAD_ID;

try {
  const init = spawnSync("git", ["init", repo], { encoding: "utf8", windowsHide: true });
  assert.equal(init.status, 0, init.stderr);
  process.env.CODEX_THREAD_ID = "session-mode-test-thread";

  const first = enableSessionMode(repo);
  assert.equal(first.already_active, false);
  assert.equal(first.view.context, "active");
  const policyPath = path.join(repo, ".codex-praetor", "session-policies", first.policy.thread_id_sha256, "mode.json");
  const persisted = readFileSync(policyPath, "utf8");
  assert.equal(persisted.includes("session-mode-test-thread"), false, "Raw host thread IDs must never be persisted.");

  const repeated = enableSessionMode(repo);
  assert.equal(repeated.already_active, true);
  assert.equal(repeated.policy.mode_session_id, first.policy.mode_session_id);
  assert.equal(getSessionMode(repo).view.context, "active");
  assert.equal(routeIntent("修复这个测试", false, "active").route, "codex_praetor_external_worker");
  assert.equal(routeIntent("不要外派，Codex 自己做", false, "active").route, "codex_retains_ineligible_work");
  assert.equal(classifySessionModeCommand("开启 Codex 执行官模式"), "enable");
  assert.equal(classifySessionModeCommand("关闭执行官模式"), "disable");
  assert.equal(classifySessionModeCommand("执行官模式是什么？"), undefined);

  const jobDir = path.join(repo, ".codex-praetor", "jobs", "session-mode-redaction");
  mkdirSync(jobDir, { recursive: true });
  writeFileSync(path.join(jobDir, "job.json"), JSON.stringify({
    job_id: "session-mode-redaction",
    status: "running",
    provider: "codebuddy",
    notify_thread_id: "session-mode-test-thread",
    mode_session_id: first.policy.mode_session_id
  }), "utf8");
  const timeline = jobTimelineTool({ repo, job_id: "session-mode-redaction" });
  const result = resultTool({ repo, job_id: "session-mode-redaction", include_log_tails: false });
  if (!timeline.found || !timeline.meta || !result.found || !result.meta) {
    throw new Error("Redaction fixture job was not readable.");
  }
  assert.equal(Object.hasOwn(timeline.meta, "notify_thread_id"), false, "Timeline output must redact the raw host thread ID.");
  assert.equal(Object.hasOwn(result.meta, "notify_thread_id"), false, "Result output must redact the raw host thread ID.");

  const closing = beginSessionModeClose(repo);
  assert.equal(closing.view.state, "closing");
  assert.equal(getSessionMode(repo).view.context, "inactive", "A closing policy must block newly associated dispatches.");
  const resumed = resumeSessionMode(repo, first.policy.mode_session_id);
  assert.equal(resumed.view.context, "active");

  const revoked = revokeSessionMode(repo);
  assert.equal(revoked.view.state, "revoked");
  assert.equal(getSessionMode(repo).view.context, "inactive");
} finally {
  if (previousThread === undefined) delete process.env.CODEX_THREAD_ID;
  else process.env.CODEX_THREAD_ID = previousThread;
  rmSync(temporaryRoot, { recursive: true, force: true });
}

console.log("codex-praetor-session-mode test ok");
