import assert from "node:assert/strict";
import { execFileSync } from "node:child_process";
import { existsSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import os from "node:os";
import path from "node:path";
import { dispatchReadinessTool, dispatchTool, planTool } from "./tools.js";

const projectRoot = path.resolve(process.cwd(), "..");
const root = mkdtempSync(path.join(os.tmpdir(), "codex-praetor-executive-dispatch-"));
const repo = path.join(root, "repo");
const previousConfig = process.env.CODEX_PRAETOR_CONFIG;

function run(file: string, args: string[]) {
  return execFileSync(file, args, { cwd: projectRoot, encoding: "utf8", stdio: ["ignore", "pipe", "pipe"] });
}

try {
  run("git", ["init", "-q", repo]);
  run("git", ["-C", repo, "config", "user.email", "executive-dispatch@example.invalid"]);
  run("git", ["-C", repo, "config", "user.name", "Codex Praetor test"]);
  writeFileSync(path.join(repo, "README.md"), "fixture\n", "utf8");
  run("git", ["-C", repo, "add", "README.md"]);
  run("git", ["-C", repo, "commit", "-qm", "fixture"]);
  const baseCommit = run("git", ["-C", repo, "rev-parse", "HEAD"]).trim();

  const direct = await dispatchTool({
    repo,
    task: "This must not create a worker without a durable plan.",
    provider: "qoder",
    task_family: "read_only_diagnosis",
    task_kind: "local_audit",
    mode: "readonly"
  });
  assert.equal(direct.ok, false);
  assert.equal(direct.failure_class, "use_dispatch_plan_task");
  assert.equal(direct.job_id, "");
  assert.equal(existsSync(path.join(repo, ".codex-praetor", "jobs")), false, "generic dispatch must stop before any job root is created");

  const config = JSON.parse(readFileSync(path.join(projectRoot, "config", "codex-praetor-tiers.example.json"), "utf8").replace(/^\uFEFF/, ""));
  config.providers.qoder.cliPath = process.execPath;
  const configPath = path.join(root, "tiers.json");
  writeFileSync(configPath, `${JSON.stringify(config)}\n`, "utf8");
  process.env.CODEX_PRAETOR_CONFIG = configPath;

  const readiness = await dispatchReadinessTool({
    repo,
    task: "Resolve the exact tuple only; do not launch a worker.",
    provider: "qoder",
    tier: "qoder-day-cheap",
    mode: "readonly",
    task_kind: "local_audit",
    task_family: "read_only_diagnosis",
    acceptance: "The exact tuple is reported without a job.",
    allowed_paths: ["README.md"],
    forbidden_paths: [".git"],
    required_checks: ["git status --short"],
    budget: { max_wall_seconds: 300 },
    base_commit: baseCommit
  });
  assert.equal(readiness.ok, true, String(readiness.stderr));
  assert.ok(["direct_ready", "bootstrap_eligible"].includes(readiness.dispatch_readiness));
  assert.equal(readiness.connection_mode, "supervised_cli_stream_json");
  assert.equal(existsSync(path.join(repo, ".codex-praetor", "jobs")), false, "readiness probe must never create a worker job");

  const plan = await planTool({
    repo,
    plan_id: "executive-dispatch-fixture",
    title: "Executive dispatch state fixture",
    tasks: [{
      task_id: "one-task",
      title: "A bounded readonly task",
      task_family: "read_only_diagnosis",
      task_kind: "local_audit",
      mode: "readonly",
      acceptance: "A result is independently checked by Codex.",
      allowed_paths: ["README.md"],
      forbidden_paths: [".git"],
      required_checks: ["git status --short"],
      budget: { max_wall_seconds: 300 }
    }]
  });
  assert.equal(plan.ok, true);
  const manager = path.join(projectRoot, "scripts", "dispatch", "manage-codex-praetor-plan.ps1");
  run("powershell.exe", ["-NoProfile", "-ExecutionPolicy", "Bypass", "-File", manager, "-Action", "SetDispatchState", "-PlanId", "executive-dispatch-fixture", "-PlanRoot", path.join(repo, ".codex-praetor", "plans"), "-TaskId", "one-task", "-DispatchState", "bootstrap_eligible", "-NextAction", "Dispatch the same task once.", "-OutputJson"]);
  const persisted = JSON.parse(readFileSync(String(plan.plan_path), "utf8").replace(/^\uFEFF/, ""));
  assert.equal(persisted.tasks[0].dispatch_state, "bootstrap_eligible");
  assert.equal(persisted.tasks[0].next_action, "Dispatch the same task once.");
  console.log("executive dispatch control regression ok");
} finally {
  if (previousConfig === undefined) delete process.env.CODEX_PRAETOR_CONFIG;
  else process.env.CODEX_PRAETOR_CONFIG = previousConfig;
  rmSync(root, { recursive: true, force: true });
}
