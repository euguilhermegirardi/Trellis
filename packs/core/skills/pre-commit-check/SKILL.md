---
name: pre-commit-check
description: Mandatory check before any commit - read the staged diff, scan for secrets, confirm forbidden files are not staged, run format, build and tests. Use every time you are about to commit.
---

# Pre-commit check

Run these steps in order before every commit. The git hook enforces some of them, but the hook is the
second lock: do the check yourself so the hook never has to stop you.

1. Run `git status` and read the **whole** staged diff (`git diff --cached`), not only the summary.
2. Look for secrets in what is about to be committed. The hook `scan-secrets.sh` does this on added
   lines; you read the diff for what a pattern cannot catch (real e-mails, personal data, internal URLs,
   customer names).
3. Confirm forbidden files are **not** staged: environment files (except `.env.example`), key and
   certificate files, database dumps, build output, dependency folders. The project list lives in
   `.trellis/forbidden-files.txt`.
4. Committed configuration files hold only non-secret defaults. Anything secret lives in an untracked
   file or an environment variable.
5. If something looks suspicious: **stop**, do not commit, tell the human which file and line.
6. If the change alters an access rule, confirm there is a new or updated test for it.
7. Formatting: run the project formatter on the staged files. Do not fix formatting by hand.
8. Build and tests are green before the commit.
9. If the project keeps a living plan document and the commit changes product state, the plan goes in
   the same commit. If a hook blocks for that reason, update the plan and commit again without waiting
   for the human.
10. Write a short commit message in the style of `git log --oneline -10`.

Never bypass a hook: no `--no-verify`, no environment switch that disables a check, unless the human
explicitly asks for it in this session.

## Configuration

The scan reads optional files from `.trellis/`: `secret-patterns.txt` (`name|regex` per line),
`forbidden-files.txt` and `secret-allow-files.txt` (path globs). A line carrying the marker
`trellis:allow-secret` is skipped, for fixtures that must contain a fake secret.
