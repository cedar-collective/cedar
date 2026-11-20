// Run buttons wait for what they need (cedar_requires() in
// R/modules/ui-helpers.R, the run-button block in www/cedar-navigation.js),
// and the Dept Dashboard reads in dark mode.
//
// Asserts the Dept Dashboard's Gather Data is disabled, with its hint, until a
// department is chosen in the picker; Open Seats' Find Seats is disabled with
// no term; Pathways' Define Population follows "Select population by" (a
// preset needs nothing, a department needs one); the Pathways subtabs' Run
// waits for a population. In dark mode the dashboard's Students cards take the
// dark card surface, its trend is a native plotly chart with the dark grid,
// and no table cell keeps a light background.
//
//   node tests/e2e/run-buttons.test.mjs

import { launch, connect, waitFor, waitForIdle } from './lib.mjs';

const fail = [];
const ok = (cond, msg) => { if (!cond) fail.push(msg); console.log(`${cond ? 'ok  ' : 'FAIL'} ${msg}`); };

const { browser, page, jsErrors } = await launch({ width: 1400, height: 1000 });
const state = (id) => page.evaluate((i) => { const b = document.getElementById(i); return b ? { disabled: b.disabled, title: b.title } : null; }, id);
// Choose in the picker itself, as a reader does.
const pick = (id, value) => page.evaluate((i, v) => { const s = document.getElementById(i).selectize; s.setValue(v); }, id, value);

try {
  await connect(page, { tab: 'home' });
  await page.evaluate(() => localStorage.setItem('cedar-theme', 'dark'));

  await connect(page, { tab: 'dept-dashboard' });
  let gather = await state('dashboard_button');
  ok(gather?.disabled && /department/i.test(gather.title), `Gather Data waits for a department (${JSON.stringify(gather)})`);
  const dept = await page.evaluate(() => Object.keys(document.getElementById('dashboard_dept').selectize.options).filter((k) => k)[0]);
  await pick('dashboard_dept', dept);
  await waitFor(page, () => !document.getElementById('dashboard_button').disabled, { timeout: 10000 });
  gather = await state('dashboard_button');
  ok(gather && !gather.disabled && gather.title === '', `choosing one enables it (${JSON.stringify(gather)})`);
  await pick('dashboard_dept', '');
  await waitFor(page, () => document.getElementById('dashboard_button').disabled, { timeout: 10000 });
  ok((await state('dashboard_button')).disabled, 'clearing it disables it again');

  // Dark mode on a built dashboard.
  await pick('dashboard_dept', dept);
  await waitFor(page, () => !document.getElementById('dashboard_button').disabled, { timeout: 10000 });
  await page.click('#dashboard_button');
  await waitFor(page, () => !!document.querySelector('.dept-headcount-card'), { timeout: 300000 });
  await waitForIdle(page, { timeout: 300000 });
  const look = await page.evaluate(() => {
    const card = document.querySelector('.dept-headcount-card');
    const r = document.getElementById('dashboard_headcount_sparkline');
    const gd = r?.classList.contains('js-plotly-plot') ? r : r?.querySelector('.js-plotly-plot');
    const light = (c) => { const m = (c || '').match(/\d+(\.\d+)?/g); if (!m) return false; const [r1, g, b, a] = m.map(Number); return (a === undefined || a > 0.3) && (r1 + g + b) / 3 > 200; };
    const cells = [...document.querySelectorAll('.rt-td, .rt-th, td, th')].filter((c) => c.checkVisibility()).map((c) => getComputedStyle(c).backgroundColor);
    return { card: getComputedStyle(card).backgroundColor, plotly: !!(gd && gd._fullLayout),
             grid: gd?._fullLayout?.yaxis?.gridcolor || null, lightCells: cells.filter(light).length, cells: cells.length };
  });
  ok(look.card === 'rgb(34, 38, 36)', `the Students cards take the dark card surface (${look.card})`);
  ok(look.plotly && /rgba\(255, 255, 255, 0\.1/.test(look.grid || ''), `the trend is plotly with the dark grid (${look.grid})`);
  ok(look.lightCells === 0, `no table cell keeps a light background (${look.lightCells} of ${look.cells})`);

  await connect(page, { tab: 'open-seats' });
  await page.evaluate(() => document.getElementById('seatfinder-sf_term').selectize.clear());
  await waitFor(page, () => document.getElementById('seatfinder-sf_button').disabled, { timeout: 10000 });
  ok((await state('seatfinder-sf_button')).disabled, 'Find Seats waits for a term');

  await connect(page, { tab: 'pathways' });
  const build = async (type) => {
    await page.evaluate((t) => { const el = document.getElementById('pathways-population-population_type'); if (el.selectize) el.selectize.setValue(t); else { el.value = t; el.dispatchEvent(new Event('change', { bubbles: true })); } }, type);
    await new Promise((r) => setTimeout(r, 300));
    return state('pathways-population-build_btn');
  };
  const preset = await build('preset');
  ok(preset && !preset.disabled, 'Define Population needs nothing for a preset');
  await build('dept');
  // A single-choice picker opens on its first option; cleared, nothing is chosen.
  await page.evaluate(() => document.getElementById('pathways-population-dept_code').selectize.clear());
  await waitFor(page, () => document.getElementById('pathways-population-build_btn').disabled, { timeout: 10000 });
  const byDept = await state('pathways-population-build_btn');
  ok(byDept?.disabled && /who to include/.test(byDept.title), `by department it waits for one (${JSON.stringify(byDept)})`);
  const run = await state('pathways-so_run');
  ok(run?.disabled, 'a subtab Run waits for a population');

  ok(jsErrors.length === 0, `no page errors (${jsErrors.join('; ')})`);
} catch (e) {
  fail.push(String(e));
  console.log(`FAIL ${e}`);
} finally {
  await page.evaluate(() => { try { localStorage.removeItem('cedar-theme'); } catch (e) {} }).catch(() => {});
  await browser.close();
}

if (fail.length) {
  console.log(`\n${fail.length} failed`);
  process.exit(1);
}
console.log('\nall passed');
