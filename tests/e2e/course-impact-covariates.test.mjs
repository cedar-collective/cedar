// Course Dynamics > Downstream > Course Sequence: reconstructed matching covariates.
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

import { launch, connect, setInput, runAndWait, openSubTab,
         waitForIdle, requireIds } from './lib.mjs';

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

  // ── Downstream > Course Sequence ──────────────────────────────────────────
  // openSubTab waits for the pane to be visible and for its outputs to settle.
  // Both matter here: the run button is itself rendered by cr_impact_sequence_ui,
  // and innerText on a still-hidden pane returns '' — indistinguishable from a
  // tab that rendered nothing.
  await openSubTab(page, 'Downstream', { timeout: 300000 });
  await openSubTab(page, 'Course Sequence', { timeout: 300000 });
  await requireIds(page, ['cr_impact_seq_course_y', 'cr_impact_seq_run']);

  await setInput(page, 'cr_impact_seq_course_y', COURSE_Y);
  await runAndWait(page, 'cr_impact_seq_run', { timeout: 300000 });

  const body = await page.evaluate(() =>
    document.getElementById('cr_impact_sequence_ui').innerText);

  const definition = await page.evaluate(() => {
    const note = document.querySelector(
      '#cr_impact_sequence_ui [data-definition-id="course-sequence"]'
    );
    return note ? {
      version: note.getAttribute('data-definition-version'),
      text: note.innerText
    } : null;
  });

  ok(definition?.version === '2.0.0',
     'Course Sequence uses definition v2');
  ok(/small observed difference/i.test(body) && /0\.10/.test(body),
     'the page defines the small observed-difference band');
  ok(/0\.10[–-]0\.25/.test(body) && /review/i.test(body),
     'the page exposes the review band rather than a green success state');
  ok(/substantial difference/i.test(body) && />0\.25/.test(body),
     'the page defines the substantial observed-difference band');
  ok(!/Groups appear well-balanced/i.test(body),
     'the old all-values-at-or-below-0.25 success claim is absent');

  // ── The new covariates are present ────────────────────────────────────────
  ok(/Cum GPA/i.test(body), 'group profile shows the reconstructed cumulative GPA');
  ok(/cum_gpa_entering/i.test(body) || /Cum Gpa Entering/i.test(body),
     'balance table lists cum_gpa_entering as a matched covariate');
  ok(/credits_entering/i.test(body) || /Credits Entering/i.test(body),
     'balance table lists a reconstructed credit covariate');

  // ── Institution GPA: shown, but only as description ───────────────────────
  // It is the best-covered summary of overall academic strength, so it belongs
  // in the profile. It is measured at the data pull — after the outcome — so it
  // must never appear as a balanced covariate.
  ok(/Current UNM GPA/i.test(body),
     'group profile shows the registrar current UNM GPA alongside the rebuilt one');
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
