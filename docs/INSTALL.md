# Installing Trellis

Trellis has two ways in. They install the same content; pick one, or use both.

## 1. The installer (everything, including rules and hooks)

From a clone of this repository:

```bash
scripts/install.sh /path/to/your/project --stack react --stack dotnet
scripts/install.sh --user
```

- The core pack is always installed; `--stack` adds `react` and/or `dotnet`.
- `--user` also adds the pull request rule to `~/.claude/CLAUDE.md`, so it applies to every project on the machine.
- `--dry-run` prints what would change. Run it first.
- Run it again to upgrade. A manifest (`.trellis/installed.json`) remembers what was installed, so a file you edited
  is kept and reported; `--force` overwrites it.
- The installer never overwrites `.trellis/*.json` (your configuration) and keeps your own text in `CLAUDE.md`:
  Trellis content lives between `<!-- trellis:begin ... -->` and `<!-- trellis:end ... -->` markers.

Presets (lint, formatting, end-to-end) are not installed automatically because they must match your layout.
Copy what you need from `packs/stacks/react/presets/`.

## 2. The plugin marketplace (skills, agents and the unattended guard)

```
/plugin marketplace add euguilhermegirardi/Trellis
/plugin install trellis-core@trellis
/plugin install trellis-react@trellis
```

Plugins carry skills, agents and hooks. They cannot carry rules, `CLAUDE.md` fragments or git hooks, which is why the
installer exists. Plugin skills are namespaced, for example `trellis-core:pre-commit-check`.

## Configuration

Files under `.trellis/` tune the packs: `living-doc.json`, `capture.json`, `secret-patterns.txt`,
`forbidden-files.txt`, `secret-allow-files.txt`, `protected-branches.txt`. All are optional.
