#!/usr/bin/env bash
# Scans the staged diff (added lines only) for secrets and refuses forbidden files.
#
# Configuration, all optional, read from the repository root:
#   .trellis/secret-patterns.txt     extra patterns, one per line: name|extended-regex
#   .trellis/forbidden-files.txt     extra forbidden path globs, one per line (matched with `case`)
#   .trellis/secret-allow-files.txt  path globs the scan skips (fixtures, docs)
# A line containing the marker `trellis:allow-secret` is ignored.
# The report never prints the matched value, only file, line and rule name.
set -euo pipefail

root="$(git rev-parse --show-toplevel)"
cd "$root"
conf=".trellis"
status=0

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

read_list() { [ -f "$1" ] && grep -vE '^[[:space:]]*(#|$)' "$1" || true; }

# ---------- 1. Forbidden files ----------
forbidden_default='.env
.env.*
*.pem
*.key
*.p12
*.pfx
*id_rsa*
*id_ed25519*
*.kdbx'
allowed_default='.env.example
.env.sample
.env.template
*.example
*.sample'

staged_files="$(git diff --cached --name-only --diff-filter=ACMR)"
blocked_files=""
while IFS= read -r f; do
  [ -z "$f" ] && continue
  base="${f##*/}"
  ok=0
  while IFS= read -r a; do
    [ -z "$a" ] && continue
    # shellcheck disable=SC2254
    case "$base" in $a) ok=1 ;; esac
  done <<< "$allowed_default"
  [ "$ok" = 1 ] && continue
  while IFS= read -r g; do
    [ -z "$g" ] && continue
    # shellcheck disable=SC2254
    case "$base" in $g) blocked_files="$blocked_files$f"$'\n'; break ;; esac
    # shellcheck disable=SC2254
    case "$f" in $g) blocked_files="$blocked_files$f"$'\n'; break ;; esac
  done <<< "$forbidden_default
$(read_list "$conf/forbidden-files.txt")"
done <<< "$staged_files"

if [ -n "$blocked_files" ]; then
  {
    echo "Commit blocked: forbidden files are staged:"
    printf '%s' "$blocked_files" | sed 's/^/  - /'
    echo "Unstage them (git restore --staged <file>) and add them to .gitignore."
  } >&2
  status=1
fi

# ---------- 2. Secret patterns in added lines ----------
git diff --cached -U0 --no-color --diff-filter=ACMR | awk -v meta="$tmp/meta" -v content="$tmp/content" '
  /^\+\+\+ b\// { file = substr($0, 7); next }
  /^\+\+\+ /    { file = ""; next }
  /^@@ /        { match($0, /\+[0-9]+/); line = substr($0, RSTART + 1, RLENGTH - 1) + 0; next }
  /^\+/         { if (file != "") { print file ":" line > meta; print substr($0, 2) > content } line++ }
' || true
[ -f "$tmp/content" ] || { : > "$tmp/content"; : > "$tmp/meta"; }

patterns="private key|-----BEGIN ([A-Z]+ )?PRIVATE KEY-----
AWS access key id|AKIA[0-9A-Z]{16}
GitHub token|gh[pousr]_[A-Za-z0-9]{36,}
GitHub fine-grained token|github_pat_[A-Za-z0-9_]{20,}
Slack token|xox[baprs]-[A-Za-z0-9-]{10,}
API key (sk- style)|sk-[A-Za-z0-9_-]{20,}
bcrypt hash|\\\$2[aby]\\\$[0-9]{2}\\\$[./A-Za-z0-9]{50,}
bearer token|[Bb]earer [A-Za-z0-9._~+/=-]{24,}
JSON web token|eyJ[A-Za-z0-9_-]{10,}\\.eyJ[A-Za-z0-9_-]{10,}
credentials in URL|[a-z][a-z0-9+.-]*://[^/[:space:]:@]+:[^/[:space:]@]{3,}@
quoted secret assignment|(secret|passw(or)?d|pwd|api[_-]?key|access[_-]?key|private[_-]?key|auth[_-]?token|client[_-]?secret|token)[A-Za-z0-9_]*[\"']?[[:space:]]*[:=][[:space:]]*[\"'][A-Za-z0-9/+_.=@!#%^*-]{8,}[\"']
env-style secret assignment|^[A-Z0-9_]*(SECRET|PASSWORD|TOKEN|API_KEY|ACCESS_KEY|PRIVATE_KEY)[A-Z0-9_]*=[^[:space:]\$<{\"'][^[:space:]]{7,}\$
$(read_list "$conf/secret-patterns.txt")"

placeholder='\$\{|\$[A-Za-z_]|process\.env|os\.environ|getenv|<[A-Za-z_-]+>|your[-_ ]|changeme|example|placeholder|xxxx|\*\*\*\*|redacted'

allow_files="$(read_list "$conf/secret-allow-files.txt")"

found=""
while IFS= read -r p; do
  [ -z "$p" ] && continue
  name="${p%%|*}"
  regex="${p#*|}"
  [ "$name" = "$p" ] && continue
  while IFS=: read -r n _; do
    [ -z "$n" ] && continue
    text="$(sed -n "${n}p" "$tmp/content")"
    case "$text" in *trellis:allow-secret*) continue ;; esac
    if printf '%s' "$text" | grep -qiE -- "$placeholder"; then
      case "$name" in "quoted secret assignment"|"env-style secret assignment"|"credentials in URL") continue ;; esac
    fi
    loc="$(sed -n "${n}p" "$tmp/meta")"
    skip=0
    while IFS= read -r g; do
      [ -z "$g" ] && continue
      # shellcheck disable=SC2254
      case "${loc%:*}" in $g) skip=1 ;; esac
    done <<< "$allow_files"
    [ "$skip" = 1 ] && continue
    found="$found  - $loc  [$name]"$'\n'
  done < <(grep -nE -i -- "$regex" "$tmp/content" 2>/dev/null || true)
done <<< "$patterns"

if [ -n "$found" ]; then
  {
    echo "Commit blocked: possible secrets in the staged changes (values are not shown):"
    printf '%s' "$found" | sort -u
    echo "Remove the value and use an environment variable or an untracked config file."
    echo "False positive in a fixture? Add the path to .trellis/secret-allow-files.txt"
    echo "or put the marker 'trellis:allow-secret' on that line."
  } >&2
  status=1
fi

exit "$status"
