# GitHub Publish Runbook

Date: 2026-07-13
Target release: `0.1.1-alpha`

Status: `v0.1.1-alpha` has already been published. This runbook records the safe path that was used for that release and can be reused as a template for the next release after replacing the target version.

This runbook is the safe path for publishing Codex Praetor to GitHub. It assumes Codex does the release work after the user completes only the account-owner actions that cannot be delegated safely.

## Hard Rules

- Do not paste GitHub Personal Access Tokens into Codex, docs, scripts, issues, release notes, or config files.
- If a token is pasted into any chat, issue, log, or terminal transcript, revoke it immediately in GitHub before continuing.
- Prefer GitHub CLI browser/device login over raw token handling.
- Codex may create the repository, set remotes, push, tag, and create releases only after a safe local GitHub auth state exists.
- Codex must stop before the first public push, tag, or release unless the user has explicitly confirmed that public publication may proceed.

## User-Owned One-Time Actions

1. Revoke any exposed token:

   https://github.com/settings/tokens

2. Install GitHub CLI if `gh --version` is not available:

   https://cli.github.com/

3. Sign in with a browser or device-code flow:

   ```powershell
   gh auth login
   gh auth status
   ```

4. Tell Codex the final owner/repo pair, for example:

   ```text
   OWNER/codex-praetor
   ```

These are the only manual steps expected before Codex can run the GitHub publication commands.

## Codex-Owned Publication Steps

After `gh auth status` succeeds and the user confirms the final owner/repo:

1. Confirm the working tree and release gates:

   ```powershell
   git status --short
   powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\verify\doctor-codex-praetor.ps1 -RequireHead -PublicRelease -AllowDraftMetadataPlaceholders
   powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\verify\test-codex-praetor.ps1 -SkipInstalledSkillCheck
   npm test --prefix .\mcp
   ```

2. Create or connect the GitHub repository:

   ```powershell
   gh repo create OWNER/codex-praetor --public --source . --remote origin --description "Codex external worker orchestration plugin and MCP layer" --disable-wiki
   ```

   If the repository already exists, use:

   ```powershell
   git remote add origin https://github.com/OWNER/codex-praetor.git
   ```

3. Replace draft metadata:

   ```powershell
   powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\release\set-codex-praetor-public-metadata.ps1 -RepositoryUrl https://github.com/OWNER/codex-praetor -Apply
   ```

4. Re-run final gates without draft placeholders:

   ```powershell
   powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\verify\doctor-codex-praetor.ps1 -RequireHead -PublicRelease
   powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\verify\test-codex-praetor.ps1 -SkipInstalledSkillCheck
   npm test --prefix .\mcp
   git diff --check
   powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\release\build-codex-praetor-release.ps1 -Apply
   ```

5. Run the final fresh-context native MCP canary:

   ```text
   docs/architecture/fresh-context-native-mcp-canary.md
   ```

6. Commit, push, tag, and publish only after explicit user confirmation:

   ```powershell
   git add .
   git commit -m "Prepare Codex Praetor 0.1.1-alpha"
   git push -u origin main
   git tag v0.1.1-alpha
   git push origin v0.1.1-alpha
   gh release create v0.1.1-alpha .\.codex-praetor\releases\codex-praetor-setup-0.1.1-alpha.zip --title "Codex Praetor 0.1.1-alpha" --notes-file .\docs\release\release-notes-0.1.1-alpha.md
   ```

## Blockers That Stop Publication

- `gh auth status` fails or GitHub CLI is missing.
- The final owner/repo is unknown.
- Public metadata still contains placeholder URLs.
- Public release scan finds local paths, account data, auth/token/secret material, provider caches, or private evidence.
- Fresh-context native MCP canary fails.
- User has not confirmed the first public push/tag/release.
