# Unattended-mode guard

`guard-unattended.sh` is a Claude Code `PreToolUse` hook for the `Bash` tool. It does nothing unless the
environment variable `TRELLIS_UNATTENDED=1` is set, which the script that launches an unattended session
sets. When active it blocks (exit code 2) what an agent must never do alone:

- `git push`, force or not, and any `gh` command that is not read-only (the launcher pushes and opens the
  pull request after the agent finishes);
- skipping checks: `--no-verify`, `git commit -n`, inline `SKIP_*` variables, `HUSKY=0`, changing
  `core.hooksPath`, redirecting git with `GIT_DIR`;
- destroying work: `git reset --hard`, `git clean -f`, `git branch -D`, history rewriting;
- committing, merging or rebasing on a protected branch, or switching to one;
- `sudo`, recursive `rm` outside the project, naming secret files (`.env`, keys, certificates);
- piping a download into a shell or interpreter.

It reads the command as argv tokens after splitting on `;`, `&`, `|` and newlines and descending into
`$(...)`, backticks, `bash -c` and `eval`. A commit message that mentions "git push" is therefore allowed.
If the guard cannot read its input while unattended, it blocks.

Register it in `.claude/settings.json`:

```json
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Bash",
        "hooks": [{ "type": "command", "command": "\"${CLAUDE_PROJECT_DIR}\"/.claude/hooks/guard-unattended.sh", "timeout": 10 }]
      }
    ]
  }
}
```

Copy both `guard-unattended.sh` and `guard_unattended.py` into the project's `.claude/hooks/`.

## Configuration

| Setting | Effect |
|---|---|
| `TRELLIS_PROTECTED_BRANCHES` | Space-separated protected branches (default `main master`) |
| `.trellis/protected-branches.txt` | One protected branch per line |
| `.trellis/forbidden-files.txt` | Extra path globs a command may not name |
| `TRELLIS_FORBIDDEN_ENV` | Extra variable names that may not be set inline |

## Limits

This is a second lock, not a sandbox. It cannot see inside scripts, interpreters (`python -c`, `node -e`)
or tools that run commands for the agent. Pair it with `permissions.deny` rules and with running the
session as an unprivileged user.
