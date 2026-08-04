# Codex Praetor 0.16.27-alpha

## What changed

- Fixed CI classification so a dependency-manifest-only update receives deterministic MCP installation and test coverage instead of being rejected for missing release-only evidence before testing begins.
- Updated the MCP dependency set: Hono 4.13.0, ip-address 10.4.0, Model Context Protocol TypeScript SDK 1.30.0, and Qoder Agent SDK 1.0.17.
- Kept the release path strict: a PR that changes a product or release surface still needs one attested candidate ZIP, Desktop host evidence, and same-artifact promotion on main.

## User impact

This maintenance release does not add setup steps or change how normal natural-language dispatch works. After the normal supported Desktop refresh for an update, users can continue to dispatch work as before.

## No provider or account expansion

This release updates packaged dependency versions and CI routing only. It does not add a provider, model, account permission, or new worker execution capability.

Qoder Agent SDK and CodeBuddy ACP retain their existing structured-progress and formal-cancellation contracts. The affected deterministic adapter contract tests run in CI; no provider credits are spent unless a provider execution semantic changes.
