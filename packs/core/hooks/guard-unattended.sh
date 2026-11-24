#!/usr/bin/env bash
# PreToolUse (Bash) hook: guard for unattended runs. Acts only when TRELLIS_UNATTENDED=1 (set by the
# script that launches the unattended session); in normal sessions it never interferes.
# Exit 2 blocks the command and shows the reason to the agent. Fails closed: if the guard cannot
# run or cannot parse its input while unattended, the command is blocked.
[ "${TRELLIS_UNATTENDED:-0}" = "1" ] || exit 0
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if ! command -v python3 >/dev/null 2>&1; then
  echo "Blocked in unattended mode: python3 is required by the guard and was not found." >&2
  exit 2
fi
exec python3 "$here/guard_unattended.py"
