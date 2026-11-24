#!/usr/bin/env bash
# Tiny test helpers shared by the hook tests.
PASS=0
FAIL=0
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

new_repo() {
  REPO="$(mktemp -d)"
  git -C "$REPO" init -q -b main
  git -C "$REPO" config user.name "Test"
  git -C "$REPO" config user.email "test@example.invalid"
  mkdir -p "$REPO/.githooks"
  cp "$ROOT"/packs/core/hooks/git/* "$REPO/.githooks/"
  chmod +x "$REPO"/.githooks/*
  git -C "$REPO" config core.hooksPath .githooks
}

# expect_exit <expected> <name> <command...>
expect_exit() {
  local want="$1" name="$2"
  shift 2
  OUT="$("$@" 2>&1)"
  local got=$?
  if [ "$got" = "$want" ]; then PASS=$((PASS + 1)); echo "  ok   $name"
  else FAIL=$((FAIL + 1)); echo "  FAIL $name (exit $got, wanted $want)"; echo "$OUT" | sed 's/^/       /'; fi
}

expect_output() {
  local name="$1" pattern="$2"
  if printf '%s' "$OUT" | grep -qE -- "$pattern"; then PASS=$((PASS + 1)); echo "  ok   $name"
  else FAIL=$((FAIL + 1)); echo "  FAIL $name (output lacks /$pattern/)"; fi
}

expect_no_output() {
  local name="$1" pattern="$2"
  if printf '%s' "$OUT" | grep -qE -- "$pattern"; then FAIL=$((FAIL + 1)); echo "  FAIL $name (output contains /$pattern/)"
  else PASS=$((PASS + 1)); echo "  ok   $name"; fi
}

summary() {
  echo "  $PASS passed, $FAIL failed"
  [ "$FAIL" = 0 ]
}
