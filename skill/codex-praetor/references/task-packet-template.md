# Worker Task Packet Template

Use this template when dispatching work to Qoder or CodeBuddy.

```text
Role: worker agent. Codex is supervising.

Scope:
- Repo/path: <absolute path>
- Files or directories in scope: <list>
- Files or directories out of scope: <list>

Task:
<one concrete task>

Outcome:
- <the observable completed state Codex will verify>

Mode:
- readonly: inspect and report only
- edit: edit only the named files/areas

Constraints:
- Do not touch auth files, application caches, internal databases, unrelated reports, lockfiles, or generated artifacts unless specifically requested.
- Keep changes minimal.
- Stop and report if blocked by login, missing dependencies, or permission prompts.
- Work autonomously until complete, blocked, or unsafe.
- Do not provide progress updates or ask for intermediate supervision.

Output required:
1. Summary
2. Files read
3. Files changed
4. Commands/checks run
5. Exact verification result
6. Open risks or unknowns
```

