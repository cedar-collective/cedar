// Bird's Eye > DFW Rates: how lower-division DFW rates are moving and where
// to act (R/modules/dfw-rates.R over build_dfw_dashboard()).
//
// Asserts the tab opens on fall terms and builds without a run button: the
// latest-term and trend cards, the term bars split into the four kinds of DFW
// grade with each bar's total labelled, the concentration figure whose parts
// add to its headline, the course bars and table, the rising/falling/swinging
// cards with the slope chart; how far apart sections are and where the listed
// courses' sections are heading, the term-by-term line, the bars and a table
// ranked furthest apart first with each course's direction in words; the
// campus and college tables; every method slot filled; no instructor anywhere; a re-read
// when the term type changes; ABQ and EA as the opening campuses, with the
// campus table still setting every campus side by side; trend cells that are
// a line with no word; no Swings column; a From term that shortens the series;
// and a deep link that restores the term type, campus and term range.
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
  await requireIds(page, ['dfw_rates-dr_term_type', 'dfw_rates-dr_campus', 'dfw_rates-dr_from_term',
                          'dfw_rates-dr_to_term', 'dfw_rates-dr_copy_url',
                          'dfw_rates-overall_plot', 'dfw_rates-course_table', 'dfw_rates-campus_table']);
  const campuses = await page.$eval('#dfw_rates-dr_campus', (el) => [...el.selectedOptions].map((o) => o.value).sort());
  ok(campuses.join(',') === 'ABQ,EA', `the page opens on ABQ and EA (${campuses})`);

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
  ok(courses.rows?.every((r) => ['ABQ', 'EA'].includes(r[2])), `the course table holds ABQ and EA courses (${[...new Set(courses.rows?.map((r) => r[2]))]})`);
  ok(!courses.headers?.some((h) => /swings/i.test(h)), `no Swings column (${courses.headers})`);
  const trendWords = await page.evaluate(() => [...document.querySelectorAll('#dfw_rates-course_table .rt-tbody .rt-tr')]
    .map((r) => r.lastElementChild?.innerText.trim()).filter(Boolean));
  ok(trendWords.length === 0, `a trend cell is its line, with no word (${trendWords.slice(0, 3)})`);

  const change = await cards('change_cards');
  ok(change.map((c) => c.title).join('|') === 'Rising|Falling|Swinging', `rising, falling and swinging cards (${change.map((c) => c.title)})`);
  const slopes = await plot('slope_plot');
  ok(slopes && slopes.names.every((n) => ['Rising', 'Falling'].includes(n)), `the slope chart holds rising and falling courses (${slopes?.names})`);

  const section = await cards('section_finding');
  ok(section.map((c) => c.title).join('|') === 'How far apart|Direction', `how-far-apart and direction cards (${section.map((c) => c.title)})`);
  ok(/^\d+\.\d$/.test(section[0]?.headline || ''), `the first card leads with points apart (${section[0]?.headline})`);
  const spreading = parseInt((section[1]?.headline || '').replace(/,/g, ''), 10);
  ok(section[1]?.parts.length === 3 && section[1].parts[0] === spreading,
     `the direction card splits the listed courses three ways, led by the ${spreading} spreading (${section[1]?.parts})`);
  const listedCourses = (section[1]?.parts || []).reduce((a, b) => a + b, 0);
  const spreadTerms = await plot('spread_terms_plot');
  ok(spreadTerms && spreadTerms.names.join('|') === 'Every course' && spreadTerms.n[0] >= 4,
     `the term-by-term line reads every course over ${spreadTerms?.n[0]} terms (${spreadTerms?.names})`);
  const directions = ['Spreading', 'Consolidating', 'No clear change'];
  const spreadBars = await plot('spread_course_bars');
  const nBars = (spreadBars?.n || []).reduce((a, b) => a + b, 0);
  ok(spreadBars && spreadBars.names.every((n) => directions.includes(n)) && nBars === Math.min(15, listedCourses),
     `a bar for each of the ${Math.min(15, listedCourses)} courses furthest apart, by direction (${nBars}: ${spreadBars?.names})`);
  const sectionTable = await readReactable(page, `${NS}section_table`, { limit: 15 });
  // Headers are read as drawn, in capitals.
  const direction = (sectionTable.headers || []).findIndex((h) => /^direction$/i.test(h));
  ok(sectionTable.rows?.length > 0 && sectionTable.rows.every((r) => directions.includes(r[direction])),
     `the section table names each course's direction (${[...new Set(sectionTable.rows?.map((r) => r[direction]))]})`);
  const points = (sectionTable.rows || []).map((r) => parseFloat(r[2]));
  ok(points.length > 1 && points.every((v, i) => i === 0 || v <= points[i - 1]),
     `the section table runs from the course furthest apart (${points.slice(0, 3)})`);
  const sectionPages = await page.$eval('#dfw_rates-section_table .rt-page-info', (el) => el.innerText).catch(() => '');
  ok(new RegExp(`of ${listedCourses} rows`).test(sectionPages.replace(/,/g, '')),
     `the section table lists the ${listedCourses} courses the direction card counts (${sectionPages})`);

  for (const id of ['campus_table', 'college_table']) {
    const t = await readReactable(page, `${NS}${id}`, { limit: 5 });
    ok(t.rows?.length > 0 && t.rows.every((r) => r.length === 5), `${id} lists groups with a trend cell (${t.rows?.length})`);
  }
  const campusRows = await readReactable(page, `${NS}campus_table`, { limit: 20 });
  ok(campusRows.rows?.length > 2, `the campus table sets every campus side by side, not only ABQ and EA (${campusRows.rows?.length})`);

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

  const springTerms = (await plot('overall_plot'))?.n[0];
  const terms = await page.$eval('#dfw_rates-dr_from_term', (el) => Object.keys(el.selectize?.options || {}));
  const springs = terms.filter((t) => t.endsWith('10')).sort();
  const from = springs[springs.length - 3];
  await setInput(page, `${NS}dr_from_term`, from);
  await waitForIdle(page, { timeout: 300000 });
  const shorter = await waitFor(page, (n) => {
    const root = document.getElementById('dfw_rates-overall_plot');
    const p = root?.classList.contains('js-plotly-plot') ? root : root?.querySelector('.js-plotly-plot');
    return p?.data && (p.data[0].x || []).length < n;
  }, { timeout: 300000, args: [springTerms] });
  ok(shorter, `a later From term (${from}) shortens the series from ${springTerms} terms`);

  await connect(page, { tab: 'dfw-rates', search: `tab=dfw-rates&term_type=spring&campus=EA&from_term=${from}`, expect: 'DFW Rates' });
  const restored = await waitFor(page, (f) =>
    document.querySelector('input[name="dfw_rates-dr_term_type"]:checked')?.value === 'spring' &&
    [...(document.getElementById('dfw_rates-dr_campus')?.selectedOptions || [])].map((o) => o.value).join(',') === 'EA' &&
    document.getElementById('dfw_rates-dr_from_term')?.value === f, { timeout: 60000, args: [from] });
  ok(restored, 'a link restores the term type, campus and From term');
  if (restored) {
    await waitBuilt('spring');
    const eaCourses = await readReactable(page, `${NS}course_table`, { limit: 10 });
    ok(eaCourses.rows?.length > 0 && eaCourses.rows.every((r) => r[2] === 'EA'), `the campus scope narrows the course table (${[...new Set(eaCourses.rows?.map((r) => r[2]))]})`);
    const campus = await readReactable(page, `${NS}campus_table`, { limit: 20 });
    ok(campus.rows?.length > 1, `the campus table still sets every campus side by side (${campus.rows?.map((r) => r[0])})`);
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
