#!/usr/bin/env bash
# Verifies the React presets against real tools: oxlint must report the intended rules and prettier
# must accept the preset. Needs network access for npm; skipped when npm is missing or offline.
set -u
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
PASS=0
FAIL=0
expect_exit() { # expect_exit <expected> <name> <command...>
  local want="$1" name="$2"; shift 2
  OUT="$("$@" 2>&1)"; local got=$?
  if [ "$got" = "$want" ]; then PASS=$((PASS + 1)); echo "  ok   $name"
  else FAIL=$((FAIL + 1)); echo "  FAIL $name (exit $got, wanted $want)"; fi
}
expect_output() {
  if printf '%s' "$OUT" | grep -qE -- "$2"; then PASS=$((PASS + 1)); echo "  ok   $1"
  else FAIL=$((FAIL + 1)); echo "  FAIL $1 (output lacks /$2/)"; fi
}
expect_no_output() {
  if printf '%s' "$OUT" | grep -qE -- "$2"; then FAIL=$((FAIL + 1)); echo "  FAIL $1 (output contains /$2/)"
  else PASS=$((PASS + 1)); echo "  ok   $1"; fi
}
summary() { echo "  $PASS passed, $FAIL failed"; [ "$FAIL" = 0 ]; }

echo "react-presets"

if ! command -v npm >/dev/null 2>&1; then echo "  skip (npm not found)"; exit 0; fi

WORK="$(mktemp -d)"
P="$ROOT/packs/stacks/react/presets"
cd "$WORK" || exit 1
printf '{"name":"fixture","private":true}\n' > package.json
if ! npm install --silent --no-audit --no-fund oxlint@^1 prettier@^3 >/dev/null 2>&1; then
  echo "  skip (npm install failed, offline?)"; exit 0
fi

cp "$P/oxlintrc.json" .oxlintrc.json
cp "$P/prettierrc.json" .prettierrc.json
mkdir -p src/modules/a src/modules/b src/components src/utils src/layouts

cat > src/modules/a/Bad.tsx <<'TSX'
import { Other } from '@/modules/b/Other';
export const Bad = (x: any) => {
  localStorage.setItem('t', 'v');
  console.log(x == 1, Other);
  return <div dangerouslySetInnerHTML={{ __html: x }} />;
};
TSX
cat > src/components/Leak.tsx <<'TSX'
import { Other } from '@/modules/b/Other';
export const Leak = () => <p>{String(Other)}</p>;
TSX
cat > src/layouts/Shell.tsx <<'TSX'
import { Other } from '@/modules/b/Other';
export const Shell = () => <p>{String(Other)}</p>;
TSX
cat > src/utils/arrow.ts <<'TS'
export const helper = () => 1;
TS
cat > src/modules/a/Good.tsx <<'TSX'
export const Good = () => <p>fine</p>;
TSX

OUT="$(./node_modules/.bin/oxlint --format=unix . 2>&1)"
expect_output "config is accepted and reports findings" "Found|Error|error"
expect_output "any is rejected" "no-explicit-any"
expect_output "localStorage is rejected" "no-restricted-globals"
expect_output "== is rejected" "eqeqeq"
expect_output "dangerouslySetInnerHTML is rejected" "no-danger"
expect_output "module-to-module import is rejected" "src/modules/a/Bad.tsx.*no-restricted-imports|Bad.tsx.*no-restricted-imports"
expect_output "base importing a module is rejected" "src/components/Leak.tsx.*no-restricted-imports|Leak.tsx.*no-restricted-imports"
expect_output "layout importing a module is rejected" "Shell.tsx.*no-restricted-imports"
expect_output "arrow in utils is rejected" "func-style"
expect_no_output "clean component has no findings" "Good.tsx"

printf 'const a = {x:1,}\n' > src/fmt.ts
OUT="$(./node_modules/.bin/prettier --check src/fmt.ts 2>&1)"; rc=$?
if [ "$rc" != 0 ]; then PASS=$((PASS + 1)); echo "  ok   prettier flags unformatted code"; else FAIL=$((FAIL + 1)); echo "  FAIL prettier flags unformatted code"; fi
./node_modules/.bin/prettier --write src/fmt.ts >/dev/null 2>&1
expect_exit 0 "prettier accepts the formatted result" ./node_modules/.bin/prettier --check src/fmt.ts

cp "$P/playwright.config.ts" ./playwright.config.ts
if grep -q "process.env.PW_CHROMIUM_PATH" playwright.config.ts && grep -q "testMatch: '\*\*/\*.e2e.ts'" playwright.config.ts; then
  PASS=$((PASS + 1)); echo "  ok   playwright preset keeps e2e naming and env switches"
else FAIL=$((FAIL + 1)); echo "  FAIL playwright preset content"; fi

rm -rf "$WORK"
summary
