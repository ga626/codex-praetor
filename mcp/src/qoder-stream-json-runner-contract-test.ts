import assert from "node:assert/strict";
import { spawn } from "node:child_process";
import { mkdirSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import os from "node:os";
import path from "node:path";

const root = path.join(os.tmpdir(), `codex-praetor-qoder-stream-${process.pid}-${Date.now()}`);
const runner = path.join(process.cwd(), "dist", "qoder-stream-json-runner.js");
const fakeCli = path.join(root, "fake-qoder.mjs");

const fakeCliSource = String.raw`
const mode = process.env.CP_FAKE_QODER_MODE;
if (mode === "queue") {
  let count = 101;
  setInterval(() => process.stdout.write(JSON.stringify({ type: "system", subtype: "model_queue_status", status: "queued", queue_type: "slow", queue_count: count++, queue_wait_elapsed_ms: 100, queue_max_wait_ms: 3600000, service_available: true }) + "\n"), 25);
} else {
  process.stdout.write(JSON.stringify({ type: "assistant" }) + "\n");
  process.stdout.write(JSON.stringify({ type: "result" }) + "\n");
}
`;

function run(mode: "queue" | "complete") {
  const job = path.join(root, mode);
  mkdirSync(job, { recursive: true });
  const statePath = path.join(job, "session.json");
  const optionsPath = path.join(job, "options.json");
  writeFileSync(optionsPath, JSON.stringify({
    schema: "codex-praetor-qoder-stream-json-runner/v1",
    job_id: mode,
    cwd: root,
    cli_path: process.execPath,
    args: [fakeCli],
    state_path: statePath,
    max_queue_seconds: 1
  }), "utf8");
  const child = spawn(process.execPath, [runner, "--options-file", optionsPath], { env: { ...process.env, CP_FAKE_QODER_MODE: mode }, stdio: ["ignore", "pipe", "pipe"] });
  let stdout = "";
  child.stdout.setEncoding("utf8");
  child.stdout.on("data", (chunk) => { stdout += String(chunk); });
  return new Promise<{ exitCode: number | null; state: Record<string, unknown>; stdout: string }>((resolve) => child.on("close", (exitCode) => resolve({ exitCode, state: JSON.parse(readFileSync(statePath, "utf8")) as Record<string, unknown>, stdout })));
}

try {
  assert.ok(readFileSync(runner, "utf8").length > 0, "Build Qoder stream-json runner before this contract test.");
  mkdirSync(root, { recursive: true });
  writeFileSync(fakeCli, fakeCliSource, "utf8");
  const complete = await run("complete");
  assert.equal(complete.exitCode, 0);
  assert.equal(complete.state.state, "completed");
  assert.equal(complete.state.progress_observed, true);
  assert.match(complete.stdout, /"type":"result"/);
  const queued = await run("queue");
  assert.equal(queued.exitCode, 2, "A queue-only stream must stop at the queue bound instead of the generic job timeout.");
  assert.equal(queued.state.state, "provider_queue_timeout");
  assert.equal(queued.state.queue_observed, true);
  assert.equal(queued.state.queue_type, "slow");
  assert.equal(queued.state.progress_observed, false);
  console.log("Qoder stream-json queue contract regression ok");
} finally {
  rmSync(root, { recursive: true, force: true, maxRetries: 5, retryDelay: 100 });
}
