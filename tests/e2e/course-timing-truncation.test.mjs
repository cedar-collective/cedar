// Pathways > Course Timing: the left-truncation guard on the credit axes.
//
// A credit band claims to say where a student was in their career. The running
// total behind it starts at zero on the student's first term IN THE DATA, so a
// student already enrolled when the window opened begins mid-career reading
// zero. get_course_timing() now drops those students and reports how many.
//
// This asserts the three things a user actually sees: Classification is the
// default axis (it needs no such restriction), a credit axis states its
// exclusions on the face of the chart, and the classification axis states none.
//
//   node tests/e2e/course-timing-truncation.test.mjs

import {
  launch, connect, setInput, click, waitForSelector, sleep,
} from './lib.mjs';

const DEPT = process.env.CEDAR_DEPT || 'HIST';
const fail = [];
const ok = (cond, msg) => { if (!cond) fail.push(msg); console.log(`${cond ? 'ok  ' : 'FAIL'} ${msg}`); };

const text = (page, id) => page.evaluate((i) => {
  const el = document.getElementById(i);
  return el ? el.innerText.trim() : '';
}, id);

const { browser, page, jsErrors } = await launch({ width: 1500, height: 1100 });

try {
  await connect(page, { tab: 'pathways' });

  // ── Build a population ────────────────────────────────────────────────────
  await setInput(page, 'pathways-population-population_type', 'dept');
  await setInput(page, 'pathways-population-dept_code', DEPT);
  await setInput(page, 'pathways-population-population_scope', 'all');
  await setInput(page, 'pathways-population-student_level', 'Undergraduate');
  await click(page, 'pathways-population-build_btn');

  await page.waitForFunction(() => {
    const t = (document.getElementById('pathways-pop_audit_ui') || {}).innerText || '';
    return (t.match(/[\d,]{2,}/g) || []).length >= 4;
  }, { timeout: 180000, polling: 500 });
  console.log('population built');

  // ── Course Timing sub-tab ─────────────────────────────────────────────────
  await page.evaluate(() => {
    const root = document.getElementById('pathways-analysis_tabs');
    const link = [...root.querySelectorAll('a.nav-link, a[data-toggle="tab"], a')]
      .find((a) => /Course Timing/i.test(a.textContent));
    if (!link) throw new Error('no Course Timing sub-tab');
    link.click();
  });
  await sleep(2500);

  // Classification is the only axis that reads a genuine per-term Banner value,
  // so it is the one that works for the whole population and must load first.
  const defaultAxis = await page.evaluate(() =>
    (document.getElementById('pathways-ct_x_axis') || {}).value);
  ok(defaultAxis === 'classification',
     `default x-axis is Classification (saw: ${defaultAxis})`);

  await click(page, 'pathways-ct_run');
  await waitForSelector(page, '#pathways-ct_meta', { timeout: 180000 });
  await page.waitForFunction(() => {
    const t = (document.getElementById('pathways-ct_meta') || {}).innerText || '';
    return /students analyzed/i.test(t);
  }, { timeout: 180000, polling: 500 });

  const classMeta = await text(page, 'pathways-ct_meta');
  console.log('\n--- classification axis ---\n' + classMeta + '\n');
  ok(!/excluded/i.test(classMeta),
     'classification axis excludes nobody for truncation');

  // ── Switch to a credit axis ───────────────────────────────────────────────
  // The scope bar keeps the previous run's sentence while the new one computes,
  // so waiting for "students analyzed" is satisfied instantly by stale text.
  // Wait for the string to actually change.
  await setInput(page, 'pathways-ct_x_axis', 'overall_credit_band');
  await click(page, 'pathways-ct_run');
  await page.waitForFunction((prev) => {
    const t = ((document.getElementById('pathways-ct_meta') || {}).innerText || '').trim();
    return t.length > 0 && t !== prev;
  }, { timeout: 180000, polling: 500 }, classMeta);

  const creditMeta = await text(page, 'pathways-ct_meta');
  console.log('--- total-credits axis ---\n' + creditMeta + '\n');

  // A department population drawn from the whole window will always contain
  // students who predate it, so the count must be > 0 and must be stated. If
  // this ever legitimately hits zero the sentence is correctly absent, so the
  // assertion is on "states it OR the plot covers everyone", not on the number.
  const excluded = /(\d[\d,]*) students? excluded/i.exec(creditMeta);
  ok(excluded !== null,
     `credit axis states its exclusions (${excluded ? excluded[1] : 'no such sentence'})`);
  ok(/record begins at the edge of the data/i.test(creditMeta),
     'the exclusion sentence explains why, not just how many');
  ok(/Classification axis/i.test(creditMeta),
     'and points at the axis that includes those students');

  const shot = `/tmp/cedar-course-timing-truncation-${DEPT}.png`;
  await page.screenshot({ path: shot, fullPage: false });
  console.log(`screenshot: ${shot}`);

  ok(jsErrors.length === 0, `no uncaught JS errors (${jsErrors.join(' ; ') || 'none'})`);
} finally {
  await browser.close();
}

console.log(fail.length ? `\n${fail.length} FAILED` : '\nall passed');
process.exit(fail.length ? 1 : 0);
