import assert from "node:assert/strict";
import { execFileSync } from "node:child_process";
import { mkdtempSync, mkdirSync, realpathSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import path from "node:path";
import { getJobRoot, getPlanRoot, resolveCanonicalGitRoot } from "./paths.js";

const scratch = mkdtempSync(path.join(tmpdir(), "codex-praetor-linked-plan-root-"));
const canonicalRepo = path.join(scratch, "canonical-repo");
const linkedRepo = path.join(scratch, "linked-worktree");

function git(args: string[], cwd: string) {
  return execFileSync("git", ["-C", cwd, ...args], { encoding: "utf8", windowsHide: true });
}

function sameExistingDirectory(left: string, right: string): boolean {
  // On Windows, Git may emit an 8.3 spelling while Node's resolver emits the
  // long spelling for the very same directory. realpathSync.native delegates
  // to the platform filesystem, which gives this fixture one identity check
  // instead of a lexical path-spelling check.
  const normalized = (value: string) => path.normalize(realpathSync.native(value));
  const leftPath = normalized(left);
  const rightPath = normalized(right);
  return process.platform === "win32"
    ? leftPath.toLowerCase() === rightPath.toLowerCase()
    : leftPath === rightPath;
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

  // Git and Windows can report the same existing directory through different
  // spellings (notably 8.3 profile paths on hosted runners). Compare the two
  // existing roots by filesystem identity, then keep the child-root checks
  // bound to the resolved root that production will actually use.
  const canonicalRoot = resolveCanonicalGitRoot(linkedRepo);
  const artifactRoot = path.join(canonicalRoot, ".codex-praetor");
  assert.ok(sameExistingDirectory(canonicalRoot, canonicalRepo));
  assert.equal(getPlanRoot(linkedRepo), path.join(artifactRoot, "plans"));
  assert.equal(getJobRoot(linkedRepo), path.join(artifactRoot, "jobs"));
  assert.notEqual(getPlanRoot(linkedRepo), path.join(linkedRepo, ".codex-praetor", "plans"));
  console.log("Linked worktree MCP plan/job root contract regression ok");
} finally {
  try { git(["worktree", "remove", linkedRepo], canonicalRepo); } catch { /* fixture cleanup */ }
  rmSync(scratch, { recursive: true, force: true });
}
