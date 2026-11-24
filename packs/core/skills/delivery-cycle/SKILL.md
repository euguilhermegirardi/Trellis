---
name: delivery-cycle
description: Orchestrates the autonomous delivery of one unit of work (a screen or feature) - builder builds, tester tests, design reviewer compares with the reference, failures loop back to the builder (max 3 rounds), security review, then closing with a pull request. Use when asked to build or deliver a whole unit.
---

# Delivery cycle (builder <-> tester loop)

The **main session** runs this skill (the orchestrator). A subagent cannot call another subagent. The
orchestrator only delegates, reads reports and decides; it writes neither feature code nor tests.

Project settings come from `.trellis/cycle.json` (see the end); every default below can be overridden there.
Running without a human present: also read the `unattended-mode` skill. Closing: `close-and-pr`.

## 0. Prepare

- Find the unit and its order in the living plan. Create the feature branch from the up-to-date base branch.
- The unit depends on a backend gap? Run the gap-filler before building. If it changes the database schema
  (a new numbered script), **stop**: the human has to apply it locally before the cycle continues.
- Visual capture needs the browser test dependency. If it is missing, the tester installs it at the first critical
  flow; with no browser in the environment the design reviewer returns `BLOCKED`.

## 1. Build

The builder in **build** mode, with the unit's name and the branch. If it stops because of a backend gap, go back
to step 0.

## 2. Test loop (at most 3 correction rounds)

```
round = 0
tester (fresh context) -> report
while RESULT = FAILURES:
    if round = max_rounds -> STOP (escalate)
    builder in fix mode <- the whole tester report
    tester (fresh context) <- "retest" + previous report -> new report
    round += 1
```

- Always a **fresh context** for the tester (a new call), so it does not inherit the builder's reasoning.
- Pass the **whole** report, never a summary: the report format is the contract between the agents.
- A builder `DISPUTE` goes to the tester in the retest. If the tester keeps the test and cites a source in the
  specification or rules, the dispute goes to the human (it is a product decision, not a bug).

**Stop and call the human** (with the last report, the branch and what is already done) when:

- the rounds run out;
- the same failure appears in two consecutive rounds (no progress);
- `RESULT: BLOCKED` (specification and backend disagree, or the environment cannot run the checks);
- a dispute is held by both sides;
- a fix would change an access rule, an API contract or the specification.

## 3. Design

With the tester `GREEN`: the design reviewer (fresh context) with the screen, route, role and the mocks file
created by the tester. `FAILURES` -> builder in fix mode with the design report -> **tester again** (a visual fix
must not break behavior) -> design reviewer again. It counts toward the same rounds. When the reference design and
the specification disagree about content, the specification wins and it is not a failure.

## 4. Security

For a unit with a write action or a role restriction, the security reviewer reads the branch diff
(`git diff <base>...<branch>`). A finding at medium or above -> builder in fix mode with the finding, plus a tester
retest (step 2), counting toward the same rounds.

## 5. Morning report (always, delivered or stopped)

When finishing **or** stopping, write the report from `templates/morning-report.md` (metrics in the header plus
sections) and commit it on the branch. It is the first thing the human reads: start with "In one line" and "Needs
you"; do not paste transcripts. Note during the cycle the rounds, failures by type, decisions taken where the
specification was silent, and what blocked, so nothing is rebuilt from memory. A stopped cycle explains where, why
and what is left to decide; the branch keeps everything that was done.

## 6. Close

Run the `close-and-pr` skill.

## Settings (`.trellis/cycle.json`)

```json
{
  "unit": "screen",
  "baseBranch": "main",
  "branchPrefix": "feat/",
  "maxRounds": 3,
  "planPath": "docs/PLAN.md",
  "reportDir": "docs/reports",
  "checks": ["npm run format:check", "npm run lint", "npm run typecheck", "npm test"]
}
```
