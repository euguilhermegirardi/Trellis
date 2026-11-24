---
# Metrics (the orchestrator fills these in; they show whether the harness improves over time)
date: YYYY-MM-DD
task: <name>
branch: <type>/<name>
outcome: delivered | stopped | failed       # delivered = PR opened; stopped = escalated to the human
pr: <url or ->
duration_min: <n>
fix_rounds: <0-3>
tester_failures: <n>                        # feature bugs found by the tester, all rounds
design_failures: <n>                        # failures from the design reviewer
security_findings: <n>
disputes: <n>                               # failures the builder contested
stop_reason: - | rounds | no-progress | blocked-spec | blocked-environment | dispute | access-rule
suite: green | red | not-run
e2e: passed | failed | not-run
---

# Morning report: <task> (<date>)

## In one line
<What the reader will find: "PR #12 ready for review" or "Stopped in round 2: spec and backend disagree on X".>

## Needs you
<Decisions, divergences, disputes and pending items only the human can resolve, each with the minimum
context needed to decide. "Nothing" if there is none.>

## What was delivered
- What it does, in product language
- Endpoints or interfaces touched
- Screenshots or artifacts (paths, or attached to the PR)

## How the loop went
| Round | Found by | Failure (type) | How it was fixed |
|---|---|---|---|
| 1 | tester | ... (feature-bug) | ... |

## Decisions the agents made alone
<Choices the specification did not cover (empty-state copy, default sort order). Review them: if one is
wrong, it becomes a rule in the harness.>

## Signals for the harness
<What blocked or confused the agents: ambiguous instruction, missing context, blocked tool. Each item is
a candidate improvement to the project instructions, rules, skills or agents.>
