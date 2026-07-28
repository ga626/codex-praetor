import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import path from "node:path";

const source = readFileSync(path.join(process.cwd(), "src", "qoder-sdk-runner.ts"), "utf8");

assert.match(source, /abortController:\s*controller/);
assert.match(source, /replace\(\/\^\\uFEFF\//, "Runner options must tolerate Windows UTF-8 BOM JSON.");
assert.match(source, /controller\.abort\(\)/);
assert.match(source, /cancel-request\.json/);
assert.match(source, /cancelled_session_terminated/);
assert.match(source, /iteration_ended:\s*true/);
assert.match(source, /canUseTool:\s*createToolGuard/);
assert.doesNotMatch(source, /\binterrupt\s*\(/, "The rejected Qoder interrupt() route must not re-enter the formal runner.");
console.log("Qoder SDK abort contract regression ok");
