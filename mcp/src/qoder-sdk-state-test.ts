import assert from "node:assert/strict";
import { mkdtempSync, readFileSync, readdirSync, renameSync } from "node:fs";
import os from "node:os";
import path from "node:path";
import { writeJsonStateFile } from "./qoder-sdk-state.js";

const root = mkdtempSync(path.join(os.tmpdir(), "codex-praetor-qoder-state-"));
const target = path.join(root, "session.json");
let attempts = 0;
const sleeps: number[] = [];

writeJsonStateFile(target, { state: "running" }, {
  rename: (temporary, destination) => {
    attempts += 1;
    if (attempts < 3) {
      const error = Object.assign(new Error("simulated Windows rename lock"), { code: "EPERM" });
      throw error;
    }
    renameSync(temporary, destination);
  },
  sleep: (milliseconds) => sleeps.push(milliseconds)
});

assert.equal(attempts, 3, "Transient Windows rename failures must be retried.");
assert.deepEqual(JSON.parse(readFileSync(target, "utf8")), { state: "running" });
assert.deepEqual(sleeps, [25, 50]);

writeJsonStateFile(target, { state: "completed" });
assert.deepEqual(JSON.parse(readFileSync(target, "utf8")), { state: "completed" });
assert.deepEqual(readdirSync(root).filter((entry) => entry.endsWith(".tmp")), [], "State replacement must not leave temporary files.");

const failedTarget = path.join(root, "failed-session.json");
assert.throws(
  () => writeJsonStateFile(failedTarget, { state: "failed" }, { rename: () => { throw Object.assign(new Error("persistent Windows rename lock"), { code: "EPERM" }); }, sleep: () => {} }),
  /persistent Windows rename lock/
);
assert.deepEqual(readdirSync(root).filter((entry) => entry.endsWith(".tmp")), [], "A failed state replacement must clean its temporary file.");
console.log("Qoder SDK state replacement regression ok");
