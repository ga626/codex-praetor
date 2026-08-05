# Codex Praetor 0.16.28-alpha

## What changed

- Fixed the first real code-change dispatch path. The public preflight now carries the frozen base commit, immutable paths, scope and required checks instead of sending code work into a read-only-style dry-run that must fail before a worker starts.
- The execution-mode Skill now distinguishes a harmless read-only preview from a real code-change contract preflight. A preflight explicitly says that no worker has started; only a returned job ID and execution worktree count as a dispatched worker.
- Strengthened release acceptance. A release candidate now needs evidence from one accepted real code-change path in a freshly refreshed Desktop host: route, non-starting contract preflight, started worker, isolated worktree, successful completion and Codex acceptance must all bind to the same candidate ZIP and host generation.

## User impact

After updating and performing the normal supported Desktop refresh, start a new task and say that you want to enable Codex Praetor execution mode and delegate a bounded code change. The product will either start the worker in an isolated worktree or state plainly which contract or readiness condition prevented worker startup. You do not need to run an internal canary merely to make the feature usable.

## Provider and account boundary

This release does not add providers, models or account permissions. Qoder Agent SDK and CodeBuddy ACP remain the supported worker connections. Their official login, available quota and network availability remain provider-specific first-use conditions; they are not hidden by release receipts.

Both connections retain their existing structured progress and formal cancellation contracts.
