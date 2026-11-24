# Unattended runs

Run the delivery cycle while you are away (overnight, for example). Three pieces cooperate:

| Piece | Role |
|---|---|
| `scripts/run-unattended.sh` | The launcher. Checks the environment, limits time and cost, resumes if the session dies, then pushes the branch and opens the pull request. |
| `delivery-cycle` + `unattended-mode` skills | What the agent does: build, test, review, commit on a feature branch, write the report and the state file. |
| `guard-unattended` hook | A second lock. While `TRELLIS_UNATTENDED=1` it blocks push, `gh` writes, skipped hooks, destructive git and work on the protected branch. |

The agent never pushes. That is the launcher's job, after the agent has finished.

## Set up

1. Install the packs into the project: `scripts/install.sh <project> --stack <stack>`. This copies the launcher, the guard
   and the skills and registers the guard in `.claude/settings.json`.
2. Edit `.trellis/unattended.json` (model, time and cost limits, extra allowed tools, setup commands).
3. Create a long-lived token once with `claude setup-token` and save it to `~/.config/trellis/claude-oauth-token`
   (mode 600). The launcher refuses to use an API key.
4. Open `claude` once in the project folder, accept the trust prompt and exit. Without that, Claude Code ignores
   permissions and hooks, so the launcher refuses to run.
5. Add units to `unattended.queue`, one per line (`#` starts a comment).
6. Try `scripts/run-unattended.sh --dry-run`: it runs every pre-flight check and prints the plan without starting
   the agent.

## What the launcher refuses

Missing commands, an untrusted folder, extra git worktrees, a failed fetch, a dirty tree, an unauthenticated `gh`, a
unit that already has an open pull request (override with `TRELLIS_REPEAT=1`) and a failing setup command. Each refusal
writes `.trellis/run/logs/<date>-<unit>-FAILED.md` with the reason and the loose files in the tree.

## After the run

A delivered unit leaves the queue and its pull request carries the morning report plus a list of permissions the agent
was denied. A stopped unit stays in the queue so you can decide and run it again. Leftover uncommitted changes are
stashed, never lost.

## Scheduling

Cron:

```
30 2 * * *  cd /path/to/project && scripts/run-unattended.sh >> .trellis/run/cron.log 2>&1
```

macOS launchd: a `LaunchAgent` with `ProgramArguments` set to the script, `WorkingDirectory` set to the project and a
`StartCalendarInterval` for the time. The script keeps the machine awake with `caffeinate` while it runs.

## Limits

The guard reads commands as tokens and cannot see inside scripts or interpreters; keep `python`, `node -e` and similar
out of the allowed tools unless the project needs them. Run the session as an unprivileged user.
