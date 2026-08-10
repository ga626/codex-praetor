# Codex Praetor 0.16.38-alpha

## Fixes

- CodeBuddy dispatch now performs a short, read-only admission probe before it creates a paid job or an isolated worktree. An expired session, launcher failure, or probe timeout stops at the control plane and gives one actionable next step.
- A static CodeBuddy model catalogue that omits a configured custom model is retained as an advisory rather than treated as proof that the model cannot run. Fixed-model capability remains subject to the bounded ACP task and independent acceptance evidence; no automatic model switch is introduced.
- Candidate-version fixtures now include every mirrored runtime script, and source scans ignore the project-owned `.codex/` runtime area rather than reporting historical worker worktrees as product-source findings.
- The existing controlled process cancellation path and terminal evidence requirements remain in force for both worker routes; this release does not weaken cancellation, timeout, or recovery boundaries.

## Boundaries

This version keeps CodeBuddy on ACP and Qoder China on supervised `stream-json`. It does not read, copy, migrate, or publish provider credentials, and it does not select Auto or substitute another model when a fixed tuple has not been accepted.
