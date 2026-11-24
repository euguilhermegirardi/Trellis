# Pull request descriptions

Applies to every project. Write the title and body in the project's language.

## No signatures

The title and body carry no authorship or tooling footer: no "Generated with ..." line, no session
links, no `Co-Authored-By` trailers. The body contains only content.

## Title

Short, in the imperative mood, describing the result (for example "Fix upload size check").

## Body, by type

Pick the format that matches the change.

- **Fix:** `Problem` (what broke, or what the user saw) -> `Cause` (one line) -> `Solution`.
- **New feature:** a complete description: what it does and for whom, screens or endpoints involved,
  access rules, and design decisions worth knowing.
- **Addition or maintenance** (docs, chore, refactor, tests): `What was added or changed` and `Why`.

Every body ends with:

- `How it was verified`: tests that were run and any manual checks.
- `Out of scope`: what was left for later.
