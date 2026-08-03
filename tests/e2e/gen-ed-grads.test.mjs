// Dept Trends > Gen Ed > "Gen Ed Taken by This Department's Graduates".
//
// Asserts the section actually renders against real data: the sampling strip,
// the timing heatmap image, and the course table. A green R suite says the
// numbers are right; only this says they reach the page.
//
//   node tests/e2e/gen-ed-grads.test.mjs

import fs from 'node:fs';
import {
  launch, connect, setInput, waitForSelector,
  readReactable, colIndex, queryActive, sleep,
} from './lib.mjs';

const DEPT = process.env.CEDAR_DEPT || 'ENGL';
const fail = [];
const ok = (cond, msg) => { if (!cond) fail.push(msg); console.log(`${cond ? 'ok  ' : 'FAIL'} ${msg}`); };

// Sub-tab links are looked up inside the Dept Trends tabset by id. A global
// text search finds sub-tabs on other, hidden tabs too.
const clickSubTabIn = (page, tabsetId, label) => page.evaluate((id, text) => {
  const root = document.getElementById(id);
  if (!root) throw new Error(`no tabset #${id}`);
  const link = [...root.querySelectorAll('a.nav-link, a[data-toggle="tab"], a')]
    .find((a) => a.textContent.trim() === text);
  if (!link) throw new Error(`no sub-tab "${text}" in #${id}`);
  link.click();
}, tabsetId, label);

const { browser, page, jsErrors } = await launch({ width: 1500, height: 1100 });

try {
  await connect(page, { tab: 'dept-trends' });

  await setInput(page, 'dept_trends-campus', ['ABQ', 'EA']);
  await setInput(page, 'dept_trends-dept', DEPT);

  // The profile builds every tab payload on department change; this is the
  // heavy step, not the sub-tab click. Wait for the tabset itself to appear.
  await waitForSelector(page, '#dept_trends-tabs', { timeout: 120000 });
  await sleep(3000);

  await clickSubTabIn(page, 'dept_trends-tabs', 'Gen Ed');
  await sleep(15000);

  // dashboard_section() titles are h2; dashboard_subsection() titles are lower.
  const headings = await queryActive(page, 'h2, h3, h4, h5');
  ok(headings.some((h) => /Gen Ed Taken by This Department/i.test(h)),
     `section heading present (saw: ${headings.slice(0, 12).join(' | ')})`);

  // ── Sampling strip ────────────────────────────────────────────────────────
  await waitForSelector(page, '#dept_trends-gen_ed-grad_ge_meta');
  const meta = await page.evaluate(() =>
    document.getElementById('dept_trends-gen_ed-grad_ge_meta').innerText.trim());
  console.log('\n--- meta strip ---\n' + meta + '\n------------------\n');

  ok(/graduates counted/i.test(meta) || /No graduates of this department/i.test(meta),
     'meta strip renders a cohort count or an explicit empty-state');
  if (/graduates counted/i.test(meta)) {
    ok(/of [\d,]+ undergraduate degrees awarded/i.test(meta),
       'counted total is shown against the awarded total, not alone');
    ok(/graduates not readable/i.test(meta),
       'cohort strip states how many graduates are excluded');
    // The all-Gen-Ed averages deliberately live in the all-Gen-Ed section now,
    // not beside the cohort definition — two differently-scoped student counts
    // sitting side by side is what made them easy to conflate.
    const allMeta = await page.evaluate(() =>
      (document.getElementById('dept_trends-gen_ed-grad_ge_all_meta') || {}).innerText || '');
    ok(/avg gen ed courses per graduate/i.test(allMeta),
       'average gen ed courses is shown in the all-Gen-Ed section');
    ok(!/avg gen ed courses per graduate/i.test(meta),
       'and is NOT duplicated in the cohort strip');
    ok(/Data window/i.test(meta), 'data window and exclusions are stated');
  }

  // ── Heatmap ───────────────────────────────────────────────────────────────
  const plot = await page.evaluate(() => {
    const el = document.getElementById('dept_trends-gen_ed-grad_ge_plot');
    if (!el) return null;
    const img = el.querySelector('img');
    return { h: el.getBoundingClientRect().height, src: img ? img.src.slice(0, 30) : null };
  });
  ok(plot !== null, 'timing heatmap output exists');
  if (plot) {
    ok(plot.src && plot.src.startsWith('data:image'), `heatmap rendered an image (${plot.src})`);
    ok(plot.h > 200, `heatmap has a real height (${Math.round(plot.h)}px)`);
  }

  // ── Course table ──────────────────────────────────────────────────────────
  const tbl = await readReactable(page, 'dept_trends-gen_ed-grad_ge_table');
  if (tbl.error) {
    ok(false, `course table: ${tbl.error}`);
  } else {
    console.log('table headers:', tbl.headers.join(' | '));
    console.log('first rows:', JSON.stringify(tbl.rows.slice(0, 3)));
    ok(colIndex(tbl.headers, '% of Grads') >= 0, 'table has a "% of Grads" column');
    ok(colIndex(tbl.headers, 'Gen Ed Area') >= 0, 'table has a "Gen Ed Area" column');
    ok(tbl.rows.length > 0, `table has rows (${tbl.rows.length})`);

    const pct = colIndex(tbl.headers, '% of Grads');
    const vals = tbl.rows.map((r) => parseFloat(String(r[pct]).replace('%', '')))
      .filter((v) => !Number.isNaN(v));
    ok(vals.length > 0 && vals.every((v) => v > 0 && v <= 100),
       `percentages are in range (${vals.slice(0, 5).join(', ')})`);
    // Sorted by n_students desc, so the first row must not be the smallest.
    ok(vals[0] >= vals[vals.length - 1], 'table is ordered by uptake, highest first');
  }

  // ── Own-unit scope ────────────────────────────────────────────────────────
  ok(headings.some((h) => /This Unit's Own Gen Ed/i.test(h)),
     'own-unit section heading present');

  const ownMeta = await page.evaluate(() => {
    const el = document.getElementById('dept_trends-gen_ed-grad_ge_own_meta');
    return el ? el.innerText.trim() : null;
  });
  console.log('\n--- own-unit cards ---\n' + ownMeta + '\n----------------------\n');
  ok(ownMeta && ownMeta.length > 0, 'own-unit card row renders');

  const ownTbl = await readReactable(page, 'dept_trends-gen_ed-grad_ge_own_table');
  if (ownTbl.error) {
    ok(false, `own-unit table: ${ownTbl.error}`);
  } else {
    const taughtBy = colIndex(ownTbl.headers, 'Taught By');
    const depts = [...new Set(ownTbl.rows.map((r) => r[taughtBy]))];
    ok(ownTbl.rows.length > 0, `own-unit table has rows (${ownTbl.rows.length})`);
    ok(depts.length === 1 && depts[0] === DEPT,
       `own-unit table holds only ${DEPT}-taught courses (saw: ${depts.join(', ')})`);
    ok(ownTbl.rows.length <= tbl.rows.length + 100,
       'own-unit table is a subset, not a superset');

    // Every own-unit course must appear in the all-Gen-Ed table with the same
    // "% of Grads" — the two are one calculation shown at two scopes.
    const course = colIndex(ownTbl.headers, 'Course');
    const pctO = colIndex(ownTbl.headers, '% of Grads');
    const pctA = colIndex(tbl.headers, '% of Grads');
    const allByCourse = Object.fromEntries(
      tbl.rows.map((r) => [r[colIndex(tbl.headers, 'Course')], r[pctA]]));
    const first = ownTbl.rows[0];
    const match = allByCourse[first[course]];
    ok(match === undefined || match === first[pctO],
       `${first[course]} reads the same in both tables (${first[pctO]} vs ${match})`);
  }

  // Either a heatmap or an explicit note, never an empty slot. A department can
  // legitimately have no drawable own-unit map: Biology's own Gen Ed courses
  // peak at 1-2% of its own graduates, because Biology majors take the majors
  // sequence and its Gen Ed serves everyone else. That must read as an
  // explanation, not as a chart that failed to load.
  const ownSlot = await page.evaluate(() => {
    const el = document.getElementById('dept_trends-gen_ed-grad_ge_own_plot_ui');
    if (!el) return null;
    return {
      hasImg: !!el.querySelector('img'),
      note: (el.innerText || '').trim().slice(0, 120),
    };
  });
  ok(ownSlot !== null, 'own-unit heatmap slot exists');
  ok(ownSlot && (ownSlot.hasImg || ownSlot.note.length > 0),
     `own-unit map is a chart or an explanation (${ownSlot && ownSlot.hasImg ? 'chart' : `note: ${ownSlot && ownSlot.note}`})`);

  // ── Axis toggle ───────────────────────────────────────────────────────────
  const axisNote = () => page.evaluate(() => {
    const el = document.getElementById('dept_trends-gen_ed-grad_ge_axis_note');
    return el ? el.innerText.trim() : '';
  });
  const slotFilled = (id) => page.evaluate((i) => {
    const el = document.getElementById(i);
    if (!el) return false;
    return !!el.querySelector('img') || (el.innerText || '').trim().length > 0;
  }, id);

  const defaultAxis = await page.evaluate(() =>
    (document.querySelector('input[name="dept_trends-gen_ed-grad_ge_axis"]:checked') || {}).value);
  ok(defaultAxis === 'relative_term',
     `default axis is terms enrolled (saw: ${defaultAxis})`);
  ok(/Terms enrolled/i.test(await axisNote()),
     'axis note describes the terms-enrolled axis');

  await setInput(page, 'dept_trends-gen_ed-grad_ge_axis', 'unm_credit_band');
  await sleep(14000);

  const creditNote = await axisNote();
  ok(/UNM credits/i.test(creditNote) && /not counted/i.test(creditNote),
     'switching axes swaps the caveat to the credit-band one');

  ok(await slotFilled('dept_trends-gen_ed-grad_ge_plot_ui'),
     'all-Gen-Ed map still resolves on the credit axis');
  ok(await slotFilled('dept_trends-gen_ed-grad_ge_own_plot_ui'),
     'own-unit map still resolves on the credit axis');

  // The uptake table is axis-independent — switching the map must not move it.
  const tblAfter = await readReactable(page, 'dept_trends-gen_ed-grad_ge_own_table');
  ok(JSON.stringify(tblAfter.rows) === JSON.stringify(ownTbl.rows),
     'course table is unchanged by the axis switch');

  await setInput(page, 'dept_trends-gen_ed-grad_ge_axis', 'relative_term');
  await sleep(14000);
  ok(/Terms enrolled/i.test(await axisNote()), 'axis switches back');

  // The heatmap lives far down the page; scroll it into view before shooting.
  await page.evaluate(() => {
    const el = document.getElementById('dept_trends-gen_ed-grad_ge_meta');
    if (el) el.scrollIntoView({ block: 'start' });
  });
  await sleep(1200);
  const shot = `/tmp/cedar-gen-ed-grads-${DEPT}.png`;
  await page.screenshot({ path: shot, fullPage: false });
  console.log(`\nscreenshot: ${shot}`);

  ok(jsErrors.length === 0, `no uncaught JS errors (${jsErrors.join(' ; ') || 'none'})`);
} finally {
  await browser.close();
}

console.log(fail.length ? `\n${fail.length} FAILED` : '\nall passed');
process.exit(fail.length ? 1 : 0);
