import { createHash, randomUUID } from "node:crypto";
import { existsSync, mkdirSync, readFileSync, renameSync, rmdirSync, unlinkSync, writeFileSync } from "node:fs";
import path from "node:path";
import { getProjectArtifactRoot, resolveExistingRepo } from "./paths.js";

export type SessionModeContext = "inactive" | "active" | "unavailable";

export interface SessionModePolicy {
  schema: "codex-praetor-session-policy/v1";
  scope: "host_thread_and_canonical_repo";
  mode: "prefer_external_worker";
  state: "active" | "closing" | "revoked";
  thread_id_sha256: string;
  mode_session_id: string;
  activated_at: string;
  revoked_at?: string;
}

export interface SessionModeView {
  available: boolean;
  context: SessionModeContext;
  scope: "host_thread_and_canonical_repo";
  state: "active" | "closing" | "inactive" | "revoked" | "unavailable";
  activated_at?: string;
  revoked_at?: string;
  mode_session_id?: string;
}

function currentThreadId(): string {
  return String(process.env.CODEX_THREAD_ID ?? "").trim();
}

function hashThreadId(threadId: string): string {
  return createHash("sha256").update(threadId, "utf8").digest("hex");
}

function policyDirectory(repo: string, threadId: string): string {
  return path.join(getProjectArtifactRoot(repo), "session-policies", hashThreadId(threadId));
}

function policyPath(repo: string, threadId: string): string {
  return path.join(policyDirectory(repo, threadId), "mode.json");
}

function readPolicy(repo: string, threadId: string): SessionModePolicy | null {
  const target = policyPath(repo, threadId);
  if (!existsSync(target)) return null;
  const parsed = JSON.parse(readFileSync(target, "utf8").replace(/^\uFEFF/, "")) as Partial<SessionModePolicy>;
  if (
    parsed.schema !== "codex-praetor-session-policy/v1" ||
    parsed.scope !== "host_thread_and_canonical_repo" ||
    parsed.mode !== "prefer_external_worker" ||
    (parsed.state !== "active" && parsed.state !== "closing" && parsed.state !== "revoked") ||
    parsed.thread_id_sha256 !== hashThreadId(threadId) ||
    typeof parsed.mode_session_id !== "string" ||
    !parsed.mode_session_id ||
    typeof parsed.activated_at !== "string" ||
    !parsed.activated_at
  ) {
    throw new Error("The current Codex Executive policy is malformed or does not match this host thread.");
  }
  return parsed as SessionModePolicy;
}

function withPolicyLock<T>(repo: string, threadId: string, action: () => T): T {
  const directory = policyDirectory(repo, threadId);
  mkdirSync(directory, { recursive: true });
  const lockPath = path.join(directory, ".mode.lock");
  try {
    mkdirSync(lockPath);
  } catch (error) {
    const code = typeof error === "object" && error && "code" in error ? String(error.code) : "";
    if (code === "EEXIST") throw new Error("Codex Executive mode is already changing for this conversation; read its status and retry.");
    throw error;
  }
  try {
    return action();
  } finally {
    try {
      rmdirSync(lockPath);
    } catch {
      // A failed cleanup must not alter the already committed policy. The next
      // caller gets a clear busy error instead of a concurrent write.
    }
  }
}

function writePolicyAtomically(repo: string, threadId: string, policy: SessionModePolicy): void {
  const target = policyPath(repo, threadId);
  const temporary = `${target}.${process.pid}.${randomUUID()}.tmp`;
  writeFileSync(temporary, `${JSON.stringify(policy, null, 2)}\n`, "utf8");
  try {
    renameSync(temporary, target);
  } finally {
    if (existsSync(temporary)) unlinkSync(temporary);
  }
}

function view(policy: SessionModePolicy | null, available: boolean): SessionModeView {
  if (!available) {
    return { available: false, context: "unavailable", scope: "host_thread_and_canonical_repo", state: "unavailable" };
  }
  if (!policy) {
    return { available: true, context: "inactive", scope: "host_thread_and_canonical_repo", state: "inactive" };
  }
  return {
    available: true,
    context: policy.state === "active" ? "active" : "inactive",
    scope: policy.scope,
    state: policy.state,
    activated_at: policy.activated_at,
    revoked_at: policy.revoked_at,
    mode_session_id: policy.mode_session_id
  };
}

export function getCurrentThreadId(): string {
  return currentThreadId();
}

export function getSessionMode(repoInput: string): { policy: SessionModePolicy | null; view: SessionModeView } {
  const repo = resolveExistingRepo(repoInput);
  const threadId = currentThreadId();
  if (!threadId) return { policy: null, view: view(null, false) };
  const policy = readPolicy(repo, threadId);
  return { policy: policy?.state === "active" ? policy : null, view: view(policy, true) };
}

export function enableSessionMode(repoInput: string): { repo: string; policy: SessionModePolicy; view: SessionModeView; already_active: boolean } {
  const repo = resolveExistingRepo(repoInput);
  const threadId = currentThreadId();
  if (!threadId) throw new Error("The current host did not provide CODEX_THREAD_ID, so Codex Executive mode cannot safely bind to this conversation.");
  return withPolicyLock(repo, threadId, () => {
    const existing = readPolicy(repo, threadId);
    if (existing?.state === "active") return { repo, policy: existing, view: view(existing, true), already_active: true };
    if (existing?.state === "closing") {
      throw new Error("Codex Executive mode is waiting for its active workers to reach terminal state; read status before enabling it again.");
    }
    const policy: SessionModePolicy = {
      schema: "codex-praetor-session-policy/v1",
      scope: "host_thread_and_canonical_repo",
      mode: "prefer_external_worker",
      state: "active",
      thread_id_sha256: hashThreadId(threadId),
      mode_session_id: randomUUID(),
      activated_at: new Date().toISOString()
    };
    writePolicyAtomically(repo, threadId, policy);
    return { repo, policy, view: view(policy, true), already_active: false };
  });
}

export function revokeSessionMode(repoInput: string): { repo: string; policy: SessionModePolicy | null; view: SessionModeView } {
  const repo = resolveExistingRepo(repoInput);
  const threadId = currentThreadId();
  if (!threadId) throw new Error("The current host did not provide CODEX_THREAD_ID, so Codex Executive mode cannot safely change this conversation.");
  return withPolicyLock(repo, threadId, () => {
    const existing = readPolicy(repo, threadId);
    if (!existing || (existing.state !== "active" && existing.state !== "closing")) return { repo, policy: null, view: view(existing, true) };
    const revoked: SessionModePolicy = { ...existing, state: "revoked", revoked_at: new Date().toISOString() };
    writePolicyAtomically(repo, threadId, revoked);
    return { repo, policy: revoked, view: view(revoked, true) };
  });
}

export function beginSessionModeClose(repoInput: string): { repo: string; policy: SessionModePolicy | null; view: SessionModeView } {
  const repo = resolveExistingRepo(repoInput);
  const threadId = currentThreadId();
  if (!threadId) throw new Error("The current host did not provide CODEX_THREAD_ID, so Codex Executive mode cannot safely change this conversation.");
  return withPolicyLock(repo, threadId, () => {
    const existing = readPolicy(repo, threadId);
    if (!existing || existing.state !== "active") return { repo, policy: null, view: view(existing, true) };
    const closing: SessionModePolicy = { ...existing, state: "closing" };
    writePolicyAtomically(repo, threadId, closing);
    return { repo, policy: closing, view: view(closing, true) };
  });
}

export function resumeSessionMode(repoInput: string, modeSessionId: string): { repo: string; policy: SessionModePolicy | null; view: SessionModeView } {
  const repo = resolveExistingRepo(repoInput);
  const threadId = currentThreadId();
  if (!threadId) throw new Error("The current host did not provide CODEX_THREAD_ID, so Codex Executive mode cannot safely change this conversation.");
  return withPolicyLock(repo, threadId, () => {
    const existing = readPolicy(repo, threadId);
    if (!existing || existing.state !== "closing" || existing.mode_session_id !== modeSessionId) return { repo, policy: null, view: view(existing, true) };
    const active: SessionModePolicy = { ...existing, state: "active" };
    writePolicyAtomically(repo, threadId, active);
    return { repo, policy: active, view: view(active, true) };
  });
}
