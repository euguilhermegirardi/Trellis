#!/usr/bin/env bash
# Tests for scripts/run-unattended.sh with a fake `claude` and a fake `gh` on PATH and a local bare repository as
# origin. Nothing here touches the network or a real agent.
set -u
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
LAUNCHER="$ROOT/scripts/run-unattended.sh"
PASS=0
FAIL=0
ok() { PASS=$((PASS + 1)); echo "  ok   $1"; }
bad() { FAIL=$((FAIL + 1)); echo "  FAIL $1"; }
check() { if eval "$2"; then ok "$1"; else bad "$1"; fi; }

command -v python3 >/dev/null 2>&1 && command -v perl >/dev/null 2>&1 || { echo "run-unattended"; echo "  skip (python3/perl not found)"; exit 0; }
echo "run-unattended"

# ---------- fakes
BIN="$(mktemp -d)"
cat > "$BIN/claude" <<'FAKE'
#!/usr/bin/env bash
if [ "${1:-}" = "--help" ]; then echo "usage: claude [--permission-prompts]"; exit 0; fi
n=$(( $(cat "$FAKE_DIR/count" 2>/dev/null || echo 0) + 1 )); echo "$n" > "$FAKE_DIR/count"
echo "CALL $n $*" >> "$FAKE_LOG"
echo "ENV unattended=${TRELLIS_UNATTENDED:-} apikey=${ANTHROPIC_API_KEY:-unset} token=${CLAUDE_CODE_OAUTH_TOKEN:-none}" >> "$FAKE_LOG"
state() { mkdir -p .trellis/run; printf '{"unit":"Orders screen","branch":"%s","step":"done","round":0,"outcome":"%s","report":"docs/report.md","notes":[]}\n' "$1" "$2" > .trellis/run/current.json; }
work() { git checkout -q -b feat/orders-screen 2>/dev/null || git checkout -q feat/orders-screen; echo "$1" > "work$1.txt"; git add -A; git commit -q -m "feat: work $1"; }
report() { mkdir -p docs; printf '# Morning report\n\nIn one line: done.\n' > docs/report.md; git add docs/report.md; git commit -q -m "docs: report"; }
denials='{"result":"ok","permission_denials":[{"tool_name":"Bash","tool_input":{"command":"npm audit fix"}}]}'
case "$FAKE_MODE" in
  deliver) work 1; report; state feat/orders-screen delivered; echo "$denials" ;;
  stop) work 1; report; state feat/orders-screen stopped; echo "$denials" ;;
  dirty) work 1; report; state feat/orders-screen delivered; echo leftover > leftover.txt; echo '{}' ;;
  crash)
    if [ "$n" = 1 ]; then work 1; state feat/orders-screen in-progress; exit 1; fi
    work 2; report; state feat/orders-screen delivered; echo '{}' ;;
  nobranch) state "" delivered; echo '{}' ;;
  nocommits) git checkout -q -b feat/orders-screen; state feat/orders-screen delivered; echo '{}' ;;
  noop) echo '{}' ;;
esac
exit 0
FAKE
cat > "$BIN/gh" <<'FAKE'
#!/usr/bin/env bash
case "${1:-} ${2:-}" in
  "auth status") exit 0 ;;
  "pr list") [ -n "${FAKE_OPEN_PR:-}" ] && echo "$FAKE_OPEN_PR"; exit 0 ;;
  "pr view") exit 1 ;;
  "pr create") echo "GH $*" >> "$FAKE_LOG"; echo "https://example.invalid/pr/1"; exit 0 ;;
esac
exit 0
FAKE
chmod +x "$BIN/claude" "$BIN/gh"

# ---------- a project clone with a bare origin
setup() {
  W="$(mktemp -d)"; ORIGIN="$W/origin.git"; REPO="$W/repo"; HOMEDIR="$W/home"; FAKE_DIR="$W/fake"
  mkdir -p "$HOMEDIR" "$FAKE_DIR"
  git init -q --bare -b main "$ORIGIN"
  git clone -q "$ORIGIN" "$REPO" 2>/dev/null
  git -C "$REPO" config user.name Test; git -C "$REPO" config user.email test@example.invalid
  git -C "$REPO" checkout -q -b main 2>/dev/null
  mkdir -p "$REPO/scripts" "$REPO/.trellis"
  cp "$LAUNCHER" "$REPO/scripts/run-unattended.sh"
  cat > "$REPO/.trellis/unattended.json" <<'JSON'
{ "checkTrust": false, "prepare": [], "requiredCommands": [], "allowedTools": ["Bash(npm *)"], "model": "opus", "maxUsd": 7, "maxTurns": 50, "attempts": 2 }
JSON
  printf 'x\n' > "$REPO/README.md"
  git -C "$REPO" add -A; git -C "$REPO" commit -q -m init; git -C "$REPO" push -q -u origin main 2>/dev/null
  printf 'Orders screen\n# comment\nReports screen\n' > "$REPO/unattended.queue"
  LOGF="$FAKE_DIR/log"; : > "$LOGF"
}
launch() { # launch <mode> [args...]
  local mode="$1"; shift
  OUT="$(cd "$REPO" && PATH="$BIN:$PATH" HOME="$HOMEDIR" FAKE_MODE="$mode" FAKE_LOG="$LOGF" FAKE_DIR="$FAKE_DIR" ANTHROPIC_API_KEY=sk-should-not-leak bash scripts/run-unattended.sh "$@" 2>&1)"
  RC=$?
}
calls() { grep -c '^CALL' "$LOGF"; }
remote_has() { git --git-dir="$ORIGIN" rev-parse --verify -q "refs/heads/$1" >/dev/null; }

# ---------- delivered
setup; launch deliver
check "delivered: exits 0" "[ $RC = 0 ]"
check "delivered: the agent ran once" "[ \"\$(calls)\" = 1 ]"
check "delivered: branch was pushed by the launcher" "remote_has feat/orders-screen"
check "delivered: pull request targets the base branch" "grep -q 'GH pr create --base main --head feat/orders-screen' '$LOGF'"
check "delivered: title carries the unit and the outcome" "grep -q 'Orders screen - unattended run .* (delivered)' '$LOGF'"
check "delivered: PR body is the morning report plus denials" "grep -q 'Morning report' '$REPO/.trellis/run/pr-body.md' && grep -q 'npm audit fix' '$REPO/.trellis/run/pr-body.md'"
check "delivered: PR body has no signature" "! grep -qiE 'generated with|co-authored-by|claude.ai/code' '$REPO/.trellis/run/pr-body.md'"
check "delivered: agent sees TRELLIS_UNATTENDED=1" "grep -q 'unattended=1' '$LOGF'"
check "delivered: API key is not passed to the agent" "grep -q 'apikey=unset' '$LOGF'"
check "delivered: budget, turns and model flags reach the agent" "grep -q -- '--max-budget-usd 7' '$LOGF' && grep -q -- '--max-turns 50' '$LOGF' && grep -q -- '--model opus' '$LOGF'"
check "delivered: permission mode is dontAsk" "grep -q -- '--permission-mode dontAsk' '$LOGF'"
check "delivered: extra allowed tools come from the config" "grep -q 'Bash(npm \*)' '$LOGF'"
check "delivered: the prompt names the skill and the unit" "grep -q '/delivery-cycle Orders screen' '$LOGF'"
check "delivered: unit leaves the queue, others stay" "! grep -q '^Orders screen' '$REPO/unattended.queue' && grep -q 'Reports screen' '$REPO/unattended.queue'"
check "delivered: back on the base branch" "[ \"\$(git -C '$REPO' rev-parse --abbrev-ref HEAD)\" = main ]"
check "delivered: run artifacts do not dirty the tree" "[ -z \"\$(git -C '$REPO' status --porcelain)\" ]"
check "delivered: a log file was written" "ls '$REPO'/.trellis/run/logs/*.log >/dev/null 2>&1"

# ---------- stopped
setup; launch stop
check "stopped: still pushes and opens the PR" "[ $RC = 0 ] && remote_has feat/orders-screen && grep -q '(stopped)' '$LOGF'"
check "stopped: the unit stays in the queue" "grep -q '^Orders screen' '$REPO/unattended.queue'"

# ---------- resume after a crash
setup; launch crash
check "crash: a second attempt is made" "[ \"\$(calls)\" = 2 ]"
check "crash: the second prompt says RESUME" "grep -q 'RESUME' '$LOGF'"
check "crash: the first prompt does not" "[ \"\$(grep -c 'RESUME' '$LOGF')\" = 1 ]"
check "crash: delivered after resuming" "[ $RC = 0 ] && remote_has feat/orders-screen && grep -q '(delivered)' '$LOGF'"

# ---------- attempts exhausted without finishing
setup; launch noop
check "no state: fails with a report" "[ $RC = 1 ] && ls '$REPO'/.trellis/run/logs/*-FAILED.md >/dev/null 2>&1"
check "no state: nothing is pushed" "! remote_has feat/orders-screen"
check "no state: every attempt was used" "[ \"\$(calls)\" = 2 ]"

# ---------- bad outcomes
setup; launch nocommits
check "no commits: fails and does not push" "[ $RC = 1 ] && ! remote_has feat/orders-screen && printf '%s' \"\$OUT\" | grep -q 'no commits'"
setup; launch nobranch
check "no branch recorded: fails" "[ $RC = 1 ] && printf '%s' \"\$OUT\" | grep -q 'did not record'"

# ---------- uncommitted leftovers are stashed, not lost
setup; launch dirty
check "dirty: leftovers are stashed" "[ \"\$(git -C '$REPO' stash list | wc -l | tr -d ' ')\" = 1 ]"
check "dirty: the delivery still goes out" "[ $RC = 0 ] && remote_has feat/orders-screen"

# ---------- pre-flight refusals (the agent must never start)
setup; printf 'dirty\n' >> "$REPO/README.md"; launch deliver
check "dirty tree: refuses" "[ $RC = 1 ] && printf '%s' \"\$OUT\" | grep -q 'clean tree' && [ \"\$(calls)\" = 0 ]"
setup
OUT="$(cd "$REPO" && PATH="$BIN:$PATH" HOME="$HOMEDIR" FAKE_OPEN_PR=https://example.invalid/pr/9 FAKE_MODE=deliver FAKE_LOG="$LOGF" FAKE_DIR="$FAKE_DIR" bash scripts/run-unattended.sh 2>&1)"; RC=$?
check "open PR: refuses and names it" "[ $RC = 1 ] && printf '%s' \"\$OUT\" | grep -q 'already has an open pull request' && [ \"\$(calls)\" = 0 ]"
OUT="$(cd "$REPO" && PATH="$BIN:$PATH" HOME="$HOMEDIR" FAKE_OPEN_PR=https://example.invalid/pr/9 TRELLIS_REPEAT=1 FAKE_MODE=deliver FAKE_LOG="$LOGF" FAKE_DIR="$FAKE_DIR" bash scripts/run-unattended.sh 2>&1)"; RC=$?
check "open PR: TRELLIS_REPEAT=1 overrides" "[ $RC = 0 ] && [ \"\$(calls)\" = 1 ]"

setup; git -C "$REPO" worktree add -q "$W/extra" -b extra-branch 2>/dev/null; launch deliver
check "extra worktree: refuses" "[ $RC = 1 ] && printf '%s' \"\$OUT\" | grep -q 'worktrees' && [ \"\$(calls)\" = 0 ]"

setup
cat > "$REPO/.trellis/unattended.json" <<'JSON'
{ "checkTrust": true, "prepare": [], "requiredCommands": [] }
JSON
git -C "$REPO" add -A; git -C "$REPO" commit -q -m cfg; git -C "$REPO" push -q origin main 2>/dev/null
launch deliver
check "trust check: refuses a folder Claude Code does not trust" "[ $RC = 1 ] && printf '%s' \"\$OUT\" | grep -q 'does not trust' && [ \"\$(calls)\" = 0 ]"
printf '{"projects":{"%s":{"hasTrustDialogAccepted":true}}}\n' "$REPO" > "$HOMEDIR/.claude.json"
launch deliver
check "trust check: passes once the folder is trusted" "[ $RC = 0 ] && [ \"\$(calls)\" = 1 ]"

setup
cat > "$REPO/.trellis/unattended.json" <<'JSON'
{ "checkTrust": false, "prepare": ["exit 3"], "requiredCommands": [] }
JSON
git -C "$REPO" add -A; git -C "$REPO" commit -q -m cfg; git -C "$REPO" push -q origin main 2>/dev/null
launch deliver
check "prepare step failure: refuses before the agent" "[ $RC = 1 ] && printf '%s' \"\$OUT\" | grep -q 'prepare step failed' && [ \"\$(calls)\" = 0 ]"

setup
cat > "$REPO/.trellis/unattended.json" <<'JSON'
{ "checkTrust": false, "prepare": [], "requiredCommands": ["definitely-not-installed-xyz"] }
JSON
git -C "$REPO" add -A; git -C "$REPO" commit -q -m cfg; git -C "$REPO" push -q origin main 2>/dev/null
launch deliver
check "missing required command: refuses" "[ $RC = 1 ] && printf '%s' \"\$OUT\" | grep -q 'definitely-not-installed-xyz'"

# ---------- empty queue
setup; rm -f "$REPO/unattended.queue"; launch deliver
check "empty queue: exits 0 and does nothing" "[ $RC = 0 ] && [ \"\$(calls)\" = 0 ] && printf '%s' \"\$OUT\" | grep -q 'Queue is empty'"

# ---------- dry run
setup; launch deliver --dry-run
check "dry run: exits 0" "[ $RC = 0 ]"
check "dry run: the agent never starts" "[ \"\$(calls)\" = 0 ]"
check "dry run: nothing is pushed" "! remote_has feat/orders-screen"
check "dry run: the plan is printed" "printf '%s' \"\$OUT\" | grep -q 'Dry run: pre-flight passed' && printf '%s' \"\$OUT\" | grep -q 'pull request against main'"
check "dry run: the queue is untouched" "grep -q '^Orders screen' '$REPO/unattended.queue'"
setup; printf 'dirty\n' >> "$REPO/README.md"; launch deliver --dry-run
check "dry run: still runs the pre-flight checks" "[ $RC = 1 ] && printf '%s' \"\$OUT\" | grep -q 'clean tree'"

# ---------- explicit unit beats the queue
setup; launch deliver "Reports screen"
check "explicit unit: runs that unit" "grep -q '/delivery-cycle Reports screen' '$LOGF'"

rm -rf "$BIN"
echo "  $PASS passed, $FAIL failed"
[ "$FAIL" = 0 ]
