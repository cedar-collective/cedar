// Bird's Eye > Retention: are students coming back, and who is not
// (R/modules/retention-dashboard.R over build_retention_dashboard()).
//
// Asserts the tab opens on fall terms and undergraduates and builds without a
// run button: the latest-term and trend cards, the return line with a label
// a term, the warning-sign table (a late withdrawal and a DFW grade, each with
// and without), the classification and college tables with a trend line and
// no word, the course table, every method slot filled; a re-read when the
// term type or the student level changes; and the home card's
// link.
//
//   node tests/e2e/retention-dashboard.test.mjs

import { launch, connect, setInput, waitFor, waitForIdle, requireIds, waitForSelector,
         readReactable } from './lib.mjs';

const fail = [];
const ok = (cond, msg) => { if (!cond) fail.push(msg); console.log(`${cond ? 'ok  ' : 'FAIL'} ${msg}`); };
const NS = 'retention_dashboard-';

const { browser, page, jsErrors } = await launch({ width: 1500, height: 1100 });

const cards = () => page.evaluate((el) => [...document.querySelectorAll(`#${el} .finding-card`)].map((c) => ({
  title: c.querySelector('.finding-card-title span')?.textContent.trim(),
  headline: c.querySelector('.finding-card-headline .stat-num')?.textContent.trim(),
  scope: c.querySelector('.finding-card-title')?.textContent.trim(),
})), `${NS}overall_finding`);

const line = () => page.evaluate((el) => {
  const root = document.getElementById(el);
  const p = root?.classList.contains('js-plotly-plot') ? root : root?.querySelector('.js-plotly-plot');
  if (!p || !p.data) return null;
  return { n: (p.data[0].x || []).length, text: p.data[0].text || [] };
}, `${NS}overall_plot`);

const waitBuilt = async () => {
  await waitForSelector(page, `#${NS}overall_finding .finding-card`, { timeout: 300000 });
  await waitForIdle(page, { timeout: 300000 });
  await waitFor(page, () => !!document.querySelector('#retention_dashboard-courses_table .rt-tbody'), { timeout: 300000 });
};

try {
  await connect(page, { tab: 'retention', expect: 'Retention' });
  await waitBuilt();
  await requireIds(page, [`${NS}term_type`, `${NS}level`, `${NS}campus`, `${NS}overall_plot`, `${NS}signs_table`,
                          `${NS}classification_table`, `${NS}college_table`, `${NS}courses_table`]);
  const termType = await page.$eval(`input[name="${NS}term_type"]:checked`, (el) => el.value);
  ok(termType === 'fall', `the page opens on fall terms (${termType})`);
  const level = await page.$eval(`#${NS}level`, (el) => el.value);
  ok(level === 'UG', `the page opens on undergraduates (${level})`);
  const campus = await page.$eval(`#${NS}campus`, (el) => (el.selectize ? el.selectize.getValue() : [...el.selectedOptions].map((o) => o.value)));
  ok(JSON.stringify(campus) === '["ABQ"]', `the page opens on the main home campus (${campus})`);

  const fall = await cards();
  ok(fall.map((c) => c.title).join('|') === 'Latest term|Trend', `latest-term and trend cards (${fall.map((c) => c.title)})`);
  ok(/%$/.test(fall[0]?.headline || ''), `the latest term leads with its rate (${fall[0]?.headline})`);
  const ln = await line();
  ok(ln && ln.n >= 3 && ln.text.length === ln.n, `the return line labels each of its ${ln?.n} terms`);

  const signs = await readReactable(page, `${NS}signs_table`, { limit: 5 });
  ok(signs.rows?.map((r) => r[0]).join('|') === 'A late withdrawal|A DFW grade', `the two warning signs (${signs.rows?.map((r) => r[0])})`);
  ok(signs.rows?.every((r) => parseFloat(r[3]) < parseFloat(r[4])), `each sign comes back less often than without it (${signs.rows?.map((r) => `${r[3]} vs ${r[4]}`)})`);

  for (const id of ['classification_table', 'college_table']) {
    const t = await readReactable(page, `${NS}${id}`, { limit: 5 });
    ok(t.rows?.length > 0 && t.rows.every((r) => r.length === 5), `${id} lists groups with a trend cell (${t.rows?.length})`);
    const words = await page.evaluate((el) => [...document.querySelectorAll(`#${el} .rt-tbody .rt-tr`)]
      .map((r) => r.lastElementChild?.innerText.trim()).filter(Boolean), `${NS}${id}`);
    ok(words.length === 0, `${id}: a trend cell is its line, with no word (${words.slice(0, 3)})`);
  }
  const colleges = await readReactable(page, `${NS}college_table`, { limit: 5 });
  ok(colleges.rows?.every((r) => r[0].length > 3), `colleges are named, not coded (${colleges.rows?.map((r) => r[0]).slice(0, 3)})`);

  const courses = await readReactable(page, `${NS}courses_table`, { limit: 10 });
  ok(courses.rows?.length > 0, `the course table lists courses (${courses.rows?.length})`);
  ok(courses.rows?.every((r) => parseFloat(r[4]) < parseFloat(r[5])), 'each listed course: back less often after a DFW than after passing');
  const excess = courses.rows?.map((r) => parseInt(r[7].replace(/,/g, ''), 10)) || [];
  ok(excess.every((v, i) => i === 0 || v <= excess[i - 1]), `ranked by the students a gap stands for (${excess.slice(0, 5)})`);

  const methods = await page.evaluate((ns) => ['method_overall', 'method_signs', 'method_groups', 'method_courses']
    .map((id) => document.getElementById(ns + id)?.textContent.trim().length || 0), NS);
  ok(methods.every((n) => n > 80), `every section's method is filled (${methods})`);

  await page.screenshot({ path: '/tmp/cedar-retention.png', fullPage: true });

  await setInput(page, `${NS}term_type`, 'spring');
  const reread = await waitFor(page, (f) => {
    const h = document.querySelector('#retention_dashboard-overall_finding .finding-card .finding-card-headline .stat-num')?.textContent.trim();
    const scope = document.querySelector('#retention_dashboard-overall_finding .finding-card .finding-card-title')?.textContent;
    return /Spring/.test(scope || '') && h && h !== f;
  }, { timeout: 300000, args: [fall[0]?.headline] });
  ok(reread, 'spring re-reads the page on a spring term');
  await waitBuilt();

  const countLine = () => page.evaluate(() =>
    document.querySelector('#retention_dashboard-overall_finding .finding-card .stat-compare')?.textContent.trim());
  const undergrad = await countLine();
  // The second level in student_levels.csv (graduate at UNM). A home campus
  // changes little at the undergraduate level: nearly all are ABQ students.
  const second = await page.$eval(`#${NS}level`, (el) => Object.values(el.selectize?.options || {})
    .sort((a, b) => a.$order - b.$order).map((o) => o.value)[1]);
  await setInput(page, `${NS}level`, second);
  const narrowed = await waitFor(page, (f) => {
    const t = document.querySelector('#retention_dashboard-overall_finding .finding-card .stat-compare')?.textContent.trim();
    return t && t !== f;
  }, { timeout: 300000, args: [undergrad] });
  ok(narrowed, `another student level (${second}) re-reads the page`);

  await connect(page, { tab: 'home' });
  const card = await page.evaluate(() => [...document.querySelectorAll('a[href]')].some((a) => a.getAttribute('href') === '?tab=retention'));
  ok(card, 'the home page links to Retention');

  ok(jsErrors.length === 0, `no page errors (${jsErrors.join('; ')})`);
} catch (e) {
  fail.push(String(e));
  console.log(`FAIL ${e}`);
} finally {
  await browser.close();
}

if (fail.length) {
  console.log(`\n${fail.length} failed`);
  process.exit(1);
}
console.log('\nall passed');
