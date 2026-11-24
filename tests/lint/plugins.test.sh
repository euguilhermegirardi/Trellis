#!/usr/bin/env bash
# Validates the plugin marketplace and each plugin with the Claude Code CLI. Skipped when `claude` is missing.
set -u
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
PASS=0
FAIL=0
echo "plugins"
command -v claude >/dev/null 2>&1 || { echo "  skip (claude CLI not found)"; exit 0; }
for target in "$ROOT" "$ROOT/packs/core" "$ROOT/packs/stacks/react" "$ROOT/packs/stacks/dotnet"; do
  rel="${target#"$ROOT"}"; rel="${rel:-/}"
  if (cd "$target" && claude plugin validate . >/dev/null 2>&1); then PASS=$((PASS + 1)); echo "  ok   $rel validates"
  else FAIL=$((FAIL + 1)); echo "  FAIL $rel does not validate"; fi
done
echo "  $PASS passed, $FAIL failed"
[ "$FAIL" = 0 ]
