#!/usr/bin/env node
import { build } from "esbuild";
import { mkdir, rm, writeFile } from "node:fs/promises";
import path from "node:path";
import { fileURLToPath } from "node:url";

const scriptDir = path.dirname(fileURLToPath(import.meta.url));
const mcpRoot = path.resolve(scriptDir, "..");
const projectRoot = path.resolve(mcpRoot, "..");
const pluginMcpRoot = path.join(projectRoot, "plugin", "mcp");
const outdir = path.join(pluginMcpRoot, "dist");
const outfile = path.join(outdir, "server.js");

await rm(outdir, { recursive: true, force: true });
await mkdir(outdir, { recursive: true });

await build({
  entryPoints: [path.join(mcpRoot, "src", "server.ts")],
  outfile,
  bundle: true,
  platform: "node",
  format: "esm",
  target: "node20",
  sourcemap: false
});

await writeFile(
  path.join(pluginMcpRoot, "package.json"),
  `${JSON.stringify(
    {
      name: "codex-praetor-plugin-mcp",
      version: "0.1.1-alpha",
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
