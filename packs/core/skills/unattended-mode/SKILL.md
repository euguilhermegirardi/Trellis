---
name: unattended-mode
description: Rules for running the delivery cycle with nobody watching (overnight or scheduled) - no questions, a state file for resuming, no push or PR by the agent, notes for the morning report. Use when TRELLIS_UNATTENDED=1 or the launcher script started the session.
---

# Unattended mode

Active when `TRELLIS_UNATTENDED=1` (set by the launcher script). The `guard-unattended` hook is also active: it blocks
push, `gh` writes, skipped hooks, destructive git and work on the protected branch. **Do not try to work around a
block**; note the command and move on.

## Nobody will answer

Where a skill says "stop and call the human": write the morning report with the reason under "Needs you", mark
`outcome: "stopped"` in the state file, and **finish**. Do not ask and do not wait.

## State file

Keep the state in `.trellis/run/current.json` (add `.trellis/run/` to `.gitignore`; write it with the file tool). The launcher reads it at the
end and uses it to resume if the session dies. Overwrite it after every completed step:

```json
{
  "unit": "orders-screen",
  "branch": "feat/orders-screen",
  "step": "build",
  "round": 0,
  "outcome": "in-progress",
  "report": "docs/reports/2026-01-01-orders-screen.md",
  "notes": ["failures by type, decisions, what blocked: raw material for the report"]
}
```

- `step` is one of `build`, `test`, `design`, `security`, `report`, `done`. `outcome` is `in-progress`, `delivered` or
  `stopped`.
- **Write the state at step 0**, right after creating or entering the branch (before the builder runs).
- **Resuming:** read the state and the branch's `git log`, and continue from `step`. Do not redo what is already
  committed.

## Rules for the night

- **No push and no pull request.** The launcher does both after you finish. Commit everything on the branch before
  you end: a dirty tree at the end is stashed and lost from the pull request.
- **No schema change that needs applying by hand.** Such a gap means stop; the report explains why.
- **A backend gap without a schema change:** the gap-filler commits on the unit's own branch (not a separate
  backend branch), before the unit, so it ships in the same pull request. The access-control test is mandatory;
  highlight the change in the report under "Needs you: review".
- **Permission denied?** Do not work around it. Put the command in `notes` (the launcher also lists denials in the
  pull request) and carry it to "Signals for the harness". Prefer simple commands, one per call.
- **No worktrees.** No `isolation: worktree` for subagents and no `git worktree`. Work in the main tree, switching
  branches with `git checkout`, one subagent at a time.
- **One unit per night.** When it ends (delivered or stopped), set `step: "done"` and end the session.
