// Course Dynamics > Takers vs Non-Takers: the analysed course's takers against
// the students of its classification who never took it, read against the
// college's other courses (R/modules/course-cohort.R over
// build_course_cohort_context()).
//
// Asserts the tab opens on data-read defaults, a run renders the lead
// paragraph and the four tables, and the definition record reaches the page.
//
//   node tests/e2e/course-cohort.test.mjs

import { launch, connect, setInput, runAndWait, openSubTab,
         waitForIdle, requireIds, waitForSelector } from './lib.mjs';

const COURSE = process.env.CEDAR_COURSE_X || 'HIST 1110';
const fail = [];
const ok = (cond, msg) => { if (!cond) fail.push(msg); console.log(`${cond ? 'ok  ' : 'FAIL'} ${msg}`); };

const { browser, page, jsErrors } = await launch({ width: 1500, height: 1100 });

try {
  await connect(page, { tab: 'course-dynamics' });

  await requireIds(page, ['cr_campus', 'cr_course', 'cr_generate_button']);
  await setInput(page, 'cr_campus', ['ABQ', 'EA']);
  await setInput(page, 'cr_course', COURSE);
  await runAndWait(page, 'cr_generate_button');
  console.log(`course loaded: ${COURSE}`);

  await openSubTab(page, 'Takers vs Non-Takers', { timeout: 300000 });
  await requireIds(page, ['cr_cohort-classification', 'cr_cohort-college', 'cr_cohort-terms',
                          'cr_cohort-min_n', 'cr_cohort-run']);

  // The controls open filled from the data, never empty.
  const defaults = await page.evaluate(() => ({
    classification: $('#cr_cohort-classification')[0].selectize.getValue(),
    college: $('#cr_cohort-college')[0].selectize.getValue(),
    terms: $('#cr_cohort-terms')[0].selectize.getValue(),
  }));
  ok(defaults.classification.length > 0, `classification defaults to the takers' (${defaults.classification})`);
  ok(defaults.college.length > 0, `benchmark college defaults to the course's (${defaults.college})`);
  ok(defaults.terms.length > 0, `terms default to the recent regular terms (${defaults.terms.length})`);

  const definition = await page.evaluate(() => {
    const note = document.querySelector('[data-definition-id="course-cohort-effect"]');
    return note ? note.getAttribute('data-definition-version') : null;
  });
  ok(definition === '1.0.0', 'the tab carries the course-cohort-effect definition v1');

  // The synthetic institution is small: a guard of one lets every group show.
  await setInput(page, 'cr_cohort-min_n', 1);
  await runAndWait(page, 'cr_cohort-run', { timeout: 300000 });
  await waitForSelector(page, '#cr_cohort-groups_table .rt-table', { timeout: 60000 });
  await waitForIdle(page);

  const body = await page.evaluate(() => document.getElementById('cr_cohort-results').innerText);
  ok(/returned the next regular term|no gap to read|nothing to compare/.test(body),
     'the result opens with the lead paragraph');
  ok(/Passed it/.test(body) && /Never took it/.test(body),
     'the groups table names the three groups');
  ok(/describe who takes the course before they describe the course/.test(body),
     'the page says the gaps are descriptive');
  for (const id of ['cr_cohort-population_table', 'cr_cohort-groups_table',
                    'cr_cohort-benchmark_table', 'cr_cohort-courses_table']) {
    const rendered = await page.evaluate((i) => !!document.querySelector(`#${i} .rt-table`), id);
    ok(rendered, `${id} rendered`);
  }

  const shot = '/tmp/cedar-course-cohort.png';
  await page.screenshot({ path: shot, fullPage: true });
  console.log(`screenshot: ${shot}`);

  ok(jsErrors.length === 0, `no uncaught JS errors (${jsErrors.join(' ; ') || 'none'})`);
} finally {
  await browser.close();
}

console.log(fail.length ? `\n${fail.length} FAILED` : '\nall passed');
process.exit(fail.length ? 1 : 0);
