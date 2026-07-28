import { existsSync, readFileSync, renameSync, watch, writeFileSync } from "node:fs";
import path from "node:path";
import { query, qodercliAuth } from "@qoder-ai/qoder-agent-sdk";

type RunnerOptions = {
  schema: "codex-praetor-qoder-sdk-runner/v1";
  job_id: string;
  cwd: string;
  prompt: string;
  cli_path: string;
  model: string;
  permission_mode: "dontAsk" | "bypassPermissions";
  allowed_tools: string[];
  allowed_paths: string[];
  forbidden_paths: string[];
  required_checks: string[];
  sdk_environment?: Record<string, string>;
  state_path: string;
};

type State = {
  schema: "codex-praetor-qoder-sdk-session/v1";
  job_id: string;
  connection_mode: "qoder_agent_sdk";
  state: "starting" | "running" | "completed" | "cancelled_session_terminated" | "failed";
  abort_requested: boolean;
  iteration_ended: boolean;
  result_observed: boolean;
  tool_events: number;
  result_subtype?: string;
  provider_result_error?: boolean;
  provider_result_message?: string;
  denied_tool_requests?: number;
  updated_at: string;
  error?: string;
};

function normalizeStringArray(value: unknown) {
  if (Array.isArray(value)) return value.filter((entry): entry is string => typeof entry === "string");
  return typeof value === "string" && value.trim() !== "" ? [value] : [];
}

function readOptions(): RunnerOptions {
  const index = process.argv.indexOf("--options-file");
  if (index < 0 || !process.argv[index + 1]) {
    throw new Error("Missing --options-file for Qoder SDK runner.");
  }
  // The dispatcher writes this file inside the job directory. It contains the
  // task contract but never credentials; qodercliAuth() reuses normal login
  // state without exposing it to this process's output.
  const value = JSON.parse(readFileSync(process.argv[index + 1], "utf8").replace(/^\uFEFF/, "")) as RunnerOptions;
  value.allowed_tools = normalizeStringArray(value.allowed_tools);
  value.allowed_paths = normalizeStringArray(value.allowed_paths);
  value.forbidden_paths = normalizeStringArray(value.forbidden_paths);
  value.required_checks = normalizeStringArray(value.required_checks);
  if (value.schema !== "codex-praetor-qoder-sdk-runner/v1") {
    throw new Error("Unsupported Qoder SDK runner options schema.");
  }
  if (!value.cwd || !value.prompt || !value.cli_path || !value.state_path) {
    throw new Error("Qoder SDK runner options are incomplete.");
  }
  return value;
}

function writeState(options: RunnerOptions, state: Omit<State, "schema" | "job_id" | "connection_mode" | "updated_at">) {
  const payload: State = {
    schema: "codex-praetor-qoder-sdk-session/v1",
    job_id: options.job_id,
    connection_mode: "qoder_agent_sdk",
    ...state,
    updated_at: new Date().toISOString()
  };
  const temporary = `${options.state_path}.${process.pid}.tmp`;
  writeFileSync(temporary, `${JSON.stringify(payload)}\n`, "utf8");
  renameSync(temporary, options.state_path);
}

function insideRoot(root: string, candidate: string) {
  const resolvedRoot = path.resolve(root);
  const resolvedCandidate = path.resolve(root, candidate);
  return resolvedCandidate === resolvedRoot || resolvedCandidate.startsWith(`${resolvedRoot}${path.sep}`);
}

function normalizeRelative(value: string) {
  return value.replaceAll("\\", "/").replace(/^\.\//, "");
}

function globMatches(pattern: string, value: string) {
  const escaped = normalizeRelative(pattern)
    .replace(/[|\\{}()[\]^$+?.]/g, "\\$&")
    .replaceAll("**", "::DOUBLE_STAR::")
    .replaceAll("*", "[^/]*")
    .replaceAll("::DOUBLE_STAR::", ".*");
  return new RegExp(`^${escaped}$`, "i").test(normalizeRelative(value));
}

function pathAllowed(options: RunnerOptions, candidate: unknown) {
  if (typeof candidate !== "string" || candidate.trim() === "") return true;
  if (path.isAbsolute(candidate) ? !insideRoot(options.cwd, candidate) : candidate.split(/[\\/]/).includes("..")) return false;
  const relative = normalizeRelative(path.relative(options.cwd, path.resolve(options.cwd, candidate)));
  if (relative.startsWith("../")) return false;
  if (options.forbidden_paths.some((entry) => globMatches(entry, relative))) return false;
  return options.allowed_paths.some((entry) => globMatches(entry, relative));
}

function requestedPathInputs(input: Record<string, unknown>) {
  const pathLikeKeys = new Set(["path", "file_path", "filePath", "directory", "cwd", "notebook_path", "notebookPath"]);
  return Object.entries(input)
    .filter(([key, value]) => pathLikeKeys.has(key) && typeof value === "string")
    .map(([, value]) => value as string);
}

function createToolGuard(options: RunnerOptions, onDeny: () => void) {
  const allowedTools = new Set(options.allowed_tools);
  const requiredChecks = new Set(options.required_checks.map((entry) => entry.trim()));
  return async (toolName: string, input: Record<string, unknown>) => {
    if (!allowedTools.has(toolName)) {
      onDeny();
      return { behavior: "deny" as const, message: `Tool ${toolName} is outside the Codex task contract.`, interrupt: true };
    }
    if (toolName === "Bash") {
      const command = typeof input.command === "string" ? input.command.trim() : "";
      if (!requiredChecks.has(command)) {
        onDeny();
        return { behavior: "deny" as const, message: "Shell command is not one of the declared deterministic checks.", interrupt: true };
      }
      return { behavior: "allow" as const };
    }
    const paths = requestedPathInputs(input);
    if (paths.some((candidate) => !pathAllowed(options, candidate))) {
      onDeny();
      return { behavior: "deny" as const, message: "Requested path is outside the declared allowlist or inside a forbidden path.", interrupt: true };
    }
    return { behavior: "allow" as const };
  };
}

async function main() {
  const options = readOptions();
  const cancelPath = path.join(path.dirname(options.state_path), "cancel-request.json");
  const controller = new AbortController();
  let abortRequested = false;
  let toolEvents = 0;
  let resultObserved = false;
  let resultSubtype = "";
  let providerResultError = false;
  let providerResultMessage = "";
  let deniedToolRequests = 0;
  let watcher: ReturnType<typeof watch> | undefined;

  const abortSession = () => {
    if (!abortRequested) {
      abortRequested = true;
      controller.abort();
    }
  };
  if (existsSync(cancelPath)) abortSession();
  watcher = watch(path.dirname(cancelPath), (_event, filename) => {
    if (filename?.toString() === path.basename(cancelPath) && existsSync(cancelPath)) abortSession();
  });

  writeState(options, { state: "starting", abort_requested: abortRequested, iteration_ended: false, result_observed: false, tool_events: 0 });
  try {
    writeState(options, { state: "running", abort_requested: abortRequested, iteration_ended: false, result_observed: false, tool_events: 0 });
    let resultText = "";
    for await (const message of query({
      prompt: options.prompt,
      options: {
        auth: qodercliAuth(),
        cwd: options.cwd,
        model: options.model,
        pathToQoderCLIExecutable: options.cli_path,
        allowedTools: options.allowed_tools,
        permissionMode: options.permission_mode,
        canUseTool: createToolGuard(options, () => { deniedToolRequests += 1; }),
        abortController: controller,
        stderr: (data: string) => process.stderr.write(data),
        env: { ...process.env, ...(options.sdk_environment ?? {}), QODERCLI_PATH: options.cli_path }
      }
    })) {
      if (message.type === "assistant" || message.type === "user") toolEvents += 1;
      if (message.type === "result") {
        resultObserved = true;
        resultSubtype = typeof (message as { subtype?: unknown }).subtype === "string" ? (message as { subtype: string }).subtype : "";
        providerResultError = Boolean((message as { is_error?: unknown }).is_error);
        const candidate = (message as { result?: unknown }).result;
        if (typeof candidate === "string") resultText = candidate;
        providerResultMessage = resultText.slice(0, 500);
      }
      writeState(options, { state: "running", abort_requested: abortRequested, iteration_ended: false, result_observed: resultObserved, tool_events: toolEvents, result_subtype: resultSubtype, provider_result_error: providerResultError, provider_result_message: providerResultMessage, denied_tool_requests: deniedToolRequests });
    }
    const state = abortRequested ? "cancelled_session_terminated" : "completed";
    writeState(options, { state, abort_requested: abortRequested, iteration_ended: true, result_observed: resultObserved, tool_events: toolEvents, result_subtype: resultSubtype, provider_result_error: providerResultError, provider_result_message: providerResultMessage, denied_tool_requests: deniedToolRequests });
    if (!abortRequested && resultText) process.stdout.write(`${resultText}\n`);
  } catch (error) {
    const message = error instanceof Error ? error.message : String(error);
    writeState(options, { state: abortRequested ? "cancelled_session_terminated" : "failed", abort_requested: abortRequested, iteration_ended: abortRequested, result_observed: resultObserved, tool_events: toolEvents, result_subtype: resultSubtype, provider_result_error: providerResultError, provider_result_message: providerResultMessage, denied_tool_requests: deniedToolRequests, error: message });
    if (!abortRequested) throw error;
  } finally {
    watcher?.close();
  }
}

main().catch((error) => {
  process.stderr.write(`${error instanceof Error ? error.stack ?? error.message : String(error)}\n`);
  process.exitCode = 1;
});
