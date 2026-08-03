// Pathways surfaces that were migrated off the frozen Banner credit columns
// onto build_credit_timeline(). See the field reliability contract in AGENTS.md.
//
// The R suite proves the arithmetic; this proves the wiring. Every one of these
// paths now REQUIRES cedar_student_term_credits to be threaded through, and a
// missing thread is a runtime error the unit tests cannot see.
//
//   node tests/e2e/credit-timeline.test.mjs

import {
  launch, connect, setInput, click, clickSubTab, waitFor,
  readReactable, colIndex, queryActive, sleep,
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
  await sleep(1500);
  await click(page, 'pathways-population-build_btn');
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

  // ── Course Timing on each credit axis ─────────────────────────────────────
  // These are the migrated paths: both now resolve their position through
  // build_credit_timeline() and error loudly without term_credits.
  await clickSubTab(page, 'Course Timing');
  await sleep(2000);

  for (const axis of ['inst_credit_band', 'overall_credit_band']) {
    await setInput(page, 'pathways-ct_x_axis', axis);
    await setInput(page, 'pathways-ct_min_n', 5);
    await sleep(800);
    await click(page, 'pathways-ct_run');

    const drew = await waitFor(page, () => {
      const el = document.getElementById('pathways-ct_plot');
      return el && !!el.querySelector('img');
    }, { timeout: 180000 });

    const toasts = await errorToasts();
    ok(drew, `Course Timing renders on ${axis}`);
    ok(toasts.length === 0, `${axis} raised no error notification (${toasts.join(' | ') || 'none'})`);

    const tbl = await readReactable(page, 'pathways-ct_table');
    if (!tbl.error && tbl.headers.length) {
      const timing = colIndex(tbl.headers, 'Timing');
      const bands = [...new Set(tbl.rows.map((r) => r[timing]))];
      // The whole point of the migration: a frozen source collapsed nearly
      // every student into one band, so more than one band must appear.
      ok(bands.length > 1,
         `${axis} spreads courses across more than one band (${bands.join(', ')})`);
    }
  }

  // ── Major Changes credit column ───────────────────────────────────────────
  await clickSubTab(page, 'Major Changes');
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
