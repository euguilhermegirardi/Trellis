#!/usr/bin/env node
// Builds the log line for the living plan document from git (branch commits plus staged files).
//
//   node scripts/living-doc-log.mjs                  prints the line only
//   node scripts/living-doc-log.mjs --write          inserts or updates this branch's line at the top of the log
//   node scripts/living-doc-log.mjs --write --base feat/previous   stacked branch: only what is its own
//
// One line per branch: running again replaces the previous line and keeps a hand-written "Pending: ..." tail.
// Configuration: .trellis/living-doc.json
//   plan        path of the plan document (required)
//   logHeading  heading that opens the log (default "## Log")
//   baseBranch  default base for the diff (default "main")
//   timezone    IANA zone for the date (default: the machine's)
//   areas       [{ "match": "^src/modules/([^/]+)/", "label": "modules/$1" }, ...] first match wins; else "other"
import { execFileSync } from 'node:child_process';
import { readFileSync, writeFileSync } from 'node:fs';
import { join } from 'node:path';

const git = (...args) => {
  try {
    return execFileSync('git', args, { encoding: 'utf8', stdio: ['ignore', 'pipe', 'ignore'] }).trim();
  } catch {
    return '';
  }
};

const root = git('rev-parse', '--show-toplevel');
if (!root) {
  console.error('Not inside a git repository.');
  process.exit(1);
}
let config;
try {
  config = JSON.parse(readFileSync(join(root, '.trellis', 'living-doc.json'), 'utf8'));
} catch {
  console.error('Missing or invalid .trellis/living-doc.json');
  process.exit(1);
}
if (!config.plan) {
  console.error('.trellis/living-doc.json needs a "plan" path.');
  process.exit(1);
}

const heading = `${config.logHeading ?? '## Log'}\n`;
const branch = git('rev-parse', '--abbrev-ref', 'HEAD');
const baseFlag = process.argv.indexOf('--base');
const baseName = config.baseBranch ?? 'main';
const base =
  (baseFlag > -1 && process.argv[baseFlag + 1]) ||
  [`origin/${baseName}`, baseName].find((ref) => git('rev-parse', '--verify', '--quiet', ref)) ||
  'HEAD';

const commits = git('log', '--no-merges', '--format=%s', `${base}..HEAD`).split('\n').filter(Boolean).reverse();
const files = new Set([
  ...git('diff', '--name-only', `${base}...HEAD`).split('\n'),
  ...git('diff', '--cached', '--name-only').split('\n'),
]);
files.delete(config.plan);
files.delete('');

const areas = (config.areas ?? []).map((a) => ({ re: new RegExp(a.match), label: a.label }));
const areaOf = (file) => {
  for (const { re, label } of areas) {
    const m = file.match(re);
    if (m) return label.replace(/\$(\d)/g, (_, n) => m[Number(n)] ?? '');
  }
  return 'other';
};
const perArea = new Map();
for (const file of files) perArea.set(areaOf(file), (perArea.get(areaOf(file)) ?? 0) + 1);

const today = new Intl.DateTimeFormat('en-CA', config.timezone ? { timeZone: config.timezone } : {}).format(new Date());
const summary = commits.length ? commits.join('; ') : '(no commits yet; describe what is staged)';
const areaText = [...perArea].map(([name, n]) => `${name} (${n})`).join(', ');
const line = `- ${today} — \`${branch}\`: ${summary}.${areaText ? ` Files: ${areaText}.` : ''}`;

console.log(line);

if (process.argv.includes('--write')) {
  const path = join(root, config.plan);
  const content = readFileSync(path, 'utf8');
  const at = content.indexOf(heading);
  if (at === -1) {
    console.error(`Heading "${heading.trim()}" not found in ${config.plan}.`);
    process.exit(1);
  }
  const end = at + heading.length;
  const head = content.slice(0, end);
  const lines = content.slice(end).replace(/^\n/, '').split('\n');

  // An entry starts with "- " and may continue on indented lines.
  const entries = [];
  for (const l of lines) {
    if (l.startsWith('- ') || entries.length === 0) entries.push([l]);
    else entries.at(-1).push(l);
  }

  const mark = `\`${branch}\`:`;
  const idx = entries.findIndex((e) => e[0].startsWith('- ') && e[0].includes(mark));
  let next = line;
  if (idx !== -1) {
    const old = entries[idx].map((l) => l.trim()).join(' ');
    const pending = old.match(/Pending:.*$/)?.[0];
    if (pending && !next.includes('Pending:')) next = `${next} ${pending}`;
    entries.splice(idx, 1);
  }
  entries.unshift([next]);

  writeFileSync(path, `${head}\n${entries.map((e) => e.join('\n')).join('\n')}`);
  console.error(idx === -1 ? 'Line inserted at the top of the log.' : "This branch's line was updated and moved to the top.");
}
