#!/usr/bin/env bash
# Structural checks on agent definitions: tool boundaries and the report contract.
set -u
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
PASS=0
FAIL=0
ok() { PASS=$((PASS + 1)); echo "  ok   $1"; }
bad() { FAIL=$((FAIL + 1)); echo "  FAIL $1"; }
front() { awk 'NR==1 && $0!="---" {exit} NR==1 {next} /^---$/ {exit} {print}' "$1"; }
tools_of() { front "$1" | sed -n 's/^tools: *//p' | head -1; }

echo "agents"
shopt -s nullglob
for f in "$ROOT"/packs/*/agents/*.md "$ROOT"/packs/stacks/*/agents/*.md; do
  rel="${f#"$ROOT"/}"
  name="$(basename "$f" .md)"
  tools="$(tools_of "$f")"
  fm="$(front "$f")"

  printf '%s\n' "$fm" | grep -q '^model:' && ok "$rel declares a model" || bad "$rel has no model"

  case "$name" in
    security-reviewer|design-reviewer)
      case "$tools" in *Edit*|*Write*|*NotebookEdit*) bad "$rel is read-only but has write tools ($tools)" ;; *) ok "$rel is read-only" ;; esac ;;
  esac

  case "$name" in
    tester|security-reviewer|design-reviewer)
      if grep -q 'RESULT: GREEN | FAILURES | BLOCKED' "$f"; then ok "$rel uses the report contract"; else bad "$rel lacks the RESULT line"; fi ;;
  esac

  if grep -qE -- '--no-verify|--force' "$f"; then
    tr '\n' ' ' < "$f" | grep -qiE 'never[^.]*(--no-verify|--force)|(--no-verify|--force)[^.]*(never|must not)' && ok "$rel only mentions skip flags as prohibited" || bad "$rel mentions a skip flag without prohibiting it"
  fi

  grep -q 'Commands rule' "$f" && ok "$rel points to the Commands rule" || bad "$rel does not point to the Commands rule"
done
echo "  $PASS passed, $FAIL failed"
[ "$FAIL" = 0 ]
