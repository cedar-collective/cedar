// Course Dynamics > Other Courses > Courses Taken Alongside: what the analysed
// course's students take the same term, all together and then one card per
// major (R/modules/concurrent-by-major.R over get_concurrent_courses_by_major()).
//
// Asserts the tab is named Other Courses, the section opens on fall terms with,
// on each campus, a treemap of every student's courses grouped by college and
// labelled with shares of students beside an All students card, then a card
// for each of the largest majors with All other majors last; the course's own
// lab once above the cards and never in a card or the treemap; every share
// between 0 and 100%; the method; and a re-read when the term type changes.
//
//   node tests/e2e/concurrent-by-major.test.mjs

import { launch, connect, setInput, openSubTab, waitFor, waitForIdle, requireIds,
         waitForSelector } from './lib.mjs';

const COURSE = process.env.CEDAR_COURSE || 'CHEM 1215';
const fail = [];
const ok = (cond, msg) => { if (!cond) fail.push(msg); console.log(`${cond ? 'ok  ' : 'FAIL'} ${msg}`); };

const { browser, page, jsErrors } = await launch({ width: 1500, height: 1100 });

// Each campus's heading and cards, as the reader sees them.
const readPanels = () => page.evaluate(() => {
  const root = document.getElementById('cr_concurrent-panels');
  const campuses = [];
  let current = null;
  for (const el of root.querySelectorAll('h4, .meter-list, .finding-card')) {
    if (el.tagName === 'H4') { current = { heading: el.textContent.trim(), lab: null, all: null, cards: [] }; campuses.push(current); continue; }
    if (!current) continue;
    if (el.classList.contains('finding-card') && el.querySelector('.finding-card-title span')?.textContent.trim() === 'All students') {
      current.all = [...el.querySelectorAll('.meter-list dt')].map((d) => d.textContent.trim());
      continue;
    }
    if (el.classList.contains('finding-card')) {
      // textContent: the card title is uppercased by CSS, and innerText reads it so.
      const title = el.querySelector('.finding-card-title span')?.textContent.trim();
      const scope = el.querySelector('.finding-card-title .text-note')?.textContent.trim();
      const courses = [...el.querySelectorAll('.meter-list dt')].map((d) => d.textContent.trim());
      const shares = [...el.querySelectorAll('.meter-list-figure strong')].map((s) => parseFloat(s.textContent));
      current.cards.push({ title, scope, courses, shares });
    } else if (!el.closest('.finding-card')) {
      current.lab = el.textContent.trim();
    }
  }
  return campuses;
});

try {
  await connect(page, {
    tab: 'course-dynamics',
    search: ['tab=course-dynamics', 'autorun=true', 'campus=ABQ,EA',
             `course=${encodeURIComponent(COURSE)}`].join('&'),
  });
  const restored = await waitFor(page, (course) =>
    document.getElementById('cr_course')?.selectize?.getValue() === course,
  { timeout: 60000, args: [COURSE] });
  if (!restored) throw new Error(`the deep link did not restore ${COURSE} into the course picker`);
  await waitForSelector(page, '#cr_overview_metrics .cedar-snapshot-table', { timeout: 300000 });
  await waitForIdle(page, { timeout: 300000 });
  console.log(`course loaded: ${COURSE}`);

  await openSubTab(page, 'Other Courses', { timeout: 300000 });
  await waitForSelector(page, '#cr_concurrent-panels .finding-card', { timeout: 300000 });
  await waitForIdle(page);
  await requireIds(page, ['cr_concurrent-term_type', 'cr_concurrent-panels', 'cr_concurrent-method']);

  await waitFor(page, () => [...document.querySelectorAll('#cr_concurrent-panels .js-plotly-plot')]
    .some((p) => (p.data || []).some((t) => t.type === 'treemap')), { timeout: 120000 });
  const treemaps = await page.evaluate(() => [...document.querySelectorAll('#cr_concurrent-panels .js-plotly-plot')]
    .map((p) => (p.data || []).find((t) => t.type === 'treemap')).filter(Boolean)
    .map((t) => ({ roots: t.parents.filter((x) => x === '').length, leaves: t.parents.filter((x) => x !== '').length,
                   leafText: t.text.filter((x, i) => t.parents[i] !== ''), labels: t.labels })));
  const termType = await page.evaluate(() =>
    document.querySelector('input[name="cr_concurrent-term_type"]:checked')?.value);
  ok(termType === 'fall', `the section opens on fall terms (${termType})`);

  const fall = await readPanels();
  ok(treemaps.length === fall.filter((c) => c.all).length && treemaps.length > 0,
     `a treemap for each campus with an All students card (${treemaps.length})`);
  ok(treemaps.every((t) => t.roots >= 1 && t.leaves >= 1 && t.leaves <= 20),
     `each treemap groups up to 20 courses under their colleges (${treemaps.map((t) => `${t.roots}/${t.leaves}`).join(', ')})`);
  ok(treemaps.every((t) => t.leafText.every((x) => /^\d+% of students$/.test(x))),
     'every course block is labelled with its share of students');
  ok(fall.every((c) => !c.all || (c.all.length >= 1 && c.all.length <= 10)), 'the All students card lists up to ten courses');
  ok(fall.length > 0, `a heading for each campus (${fall.map((c) => c.heading.split(':')[0]).join(', ')})`);
  ok(fall.every((c) => /student-terms in .*\(Fall \d{4}/.test(c.heading)),
     'each campus heading counts the student-terms and names fall terms');
  ok(fall.every((c) => c.cards.length >= 1 && c.cards.length <= 6),
     `at most six cards a campus (${fall.map((c) => c.cards.length).join(', ')})`);
  ok(fall.every((c) => c.cards.filter((k) => k.title === 'All other majors').length <= 1
                    && (c.cards[c.cards.length - 1].title === 'All other majors'
                        || !c.cards.some((k) => k.title === 'All other majors'))),
     'All other majors is the last card on a campus');
  ok(fall.every((c) => c.cards.filter((k) => k.title !== 'All other majors').every((k) => /^[A-Z0-9]/.test(k.scope || ''))),
     'every named major shows its program codes');
  const pre = fall.flatMap((c) => c.cards).filter((k) => /\(pre-major\)$/.test(k.title));
  ok(pre.length > 0, `a pre-major is its own card (${pre.length})`);
  const shares = fall.flatMap((c) => c.cards.flatMap((k) => k.shares));
  ok(shares.length > 0 && shares.every((s) => s >= 0 && s <= 100),
     `every share is between 0 and 100% (${shares.length} bars)`);
  ok(fall.every((c) => c.cards.every((k) => k.courses.length <= 5)), 'no card lists more than five courses');

  const lab = `${COURSE}L`;
  ok(fall.some((c) => c.lab && c.lab.includes(`${lab}, its lab`)), `the lab, ${lab}, is shown above the cards`);
  ok(!fall.some((c) => c.cards.some((k) => k.courses.includes(lab)) || (c.all || []).includes(lab))
     && !treemaps.some((t) => t.labels.includes(lab)), `no card or treemap lists ${lab}`);

  // The method panel is collapsed, so read its text rather than what is drawn.
  const method = await page.evaluate(() => document.getElementById('cr_concurrent-method').textContent);
  ok(/student-term/.test(method) && /another campus/.test(method) && /lab/.test(method),
     'the method says what a student-term is, that another campus is not counted, and why the lab is apart');

  await setInput(page, 'cr_concurrent-term_type', 'spring');
  const respun = await waitFor(page, () =>
    [...document.querySelectorAll('#cr_concurrent-panels h4')].some((h) => /\(Spring \d{4}/.test(h.innerText))
    || /Try another term type/.test(document.getElementById('cr_concurrent-panels').innerText),
  { timeout: 120000 });
  ok(respun, 'choosing Spring re-reads the course on spring terms');

  ok(jsErrors.length === 0, `no uncaught JS errors (${jsErrors.length ? jsErrors.join(' | ') : 'none'})`);
} catch (e) {
  fail.push(String(e && e.message || e));
  console.log(`FAIL ${e && e.stack || e}`);
} finally {
  await browser.close();
}

if (fail.length) { console.log(`${fail.length} failed`); process.exit(1); }
console.log('all passed');
