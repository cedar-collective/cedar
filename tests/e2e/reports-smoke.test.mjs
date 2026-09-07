// Report checks for the running CEDAR Shiny app.
//
//   ./run-tests.sh --e2e [smoke|reports|dept-trends|roadblocks|retention|headcount]
//
// These checks do not assert analytical values. They drive active report
// surfaces with known filters. The default smoke scope runs Enrollment and
// Course Dynamics; all retains the full institutional report tour.
import {
  launch,
  connect,
  setInput as setShinyInput,
  click,
  clickNavTab,
  waitForIdle,
  explainAppReload,
} from './lib.mjs';
import assert from 'node:assert/strict';
import { resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

// One report walkthrough serves institutional smoke checks and synthetic
// acceptance. The synthetic profile selects the fixture scenario for each job.
export async function runReportChecks({ scope = 'smoke', synthetic = false } = {}) {
  const SCOPE = scope;
  if (!['smoke', 'all', 'dept-trends', 'roadblocks', 'retention', 'headcount'].includes(SCOPE)) {
    throw new Error(`Unknown report scope: ${SCOPE}`);
  }

  const DEPT = synthetic ? 'HIST' : process.env.CEDAR_SMOKE_DEPT || 'HIST';
  const COURSE = synthetic ? 'HIST 1110' : process.env.CEDAR_SMOKE_COURSE || 'HIST 1110';
  const TERM = synthetic ? '202080' : process.env.CEDAR_SMOKE_TERM || '202680';
  const CAMPUSES = (synthetic ? 'ABQ,EA' : process.env.CEDAR_SMOKE_CAMPUSES || 'ABQ,EA')
    .split(',')
    .map((s) => s.trim())
    .filter(Boolean);
  const STEP_TIMEOUT = Number(process.env.CEDAR_SMOKE_TIMEOUT_MS || 90000);
  const DEFAULT_DEPT_CAMPUSES = ['ABQ', 'EA'];

  const results = [];
  let failed = 0;

  function logResult(name, ok, detail = '') {
    results.push({ name, ok: !!ok });
    if (!ok) failed++;
    console.log(`${ok ? 'PASS' : 'FAIL'}  ${name}${detail ? `  - ${detail}` : ''}`);
  }

  function sanitize(name) {
    return name.toLowerCase().replace(/[^a-z0-9]+/g, '-').replace(/^-|-$/g, '');
  }

  function sameValues(a, b) {
    return a.length === b.length && [...a].sort().every((v, i) => v === [...b].sort()[i]);
  }

  async function withStep(page, scopes, name, fn) {
    if (SCOPE !== 'all' && !scopes.includes(SCOPE)) return;
    const start = Date.now();
    try {
      await fn();
      logResult(name, true, `${((Date.now() - start) / 1000).toFixed(1)}s`);
    } catch (e) {
      // A self-reloading app destroys the execution context under any step;
      // blaming this one sent people hunting a Headcount bug that never
      // existed. Name the real cause before reporting.
      const err = explainAppReload(page, e);
      const path = `/tmp/cedar-smoke-${sanitize(name)}.png`;
      let shot = `screenshot ${path}`;
      try {
        await page.screenshot({ path, fullPage: true });
      } catch {
        // The same reload that killed the step kills the screenshot, leaving a
        // stale image from an earlier run to be read as current evidence.
        shot = 'screenshot unavailable (page was navigating)';
      }
      logResult(name, false, `${err.message}; ${shot}`);
      throw err; // Stop before dependent steps; do not repeat the whole report tour.
    }
  }

  async function openReport(page, navName, slug) {
    await clickNavTab(page, navName);
    try {
      // Match the tab PARAM, not the whole query string. Earlier steps leave real
      // app state behind (autorun, campus, dept, term), so a strict equality here
      // fails on a tab that opened perfectly well — the reported symptom was
      // "expected ?tab=gen-ed, got ?tab=waitlists&autorun=true&campus=...".
      await page.waitForFunction(
        (expected) => new URLSearchParams(location.search).get('tab') === expected,
        { timeout: 20000, polling: 250 },
        slug,
      );
    } catch {
      const search = await page.evaluate(() => location.search);
      throw new Error(`expected ?tab=${slug}, got ${search}`);
    }
    // Wait for the tab's first render instead of guessing. The fixed sleep that
    // used to be here let the next step set inputs while the module was still
    // wiring up, which surfaces as an empty population rather than as a timeout.
    await waitForIdle(page, { timeout: 120000 }).catch(() => {});
  }

  function clickSubTabIn(page, tabsetId, label) {
    return page.evaluate((id, text) => {
      const root = document.getElementById(id);
      if (!root) throw new Error(`no tabset #${id}`);
      const link = [...root.querySelectorAll('a.nav-link, a[data-toggle="tab"], a')]
        .find((a) => a.textContent.trim() === text);
      if (!link) throw new Error(`no sub-tab "${text}" in #${id}`);
      link.click();
    }, tabsetId, label);
  }

  async function waitForOutput(page, label, checks, { timeout = STEP_TIMEOUT, all = false } = {}) {
    try {
      await page.waitForFunction(
        (items, requireAll) => {
          const hasText = (id, disallowed = []) => {
            const el = document.getElementById(id);
            if (!el) return false;
            const text = el.innerText.trim();
            return text.length > 0 && !disallowed.some((needle) => text.includes(needle));
          };
          const hasReactableRows = (id) => {
            const el = document.getElementById(id);
            return !!el && el.querySelectorAll('.rt-tbody .rt-tr').length > 0;
          };
          const hasDTRows = (id) => {
            const el = document.getElementById(id);
            return !!el && el.querySelectorAll('table.dataTable tbody tr').length > 0;
          };
          const hasPlotly = (id) => {
            const el = document.getElementById(id);
            return !!el && !!el.querySelector('.js-plotly-plot svg.main-svg, .plotly svg.main-svg');
          };
          const hasImgPlot = (id) => {
            const el = document.getElementById(id);
            return !!el && !!el.querySelector('img');
          };

          const hasItem = (item) => {
            if (item.type === 'text') return hasText(item.id, item.disallowed || []);
            if (item.type === 'reactable') return hasReactableRows(item.id);
            if (item.type === 'dt') return hasDTRows(item.id);
            if (item.type === 'plotly') return hasPlotly(item.id);
            if (item.type === 'plot') return hasImgPlot(item.id);
            return false;
          };

          return requireAll ? items.every(hasItem) : items.some(hasItem);
        },
        { timeout, polling: 500 },
        checks,
        all,
      );
    } catch {
      throw new Error(`timed out waiting for ${label}`);
    }
  }

  async function waitForDownloadLinks(page, label, ids, { timeout = STEP_TIMEOUT } = {}) {
    try {
      await page.waitForFunction(
        (downloadIds) => downloadIds.every((id) => {
          const el = document.getElementById(id);
          return !!el &&
            el.tagName === 'A' &&
            el.classList.contains('shiny-download-link') &&
            el.getAttribute('href');
        }),
        { timeout, polling: 500 },
        ids,
      );
    } catch {
      throw new Error(`timed out waiting for ${label} download links`);
    }
  }

  async function setIfPresent(page, id, value) {
    const exists = await page.evaluate((inputId) => !!document.getElementById(inputId), id);
    if (exists) await setInput(page, id, value);
  }

  // A server-side selectize (updateSelectizeInput(server = TRUE), rendered with
  // choices = NULL) holds NO options until a search asks the server for them —
  // cr_course is one, and it caps at maxOptions = 20. Checking picker.options
  // before searching therefore reports "has no option HIST 1110" for a course
  // that exists. Drive it the way a person does: type the query, wait for the
  // server to answer, then select.
  async function loadSelectizeOption(page, id, value) {
    const present = await page.evaluate((inputId, val) => {
      const picker = document.getElementById(inputId)?.selectize;
      return !picker || !!picker.options[val];
    }, id, value);
    if (present) return;
    await page.evaluate((inputId, query) => {
      const picker = document.getElementById(inputId)?.selectize;
      if (picker?.onSearchChange) picker.onSearchChange(String(query));
    }, id, value);
    // loadThrottle debounces the request, so poll rather than sleeping.
    await page.waitForFunction(
      (inputId, val) => !!document.getElementById(inputId)?.selectize?.options[val],
      { timeout: 20000, polling: 200 },
      id,
      value,
    ).catch(() => {}); // Fall through to the explicit error below.
  }

  async function setInput(page, id, value) {
    const values = Array.isArray(value) ? value : [value];
    for (const single of values) await loadSelectizeOption(page, id, single);
    // Keep selectize's visible state in sync with Shiny. Sending only a server
    // value lets later cascading choices erase a selection the UI never held.
    const selected = await page.evaluate((inputId, next) => {
      const picker = document.getElementById(inputId)?.selectize;
      if (!picker) return false;
      const vals = Array.isArray(next) ? next : [next];
      for (const value of vals) {
        if (!picker.options[value]) throw new Error(`${inputId} has no option ${value}`);
      }
      picker.setValue(next);
      return true;
    }, id, value);
    if (!selected) await setShinyInput(page, id, value);
  }

  const { browser, page, jsErrors } = await launch();
  try {
    console.log(`Report scope=${SCOPE}: dept=${DEPT}, course=${COURSE}, term=${TERM}, campuses=${CAMPUSES.join(',')}`);
    await connect(page, { tab: 'home' });
    if (synthetic) {
      assert.ok(await page.$('#cedar_demo_banner'), 'Synthetic acceptance requires the isolated demo app');
      await withStep(page, [], 'Synthetic notice and source freshness', async () => {
        assert.ok(await page.$eval('#cedar_demo_banner', el =>
          el.checkVisibility() && /Synthetic data/.test(el.innerText) && /Fall 2025/.test(el.innerText)));
        await openReport(page, 'Data & Usage', 'data-usage');
        assert.ok(await page.evaluate(() => {
          const rows = [...document.querySelectorAll('#data_status_table tbody tr')];
          return rows.length === 5 && rows.every(row => !row.innerText.includes('Not loaded'));
        }));
      });
    }

    await withStep(page, [], 'Dept Dashboard runs', async () => {
      await openReport(page, 'Dept Dashboard', 'dept-dashboard');
      if (!sameValues(CAMPUSES, DEFAULT_DEPT_CAMPUSES)) {
        await setInput(page, 'dashboard_campus', CAMPUSES);
        await waitForIdle(page, { timeout: 30000 }).catch(() => {});
      }
      await setInput(page, 'dashboard_dept', DEPT);
      await click(page, 'dashboard_button');
      await waitForOutput(page, 'Dept Dashboard output', [
        { type: 'text', id: 'dashboard_headcount_cards', disallowed: ['Gather Data'] },
        { type: 'plot', id: 'dashboard_headcount_sparkline' },
      ]);
    });

    await withStep(page, ['dept-trends'], 'Dept Trends defers hidden charts and renders opened tabs', async () => {
      await openReport(page, 'Dept Trends', 'dept-trends');
      if (!sameValues(CAMPUSES, DEFAULT_DEPT_CAMPUSES)) {
        await setInput(page, 'dept_trends-campus', CAMPUSES);
        await waitForIdle(page, { timeout: 30000 }).catch(() => {});
      }
      await setInput(page, 'dept_trends-dept', DEPT);
      await waitForOutput(page, 'Dept Trends headcount', [
        { type: 'plotly', id: 'dept_trends-hc_progs_under_long_majors_plot' },
      ]);
      await waitForIdle(page, { timeout: STEP_TIMEOUT });
      const hiddenChartsRendered = await page.evaluate(() => [
        'dept_trends-degree_summary_faceted_by_major_plot',
        'dept_trends-pt_plot',
      ].some((id) => document.getElementById(id)?.querySelector('svg.main-svg, img')));
      if (hiddenChartsRendered) throw new Error('Hidden Department Trends charts rendered before opening their tabs');

      await clickSubTabIn(page, 'dept_trends-tabs', 'Enrollment');
      await waitForOutput(page, 'Dept Trends Enrollment tab', [
        { type: 'plotly', id: 'dept_trends-highest_total_enrl_plot' },
        { type: 'plotly', id: 'dept_trends-enrl_college_dept_dual_plot' },
      ], { all: true });

      await clickSubTabIn(page, 'dept_trends-tabs', 'Degrees');
      await waitForOutput(page, 'Dept Trends Degrees tab', [
        { type: 'plotly', id: 'dept_trends-degree_summary_faceted_by_major_plot' },
      ]);

      await clickSubTabIn(page, 'dept_trends-tabs', 'Credit Hours');
      await waitForOutput(page, 'Dept Trends Credit Hours tab', [
        { type: 'plotly', id: 'dept_trends-chd_by_year_facet_subj_plot' },
        { type: 'reactable', id: 'dept_trends-sch_outside_full_table' },
      ], { all: true });
      await waitForDownloadLinks(page, 'Dept Trends Credit Hours', [
        'dept_trends-download_ch_period',
        'dept_trends-download_ch_outside',
      ]);

      await clickSubTabIn(page, 'dept_trends-tabs', 'Demographics');
      await waitForOutput(page, 'Dept Trends Demographics tab', [
        { type: 'plot', id: 'dept_trends-pt_plot' },
      ]);
      if (SCOPE === 'dept-trends') {
        await page.screenshot({ path: '/tmp/cedar-dept-trends.png', fullPage: true });
      }
    });

    await withStep(page, ['smoke'], 'Enrollment runs', async () => {
      await openReport(page, 'Enrollment', 'enrollment');
      if (synthetic) {
        assert.deepEqual(await page.$eval('#enrl_term', el =>
          [...el.selectedOptions].map(option => option.value)), ['202080']);
      }
      await setInput(page, 'enrl_campus', CAMPUSES);
      await setInput(page, 'enrl_term', [TERM]);
      await setInput(page, 'enrl_dept', [DEPT]);
      await setInput(page, 'enrl_agg_by', ['campus', 'subject_course', 'course_title', 'term']);
      await click(page, 'enrl_button');
      await waitForOutput(page, 'Enrollment rows', [
        { type: 'reactable', id: 'enrl_summary' },
      ]);
      await page.waitForFunction(() => {
        const scope = document.getElementById('enrl_filter_summary')?.innerText || '';
        const minLabel = document.querySelector('label[for="enrl_min"]')?.innerText || '';
        return scope.includes('DESR Home:') &&
          minLabel.toUpperCase().includes('DESR MIN') &&
          !!document.querySelector('[data-definition-id="desr-enrollment"]');
      }, { timeout: STEP_TIMEOUT, polling: 500 });

      await clickSubTabIn(page, 'enrl_output_tabs', 'Classlist');
      await waitForOutput(page, 'Enrollment Classlist rows', [
        { type: 'reactable', id: 'enrl_cl_summary' },
      ]);
      await page.waitForFunction(() => {
        const text = document.getElementById('enrl_cl_summary')?.innerText || '';
        return text.includes('EVER REGISTERED PROXY') &&
          text.includes('CENSUS ESTIMATE') &&
          text.includes('REGISTERED AT EXTRACT') &&
          !!document.querySelector('[data-definition-id="registered"]') &&
          !!document.querySelector('[data-definition-id="census-enrollment"]');
      }, { timeout: STEP_TIMEOUT, polling: 500 });
    });

    await withStep(page, [], 'Regstats runs', async () => {
      await openReport(page, 'Regstats', 'registration');
      await setInput(page, 'regstats-rs_campus', CAMPUSES);
      await setInput(page, 'regstats-rs_term', [TERM]);
      await setInput(page, 'regstats-rs_dept', [synthetic ? 'SOCI' : DEPT]);
      await setInput(page, 'regstats-rs_level', ['lower']);
      await click(page, 'regstats-rs_dashboard_button');
      await waitForOutput(page, 'Regstats dashboard', [
        { type: 'text', id: 'regstats-rs_dashboard', disallowed: ['click Get Stats'] },
      ]);
      await page.waitForFunction(() => {
        const note = document.querySelector('[data-definition-id="regstats"][data-definition-version="4.0.0"]');
        const text = document.body.innerText;
        return !!note && text.includes('strictly earlier same-season/part-of-term means and population SD') &&
          text.includes('Unscored SD comparisons: enrollment') &&
          text.includes('Saturation source coverage:') &&
          text.includes('distinct prior comparison term') &&
          text.includes('class-list census proxy');
      }, { timeout: STEP_TIMEOUT, polling: 500 });
      if (synthetic) {
        await waitForOutput(page, 'fixture enrollment bump', [
          { type: 'reactable', id: 'regstats-rs_bumps_table' },
        ]);
        assert.match(await page.$eval('#regstats-rs_bumps_table', el => el.innerText), /SOCI 100/);
        await clickSubTabIn(page, 'regstats-rs_tabs', 'Enrollment Dips');
        await waitForOutput(page, 'fixture enrollment dip', [
          { type: 'reactable', id: 'regstats-rs_dips_table' },
        ]);
        assert.match(await page.$eval('#regstats-rs_dips_table', el => el.innerText), /SOCI 101/);
      }
    });

    await withStep(page, ['roadblocks'], 'Pathways population builds', async () => {
      await openReport(page, 'Pathways', 'pathways');
      // No population-campus here. That control filters cedar_programs$student_campus
      // (home campus, "Albuquerque/Main"), not the ABQ/EA section-campus codes in
      // CAMPUSES — see the two campus fields in AGENTS.md. Passing section codes
      // matched nothing and built an EMPTY population, which still renders both
      // outputs below, so this step passed while testing nothing.
      await setInput(page, 'pathways-population-population_type', 'dept');
      await setInput(page, 'pathways-population-dept_code', DEPT);
      await setInput(page, 'pathways-population-population_scope', 'all');
      await setInput(page, 'pathways-population-student_level', 'Undergraduate');
      await click(page, 'pathways-population-build_btn');
      await waitForOutput(page, 'Pathways population status', [
        { type: 'text', id: 'pathways-population_status', disallowed: ['Define your student population first'] },
        { type: 'text', id: 'pathways-pop_audit_ui', disallowed: ['Define your student population first'] },
      ]);
      // Both outputs render for an EMPTY population too, so the step above cannot
      // tell "built 1,400 students" from "built nothing". Assert the audit filled
      // with real counts. Read pop_audit_ui rather than population_status — the
      // latter sits on a hidden sub-tab and keeps its stale placeholder — and wait
      // for the numbers, since the "non-empty text" wait above is satisfied
      // mid-render before any count has been written.
      try {
        await page.waitForFunction(() => {
          const t = (document.getElementById('pathways-pop_audit_ui') || {}).innerText || '';
          return (t.match(/[\d,]{2,}/g) || []).length >= 4;
        }, { timeout: STEP_TIMEOUT, polling: 500 });
      } catch {
        throw new Error('population audit never filled with counts — likely an empty population');
      }
    });

    await withStep(page, ['roadblocks'], 'Pathways Roadblocks uses current saved outcomes', async () => {
      // Building a population never reads cedar_grades. Exercise its consumer too,
      // so an obsolete file in the actual Docker data mount cannot pass unnoticed.
      await clickSubTabIn(page, 'pathways-analysis_tabs', 'Roadblocks');
      await click(page, 'pathways-so_run');
      await waitForOutput(page, 'Roadblocks saved outcomes', [
        { type: 'reactable', id: 'pathways-so_table' },
      ]);
      await page.waitForFunction(() => {
        const note = document.querySelector('[data-definition-id="roadblocks"][data-definition-version="2.0.0"]');
        const scope = document.getElementById('pathways-so_meta')?.innerText || '';
        const table = document.getElementById('pathways-so_table')?.innerText || '';
        return !!note && scope.includes('first eligible student-course-campus observations') &&
          scope.includes('conflicting first-term outcomes') && /excess gap \(pp\)/i.test(table) &&
          /\d+\.\d%/.test(table);
      }, { timeout: STEP_TIMEOUT, polling: 500 });
    });

    await withStep(page, [], 'Open Seats runs', async () => {
      await openReport(page, 'Open Seats', 'open-seats');
      await setInput(page, 'seatfinder-sf_campus', CAMPUSES);
      await setInput(page, 'seatfinder-sf_term', [synthetic ? '202580' : TERM]);
      await setIfPresent(page, 'seatfinder-sf_dept', [DEPT]);
      // 'lower' for the synthetic run tracks a real defect, not the course: the
      // fixture's HIST 3010 is upper-division, but the DESR level rule sends
      // every 4-digit number to "lower" (ISSUES.md I5). Flip this to 'upper'
      // when I5 is fixed.
      await setInput(page, 'seatfinder-sf_level', ['lower']);
      await click(page, 'seatfinder-sf_button');
      await waitForOutput(page, 'Open Seats output', [
        { type: 'reactable', id: 'seatfinder-type_summary' },
        { type: 'text', id: 'seatfinder-sf_output', disallowed: ['click Find Seats'] },
      ]);
      if (synthetic) {
        assert.match(await page.$eval('#seatfinder-sf_output', el => el.innerText), /HIST 3010/);
      }
    });

    await withStep(page, [], 'Cancellations runs', async () => {
      await openReport(page, 'Cancellations', 'cancellations');
      await setInput(page, 'cancellations-cn_campus', CAMPUSES);
      await setInput(page, 'cancellations-cn_term', [TERM]);
      await setIfPresent(page, 'cancellations-cn_dept', [synthetic ? 'PSYC' : DEPT]);
      // 'lower' for the synthetic run tracks ISSUES.md I5, not the course:
      // PSYC 3200 is upper-division, but the DESR level rule files every
      // 4-digit number as "lower". Flip to 'upper' when I5 is fixed.
      await setInput(page, 'cancellations-cn_level', ['lower']);
      await click(page, 'cancellations-cn_button');
      await waitForOutput(page, 'Cancellations output', [
        { type: 'reactable', id: 'cancellations-cn_cancelled_sections' },
        { type: 'text', id: 'cancellations-cn_output', disallowed: ['click Find Cancellations'] },
      ]);
      if (synthetic) {
        await waitForOutput(page, 'fixture cancellation rows', [
          { type: 'reactable', id: 'cancellations-cn_cancelled_sections' },
        ]);
        assert.match(await page.$eval('#cancellations-cn_cancelled_sections', el => el.innerText), /PSYC 3200/);
      }
    });

    await withStep(page, [], 'Waitlists runs', async () => {
      await openReport(page, 'Waitlists', 'waitlists');
      await setInput(page, 'waitlist-wl_campus', CAMPUSES);
      await setInput(page, 'waitlist-wl_term', [TERM]);
      await setIfPresent(page, 'waitlist-wl_dept', [synthetic ? 'NURS' : DEPT]);
      await setInput(page, 'waitlist-wl_level', ['lower']);
      await click(page, 'waitlist-wl_button');
      await waitForOutput(page, 'Waitlists output', [
        { type: 'reactable', id: 'waitlist-wl_count' },
        { type: 'text', id: 'waitlist-wl_output', disallowed: ['click Inspect Waitlists'] },
      ]);
      if (synthetic) {
        await waitForOutput(page, 'fixture waitlist demand', [
          { type: 'reactable', id: 'waitlist-wl_count' },
        ]);
        const row = await page.$eval('#waitlist-wl_count', el => el.innerText);
        assert.match(row, /NURS 2010/);
        assert.match(row, /\b140\b/, '28 distinct waiting students in each of five cohorts');
      }
    });

    await withStep(page, [], 'Gen Ed runs', async () => {
      await openReport(page, 'Gen Ed', 'gen-ed');
      await setInput(page, 'gen_ed-ge_campus', CAMPUSES);
      await setIfPresent(page, 'gen_ed-ge_dept', [DEPT]);
      await click(page, 'gen_ed-ge_button');
      await waitForOutput(page, 'Gen Ed output', [
        { type: 'plotly', id: 'gen_ed-enrl_modality' },
        { type: 'reactable', id: 'gen_ed-dept_table' },
        { type: 'text', id: 'gen_ed-summary_cards' },
      ]);
    });

    await withStep(page, ['headcount'], 'Headcount runs', async () => {
      await openReport(page, 'Headcount', 'headcount');
      await setInput(page, 'headcount-dept', [DEPT]);
      await click(page, 'headcount-button');
      await waitForOutput(page, 'Headcount output', [
        { type: 'plotly', id: 'headcount-undergrad_plot' },
        { type: 'plotly', id: 'headcount-grad_plot' },
      ]);
    });

    await withStep(page, ['headcount'], 'Headcount combined filters render the current definition', async () => {
      // Cross-department selections must not retain the department row filter.
      await setInput(page, 'headcount-dept', []);
      await waitForIdle(page);
      await setInput(page, 'headcount-major', ['History']);
      await waitForIdle(page);
      await setInput(page, 'headcount-minor', ['English']);
      await waitForIdle(page);
      await click(page, 'headcount-button');
      await waitForIdle(page);
      await waitForOutput(page, 'Combined Headcount output', [
        { type: 'plotly', id: 'headcount-undergrad_plot' },
      ]);
      await waitForDownloadLinks(page, 'Combined Headcount', ['headcount-download_headcount']);
      const scope = await page.$eval('#headcount-scope_summary', (el) => el.textContent);
      if (!scope.includes('History') || !scope.includes('English')) {
        throw new Error(`combined filters did not reach the scope stripe: ${scope}`);
      }
      const definition = await page.$eval(
        '#headcount-output [data-definition-id="program-headcount"]',
        (el) => ({ version: el.dataset.definitionVersion, text: el.textContent }),
      );
      if (definition.version !== '2.0.0' || !definition.text.includes('in the same term')) {
        throw new Error('combined Headcount did not render definition 2.0.0');
      }
    });

    await withStep(page, ['smoke', 'retention'], 'Course Dynamics runs', async () => {
      await openReport(page, 'Course Dynamics', 'course-dynamics');
      await setInput(page, 'cr_campus', CAMPUSES);
      await setInput(page, 'cr_course', COURSE);
      await click(page, 'cr_generate_button');
      await waitForOutput(page, 'Course Dynamics overview', [
        { type: 'text', id: 'cr_overview_metrics' },
        { type: 'plotly', id: 'cr_overview_enrollment_plot' },
        { type: 'plotly', id: 'cr_overview_sections_plot' },
        { type: 'plotly', id: 'cr_overview_avg_size_plot' },
      ], { all: true });
      if (synthetic) {
        const cards = await page.$eval('#cr_overview_metrics', el => el.innerText);
        assert.match(cards, /Fall 2020/);
        // The snapshot keeps one card row per campus, which is the campus
        // policy working: ABQ's 25 and EA's 15 fixture registrations stay
        // visible as themselves and are never merged into a single 40.
        assert.match(cards, /\bABQ\b/);
        assert.match(cards, /\bEA\b/);
        assert.match(cards, /\b25\b/);
        assert.match(cards, /\b15\b/);
        assert.doesNotMatch(cards, /\b40\b/, 'campus cards must not be summed');
      }

      await clickSubTabIn(page, 'cr_tabs', 'Enrollment');
      await waitForOutput(page, 'Course Dynamics enrollment detail', [
        { type: 'plotly', id: 'cr_enrollment_pressure_plot' },
        { type: 'reactable', id: 'cr_enrollment_table' },
      ], { all: true });
    });

    await withStep(page, ['retention'], 'Course Dynamics Retention runs with benchmarks', async () => {
      await clickSubTabIn(page, 'cr_tabs', 'Retention');
      await waitForIdle(page, { timeout: 120000 }).catch(() => {});
      await setInput(page, 'cr_ret_campus', CAMPUSES);
      await setInput(page, 'cr_ret_min_n', 1);
      await setInput(page, 'cr_ret_by_instructor', false);
      await click(page, 'cr_ret_run');
      await waitForIdle(page, { timeout: 180000 }).catch(() => {});
      await waitForOutput(page, 'Course Dynamics Retention benchmarks', [
        { type: 'reactable', id: 'cr_retention_table' },
        { type: 'plotly', id: 'cr_retention_benchmark_diff_plot' },
        { type: 'reactable', id: 'cr_retention_dept_table' },
        { type: 'reactable', id: 'cr_retention_college_table' },
      ], { all: true });
    });

    await withStep(page, ['retention'], 'Course Dynamics Retention instructor breakout runs', async () => {
      await setInput(page, 'cr_ret_by_instructor', true);
      await setInput(page, 'cr_ret_min_n', 1);
      await click(page, 'cr_ret_run');
      await waitForIdle(page, { timeout: 180000 }).catch(() => {});
      await waitForOutput(page, 'Course Dynamics Retention instructor breakout', [
        { type: 'reactable', id: 'cr_retention_table' },
        { type: 'reactable', id: 'cr_retention_instructor_top_table' },
        { type: 'reactable', id: 'cr_retention_instructor_bottom_table' },
      ], { all: true });
    });

    if (synthetic) {
      await withStep(page, [], 'Fixture course shows a multi-year enrollment history', async () => {
        await setInput(page, 'cr_campus', ['ABQ']);
        await setInput(page, 'cr_course', 'SOCI 100');
        await click(page, 'cr_generate_button');
        await clickSubTabIn(page, 'cr_tabs', 'Overview');
        await waitForOutput(page, 'multi-year fixture history', [
          { type: 'plotly', id: 'cr_overview_enrollment_plot' },
        ]);
        // term_code_to_axis_label() abbreviates to a two-digit year ("Fa 18"),
        // so the fixture's four fall terms 201880-202180 read Fa 18..Fa 21.
        // Asserting "2018" here never matched and only ever timed out.
        await page.waitForFunction(() => {
          const labels = [...document.querySelectorAll('#cr_overview_enrollment_plot .xtick text')]
            .map(el => el.textContent).join(' ');
          return ['Fa 18', 'Fa 19', 'Fa 20', 'Fa 21'].every(term => labels.includes(term));
        }, { timeout: STEP_TIMEOUT, polling: 500 });
        await page.screenshot({ path: '/tmp/cedar-synthetic-demo.png', fullPage: true });
      });
    }

    await withStep(page, [], 'Usage Overview renders', async () => {
      await openReport(page, 'Data & Usage', 'data-usage');
      await clickSubTabIn(page, 'data_usage_tabs', 'Usage Overview');
      await waitForIdle(page, { timeout: 120000 }).catch(() => {});
      await click(page, 'refresh_usage_overview');
      await waitForIdle(page, { timeout: 120000 }).catch(() => {});
      await waitForOutput(page, 'Usage Overview dashboard', [
        {
          type: 'text',
          id: 'usage_overview_ui',
          disallowed: ['Error loading usage data', 'Unique sessions'],
        },
        { type: 'reactable', id: 'report_type_usage_table' },
      ], { all: true });

      const overviewText = await page.evaluate(() => {
        const el = document.getElementById('usage_overview_ui');
        return el ? el.innerText : '';
      });
      if (!overviewText.includes('Active sessions')) {
        throw new Error('usage overview did not label sessions as active sessions');
      }
    });

    logResult(
      'no uncaught JS page errors',
      jsErrors.length === 0,
      jsErrors.slice(0, 3).join(' | '),
    );
    const passed = results.filter((r) => r.ok).length;
    console.log(`\n${passed}/${results.length} checks passed`);
    if (failed) throw new Error(`${failed} report checks failed`);
  } finally {
    await browser.close();
  }
}

if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  if (process.argv.length > 3) throw new Error('Expected one report scope');
  await runReportChecks({ scope: process.argv[2] || 'smoke' }).catch(error => {
    console.error('REPORT CHECK FAILED:', error);
    process.exitCode = 1;
  });
}
