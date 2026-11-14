// Course Dynamics > Topics: one course number's topics by term and side by side
// (R/modules/course-topics.R over build_course_topics()).
//
// Asserts the tab is shown for a course that offers topics and hidden for one
// that does not; that it opens on Fall and Spring with a chart, the pooled
// table led by every topic together on each campus, the term table and the
// titles behind each topic; and that, with the instructor gate closed, the gate
// is on the page and no topic's rates are drawn where they are withheld.
//
//   node tests/e2e/course-topics.test.mjs
//   CEDAR_TOPICS_COURSE=... CEDAR_PLAIN_COURSE=... node tests/e2e/course-topics.test.mjs

import { launch, connect, openSubTab, waitFor, waitForIdle, requireIds,
         waitForSelector, readReactable, colIndex } from './lib.mjs';

const TOPICS_COURSE = process.env.CEDAR_TOPICS_COURSE || 'FYEX 1110';
const PLAIN_COURSE = process.env.CEDAR_PLAIN_COURSE || 'CHEM 1215L';
const fail = [];
const ok = (cond, msg) => { if (!cond) fail.push(msg); console.log(`${cond ? 'ok  ' : 'FAIL'} ${msg}`); };

// Load a course through a deep link, so the app's own restore fills the picker
// and runs the report (see later-course.test.mjs for why not set cr_course).
async function loadCourse(page, course) {
  await connect(page, {
    tab: 'course-dynamics',
    search: ['tab=course-dynamics', 'autorun=true', 'campus=ABQ,EA',
             `course=${encodeURIComponent(course)}`].join('&'),
  });
  const restored = await waitFor(page, (c) =>
    document.getElementById('cr_course')?.selectize?.getValue() === c,
  { timeout: 60000, args: [course] });
  if (!restored) throw new Error(`the deep link did not restore ${course} into the course picker`);
  await waitForSelector(page, '#cr_overview_metrics .cedar-snapshot-table', { timeout: 300000 });
  await waitForIdle(page, { timeout: 300000 });
  console.log(`course loaded: ${course}`);
}

const topicsLinkShown = (page) => page.evaluate(() => {
  const link = document.querySelector('#cr_tabs a[data-value="Topics"]');
  return !!link && link.checkVisibility();
});

const { browser, page, jsErrors } = await launch({ width: 1500, height: 1100 });

try {
  await loadCourse(page, TOPICS_COURSE);
  ok(await waitFor(page, () => {
    const link = document.querySelector('#cr_tabs a[data-value="Topics"]');
    return !!link && link.checkVisibility();
  }, { timeout: 60000 }), `the Topics tab is shown for ${TOPICS_COURSE}`);

  await openSubTab(page, 'Topics', { timeout: 300000 });
  await waitForSelector(page, '#cr_topics-summary .rt-table', { timeout: 300000 });
  await waitForIdle(page);
  await requireIds(page, ['cr_topics-term_type', 'cr_topics-topics', 'cr_topics-measure',
                          'cr_topics-min_n', 'cr_topics-plot', 'cr_topics-summary',
                          'cr_topics-term_table', 'cr_topics-titles']);

  const body = await page.evaluate(() => document.getElementById('cr_topics-body').innerText);
  for (const heading of ['Topics by Term', 'Topics Side by Side', 'Topic by Term',
                         'Titles Behind Each Topic']) {
    ok(new RegExp(heading, 'i').test(body), `section "${heading}" is on the page`);
  }
  ok(/Terms run through/.test(body), 'the scope note names the edges');

  const ticked = await page.evaluate(() =>
    [...document.querySelectorAll('#cr_topics-term_type input:checked')].map((i) => i.value).sort());
  ok(ticked.join(',') === 'fall,spring', `the tab opens on Fall and Spring (${ticked.join(', ')})`);
  const drawn = await page.evaluate(() => $('#cr_topics-topics')[0].selectize.getValue());
  ok(drawn.length > 0 && drawn.length <= 5, `the chart opens on up to five topics (${drawn.length})`);
  ok(await waitFor(page, () => !!document.querySelector('#cr_topics-plot svg.main-svg'),
                   { timeout: 60000 }), 'the chart rendered');

  // Every campus's pooled rows open with every topic together.
  const summary = await readReactable(page, 'cr_topics-summary', { limit: 25 });
  const campusCol = colIndex(summary.headers, 'Campus');
  const topicCol = colIndex(summary.headers, 'Topic');
  ok(campusCol >= 0 && topicCol >= 0, `the pooled table has Campus and Topic (${summary.headers.join(' | ')})`);
  const firsts = new Map();
  for (const r of summary.rows) if (!firsts.has(r[campusCol])) firsts.set(r[campusCol], r[topicCol]);
  ok(firsts.size > 0 && [...firsts.values()].every((t) => t === 'All topics'),
     `each campus's rows open with All topics (${[...firsts].map(([c, t]) => `${c}: ${t}`).join('; ')})`);
  ok(summary.rows.length > firsts.size, `topics follow the totals (${summary.rows.length} rows)`);

  const terms = await readReactable(page, 'cr_topics-term_table', { limit: 25 });
  const termCol = colIndex(terms.headers, 'Term');
  const termTopicCol = colIndex(terms.headers, 'Topic');
  ok(terms.rows.length > 0 && terms.rows.every((r) => /^(Fall|Spring) \d{4}/.test(r[termCol])),
     `every term row is a Fall or Spring term (${terms.rows.length} rows)`);

  const titles = await readReactable(page, 'cr_topics-titles', { limit: 25 });
  const readCol = colIndex(titles.headers, 'Counted by');
  ok(readCol >= 0 && titles.rows.length > 0 &&
     titles.rows.every((r) => ['its own title', 'the same words', 'topic_titles.csv', 'no title'].includes(r[readCol])),
     `every title says how it was counted (${titles.rows.length} rows)`);

  // The gate is closed: it is on the page, a withheld rate reads "withheld",
  // and the table never prints a rate where one is withheld.
  ok(await page.evaluate(() => !!document.getElementById('cr_topics-instructor_gate-gate')),
     'the instructor gate is on the page while one-instructor topics are withheld');
  const gate = await page.evaluate(() =>
    document.getElementById('cr_topics-instructor_gate-gate')?.innerText || '');
  ok(/Access (Restricted|Unavailable)/.test(gate), 'the gate asks for the password');
  const dfwCol = colIndex(terms.headers, 'DFW');
  const dfwPctCol = colIndex(terms.headers, 'DFW %');
  ok(terms.rows.every((r) => (r[dfwCol] === 'withheld') === (r[dfwPctCol] === 'withheld')),
     'a withheld count and its rate are withheld together');
  ok(terms.rows.filter((r) => r[termTopicCol] === 'All topics').every((r) => r[dfwPctCol] !== 'withheld'),
     'every topic together is never withheld');

  const shot = '/tmp/cedar-course-topics.png';
  await page.screenshot({ path: shot, fullPage: true });
  console.log(`screenshot: ${shot}`);

  // A course with one title a term has no topics: the tab is hidden.
  await loadCourse(page, PLAIN_COURSE);
  await waitForIdle(page);
  ok(!(await topicsLinkShown(page)), `the Topics tab is hidden for ${PLAIN_COURSE}`);

  ok(jsErrors.length === 0, `no uncaught JS errors (${jsErrors.join(' ; ') || 'none'})`);
} finally {
  await browser.close();
}

console.log(fail.length ? `\n${fail.length} FAILED` : '\nall passed');
process.exit(fail.length ? 1 : 0);
