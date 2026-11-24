---
name: living-doc
description: Keep the project's living plan document in step with the code - update status, gaps and decisions, generate the log line, and resolve the commit gate without waiting for the human. Use when a commit is blocked for a missing plan update or when closing a unit of work.
---

# Living plan document

The plan (path in `.trellis/living-doc.json`) is the single place that says where the project stands.
A git hook blocks any commit that changes product state (files matching `triggers`) unless the plan is
part of the same commit.

## When the hook blocks

Resolve it yourself; do not wait for the human and do not bypass the hook.

1. Read `git diff --cached` to see what changed.
2. Update the plan: the status of the affected unit, new gaps, decisions taken (with the reason).
3. Run `node scripts/living-doc-log.mjs --write`. It builds one log line for the current branch from the
   commits and staged files, and replaces the earlier line of the same branch. A hand-written
   `Pending: ...` tail on that line is preserved.
4. `git add` the plan and commit again.

There is no switch to disable the gate. Exemptions are decided by the human: a branch listed in
`skipBranches` (for example `wip/*`), or `git commit --no-verify` typed by them.

## When closing a unit of work

Before the final merge, run the log script once more with everything committed and commit the result
as `docs: log`. For a branch stacked on another, pass `--base <previous-branch>` so the line lists only
this branch's own work.

## What belongs in the plan

- Status per unit (planned, in progress, delivered, blocked) with a one-line note.
- Gaps: what is missing and which units it blocks.
- Decisions: the choice, the reason and the date. Never rewrite history; add a new decision that
  supersedes the old one.
- The log: one line per branch, newest first.
