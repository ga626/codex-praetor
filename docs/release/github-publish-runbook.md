# GitHub Publish Runbook

Date: 2026-07-19
Target release: `0.6.0-alpha`

Status: `v0.5.0-alpha` is already published. `v0.6.0-alpha` is declared in the same release-impacting PR and is published automatically by `Release On Main` after that PR reaches `main`; existing tags are immutable.

This runbook defines the single merge-to-release pipeline. A release-impacting PR is not merge-ready until it contains the version surface, `config/release-intent.json`, release notes, and passing candidate gates. After merge, GitHub Actions builds the exact merge commit, creates a draft Release, uploads all assets, publishes it, and verifies the remote download. There is no manual post-merge publish step.

## Hard Rules

- Do not paste GitHub Personal Access Tokens into Codex, docs, scripts, issues, release notes, or config files.
- If a token is pasted into any chat, issue, log, or terminal transcript, revoke it immediately in GitHub before continuing.
- Prefer GitHub CLI browser/device login over raw token handling.
- The repository must have a protected `main` branch, required CI checks, and `contents: write` permission for the `Release On Main` workflow.
- Release tags and assets are immutable. A version already tagged on another commit is a hard failure, never an asset replacement.
- The automatic workflow is the only supported public release path; do not run the old manual sequence after merge.

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

6. Prepare the release through the same PR that changes the product. Run the version updater, commit `config/release-intent.json`, the matching release notes and changelog, then run:

   ```powershell
   powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\release\set-codex-praetor-version.ps1 -Version NEXT_VERSION -Apply
   powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\verify\test-release-intent.ps1 -BaseRef origin/main -RequireReleaseImpact
   ```

7. After the PR merges, `Release On Main` performs, in one idempotent workflow:

   - checkout of the exact merge commit;
   - release-intent, source, MCP, product, public-entry and deterministic package gates;
   - creation of the tag and a draft Release;
   - upload of zip and `.sha256` before publishing the immutable Release;
   - download/hash/entry/notes verification through `verify-github-release-asset.ps1`.

   A workflow failure is a delivery incident with an explicit run URL, not a hidden manual tail. It must be retried or fixed before the next release-impacting PR.

8. `-ReplaceExistingAsset` is forbidden in the normal path. It is reserved for a broken asset from the exact same tagged commit and requires explicit incident approval; it can never put newer source under an older tag.

## Blockers That Stop Publication

- `gh auth status` fails or GitHub CLI is missing.
- The final owner/repo is unknown.
- Public metadata still contains placeholder URLs.
- Public release scan finds local paths, account data, auth/token/secret material, provider caches, or private evidence.
- Fresh-context native MCP canary fails.
- `Release On Main` lacks repository write permission or required branch protection.
- The GitHub Release zip, notes, public README, installation guide, or roadmap point to different user-downloadable versions.
