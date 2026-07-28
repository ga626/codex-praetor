import { ChildProcess, spawn } from "node:child_process";
import { appendFileSync, existsSync, readFileSync, renameSync, watch, writeFileSync } from "node:fs";
import path from "node:path";

type RunnerOptions = {
  schema: "codex-praetor-codebuddy-acp-runner/v1";
  job_id: string;
  cwd: string;
  prompt: string;
  launcher_path: string;
  cli_path: string;
  model: string;
  allowed_paths: string[];
  forbidden_paths: string[];
  writable_paths: string[];
  required_checks: string[];
  state_path: string;
  trace_path: string;
};

type State = {
  schema: "codex-praetor-codebuddy-acp-session/v1";
  job_id: string;
  connection_mode: "codebuddy_acp";
  state: "starting" | "running" | "completed" | "cancelled_session_terminated" | "failed";
  session_id?: string;
  structured_events: number;
  boundary_denials: number;
  cancel_requested: boolean;
  cancel_acknowledged: boolean;
  terminal_stop_reason?: string;
  last_event_type?: string;
  updated_at: string;
  error?: string;
};

type JsonRpcMessage = { jsonrpc?: string; id?: number; method?: string; params?: Record<string, unknown>; result?: unknown; error?: unknown };

function normalizeStringArray(value: unknown) {
  if (Array.isArray(value)) return value.filter((entry): entry is string => typeof entry === "string");
  return typeof value === "string" && value.trim() !== "" ? [value] : [];
}

function readOptions(): RunnerOptions {
  const index = process.argv.indexOf("--options-file");
  if (index < 0 || !process.argv[index + 1]) throw new Error("Missing --options-file for CodeBuddy ACP runner.");
  const options = JSON.parse(readFileSync(process.argv[index + 1], "utf8").replace(/^\uFEFF/, "")) as RunnerOptions;
  // PowerShell ConvertTo-Json serializes a one-item collection as a scalar.
  // Normalize at the process boundary so a legitimate one-file work contract
  // cannot crash the permission proxy before the worker starts.
  options.allowed_paths = normalizeStringArray(options.allowed_paths);
  options.forbidden_paths = normalizeStringArray(options.forbidden_paths);
  options.writable_paths = normalizeStringArray(options.writable_paths);
  options.required_checks = normalizeStringArray(options.required_checks);
  if (options.schema !== "codex-praetor-codebuddy-acp-runner/v1") throw new Error("Unsupported CodeBuddy ACP runner options schema.");
  if (![options.job_id, options.cwd, options.prompt, options.launcher_path, options.cli_path, options.model, options.state_path, options.trace_path].every(Boolean)) {
    throw new Error("CodeBuddy ACP runner options are incomplete.");
  }
  return options;
}

function writeState(options: RunnerOptions, state: Omit<State, "schema" | "job_id" | "connection_mode" | "updated_at">) {
  const payload: State = { schema: "codex-praetor-codebuddy-acp-session/v1", job_id: options.job_id, connection_mode: "codebuddy_acp", ...state, updated_at: new Date().toISOString() };
  const temporary = `${options.state_path}.${process.pid}.tmp`;
  writeFileSync(temporary, `${JSON.stringify(payload)}\n`, "utf8");
  renameSync(temporary, options.state_path);
}

function trace(options: RunnerOptions, event: string, data: Record<string, unknown> = {}) {
  appendFileSync(options.trace_path, `${JSON.stringify({ at: new Date().toISOString(), event, ...data })}\n`, "utf8");
}

function normalizeRelative(value: string) { return value.replaceAll("\\", "/").replace(/^\.\//, ""); }
function globMatches(pattern: string, value: string) {
  const escaped = normalizeRelative(pattern).replace(/[|\\{}()[\]^$+?.]/g, "\\$&").replaceAll("**", "::DOUBLE_STAR::").replaceAll("*", "[^/]*").replaceAll("::DOUBLE_STAR::", ".*");
  return new RegExp(`^${escaped}$`, "i").test(normalizeRelative(value));
}
function relativeInside(root: string, candidate: unknown) {
  if (typeof candidate !== "string" || candidate.trim() === "") return "";
  const resolvedRoot = path.resolve(root);
  const resolved = path.resolve(root, candidate);
  if (resolved !== resolvedRoot && !resolved.startsWith(`${resolvedRoot}${path.sep}`)) return undefined;
  const relative = normalizeRelative(path.relative(resolvedRoot, resolved));
  return relative || ".";
}
function pathAllowed(options: RunnerOptions, candidate: unknown, write = false) {
  const relative = relativeInside(options.cwd, candidate);
  if (relative === undefined) return false;
  if (relative === "") return true;
  if (options.forbidden_paths.some((entry) => globMatches(entry, relative))) return false;
  const allowlist = write ? options.writable_paths : options.allowed_paths;
  return allowlist.some((entry) => globMatches(entry, relative));
}
function pathScope(options: RunnerOptions, candidate: unknown, write = false) {
  const relative = relativeInside(options.cwd, candidate);
  if (relative === undefined) return "outside_worktree";
  if (relative === "") return "no_path";
  if (options.forbidden_paths.some((entry) => globMatches(entry, relative))) return "forbidden_path";
  const allowlist = write ? options.writable_paths : options.allowed_paths;
  return allowlist.some((entry) => globMatches(entry, relative)) ? "allowed_path" : "not_allowlisted";
}
function requestedPath(params: Record<string, unknown> = {}) {
  const raw = params.path ?? params.filePath ?? (params.toolCall as { rawInput?: Record<string, unknown> } | undefined)?.rawInput?.file_path;
  return typeof raw === "string" ? raw : "";
}
function requestedCommand(params: Record<string, unknown> = {}) {
  const raw = params.toolCall as { rawInput?: Record<string, unknown> } | undefined;
  const input = raw?.rawInput ?? params;
  const command = typeof input.command === "string" ? input.command.trim() : "";
  const args = Array.isArray(input.args) ? input.args.filter((entry): entry is string => typeof entry === "string") : [];
  return [command, ...args].filter(Boolean).join(" ").trim();
}

class AcpClient {
  private readonly pending = new Map<number, { resolve(value: unknown): void; reject(reason: Error): void }>();
  private readonly terminalProcesses = new Map<string, ChildProcess>();
  private child: ChildProcess;
  private nextId = 1;
  private buffer = "";
  private structuredEvents = 0;
  private boundaryDenials = 0;
  private cancelRequested = false;
  private cancelAcknowledged = false;
  private sessionId = "";
  private terminalStopReason = "";
  private terminalText = "";
  private readonly agentMessages = new Map<string, string>();
  private lastAgentMessageId = "";
  private lastEventType = "";

  constructor(private readonly options: RunnerOptions) {
    this.child = spawn(options.launcher_path, [options.cli_path, "--acp", "-y", "--setting-sources", "project", "--model", options.model], { cwd: options.cwd, stdio: ["pipe", "pipe", "pipe"], windowsHide: true });
    const stdout = this.child.stdout;
    const stderr = this.child.stderr;
    if (!stdout || !stderr || !this.child.stdin) throw new Error("ACP runner could not create stdio pipes.");
    stdout.setEncoding("utf8");
    stderr.setEncoding("utf8");
    stdout.on("data", (chunk: string) => this.consume(String(chunk)));
    stderr.on("data", (chunk: string) => trace(this.options, "provider_stderr", { bytes: Buffer.byteLength(String(chunk), "utf8") }));
    this.child.on("error", (error) => trace(this.options, "spawn_error", { message: error.message }));
  }

  private currentState(state: State["state"], error?: string) {
    writeState(this.options, { state, session_id: this.sessionId || undefined, structured_events: this.structuredEvents, boundary_denials: this.boundaryDenials, cancel_requested: this.cancelRequested, cancel_acknowledged: this.cancelAcknowledged, terminal_stop_reason: this.terminalStopReason || undefined, last_event_type: this.lastEventType || undefined, error });
  }
  private send(message: JsonRpcMessage) {
    trace(this.options, "client_message", { method: message.method ?? "response", id: message.id ?? null });
    if (!this.child.stdin) throw new Error("ACP server stdin is unavailable.");
    this.child.stdin.write(`${JSON.stringify({ jsonrpc: "2.0", ...message })}\n`);
  }
  private request(method: string, params: Record<string, unknown>) {
    const id = this.nextId++;
    this.send({ id, method, params });
    return new Promise<unknown>((resolve, reject) => this.pending.set(id, { resolve, reject }));
  }
  private deny(id: number, message: string) {
    this.boundaryDenials += 1;
    this.send({ id, error: { code: -32001, message } });
  }
  private allowPermission(id: number, allowed: boolean) {
    if (!allowed) this.boundaryDenials += 1;
    this.send({ id, result: { outcome: { outcome: "selected", optionId: allowed ? "allow" : "reject" } } });
  }
  private async handleRequest(message: JsonRpcMessage) {
    const params = message.params ?? {};
    const requestId = message.id;
    if (requestId === undefined || !message.method) return;
    const filePath = requestedPath(params);
    if (message.method === "session/request_permission") {
      const command = requestedCommand(params);
      const write = String((params.toolCall as { rawInput?: Record<string, unknown> } | undefined)?.rawInput?.tool ?? "").toLowerCase().includes("write");
      const allowed = filePath ? pathAllowed(this.options, filePath, write) : (command !== "" && this.options.required_checks.includes(command));
      this.allowPermission(requestId, allowed);
      trace(this.options, "permission", { allowed, path_scope: filePath ? pathScope(this.options, filePath, write) : "no_path", has_command: Boolean(command) });
      this.currentState("running");
      return;
    }
    if (message.method === "fs/read_text_file") {
      if (!pathAllowed(this.options, filePath, false)) { this.deny(requestId, "Read outside the declared Codex worktree contract is denied."); this.currentState("running"); return; }
      try { this.send({ id: requestId, result: { content: readFileSync(path.resolve(this.options.cwd, filePath), "utf8") } }); }
      catch (error) { this.deny(requestId, error instanceof Error ? error.message : String(error)); }
      return;
    }
    if (message.method === "fs/write_text_file") {
      if (!pathAllowed(this.options, filePath, true)) { this.deny(requestId, "Write outside the declared Codex worktree contract is denied."); this.currentState("running"); return; }
      const content = params.content ?? params.text;
      if (typeof content !== "string") { this.deny(requestId, "ACP write request omitted textual content."); return; }
      try { writeFileSync(path.resolve(this.options.cwd, filePath), content, "utf8"); this.send({ id: requestId, result: null }); }
      catch (error) { this.deny(requestId, error instanceof Error ? error.message : String(error)); }
      return;
    }
    if (message.method === "terminal/create") {
      const command = requestedCommand(params);
      if (!this.options.required_checks.includes(command)) { this.deny(requestId, "Terminal command is not an exact declared deterministic check."); this.currentState("running"); return; }
      const terminalId = `codex-praetor-${this.terminalProcesses.size + 1}`;
      const [executable, ...args] = command.split(/\s+/);
      const process = spawn(executable, args, { cwd: this.options.cwd, windowsHide: true, stdio: ["ignore", "pipe", "pipe"] });
      this.terminalProcesses.set(terminalId, process);
      process.stdout?.on("data", (data) => this.send({ method: "terminal/output", params: { terminalId, data: String(data) } }));
      process.stderr?.on("data", (data) => this.send({ method: "terminal/output", params: { terminalId, data: String(data) } }));
      process.on("exit", (exitCode) => this.send({ method: "terminal/exit", params: { terminalId, exitCode: exitCode ?? -1 } }));
      this.send({ id: requestId, result: { terminalId } });
      trace(this.options, "terminal_started", { command });
      return;
    }
    if (message.method === "terminal/kill") {
      const terminalId = typeof params.terminalId === "string" ? params.terminalId : "";
      const process = this.terminalProcesses.get(terminalId);
      if (process) process.kill();
      this.send({ id: requestId, result: null });
      return;
    }
    this.deny(requestId, `Unsupported ACP client request: ${message.method}`);
    this.currentState("running");
  }
  private handle(message: JsonRpcMessage) {
    if (typeof message.id === "number" && (message.result !== undefined || message.error !== undefined) && !message.method) {
      const pending = this.pending.get(message.id);
      if (pending) { this.pending.delete(message.id); message.error === undefined ? pending.resolve(message.result) : pending.reject(new Error(JSON.stringify(message.error))); }
      return;
    }
    if (typeof message.id === "number" && message.method) { void this.handleRequest(message); return; }
    if (message.method === "session/update") {
      this.structuredEvents += 1;
      const update = message.params?.update as { sessionUpdate?: unknown; content?: { type?: unknown; text?: unknown }; messageId?: unknown; _meta?: Record<string, unknown> } | undefined;
      const updateKind = typeof update?.sessionUpdate === "string" ? update.sessionUpdate : "structured";
      const previousKind = this.lastEventType;
      this.lastEventType = updateKind;
      if (updateKind === "agent_message_chunk" && update?.content?.type === "text" && typeof update.content.text === "string") {
        const metaMessageId = update._meta?.["codebuddy.ai/messageId"];
        const messageId = typeof update.messageId === "string" ? update.messageId : typeof metaMessageId === "string" ? metaMessageId : "terminal-message";
        this.lastAgentMessageId = messageId;
        const existing = this.agentMessages.get(messageId) ?? "";
        this.agentMessages.set(messageId, (existing + update.content.text).slice(0, 65_536));
      }
      // Persist only meaningful state transitions or exponential activity
      // milestones. This is event-driven progress evidence, not a polling loop
      // and avoids turning streamed text into hundreds of disk writes. The
      // trace follows the same rule: a 600-piece final answer is still one
      // progress signal, not 600 durable facts. Its complete text remains
      // available only through the worker stdout handed to Codex for review.
      const milestone = (this.structuredEvents & (this.structuredEvents - 1)) === 0;
      if (milestone || updateKind !== previousKind) {
        trace(this.options, "session_progress", { update_kind: updateKind, structured_events: this.structuredEvents, event_kind_changed: updateKind !== previousKind });
        this.currentState("running");
      }
      return;
    }
    if (message.method) trace(this.options, "notification", { method: message.method });
  }
  private consume(chunk: string) {
    this.buffer += chunk;
    for (;;) {
      const boundary = this.buffer.indexOf("\n");
      if (boundary < 0) return;
      const line = this.buffer.slice(0, boundary).trim();
      this.buffer = this.buffer.slice(boundary + 1);
      if (!line) continue;
      try { this.handle(JSON.parse(line) as JsonRpcMessage); }
      catch { trace(this.options, "unparseable_stdout", { bytes: Buffer.byteLength(line, "utf8") }); }
    }
  }
  private async cancelWhenRequested(cancelPath: string) {
    const requestCancel = async () => {
      if (this.cancelRequested || !this.sessionId) return;
      this.cancelRequested = true;
      this.currentState("running");
      trace(this.options, "cancel_requested", { session_id: this.sessionId });
      try { this.send({ method: "session/cancel", params: { sessionId: this.sessionId } }); this.cancelAcknowledged = true; this.currentState("running"); }
      catch (error) { trace(this.options, "cancel_request_error", { message: error instanceof Error ? error.message : String(error) }); }
    };
    if (existsSync(cancelPath)) await requestCancel();
    return watch(path.dirname(cancelPath), (_event, filename) => { if (filename?.toString() === path.basename(cancelPath) && existsSync(cancelPath)) void requestCancel(); });
  }
  fail(message: string) {
    this.currentState("failed", message);
  }
  async run() {
    this.currentState("starting");
    const initialized = await this.request("initialize", { protocolVersion: 1, clientInfo: { name: "codex-praetor", version: "1" }, clientCapabilities: { fs: { readTextFile: true, writeTextFile: true }, terminal: true } }) as { protocolVersion?: number };
    trace(this.options, "initialized", { protocol_version: initialized.protocolVersion ?? null });
    const opened = await this.request("session/new", { cwd: path.resolve(this.options.cwd), mcpServers: [] }) as { sessionId?: unknown };
    if (typeof opened.sessionId !== "string" || !opened.sessionId) throw new Error("ACP session/new returned no sessionId.");
    this.sessionId = opened.sessionId;
    this.currentState("running");
    const cancelWatcher = await this.cancelWhenRequested(path.join(path.dirname(this.options.state_path), "cancel-request.json"));
    try {
      const terminal = await this.request("session/prompt", { sessionId: this.sessionId, prompt: [{ type: "text", text: this.options.prompt }] }) as { stopReason?: unknown; result?: unknown };
      this.terminalStopReason = typeof terminal.stopReason === "string" ? terminal.stopReason : "";
      if (typeof terminal.result === "string") this.terminalText = terminal.result;
      if (!this.terminalText && this.lastAgentMessageId) this.terminalText = this.agentMessages.get(this.lastAgentMessageId) ?? "";
      const cancelled = this.cancelRequested && this.terminalStopReason === "cancelled";
      if (this.terminalStopReason === "cancelled" && !this.cancelRequested) {
        const message = "CodeBuddy ACP session ended as cancelled without a Codex cancellation request.";
        this.fail(message);
        trace(this.options, "terminal", { stop_reason: this.terminalStopReason, cancelled: false, unexpected_cancel: true });
        throw new Error(message);
      }
      this.currentState(cancelled ? "cancelled_session_terminated" : "completed");
      trace(this.options, "terminal", { stop_reason: this.terminalStopReason || null, cancelled });
      if (!cancelled && this.terminalText) process.stdout.write(`${this.terminalText}\n`);
    } finally {
      cancelWatcher.close();
      for (const terminal of this.terminalProcesses.values()) terminal.kill();
      this.child.stdin?.end();
      // ACP servers are long-lived by design. Once session/prompt returned a
      // terminal result, this disposable worker connection has no reusable
      // session contract; close it so a completed job cannot keep the watcher
      // alive. This is deliberately after, never instead of, terminal proof.
      this.child.kill();
    }
  }
}

async function main() {
  const options = readOptions();
  const runner = new AcpClient(options);
  try { await runner.run(); }
  catch (error) {
    const message = error instanceof Error ? error.message : String(error);
    runner.fail(message);
    throw error;
  }
}

main().catch((error) => { process.stderr.write(`${error instanceof Error ? error.stack ?? error.message : String(error)}\n`); process.exitCode = 1; });
