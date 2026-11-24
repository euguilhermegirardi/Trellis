#!/usr/bin/env bash
set -u
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
PASS=0
FAIL=0
ok() { PASS=$((PASS + 1)); echo "  ok   $1"; }
bad() { FAIL=$((FAIL + 1)); echo "  FAIL $1"; }
has() { grep -qF -- "$2" "$1" && ok "$3" || bad "$3 (missing: $2)"; }

command -v node >/dev/null 2>&1 || { echo "living-doc-log"; echo "  skip (node not found)"; exit 0; }
echo "living-doc-log"

REPO="$(mktemp -d)"
git -C "$REPO" init -q -b main
git -C "$REPO" config user.name Test
git -C "$REPO" config user.email test@example.invalid
mkdir -p "$REPO/.trellis" "$REPO/docs" "$REPO/src/modules/billing"
cat > "$REPO/.trellis/living-doc.json" <<'JSON'
{ "plan": "docs/PLAN.md", "timezone": "UTC",
  "areas": [ { "match": "^src/modules/([^/]+)/", "label": "modules/$1" }, { "match": "^docs/", "label": "docs" } ] }
JSON
printf '# Plan\n\n## Log\n\n- 2026-01-01 — `main`: first.\n' > "$REPO/docs/PLAN.md"
git -C "$REPO" add -A
git -C "$REPO" commit -q -m "chore: base"
git -C "$REPO" checkout -q -b feat/billing
printf 'a\n' > "$REPO/src/modules/billing/Page.tsx"
git -C "$REPO" add -A
git -C "$REPO" commit -q -m "feat(billing): add page"
printf 'b\n' > "$REPO/src/modules/billing/Other.tsx"
git -C "$REPO" add -A
git -C "$REPO" commit -q -m "feat(billing): add other"

LINE="$(cd "$REPO" && node "$ROOT/scripts/living-doc-log.mjs" 2>/dev/null)"
case "$LINE" in *'`feat/billing`'*'feat(billing): add page; feat(billing): add other'*'modules/billing (2)'*) ok "prints a line with branch, commits in order and areas" ;; *) bad "line shape: $LINE" ;; esac

(cd "$REPO" && node "$ROOT/scripts/living-doc-log.mjs" --write >/dev/null 2>&1)
has "$REPO/docs/PLAN.md" '`feat/billing`:' "--write inserts the branch line"
FIRST="$(grep -n '^- ' "$REPO/docs/PLAN.md" | head -1)"
case "$FIRST" in *'feat/billing'*) ok "new line goes to the top" ;; *) bad "new line not at top: $FIRST" ;; esac
has "$REPO/docs/PLAN.md" '`main`: first.' "older entries are kept"

sed -i.bak 's|add other\.|add other. Pending: wire the API.|' "$REPO/docs/PLAN.md"
printf 'c\n' > "$REPO/src/modules/billing/Third.tsx"
git -C "$REPO" add -A
git -C "$REPO" commit -q -m "feat(billing): add third"
(cd "$REPO" && node "$ROOT/scripts/living-doc-log.mjs" --write >/dev/null 2>&1)
COUNT="$(grep -c 'feat/billing`:' "$REPO/docs/PLAN.md")"
[ "$COUNT" = 1 ] && ok "running again keeps one line per branch" || bad "expected 1 line, got $COUNT"
has "$REPO/docs/PLAN.md" 'add third' "the updated line has the new commit"
has "$REPO/docs/PLAN.md" 'Pending: wire the API.' "a hand-written Pending tail is preserved"

printf '# Plan\n' > "$REPO/docs/PLAN.md"
(cd "$REPO" && node "$ROOT/scripts/living-doc-log.mjs" --write >/dev/null 2>"$REPO/err.txt"); rc=$?
[ "$rc" != 0 ] && ok "fails when the log heading is missing" || bad "should fail without the heading"
has "$REPO/err.txt" 'not found' "error names the missing heading"

rm -rf "$REPO/.trellis"
(cd "$REPO" && node "$ROOT/scripts/living-doc-log.mjs" >/dev/null 2>&1); rc=$?
[ "$rc" != 0 ] && ok "fails without configuration" || bad "should fail without configuration"

echo "  $PASS passed, $FAIL failed"
[ "$FAIL" = 0 ]
