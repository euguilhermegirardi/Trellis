#!/usr/bin/env bash
# Runs every tests/**/*.test.sh and reports a summary.
set -u
cd "$(dirname "${BASH_SOURCE[0]}")"
fail=0
for t in $(find . -name '*.test.sh' | sort); do
  echo "== $t"
  if ! bash "$t"; then fail=1; fi
done
[ "$fail" = 0 ] && echo "ALL TESTS PASSED" || echo "SOME TESTS FAILED"
exit "$fail"
