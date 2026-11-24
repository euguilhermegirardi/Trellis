#!/usr/bin/env bash
set -u
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

check() { (cd "$REPO" && bash .githooks/living-doc-check.sh); }
stage() { mkdir -p "$REPO/$(dirname "$1")"; printf '%s\n' "${2:-x}" > "$REPO/$1"; git -C "$REPO" add "$1"; }
config() { mkdir -p "$REPO/.trellis"; cat > "$REPO/.trellis/living-doc.json"; }

echo "living-doc-check"

new_repo
stage src/modules/a/Screen.tsx
expect_exit 0 "no config means no check" check

new_repo
config <<'JSON'
{ "plan": "docs/PLAN.md", "triggers": ["src/modules/**", "database/schema/**"], "excludes": ["**/*.test.tsx"], "skipBranches": ["wip/*"] }
JSON
stage README.md
expect_exit 0 "unrelated change passes" check

new_repo
config <<'JSON'
{ "plan": "docs/PLAN.md", "triggers": ["src/modules/**", "database/schema/**"], "excludes": ["**/*.test.tsx"], "skipBranches": ["wip/*"] }
JSON
stage src/modules/a/Screen.tsx
expect_exit 1 "screen change without the plan is blocked" check
expect_output "message names the trigger file" "src/modules/a/Screen.tsx"
expect_output "message explains the fix" "living-doc-log"

stage docs/PLAN.md "plan"
expect_exit 0 "same change with the plan passes" check

new_repo
config <<'JSON'
{ "plan": "docs/PLAN.md", "triggers": ["src/modules/**", "database/schema/**"], "excludes": ["**/*.test.tsx"], "skipBranches": ["wip/*"] }
JSON
stage src/modules/a/Screen.test.tsx
expect_exit 0 "excluded test file does not trigger" check

new_repo
config <<'JSON'
{ "plan": "docs/PLAN.md", "triggers": ["src/modules/**", "database/schema/**"], "excludes": [], "skipBranches": ["wip/*"] }
JSON
stage database/schema/001_x.sql
expect_exit 1 "schema change is a trigger" check

new_repo
config <<'JSON'
{ "plan": "docs/PLAN.md", "triggers": ["src/modules/**"], "excludes": [], "skipBranches": ["wip/*"] }
JSON
git -C "$REPO" checkout -q -b wip/spike
stage src/modules/a/Screen.tsx
expect_exit 0 "skip branch is exempt" check

new_repo
config <<'JSON'
{ "plan": "docs/PLAN.md", "triggers": ["src/modules/**"], "excludes": [], "skipBranches": [] }
JSON
stage src/modules/a/Screen.tsx
expect_exit 1 "gate has no environment override" env SKIP_PLAN_CHECK=1 bash -c "cd '$REPO' && bash .githooks/living-doc-check.sh"

new_repo
config <<'JSON'
{ "plan": "docs/PLAN.md", "triggers": ["src/modules/**"], "excludes": [], "skipBranches": [] }
JSON
stage src/modules/a/Screen.tsx
expect_exit 1 "git commit is rejected by the hook" git -C "$REPO" commit -q -m "feat: screen"

new_repo
config <<'JSON'
{ "plan": "docs/PLAN.md", "triggers": ["src/modules/**"], "excludes": [], "skipBranches": [] }
JSON
stage README.md
git -C "$REPO" -c core.hooksPath=/dev/null commit -q -m base
git -C "$REPO" checkout -q -b other
stage src/modules/a/Screen.tsx
git -C "$REPO" -c core.hooksPath=/dev/null commit -q -m screen
git -C "$REPO" checkout -q main
stage docs/PLAN.md
git -C "$REPO" -c core.hooksPath=/dev/null commit -q -m plan
expect_exit 0 "merge commit is exempt" git -C "$REPO" merge --no-ff other -m "merge other"

summary
