import assert from "node:assert/strict";
import { execFileSync } from "node:child_process";
import { runPowerShell } from "./powershell.js";

const marker = `CODEX_PRAETOR_TIMEOUT_TEST_${process.pid}_${Date.now()}`;

function markedProcessIds(): number[] {
  const command = `$marker = '${marker}'; Get-CimInstance Win32_Process -Filter \"Name = 'powershell.exe'\" | Where-Object { $_.ProcessId -ne $PID -and $_.CommandLine -like \"*$marker*\" } | ForEach-Object { $_.ProcessId }`;
  const output = execFileSync("powershell.exe", ["-NoProfile", "-Command", command], { encoding: "utf8" });
  return output.split(/\r?\n/).map((value) => Number(value.trim())).filter((value) => Number.isInteger(value) && value > 0);
}

function cleanupMarkedProcesses() {
  for (const processId of markedProcessIds()) {
    execFileSync("taskkill.exe", ["/pid", String(processId), "/T", "/F"], { stdio: "ignore" });
  }
}

if (process.platform === "win32") {
  const command = `$child = Start-Process powershell.exe -ArgumentList '-NoProfile','-Command','Start-Sleep -Seconds 30 # ${marker}' -PassThru; Start-Sleep -Seconds 30`;
  try {
    await assert.rejects(
      runPowerShell(["-NoProfile", "-Command", command], { timeoutMs: 2_000 }),
      /process tree was terminated/
    );
    await new Promise((resolve) => setTimeout(resolve, 300));
    assert.deepEqual(markedProcessIds(), [], "A timed-out PowerShell command must not leave a child process alive.");
  } finally {
    cleanupMarkedProcesses();
  }
}

console.log("PowerShell timeout process-tree contract regression ok");
