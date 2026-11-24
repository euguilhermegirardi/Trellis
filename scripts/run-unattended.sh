#!/usr/bin/env bash
# Launcher for unattended runs of the delivery cycle (overnight or scheduled). Usage:
#   scripts/run-unattended.sh "Orders screen"       explicit unit
#   scripts/run-unattended.sh                        first entry of the queue file
#   scripts/run-unattended.sh --dry-run [unit]       run the pre-flight checks and print the plan, nothing else
#
# Division of labor:
#   - the agent (claude -p plus the delivery-cycle skill) builds, tests, reviews, commits on the feature branch and
#     writes the report;
#   - THIS script does what is risky and deterministic: checks the environment, limits time and cost, resumes if the
#     session dies, pushes the branch and opens the pull request. The agent has no push permission and the
#     guard-unattended hook blocks it.
# Configuration: .trellis/unattended.json (optional; environment variables TRELLIS_* override it).
# Works with the bash 3.2 that ships with macOS.
set -u

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT" || exit 1

DRY=0
if [ "${1:-}" = "--dry-run" ]; then DRY=1; shift; fi

CONF="$ROOT/.trellis/unattended.json"
cfg() { python3 - "$CONF" "$1" "$2" <<'PY'
import json, sys
try:
    d = json.load(open(sys.argv[1]))
except Exception:
    d = {}
v = d.get(sys.argv[2])
print(sys.argv[3] if v is None else (str(v).lower() if isinstance(v, bool) else v))
PY
}
cfg_list() { python3 - "$CONF" "$1" <<'PY'
import json, sys
try:
    d = json.load(open(sys.argv[1]))
except Exception:
    d = {}
for item in d.get(sys.argv[2]) or []:
    print(item)
PY
}

BASE="${TRELLIS_BASE_BRANCH:-$(cfg baseBranch main)}"
PREFIX="${TRELLIS_BRANCH_PREFIX:-$(cfg branchPrefix feat/)}"
SKILL="${TRELLIS_SKILL:-$(cfg skill delivery-cycle)}"
QUEUE="$(cfg queueFile unattended.queue)"
MODEL="${TRELLIS_MODEL:-$(cfg model opus)}"
LIMIT_SEC="${TRELLIS_LIMIT_SEC:-$(cfg limitSeconds 18000)}"
MAX_TURNS="${TRELLIS_MAX_TURNS:-$(cfg maxTurns 400)}"
MAX_USD="${TRELLIS_MAX_USD:-$(cfg maxUsd 25)}"
ATTEMPTS="${TRELLIS_ATTEMPTS:-$(cfg attempts 2)}"
CHECK_TRUST="$(cfg checkTrust true)"
FORCE_SUBSCRIPTION="$(cfg forceSubscription true)"
TOKEN_FILE="${TRELLIS_TOKEN_FILE:-$(cfg tokenFile "$HOME/.config/trellis/claude-oauth-token")}"
CLAUDE_BIN="${TRELLIS_CLAUDE:-claude}"

UNIT="${1:-}"
[ -z "$UNIT" ] && [ -f "$QUEUE" ] && UNIT="$(grep -v '^[[:space:]]*\(#\|$\)' "$QUEUE" | head -n1)"
if [ -z "$UNIT" ]; then echo "Queue is empty ($QUEUE). Nothing to do."; exit 0; fi

DATE="$(date +%F)"
SLUG="$(python3 -c 'import sys,unicodedata,re; t=unicodedata.normalize("NFKD",sys.argv[1]).encode("ascii","ignore").decode().lower(); print(re.sub(r"[^a-z0-9]+","-",t).strip("-"))' "$UNIT")"
RUN="$ROOT/.trellis/run"
LOGDIR="$RUN/logs"
mkdir -p "$LOGDIR"
STATE="$RUN/current.json"   # outside .claude/, which Claude Code protects against writes
LOG="$LOGDIR/$DATE-$SLUG.log"
DENIED="$RUN/denied.md"; : > "$DENIED"

# Keep run artifacts and the queue out of "git status" without touching versioned files.
if [ -d .git ]; then
  for pat in ".trellis/run/" "$QUEUE"; do
    grep -qxF "$pat" .git/info/exclude 2>/dev/null || { mkdir -p .git/info; echo "$pat" >> .git/info/exclude; }
  done
fi
exec > >(tee -a "$LOG") 2>&1

START="$(date +%s)"
notify() {
  if command -v osascript >/dev/null 2>&1; then osascript -e "display notification \"$1\" with title \"Trellis - unattended\"" >/dev/null 2>&1 || true
  elif command -v notify-send >/dev/null 2>&1; then notify-send "Trellis - unattended" "$1" >/dev/null 2>&1 || true; fi
}
log() { echo "[$(date '+%H:%M:%S')] $*"; }
fail() {
  {
    echo "# Unattended run did NOT run - $DATE ($UNIT)"
    echo
    echo "**Reason:** $1"
    echo
    if [ -s "$DENIED" ]; then echo "**Permissions denied to the agent:**"; echo; cat "$DENIED"; echo; fi
    if [ -n "$(git status --porcelain 2>/dev/null)" ]; then echo "**Loose files in the tree** (clean up before the next run):"; echo; git status --short | sed 's/^/    /'; echo; fi
    echo "Full log: \`.trellis/run/logs/$DATE-$SLUG.log\`."
  } > "$LOGDIR/$DATE-$SLUG-FAILED.md"
  echo "FAILED: $1"; notify "Did not run: $1"; exit 1
}

log "Start - unit: $UNIT (slug $SLUG)$( [ "$DRY" = 1 ] && echo ' [dry run]')"

# ---- 1. Credentials: a long-lived token (claude setup-token), never an API key
if [ "$FORCE_SUBSCRIPTION" = "true" ]; then
  unset ANTHROPIC_API_KEY ANTHROPIC_AUTH_TOKEN
  if [ -f "$TOKEN_FILE" ]; then
    CLAUDE_CODE_OAUTH_TOKEN="$(tr -d '[:space:]' < "$TOKEN_FILE")"; export CLAUDE_CODE_OAUTH_TOKEN
  else
    log "Note: $TOKEN_FILE does not exist; trying the existing Claude Code login (may fail outside an open session)."
  fi
fi

# ---- 2. Pre-flight (failing means not running, with a failure report)
for c in "$CLAUDE_BIN" git python3 gh perl $(cfg_list requiredCommands); do
  command -v "$c" >/dev/null 2>&1 || fail "command '$c' not found on PATH ($PATH)"
done
if [ "$CHECK_TRUST" = "true" ]; then
  python3 - "$ROOT" <<'TRUST' || fail "Claude Code does not trust this folder yet (without that it ignores permissions and guard hooks). Run 'claude' here once, answer Yes and exit with /exit"
import json, os, sys
base = os.environ.get("CLAUDE_CONFIG_DIR")
cands = [os.path.join(base, ".claude.json")] if base else []
cands.append(os.path.expanduser("~/.claude.json"))
projects = {}
for c in cands:
    try:
        projects.update(json.load(open(c)).get("projects", {}))
    except Exception:
        pass
# Trust applies to the folder or any folder above it, as Claude Code does.
real = os.path.realpath(sys.argv[1])
targets = set()
for p in (sys.argv[1], real):
    while True:
        targets.add(p)
        parent = os.path.dirname(p)
        if parent == p:
            break
        p = parent
sys.exit(0 if any(projects.get(t, {}).get("hasTrustDialogAccepted") for t in targets) else 1)
TRUST
fi
git worktree prune
[ "$(git worktree list | wc -l | tr -d ' ')" -eq 1 ] || fail "extra worktrees exist: $(git worktree list | tail -n +2 | awk '{print $1}' | tr '\n' ' '). Remove them with: git worktree remove --force <path>"
git fetch -q origin || fail "git fetch failed (network or credentials)"
[ -z "$(git status --porcelain)" ] || fail "uncommitted local changes; unattended runs need a clean tree"
if [ "$DRY" = 0 ]; then
  git checkout -q "$BASE" && git pull -q --ff-only || fail "could not update $BASE (checkout/pull)"
fi
gh auth status >/dev/null 2>&1 || fail "gh is not authenticated (run: gh auth login)"
if [ "${TRELLIS_REPEAT:-0}" != "1" ]; then
  OPEN_PR="$(gh pr list --head "$PREFIX$SLUG" --state open --json url --jq '.[0].url' 2>/dev/null)"
  [ -z "$OPEN_PR" ] || fail "this unit already has an open pull request ($OPEN_PR). Review and merge it and remove the unit from the queue, or run again with TRELLIS_REPEAT=1"
fi
if [ "$DRY" = 0 ]; then
  while IFS= read -r cmd; do
    [ -z "$cmd" ] && continue
    log "prepare: $cmd"
    sh -c "$cmd" || fail "prepare step failed: $cmd"
  done <<EOP
$(cfg_list prepare)
EOP
fi

PERM_PROMPTS=()
"$CLAUDE_BIN" --help 2>/dev/null | grep -q -- '--permission-prompts' && PERM_PROMPTS=(--permission-prompts none)

# ---- 3. What the agent may do alone (the rest is denied; denials are listed in the log and the PR)
ALLOWED=(
  Read Glob Grep Edit Write Agent Skill TaskCreate TaskUpdate TaskList TaskGet
  "Bash(cd *)" "Bash(pwd)" "Bash(ls *)" "Bash(cat *)" "Bash(head *)" "Bash(tail *)" "Bash(wc *)" "Bash(grep *)"
  "Bash(rg *)" "Bash(find *)" "Bash(sed *)" "Bash(awk *)" "Bash(sort *)" "Bash(uniq *)" "Bash(jq *)" "Bash(echo *)"
  "Bash(date *)" "Bash(sleep *)" "Bash(which *)" "Bash(test *)" "Bash(mkdir *)" "Bash(cp *)" "Bash(mv *)" "Bash(rm *)"
  "Bash(touch *)" "Bash(chmod +x *)"
  "Bash(git status *)" "Bash(git diff *)" "Bash(git log *)" "Bash(git show *)" "Bash(git add *)" "Bash(git commit *)"
  "Bash(git checkout *)" "Bash(git switch *)" "Bash(git branch *)" "Bash(git rev-parse *)" "Bash(git fetch *)"
  "Bash(git pull *)" "Bash(git merge *)" "Bash(git stash *)" "Bash(git restore *)" "Bash(git ls-files *)"
  "Bash(git rm *)" "Bash(git mv *)"
)
while IFS= read -r extra; do [ -n "$extra" ] && ALLOWED+=("$extra"); done <<EOA
$(cfg_list allowedTools)
EOA

INITIAL_PROMPT="/$SKILL $UNIT
Unattended run: the human is away and TRELLIS_UNATTENDED=1. Follow the unattended-mode skill: keep the state in
.trellis/run/current.json after every step, never wait for an answer (escalating means writing the report and
stopping), no push and no pull request (the launcher does that at the end). Today's date: $DATE."
RESUME_PROMPT="/$SKILL $UNIT
Unattended run (TRELLIS_UNATTENDED=1) - RESUME: the previous session died midway. Read .trellis/run/current.json and
the branch's git history, and continue from the recorded step (do not redo what is already committed). Same rules
as the unattended-mode skill. Today's date: $DATE."

if [ "$DRY" = 1 ]; then
  log "Dry run: pre-flight passed. Would run up to $ATTEMPTS attempt(s) of:"
  log "  $CLAUDE_BIN -p \"/$SKILL $UNIT ...\" --model $MODEL --permission-mode dontAsk --max-turns $MAX_TURNS --max-budget-usd $MAX_USD (limit ${LIMIT_SEC}s)"
  log "  allowed tools: ${#ALLOWED[@]} entries; then push $PREFIX$SLUG and open a pull request against $BASE."
  log "Nothing was started, pushed or changed."
  exit 0
fi

export TRELLIS_UNATTENDED=1
if command -v caffeinate >/dev/null 2>&1; then caffeinate -i -w $$ >/dev/null 2>&1 & fi   # keep a Mac awake while this runs

finished() { python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); sys.exit(0 if d.get("outcome") in ("delivered","stopped") else 1)' "$STATE" 2>/dev/null; }

attempt=1
rm -f "$STATE"
while [ "$attempt" -le "$ATTEMPTS" ]; do
  LEFT=$(( LIMIT_SEC - ( $(date +%s) - START ) ))
  [ "$LEFT" -gt 300 ] || { log "No time left for another attempt."; break; }
  if [ "$attempt" -eq 1 ]; then PROMPT="$INITIAL_PROMPT"; else PROMPT="$RESUME_PROMPT"; fi
  log "Attempt $attempt (limit ${LEFT}s, $MAX_TURNS turns, USD $MAX_USD, model $MODEL)"
  perl -e 'alarm shift; exec @ARGV' "$LEFT" \
    "$CLAUDE_BIN" -p "$PROMPT" --model "$MODEL" --permission-mode dontAsk ${PERM_PROMPTS[@]+"${PERM_PROMPTS[@]}"} \
      --allowedTools "${ALLOWED[@]}" --max-turns "$MAX_TURNS" --max-budget-usd "$MAX_USD" \
      --output-format json > "$LOGDIR/$DATE-$SLUG-attempt$attempt.json"
  code=$?
  log "claude exited with code $code"
  python3 - "$LOGDIR/$DATE-$SLUG-attempt$attempt.json" "$DENIED" <<'DEN'
import json, sys
try:
    d = json.load(open(sys.argv[1]))
except Exception:
    sys.exit(0)
with open(sys.argv[2], "a", encoding="utf-8") as f:
    for n in d.get("permission_denials") or []:
        inp = n.get("tool_input") or {}
        target = inp.get("command") or inp.get("file_path") or json.dumps(inp)
        target = " ".join(str(target).split())[:200]
        print("Denied: %s: %s" % (n.get("tool_name"), target))
        f.write("- %s: `%s`\n" % (n.get("tool_name"), target))
DEN
  finished && break
  attempt=$(( attempt + 1 ))
done

# ---- 4. Push and pull request (deterministic, outside the agent)
field() { python3 -c 'import json,sys; print(json.load(open(sys.argv[1])).get(sys.argv[2],sys.argv[3]))' "$STATE" "$1" "$2" 2>/dev/null; }
BRANCH="$(field branch '')"
OUTCOME="$(field outcome unknown)"
REPORT="$(field report '')"
log "Final state: outcome=$OUTCOME branch=$BRANCH report=$REPORT"

case "$BRANCH" in "$PREFIX"*) ;; *) fail "the cycle did not record a $PREFIX* branch in .trellis/run/current.json (outcome: $OUTCOME)";; esac
git checkout -q "$BRANCH" 2>/dev/null || fail "branch $BRANCH does not exist locally"
if [ -n "$(git status --porcelain)" ]; then git stash -u -q -m "unattended $DATE: uncommitted leftovers"; log "Note: there were uncommitted changes; stashed them."; fi
[ "$(git rev-list --count "origin/$BASE..HEAD")" -gt 0 ] || fail "branch $BRANCH has no commits beyond $BASE"

git push -q -u origin "$BRANCH" || fail "push of $BRANCH failed"
if gh pr view "$BRANCH" >/dev/null 2>&1; then
  log "A pull request already exists for $BRANCH (the push updated it)."
else
  TITLE="$UNIT - unattended run $DATE ($OUTCOME)"
  BODY="$RUN/pr-body.md"
  if [ -n "$REPORT" ] && [ -f "$REPORT" ]; then cat "$REPORT" > "$BODY"; else echo "Report not found; see .trellis/run/logs/$DATE-$SLUG.log." > "$BODY"; fi
  if [ -s "$DENIED" ]; then printf '\n## Permissions denied (recorded by the launcher)\n\n' >> "$BODY"; cat "$DENIED" >> "$BODY"; fi
  gh pr create --base "$BASE" --head "$BRANCH" --title "$TITLE" --body-file "$BODY" || fail "gh pr create failed"
fi
git checkout -q "$BASE"

# A delivered unit leaves the queue; a stopped one stays (you decide, then it runs again).
if [ "$OUTCOME" = "delivered" ] && [ -f "$QUEUE" ]; then
  python3 - "$UNIT" "$QUEUE" <<'PY'
import sys
unit, path = sys.argv[1], sys.argv[2]
lines = open(path, encoding="utf-8").read().splitlines()
done, out = False, []
for l in lines:
    if not done and l.strip() == unit:
        done = True
        continue
    out.append(l)
open(path, "w", encoding="utf-8").write("\n".join(out) + ("\n" if out else ""))
PY
fi

log "End: $OUTCOME - $BRANCH"
notify "$UNIT: $OUTCOME. Pull request opened for $BRANCH."
