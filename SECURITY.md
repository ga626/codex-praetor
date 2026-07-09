# Security Policy

## Supported Versions

`0.1.0-alpha` is pre-release software. Security fixes are handled on the main branch until the first tagged release.

## Reporting

Please report suspected security issues privately to the repository owner once the GitHub repository is published. Do not open public issues that contain tokens, account data, provider logs, local paths, or exploit details.

## Local Data Boundary

Codex Praetor should not require provider account files, API keys, browser cookies, local app databases, or model-provider caches to be committed. Provider credentials stay in the user's normal Qoder, CodeBuddy, or MiMo installation.

Before publishing a fork or bug report, remove:

- `*.local.json`
- `.env*`
- provider auth files
- screenshots showing accounts, credits, or tokens
- runtime job logs that contain private prompts or paths
- ignored `handoff/` and `docs/internal/` material
