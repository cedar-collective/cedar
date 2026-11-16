// Bird's Eye > DFW Rates: how lower-division DFW rates are moving and where
// to act (R/modules/dfw-rates.R over build_dfw_dashboard()).
//
// Asserts the tab opens on fall terms and builds without a run button: the
// latest-term and trend cards, the term bars split into the four kinds of DFW
// grade with each bar's total labelled, the concentration figure whose parts
// add to its headline, the course bars and table, the rising/falling/swinging
// cards with the slope chart, the section strip and table, the campus and
// college tables; every method slot filled; no instructor anywhere; a re-read
// when the term type changes; and a deep link that restores the term type and
// campus.
//
//   node tests/e2e/dfw-rates.test.mjs

import { launch, connect, setInput, waitFor, waitForIdle, requireIds, waitForSelector,
         readReactable } from './lib.mjs';

const fail = [];
const ok = (cond, msg) => { if (!cond) fail.push(msg); console.log(`${cond ? 'ok  ' : 'FAIL'} ${msg}`); };
const NS = 'dfw_rates-';

const { browser, page, jsErrors } = await launch({ width: 1500, height: 1100 });

const plot = (id) => page.evaluate((el) => {
  const root = document.getElementById(el);
  const p = root?.classList.contains('js-plotly-plot') ? root : root?.querySelector('.js-plotly-plot');
  if (!p || !p.data) return null;
  return { names: p.data.map((t) => t.name), n: p.data.map((t) => (t.x || []).length),
           annotations: (p.layout?.annotations || []).map((a) => a.text) };
}, `${NS}${id}`);

const cards = (id) => page.evaluate((el) => [...document.querySelectorAll(`#${el} .finding-card`)].map((c) => ({
  title: c.querySelector('.finding-card-title span')?.textContent.trim(),
  headline: c.querySelector('.finding-card-headline .stat-num')?.textContent.trim(),
  parts: [...c.querySelectorAll('.segment-legend-count')].map((s) => parseInt(s.textContent.replace(/,/g, ''), 10)),
})), `${NS}${id}`);

const waitBuilt = async (termType) => {
  await waitFor(page, (t) => document.querySelector('input[name="dfw_rates-dr_term_type"]:checked')?.value === t,
                { timeout: 60000, args: [termType] });
  await waitForSelector(page, `#${NS}overall_finding .finding-card`, { timeout: 300000 });
  await waitForIdle(page, { timeout: 300000 });
  await waitFor(page, () => !!document.querySelector('#dfw_rates-section_table .rt-tbody'), { timeout: 120000 });
};

try {
  await connect(page, { tab: 'dfw-rates', expect: 'DFW Rates' });
  await waitBuilt('fall');
  await requireIds(page, ['dfw_rates-dr_term_type', 'dfw_rates-dr_campus', 'dfw_rates-dr_copy_url',
                          'dfw_rates-overall_plot', 'dfw_rates-course_table', 'dfw_rates-campus_table']);

  const overall = await cards('overall_finding');
  ok(overall.map((c) => c.title).join('|') === 'Latest term|Trend', `latest-term and trend cards (${overall.map((c) => c.title)})`);
  ok(/%$/.test(overall[0]?.headline || ''), `the latest term leads with its rate (${overall[0]?.headline})`);

  const bars = await plot('overall_plot');
  ok(bars && bars.names.join('|') === 'Withdrew (W)|F|D or C-|Other nonpassing', `the term bars stack the four kinds (${bars?.names})`);
  ok(bars && bars.annotations.length === bars.n[0] && bars.n[0] >= 4, `each term's bar carries its total (${bars?.annotations.length} of ${bars?.n[0]})`);

  const [conc] = await cards('concentration');
  const total = parseInt((conc?.headline || '').replace(/,/g, ''), 10);
  ok(conc && conc.parts.length === 3 && conc.parts.reduce((a, b) => a + b, 0) === total,
     `the concentration parts add to its ${total} DFW grades (${conc?.parts})`);

  const courseBars = await plot('course_bars');
  ok(courseBars && courseBars.n.reduce((a, b) => a + b, 0) === 15, `fifteen course bars (${courseBars?.n})`);
  const courses = await readReactable(page, `${NS}course_table`, { limit: 15 });
  ok(courses.rows?.length === 15, `the course table shows its first 15 rows (${courses.rows?.length})`);
  ok(courses.rows?.[0]?.[0] === '1', `the table is ranked from the course with the most DFW grades (${courses.rows?.[0]?.[0]})`);

  const change = await cards('change_cards');
  ok(change.map((c) => c.title).join('|') === 'Rising|Falling|Swinging', `rising, falling and swinging cards (${change.map((c) => c.title)})`);
  const slopes = await plot('slope_plot');
  ok(slopes && slopes.names.every((n) => ['Rising', 'Falling'].includes(n)), `the slope chart holds rising and falling courses (${slopes?.names})`);

  const strip = await plot('section_strip');
  ok(strip && strip.names[0] === "The course's rate that term", `the section strip marks each course's rate (${strip?.names})`);
  const sectionRows = await readReactable(page, `${NS}section_table`, { limit: 5 });
  ok(sectionRows.rows?.length > 0, `the section table lists tested courses (${sectionRows.rows?.length})`);

  for (const id of ['campus_table', 'college_table']) {
    const t = await readReactable(page, `${NS}${id}`, { limit: 5 });
    ok(t.rows?.length > 0 && t.rows.every((r) => r.length === 5), `${id} lists groups with a trend cell (${t.rows?.length})`);
  }

  const methods = await page.evaluate(() => [...document.querySelectorAll('#dfw_rates-method_overall, #dfw_rates-method_courses, #dfw_rates-method_changing, #dfw_rates-method_sections, #dfw_rates-method_groups')]
    .map((m) => m.textContent.trim().length));
  ok(methods.length === 5 && methods.every((n) => n > 80), `every section's method is filled (${methods})`);
  const text = await page.evaluate(() => document.querySelector('.tab-pane.active')?.innerText || '');
  ok(!/instructor:/i.test(text) && !/\binstructor name\b/i.test(text), 'no instructor is named on the page');

  await page.screenshot({ path: '/tmp/cedar-dfw-rates.png', fullPage: true });

  const fallLatest = overall[0]?.headline;
  await setInput(page, `${NS}dr_term_type`, 'spring');
  await waitBuilt('spring');
  const spring = await cards('overall_finding');
  ok(spring[0]?.headline && spring[0].headline !== fallLatest, `spring re-reads the page (${fallLatest} -> ${spring[0]?.headline})`);

  await connect(page, { tab: 'dfw-rates', search: 'tab=dfw-rates&term_type=spring&campus=EA', expect: 'DFW Rates' });
  const restored = await waitFor(page, () =>
    document.querySelector('input[name="dfw_rates-dr_term_type"]:checked')?.value === 'spring' &&
    document.getElementById('dfw_rates-dr_campus')?.value === 'EA', { timeout: 60000 });
  ok(restored, 'a link restores the term type and campus');
  if (restored) {
    await waitBuilt('spring');
    const campus = await readReactable(page, `${NS}campus_table`, { limit: 5 });
    ok(campus.rows?.length === 1 && /^EA/.test(campus.rows[0][0]), `the campus scope narrows the campus table (${campus.rows?.map((r) => r[0])})`);
  }

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
