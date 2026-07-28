#!/usr/bin/env node
import { build } from "esbuild";
import { copyFile, mkdir, readFile, rm, writeFile } from "node:fs/promises";
import path from "node:path";
import { fileURLToPath } from "node:url";

const scriptDir = path.dirname(fileURLToPath(import.meta.url));
const mcpRoot = path.resolve(scriptDir, "..");
const projectRoot = path.resolve(mcpRoot, "..");
const pluginMcpRoot = path.join(projectRoot, "plugin", "mcp");
const outdir = path.join(pluginMcpRoot, "dist");
const outfile = path.join(outdir, "server.js");
const packageMetadata = JSON.parse(await readFile(path.join(mcpRoot, "package.json"), "utf8"));

const prepare = await import("node:child_process");
const prepared = prepare.spawnSync(process.execPath, [path.join(mcpRoot, "scripts", "ensure-qoder-sdk-cli.js")], { cwd: mcpRoot, stdio: "inherit" });
if (prepared.status !== 0) throw new Error(`Could not prepare Qoder SDK runtime (exit ${prepared.status ?? "unknown"}).`);

await rm(outdir, { recursive: true, force: true });
await mkdir(outdir, { recursive: true });

for (const [entry, destination] of [
  ["server.ts", outfile],
  ["qoder-sdk-runner.ts", path.join(outdir, "qoder-sdk-runner.js")],
  ["codebuddy-acp-runner.ts", path.join(outdir, "codebuddy-acp-runner.js")]
]) {
  await build({
    entryPoints: [path.join(mcpRoot, "src", entry)],
    outfile: destination,
    bundle: true,
    platform: "node",
    format: "esm",
    target: "node20",
    // The Qoder SDK bundle preserves whitespace from its dependencies. Minify
    // whitespace so generated runtime files remain deterministic and pass the
    // repository's whitespace gate without changing runtime semantics.
    minifyWhitespace: true,
    sourcemap: false
  });
  // Some third-party SDK templates preserve indentation on otherwise blank
  // lines. It has no runtime meaning in the generated JavaScript but makes
  // `git diff --check` reject the immutable plugin artifact.
  const generated = await readFile(destination, "utf8");
  await writeFile(destination, generated.replace(/[\t ]+$/gm, ""), "utf8");
}

const bundledCli = path.join(mcpRoot, "node_modules", "@qoder-ai", "qoder-agent-sdk", "dist", "_bundled", process.platform === "win32" ? "qodercli.exe" : "qodercli");
await copyFile(bundledCli, path.join(outdir, process.platform === "win32" ? "qodercli.exe" : "qodercli"));

await writeFile(
  path.join(pluginMcpRoot, "package.json"),
  `${JSON.stringify(
    {
      name: "codex-praetor-plugin-mcp",
      version: packageMetadata.version,
      private: true,
      type: "module",
      main: "dist/server.js",
      bin: {
        "codex-praetor-mcp": "dist/server.js"
      }
    },
    null,
    2
  )}\n`,
  "utf8"
);

console.log(`Packaged Codex Praetor MCP runtime: ${outfile}`);
