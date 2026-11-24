#!/usr/bin/env bash
# Installs the Trellis git hooks into a project.
#
# Usage: scripts/install-hooks.sh [--dry-run] [target-dir]
#   target-dir  a git repository (default: current directory)
#
# Copies packs/core/hooks/git/* to <target>/.githooks/ and points core.hooksPath at it (local config,
# never global). Safe to run again: files are overwritten with the packaged version.
set -euo pipefail

dry=0
if [ "${1:-}" = "--dry-run" ]; then dry=1; shift; fi
target="${1:-.}"

src="$(cd "$(dirname "${BASH_SOURCE[0]}")/../packs/core/hooks/git" && pwd)"

if ! git -C "$target" rev-parse --show-toplevel >/dev/null 2>&1; then
  echo "error: '$target' is not a git repository" >&2
  exit 2
fi
root="$(git -C "$target" rev-parse --show-toplevel)"

echo "Installing Trellis hooks into $root/.githooks"
for f in "$src"/*; do
  name="$(basename "$f")"
  echo "  $name"
  if [ "$dry" = 0 ]; then
    mkdir -p "$root/.githooks"
    cp "$f" "$root/.githooks/$name"
    chmod +x "$root/.githooks/$name"
  fi
done

if [ "$dry" = 0 ]; then
  git -C "$root" config core.hooksPath .githooks
  echo "core.hooksPath=.githooks"
else
  echo "(dry run: nothing written)"
fi
