const { spawn } = require("node:child_process");
const fs = require("node:fs");
const path = require("node:path");

function findCodexExe() {
  if (process.env.CODEX_EXE && fs.existsSync(process.env.CODEX_EXE)) {
    return process.env.CODEX_EXE;
  }

  const base = path.join(process.env.LOCALAPPDATA || "", "OpenAI", "Codex", "bin");
  const candidates = [];
  try {
    for (const entry of fs.readdirSync(base, { withFileTypes: true })) {
      if (entry.isFile() && entry.name.toLowerCase() === "codex.exe") {
        candidates.push(path.join(base, entry.name));
      }
      if (entry.isDirectory()) {
        const nested = path.join(base, entry.name, "codex.exe");
        if (fs.existsSync(nested)) candidates.push(nested);
      }
    }
  } catch {
    // Fall through to PATH lookup.
  }

  candidates.sort((a, b) => fs.statSync(b).mtimeMs - fs.statSync(a).mtimeMs);
  return candidates[0] || "codex";
}

const payloadB64 = process.argv[2];
if (!payloadB64) {
  console.error("missing base64 JSON-RPC payload");
  process.exit(2);
}

const waitForTurnComplete = process.argv.includes("--wait-turn-complete");
const timeoutArgIndex = process.argv.indexOf("--timeout-ms");
const timeoutMs =
  timeoutArgIndex >= 0 ? Number(process.argv[timeoutArgIndex + 1]) || 120000 : Number(process.env.CODEX_APP_SERVER_TIMEOUT_MS) || 120000;

const parsedPayload = JSON.parse(Buffer.from(payloadB64, "base64").toString("utf8"));
const requests = Array.isArray(parsedPayload) ? parsedPayload : [parsedPayload];
const wantedIds = new Set(requests.map((request) => request.id).filter((id) => id !== undefined && id !== null));
const turnIds = new Set();

const messages = [
  {
    id: 0,
    method: "initialize",
    params: {
      clientInfo: { name: "codex-praetor", version: "1.0.0" },
      capabilities: { experimentalApi: true },
    },
  },
  { method: "initialized", params: {} },
  ...requests,
];

const child = spawn(findCodexExe(), ["app-server", "--listen", "stdio://"], {
  stdio: ["pipe", "pipe", "pipe"],
  windowsHide: true,
});

let stdoutBuffer = "";
let stderr = "";
let exiting = false;

function maybeDone() {
  if (exiting) return;
  if (wantedIds.size === 0 && (!waitForTurnComplete || turnIds.size === 0)) {
    exiting = true;
    child.kill();
  }
}

child.stderr.setEncoding("utf8");
child.stdout.setEncoding("utf8");
child.stderr.on("data", (chunk) => {
  stderr += chunk;
});

child.stdout.on("data", (chunk) => {
  stdoutBuffer += chunk;
  const lines = stdoutBuffer.split(/\r?\n/);
  stdoutBuffer = lines.pop() || "";

  for (const line of lines) {
    if (!line.trim()) continue;
    let msg;
    try {
      msg = JSON.parse(line);
    } catch {
      process.stderr.write(line + "\n");
      continue;
    }

    if (wantedIds.has(msg.id)) {
      process.stdout.write(JSON.stringify(msg) + "\n");
      if (msg.result && msg.result.turn && msg.result.turn.id) {
        turnIds.add(msg.result.turn.id);
      }
      wantedIds.delete(msg.id);
      maybeDone();
      continue;
    }

    if (waitForTurnComplete && msg.method === "turn/completed" && msg.params && msg.params.turn && turnIds.has(msg.params.turn.id)) {
      process.stdout.write(JSON.stringify(msg) + "\n");
      turnIds.delete(msg.params.turn.id);
      maybeDone();
      continue;
    }

    if (msg.id === 0 || msg.method) {
      continue;
    }
  }
});

const timeout = setTimeout(() => {
  exiting = true;
  child.kill();
  console.error("app-server proxy timed out");
  process.exit(124);
}, timeoutMs);

child.on("error", (error) => {
  clearTimeout(timeout);
  console.error(error.stack || error.message || String(error));
  process.exit(1);
});

child.on("close", (code) => {
  clearTimeout(timeout);
  if (stdoutBuffer.trim()) process.stderr.write(stdoutBuffer);
  if (stderr) process.stderr.write(stderr);
  process.exit(exiting ? 0 : code || 0);
});

for (const message of messages) {
  child.stdin.write(JSON.stringify(message) + "\n", "utf8");
}

