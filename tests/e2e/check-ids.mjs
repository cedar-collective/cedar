// Static check: every element/input id an e2e test drives must exist in the app.
//
//   node tests/e2e/check-ids.mjs
//
// WHY THIS EXISTS
//
// Four ids in reports-smoke.test.mjs had rotted before anyone noticed:
// `cr_enrollment_plot` and `dashboard_credit_hours` did not exist at all, and
// `download_ch_outside_lower` / `sch_outside_full_lower_table` had been
// consolidated into singular versions. Two of them sat inside a `.some()` check,
// so they passed while testing nothing; the other two failed as *timeouts*, which
// read like two broken Core Surfaces rather than two stale strings.
//
// A renamed output should fail here, in seconds, with the new name suggested —
// not thirty minutes later as an ambiguous browser timeout.
//
// WHAT IT CANNOT SEE
//
// Ids built at runtime (paste0/glue in R, template literals in JS) are skipped.
// The check is deliberately conservative: it only reads ids out of the helper
// call sites where a literal string is required, so a miss here means a real
// stale selector, not a parsing artifact.

import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const here = path.dirname(fileURLToPath(import.meta.url));
const repo = path.resolve(here, '../..');

// ── Collect ids referenced by the tests ──────────────────────────────────────
// Only literal-string call sites. Anything dynamic is skipped rather than
// guessed at.
const PATTERNS = [
  /\bsetInput\(\s*page\s*,\s*'([^']+)'/g,
  /\bclick\(\s*page\s*,\s*'([^']+)'/g,
  /\brunAndWait\(\s*page\s*,\s*'([^']+)'/g,
  /\breadReactable\(\s*page\s*,\s*'([^']+)'/g,
  /\bgetElementById\(\s*'([^']+)'\s*\)/g,
  /\bid:\s*'([^']+)'/g,
  /\brequireIds\(\s*page\s*,\s*\[([^\]]+)\]/g,   // handled specially below
  /waitForSelector\(\s*page\s*,\s*'#([^'\s]+)'/g,
];

// Call sites only would miss ids handed to a test's own local helper — which is
// how `dept_trends-download_ch_outside_lower` survived: it lived in an array
// passed to waitForDownloadLinks(), a function this file has never heard of.
// So also sweep every quoted string that is SHAPED like a Shiny id.
//
// The shape rule is what keeps this quiet: Shiny ids in CEDAR are snake_case,
// optionally prefixed by dash-joined module namespaces. Requiring an underscore
// excludes tab slugs ('course-dynamics'), CSS classes ('text-muted-sm') and
// dplyr's join strings ('many-to-many'); requiring all-lowercase-no-spaces
// excludes prose and headings.
const ID_SHAPED = /^[a-z][a-z0-9_]*(?:-[a-z][a-z0-9_]*)*$/;
const looksLikeId = (s) => s.includes('_') && s.length >= 6 && ID_SHAPED.test(s);

const testFiles = fs.readdirSync(here)
  .filter((f) => f.endsWith('.test.mjs'))
  .map((f) => path.join(here, f));

// A test may legitimately name a string that is NOT an id — most often to assert
// it is absent from the page, which is exactly what the course-impact covariate
// test does with the banned frozen fields. Declare those with a file-level
// pragma so the sweep stays strict everywhere else:
//
//   // check-ids-ignore: inst_gpa, overall_credits_earned
const ignoredFor = (src) => new Set(
  [...src.matchAll(/\/\/\s*check-ids-ignore:\s*(.+)/g)]
    .flatMap((m) => m[1].split(',').map((s) => s.trim()))
    .filter(Boolean));

const refs = new Map();   // id -> Set(file)
for (const file of testFiles) {
  const src = fs.readFileSync(file, 'utf8');
  const base = path.basename(file);
  const ignored = ignoredFor(src);
  for (const re of PATTERNS) {
    for (const m of src.matchAll(re)) {
      // requireIds takes an array literal; split it.
      const chunk = m[1];
      const ids = chunk.includes(',') && chunk.includes("'")
        ? [...chunk.matchAll(/'([^']+)'/g)].map((x) => x[1])
        : [chunk];
      for (const id of ids) {
        if (!id || /[${}`]/.test(id)) continue;   // dynamic — skip
        if (ignored.has(id)) continue;
        if (!refs.has(id)) refs.set(id, new Set());
        refs.get(id).add(base);
      }
    }
  }

  for (const m of src.matchAll(/'([^'\n]+)'/g)) {
    const s = m[1];
    if (!looksLikeId(s) || ignored.has(s)) continue;
    if (!refs.has(s)) refs.set(s, new Set());
    refs.get(s).add(base);
  }
}

// ── Collect ids the app can actually produce ─────────────────────────────────
const sources = [];
const walk = (dir) => {
  for (const e of fs.readdirSync(dir, { withFileTypes: true })) {
    if (e.name === 'renv' || e.name === 'node_modules' || e.name === '.git') continue;
    const p = path.join(dir, e.name);
    if (e.isDirectory()) walk(p);
    else if (/\.(R|Rmd)$/i.test(e.name)) sources.push(p);
  }
};
walk(path.join(repo, 'R'));
for (const f of ['ui.R', 'server.R', 'global.R']) {
  const p = path.join(repo, f);
  if (fs.existsSync(p)) sources.push(p);
}
const appSrc = sources.map((f) => fs.readFileSync(f, 'utf8')).join('\n');

// An id in the app is written either bare ("foo") or namespaced by a module, in
// which case the test drives "module-foo" but the source only ever says "foo".
const known = new Set();
for (const m of appSrc.matchAll(/["']([A-Za-z][A-Za-z0-9_.]{2,})["']/g)) known.add(m[1]);
// Inputs and outputs are usually referenced unquoted in R — `input$wl_navigate`,
// `output$cr_enrollment_table` — and only ever appear as a quoted string in the
// UI half, which some modules build with ns() indirection. Reading the accessor
// form too is what keeps a real id from being reported as stale.
for (const m of appSrc.matchAll(/\b(?:input|output)\$([A-Za-z][A-Za-z0-9_.]*)/g)) known.add(m[1]);

const exists = (id) => {
  if (known.has(id)) return true;
  const bare = id.includes('-') ? id.slice(id.indexOf('-') + 1) : null;
  if (bare && known.has(bare)) return true;
  // Nested modules: "pathways-population-dept_code" -> "dept_code"
  const last = id.split('-').pop();
  return known.has(last);
};

const suggest = (id) => {
  const stem = id.split('-').pop().split('_').slice(0, 2).join('_');
  if (stem.length < 4) return [];
  return [...known].filter((k) => k.includes(stem) && k !== id).slice(0, 4);
};

// ── Report ───────────────────────────────────────────────────────────────────
const missing = [...refs.entries()]
  .filter(([id]) => !exists(id))
  .sort((a, b) => a[0].localeCompare(b[0]));

console.log(`checked ${refs.size} ids referenced across ${testFiles.length} e2e test files`);

if (missing.length === 0) {
  console.log('all referenced ids exist in the app source');
  process.exit(0);
}

console.log(`\n${missing.length} id(s) referenced by tests but absent from the app:\n`);
for (const [id, files] of missing) {
  const near = suggest(id);
  console.log(`  ${id}`);
  console.log(`      used in: ${[...files].join(', ')}`);
  if (near.length) console.log(`      did you mean: ${near.join(', ')}`);
}
console.log('\nA stale selector fails as a timeout at runtime, which looks like a broken feature.');
process.exit(1);
