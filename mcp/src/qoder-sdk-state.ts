import { renameSync, unlinkSync, writeFileSync } from "node:fs";

const STATE_RENAME_RETRY_DELAYS_MS = [0, 25, 50, 100, 200];
let stateWriteSequence = 0;

type RenameFile = (temporary: string, target: string) => void;
type Sleep = (milliseconds: number) => void;

export type StateWriteDependencies = {
  rename?: RenameFile;
  sleep?: Sleep;
};

function isRetryableStateRenameError(error: unknown) {
  const code = typeof error === "object" && error !== null && "code" in error ? String((error as { code?: unknown }).code) : "";
  return code === "EPERM" || code === "EBUSY" || code === "EACCES";
}

function sleepSync(milliseconds: number) {
  if (milliseconds <= 0) return;
  const signal = new Int32Array(new SharedArrayBuffer(4));
  Atomics.wait(signal, 0, 0, milliseconds);
}

export function replaceStateFile(temporary: string, target: string, dependencies: StateWriteDependencies = {}) {
  const rename = dependencies.rename ?? renameSync;
  const sleep = dependencies.sleep ?? sleepSync;
  let lastError: unknown;
  for (let attempt = 0; attempt < STATE_RENAME_RETRY_DELAYS_MS.length; attempt += 1) {
    try {
      rename(temporary, target);
      return;
    } catch (error) {
      lastError = error;
      if (!isRetryableStateRenameError(error) || attempt === STATE_RENAME_RETRY_DELAYS_MS.length - 1) throw error;
      sleep(STATE_RENAME_RETRY_DELAYS_MS[attempt + 1]);
    }
  }
  throw lastError;
}

export function writeJsonStateFile(target: string, payload: unknown, dependencies: StateWriteDependencies = {}) {
  const temporary = `${target}.${process.pid}.${++stateWriteSequence}.tmp`;
  writeFileSync(temporary, `${JSON.stringify(payload)}\n`, "utf8");
  try {
    replaceStateFile(temporary, target, dependencies);
  } catch (error) {
    try {
      unlinkSync(temporary);
    } catch {
      // Preserve the original state-write failure; cleanup is best effort.
    }
    throw error;
  }
}
