import { spawn } from "node:child_process";
import { StringDecoder } from "node:string_decoder";
import type { PowerShellResult } from "./types.js";

export interface PowerShellOptions {
  timeoutMs?: number;
  maxOutputBytes?: number;
}

export function decodeUtf8Chunks(chunks: readonly Buffer[]): string {
  const decoder = new StringDecoder("utf8");
  let text = "";
  for (const chunk of chunks) {
    text += decoder.write(chunk);
  }
  return text + decoder.end();
}

export function runPowerShell(args: string[], options: PowerShellOptions = {}): Promise<PowerShellResult> {
  const timeoutMs = options.timeoutMs ?? 120_000;
  const maxOutputBytes = options.maxOutputBytes ?? 256_000;

  return new Promise((resolve, reject) => {
    const child = spawn("powershell", args, {
      windowsHide: true,
      stdio: ["ignore", "pipe", "pipe"]
    });

    let stdout = "";
    let stderr = "";
    // A pipe chunk can end in the middle of a multi-byte UTF-8 character.
    // StringDecoder keeps the incomplete bytes for the following chunk.
    const stdoutDecoder = new StringDecoder("utf8");
    const stderrDecoder = new StringDecoder("utf8");
    let settled = false;

    const timer = setTimeout(() => {
      if (settled) {
        return;
      }
      settled = true;
      child.kill();
      reject(new Error(`PowerShell command timed out after ${timeoutMs} ms.`));
    }, timeoutMs);

    child.stdout.on("data", (chunk: Buffer) => {
      stdout += stdoutDecoder.write(chunk);
      if (Buffer.byteLength(stdout, "utf8") > maxOutputBytes) {
        stdout = stdout.slice(0, maxOutputBytes);
      }
    });

    child.stderr.on("data", (chunk: Buffer) => {
      stderr += stderrDecoder.write(chunk);
      if (Buffer.byteLength(stderr, "utf8") > maxOutputBytes) {
        stderr = stderr.slice(0, maxOutputBytes);
      }
    });

    child.on("error", (error) => {
      if (settled) {
        return;
      }
      settled = true;
      clearTimeout(timer);
      reject(error);
    });

    child.on("close", (exitCode) => {
      if (settled) {
        return;
      }
      settled = true;
      clearTimeout(timer);
      stdout += stdoutDecoder.end();
      stderr += stderrDecoder.end();
      resolve({ exitCode, stdout, stderr });
    });
  });
}
