#!/usr/bin/env bash
# Blocks a commit that changes product state without the living plan document in the same commit.
# Configuration: .trellis/living-doc.json (no file = no check). See templates/trellis/living-doc.json.
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
command -v python3 >/dev/null 2>&1 || { echo "living-doc check needs python3" >&2; exit 1; }
exec python3 "$here/living_doc_check.py"
