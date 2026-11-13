// Course Dynamics > Downstream > Later Course: of the analysed course's
// students, how many took a later course within the window, when, and how they
// did in it (R/modules/later-course.R over build_later_course()).
//
// Asserts the tab opens first under Downstream with its definition and an
// empty state, the picker offers the later course with its share, a run renders
// the two rates with the counts behind them, the per-term chart, sentences and
// table read one term type at a time, and nothing that names an instructor is
// on the page while the instructor gate is closed.
//
//   node tests/e2e/later-course.test.mjs

import { launch, connect, setInput, runAndWait, openSubTab, waitFor,
         waitForIdle, requireIds, waitForSelector, readReactable } from './lib.mjs';

const COURSE_X = process.env.CEDAR_COURSE_X || 'HIST 1110';
const COURSE_Y = process.env.CEDAR_COURSE_Y || 'HIST 1120';
const fail = [];
const ok = (cond, msg) => { if (!cond) fail.push(msg); console.log(`${cond ? 'ok  ' : 'FAIL'} ${msg}`); };

const { browser, page, jsErrors } = await launch({ width: 1500, height: 1100 });

try {
  // Load the course through a deep link, so the app's own restore fills the
  // course picker and runs the report. Setting cr_course directly loses the
  // value on the first session after a restart: the picker's server-side
  // initialisation lands afterwards and clears it, and Downstream, which reads
  // the picker, then shows its empty state.
  await connect(page, {
    tab: 'course-dynamics',
    search: ['tab=course-dynamics', 'autorun=true', 'campus=ABQ,EA',
             `course=${encodeURIComponent(COURSE_X)}`].join('&'),
  });
  const restored = await waitFor(page, (course) =>
    document.getElementById('cr_course')?.selectize?.getValue() === course,
  { timeout: 60000, args: [COURSE_X] });
  if (!restored) throw new Error(`the deep link did not restore ${COURSE_X} into the course picker`);
  await waitForSelector(page, '#cr_overview_metrics .cedar-snapshot-table', { timeout: 300000 });
  await waitForIdle(page, { timeout: 300000 });
  console.log(`course loaded: ${COURSE_X}`);

  // Later Course is the first view under Downstream: opening Downstream shows it.
  // The two views are themselves rendered by cr_impact_downstream_ui, so wait
  // for their links before clicking one. The picker starts with nothing chosen
  // and so has no text: wait for the control, not for words in it.
  await openSubTab(page, 'Downstream', { timeout: 300000 });
  await waitForSelector(page, '#cr_impact_downstream_ui .nav-link', { timeout: 120000 });
  await openSubTab(page, 'Later Course', { timeout: 300000 });
  await waitForSelector(page, '#cr_later-picker .selectize-control', { timeout: 120000, nonEmpty: false });
  await requireIds(page, ['cr_later-course_y', 'cr_later-window_terms', 'cr_later-min_n',
                          'cr_later-run', 'cr_later-results']);

  const definition = await page.evaluate(() => {
    const note = document.querySelector('[data-definition-id="downstream-outcomes"]');
    return note ? note.getAttribute('data-definition-version') : null;
  });
  ok(definition === '1.0.0', 'the tab carries the downstream-outcomes definition v1');

  const before = await page.evaluate(() => document.getElementById('cr_later-results').innerText);
  ok(/Choose a later course/.test(before), 'before a run the results say what to do');

  // The picker lists each later course with how many students took it and the
  // share that is of those who could have.
  const offered = await page.evaluate(() => {
    const s = $('#cr_later-course_y')[0].selectize;
    return Object.values(s.options).map((o) => ({ value: o.value, label: o.label }));
  });
  const choice = offered.find((o) => o.value === COURSE_Y);
  ok(offered.length > 0, `the picker offers later courses (${offered.length})`);
  ok(!!choice, `the picker offers ${COURSE_Y}`);
  ok(!!choice && /— [\d,]+ students \(\d+\.\d%\)$/.test(choice.label),
     `its label carries the count and the share (${choice ? choice.label : 'not offered'})`);

  await setInput(page, 'cr_later-course_y', [COURSE_Y]);
  await setInput(page, 'cr_later-min_n', 5);
  await runAndWait(page, 'cr_later-run', { timeout: 300000 });
  await waitForSelector(page, '#cr_later-term_table .rt-table', { timeout: 120000 });
  await waitForIdle(page);

  const body = await page.evaluate(() => document.getElementById('cr_later-results').innerText);
  const esc = (s) => s.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
  const X = esc(COURSE_X);
  const Y = esc(COURSE_Y);

  // The number up front, and its arithmetic open right below it.
  ok(new RegExp(`took ${Y} within 3 regular terms`, 'i').test(body),
     'the result opens with the share who took the later course within the window');
  ok(new RegExp(`of them passed ${Y}`, 'i').test(body),
     'and the pass rate among those who took it');
  ok(/[\d,]+ of [\d,]+ who could have/.test(body) && /[\d,]+ of [\d,]+ with a grade/.test(body),
     'each rate is shown with its count and denominator');
  const steps = await page.evaluate(() =>
    [...document.querySelectorAll('#cr_later-results .stat-row table tr')].map((tr) => tr.innerText.trim()));
  ok(steps.length >= 4, `the counts behind the rates are open under them (${steps.length} rows)`);
  ok(!(await page.evaluate(() => !!document.querySelector('#cr_later-results details'))),
     'none of the result is collapsed');

  for (const heading of ['Over Time', `Results in ${COURSE_Y} by Grade in ${COURSE_X}`,
                         `When They Took ${COURSE_Y}`, `By Instructor in ${COURSE_X}`,
                         'Course Order']) {
    ok(new RegExp(esc(heading), 'i').test(body), `section "${heading}" is on the page`);
  }

  // Over Time reads one term type at a time: one box ticked, and every row of
  // the table and every sentence under the chart is of that term type.
  const ticked = await page.evaluate(() =>
    [...document.querySelectorAll('#cr_later-term_type input:checked')].map((i) => i.value));
  ok(ticked.length === 1, `Over Time opens on one term type (${ticked.join(', ')})`);
  const terms = await readReactable(page, 'cr_later-term_table', { limit: 200 });
  const termCol = terms.headers.findIndex((h) => new RegExp(`^Term of ${X}$`, 'i').test(h));
  ok(termCol >= 0, `the per-term table has a "Term of ${COURSE_X}" column (${terms.headers.join(' | ')})`);
  ok(terms.rows.length > 0 &&
     terms.rows.every((r) => r[termCol].toLowerCase().startsWith(ticked[0])),
     `every row is a ${ticked[0]} term (${terms.rows.length} rows)`);
  ok(await page.evaluate(() => !!document.querySelector(
       '#cr_later-trend_plot.js-plotly-plot svg.main-svg, #cr_later-trend_plot .js-plotly-plot svg.main-svg')),
     'the per-term chart rendered');
  const sentences = await page.evaluate(() =>
    [...document.querySelectorAll('#cr_later-trend_text li')].map((li) => li.innerText.trim()));
  ok(sentences.length > 0, `the chart is read in sentences under it (${sentences.length})`);
  ok(sentences.every((s) => /an upward trend|a downward trend|no trend beyond that|a trend is read from 3 or more/.test(s)),
     'every sentence ends in a verdict, or says there are too few terms for one');
  ok(sentences.every((s) => new RegExp(`, ${ticked[0]} terms of ${X}`, 'i').test(s)),
     `every sentence is about ${ticked[0]} terms`);

  // Ticking every term type adds the other terms' rows.
  const types = await page.evaluate(() =>
    [...document.querySelectorAll('#cr_later-term_type input')].map((i) => i.value));
  if (types.length > 1) {
    await setInput(page, 'cr_later-term_type', types);
    await waitForIdle(page);
    const all = await readReactable(page, 'cr_later-term_table', { limit: 200 });
    const seen = new Set(all.rows.map((r) => r[termCol].split(' ')[0].toLowerCase()));
    ok(seen.size > 1, `with every term type ticked the table holds ${[...seen].join(', ')} terms`);
  } else {
    console.log(`skip the course has one term type (${types.join(', ')})`);
  }

  // Instructor names sit behind the gate: a session that has not unlocked it
  // sees the prompt where the table would be, and no instructor column.
  await requireIds(page, ['cr_later-instructor_gate-gate']);
  const gate = await page.evaluate(() =>
    document.getElementById('cr_later-instructor_gate-gate').innerText);
  ok(/Access (Restricted|Unavailable)/.test(gate), 'the instructor section shows the gate');
  const headers = await page.evaluate(() =>
    [...document.querySelectorAll('#cr_later-results .rt-th')].map((h) => h.innerText.trim()));
  ok(!headers.some((h) => /^Instructor in/i.test(h)),
     'no table has an instructor column without the instructor password');
  ok(!/Did the Two Largest Instructor Groups Start Alike/i.test(body),
     'the instructor balance check is not rendered either');

  const shot = '/tmp/cedar-later-course.png';
  await page.screenshot({ path: shot, fullPage: true });
  console.log(`screenshot: ${shot}`);

  ok(jsErrors.length === 0, `no uncaught JS errors (${jsErrors.join(' ; ') || 'none'})`);
} finally {
  await browser.close();
}

console.log(fail.length ? `\n${fail.length} FAILED` : '\nall passed');
process.exit(fail.length ? 1 : 0);
