import assert from "node:assert/strict";
import { execFileSync } from "node:child_process";
import { existsSync, mkdirSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import os from "node:os";
import path from "node:path";
import { dispatchPlanTaskTool } from "./tools.js";

const projectRoot = path.resolve(process.cwd(), "..");
const root = path.join(os.tmpdir(), `codex-praetor-evaluation-dispatch-${process.pid}-${Date.now()}`);
const repo = path.join(root, "repo");
const planId = "evaluation-dispatch-fixture";
const previousConfig = process.env.CODEX_PRAETOR_CONFIG;
const previousPortableFileHash = process.env.CODEX_PRAETOR_FORCE_PORTABLE_FILE_HASH;
const wrapperSource = readFileSync(path.join(projectRoot, "scripts", "dispatch", "invoke-codex-praetor.ps1"), "utf8");

assert.doesNotMatch(wrapperSource, /\bGet-FileHash\b/, "dispatch must use the cross-version .NET SHA-256 helper rather than a runner-specific cmdlet");

function run(file: string, args: string[]) {
  return execFileSync(file, args, { cwd: projectRoot, encoding: "utf8", stdio: ["ignore", "pipe", "pipe"] });
}

try {
  mkdirSync(repo, { recursive: true });
  writeFileSync(path.join(repo, "README.md"), "fixture\n", "utf8");
  run("git", ["-C", repo, "init", "-q"]);
  run("git", ["-C", repo, "config", "user.email", "evaluation-dispatch@example.invalid"]);
  run("git", ["-C", repo, "config", "user.name", "Codex Praetor test"]);
  run("git", ["-C", repo, "add", "README.md"]);
  run("git", ["-C", repo, "commit", "-qm", "fixture"]);

  const config = JSON.parse(readFileSync(path.join(projectRoot, "config", "codex-praetor-tiers.example.json"), "utf8").replace(/^\uFEFF/, ""));
  config.providers.qoder.cliPath = process.execPath;
  const configPath = path.join(root, "tiers.json");
  writeFileSync(configPath, `${JSON.stringify(config)}\n`, "utf8");
  process.env.CODEX_PRAETOR_CONFIG = configPath;
  process.env.CODEX_PRAETOR_FORCE_PORTABLE_FILE_HASH = "1";

  const planRoot = path.join(repo, ".codex-praetor", "plans");
  const preparation = run("powershell.exe", [
    "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", path.join(projectRoot, "scripts", "evaluation", "initialize-codex-praetor-evaluation.ps1"),
    "-ProjectRoot", projectRoot, "-Action", "Prepare", "-PlanRoot", planRoot, "-PlanId", planId, "-Apply"
  ]);
  assert.match(preparation, /plan_path/);

  const dispatched = await dispatchPlanTaskTool({ repo, plan_id: planId, task_id: "fixed-profile-regression", provider: "qoder", tier: "qoder-day-cheap", dry_run: true });
  const dispatchedRecord = dispatched as Record<string, unknown>;
  assert.equal(dispatched.ok, true, String(dispatchedRecord.stderr ?? dispatchedRecord.message ?? ""));
  assert.equal(dispatchedRecord.task_kind, "test_execution");
  assert.match(String(dispatchedRecord.command ?? ""), /--tools Read Grep Glob Bash/);

  const planPath = path.join(planRoot, planId, "plan.json");
  assert.ok(existsSync(planPath));
  const plan = JSON.parse(readFileSync(planPath, "utf8").replace(/^\uFEFF/, ""));
  const fixed = plan.tasks.find((task: { task_id: string }) => task.task_id === "fixed-profile-regression");
  fixed.task_kind = "local_audit";
  writeFileSync(planPath, `${JSON.stringify(plan, null, 2)}\n`, "utf8");
  const rejected = await dispatchPlanTaskTool({ repo, plan_id: planId, task_id: "fixed-profile-regression", provider: "qoder", dry_run: true });
  const rejectedRecord = rejected as Record<string, unknown>;
  assert.equal(rejected.ok, false);
  assert.match(String(rejectedRecord.message ?? ""), /downgraded to local_audit/);
  console.log("evaluation dispatch contract regression ok");
} finally {
  if (previousConfig === undefined) delete process.env.CODEX_PRAETOR_CONFIG;
  else process.env.CODEX_PRAETOR_CONFIG = previousConfig;
  if (previousPortableFileHash === undefined) delete process.env.CODEX_PRAETOR_FORCE_PORTABLE_FILE_HASH;
  else process.env.CODEX_PRAETOR_FORCE_PORTABLE_FILE_HASH = previousPortableFileHash;
  rmSync(root, { recursive: true, force: true });
}
