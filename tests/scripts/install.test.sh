#!/usr/bin/env bash
# Tests for scripts/install.py using a fixture packs tree (TRELLIS_ROOT), so they do not depend on which
# packs exist in the repository at the time.
set -u
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
INSTALL="$ROOT/scripts/install.sh"
PASS=0
FAIL=0
ok() { PASS=$((PASS + 1)); echo "  ok   $1"; }
bad() { FAIL=$((FAIL + 1)); echo "  FAIL $1"; }
check() { if eval "$2"; then ok "$1"; else bad "$1"; fi; }

command -v python3 >/dev/null 2>&1 || { echo "install"; echo "  skip (python3 not found)"; exit 0; }
echo "install"

# ---- fixture packs
FX="$(mktemp -d)"
mkdir -p "$FX/packs/core/agents" "$FX/packs/core/skills/demo-skill" "$FX/packs/core/rules" "$FX/packs/core/hooks/git" \
  "$FX/packs/core/fragments" "$FX/packs/core/scripts" "$FX/packs/stacks/react/rules" "$FX/packs/stacks/dotnet/rules" \
  "$FX/templates/trellis"
printf -- '---\nname: tester\ndescription: d\ntools: Read\nmodel: sonnet\n---\nbody v1\n' > "$FX/packs/core/agents/tester.md"
printf -- '---\nname: demo-skill\ndescription: d\n---\nskill v1\n' > "$FX/packs/core/skills/demo-skill/SKILL.md"
printf 'extra\n' > "$FX/packs/core/skills/demo-skill/notes.md"
printf 'core rule\n' > "$FX/packs/core/rules/pull-requests.md"
printf '# Pull request descriptions\n\nNo signatures.\n\n## Title\n\nShort.\n' > "$FX/packs/core/rules/pull-requests.md"
printf '#!/usr/bin/env bash\necho guard\n' > "$FX/packs/core/hooks/guard-unattended.sh"
printf '{"hooks":{}}\n' > "$FX/packs/core/hooks/hooks.json"
printf '#!/usr/bin/env bash\necho precommit\n' > "$FX/packs/core/hooks/git/pre-commit"
printf '# Report contract\n\nText v1\n\n```\n# not a heading\n```\n' > "$FX/packs/core/fragments/report-contract.md"
printf '#!/usr/bin/env bash\necho tool\n' > "$FX/packs/core/scripts/tool.sh"
printf 'react rule\n' > "$FX/packs/stacks/react/rules/react-testing.md"
printf 'dotnet rule\n' > "$FX/packs/stacks/dotnet/rules/dotnet-backend.md"
printf '{ "plan": "docs/PLAN.md" }\n' > "$FX/templates/trellis/living-doc.json"
printf '# Project instructions\n\nMine.\n' > "$FX/templates/CLAUDE.project.md"

inst() { TRELLIS_ROOT="$FX" bash "$INSTALL" "$@"; }
new_target() { T="$(mktemp -d)"; git -C "$T" init -q -b main; }

# ---- basic install
new_target
OUT="$(inst "$T" --stack react 2>&1)"; rc=$?
check "exits 0" "[ $rc = 0 ]"
check "agent installed" "[ -f '$T/.claude/agents/tester.md' ]"
check "skill installed with its extra files" "[ -f '$T/.claude/skills/demo-skill/SKILL.md' ] && [ -f '$T/.claude/skills/demo-skill/notes.md' ]"
check "core rule installed" "[ -f '$T/.claude/rules/pull-requests.md' ]"
check "selected stack rule installed" "[ -f '$T/.claude/rules/react-testing.md' ]"
check "unselected stack is not installed" "[ ! -f '$T/.claude/rules/dotnet-backend.md' ]"
check "claude hook installed and executable" "[ -x '$T/.claude/hooks/guard-unattended.sh' ]"
check "plugin hooks.json is not copied as a hook" "[ ! -f '$T/.claude/hooks/hooks.json' ]"
check "git hook installed and executable" "[ -x '$T/.githooks/pre-commit' ]"
check "core.hooksPath set locally" "[ \"\$(git -C '$T' config --local core.hooksPath)\" = .githooks ]"
check "script installed and executable" "[ -x '$T/scripts/tool.sh' ]"
check "config template created" "[ -f '$T/.trellis/living-doc.json' ]"
check "manifest written" "[ -f '$T/.trellis/installed.json' ]"
check "CLAUDE.md created from the template" "grep -q 'Mine\.' '$T/CLAUDE.md'"
check "fragment is a managed block" "grep -q 'trellis:begin report-contract' '$T/CLAUDE.md' && grep -q 'trellis:end report-contract' '$T/CLAUDE.md'"
check "fragment headings shifted down one level" "grep -q '^## Report contract' '$T/CLAUDE.md'"
check "headings inside code fences are left alone" "grep -q '^# not a heading' '$T/CLAUDE.md'"

# ---- settings merge
S="$T/.claude/settings.json"
check "settings has the guard hook" "python3 -c \"import json,sys; d=json.load(open('$S')); sys.exit(0 if any('guard-unattended.sh' in h['command'] for e in d['hooks']['PreToolUse'] for h in e['hooks']) else 1)\""
check "settings denies force push and .env" "grep -q 'git push --force' '$S' && grep -q 'Read(./.env)' '$S'"

# ---- idempotence
OUT="$(inst "$T" --stack react 2>&1)"
check "second run changes nothing" "! printf '%s' \"\$OUT\" | grep -qE '^  (added|updated) '"
check "second run reports unchanged" "printf '%s' \"\$OUT\" | grep -q 'unchanged'"
check "guard hook is registered once" "[ \"\$(grep -c 'guard-unattended.sh' '$S')\" = 1 ]"
check "block is not duplicated in CLAUDE.md" "[ \"\$(grep -c 'trellis:begin report-contract' '$T/CLAUDE.md')\" = 1 ]"

# ---- upgrade: unedited files update, edited files are kept
printf -- '---\nname: tester\ndescription: d\ntools: Read\nmodel: sonnet\n---\nbody v2\n' > "$FX/packs/core/agents/tester.md"
printf 'skill v2\n' >> "$FX/packs/core/skills/demo-skill/SKILL.md"
printf '\nMY LOCAL EDIT\n' >> "$T/.claude/skills/demo-skill/SKILL.md"
printf '# Report contract\n\nText v2\n' > "$FX/packs/core/fragments/report-contract.md"
printf '\nMy own section\n' >> "$T/CLAUDE.md"
OUT="$(inst "$T" --stack react 2>&1)"
check "unedited file is updated" "grep -q 'body v2' '$T/.claude/agents/tester.md'"
check "locally edited file is kept" "grep -q 'MY LOCAL EDIT' '$T/.claude/skills/demo-skill/SKILL.md' && ! grep -q 'skill v2' '$T/.claude/skills/demo-skill/SKILL.md'"
check "kept file is reported" "printf '%s' \"\$OUT\" | grep -q 'kept.*demo-skill'"
check "managed block is refreshed" "grep -q 'Text v2' '$T/CLAUDE.md' && ! grep -q 'Text v1' '$T/CLAUDE.md'"
check "text outside the block survives" "grep -q 'My own section' '$T/CLAUDE.md' && grep -q 'Mine\.' '$T/CLAUDE.md'"
inst "$T" --stack react --force >/dev/null 2>&1
check "--force overwrites the local edit" "grep -q 'skill v2' '$T/.claude/skills/demo-skill/SKILL.md' && ! grep -q 'MY LOCAL EDIT' '$T/.claude/skills/demo-skill/SKILL.md'"

# ---- user config is never overwritten
printf '{ "plan": "mine.md" }\n' > "$T/.trellis/living-doc.json"
inst "$T" --stack react >/dev/null 2>&1
check "config under .trellis is never overwritten" "grep -q 'mine.md' '$T/.trellis/living-doc.json'"

# ---- settings merge keeps unrelated keys
new_target
mkdir -p "$T/.claude"
printf '{ "model": "sonnet", "permissions": { "allow": ["Bash(npm test:*)"], "deny": ["Read(./secrets/**)"] }, "hooks": { "PreToolUse": [ { "matcher": "Edit", "hooks": [ { "type": "command", "command": "echo mine" } ] } ] } }\n' > "$T/.claude/settings.json"
inst "$T" >/dev/null 2>&1
S="$T/.claude/settings.json"
check "existing keys are kept" "grep -q '\"model\": \"sonnet\"' '$S' && grep -q 'Bash(npm test:\*)' '$S' && grep -q 'Read(./secrets/\*\*)' '$S' && grep -q 'echo mine' '$S'"
check "guard hook was added next to the existing hook" "grep -q 'guard-unattended.sh' '$S'"

new_target
printf '{ not json' > /dev/null
mkdir -p "$T/.claude"; printf '{ broken' > "$T/.claude/settings.json"
OUT="$(inst "$T" 2>&1)"; rc=$?
check "invalid settings.json stops the install" "[ $rc != 0 ]"
check "invalid settings.json is left untouched" "[ \"\$(cat '$T/.claude/settings.json')\" = '{ broken' ]"

# ---- dry run
new_target
OUT="$(inst "$T" --stack react --dry-run 2>&1)"
check "dry run lists the changes" "printf '%s' \"\$OUT\" | grep -q 'added.*\.claude/agents/tester.md'"
check "dry run writes nothing" "[ ! -e '$T/.claude' ] && [ ! -e '$T/CLAUDE.md' ] && [ ! -e '$T/.trellis' ] && [ -z \"\$(git -C '$T' config --local core.hooksPath)\" ]"

# ---- errors
new_target
OUT="$(inst "$T" --stack nope 2>&1)"; rc=$?
check "unknown stack fails with the available list" "[ $rc = 2 ] && printf '%s' \"\$OUT\" | grep -q 'Available: dotnet, react'"
OUT="$(inst "$T/does-not-exist" 2>&1)"; rc=$?
check "missing target fails" "[ $rc = 2 ]"

# ---- non-git target
T="$(mktemp -d)"
OUT="$(inst "$T" 2>&1)"
check "non-git target installs and explains the hooks path" "[ -f '$T/.githooks/pre-commit' ] && printf '%s' \"\$OUT\" | grep -q 'not a git repository'"

# ---- user level
H="$(mktemp -d)"
printf 'My global notes.\n' > /dev/null
mkdir -p "$H/.claude"; printf 'My global notes.\n' > "$H/.claude/CLAUDE.md"
HOME="$H" TRELLIS_ROOT="$FX" bash "$INSTALL" --user >/dev/null 2>&1
check "--user adds the pull request block to ~/.claude/CLAUDE.md" "grep -q 'trellis:begin pull-requests' '$H/.claude/CLAUDE.md' && grep -q 'No signatures' '$H/.claude/CLAUDE.md'"
check "--user keeps existing global text" "grep -q 'My global notes' '$H/.claude/CLAUDE.md'"
HOME="$H" TRELLIS_ROOT="$FX" bash "$INSTALL" --user >/dev/null 2>&1
check "--user is idempotent" "[ \"\$(grep -c 'trellis:begin pull-requests' '$H/.claude/CLAUDE.md')\" = 1 ]"
CWD="$(mktemp -d)"
(cd "$CWD" && HOME="$H" TRELLIS_ROOT="$FX" bash "$INSTALL" --user >/dev/null 2>&1)
check "--user alone does not touch the current directory" "[ -z \"\$(ls -A '$CWD')\" ]"

# ---- the real packs install cleanly too (smoke test)
new_target
OUT="$(bash "$INSTALL" "$T" --stack react --stack dotnet 2>&1)"; rc=$?
check "real packs: install succeeds" "[ $rc = 0 ]"
check "real packs: report contract lands in CLAUDE.md" "! [ -d '$ROOT/packs/core/fragments' ] || grep -q 'trellis:begin report-contract' '$T/CLAUDE.md'"
OUT="$(bash "$INSTALL" "$T" --stack react --stack dotnet 2>&1)"
check "real packs: second run is a no-op" "! printf '%s' \"\$OUT\" | grep -qE '^  (added|updated) '"

rm -rf "$FX"
echo "  $PASS passed, $FAIL failed"
[ "$FAIL" = 0 ]
