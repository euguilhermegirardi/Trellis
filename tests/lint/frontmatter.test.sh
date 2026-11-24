#!/usr/bin/env bash
# Structural checks for the pack content: every rule, skill and agent file must have valid front matter.
set -u
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
PASS=0
FAIL=0
ok() { PASS=$((PASS + 1)); echo "  ok   $1"; }
bad() { FAIL=$((FAIL + 1)); echo "  FAIL $1"; }

# front <file>: prints the front matter block (between the first two --- lines)
front() { awk 'NR==1 && $0!="---" {exit} NR==1 {next} /^---$/ {exit} {print}' "$1"; }

echo "frontmatter"

# Rules: front matter is optional, but when present it needs a non-empty `paths:` list.
while IFS= read -r f; do
  rel="${f#"$ROOT"/}"
  if [ "$(head -1 "$f")" = "---" ]; then
    fm="$(front "$f")"
    if printf '%s\n' "$fm" | grep -q '^paths:' && printf '%s\n' "$fm" | grep -qE '^  - ".+"'; then ok "$rel has paths"
    else bad "$rel front matter lacks a paths list"; fi
  else ok "$rel has no front matter (always loaded)"; fi
done < <(find "$ROOT/packs" -path '*/rules/*.md' | sort)

# Skills: SKILL.md with name equal to the folder and a description.
while IFS= read -r f; do
  rel="${f#"$ROOT"/}"
  dir="$(basename "$(dirname "$f")")"
  fm="$(front "$f")"
  name="$(printf '%s\n' "$fm" | sed -n 's/^name: *//p' | head -1)"
  desc="$(printf '%s\n' "$fm" | sed -n 's/^description: *//p' | head -1)"
  if [ "$name" = "$dir" ] && [ -n "$desc" ]; then ok "$rel name and description"
  else bad "$rel needs name == folder ($dir) and a description"; fi
done < <(find "$ROOT/packs" -name SKILL.md | sort)

# Agents: name, description and tools.
while IFS= read -r f; do
  rel="${f#"$ROOT"/}"
  fm="$(front "$f")"
  if printf '%s\n' "$fm" | grep -q '^name:' && printf '%s\n' "$fm" | grep -q '^description:' && printf '%s\n' "$fm" | grep -q '^tools:'; then ok "$rel name, description, tools"
  else bad "$rel needs name, description and tools"; fi
done < <(find "$ROOT/packs" -path '*/agents/*.md' | sort)

echo "  $PASS passed, $FAIL failed"
[ "$FAIL" = 0 ]
