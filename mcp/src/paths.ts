import { spawnSync } from "node:child_process";
import { existsSync, realpathSync } from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const moduleDir = path.dirname(fileURLToPath(import.meta.url));

export function getMcpRoot(): string {
  return path.resolve(moduleDir, "..");
}

export function getProjectRoot(): string {
  return path.resolve(getMcpRoot(), "..");
}

export function getScriptRoot(): string {
  const sourceScriptRoot = path.join(getProjectRoot(), "scripts");
  if (existsSync(path.join(sourceScriptRoot, "invoke-codex-praetor.ps1"))) {
    return sourceScriptRoot;
  }

  const pluginSkillScriptRoot = path.join(getProjectRoot(), "skills", "codex-praetor", "scripts");
  if (existsSync(path.join(pluginSkillScriptRoot, "invoke-codex-praetor.ps1"))) {
    return pluginSkillScriptRoot;
  }

  return sourceScriptRoot;
}

export function getInvokeScriptPath(): string {
  return path.join(getScriptRoot(), "invoke-codex-praetor.ps1");
}

export function getPlanScriptPath(): string {
  return path.join(getScriptRoot(), "manage-codex-praetor-plan.ps1");
}

export function resolveExistingRepo(repo: string): string {
  if (!repo || !repo.trim()) {
    throw new Error("repo is required.");
  }
  const resolved = path.resolve(repo);
  if (!existsSync(resolved)) {
    throw new Error(`Repo path does not exist: ${resolved}`);
  }
  return realpathSync(resolved);
}

export function resolveGitRoot(repo: string): string {
  const result = spawnSync("git", ["-C", repo, "rev-parse", "--show-toplevel"], {
    encoding: "utf8",
    windowsHide: true
  });
  if (result.status === 0 && result.stdout.trim()) {
    return path.resolve(result.stdout.trim());
  }
  return repo;
}

export function getProjectArtifactRoot(repo: string): string {
  const projectRoot = resolveGitRoot(resolveExistingRepo(repo));
  return path.join(projectRoot, ".codex-praetor");
}

export function getJobRoot(repo: string): string {
  return path.join(getProjectArtifactRoot(repo), "jobs");
}

export function getPlanRoot(repo: string): string {
  return path.join(getProjectArtifactRoot(repo), "plans");
}

export function getLockRoot(repo: string): string {
  return path.join(getProjectArtifactRoot(repo), "locks");
}
