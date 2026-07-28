import assert from "node:assert/strict";
import { spawn } from "node:child_process";
import { existsSync, mkdirSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import os from "node:os";
import path from "node:path";

const root = path.join(os.tmpdir(), `codex-praetor-codebuddy-acp-${process.pid}-${Date.now()}`);
const runner = path.join(process.cwd(), "dist", "codebuddy-acp-runner.js");
const fakeAgent = path.join(root, "fake-acp-agent.mjs");

const source = String.raw`
import readline from "node:readline";
const mode = process.env.CP_FAKE_ACP_MODE || "complete";
let promptId = 0;
function send(message) { process.stdout.write(JSON.stringify({ jsonrpc: "2.0", ...message }) + "\n"); }
const lines = readline.createInterface({ input: process.stdin });
lines.on("line", (line) => {
  const message = JSON.parse(line);
  if (message.method === "initialize") { send({ id: message.id, result: { protocolVersion: 1 } }); return; }
  if (message.method === "session/new") { send({ id: message.id, result: { sessionId: "fixture-session" } }); return; }
  if (message.method === "session/prompt") {
    promptId = message.id;
    send({ method: "session/update", params: { sessionId: "fixture-session", update: { sessionUpdate: "tool_call_update" } } });
    const chunkCount = mode === "high_volume" ? 512 : 1;
    for (let index = 0; index < chunkCount; index += 1) send({ method: "session/update", params: { sessionId: "fixture-session", update: { sessionUpdate: "agent_message_chunk", messageId: "fixture-final", content: { type: "text", text: chunkCount === 1 ? "ACP fixture complete" : "x" } } } });
    send({ id: 50, method: "fs/read_text_file", params: { path: process.env.CP_FAKE_INSIDE } });
    return;
  }
  if (message.id === 50) {
    send({ id: 51, method: "fs/write_text_file", params: { path: process.env.CP_FAKE_INSIDE, content: "changed" } });
    return;
  }
  if (message.id === 51) {
    send({ id: 90, method: "fs/read_text_file", params: { path: process.env.CP_FAKE_OUTSIDE } });
    return;
  }
  if (message.id === 90 && (mode === "complete" || mode === "high_volume")) { send({ id: promptId, result: { stopReason: "end_turn" } }); return; }
  if (message.id === 90 && mode === "unexpected_cancel") { send({ id: promptId, result: { stopReason: "cancelled" } }); return; }
  if (message.method === "session/cancel") { send({ id: promptId, result: { stopReason: "cancelled" } }); return; }
});
`;

function waitFor(predicate: () => boolean, label: string) {
  const deadline = Date.now() + 10_000;
  return new Promise<void>((resolve, reject) => {
    const timer = setInterval(() => {
      if (predicate()) { clearInterval(timer); resolve(); }
      else if (Date.now() > deadline) { clearInterval(timer); reject(new Error(`Timed out waiting for ${label}.`)); }
    }, 25);
  });
}

function options(jobId: string) {
  const job = path.join(root, jobId);
  mkdirSync(job, { recursive: true });
  const value = {
    schema: "codex-praetor-codebuddy-acp-runner/v1",
    job_id: jobId,
    cwd: root,
    prompt: "fixture",
    launcher_path: process.execPath,
    cli_path: fakeAgent,
    model: "hy3",
    allowed_paths: ["material"],
    forbidden_paths: [],
    writable_paths: ["material"],
    required_checks: [],
    max_stall_seconds: 30,
    state_path: path.join(job, "session.json"),
    trace_path: path.join(job, "trace.ndjson")
  };
  const optionsPath = path.join(job, "options.json");
  // Windows PowerShell 5 can emit a UTF-8 BOM for JSON state files; runners
  // must accept it rather than failing before the provider session begins.
  writeFileSync(optionsPath, `\uFEFF${JSON.stringify(value)}`, "utf8");
  return { job, optionsPath, statePath: value.state_path, tracePath: value.trace_path };
}

try {
  assert.ok(existsSync(runner), "Build codebuddy ACP runner before this contract test.");
  mkdirSync(root, { recursive: true });
  const inside = path.join(root, "material", "inside.txt");
  mkdirSync(path.dirname(inside), { recursive: true });
  writeFileSync(inside, "before", "utf8");
  writeFileSync(fakeAgent, source, "utf8");
  const outside = path.join(os.tmpdir(), `codex-praetor-outside-${process.pid}.txt`);
  writeFileSync(outside, "outside", "utf8");

  const complete = options("complete");
  const completeProcess = spawn(process.execPath, [runner, "--options-file", complete.optionsPath], { env: { ...process.env, CP_FAKE_ACP_MODE: "complete", CP_FAKE_INSIDE: inside, CP_FAKE_OUTSIDE: outside }, stdio: ["ignore", "pipe", "pipe"] });
  let completeOut = "";
  completeProcess.stdout.setEncoding("utf8");
  completeProcess.stdout.on("data", (chunk) => { completeOut += String(chunk); });
  const completeExit = await new Promise<number | null>((resolve) => completeProcess.on("exit", resolve));
  assert.equal(completeExit, 0);
  const completeState = JSON.parse(readFileSync(complete.statePath, "utf8"));
  assert.equal(completeState.state, "completed");
  assert.ok(completeState.structured_events >= 1, "session/update must become compact structured progress evidence.");
  assert.ok(completeState.boundary_denials >= 1, "outside-worktree filesystem read must be denied by the client proxy.");
  assert.equal(readFileSync(inside, "utf8"), "changed", "a literal directory contract must allow its descendant file through the ACP proxy.");
  assert.match(completeOut, /ACP fixture complete/);

  const highVolume = options("high-volume");
  const highVolumeProcess = spawn(process.execPath, [runner, "--options-file", highVolume.optionsPath], { env: { ...process.env, CP_FAKE_ACP_MODE: "high_volume", CP_FAKE_INSIDE: inside, CP_FAKE_OUTSIDE: outside }, stdio: ["ignore", "pipe", "pipe"] });
  const highVolumeExit = await new Promise<number | null>((resolve) => highVolumeProcess.on("exit", resolve));
  assert.equal(highVolumeExit, 0);
  const highVolumeState = JSON.parse(readFileSync(highVolume.statePath, "utf8"));
  assert.equal(highVolumeState.structured_events, 513, "all structured stream events must still count as live progress.");
  const highVolumeTrace = readFileSync(highVolume.tracePath, "utf8").trim().split(/\r?\n/).filter(Boolean).map((line) => JSON.parse(line) as { event?: string; structured_events?: number });
  assert.ok(highVolumeTrace.some((entry) => entry.event === "session_progress" && entry.structured_events === 512), "exponential progress milestones must remain auditable.");
  assert.ok(highVolumeTrace.length < 32, "stream chunks must not create one durable trace record per chunk.");

  const unexpected = options("unexpected-cancel");
  const unexpectedProcess = spawn(process.execPath, [runner, "--options-file", unexpected.optionsPath], { env: { ...process.env, CP_FAKE_ACP_MODE: "unexpected_cancel", CP_FAKE_INSIDE: inside, CP_FAKE_OUTSIDE: outside }, stdio: ["ignore", "pipe", "pipe"] });
  const unexpectedExit = await new Promise<number | null>((resolve) => unexpectedProcess.on("exit", resolve));
  assert.equal(unexpectedExit, 1, "Provider-side cancellation without a Codex request must not be accepted as success.");
  const unexpectedState = JSON.parse(readFileSync(unexpected.statePath, "utf8"));
  assert.equal(unexpectedState.state, "failed");
  assert.equal(unexpectedState.terminal_stop_reason, "cancelled");

  const cancelled = options("cancelled");
  const cancelProcess = spawn(process.execPath, [runner, "--options-file", cancelled.optionsPath], { env: { ...process.env, CP_FAKE_ACP_MODE: "cancel", CP_FAKE_INSIDE: inside, CP_FAKE_OUTSIDE: outside }, stdio: ["ignore", "pipe", "pipe"] });
  await waitFor(() => existsSync(cancelled.statePath) && JSON.parse(readFileSync(cancelled.statePath, "utf8")).state === "running", "ACP running state");
  writeFileSync(path.join(cancelled.job, "cancel-request.json"), JSON.stringify({ schema: "codex-praetor-cancel-request/v1" }), "utf8");
  const cancelExit = await new Promise<number | null>((resolve) => cancelProcess.on("exit", resolve));
  assert.equal(cancelExit, 0);
  const cancelState = JSON.parse(readFileSync(cancelled.statePath, "utf8"));
  assert.equal(cancelState.state, "cancelled_session_terminated");
  assert.equal(cancelState.cancel_requested, true);
  assert.equal(cancelState.cancel_acknowledged, true);
  assert.equal(cancelState.terminal_stop_reason, "cancelled");
  console.log("CodeBuddy ACP runner contract regression ok");
} finally {
  rmSync(root, { recursive: true, force: true });
}
