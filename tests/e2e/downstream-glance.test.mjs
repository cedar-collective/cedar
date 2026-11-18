// Course Dynamics > Downstream > At a Glance: the five steps of what happens
// to a course's students, one card each, read off the other Downstream views
// (R/features/downstream-glance.R).
//
// Asserts Downstream opens on At a Glance, its five cards arrive in story
// order and each settles (ready, or saying why not) without a click, a ready
// card draws its figure and names its campus, and a card's link opens its
// subtab.
//
//   node tests/e2e/downstream-glance.test.mjs

// Each step's link id is built from its step (paste0("cr_glance_go_", step), server.R):
// check-ids-ignore: cr_glance_go_coming_back

import { launch, connect, setInput, runAndWait, openSubTab, waitFor,
         waitForIdle, requireIds, waitForSelector } from './lib.mjs';

const COURSE = process.env.CEDAR_COURSE_X || 'HIST 1110';
const STEPS = ['In the Course', 'Coming Back', 'Against Non-Takers', 'Next Courses', 'Prepared for It'];
const fail = [];
const ok = (cond, msg) => { if (!cond) fail.push(msg); console.log(`${cond ? 'ok  ' : 'FAIL'} ${msg}`); };

const { browser, page, jsErrors } = await launch({ width: 1500, height: 1100 });

try {
  await connect(page, { tab: 'course-dynamics' });
  await requireIds(page, ['cr_campus', 'cr_course', 'cr_generate_button']);
  await setInput(page, 'cr_campus', ['ABQ', 'EA']);
  await setInput(page, 'cr_course', COURSE);
  await runAndWait(page, 'cr_generate_button');
  console.log(`course loaded: ${COURSE}`);

  await openSubTab(page, 'Downstream', { timeout: 300000 });
  await waitForSelector(page, '#cr_downstream_glance_ui .downstream-glance', { timeout: 300000 });
  const active = await page.evaluate(() =>
    document.querySelector('#cr_downstream_view .nav-link.active')?.textContent.trim());
  ok(active === 'At a Glance', `Downstream opens on At a Glance (${active})`);

  // Every step settles on its own: none is left running.
  const settled = await waitFor(page, () => {
    const cards = [...document.querySelectorAll('#cr_downstream_glance_ui .downstream-glance-step')];
    return cards.length === 5 && cards.every((c) => !c.classList.contains('downstream-glance-step--pending'));
  }, { timeout: 600000 });
  ok(settled, 'all five steps settle without a click');
  await waitForIdle(page, { timeout: 300000 });

  const cards = await page.evaluate(() =>
    [...document.querySelectorAll('#cr_downstream_glance_ui .downstream-glance-step')].map((c) => ({
      title: c.querySelector('.finding-card-title span')?.textContent.trim(),
      scope: c.querySelector('.finding-card-title .text-note')?.textContent.trim() || null,
      ready: c.classList.contains('downstream-glance-step--ready'),
      bars: c.querySelectorAll('.compare-bars .meter-bar').length,
      text: c.innerText,
    })));
  ok(cards.map((c) => c.title.replace(/^\d+\. /, '')).join('|') === STEPS.join('|'),
     `the steps run in story order (${cards.map((c) => c.title).join(' | ')})`);
  ok(cards[0].ready && cards[1].ready, 'the course and its returners are always ready');
  for (const c of cards.filter((x) => x.ready)) {
    ok(c.bars > 0, `${c.title} draws its figure (${c.bars} bars)`);
  }
  for (const c of cards.filter((x) => x.ready && !/Against Non-Takers|Prepared/.test(x.title))) {
    ok(!!c.scope, `${c.title} names the campus it reads (${c.scope})`);
  }
  ok(cards.every((c) => /\S/.test(c.text)), 'every step says something, ready or not');

  // A step opens its subtab.
  await runAndWait(page, 'cr_glance_go_coming_back', { timeout: 300000 });
  const opened = await page.evaluate(() =>
    document.querySelector('#cr_downstream_view .nav-link.active')?.textContent.trim());
  ok(opened === 'Coming Back', `the Coming Back step opens its subtab (${opened})`);

  await openSubTab(page, 'At a Glance', { timeout: 300000 });
  const shot = '/tmp/cedar-downstream-glance.png';
  await page.screenshot({ path: shot, fullPage: true });
  console.log(`screenshot: ${shot}`);

  ok(jsErrors.length === 0, `no uncaught JS errors (${jsErrors.join(' ; ') || 'none'})`);
} finally {
  await browser.close();
}

console.log(fail.length ? `\n${fail.length} FAILED` : '\nall passed');
process.exit(fail.length ? 1 : 0);
