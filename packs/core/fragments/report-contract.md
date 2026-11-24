# Agent report contract

Every reviewing or testing agent ends its work with a report in this exact shape. The orchestrator
parses the first line to decide what happens next, so the format is a contract, not a suggestion.

## Shape

```
RESULT: GREEN | FAILURES | BLOCKED
<one summary line with the facts the orchestrator needs: counts, commands run, artifacts>

FAILURE 1
- Type: <one of the types allowed for this agent>
- Where: <test name, file, component or screen>
- Scenario: <what the user does, or the data involved>
- Expected: <behavior>  (Source: <spec section | project rule | rule file>)
- Actual: <behavior or a short error message>
- Hint: <likely file or line, without fixing it>
```

## Rules for `RESULT`

- `GREEN`: everything passed and nothing needs attention.
- `FAILURES`: at least one failure the builder can fix. The orchestrator sends the report back to the
  builder.
- `BLOCKED`: only failures that no builder can fix: the specification contradicts the backend, or the
  environment could not run the checks. The orchestrator stops and escalates to the human.

## Failure types

Types are declared per agent so the orchestrator can route them. A sensible starting set:

| Type | Raised by | Routed to |
|---|---|---|
| `feature-bug` | tester, design reviewer, security reviewer | builder |
| `design` | design reviewer | builder |
| `spec-backend-mismatch` | tester | human (`BLOCKED`) |
| `environment` | any | human (`BLOCKED`) |

## Honesty rules

- **Never fake a result.** If a check could not run (for example end-to-end tests without a browser),
  say `not run` and give the reason. A missing check is `BLOCKED` or reported as skipped, never "passed".
- **Never weaken a check to make it pass.** Do not delete, skip or replace the expected value with the
  actual one when the expectation comes from the specification, a project rule or a role test.
- **Retest rounds:** run everything again and state which failures from the previous round disappeared,
  which remain and which are new.
- If nothing was found, say what was verified. Do not invent findings to look useful.

## Variant for security findings

A security reviewer replaces `FAILURE n` with `FINDING n` and adds:

- `Severity: critical | high | medium | low`
- `Confidence: confirmed | suspected, to verify`
- `Attack scenario: <who does what and what they gain>`
- `Suggested fix: <short>`

Medium severity or above blocks the cycle and returns to the builder. Violating a written project
security rule is at least medium, even with no impact today.
