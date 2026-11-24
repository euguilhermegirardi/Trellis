#!/usr/bin/env bash
# Tests for packs/core/hooks/git/scan-secrets.sh. Fake secrets are assembled at runtime so this file
# never contains a literal that a scanner (or the hook itself) would flag.
set -u
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

scan() { (cd "$REPO" && bash .githooks/scan-secrets.sh); }
stage() { # stage <path> <content>
  mkdir -p "$REPO/$(dirname "$1")"
  printf '%s\n' "$2" > "$REPO/$1"
  git -C "$REPO" add "$1"
}

aws="AK""IA""ABCDEFGHIJKLMNOP"
ghtok="gh""p_""$(printf 'a%.0s' $(seq 1 36))"
pem="-----BEGIN RSA ""PRIVATE KEY-----"
bcrypt="\$2""b\$12\$$(printf 'a%.0s' $(seq 1 53))"

echo "scan-secrets"

new_repo
stage src/app.txt "hello world"
expect_exit 0 "clean change passes" scan

new_repo
expect_exit 0 "nothing staged passes" scan

new_repo
stage src/key.txt "id = $aws"
expect_exit 1 "AWS key id is blocked" scan
expect_output "report names the file and line" "src/key.txt:1"
expect_no_output "report does not echo the value" "$aws"

new_repo
stage src/t.txt "token $ghtok"
expect_exit 1 "GitHub token is blocked" scan

new_repo
stage src/k.txt "$pem"
expect_exit 1 "private key header is blocked" scan

new_repo
stage src/u.txt "hash: $bcrypt"
expect_exit 1 "bcrypt hash is blocked" scan

new_repo
stage src/c.txt "url = postgres://admin:hunter2pass@db.internal/app" # trellis:allow-secret
expect_exit 1 "credentials in a URL are blocked" scan

new_repo
stage src/cfg.json "{ \"password\": \"s3cretValue99\" }"
expect_exit 1 "quoted password assignment is blocked" scan

new_repo
stage src/e.txt "API_KEY=abcdef1234567890"
expect_exit 1 "env-style assignment is blocked" scan

new_repo
stage src/ok.txt "const password = process.env.DB_PASSWORD"
expect_exit 0 "reading from the environment passes" scan

new_repo
stage src/ok2.txt "password: \"changeme-example\""
expect_exit 0 "obvious placeholder passes" scan

new_repo
stage src/ok3.txt "The user enters a password in the form."
expect_exit 0 "prose mentioning password passes" scan

new_repo
stage .env "A=1"
expect_exit 1 ".env file is blocked" scan
expect_output "report lists the forbidden file" "\.env"

new_repo
stage .env.example "DB_PASSWORD=<your-password>"
expect_exit 0 ".env.example is allowed" scan

new_repo
stage certs/server.pem "x"
expect_exit 1 ".pem file is blocked" scan

new_repo
stage config/dev.json "{}"
mkdir -p "$REPO/.trellis"; echo "config/dev.json" > "$REPO/.trellis/forbidden-files.txt"
expect_exit 1 "project forbidden-files list is honored" scan

new_repo
mkdir -p "$REPO/.trellis"; echo "internal ticket|TKT-[0-9]{4}" > "$REPO/.trellis/secret-patterns.txt"
stage src/n.txt "see TKT-1234"
expect_exit 1 "project secret pattern is honored" scan

new_repo
stage test/fixture.txt "id = $aws  # trellis:allow-secret"
expect_exit 0 "allow marker skips the line" scan

new_repo
mkdir -p "$REPO/.trellis"; echo "fixtures/*" > "$REPO/.trellis/secret-allow-files.txt"
stage fixtures/data.txt "id = $aws"
expect_exit 0 "allow-files glob skips the path" scan

new_repo
stage src/old.txt "id = $aws"
git -C "$REPO" -c core.hooksPath=/dev/null commit -q -m seed
printf 'clean\n' > "$REPO/src/old.txt"
git -C "$REPO" add src/old.txt
expect_exit 0 "removed secret lines are not flagged" scan

new_repo
stage src/a.txt "fine"
expect_exit 0 "git commit with the hook installed succeeds" git -C "$REPO" commit -q -m ok
new_repo
stage src/b.txt "id = $aws"
expect_exit 1 "git commit with a secret is rejected by the hook" git -C "$REPO" commit -q -m bad

summary
