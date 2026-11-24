#!/usr/bin/env bash
# Runs packs/stacks/react/scripts/capture-screen.mjs against a tiny fixture app with real Playwright and a
# real Chromium. Skipped when npm, node or a browser is missing, or when npm cannot install Playwright.
set -u
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SCRIPT="$ROOT/packs/stacks/react/scripts/capture-screen.mjs"
PASS=0
FAIL=0
ok() { PASS=$((PASS + 1)); echo "  ok   $1"; }
bad() { FAIL=$((FAIL + 1)); echo "  FAIL $1"; }

echo "capture-screen"
command -v node >/dev/null 2>&1 && command -v npm >/dev/null 2>&1 || { echo "  skip (node/npm not found)"; exit 0; }

BROWSER="${PW_CHROMIUM_PATH:-}"
if [ -z "$BROWSER" ] && [ -z "${PW_CHANNEL:-}" ]; then
  for c in /opt/pw-browsers/chromium-*/chrome-linux64/chrome /usr/bin/chromium /usr/bin/chromium-browser /usr/bin/google-chrome; do
    [ -x "$c" ] && { BROWSER="$c"; break; }
  done
fi
[ -n "$BROWSER" ] || [ -n "${PW_CHANNEL:-}" ] || { echo "  skip (no Chromium found; set PW_CHROMIUM_PATH or PW_CHANNEL)"; exit 0; }

W="$(mktemp -d)"
cd "$W" || exit 1
printf '{"name":"fixture","private":true}\n' > package.json
if ! PLAYWRIGHT_SKIP_BROWSER_DOWNLOAD=1 npm install --silent --no-audit --no-fund @playwright/test@^1 >/dev/null 2>&1; then
  echo "  skip (npm install failed, offline?)"; exit 0
fi

PORT=$((41000 + RANDOM % 2000))
API="http://localhost:$((PORT + 1))"
cat > app.js <<JS
const http = require('http');
const fs = require('fs');
const html = \`<!doctype html><meta charset=utf-8><style>body{background:#fff;color:#000}
@media (prefers-color-scheme: dark){body{background:#000;color:#fff}}</style>
<h1>Items</h1><ul id=l></ul><p id=who></p><img id=img width=16 height=12>
<script>
const API = '$API';
const s = sessionStorage.getItem('fixture.session');
const role = s ? JSON.parse(s).role : 'signed-out';
document.getElementById('who').textContent = role;
Promise.all([
  fetch(API + '/items').then(r => r.json()),
  fetch(API + '/items/9').then(r => r.status),
  fetch(API + '/missing').then(r => r.status),
  new Promise(res => { const i = document.getElementById('img'); i.onload = () => res(true); i.onerror = () => res(false); i.src = API + '/files/f1/content'; }),
]).then(([items, status9, statusMissing, img]) => {
  document.getElementById('l').innerHTML = items.map(x => '<li>' + x + '</li>').join('');
  navigator.sendBeacon('/report', JSON.stringify({ role, items: items.length, status9, statusMissing, img }));
});
</script>\`;
http.createServer((req, res) => {
  if (req.method === 'POST' && req.url === '/report') {
    let b = ''; req.on('data', d => b += d); req.on('end', () => { fs.appendFileSync('report.log', b + '\n'); res.end('ok'); }); return;
  }
  res.setHeader('content-type', 'text/html'); res.end(html);
}).listen(process.env.PORT || $PORT);
JS
mkdir -p .trellis
cat > .trellis/capture.json <<JSON
{ "devCommand": ["node", "app.js"], "base": "http://localhost:$PORT", "api": "$API", "sessionKey": "fixture.session" }
JSON
cat > mocks.json <<'JSON'
{ "GET /items": ["a", "b", "c"], "GET /items/9": { "status": 500, "body": { "requestId": "r1", "message": "boom" } }, "GET /files/*/content": { "image": true } }
JSON

export PW_CHROMIUM_PATH="$BROWSER"
OUT="$(node "$SCRIPT" --route / --role Admin --mocks mocks.json --out shots/home 2>&1)"; rc=$?
[ "$rc" = 0 ] && ok "exits 0 with all three captures" || { bad "exit code $rc"; echo "$OUT" | sed 's/^/       /'; }

for f in shots/home.png shots/home-dark.png shots/home-1280.png; do
  if [ -f "$f" ] && [ "$(head -c 4 "$f" | od -An -tx1 | tr -d ' \n')" = "89504e47" ]; then ok "$f is a PNG"; else bad "$f missing or not a PNG"; fi
done
if [ -f shots/home.png ] && [ -f shots/home-dark.png ] && ! cmp -s shots/home.png shots/home-dark.png; then ok "dark capture differs from light"; else bad "dark capture equals light"; fi
case "$OUT" in *"Calls without a mock"*"/missing"*) ok "reports the call that had no mock" ;; *) bad "unmocked call not reported: $OUT" ;; esac
[ -f report.log ] && R="$(tail -1 report.log)" || R=""
case "$R" in *'"role":"Admin"'*) ok "session role reached the app" ;; *) bad "role not injected: $R" ;; esac
case "$R" in *'"items":3'*) ok "mocked body served" ;; *) bad "mock body missing: $R" ;; esac
case "$R" in *'"status9":500'*) ok "mocked status served" ;; *) bad "mock status missing: $R" ;; esac
case "$R" in *'"statusMissing":501'*) ok "unmocked call answers 501" ;; *) bad "501 missing: $R" ;; esac
case "$R" in *'"img":true'*) ok "wildcard image mock served" ;; *) bad "image mock missing: $R" ;; esac

rm -f report.log
OUT="$(node "$SCRIPT" --route / --mocks mocks.json --out shots/one --only-one --theme dark --width 1000 --strict 2>&1)"; rc=$?
[ "$rc" = 3 ] && ok "--strict exits 3 on an unmocked call" || bad "--strict exit code $rc"
[ -f shots/one.png ] && [ ! -f shots/one-dark.png ] && ok "--only-one writes a single capture" || bad "--only-one wrote the wrong files"
R="$(tail -1 report.log 2>/dev/null)"
case "$R" in *'"role":"signed-out"'*) ok "no --role means signed out" ;; *) bad "signed-out expected: $R" ;; esac

if pgrep -f "node app.js" >/dev/null 2>&1; then bad "the started app was not stopped"; else ok "the started app is stopped at the end"; fi

rm -rf "$W"
echo "  $PASS passed, $FAIL failed"
[ "$FAIL" = 0 ]
