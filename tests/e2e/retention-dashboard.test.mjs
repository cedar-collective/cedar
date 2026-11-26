// Bird's Eye > Retention: are students coming back, and who is not
// (R/modules/retention-dashboard.R over build_retention_dashboard()).
//
// Asserts the tab opens on fall terms and undergraduates and builds without a
// run button: the data scope bar saying who is counted (the level's students
// in the latest term, first-time, transfer and start-not-on-record students
// adding to them, and the levels left out); the return line with a label a term and the dashed trend line
// labelled with its slope and verdict (no cards), the warning-sign table (a late withdrawal and a DFW grade, each with
// and without), the classification and college tables with a trend line and
// no word, the course table, every method slot filled; a re-read when the
// term type or the student level changes, the courses-by-GPA section with
// the rest of the page (ISSUES M67); and the home card's link.
//
// The two entering-class sections (R/modules/retention-entering-classes.R, the
// First Year page until 2026-11): a line for each of four semesters with a
// point a class, its lead sentence and its "How this is counted" dialog; the
// summer after the first spring; a re-read when who a class holds changes;
// their place on the page (the classes before the year-by-year pace section,
// each summer section beside the other); and the old ?tab=first-year link
// opening this page, with no First Year page or card left.
//
//   node tests/e2e/retention-dashboard.test.mjs

import { launch, connect, setInput, waitFor, waitForIdle, requireIds, waitForSelector,
         readReactable, outputsInError } from './lib.mjs';

const fail = [];
const ok = (cond, msg) => { if (!cond) fail.push(msg); console.log(`${cond ? 'ok  ' : 'FAIL'} ${msg}`); };
const NS = 'retention_dashboard-';
const CL = `${NS}classes-`;  // the entering-class sections, a module inside the page

const { browser, page, jsErrors } = await launch({ width: 1500, height: 1100 });

const line = () => page.evaluate((el) => {
  const root = document.getElementById(el);
  const p = root?.classList.contains('js-plotly-plot') ? root : root?.querySelector('.js-plotly-plot');
  if (!p || !p.data) return null;
  const ann = (p.layout.annotations || []).map((a) => a.text);
  return { n: (p.data[0].x || []).length, x: p.data[0].x || [], y: p.data[0].y || [], text: p.data[0].text || [],
           trend: p.data.find((d) => d.name === 'Trend') || null, label: ann.join(' | ') };
}, `${NS}overall_plot`);

const waitBuilt = async () => {
  await waitFor(page, () => {
    const r = document.getElementById('retention_dashboard-overall_plot');
    const p = r?.classList.contains('js-plotly-plot') ? r : r?.querySelector('.js-plotly-plot');
    return !!(p && p.data && p.data.length);
  }, { timeout: 300000 });
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

  // Who is counted, as facts under the controls.
  const readScope = () => page.evaluate((ns) => [...document.querySelectorAll(`#${ns}scope .scope-chip`)].map((c) => ({
    key: c.querySelector('.scope-chip-key')?.textContent.trim(), val: c.querySelector('.scope-chip-val')?.textContent.trim() })), NS);
  const num = (text) => parseInt(String(text || '').replace(/,/g, ''), 10);
  await waitForSelector(page, `#${NS}scope .scope-chip`, { timeout: 120000 });
  const scope = await readScope();
  const keys = scope.map((c) => c.key);
  ok(/^Counted, Fall \d{4}$/.test(keys[0] || '') && keys.slice(1, 4).join('|') === 'First-time students|Transfer students|Start not on record',
     `the scope bar says who is counted and how they started (${keys})`);
  const started = scope.slice(1, 4).map((c) => num(c.val));
  ok(started.every((n) => n >= 0) && started.reduce((a, b) => a + b, 0) === num(scope[0]?.val),
     `first-time, transfer and start-not-on-record students add to those counted (${started} of ${num(scope[0]?.val)})`);
  ok(started[1] > 0, `transfer students are among those counted (${started[1]})`);
  const leftOut0 = scope.find((c) => c.key === 'Not counted');
  ok(leftOut0 && /^students at another level: \D+ [\d,]+/.test(leftOut0.val), `the levels left out are named with their counts (${leftOut0?.val.slice(0, 80)})`);

  const noCards = await page.evaluate(() => !document.querySelector('#retention_dashboard-overall_finding .finding-card'));
  ok(noCards, 'the chart carries the finding: no cards');
  const lead = await page.$eval(`#${NS}overall_finding`, (el) => el.innerText.trim());
  ok(/^The share of fall students who came back the next regular term is (rising|falling|not clearly rising or falling): /.test(lead),
     `the section opens on the verdict over the terms (${lead.slice(0, 60)}…)`);
  const ln = await line();
  // Each point is its own counts: the rate drawn is came back over students read, as the hover states them.
  const drawn = await page.evaluate((el) => {
    const r = document.getElementById(el);
    const p = r?.classList.contains('js-plotly-plot') ? r : r?.querySelector('.js-plotly-plot');
    const d = p?.data?.[0];
    return (d?.hovertext || []).map((h, i) => {
      const m = String(h).replace(/,/g, '').match(/([0-9]+) of ([0-9]+) came back/);
      return m ? Math.abs(100 * Number(m[1]) / Number(m[2]) - d.y[i]) : null;
    });
  }, `${NS}overall_plot`);
  ok(drawn.length >= 3 && drawn.every((gap) => gap !== null && gap < 0.05),
     `every term's rate is its hover's counts divided (${drawn.length} terms)`);
  ok(ln && ln.n >= 3 && ln.text.length === ln.n, `the return line labels each of its ${ln?.n} terms`);
  ok(ln?.trend && ln.trend.x.length === 2 && ln.trend.line?.dash === 'dash',
     'the trend is a dashed line from the first term to the last');
  ok(/points a year/.test(ln?.label || '') && /(rising|falling|steady)/.test(ln?.label || ''),
     `the trend line is labelled with its slope and verdict (${ln?.label})`);

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

  // Courses by GPA band: the sentence counts what was read and what chance
  // would list, and each list sets the lowest band beside the other students.
  await waitFor(page, () => !!document.querySelector(`#${NS}bands_harder .rt-tbody`), { timeout: 240000 });
  const bandLead = await page.$eval(`#${NS}bands_finding`, (el) => el.innerText);
  ok(/Of the \d[\d,]* courses? read/.test(bandLead) && /Chance alone would put/.test(bandLead),
     `the by-band sentence counts the courses read and chance (${bandLead.slice(0, 60)})`);
  const harder = await readReactable(page, `${NS}bands_harder`, { limit: 5 });
  ok(harder.rows?.every((r) => r.length === 9), `the harder list has its nine columns (${harder.rows?.length} rows)`);

  const methods = await page.evaluate((ns) => ['method_overall', 'method_signs', 'method_groups', 'method_courses']
    .map((id) => document.getElementById(ns + id)?.textContent.trim().length || 0), NS);
  ok(methods.every((n) => n > 80), `every section's method is filled (${methods})`);
  const who = await page.$eval(`#${NS}method_overall`, (el) => el.textContent);
  ok(/transfer student is counted/i.test(who) && /another level is not counted/i.test(who),
     'the first method note says transfer students are counted and other levels are not');

  await page.screenshot({ path: '/tmp/cedar-retention.png', fullPage: true });

  const plotX = () => {
    const r = document.getElementById('retention_dashboard-overall_plot');
    const p = r?.classList.contains('js-plotly-plot') ? r : r?.querySelector('.js-plotly-plot');
    return p?.data?.[0] ? JSON.stringify([p.data[0].x, p.data[0].y]) : '';
  };
  // Each fall's classes, year by year, and their pace.
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

  const paceMethod = await page.$eval(`#${NS}method_pace`, (el) => el.textContent.trim().length);
  ok(paceMethod > 80, 'the pace section says how it is counted');
  // Students behind on credits each spring, and what the summer did.
  await waitFor(page, plotTraces, { timeout: 300000, args: [`${NS}pace_summer_plot`] });
  const catchUp = await page.evaluate(plotTraces, `${NS}pace_summer_plot`);
  ok(catchUp?.length === 3 && catchUp[2] === 'Summer course, caught up', `the students behind are drawn in three parts (${catchUp})`);
  const catchUpLead = await page.$eval(`#${NS}pace_summer_finding`, (el) => el.innerText.trim());
  ok(/had caught up by the fall\.$/.test(catchUpLead), `the section opens on the springs read (${catchUpLead.slice(0, 50)}…)`);
  await waitForSelector(page, `#${NS}pace_summer_courses .rt-tbody`);
  const behindCourses = await readReactable(page, `${NS}pace_summer_courses`, { limit: 5 });
  ok(behindCourses.rows.length > 0 && behindCourses.rows[0].length === 5, `their summer courses are listed with titles (${behindCourses.rows.length})`);
  const catchUpMethod = await page.$eval(`#${NS}method_pace_summer`, (el) => el.textContent.trim().length);
  ok(catchUpMethod > 80, 'the summer and pace section says how it is counted');

  // Each entering class, semester by semester (was the First Year page).
  const classLines = () => page.evaluate((el) => {
    const root = document.getElementById(el);
    const p = root?.classList.contains('js-plotly-plot') ? root : root?.querySelector('.js-plotly-plot');
    if (!p || !p.data || !p.data.length) return null;
    return { names: p.data.map((d) => d.name), x: p.data[0].x || [], y: JSON.stringify(p.data.map((d) => d.y)) };
  }, `${CL}milestones_plot`);
  await waitFor(page, plotTraces, { timeout: 300000, args: [`${CL}milestones_plot`] });
  await requireIds(page, [`${CL}entry`, `${CL}milestones_plot`, `${CL}summer_plot`, `${CL}summer_courses`]);
  const entry = await page.$eval(`input[name="${CL}entry"]:checked`, (el) => el.value);
  ok(entry === 'first_time', `the entering classes open on first-time students (${entry})`);
  const firstClasses = await classLines();
  ok(firstClasses && firstClasses.names.length === 4 && /2nd semester/.test(firstClasses.names[0]),
     `a line for each of four semesters (${firstClasses?.names.join(', ')})`);
  ok(firstClasses?.x.length >= 2 && firstClasses.x.every((x) => /^Fall /.test(x)),
     `a point for each fall entering class (${firstClasses?.x.length})`);
  // Each point is its own counts: still here over the class, as the hover states them.
  const classPoints = await page.evaluate((el) => {
    const r = document.getElementById(el);
    const p = r?.classList.contains('js-plotly-plot') ? r : r?.querySelector('.js-plotly-plot');
    return (p?.data || []).flatMap((d) => (d.hovertext || []).map((h, i) => {
      const m = String(h).replace(/,/g, '').match(/: ([0-9]+) of ([0-9]+) \(/);
      return m ? Math.abs(100 * Number(m[1]) / Number(m[2]) - d.y[i]) : null;
    }));
  }, `${CL}milestones_plot`);
  ok(classPoints.length >= 4 && classPoints.every((gap) => gap !== null && gap < 0.05),
     `every class point is its hover's counts divided (${classPoints.length} points)`);
  const classLead = await page.$eval(`#${CL}milestones_finding`, (el) => el.innerText.trim());
  ok(/^A year on/.test(classLead) && /in each of the \d+ classes from/.test(classLead) && /between [0-9.]+% and [0-9.]+%/.test(classLead),
     `the entering classes open on the range over every class (${classLead.slice(0, 60)}…)`);
  // The third semester of a first-time fall class and the start of its second
  // year are one moment, read by one function: the two sections agree on it.
  await setInput(page, `${NS}pace_step`, '2');
  await waitFor(page, (id) => /At the start of their second year/.test(document.getElementById(id)?.textContent || ''),
                { timeout: 120000, args: [`${NS}pace_lead`] });
  const sameMoment = await page.evaluate((classesId, paceId) => {
    const plot = (id) => { const r = document.getElementById(id); return r?.classList.contains('js-plotly-plot') ? r : r?.querySelector('.js-plotly-plot'); };
    const third = plot(classesId)?.data?.find((d) => /^3rd semester/.test(d.name));
    const bars = plot(paceId)?.data || [];
    if (!third || !bars.length) return null;
    // Still enrolled or with a degree: every part of a bar but the last ("Not enrolled").
    return bars[0].x.map((cls, i) => {
      const here = bars.slice(0, -1).reduce((sum, part) => sum + part.y[i], 0);
      const at = third.x.indexOf(cls);
      return at < 0 ? null : Math.abs(here - third.y[at]);
    }).filter((gap) => gap !== null);
  }, `${CL}milestones_plot`, `${NS}pace_plot`);
  ok(sameMoment && sameMoment.length >= 2 && sameMoment.every((gap) => gap < 0.05),
     `a class's 3rd semester is its second year's bar less those not enrolled (${sameMoment?.length} classes)`);
  await setInput(page, `${NS}pace_step`, '4');
  // How this is counted is a link after the section's sentence that opens a dialog: the idea first, then this view's counts.
  const classMethod = await page.$eval(`#${CL}method_milestones`, (el) => el.textContent.trim().length);
  ok(classMethod > 80, 'the entering-class section says how it is counted');
  const panel = `details.cedar-method-panel:has(#${CL}method_milestones)`;
  const shown = () => page.$eval(panel, (el) => {
    const body = el.querySelector('.panel-body');
    const box = body.getBoundingClientRect();
    return { open: el.open, visible: body.checkVisibility(), fixed: getComputedStyle(body).position === 'fixed',
             centred: Math.abs((box.left + box.right) / 2 - window.innerWidth / 2) < 4,
             idea: el.querySelector('.cedar-method-idea')?.innerText || '', link: el.querySelector('summary').innerText.trim(),
             size: parseFloat(getComputedStyle(body).fontSize) };
  });
  const closed = await shown();
  ok(!closed.open && !closed.visible && closed.link === 'How this is counted', 'how it is counted is a closed link beside the sentence');
  await page.click(`${panel} > summary`);
  await waitFor(page, (sel) => document.querySelector(sel).open, { args: [panel] });
  const opened = await shown();
  ok(opened.visible && opened.fixed && opened.centred && opened.size >= 16, `the link opens a centred dialog in readable type (${opened.size}px)`);
  ok(/follow them as one class/.test(opened.idea), 'the dialog opens on the section\'s idea in plain words');
  await page.keyboard.press('Escape');
  await waitFor(page, (sel) => !document.querySelector(sel).open, { args: [panel] });
  ok(!(await shown()).visible, 'Escape closes it');

  // The summer after the first spring: back in the fall, by taking a summer course or not.
  await waitFor(page, plotTraces, { timeout: 300000, args: [`${CL}summer_plot`] });
  const summerLines = await page.evaluate(plotTraces, `${CL}summer_plot`);
  ok(JSON.stringify(summerLines) === '["Took a summer course","Did not"]', `the first-summer chart has a line for each group (${summerLines})`);
  const summerLead = await page.$eval(`#${CL}summer_finding`, (el) => el.innerText.trim());
  ok(/back in the fall/.test(summerLead) && /not what it causes\.$/.test(summerLead),
     `the first-summer section opens on the classes read, with its warning (${summerLead.slice(0, 50)}…)`);
  await waitForSelector(page, `#${CL}summer_courses .rt-tbody`);
  const summerCourses = await readReactable(page, `${CL}summer_courses`, { limit: 5 });
  ok(summerCourses.rows.length > 0 && summerCourses.rows[0].length === 5, `the first-summer courses are listed with titles (${summerCourses.rows.length})`);
  const summerMethod = await page.$eval(`#${CL}method_summer`, (el) => el.textContent.trim().length);
  ok(summerMethod > 80, 'the first-summer section says how it is counted');

  // Where the sections sit: the classes semester by semester, then year by
  // year; the two summer sections together; every heading once.
  const headings = await page.evaluate(() => [...document.querySelectorAll('.tab-pane.active .cedar-dashboard-section-title')]
    .map((h) => h.innerText.trim()));
  const at = (title) => headings.indexOf(title);
  ok(at('Each Entering Class, Semester by Semester') >= 0 &&
     at('Still Here, and Moving Forward?') === at('Each Entering Class, Semester by Semester') + 1,
     `the classes are read semester by semester, then year by year (${headings.join(' | ')})`);
  ok(at('Summer and Staying on Pace') === at('The Summer After the First Spring') + 1, 'the two summer sections sit together');
  ok(new Set(headings).size === headings.length && headings.length === 9, `nine sections, each heading once (${headings.length})`);

  await setInput(page, `${CL}entry`, 'transfer');
  const classesReread = await waitFor(page, (id, before) => {
    const r = document.getElementById(id);
    const p = r?.classList.contains('js-plotly-plot') ? r : r?.querySelector('.js-plotly-plot');
    return !!p?.data?.length && JSON.stringify(p.data.map((d) => d.y)) !== before;
  }, { timeout: 300000, args: [`${CL}milestones_plot`, firstClasses?.y] });
  ok(classesReread, 'new transfer students re-read the entering classes');
  await waitForIdle(page, { timeout: 300000 });
  const overallAfter = await line();
  ok(JSON.stringify(overallAfter?.y) === JSON.stringify(ln?.y), 'who a class holds changes the entering classes only: the return line is as it was');
  ok((await outputsInError(page, NS)).length === 0, `no output in error for transfer classes (${(await outputsInError(page, NS)).join('; ')})`);
  await setInput(page, `${CL}entry`, 'first_time');
  await waitForIdle(page, { timeout: 300000 });
  ok((await outputsInError(page, NS)).length === 0, `no output in error on fall terms (${(await outputsInError(page, NS)).join('; ')})`);
  await setInput(page, `${NS}term_type`, 'spring');
  const reread = await waitFor(page, () => {
    const r = document.getElementById('retention_dashboard-overall_plot');
    const p = r?.classList.contains('js-plotly-plot') ? r : r?.querySelector('.js-plotly-plot');
    return (p?.data?.[0]?.x || []).every((x) => /Spring/.test(x)) && (p?.data?.[0]?.x || []).length > 0;
  }, { timeout: 300000 });
  ok(reread, 'spring re-reads the page on spring terms');
  await waitBuilt();
  // The entering classes read the page's term type: spring classes now.
  const springClasses = await waitFor(page, (id) => {
    const r = document.getElementById(id);
    const p = r?.classList.contains('js-plotly-plot') ? r : r?.querySelector('.js-plotly-plot');
    const x = p?.data?.[0]?.x || [];
    return x.length > 0 && x.every((cls) => /^Spring /.test(cls));
  }, { timeout: 300000, args: [`${CL}milestones_plot`] });
  ok(springClasses, 'spring re-reads the entering classes as spring classes');

  const leftOut = await page.$eval(`#${NS}method_overall`, (el) => el.textContent);
  ok(/in the summer after it/.test(leftOut), 'the method note counts summer finishers as finished');
  ok((await outputsInError(page, NS)).length === 0, `no output in error on spring terms (${(await outputsInError(page, NS)).join('; ')})`);

  const undergrad = await page.evaluate(plotX);
  // The courses-by-GPA sentence for undergraduates, to set beside the next level's.
  const bandText = () => document.getElementById('retention_dashboard-bands_finding')?.innerText.trim() || '';
  await waitFor(page, bandText, { timeout: 240000 });
  const undergradBands = await page.evaluate(bandText);
  // The second level in student_levels.csv (graduate at UNM). A home campus
  // changes little at the undergraduate level: nearly all are ABQ students.
  const second = await page.$eval(`#${NS}level`, (el) => Object.values(el.selectize?.options || {})
    .sort((a, b) => a.$order - b.$order).map((o) => o.value)[1]);
  await setInput(page, `${NS}level`, second);
  const narrowed = await waitFor(page, (f) => {
    const r = document.getElementById('retention_dashboard-overall_plot');
    const p = r?.classList.contains('js-plotly-plot') ? r : r?.querySelector('.js-plotly-plot');
    const now = p?.data?.[0] ? JSON.stringify([p.data[0].x, p.data[0].y]) : '';
    return now && now !== f;
  }, { timeout: 300000, args: [undergrad] });
  ok(narrowed, `another student level (${second}) re-reads the page`);
  await waitFor(page, (ns, before) => {
    const val = document.querySelector(`#${ns}scope .scope-chip-val`);
    return !!val && val.textContent.trim() !== before;
  }, { timeout: 120000, args: [NS, scope[0]?.val] });
  const [counted] = await readScope();
  ok(/^Counted, Spring \d{4}$/.test(counted?.key || '') && counted.val !== scope[0]?.val,
     `the scope bar re-reads with the level and term type (${counted?.key}: ${counted?.val})`);
  // The section reads the page's students: another level is another reading.
  const bandsReread = await waitFor(page, (before) => {
    const now = document.getElementById('retention_dashboard-bands_finding')?.innerText.trim() || '';
    return !!now && now !== before;
  }, { timeout: 240000, args: [undergradBands] });
  ok(bandsReread, `the courses-by-GPA section re-reads with the student level (was: ${undergradBands.slice(0, 40)})`);

  await connect(page, { tab: 'home' });
  const card = await page.evaluate(() => [...document.querySelectorAll('a[href]')].some((a) => a.getAttribute('href') === '?tab=retention'));
  ok(card, 'the home page links to Retention');
  // First Year is no longer a page: no card, no menu item, and its link opens Retention.
  const gone = await page.evaluate(() => ({
    card: [...document.querySelectorAll('a[href]')].some((a) => a.getAttribute('href') === '?tab=first-year'),
    menu: !!document.querySelector('.navbar [data-value="First Year"]') }));
  ok(!gone.card && !gone.menu, 'no First Year card or menu item');
  await connect(page, { tab: 'first-year', expect: 'Retention' });
  await waitFor(page, plotTraces, { timeout: 300000, args: [`${CL}milestones_plot`] });
  ok(true, 'the old First Year link opens Retention, with the entering classes on it');

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
