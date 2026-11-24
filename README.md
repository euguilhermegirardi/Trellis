# Trellis

*A reusable harness for Claude Code agents.*

Trellis is a collection of installable packs (rules, skills, agents, hooks and scripts) that give
Claude Code a consistent, safe way of working across projects: a core of stack-agnostic guardrails plus
optional packs per stack.

> Status: work in progress. Packs are being extracted one at a time, with tests.

## Layout

```
packs/
  core/            stack-agnostic rules, skills, agents and hooks
  stacks/
    react/         React + TypeScript conventions
    dotnet/        .NET conventions
scripts/           installer and maintenance scripts
templates/         per-project configuration templates
docs/              design notes
examples/          sample projects
tests/             tests for hooks and scripts
```

## License

MIT. See [LICENSE](LICENSE).
