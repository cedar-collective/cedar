// Operational smoke checks for the running CEDAR Shiny app.
//
//   node tests/e2e/reports-smoke.test.mjs
//
// These checks do not assert analytical values. They drive active report
// surfaces with simple known filters and verify that at least one expected
// output renders after each operation.
import {
  launch,
  connect,
  setInput,
  click,
  clickNavTab,
  sleep,
} from './lib.mjs';

const DEPT = process.env.CEDAR_SMOKE_DEPT || 'HIST';
const COURSE = process.env.CEDAR_SMOKE_COURSE || 'HIST 1110';
const TERM = process.env.CEDAR_SMOKE_TERM || '202680';
const CAMPUSES = (process.env.CEDAR_SMOKE_CAMPUSES || 'ABQ,EA')
  .split(',')
  .map((s) => s.trim())
  .filter(Boolean);
const STEP_TIMEOUT = Number(process.env.CEDAR_SMOKE_TIMEOUT_MS || 90000);

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

async function withStep(page, name, fn) {
  try {
    await fn();
    logResult(name, true);
  } catch (e) {
    const path = `/tmp/cedar-smoke-${sanitize(name)}.png`;
    try {
      await page.screenshot({ path, fullPage: true });
    } catch {}
    logResult(name, false, `${e.message}; screenshot ${path}`);
  }
}

async function openReport(page, navName, slug) {
  await clickNavTab(page, navName);
  try {
    await page.waitForFunction(
      (expected) => location.search === `?tab=${expected}`,
      { timeout: 20000, polling: 250 },
      slug,
    );
  } catch {
    const search = await page.evaluate(() => location.search);
    throw new Error(`expected ?tab=${slug}, got ${search}`);
  }
  await sleep(750);
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

async function waitForOutput(page, label, checks, { timeout = STEP_TIMEOUT } = {}) {
  try {
    await page.waitForFunction(
      (items) => {
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

      return items.some((item) => {
        if (item.type === 'text') return hasText(item.id, item.disallowed || []);
        if (item.type === 'reactable') return hasReactableRows(item.id);
        if (item.type === 'dt') return hasDTRows(item.id);
        if (item.type === 'plotly') return hasPlotly(item.id);
        if (item.type === 'plot') return hasImgPlot(item.id);
        return false;
      });
      },
      { timeout, polling: 500 },
      checks,
    );
  } catch {
    throw new Error(`timed out waiting for ${label}`);
  }
}

async function setIfPresent(page, id, value) {
  const exists = await page.evaluate((inputId) => !!document.getElementById(inputId), id);
  if (exists) await setInput(page, id, value);
}

(async () => {
  const { browser, page, jsErrors } = await launch();

  console.log(`Smoke defaults: dept=${DEPT}, course=${COURSE}, term=${TERM}, campuses=${CAMPUSES.join(',')}`);
  await connect(page, { tab: 'home' });

  await withStep(page, 'Dept Dashboard runs', async () => {
    await openReport(page, 'Dept Dashboard', 'dept-dashboard');
    await setInput(page, 'dashboard_campus', CAMPUSES);
    await setInput(page, 'dashboard_dept', DEPT);
    await click(page, 'dashboard_button');
    await waitForOutput(page, 'Dept Dashboard output', [
      { type: 'text', id: 'dashboard_headcount_cards', disallowed: ['Gather Data'] },
      { type: 'plotly', id: 'dashboard_credit_hours' },
    ]);
  });

  await withStep(page, 'Dept Trends runs and lazy tabs populate', async () => {
    await openReport(page, 'Dept Trends', 'dept-trends');
    await setInput(page, 'dept_trends-campus', CAMPUSES);
    await setInput(page, 'dept_trends-dept', DEPT);
    await waitForOutput(page, 'Dept Trends headcount', [
      { type: 'plotly', id: 'dept_trends-hc_progs_under_long_majors_plot' },
    ]);

    await clickSubTabIn(page, 'dept_trends-tabs', 'Enrollment');
    await waitForOutput(page, 'Dept Trends Enrollment tab', [
      { type: 'plotly', id: 'dept_trends-highest_total_enrl_plot' },
      { type: 'plotly', id: 'dept_trends-enrl_credit_hours_by_level_plot' },
    ]);

    await clickSubTabIn(page, 'dept_trends-tabs', 'Degrees');
    await waitForOutput(page, 'Dept Trends Degrees tab', [
      { type: 'plotly', id: 'dept_trends-degree_summary_faceted_by_major_plot' },
    ]);

    await clickSubTabIn(page, 'dept_trends-tabs', 'Credit Hours');
    await waitForOutput(page, 'Dept Trends Credit Hours tab', [
      { type: 'plotly', id: 'dept_trends-chd_by_year_facet_subj_plot' },
      { type: 'dt', id: 'dept_trends-sch_outside_full_lower_table' },
    ]);

    await clickSubTabIn(page, 'dept_trends-tabs', 'Demographics');
    await waitForOutput(page, 'Dept Trends Demographics tab', [
      { type: 'plot', id: 'dept_trends-pt_plot' },
    ]);
  });

  await withStep(page, 'Enrollment runs', async () => {
    await openReport(page, 'Enrollment', 'enrollment');
    await setInput(page, 'enrl_campus', CAMPUSES);
    await setInput(page, 'enrl_dept', [DEPT]);
    await setInput(page, 'enrl_agg_by', ['campus', 'subject_course', 'course_title', 'term']);
    await click(page, 'enrl_button');
    await waitForOutput(page, 'Enrollment rows', [
      { type: 'reactable', id: 'enrl_summary' },
    ]);
  });

  await withStep(page, 'Regstats runs', async () => {
    await openReport(page, 'Regstats', 'registration');
    await setInput(page, 'regstats-rs_campus', CAMPUSES);
    await setInput(page, 'regstats-rs_term', [TERM]);
    await setInput(page, 'regstats-rs_dept', [DEPT]);
    await setInput(page, 'regstats-rs_level', ['lower']);
    await click(page, 'regstats-rs_dashboard_button');
    await waitForOutput(page, 'Regstats dashboard', [
      { type: 'text', id: 'regstats-rs_dashboard', disallowed: ['Set your filters and click'] },
    ]);
  });

  await withStep(page, 'Pathways population builds', async () => {
    await openReport(page, 'Pathways', 'pathways');
    await setInput(page, 'pathways-population-campus', CAMPUSES);
    await setInput(page, 'pathways-population-population_type', 'dept');
    await setInput(page, 'pathways-population-dept_code', DEPT);
    await setInput(page, 'pathways-population-population_scope', 'all');
    await setInput(page, 'pathways-population-student_level', 'Undergraduate');
    await click(page, 'pathways-population-build_btn');
    await waitForOutput(page, 'Pathways population status', [
      { type: 'text', id: 'pathways-population_status', disallowed: ['Define your student population first'] },
      { type: 'text', id: 'pathways-pop_audit_ui', disallowed: ['Define your student population first'] },
    ]);
  });

  await withStep(page, 'Open Seats runs', async () => {
    await openReport(page, 'Open Seats', 'open-seats');
    await setInput(page, 'seatfinder-sf_campus', CAMPUSES);
    await setInput(page, 'seatfinder-sf_term', [TERM]);
    await setIfPresent(page, 'seatfinder-sf_dept', [DEPT]);
    await setInput(page, 'seatfinder-sf_level', ['lower']);
    await click(page, 'seatfinder-sf_button');
    await waitForOutput(page, 'Open Seats output', [
      { type: 'reactable', id: 'seatfinder-type_summary' },
      { type: 'text', id: 'seatfinder-sf_output', disallowed: ['Set filters and click'] },
    ]);
  });

  await withStep(page, 'Cancellations runs', async () => {
    await openReport(page, 'Cancellations', 'cancellations');
    await setInput(page, 'cancellations-cn_campus', CAMPUSES);
    await setInput(page, 'cancellations-cn_term', [TERM]);
    await setIfPresent(page, 'cancellations-cn_dept', [DEPT]);
    await setInput(page, 'cancellations-cn_level', ['lower']);
    await click(page, 'cancellations-cn_button');
    await waitForOutput(page, 'Cancellations output', [
      { type: 'reactable', id: 'cancellations-cn_cancelled_sections' },
      { type: 'text', id: 'cancellations-cn_output', disallowed: ['Set filters and click'] },
    ]);
  });

  await withStep(page, 'Waitlists runs', async () => {
    await openReport(page, 'Waitlists', 'waitlists');
    await setInput(page, 'waitlist-wl_campus', CAMPUSES);
    await setInput(page, 'waitlist-wl_term', [TERM]);
    await setIfPresent(page, 'waitlist-wl_dept', [DEPT]);
    await setInput(page, 'waitlist-wl_level', ['lower']);
    await click(page, 'waitlist-wl_button');
    await waitForOutput(page, 'Waitlists output', [
      { type: 'reactable', id: 'waitlist-wl_count' },
      { type: 'text', id: 'waitlist-wl_output', disallowed: ['Select a course or term and click'] },
    ]);
  });

  await withStep(page, 'Gen Ed runs', async () => {
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

  await withStep(page, 'Headcount runs', async () => {
    await openReport(page, 'Headcount', 'headcount');
    await setInput(page, 'headcount-dept', [DEPT]);
    await click(page, 'headcount-button');
    await waitForOutput(page, 'Headcount output', [
      { type: 'plotly', id: 'headcount-undergrad_plot' },
      { type: 'plotly', id: 'headcount-grad_plot' },
    ]);
  });

  await withStep(page, 'Course Dynamics runs', async () => {
    await openReport(page, 'Course Dynamics', 'course-dynamics');
    await setInput(page, 'cr_campus', CAMPUSES);
    await setInput(page, 'cr_course', COURSE);
    await click(page, 'cr_generate_button');
    await waitForOutput(page, 'Course Dynamics output', [
      { type: 'plotly', id: 'cr_enrollment_plot' },
      { type: 'dt', id: 'cr_enrollment_table' },
    ]);
  });

  logResult(
    'no uncaught JS page errors',
    jsErrors.length === 0,
    jsErrors.slice(0, 3).join(' | '),
  );
  await browser.close();

  const passed = results.filter((r) => r.ok).length;
  console.log(`\n${passed}/${results.length} checks passed`);
  process.exit(failed ? 1 : 0);
})().catch((e) => {
  console.error('REPORT SMOKE HARNESS ERROR:', e);
  process.exit(2);
});
