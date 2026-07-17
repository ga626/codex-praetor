# GitHub Publish Runbook

Date: 2026-07-17
Target release: `0.4.0-alpha`

Status: `v0.3.0-alpha` is already published. `v0.4.0-alpha` must merge before its new tag and Release are created from the latest `main`; existing tags are immutable.

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
   powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\verify\test-codex-praetor.ps1
   powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\verify\test-public-entry-consistency.ps1 -SkipRemoteRelease
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
   powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\verify\test-codex-praetor.ps1
   powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\verify\test-public-entry-consistency.ps1 -SkipRemoteRelease
   npm test --prefix .\mcp
   git diff --check
   powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\release\build-codex-praetor-release.ps1 -Apply
   ```

5. Run the final fresh-context native MCP canary:

   ```text
   docs/architecture/fresh-context-native-mcp-canary.md
   ```

6. Prepare the release through a normal PR. Version metadata, public download links, release notes, changelog, roadmap, and script defaults must all name the new version. Codex creates the branch, commits, pushes, and provides the Chinese PR title and description; the user creates and merges the PR on GitHub.

7. After the release PR is merged, return to the latest clean `main`. Preview the publication first, then publish:

   ```powershell
   git switch main
   git pull --ff-only
   powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\release\publish-github-release-asset.ps1 -Version 0.4.0-alpha -Tag v0.4.0-alpha
   powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\release\publish-github-release-asset.ps1 -Version 0.4.0-alpha -Tag v0.4.0-alpha -Apply
   ```

   The apply command creates and pushes the new tag, creates a prerelease with the zip and `.sha256`, then downloads the remote assets and verifies them. Existing tags and Releases are rejected by default.

8. Only when repairing a broken asset for the exact same tagged commit, and only after explicit user approval, add `-ReplaceExistingAsset`. It must never be used to put newer source under an older tag.

9. After any later delivery-affecting PR is merged, repeat the same process with a new version unless the user explicitly approves replacing a broken asset built from the same commit:

   ```powershell
   git switch main
   git pull --ff-only
   powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\verify\doctor-codex-praetor.ps1 -RequireHead -PublicRelease
   powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\verify\test-codex-praetor.ps1
   powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\verify\test-public-entry-consistency.ps1 -SkipRemoteRelease
   npm test --prefix .\mcp
   powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\release\publish-github-release-asset.ps1 -Version NEXT_VERSION -Tag vNEXT_VERSION
   powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\release\publish-github-release-asset.ps1 -Version NEXT_VERSION -Tag vNEXT_VERSION -Apply
   ```

   The first command is a dry-run confirmation. The `-Apply` command builds, publishes, downloads, and verifies the GitHub Release assets, then runs the public-entry consistency gate through `scripts\release\verify-github-release-asset.ps1`. Do not say the product is delivered until it passes.

## Blockers That Stop Publication

- `gh auth status` fails or GitHub CLI is missing.
- The final owner/repo is unknown.
- Public metadata still contains placeholder URLs.
- Public release scan finds local paths, account data, auth/token/secret material, provider caches, or private evidence.
- Fresh-context native MCP canary fails.
- User has not confirmed the first public push/tag/release.
- The GitHub Release zip, notes, public README, installation guide, or roadmap point to different user-downloadable versions.
