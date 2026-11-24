# Project instructions

> Short on purpose. Details live in `docs/`, `.claude/rules/` (loaded by path) and `.claude/skills/`.

## What this is

<One paragraph: what the system does, for whom, and the stack.>

## Where things are

- `docs/` - specification and the living plan.
- `.claude/rules/` - conventions by path, loaded on demand.
- `.claude/agents/` - builder, tester, design reviewer, security reviewer.
- `.claude/skills/` - the step-by-step procedures.

## Commands

```bash
<install dependencies>
<run the app>
<format, lint, typecheck, test>
```

## Security rules (non-negotiable)

1. No secret in a versioned file. Secrets live in an untracked settings file or environment variables.
2. Before every commit: read `git diff --cached` and scan for secrets. If you find one, stop.
3. <Project-specific access rules: who may read and write what.>

## Git and pull requests

- The protected branch is never committed to or pushed directly. Work on a feature branch; the human merges.
- Never `--force`, never `--no-verify`.
- Pull request descriptions follow the pull request rule (no signatures; format by type).
