import { spawn } from "node:child_process";
import { existsSync, readFileSync, watch } from "node:fs";
import readline from "node:readline";
import path from "node:path";
import { writeJsonStateFile } from "./qoder-sdk-state.js";

type RunnerOptions = {
  schema: "codex-praetor-qoder-stream-json-runner/v1";
  job_id: string;
  cwd: string;
  cli_path: string;
  args: string[];
  state_path: string;
  max_queue_seconds: number;
};

type State = {
  schema: "codex-praetor-qoder-stream-json-session/v1";
  job_id: string;
  connection_mode: "supervised_cli_stream_json";
  state: "starting" | "running" | "completed" | "provider_queue_timeout" | "cancelled_session_terminated" | "failed";
  total_lines: number;
  parsed_events: number;
  invalid_lines: number;
  event_types: string[];
  queue_observed: boolean;
  queue_type?: string;
  queue_count?: number;
  queue_wait_elapsed_ms?: number;
  queue_max_wait_ms?: number;
  service_available?: boolean;
  progress_observed: boolean;
  cancelled: boolean;
  exit_code?: number | null;
  updated_at: string;
  error?: string;
};

function readOptions() {
  const index = process.argv.indexOf("--options-file");
  if (index < 0 || !process.argv[index + 1]) throw new Error("Missing --options-file for Qoder stream-json runner.");
  const value = JSON.parse(readFileSync(process.argv[index + 1], "utf8").replace(/^\uFEFF/, "")) as RunnerOptions;
  if (value.schema !== "codex-praetor-qoder-stream-json-runner/v1" || !value.job_id || !value.cwd || !value.cli_path || !value.state_path || !Array.isArray(value.args) || !Number.isFinite(value.max_queue_seconds) || value.max_queue_seconds < 1) {
    throw new Error("Qoder stream-json runner options are incomplete.");
  }
  return value;
}

function numberField(input: Record<string, unknown>, key: string) {
  const value = input[key];
  return typeof value === "number" && Number.isFinite(value) ? value : undefined;
}

async function main() {
  const options = readOptions();
  const cancelPath = path.join(path.dirname(options.state_path), "cancel-request.json");
  let totalLines = 0;
  let parsedEvents = 0;
  let invalidLines = 0;
  const eventTypes = new Set<string>();
  let queueObserved = false;
  let queueType = "";
  let queueCount: number | undefined;
  let queueWaitElapsedMs: number | undefined;
  let queueMaxWaitMs: number | undefined;
  let serviceAvailable: boolean | undefined;
  let progressObserved = false;
  let cancelled = false;
  let queueTimedOut = false;
  let queueTimer: ReturnType<typeof setTimeout> | undefined;
  let cancellationWatcher: ReturnType<typeof watch> | undefined;
  const child = spawn(options.cli_path, options.args, { cwd: options.cwd, stdio: ["ignore", "pipe", "pipe"], windowsHide: true });

  const writeState = (state: State["state"], error?: string, exitCode?: number | null) => {
    const payload: State = {
      schema: "codex-praetor-qoder-stream-json-session/v1",
      job_id: options.job_id,
      connection_mode: "supervised_cli_stream_json",
      state,
      total_lines: totalLines,
      parsed_events: parsedEvents,
      invalid_lines: invalidLines,
      event_types: [...eventTypes],
      queue_observed: queueObserved,
      queue_type: queueType || undefined,
      queue_count: queueCount,
      queue_wait_elapsed_ms: queueWaitElapsedMs,
      queue_max_wait_ms: queueMaxWaitMs,
      service_available: serviceAvailable,
      progress_observed: progressObserved,
      cancelled,
      exit_code: exitCode,
      updated_at: new Date().toISOString(),
      error
    };
    writeJsonStateFile(options.state_path, payload);
  };

  const stop = (reason: "queue" | "cancel") => {
    if (reason === "queue") queueTimedOut = true;
    else cancelled = true;
    if (!child.killed) child.kill();
  };
  const armQueueTimer = () => {
    if (queueTimer || progressObserved || cancelled) return;
    queueTimer = setTimeout(() => {
      queueWaitElapsedMs = Math.max(queueWaitElapsedMs ?? 0, options.max_queue_seconds * 1000);
      writeState("provider_queue_timeout", "queue_wait_limit_exceeded");
      stop("queue");
    }, options.max_queue_seconds * 1000);
  };
  const markProgress = () => {
    progressObserved = true;
    if (queueTimer) { clearTimeout(queueTimer); queueTimer = undefined; }
  };

  writeState("starting");
  if (existsSync(cancelPath)) stop("cancel");
  cancellationWatcher = watch(path.dirname(cancelPath), (_event, filename) => {
    if (filename?.toString() === path.basename(cancelPath) && existsSync(cancelPath)) stop("cancel");
  });
  child.once("error", (error) => writeState("failed", error.message));
  const stdout = child.stdout;
  const stderr = child.stderr;
  if (!stdout || !stderr) throw new Error("Qoder stream-json runner could not create stdio pipes.");
  stderr.pipe(process.stderr);
  const lines = readline.createInterface({ input: stdout, crlfDelay: Infinity });
  lines.on("line", (line) => {
    process.stdout.write(`${line}\n`);
    if (!line.trim()) return;
    totalLines += 1;
    try {
      const event = JSON.parse(line) as Record<string, unknown>;
      parsedEvents += 1;
      const type = typeof event.type === "string" ? event.type : typeof event.event === "string" ? event.event : "untyped";
      eventTypes.add(type);
      const subtype = typeof event.subtype === "string" ? event.subtype : "";
      if (type === "system" && subtype === "model_queue_status" && event.status === "queued") {
        queueObserved = true;
        queueType = typeof event.queue_type === "string" ? event.queue_type : queueType;
        queueCount = numberField(event, "queue_count") ?? queueCount;
        queueWaitElapsedMs = numberField(event, "queue_wait_elapsed_ms") ?? queueWaitElapsedMs;
        queueMaxWaitMs = numberField(event, "queue_max_wait_ms") ?? queueMaxWaitMs;
        serviceAvailable = typeof event.service_available === "boolean" ? event.service_available : serviceAvailable;
        armQueueTimer();
      } else if (type === "assistant" || type === "user" || type === "result") {
        markProgress();
      }
      writeState(queueTimedOut ? "provider_queue_timeout" : "running");
    } catch {
      invalidLines += 1;
      writeState(queueTimedOut ? "provider_queue_timeout" : "running");
    }
  });
  const exitCode = await new Promise<number | null>((resolve) => child.once("close", resolve));
  if (queueTimer) clearTimeout(queueTimer);
  cancellationWatcher.close();
  if (queueTimedOut) {
    writeState("provider_queue_timeout", "queue_wait_limit_exceeded", exitCode);
    process.exitCode = 2;
  } else if (cancelled) {
    writeState("cancelled_session_terminated", undefined, exitCode);
  } else if (exitCode === 0) {
    writeState("completed", undefined, exitCode);
  } else {
    writeState("failed", "qoder_process_failed", exitCode);
    process.exitCode = exitCode ?? 1;
  }
}

main().catch((error) => {
  process.stderr.write(`${error instanceof Error ? error.stack ?? error.message : String(error)}\n`);
  process.exitCode = 1;
});
