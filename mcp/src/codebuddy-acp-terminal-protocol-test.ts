import assert from "node:assert/strict";
import { spawn } from "node:child_process";
import { mkdirSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import os from "node:os";
import path from "node:path";

const root = path.join(os.tmpdir(), `codex-praetor-acp-terminal-${process.pid}-${Date.now()}`);
const runner = path.join(process.cwd(), "dist", "codebuddy-acp-runner.js");
const fakeAgent = path.join(root, "fake-acp-agent.mjs");
const material = path.join(root, "material");
const readable = path.join(material, "input.txt");
const writable = path.join(material, "output.txt");
const outside = path.join(os.tmpdir(), `codex-praetor-acp-outside-${process.pid}.txt`);
const terminalCheck = `"${process.execPath}" -e process.stdout.write('terminal-ok')`;

const fakeAgentSource = String.raw`
import readline from "node:readline";
let promptId = 0;
let terminalId = "";
function send(message) { process.stdout.write(JSON.stringify({ jsonrpc: "2.0", ...message }) + "\n"); }
function fail(message) { process.stderr.write(message + "\n"); process.exitCode = 2; }
const lines = readline.createInterface({ input: process.stdin });
lines.on("line", (line) => {
  const message = JSON.parse(line);
  if (message.method === "initialize") { send({ id: message.id, result: { protocolVersion: 1 } }); return; }
  if (message.method === "session/new") { send({ id: message.id, result: { sessionId: "fixture-session" } }); return; }
  if (message.method === "session/prompt") {
    promptId = message.id;
    send({ id: 90, method: "fs/read_text_file", params: { path: process.env.CP_OUTSIDE } });
    return;
  }
  if (message.id === 90) {
    if (!message.error) return fail("outside filesystem read was not rejected");
    send({ id: 91, method: "fs/read_text_file", params: { path: process.env.CP_READABLE } });
    return;
  }
  if (message.id === 91) {
    if (message.result?.content !== "before") return fail("allowed filesystem read did not return content");
    send({ id: 92, method: "fs/write_text_file", params: { path: process.env.CP_WRITABLE, content: "after" } });
    return;
  }
  if (message.id === 92) {
    if (message.error) return fail("allowed filesystem write was rejected");
    send({ id: 93, method: "terminal/create", params: { command: process.env.CP_TERMINAL_CHECK } });
    return;
  }
  if (message.id === 93) {
    terminalId = message.result?.terminalId || "";
    if (!terminalId) return fail("terminal/create returned no terminal id");
    send({ id: 94, method: "terminal/wait_for_exit", params: { terminalId } });
    return;
  }
  if (message.id === 94) {
    if (message.result?.exitCode !== 0) return fail("terminal/wait_for_exit did not return exit code 0");
    send({ id: 95, method: "terminal/output", params: { terminalId } });
    return;
  }
  if (message.id === 95) {
    if (!message.result?.output?.includes("terminal-ok") || message.result?.exitStatus?.exitCode !== 0) return fail("terminal/output did not return final output and status");
    send({ id: 96, method: "terminal/release", params: { terminalId } });
    return;
  }
  if (message.id === 96) {
    if (message.error) return fail("terminal/release was rejected");
    send({ id: promptId, result: { stopReason: "end_turn", result: "ACP terminal protocol fixture complete" } });
  }
});
`;

try {
  mkdirSync(material, { recursive: true });
  writeFileSync(readable, "before", "utf8");
  writeFileSync(writable, "original", "utf8");
  writeFileSync(outside, "outside", "utf8");
  writeFileSync(fakeAgent, fakeAgentSource, "utf8");
  const job = path.join(root, "job");
  mkdirSync(job, { recursive: true });
  const optionsPath = path.join(job, "options.json");
  writeFileSync(optionsPath, JSON.stringify({
    schema: "codex-praetor-codebuddy-acp-runner/v1",
    job_id: "terminal-protocol",
    cwd: root,
    prompt: "fixture",
    launcher_path: process.execPath,
    cli_path: fakeAgent,
    model: "hy3",
    allowed_paths: ["material/**"],
    forbidden_paths: [],
    writable_paths: ["material/**"],
    required_checks: [terminalCheck],
    max_stall_seconds: 30,
    state_path: path.join(job, "session.json"),
    trace_path: path.join(job, "trace.ndjson")
  }), "utf8");
  const child = spawn(process.execPath, [runner, "--options-file", optionsPath], {
    env: { ...process.env, CP_OUTSIDE: outside, CP_READABLE: readable, CP_WRITABLE: writable, CP_TERMINAL_CHECK: terminalCheck },
    stdio: ["ignore", "pipe", "pipe"]
  });
  let stdout = "";
  let stderr = "";
  child.stdout.setEncoding("utf8");
  child.stderr.setEncoding("utf8");
  child.stdout.on("data", (chunk) => { stdout += String(chunk); });
  child.stderr.on("data", (chunk) => { stderr += String(chunk); });
  const exitCode = await new Promise<number | null>((resolve) => child.on("exit", resolve));
  assert.equal(exitCode, 0, `ACP terminal protocol fixture failed: ${stderr}`);
  assert.equal(readFileSync(writable, "utf8"), "after");
  assert.match(stdout, /ACP terminal protocol fixture complete/);
  const state = JSON.parse(readFileSync(path.join(job, "session.json"), "utf8"));
  assert.equal(state.state, "completed");
  assert.ok(state.boundary_denials >= 1, "outside-worktree read must remain denied.");
  console.log("CodeBuddy ACP terminal protocol regression ok");
} finally {
  rmSync(root, { recursive: true, force: true });
  rmSync(outside, { force: true });
}
