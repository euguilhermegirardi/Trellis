#!/usr/bin/env bash
set -u
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

echo "install-hooks"

REPO="$(mktemp -d)"; git -C "$REPO" init -q -b main
expect_exit 0 "installs into a git repo" bash "$ROOT/scripts/install-hooks.sh" "$REPO"
expect_exit 0 "pre-commit is executable" test -x "$REPO/.githooks/pre-commit"
expect_exit 0 "scan-secrets is executable" test -x "$REPO/.githooks/scan-secrets.sh"
expect_exit 0 "pre-push is installed" test -x "$REPO/.githooks/pre-push"
OUT="$(git -C "$REPO" config --local core.hooksPath)"
expect_output "core.hooksPath is set locally" "^\.githooks$"
expect_exit 0 "running twice is fine" bash "$ROOT/scripts/install-hooks.sh" "$REPO"

REPO="$(mktemp -d)"; git -C "$REPO" init -q -b main
expect_exit 0 "dry run succeeds" bash "$ROOT/scripts/install-hooks.sh" --dry-run "$REPO"
expect_exit 1 "dry run writes nothing" test -d "$REPO/.githooks"

NOREPO="$(mktemp -d)"
expect_exit 2 "refuses a non-repository" bash "$ROOT/scripts/install-hooks.sh" "$NOREPO"

summary
