---
name: close-and-pr
description: Closes a unit of work - green suite, pre-commit check, living plan and log line, then push and pull request against the protected base branch with a description by change type and no signatures. Use at the end of the delivery cycle.
---

# Close the branch and open the pull request

1. **Suite green:** run the project's checks (`checks` in `.trellis/cycle.json`: format check, lint, typecheck, tests).
2. **Pre-commit check:** run the `pre-commit-check` skill.
3. **Living plan:** update status, gaps and decisions; with everything committed, generate the log line
   (`node scripts/living-doc-log.mjs --write`) and commit it as `docs: log`. For a branch stacked on another that
   is not merged yet, add `--base <previous-branch>`, otherwise the line inherits the other branch's commits.
4. **Push and pull request** (not in unattended mode; the launcher does it there): push the branch and open the
   pull request against the **protected base branch**.
5. **Description** follows the pull request rule: no signature or tooling footer, a body by type (fix: problem,
   cause, solution; feature: a complete description; addition or maintenance: what and why), always ending with
   how it was verified and what is out of scope. For a delivered unit also include: endpoints or interfaces
   consumed, the suite and end-to-end result, captures (light, dark, narrow width), the **loop history** (rounds,
   failures found and how they were fixed), security findings, pending items and a link to the morning report.
6. **Never** merge, push or commit on the protected base branch; never `--force`, `--no-verify` or an
   environment switch that skips a hook. The human merges.

## Always target the base branch

A pull request is always opened with the protected base branch as its base. Stacking pull requests (base = another
unit's branch) lost code once: the human merged the first into the base branch, and the next two were then merged
into already-merged branches instead of the base branch, so their work never arrived. If a unit depends on one that
is not merged yet, the branch may start from it, but the pull request still points at the base branch (its diff
shows both until the first is merged), and the description says "merge after #N".

After each merge, verify that nothing was left behind: `git log origin/<base>..origin/<branch>` must be empty.
