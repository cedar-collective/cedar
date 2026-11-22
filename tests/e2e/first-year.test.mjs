// Bird's Eye > First Year: how much of each entering class is still here after
// its first semesters (R/modules/first-year.R over
// retention_dashboard_milestones()).
//
// Asserts the tab opens on fall classes, undergraduates and first-time
// students and builds without a run button: a line for each of the four
// semesters with a point a class, a lead sentence, the method filled, no
// output in error; a re-read when who a class holds changes; and the home
// card's link.
//
//   node tests/e2e/first-year.test.mjs

import { launch, connect, setInput, waitFor, waitForIdle, requireIds, outputsInError, readReactable,
         waitForSelector } from './lib.mjs';

const fail = [];
const ok = (cond, msg) => { if (!cond) fail.push(msg); console.log(`${cond ? 'ok  ' : 'FAIL'} ${msg}`); };
const NS = 'first_year-';

const { browser, page, jsErrors } = await launch({ width: 1500, height: 1100 });

const lines = () => page.evaluate((el) => {
  const root = document.getElementById(el);
  const p = root?.classList.contains('js-plotly-plot') ? root : root?.querySelector('.js-plotly-plot');
  if (!p || !p.data || !p.data.length) return null;
  return { names: p.data.map((d) => d.name), x: p.data[0].x || [], y: JSON.stringify(p.data.map((d) => d.y)) };
}, `${NS}milestones_plot`);
const waitBuilt = async () => {
  await waitFor(page, (id) => {
    const r = document.getElementById(id);
    const p = r?.classList.contains('js-plotly-plot') ? r : r?.querySelector('.js-plotly-plot');
    return !!(p && p.data && p.data.length);
  }, { timeout: 300000, args: [`${NS}milestones_plot`] });
  await waitForIdle(page, { timeout: 300000 });
};

try {
  await connect(page, { tab: 'first-year', expect: 'First Year' });
  await waitBuilt();
  await requireIds(page, [`${NS}term_type`, `${NS}level`, `${NS}campus`, `${NS}entry`, `${NS}milestones_plot`]);
  const termType = await page.$eval(`input[name="${NS}term_type"]:checked`, (el) => el.value);
  ok(termType === 'fall', `the page opens on fall classes (${termType})`);
  const entry = await page.$eval(`input[name="${NS}entry"]:checked`, (el) => el.value);
  ok(entry === 'first_time', `the page opens on first-time students (${entry})`);

  const first = await lines();
  ok(first && first.names.length === 4 && /2nd semester/.test(first.names[0]),
     `a line for each of four semesters (${first?.names.join(', ')})`);
  ok(first?.x.length >= 2, `a point for each entering class (${first?.x.length})`);
  const lead = await page.$eval(`#${NS}milestones_finding`, (el) => el.innerText.trim());
  ok(/^Of the /.test(lead) && /who entered in/.test(lead), `the section opens on one class in words (${lead.slice(0, 60)}…)`);
  const method = await page.$eval(`#${NS}method_milestones`, (el) => el.textContent.trim().length);
  ok(method > 80, 'the section says how it is counted');

  // The summer after the first spring: back in the fall, by taking a summer course or not.
  const traces = (id) => {
    const r = document.getElementById(id);
    const p = r?.classList.contains('js-plotly-plot') ? r : r?.querySelector('.js-plotly-plot');
    return p?.data?.length ? p.data.map((t) => t.name) : null;
  };
  await waitFor(page, traces, { timeout: 300000, args: [`${NS}summer_plot`] });
  const summerLines = await page.evaluate(traces, `${NS}summer_plot`);
  ok(JSON.stringify(summerLines) === '["Took a summer course","Did not"]', `the summer chart has a line for each group (${summerLines})`);
  const summerLead = await page.$eval(`#${NS}summer_finding`, (el) => el.innerText.trim());
  ok(/back in the fall/.test(summerLead) && /not what it causes\.$/.test(summerLead),
     `the summer section opens on the classes read, with its warning (${summerLead.slice(0, 50)}…)`);
  await waitForSelector(page, `#${NS}summer_courses .rt-tbody`);
  const summerCourses = await readReactable(page, `${NS}summer_courses`, { limit: 5 });
  ok(summerCourses.rows.length > 0 && summerCourses.rows[0].length === 5, `the summer courses are listed with titles (${summerCourses.rows.length})`);
  const summerMethod = await page.$eval(`#${NS}method_summer`, (el) => el.textContent.trim().length);
  ok(summerMethod > 80, 'the summer section says how it is counted');
  ok((await outputsInError(page, NS)).length === 0, `no output in error (${(await outputsInError(page, NS)).join('; ')})`);

  await setInput(page, `${NS}entry`, 'transfer');
  const reread = await waitFor(page, (id, before) => {
    const r = document.getElementById(id);
    const p = r?.classList.contains('js-plotly-plot') ? r : r?.querySelector('.js-plotly-plot');
    return !!p?.data?.length && JSON.stringify(p.data.map((d) => d.y)) !== before;
  }, { timeout: 300000, args: [`${NS}milestones_plot`, first?.y] });
  ok(reread, 'new transfer students re-read the chart');
  await waitBuilt();
  ok((await outputsInError(page, NS)).length === 0, 'no output in error for transfer classes');

  await page.screenshot({ path: '/tmp/cedar-first-year.png', fullPage: true });

  await connect(page, { tab: 'home' });
  const card = await page.evaluate(() => [...document.querySelectorAll('a[href]')].some((a) => a.getAttribute('href') === '?tab=first-year'));
  ok(card, 'the home page links to First Year');
  ok(jsErrors.length === 0, `no JavaScript errors (${jsErrors.join('; ')})`);
} catch (e) {
  fail.push(`threw: ${e.message}`);
  console.log(`FAIL threw: ${e.message}`);
} finally {
  await browser.close();
}

console.log(fail.length ? `\n${fail.length} FAILED` : '\nall passed');
process.exit(fail.length ? 1 : 0);
