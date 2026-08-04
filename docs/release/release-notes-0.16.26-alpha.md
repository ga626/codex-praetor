# Codex Praetor 0.16.26-alpha

## What changed

- A release-impact PR now produces one attested candidate ZIP, and main refuses to promote it unless a real Codex Desktop has loaded that exact candidate generation.
- The maintainer's candidate install remains reversible: the stable plugin is backed up by the bundled installer and a dedicated restore command can recover it without relying on the candidate plugin.
- Main uploads the same verified ZIP to a GitHub draft, downloads and checks that draft, and only then makes the Release public. Public verification checks delivery identity only; it does not spend provider credits on a second functional run.

## User impact

After installing or updating, a user may need one supported Codex Desktop refresh. After that, normal natural-language dispatch is the supported first-use path; canary and doctor commands are troubleshooting tools, not prerequisites.

## No provider or account expansion

This release changes release assurance and installation recovery only. It does not add a provider, model, account permission, or new worker execution capability.

Qoder Agent SDK and CodeBuddy ACP keep their existing structured progress and formal cancellation contracts. This release does not change either provider's dispatch, permission, connection, or recovery semantics.
