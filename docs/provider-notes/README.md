# Provider setup notes

Codex Praetor supports optional external CLI providers:

- [Qoder](qoder.md)
- [CodeBuddy](codebuddy.md)
- [MiMo](mimo.md)

These providers are not bundled with Codex Praetor. Users install and sign in to them through each provider's official flow, then point Codex Praetor at the local CLI path in an ignored local config.

If no provider is configured, Codex Praetor still has useful local functions: route-intent, planning, dry-run shape, status, lane/conflict visibility, and MCP tool discovery. Real worker dispatch is disabled until at least one provider CLI is installed, logged in, and verified by a readonly canary.

Back to the root setup guide: [README](../../README.md).
