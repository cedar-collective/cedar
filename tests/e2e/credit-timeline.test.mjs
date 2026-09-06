// Pathways surfaces that were migrated off the frozen Banner credit columns
// onto build_credit_timeline(). See the field reliability contract in AGENTS.md.
//
// The R suite proves the arithmetic; this proves the wiring. Every one of these
// paths now REQUIRES cedar_student_term_credits to be threaded through, and a
// missing thread is a runtime error the unit tests cannot see.
//
//   node tests/e2e/credit-timeline.test.mjs

import {
  launch, connect, setInput, openSubTab, runAndWait, waitFor,
  readReactable, colIndex, queryActive, waitForIdle,
} from './lib.mjs';

const DEPT = process.env.CEDAR_DEPT || 'HIST';
const fail = [];
const ok = (c, m) => { if (!c) fail.push(m); console.log(`${c ? 'ok  ' : 'FAIL'} ${m}`); };

const { browser, page, jsErrors } = await launch({ width: 1500, height: 1100 });

// Shiny surfaces R errors as a notification rather than a page error, so a
// missing term_credits argument would otherwise look like an empty tab.
const errorToasts = () => page.evaluate(() =>
  [...document.querySelectorAll('.shiny-notification')]
    .map((n) => n.innerText.trim())
    .filter((t) => /fail|error/i.test(t)));

try {
  await connect(page, { tab: 'pathways' });

  // ── Build a population ────────────────────────────────────────────────────
  // population_type gates which selector applies, and the audit output lives in
  // the PARENT namespace (pathways-pop_audit_ui), not the population submodule.
  // Deliberately NOT setting population-campus. That control filters
  // cedar_programs$student_campus, whose values are home-campus names
  // ("Albuquerque/Main"), not the ABQ/EA section-campus codes — see the two
  // campus fields in AGENTS.md. Passing section codes here matches nothing and
  // yields an EMPTY population that still renders an audit panel, so the tab
  // looks built while every downstream assertion silently tests nothing.
  await setInput(page, 'pathways-population-population_type', 'dept');
  await setInput(page, 'pathways-population-dept_code', DEPT);
  await setInput(page, 'pathways-population-population_scope', 'all');
  await setInput(page, 'pathways-population-student_level', 'Undergraduate');
  await waitForIdle(page);
  await runAndWait(page, 'pathways-population-build_btn', { timeout: 180000 });
  const built = await waitFor(page, () => {
    const el = document.getElementById('pathways-pop_audit_ui');
    return el && el.innerText.trim().length > 0 &&
           !el.innerText.includes('Define your student population first');
  }, { timeout: 180000 });
  ok(built, 'population panel renders');

  // The panel renders for an empty population too, so assert it filled with real
  // counts. This is the check that would have caught the campus-field mixup
  // above. Two traps here: population_status lives on a hidden sub-tab and keeps
  // its stale placeholder, and pop_audit_ui passes a "non-empty text" wait while
  // still mid-render — so wait for the numbers themselves, not for any text.
  const audited = await waitFor(page, () => {
    const t = (document.getElementById('pathways-pop_audit_ui') || {}).innerText || '';
    return (t.match(/[\d,]{2,}/g) || []).length >= 4;
  }, { timeout: 120000 });
  const popText = await page.evaluate(() =>
    (document.getElementById('pathways-pop_audit_ui') || {}).innerText || '');
  const popNums = (popText.match(/[\d,]{2,}/g) || [])
    .map((t) => parseInt(t.replace(/,/g, ''), 10));
  ok(audited && popNums.length >= 4,
     `population audit filled with real counts (${popNums.slice(0, 6).join(', ')})`);

  // One population covers credit wiring and the truncation disclosure.
  await openSubTab(page, 'Course Timing');
  const metaText = () => page.$eval('#pathways-ct_meta', el => el.innerText.trim());
  const defaultAxis = await page.$eval('#pathways-ct_x_axis', el => el.value);
  ok(defaultAxis === 'classification', 'Classification is the default axis');
  await runAndWait(page, 'pathways-ct_run', { timeout: 180000 });
  await page.waitForFunction(() =>
    /students analyzed/i.test(document.getElementById('pathways-ct_meta')?.innerText || ''),
    { timeout: 180000 });
  ok(!/excluded/i.test(await metaText()), 'Classification excludes nobody for truncation');

  for (const axis of ['inst_credit_band', 'overall_credit_band']) {
    await setInput(page, 'pathways-ct_x_axis', axis);
    await setInput(page, 'pathways-ct_min_n', 5);
    await waitForIdle(page);
    await runAndWait(page, 'pathways-ct_run', { timeout: 180000 });

    const drew = await waitFor(page, () => {
      const el = document.getElementById('pathways-ct_plot');
      return el && !!el.querySelector('img');
    }, { timeout: 180000 });
    ok(drew, `Course Timing renders on ${axis}`);
    const toasts = await errorToasts();
    ok(toasts.length === 0, `${axis} raised no error notification (${toasts.join(' | ') || 'none'})`);

    const creditMeta = await metaText();
    ok(/students? excluded/i.test(creditMeta), `${axis} states truncation exclusions`);
    ok(/record begins at the edge of the data/i.test(creditMeta), 'exclusions explain the missing history');
    ok(/Classification axis/i.test(creditMeta), 'disclosure points to the unrestricted axis');

    const tbl = await readReactable(page, 'pathways-ct_table');
    const timing = colIndex(tbl.headers || [], 'Timing');
    ok(!tbl.error && timing >= 0 && tbl.rows.length > 0, `${axis} has a populated timing table`);
    if (!tbl.error && timing >= 0) {
      const bands = [...new Set(tbl.rows.map(r => r[timing]))];
      ok(bands.length > 1, `${axis} spreads courses across more than one band (${bands.join(', ')})`);
    }
  }
  // ── Major Changes credit column ───────────────────────────────────────────
  await openSubTab(page, 'Major Changes', { timeout: 180000 });
  const mcReady = await waitFor(page, () => {
    const el = document.getElementById('pathways-mc_summary_cards');
    return el && el.innerText.trim().length > 0;
  }, { timeout: 180000 });
  ok(mcReady, 'Major Changes computes');
  ok((await errorToasts()).length === 0, 'Major Changes raised no error notification');

  // The change-events table lives inside a collapsed <details> panel, and Shiny
  // suspends hidden outputs — it never renders until the panel is opened.
  await page.evaluate(() => {
    document.querySelectorAll('details.cedar-info-panel').forEach((d) => { d.open = true; });
  });
  await waitFor(page, () => {
    const el = document.getElementById('pathways-mc_changes_table');
    return el && el.querySelectorAll('.rt-tbody .rt-tr').length > 0;
  }, { timeout: 120000 });

  const changes = await readReactable(page, 'pathways-mc_changes_table');
  if (changes.error) {
    ok(false, `changes table: ${changes.error}`);
  } else {
    console.log('changes headers:', changes.headers.join(' | '));
    const unm = colIndex(changes.headers, 'UNM credits at change');
    ok(unm >= 0, 'changes table has the migrated credit column');
    if (unm >= 0) {
      const vals = changes.rows.map((r) => parseFloat(r[unm])).filter((v) => !Number.isNaN(v));
      ok(vals.length > 0, `credit positions are populated (${vals.slice(0, 5).join(', ')})`);
      // A frozen source made every row that student's final total, so distinct
      // values across rows is the signal that a real position is being read.
      ok(new Set(vals).size > 1, `credit positions vary across students (${new Set(vals).size} distinct)`);
      ok(vals.every((v) => v >= 0 && v < 400), 'credit positions are in a plausible range');
    }
  }

  const headings = await queryActive(page, 'h2, h3, h4, h5');
  console.log('subtab headings:', headings.slice(0, 8).join(' | '));

  await page.screenshot({ path: '/tmp/cedar-credit-timeline.png' });
  ok(jsErrors.length === 0, `no uncaught JS errors (${jsErrors.join(' ; ') || 'none'})`);
} finally {
  await browser.close();
}

console.log(fail.length ? `\n${fail.length} FAILED` : '\nall passed');
process.exit(fail.length ? 1 : 0);
