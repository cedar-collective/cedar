// Course Dynamics > Downstream > Prepared for It (Course Sequence in code):
// reconstructed matching covariates.
//
// build_comparison() used to match treatment and control on `inst_gpa` and the
// `*_credits_earned/attempted` columns. Those are stamped as of the data pull
// and repeat a student's final totals on every historical row — identical across
// a student's whole history for 67.8% of students with 5+ terms — so matching on
// them means matching on where each student ended up, which for an outcome
// measured after the covariate term is partly the outcome itself.
//
// They are now rebuilt at each student's covariate term. This asserts the new
// covariates reach the page and the banned ones do not.
//
//   node tests/e2e/course-impact-covariates.test.mjs

// These are asserted ABSENT from the page, so they are not selectors:
// check-ids-ignore: inst_gpa, overall_credits_earned, inst_credits_attempted
// The sequence view's own picker and the later-course run button, gone since
// the shared choice; asserted absent:
// check-ids-ignore: cr_impact_seq_course_y, cr_later-run

// The pickers' ids are built per slot (paste0("course_y_", slot), later-course.R):
// check-ids-ignore: cr_later-course_y_next, cr_later-course_y_seq

import { launch, connect, setInput, runAndWait, openSubTab,
         waitForIdle, requireIds, waitForSelector } from './lib.mjs';

const COURSE_X = process.env.CEDAR_COURSE_X || 'HIST 1110';
const COURSE_Y = process.env.CEDAR_COURSE_Y || 'HIST 1120';
const fail = [];
const ok = (cond, msg) => { if (!cond) fail.push(msg); console.log(`${cond ? 'ok  ' : 'FAIL'} ${msg}`); };

const { browser, page, jsErrors } = await launch({ width: 1500, height: 1100 });

try {
  await connect(page, { tab: 'course-dynamics' });

  await requireIds(page, ['cr_campus', 'cr_course', 'cr_generate_button']);
  await setInput(page, 'cr_campus', ['ABQ', 'EA']);
  await setInput(page, 'cr_course', COURSE_X);
  await runAndWait(page, 'cr_generate_button');
  console.log(`course loaded: ${COURSE_X}`);

  // ── Downstream > Prepared for It ─────────────────────────────────────────
  // openSubTab waits for the pane to be visible and for its outputs to settle:
  // innerText on a still-hidden pane returns '' — indistinguishable from a
  // tab that rendered nothing. The later-course choice is the one Next
  // Courses shares; the subtab runs on it when opened.
  await openSubTab(page, 'Downstream', { timeout: 300000 });
  await openSubTab(page, 'Next Courses', { timeout: 300000 });
  await waitForSelector(page, '#cr_later-picker_next .selectize-control', { timeout: 120000, nonEmpty: false });
  await requireIds(page, ['cr_later-course_y_next', 'cr_impact_seq_update', 'cr_impact_seq_min_n']);
  ok(!(await page.evaluate(() => [...document.querySelectorAll('.nav-link')].some((a) => a.textContent.trim() === 'Prepared for It'))),
     'the comparison is a section of Next Courses, not a subtab of its own');
  ok(!(await page.evaluate(() => !!document.getElementById('cr_later-course_y_seq'))),
     'and the tab has one later-course picker');
  ok(!(await page.evaluate(() => !!document.getElementById('cr_impact_seq_course_y'))),
     'the comparison has no picker of its own');
  ok(!(await page.evaluate(() => !!document.getElementById('cr_later-run'))),
     'and no Show Results button: it runs when the subtab opens');

  await setInput(page, 'cr_later-course_y_next', [COURSE_Y]);
  await waitForSelector(page, '#cr_impact_sequence_results .compare-bars', { timeout: 300000 });
  await waitForIdle(page, { timeout: 300000 });

  // textContent, not innerText: the counting notes and the per-term table
  // sit in collapsed panels, and innerText leaves collapsed content out.
  const body = await page.evaluate(() =>
    document.getElementById('cr_impact_sequence_ui').textContent);

  const definition = await page.evaluate(() => {
    const note = document.querySelector(
      '#cr_impact_sequence_ui [data-definition-id="course-sequence"]'
    );
    return note ? {
      version: note.getAttribute('data-definition-version'),
      text: note.innerText
    } : null;
  });

  ok(definition?.version === '3.0.0',
     'Course Sequence uses definition v2');
  // The result opens with the two rates and their counts, then the balance verdict.
  ok(/did not pass .* of the time \(\d[\d,]* of \d[\d,]*\)/.test(body),
     'the result opens with both groups\' rates and their counts');
  ok(/things measured|measured beforehand|known about the students beforehand/i.test(body),
     'the opening sentence carries the balance verdict');
  // The answer is drawn: both groups' DFW rates as bars, with their counts.
  ok(await page.evaluate(() => document.querySelectorAll(
       '#cr_impact_sequence_results .compare-bars .meter-bar').length === 2),
     'the two rates are drawn as a pair of bars');
  // Downstream's order: the answer, Over Time, the breakdowns, How Far to Trust It.
  const order = ['First, Against Not', 'Over Time', 'Who Is in the Comparison Group', 'How Far to Trust It']
    .map((h) => body.indexOf(h));
  ok(order.every((i) => i >= 0) && order.every((i, k) => k === 0 || i > order[k - 1]),
     `the sections run in Downstream's order (${order.join(', ')})`);

  // Over Time is one row per term, of the ticked term types: never a calendar
  // year, which mixes a Fall's students with a Spring's. The table is in a
  // collapsed panel: Shiny renders it once the panel opens.
  await page.evaluate(() => {
    document.querySelectorAll('#cr_impact_sequence_results details.cedar-info-panel').forEach((d) => { d.open = true; });
  });
  await waitForSelector(page, '#cr_impact_sequence_over_time .rt-table', { timeout: 60000 });
  const overTime = await page.evaluate(() => ({
    ticked: [...document.querySelectorAll('#cr_impact_seq_term_type input:checked')].map((i) => i.value),
    terms: [...document.querySelectorAll('#cr_impact_sequence_over_time .rt-tbody .rt-tr')]
      .map((r) => r.querySelector('.rt-td')?.innerText.trim()),
  }));
  ok(overTime.ticked.length === 1, `Over Time opens on one term type (${overTime.ticked.join(', ')})`);
  ok(overTime.terms.length > 0 &&
     overTime.terms.every((t) => t.toLowerCase().startsWith(overTime.ticked[0])),
     `every Over Time row is a ${overTime.ticked[0]} term (${overTime.terms.join(', ')})`);
  ok(await page.evaluate(() => !!document.querySelector('#cr_impact_sequence_trend_plot .main-svg')),
     'Over Time draws the two rates');
  const sentences = await page.evaluate(() =>
    [...document.querySelectorAll('#cr_impact_sequence_trend_text li')].map((li) => li.innerText.trim()));
  ok(sentences.length > 0 &&
     sentences.every((t) => /an upward trend|a downward trend|no trend beyond that|a trend is read from 3 or more/.test(t)),
     `the chart is read in sentences that end in a verdict (${sentences.length})`);

  // One balance table: a row per measured characteristic, the bands defined.
  ok(/under 0\.10 is a small difference/i.test(body) && /0\.10 to 0\.25 one to review/i.test(body) &&
     /above 0\.25 a substantial one/i.test(body),
     'the page defines the three observed-difference bands');
  ok(!/Groups appear well-balanced/i.test(body),
     'the old all-values-at-or-below-0.25 success claim is absent');
  ok(!/Group Profile/.test(body), 'the group profile is part of the balance table, not a second table');

  // ── The new covariates are present ────────────────────────────────────────
  ok(/GPA entering/i.test(body), 'the balance table lists the reconstructed GPA entering');
  ok(/credits entering/i.test(body), 'the balance table lists a reconstructed credit covariate');

  // ── Institution GPA: shown, but only as description ───────────────────────
  // It is the best-covered summary of overall academic strength, so it belongs
  // in the table. It is measured at the data pull — after the outcome — so it
  // is a described row with no difference, never a balanced covariate.
  ok(/Current UNM GPA/i.test(body),
     'the balance table shows the registrar current UNM GPA alongside the rebuilt one');
  ok(/description, not as evidence/i.test(body),
     'the page says plainly that the current GPA is description, not balance evidence');

  // ── The raw frozen field names are gone ───────────────────────────────────
  // These are the exact strings the old build put on the page.
  for (const banned of ['inst_gpa', 'overall_credits_earned',
                        'inst_credits_attempted']) {
    ok(!body.includes(banned), `"${banned}" no longer appears on the page`);
  }

  // The disclosure has to say the figures are reconstructed and why — otherwise a
  // reader assumes the registrar's own cumulative fields are behind them.
  ok(/entering/i.test(body) && /rebuilt from the per-term class list/i.test(body),
     'the page explains that the matched covariates are rebuilt from the class list');
  ok(/as of the data pull/i.test(body),
     'and dates the registrar figure to the pull, not to the comparison term');

  const shot = '/tmp/cedar-course-impact-covariates.png';
  await page.screenshot({ path: shot, fullPage: false });
  console.log(`screenshot: ${shot}`);

  ok(jsErrors.length === 0, `no uncaught JS errors (${jsErrors.join(' ; ') || 'none'})`);
} finally {
  await browser.close();
}

console.log(fail.length ? `\n${fail.length} FAILED` : '\nall passed');
process.exit(fail.length ? 1 : 0);
