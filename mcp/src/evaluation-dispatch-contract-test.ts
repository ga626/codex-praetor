import assert from "node:assert/strict";
import { execFileSync } from "node:child_process";
import { existsSync, mkdirSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import os from "node:os";
import path from "node:path";
import { dispatchDryRunTool, dispatchPlanTaskTool, verifyEvaluationTaskTool } from "./tools.js";

const projectRoot = path.resolve(process.cwd(), "..");
const root = path.join(os.tmpdir(), `codex-praetor-evaluation-dispatch-${process.pid}-${Date.now()}`);
const repo = path.join(root, "repo");
const planId = "evaluation-dispatch-fixture";
const previousConfig = process.env.CODEX_PRAETOR_CONFIG;
const previousPortableFileHash = process.env.CODEX_PRAETOR_FORCE_PORTABLE_FILE_HASH;
const wrapperSource = readFileSync(path.join(projectRoot, "scripts", "dispatch", "invoke-codex-praetor.ps1"), "utf8");
const toolsSource = readFileSync(path.join(projectRoot, "mcp", "src", "tools.ts"), "utf8");

assert.doesNotMatch(wrapperSource, /\bGet-FileHash\b/, "dispatch must use the cross-version .NET SHA-256 helper rather than a runner-specific cmdlet");
assert.match(wrapperSource, /powershell\.exe/, "dispatch must use the canonical PowerShell executable in packaged child processes");
assert.match(wrapperSource, /git\.exe -C \$repoForGit rev-parse --show-toplevel/, "Qoder worktree preflight must capture Git output deterministically");
assert.match(toolsSource, /-TaskMaterialPath/);
assert.doesNotMatch(toolsSource, /args\.push\("-TaskMaterialBase64"/);

function run(file: string, args: string[]) {
  return execFileSync(file, args, { cwd: projectRoot, encoding: "utf8", stdio: ["ignore", "pipe", "pipe"] });
}

try {
  mkdirSync(repo, { recursive: true });
  writeFileSync(path.join(repo, "README.md"), "fixture\n", "utf8");
  mkdirSync(path.join(repo, "baseline-directory"), { recursive: true });
  writeFileSync(path.join(repo, "baseline-directory", "immutable.txt"), "fixture\n", "utf8");
  run("git", ["-C", repo, "init", "-q"]);
  run("git", ["-C", repo, "config", "user.email", "evaluation-dispatch@example.invalid"]);
  run("git", ["-C", repo, "config", "user.name", "Codex Praetor test"]);
  run("git", ["-C", repo, "add", "README.md", "baseline-directory/immutable.txt"]);
  run("git", ["-C", repo, "commit", "-qm", "fixture"]);

  const config = JSON.parse(readFileSync(path.join(projectRoot, "config", "codex-praetor-tiers.example.json"), "utf8").replace(/^\uFEFF/, ""));
  config.providers.qoder.cliPath = process.execPath;
  const configPath = path.join(root, "tiers.json");
  writeFileSync(configPath, `${JSON.stringify(config)}\n`, "utf8");
  process.env.CODEX_PRAETOR_CONFIG = configPath;
  process.env.CODEX_PRAETOR_FORCE_PORTABLE_FILE_HASH = "1";

  const baseCommit = run("git", ["-C", repo, "rev-parse", "HEAD"]).trim();
  const realCodePreflight = await dispatchDryRunTool({
    repo,
    task: "Contract-only preflight. Do not start a worker or edit files.",
    provider: "qoder",
    tier: "qoder-day-cheap",
    mode: "edit",
    run_mode: "blocking",
    task_kind: "code_change",
    task_family: "bounded_code_change",
    acceptance: "The exact frozen source contract is accepted for a later real dispatch.",
    worktree_name: "contract-preflight",
    base_commit: baseCommit,
    immutable_paths: ["README.md"],
    allowed_paths: ["README.md"],
    forbidden_paths: [".git", "**/*auth*"],
    required_checks: ["git diff --exit-code"],
    budget: { max_wall_seconds: 300 }
  });
  assert.equal(realCodePreflight.ok, true, String((realCodePreflight as Record<string, unknown>).stderr ?? ""));
  const realCodePreflightRecord = realCodePreflight as {
    display: { 阶段: string; 状态: string };
    stdout: string;
    job_id?: string;
    preflight_kind: string;
    real_worktree: boolean;
    base_commit: string;
    immutable_paths: string[];
  };
  assert.equal(realCodePreflightRecord.display.阶段, "真实代码任务合同预检");
  assert.equal(realCodePreflightRecord.display.状态, "可继续，未启动 worker");
  assert.equal(realCodePreflightRecord.job_id ?? "", "", "A contract preflight must not create a worker job.");
  assert.equal(realCodePreflightRecord.preflight_kind, "real_code_change");
  assert.equal(realCodePreflightRecord.real_worktree, true);
  assert.equal(realCodePreflightRecord.base_commit, baseCommit);
  assert.deepEqual(realCodePreflightRecord.immutable_paths, ["README.md"]);

  const unknownTier = await dispatchDryRunTool({
    repo,
    task: "Reject an unknown tier before a worker starts.",
    provider: "qoder",
    tier: "conservative",
    task_kind: "test_execution",
    allowed_paths: ["README.md"],
    forbidden_paths: [".git", "**/*auth*"],
    required_checks: ["git diff --exit-code"],
    budget: { max_wall_seconds: 300 }
  });
  assert.equal(unknownTier.ok, false);
  assert.equal((unknownTier as Record<string, unknown>).failure_class, "unknown_tier");
  assert.equal((unknownTier as Record<string, unknown>).field, "tier");
  assert.equal((unknownTier as Record<string, unknown>).retryable_without_worker, true);

  const absoluteImmutable = await dispatchDryRunTool({
    repo,
    task: "Reject absolute immutable paths before a worker starts.",
    provider: "qoder",
    tier: "qoder-day-cheap",
    task_kind: "code_change",
    mode: "edit",
    base_commit: baseCommit,
    immutable_paths: [path.join(repo, "README.md")]
  });
  assert.equal(absoluteImmutable.ok, false);
  assert.equal((absoluteImmutable as Record<string, unknown>).failure_class, "invalid_immutable_path");

  const directoryImmutable = await dispatchDryRunTool({
    repo,
    task: "Reject directory immutable paths before a worker starts.",
    provider: "qoder",
    tier: "qoder-day-cheap",
    task_kind: "code_change",
    mode: "edit",
    base_commit: baseCommit,
    immutable_paths: ["baseline-directory"]
  });
  assert.equal(directoryImmutable.ok, false);
  assert.equal((directoryImmutable as Record<string, unknown>).failure_class, "immutable_path_not_file");

  const planRoot = path.join(repo, ".codex-praetor", "plans");
  const preparation = run("powershell.exe", [
    "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", path.join(projectRoot, "scripts", "evaluation", "initialize-codex-praetor-evaluation.ps1"),
    // The plan's frozen base must name the repository that will receive the
    // disposable worktree, not the Praetor source repository which supplies
    // the suite and immutable templates.
    "-ProjectRoot", repo,
    "-SuitePath", path.join(projectRoot, "config", "evaluation-suite.json"),
    "-TemplateRoot", path.join(projectRoot, "config", "evaluation-task-templates"),
    "-PlanScript", path.join(projectRoot, "scripts", "dispatch", "manage-codex-praetor-plan.ps1"),
    "-Action", "Prepare", "-PlanRoot", planRoot, "-PlanId", planId, "-Apply"
  ]);
  assert.match(preparation, /plan_path/);

  const bounded = await dispatchPlanTaskTool({ repo, plan_id: planId, task_id: "bounded-test-fix", provider: "qoder", tier: "qoder-day-cheap", dry_run: true });
  const boundedRecord = bounded as Record<string, unknown>;
  assert.equal(bounded.ok, true, String(boundedRecord.stderr ?? boundedRecord.message ?? ""));
  const preparedPlanPath = path.join(planRoot, planId, "plan.json");
  const boundedPlan = JSON.parse(readFileSync(preparedPlanPath, "utf8").replace(/^\uFEFF/, ""));
  const boundedTask = boundedPlan.tasks.find((task: { task_id: string }) => task.task_id === "bounded-test-fix");
  assert.match(String(boundedTask.base_commit ?? ""), /^[0-9a-f]{40}$/i);
  assert.notEqual(String(boundedTask.base_commit ?? ""), baseCommit, "The evaluation baseline must be a disposable fixture commit, not the source checkout HEAD.");
  assert.equal(String(boundedRecord.base_commit ?? ""), String(boundedTask.base_commit));
  assert.deepEqual(boundedRecord.immutable_paths, [
    ".codex-praetor/evaluation/bounded-test-fix/test.ps1",
    ".codex-praetor/evaluation/bounded-test-fix/task.json"
  ]);
  for (const immutablePath of boundedRecord.immutable_paths as string[]) {
    assert.match(run("git", ["-C", repo, "rev-parse", "--verify", `${String(boundedTask.base_commit)}:${immutablePath}`]).trim(), /^[0-9a-f]{40}$/i);
  }
  assert.ok(existsSync(path.join(String(boundedTask.task_material.source_root), "task-material.json")), "Prepared material needs a durable dispatch contract file.");
  assert.equal(typeof boundedTask.task_material, "object", "Copied material remains available only for regression fixtures.");
  delete boundedTask.task_material;
  writeFileSync(preparedPlanPath, `${JSON.stringify(boundedPlan, null, 2)}\n`, "utf8");
  const missingMaterial = await verifyEvaluationTaskTool({ repo, plan_id: planId, task_id: "bounded-test-fix", worktree: repo });
  const missingMaterialRecord = missingMaterial as Record<string, unknown>;
  assert.equal(missingMaterial.ok, false);
  assert.match(String(missingMaterialRecord.message ?? ""), /(immutable material|task-material)/);

  const dispatched = await dispatchPlanTaskTool({ repo, plan_id: planId, task_id: "fixed-profile-regression", provider: "qoder", tier: "qoder-day-cheap", dry_run: true });
  const dispatchedRecord = dispatched as Record<string, unknown>;
  assert.equal(dispatched.ok, true, String(dispatchedRecord.stderr ?? dispatchedRecord.message ?? ""));
  assert.equal(dispatchedRecord.task_kind, "test_execution");
  assert.match(String(dispatchedRecord.command ?? ""), /qoder-stream-json-runner\.js --options-file/);
  assert.match(wrapperSource, /"--print",\s*\n\s*"--output-format", "stream-json"/);
  assert.match(wrapperSource, /"--model", \$model/);
  assert.match(wrapperSource, /distribution qoder_cn must use connectionMode=supervised_cli_stream_json/);
  assert.match(wrapperSource, /distribution qoder_global requires explicit connectionMode=qoder_agent_sdk/);

  config.providers.qoder.distribution = "qoder_global";
  config.providers.qoder.connectionMode = "qoder_agent_sdk";
  writeFileSync(configPath, `${JSON.stringify(config)}\n`, "utf8");
  const globalDispatch = await dispatchDryRunTool({
    repo,
    task: "Contract-only global Qoder route probe. Do not start a worker.",
    provider: "qoder",
    tier: "qoder-day-cheap",
    mode: "readonly",
    run_mode: "blocking",
    task_kind: "test_execution",
    task_family: "fixed_test_execution",
    acceptance: "The explicitly opted-in global Qoder route resolves to its SDK runner.",
    allowed_paths: ["README.md"],
    forbidden_paths: [".git", "**/*auth*"],
    required_checks: ["git diff --exit-code"],
    budget: { max_wall_seconds: 300 }
  });
  assert.equal(globalDispatch.ok, true, String((globalDispatch as Record<string, unknown>).stderr ?? ""));
  assert.match(String((globalDispatch as Record<string, unknown>).command ?? ""), /qoder-sdk-runner\.js --options-file/);

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
