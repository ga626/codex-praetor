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
  const sourceScriptRoot = path.join(getProjectRoot(), "scripts", "dispatch");
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

export function getEvaluationInitializerPath(): string {
  const source = path.join(getProjectRoot(), "scripts", "evaluation", "initialize-codex-praetor-evaluation.ps1");
  if (existsSync(source)) {
    return source;
  }
  return path.join(getScriptRoot(), "initialize-codex-praetor-evaluation.ps1");
}

export function getEvaluationVerifierPath(): string {
  const source = path.join(getProjectRoot(), "scripts", "evaluation", "verify-codex-praetor-task-material.ps1");
  if (existsSync(source)) {
    return source;
  }
  return path.join(getScriptRoot(), "verify-codex-praetor-task-material.ps1");
}

export function getHealthScriptPath(): string {
  const source = path.join(getProjectRoot(), "scripts", "verify", "get-codex-praetor-health.ps1");
  if (existsSync(source)) {
    return source;
  }
  return path.join(getScriptRoot(), "get-codex-praetor-health.ps1");
}

export function getCancelScriptPath(): string {
  return path.join(getScriptRoot(), "cancel-codex-praetor-job.ps1");
}

export function getRuntimeContractPath(): string {
  const source = path.join(getProjectRoot(), "config", "runtime-contract.json");
  if (existsSync(source)) {
    return source;
  }
  return path.join(getProjectRoot(), "runtime-contract.json");
}

/**
 * Resolve a data file that is required by the MCP at runtime.
 * Source checkouts keep canonical data in config/; installed plugins carry the
 * same immutable copy under data/ because config/ is not part of the plugin.
 */
export function getRuntimeDataPath(relativePath: string): string {
  const source = path.join(getProjectRoot(), "config", relativePath);
  if (existsSync(source)) {
    return source;
  }
  return path.join(getProjectRoot(), "data", relativePath);
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
