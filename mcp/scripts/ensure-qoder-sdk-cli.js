#!/usr/bin/env node
import { existsSync, rmSync } from "node:fs";
import path from "node:path";
import { spawnSync } from "node:child_process";
import { fileURLToPath } from "node:url";

const scriptDir = path.dirname(fileURLToPath(import.meta.url));
const mcpRoot = path.resolve(scriptDir, "..");
const sdkRoot = path.join(mcpRoot, "node_modules", "@qoder-ai", "qoder-agent-sdk");
const bundledCli = path.join(sdkRoot, "dist", "_bundled", process.platform === "win32" ? "qodercli.exe" : "qodercli");
const postinstall = path.join(sdkRoot, "scripts", "postinstall.cjs");

if (!existsSync(postinstall)) {
  throw new Error("Qoder Agent SDK is not installed. Run npm ci before packaging the plugin runtime.");
}

// Qoder Agent SDK 1.0.15 defaults to an older global CLI.  The documented
// China endpoint needs the current 1.1.6 runtime; it is a public executable,
// not account material. qodercliAuth() still reads the user's normal login
// state at execution time and this script never reads or copies it.
if (existsSync(bundledCli)) {
  const version = spawnSync(bundledCli, ["--version"], { encoding: "utf8" });
  if (version.status === 0 && `${version.stdout ?? ""}${version.stderr ?? ""}`.includes("1.1.6")) {
    console.log(`Qoder SDK CLI is already current: ${bundledCli}`);
    process.exit(0);
  }
}
rmSync(bundledCli, { force: true });
const result = spawnSync(process.execPath, [postinstall], {
  cwd: sdkRoot,
  stdio: "inherit",
  env: {
    ...process.env,
    QODER_CLI_SITE: "cn",
    QODER_CLI_MIRROR: "https://static.qoder.com.cn/qoder-cli-cn/releases",
    QODER_CLI_VERSION: "1.1.6"
  }
});
if (result.status !== 0 || !existsSync(bundledCli)) {
  throw new Error(`Could not prepare the Qoder SDK CLI (exit ${result.status ?? "unknown"}).`);
}
console.log(`Prepared Qoder SDK CLI: ${bundledCli}`);
