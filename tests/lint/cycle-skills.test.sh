#!/usr/bin/env bash
# Structural checks for the three cycle skills and the config they document.
set -u
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
S="$ROOT/packs/core/skills"
PASS=0
FAIL=0
ok() { PASS=$((PASS + 1)); echo "  ok   $1"; }
bad() { FAIL=$((FAIL + 1)); echo "  FAIL $1"; }
has() { grep -qiE -- "$2" "$1" && ok "$3" || bad "$3"; }
front_name() { awk 'NR==1 {next} /^---$/ {exit} /^name:/ {sub(/^name: */,""); print}' "$1"; }

echo "cycle-skills"
for n in delivery-cycle unattended-mode close-and-pr; do
  f="$S/$n/SKILL.md"
  [ -f "$f" ] && [ "$(front_name "$f")" = "$n" ] && ok "$n exists with a matching name" || bad "$n missing or misnamed"
done

has "$S/delivery-cycle/SKILL.md" 'fresh context' "cycle requires a fresh tester context"
has "$S/delivery-cycle/SKILL.md" 'no progress' "cycle stops on repeated failures"
has "$S/delivery-cycle/SKILL.md" 'DISPUTE' "cycle handles builder disputes"
has "$S/delivery-cycle/SKILL.md" 'max_rounds|maxRounds' "rounds are configurable"
has "$S/unattended-mode/SKILL.md" 'No push and no pull request' "unattended mode forbids push and PR"
has "$S/unattended-mode/SKILL.md" 'do not try to work around' "unattended mode forbids working around blocks"
has "$S/close-and-pr/SKILL.md" 'protected base branch' "close skill targets the base branch"
has "$S/close-and-pr/SKILL.md" 'no signature' "close skill forbids signatures"
has "$S/close-and-pr/SKILL.md" 'git log origin' "close skill verifies nothing was left behind"

# The JSON examples inside the skills must parse, and the shipped template must match the documented keys.
python3 - "$S/delivery-cycle/SKILL.md" "$S/unattended-mode/SKILL.md" "$ROOT/templates/trellis/cycle.json" <<'PY' && ok "JSON examples parse and the cycle template matches the documented keys" || bad "JSON examples or template mismatch"
import json, re, sys
blocks = []
for path in sys.argv[1:3]:
    blocks += re.findall(r"```json\n(.*?)```", open(path).read(), re.S)
parsed = [json.loads(b) for b in blocks]
assert len(parsed) == 2, len(parsed)
documented = next(p for p in parsed if "maxRounds" in p)
shipped = json.load(open(sys.argv[3]))
assert set(documented) == set(shipped), (set(documented) ^ set(shipped))
state = next(p for p in parsed if "step" in p)
assert state["step"] in ("build", "test", "design", "security", "report", "done")
assert state["outcome"] in ("in-progress", "delivered", "stopped")
PY
echo "  $PASS passed, $FAIL failed"
[ "$FAIL" = 0 ]
