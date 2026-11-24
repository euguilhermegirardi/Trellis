#!/usr/bin/env node
// Captures a front-end screen with the API simulated, for visual review against reference designs.
//
// One command, no chaining (this is what unattended runs allow), from the project root:
//   node scripts/capture-screen.mjs --route /orders --role Admin --mocks e2e/mocks/orders.json --out captures/orders
//     -> captures/orders.png (light 1440), captures/orders-dark.png, captures/orders-1280.png
//   --only-one   only the capture named by --out, with --theme (light|dark) and --width
//   --strict     exit with code 3 when the screen called an endpoint that has no mock
//
// If the app is not running at --base, the script starts it, waits, and stops it at the end.
// Mocks file: { "GET /items": <body>, "GET /items/9": { "status": 500, "body": { ... } } }
//   Images served by the API: "GET /files/f1/content": { "image": true }  -> a synthetic PNG.
//   A key may use * for one path segment: "GET /files/*/content".
//
// Configuration, optional, in .trellis/capture.json (flags override it):
//   frontendDir  folder with package.json and Playwright (default ".")
//   devCommand   array, command that starts the app (default ["npm", "run", "dev"]); the port flag is appended
//   base, api    app and API URLs (defaults http://localhost:5173 and http://localhost:5285)
//   sessionKey   sessionStorage key the app reads its session from (default "app.session")
//   session      object stored under that key; the string "$ROLE" is replaced by --role
//   widths       [wide, narrow] pixel widths (default [1440, 1280])
//
// Browser: Chromium. Variables: PW_CHANNEL=chrome|msedge, PW_CHROMIUM_PATH=<executable>,
// PLAYWRIGHT_MODULE=<module to import>. Synthetic data only.
import { createRequire } from 'node:module';
import { existsSync, mkdirSync, readFileSync } from 'node:fs';
import { dirname, join, resolve } from 'node:path';
import { spawn } from 'node:child_process';

const flags = Object.fromEntries(
  process.argv.slice(2).reduce((acc, cur, i, arr) => {
    if (!cur.startsWith('--')) return acc;
    const next = arr[i + 1];
    return [...acc, [cur.slice(2), next === undefined || next.startsWith('--') ? 'true' : next]];
  }, []),
);

const configPath = flags.config ?? '.trellis/capture.json';
const config = existsSync(configPath) ? JSON.parse(readFileSync(configPath, 'utf8')) : {};

const frontendDir = resolve(flags['frontend-dir'] ?? config.frontendDir ?? '.');
const base = (flags.base ?? config.base ?? 'http://localhost:5173').replace(/\/$/, '');
const api = (flags.api ?? config.api ?? 'http://localhost:5285').replace(/\/$/, '');
const route = flags.route ?? '/';
const role = flags.role; // no role = signed out
const outBase = (flags.out ?? 'screen').replace(/\.png$/, '');
const mocks = flags.mocks ? JSON.parse(readFileSync(flags.mocks, 'utf8')) : {};
const [wide, narrow] = config.widths ?? [1440, 1280];
const sessionKey = config.sessionKey ?? 'app.session';
const sessionTemplate = config.session ?? {
  token: 'synthetic-token',
  userId: '00000000-0000-0000-0000-000000000001',
  name: 'Synthetic $ROLE',
  email: 'test@example.com',
  role: '$ROLE',
};

const variants = flags['only-one']
  ? [{ file: `${outBase}.png`, theme: flags.theme ?? 'light', width: Number(flags.width ?? wide) }]
  : [
      { file: `${outBase}.png`, theme: 'light', width: wide },
      { file: `${outBase}-dark.png`, theme: 'dark', width: wide },
      { file: `${outBase}-${narrow}.png`, theme: 'light', width: narrow },
    ];

const isUp = async () => {
  try {
    const res = await fetch(base, { signal: AbortSignal.timeout(2000) });
    return res.ok;
  } catch {
    return false;
  }
};

let dev = null;
if (!(await isUp())) {
  const command = config.devCommand ?? ['npm', 'run', 'dev'];
  console.log(`App is not running at ${base}; starting ${command.join(' ')} in ${frontendDir} ...`);
  const port = new URL(base).port || '5173';
  const extra = command[0] === 'npm' ? ['--', '--port', port, '--strictPort'] : [];
  dev = spawn(command[0], [...command.slice(1), ...extra], {
    cwd: frontendDir,
    stdio: 'ignore',
    detached: true,
    env: { ...process.env, PORT: port },
  });
  let up = false;
  for (let i = 0; i < 60 && !up; i++) {
    await new Promise((r) => setTimeout(r, 1000));
    up = await isUp();
  }
  if (!up) {
    try {
      process.kill(-dev.pid);
    } catch {}
    console.error('Could not start the app within 60 seconds.');
    process.exit(2);
  }
}
const stopDev = () => {
  if (dev) {
    try {
      process.kill(-dev.pid);
    } catch {}
  }
};

const require = createRequire(join(frontendDir, 'package.json'));
const { chromium } = require(process.env.PLAYWRIGHT_MODULE ?? '@playwright/test');
const launchOptions = {};
if (process.env.PW_CHANNEL) launchOptions.channel = process.env.PW_CHANNEL;
if (process.env.PW_CHROMIUM_PATH) launchOptions.executablePath = process.env.PW_CHROMIUM_PATH;

const unmocked = new Set();
// 16x12 blue-grey PNG used wherever a mock says { "image": true }.
const SYNTHETIC_PNG = Buffer.from(
  'iVBORw0KGgoAAAANSUhEUgAAABAAAAAMCAIAAADkharWAAAAFUlEQVR42mPYsO8oSYhhVMOoBuwIAPxoplBOylVDAAAAAElFTkSuQmCC',
  'base64',
);
const findMock = (key) => {
  if (mocks[key] !== undefined) return mocks[key];
  const wildcard = Object.keys(mocks).find(
    (k) =>
      k.includes('*') &&
      new RegExp(
        `^${k
          .split('*')
          .map((p) => p.replace(/[.+?^${}()|[\]\\]/g, '\\$&'))
          .join('[^/]+')}$`,
      ).test(key),
  );
  return wildcard === undefined ? undefined : mocks[wildcard];
};
const withRole = (value) =>
  JSON.parse(JSON.stringify(value).replaceAll('$ROLE', role ?? ''));

try {
  const browser = await chromium.launch(launchOptions);
  for (const v of variants) {
    const page = await browser.newPage({ viewport: { width: v.width, height: 900 }, colorScheme: v.theme });
    await page.route(`${api}/**`, (request) => {
      const url = new URL(request.request().url());
      const key = `${request.request().method()} ${url.pathname}`;
      const mock = findMock(key);
      if (mock && typeof mock === 'object' && mock.image === true) {
        return request.fulfill({ status: 200, contentType: 'image/png', body: SYNTHETIC_PNG });
      }
      if (mock === undefined) {
        unmocked.add(key);
        return request.fulfill({ status: 501, json: { message: `no mock: ${key}` } });
      }
      const hasStatus = mock && typeof mock === 'object' && 'status' in mock && 'body' in mock;
      return request.fulfill({ status: hasStatus ? mock.status : 200, json: hasStatus ? mock.body : mock });
    });
    if (role) {
      const session = {
        ...withRole(sessionTemplate),
        expiresAt: new Date(Date.now() + 3600e3).toISOString(),
      };
      await page.addInitScript(([k, s]) => sessionStorage.setItem(k, s), [sessionKey, JSON.stringify(session)]);
    }
    await page.goto(base + route, { waitUntil: 'networkidle' });
    await page.waitForTimeout(300);
    mkdirSync(dirname(v.file) || '.', { recursive: true });
    await page.screenshot({ path: v.file, fullPage: true });
    await page.close();
    console.log(`Capture saved to ${v.file} (${v.theme}, ${v.width}px)`);
  }
  await browser.close();
} finally {
  stopDev();
}
if (unmocked.size) {
  console.warn('Calls without a mock (answered 501):', [...unmocked].join(', '));
  if (flags.strict) process.exit(3);
}
