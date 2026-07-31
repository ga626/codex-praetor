import assert from "node:assert/strict";
import { execFileSync } from "node:child_process";
import { mkdtempSync, mkdirSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import path from "node:path";
import { getJobRoot, getPlanRoot, resolveCanonicalGitRoot } from "./paths.js";

const scratch = mkdtempSync(path.join(tmpdir(), "codex-praetor-linked-plan-root-"));
const canonicalRepo = path.join(scratch, "canonical-repo");
const linkedRepo = path.join(scratch, "linked-worktree");

function git(args: string[], cwd: string) {
  return execFileSync("git", ["-C", cwd, ...args], { encoding: "utf8", windowsHide: true });
}

try {
  mkdirSync(canonicalRepo, { recursive: true });
  writeFileSync(path.join(canonicalRepo, "README.md"), "fixture\n", "utf8");
  git(["init", "-q"], canonicalRepo);
  git(["config", "user.email", "dispatch-test@example.invalid"], canonicalRepo);
  git(["config", "user.name", "Codex Praetor test"], canonicalRepo);
  git(["add", "README.md"], canonicalRepo);
  git(["commit", "-qm", "fixture"], canonicalRepo);
  git(["worktree", "add", "-q", "-b", "linked-plan-root", linkedRepo, "HEAD"], canonicalRepo);

  const artifactRoot = path.join(canonicalRepo, ".codex-praetor");
  assert.equal(resolveCanonicalGitRoot(linkedRepo), canonicalRepo);
  assert.equal(getPlanRoot(linkedRepo), path.join(artifactRoot, "plans"));
  assert.equal(getJobRoot(linkedRepo), path.join(artifactRoot, "jobs"));
  assert.notEqual(getPlanRoot(linkedRepo), path.join(linkedRepo, ".codex-praetor", "plans"));
  console.log("Linked worktree MCP plan/job root contract regression ok");
} finally {
  try { git(["worktree", "remove", linkedRepo], canonicalRepo); } catch { /* fixture cleanup */ }
  rmSync(scratch, { recursive: true, force: true });
}
