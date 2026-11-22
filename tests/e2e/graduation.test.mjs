// Bird's Eye > Graduation: where students leave without a degree, and how far
// along they were (R/modules/graduation.R over build_graduation_dashboard()).
//
// Asserts the tab opens on undergraduates, the main home campus and the 90
// credit line, and builds without a run button: the lead sentence, one bar a
// credit band, the bar chart by last term, the standing table (one row a band,
// its aid-standard column group), the college and major tables with names, and
// every method slot filled; a re-read when the credit line changes; and the
// home card's link.
//
//   node tests/e2e/graduation.test.mjs

import { launch, connect, setInput, waitFor, waitForIdle, requireIds, readReactable, outputsInError } from './lib.mjs';

const fail = [];
const ok = (cond, msg) => { if (!cond) fail.push(msg); console.log(`${cond ? 'ok  ' : 'FAIL'} ${msg}`); };
const NS = 'graduation-';

const { browser, page, jsErrors } = await launch({ width: 1500, height: 1100 });

const bars = (id) => page.evaluate((el) => {
  const root = document.getElementById(el);
  const p = root?.classList.contains('js-plotly-plot') ? root : root?.querySelector('.js-plotly-plot');
  if (!p || !p.data) return null;
  return { x: p.data[0].x || [], y: p.data[0].y || [], text: p.data[0].text || [], title: p.layout?.yaxis?.title?.text || '',
           hatched: [].concat(p.data[0].marker?.pattern?.shape || []).filter((v) => v === '/').length,
           marks: (p.layout?.annotations || []).filter((a) => a.text === 'Not final').length };
}, `${NS}${id}`);

const waitBuilt = async () => {
  await waitFor(page, () => {
    const r = document.getElementById('graduation-bands_plot');
    const p = r?.classList.contains('js-plotly-plot') ? r : r?.querySelector('.js-plotly-plot');
    return !!(p && p.data && p.data.length);
  }, { timeout: 300000 });
  await waitForIdle(page, { timeout: 300000 });
  await waitFor(page, () => !!document.querySelector('#graduation-major_table .rt-tbody'), { timeout: 300000 });
};

try {
  await connect(page, { tab: 'graduation', expect: 'Graduation' });
  await waitBuilt();
  await requireIds(page, [`${NS}level`, `${NS}campus`, `${NS}line`, `${NS}headline`, `${NS}bands_plot`,
                          `${NS}series_plot`, `${NS}standing_table`, `${NS}college_table`, `${NS}major_table`]);
  const level = await page.$eval(`#${NS}level`, (el) => el.value);
  ok(level === 'UG', `the page opens on undergraduates (${level})`);
  const lineAt = await page.$eval(`input[name="${NS}line"]:checked`, (el) => el.value);
  ok(lineAt === '90', `far along opens at 90 credits (${lineAt})`);

  const lead = await page.$eval(`#${NS}headline`, (el) => el.innerText);
  ok(/left without one/.test(lead) && /had 90 credits or more/.test(lead), `the lead counts who left and who was far along (${lead.slice(0, 70)})`);

  const bands = await bars('bands_plot');
  ok(bands && bands.x.length >= 6 && bands.x[0] === 'Under 30' && bands.x.includes('120 or more'),
     `one bar a credit band (${bands?.x})`);
  ok(bands?.text.length === bands?.x.length, 'each bar is labelled with its count');
  const series = await bars('series_plot');
  ok(series && series.x.length >= 2 && /90 credits or more/.test(series.title), `a bar for each last term (${series?.x.length}; ${series?.title})`);
  ok(series?.hatched === series?.marks && series.hatched < series.x.length,
     `the last terms still open to a return are hatched and marked not final (${series?.hatched} of ${series?.x.length})`);

  const standing = await readReactable(page, `${NS}standing_table`, { limit: 10 });
  ok(standing.rows?.length === bands?.x.length && standing.rows.every((r) => r.length === 7),
     `the standing table has a row a band and seven columns (${standing.rows?.length})`);
  const group = await page.$eval(`#${NS}standing_table`, (el) => el.innerText);
  ok(/No longer met a general standard for aid/.test(group), 'the two standards sit under one labelled group');

  const colleges = await readReactable(page, `${NS}college_table`, { limit: 5 });
  ok(colleges.rows?.length > 0 && colleges.rows.every((r) => r[0].length > 3), `colleges are named, not coded (${colleges.rows?.map((r) => r[0]).slice(0, 3)})`);
  const majors = await readReactable(page, `${NS}major_table`, { limit: 5 });
  ok(majors.rows?.length > 0 && majors.rows.every((r) => r.length === 6), `the major table lists majors with their codes (${majors.rows?.length})`);

  const plans = await page.$$eval(`#${NS}plan option`, (os) => os.map((o) => o.textContent));
  ok(plans.length > 0 && plans.every((t) => /\(\d[\d,]* students\)$/.test(t)), `degree plans are listed with their students (${plans.length})`);
  const requiredTraces = () => {
    const r = document.getElementById('graduation-required_plot');
    const p = r?.classList.contains('js-plotly-plot') ? r : r?.querySelector('.js-plotly-plot');
    return p?.data?.length === 3 ? p.data.map((t) => t.name) : null;
  };
  await waitFor(page, requiredTraces, { timeout: 300000 });
  const required = await page.evaluate(requiredTraces);
  ok(required?.[0] === 'Tried here, never passed', `the chart leads with tried and never passed (${required})`);
  const courses = await readReactable(page, `${NS}required_table`, { limit: 5 });
  ok(courses.rows?.length > 0 && courses.rows.every((r) => r.length === 5), `the plan's courses are listed (${courses.rows?.length})`);

  const plotTraces = (id) => {
    const r = document.getElementById(id);
    const p = r?.classList.contains('js-plotly-plot') ? r : r?.querySelector('.js-plotly-plot');
    return p?.data?.length ? p.data.map((t) => t.name) : null;
  };
  await waitFor(page, plotTraces, { timeout: 300000, args: [`${NS}pace_plot`] });
  await waitFor(page, plotTraces, { timeout: 300000, args: [`${NS}accumulation_plot`] });
  const paceParts = await page.evaluate(plotTraces, `${NS}pace_plot`);
  ok(paceParts?.length === 6 && paceParts[1] === 'Enrolled, on pace for four years', `each class is split into six parts (${paceParts?.length})`);
  const creditLines = await page.evaluate(plotTraces, `${NS}accumulation_plot`);
  ok(creditLines?.length >= 3 && creditLines.some((t) => /class$/.test(t)), `credits are drawn a line a class against the two paces (${creditLines?.length})`);
  await waitFor(page, plotTraces, { timeout: 300000, args: [`${NS}ceiling_outcomes_plot`] });
  const ceilingParts = await page.evaluate(plotTraces, `${NS}ceiling_parts_plot`);
  ok(ceilingParts?.length === 3 && ceilingParts[0] === 'Brought from elsewhere', `credits at 160 are drawn in three parts (${ceilingParts})`);
  const ceilingNext = await page.evaluate(plotTraces, `${NS}ceiling_outcomes_plot`);
  ok(ceilingNext?.[0] === 'Awarded a degree' && ceilingNext.length === 3, `what happened next has three outcomes (${ceilingNext?.length})`);

  const paceLead = await page.$eval(`#${NS}pace_lead`, (el) => el.textContent);
  ok(/At the start of their third year/.test(paceLead), 'the lead reads the third year by default');

  await setInput(page, `${NS}pace_started`, 'transfer:60 or more');
  const transferRead = await waitFor(page, (id) => {
    const r = document.getElementById(id);
    const p = r?.classList.contains('js-plotly-plot') ? r : r?.querySelector('.js-plotly-plot');
    return /transfer students who brought 60 or more credits/.test(p?.layout?.xaxis?.title?.text || '');
  }, { timeout: 300000, args: [`${NS}pace_plot`] });
  ok(transferRead, 'transfer students are read as their own classes, by credits brought');
  const transferParts = await page.evaluate(plotTraces, `${NS}pace_plot`);
  ok(/earning 15 or more credits a term here/.test(transferParts?.[1] || ''), `a transfer class is split by credits earned here (${transferParts?.[1]})`);
  await setInput(page, `${NS}pace_started`, 'first_time');

  const methods = await page.evaluate((ns) => ['method_bands', 'method_series', 'method_standing', 'method_groups', 'method_required', 'method_pace', 'method_ceiling']
    .map((id) => document.getElementById(ns + id)?.textContent.trim().length || 0), NS);
  ok(methods.every((n) => n > 80), `every section's method is filled (${methods})`);

  await page.screenshot({ path: '/tmp/cedar-graduation.png', fullPage: true });

  await setInput(page, `${NS}line`, '120');
  const reread = await waitFor(page, () => {
    const r = document.getElementById('graduation-series_plot');
    const p = r?.classList.contains('js-plotly-plot') ? r : r?.querySelector('.js-plotly-plot');
    return /120 credits or more/.test(p?.layout?.yaxis?.title?.text || '');
  }, { timeout: 300000 });
  ok(reread, 'the 120 line re-reads the page');
  await waitBuilt();
  const lead120 = await page.$eval(`#${NS}headline`, (el) => el.innerText);
  ok(/had 120 credits or more\.$/.test(lead120.trim()), `the lead follows the line (${lead120.slice(-50)})`);

  const inError = await outputsInError(page, NS);
  ok(inError.length === 0, `no output in error (${inError.join('; ')})`);

  await connect(page, { tab: 'home' });
  const card = await page.evaluate(() => [...document.querySelectorAll('a[href]')].some((a) => a.getAttribute('href') === '?tab=graduation'));
  ok(card, 'the home page links to Graduation');

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
