#!/usr/bin/env bash
# Entry point for the Trellis installer. See scripts/install.py for what it does.
set -euo pipefail
command -v python3 >/dev/null 2>&1 || { echo "error: python3 is required" >&2; exit 2; }
exec python3 "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/install.py" "$@"
