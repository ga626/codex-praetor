# Codex Praetor 0.16.28-alpha

## What changed

- Fixed the first real code-change dispatch path. The public preflight now carries the frozen base commit, immutable paths, scope and required checks instead of sending code work into a read-only-style dry-run that must fail before a worker starts.
- The execution-mode Skill now distinguishes a harmless read-only preview from a real code-change contract preflight. A preflight explicitly says that no worker has started; only a returned job ID and execution worktree count as a dispatched worker.
- Strengthened release acceptance. A release candidate now needs evidence from one accepted real code-change path in a freshly refreshed Desktop host: route, non-starting contract preflight, started worker, isolated worktree, successful completion and Codex acceptance must all bind to the same candidate ZIP and host generation.
- If Codex Desktop is holding its managed plugin cache during an update, activation records a deferred helper. After the normal Desktop exit, that helper calls the official `codex plugin add` command and the following refresh loads the exact candidate generation. It never removes or edits Codex cache files directly.

## User impact

After updating and performing the normal supported Desktop refresh, start a new task and say that you want to enable Codex Praetor execution mode and delegate a bounded code change. The product will either start the worker in an isolated worktree or state plainly which contract or readiness condition prevented worker startup. You do not need to run an internal canary merely to make the feature usable.

## Provider and account boundary

This release does not add providers, models or account permissions. Qoder China CLI `stream-json` and CodeBuddy ACP are the supported worker connections. Their official login, available quota and network availability remain provider-specific first-use conditions; they are not hidden by release receipts. The global Qoder Agent SDK is a separate future opt-in route, not a fallback for the China CLI.

CodeBuddy retains its ACP session protocol. Qoder China retains parseable stdout progress, controlled process cancellation, and terminal/diff acceptance; it does not claim SDK session cancellation.
