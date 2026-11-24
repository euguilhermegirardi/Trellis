#!/usr/bin/env bash
set -u
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

zero="0000000000000000000000000000000000000000"
sha="1111111111111111111111111111111111111111"
run_push() { # run_push <remote_ref> <local_sha>
  (cd "$REPO" && printf 'refs/heads/x %s %s %s\n' "$2" "$1" "$zero" | bash .githooks/pre-push origin url)
}

echo "pre-push"

new_repo
expect_exit 1 "push to main is blocked" run_push refs/heads/main "$sha"
expect_exit 1 "push to master is blocked" run_push refs/heads/master "$sha"
expect_exit 0 "push to a feature branch passes" run_push refs/heads/feat/x "$sha"
expect_exit 1 "deleting main is blocked" run_push refs/heads/main "$zero"
expect_output "message explains the fix" "pull request|protected"

new_repo
mkdir -p "$REPO/.trellis"; echo "release" > "$REPO/.trellis/protected-branches.txt"
expect_exit 1 "project protected branch is honored" run_push refs/heads/release "$sha"
expect_exit 0 "deleting a feature branch passes" run_push refs/heads/feat/old "$zero"

summary
