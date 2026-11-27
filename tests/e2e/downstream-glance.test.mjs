// Course Dynamics > Downstream > At a Glance: the five steps of what happens
// to a course's students, one card each, read off the other Downstream views
// (R/features/downstream-glance.R).
//
// Asserts Downstream opens on At a Glance, its five cards arrive in story
// order and each settles (ready, or saying why not) without a click, a ready
// card draws its figure and names its campus, opening a subtab At a Glance
// already ran does not run it again, a card's link opens its subtab, which
// runs once, and a second session reads the first one's results without
// building them again (they are shared: cedar_shared_result()).
//
//   node tests/e2e/downstream-glance.test.mjs

// Each step's link id is built from its step (paste0("cr_glance_go_", step), server.R):
// check-ids-ignore: cr_glance_go_coming_back

import { launch, connect, setInput, runAndWait, openSubTab, appReloads, explainAppReload,
         waitForIdle, requireIds, waitForSelector } from './lib.mjs';

const COURSE = process.env.CEDAR_COURSE_X || 'HIST 1110';
const STEPS = ['In the Course', 'Coming Back', 'Against Non-Takers', 'Next Courses', 'Did Passing It First Help?'];
const fail = [];
const ok = (cond, msg) => { if (!cond) fail.push(msg); console.log(`${cond ? 'ok  ' : 'FAIL'} ${msg}`); };

// What the page's loading overlay says from here on, and how long the server
// worked with that overlay down. At a Glance runs the other views while their
// subtabs, and the overlays on them, are hidden, so their waits have to show
// on the page's (ISSUES I82). A comparison an earlier session already built
// is read with no wait at all (they are shared), so the labels themselves
// cannot be required; the time spent working unannounced can be compared.
const watchWaits = (pg) => pg.evaluate(() => {
  const label = document.getElementById('cr-loading-label');
  const overlay = document.getElementById('cr-loading-overlay');
  window.__crLabels = [];
  window.__crUnannounced = 0;
  new MutationObserver(() => window.__crLabels.push(label.textContent))
    .observe(label, { childList: true, characterData: true, subtree: true });
  setInterval(() => {
    const busy = document.documentElement.classList.contains('shiny-busy');
    const up = overlay.checkVisibility() && overlay.style.display !== 'none';
    if (busy && !up) window.__crUnannounced += 200;
  }, 200);
});
const readWaits = (pg) => pg.evaluate(() => ({
  labels: [...new Set(window.__crLabels.map((t) => t.replace(/ \(.*$/, '')))],
  unannounced: window.__crUnannounced / 1000,
}));

const { browser, page, jsErrors } = await launch({ width: 1500, height: 1100 });

try {
  await connect(page, { tab: 'course-dynamics' });
  await requireIds(page, ['cr_campus', 'cr_course', 'cr_generate_button']);
  await setInput(page, 'cr_campus', ['ABQ', 'EA']);
  await setInput(page, 'cr_course', COURSE);
  await runAndWait(page, 'cr_generate_button');
  console.log(`course loaded: ${COURSE}`);

  await watchWaits(page);
  await openSubTab(page, 'Downstream', { timeout: 300000 });
  await waitForSelector(page, '#cr_downstream_glance_ui .downstream-glance', { timeout: 300000 });
  const active = await page.evaluate(() =>
    document.querySelector('#cr_downstream_view .nav-link.active')?.textContent.trim());
  ok(active === 'At a Glance', `Downstream opens on At a Glance (${active})`);

  // Every step settles on its own: none is left running. Each step's arrival
  // is logged, seconds after the tab opened, so a slow analysis is visible.
  const opened0 = Date.now();
  const arrived = {};
  const pendingSteps = () => page.evaluate(() =>
    [...document.querySelectorAll('#cr_downstream_glance_ui .downstream-glance-step')].map((c) => ({
      title: c.querySelector('.finding-card-title span')?.textContent.trim(),
      pending: c.classList.contains('downstream-glance-step--pending'),
    })));
  let settled = false;
  while (Date.now() - opened0 < 900000) {
    if (appReloads(page) > 0) throw explainAppReload(page, new Error('waiting for the five steps'));
    const steps = await pendingSteps().catch(() => []);
    for (const st of steps) {
      if (!st.pending && !(st.title in arrived)) {
        arrived[st.title] = Math.round((Date.now() - opened0) / 1000);
        console.log(`     ${st.title} settled after ${arrived[st.title]}s`);
      }
    }
    if (steps.length === 5 && steps.every((st) => !st.pending)) { settled = true; break; }
    await waitForIdle(page, { timeout: 15000 }).catch(() => {});
  }
  const still = (await pendingSteps().catch(() => [])).filter((st) => st.pending).map((st) => st.title);
  ok(settled, `all five steps settle without a click (${still.length ? `still waiting: ${still.join(', ')}` : 'none waiting'})`);
  await waitForIdle(page, { timeout: 300000 });

  // Judged against the second session below, which builds nothing.
  const first = await readWaits(page);
  console.log(`     waits shown: ${first.labels.join(' | ') || 'none'}; ${first.unannounced}s worked with no wait up`);

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
  for (const c of cards.filter((x) => x.ready && !/Against Non-Takers|Did Passing/.test(x.title))) {
    ok(!!c.scope, `${c.title} names the campus it reads (${c.scope})`);
  }
  ok(cards.every((c) => /\S/.test(c.text)), 'every step says something, ready or not');

  // At a Glance ran Against Non-Takers, Next Courses and Prepared for It on
  // their defaults; opening their subtabs shows those results, never a second
  // run (ISSUES I66: a rendered button's 0 changed the run key). Every
  // notification shown from here on is recorded by its element id.
  await page.evaluate(() => {
    window.__cedarRuns = {};
    const scan = () => document.querySelectorAll('.shiny-notification').forEach((n) => {
      window.__cedarRuns[n.id || n.outerHTML.length] = n.innerText;
    });
    new MutationObserver(scan).observe(document.body, { childList: true, subtree: true, characterData: true });
  });
  const runs = (re) => page.evaluate((src) =>
    Object.values(window.__cedarRuns).filter((t) => new RegExp(src).test(t)).length, re.source);
  for (const view of ['Against Non-Takers', 'Next Courses']) {
    await openSubTab(page, view, { timeout: 300000 });
    await waitForIdle(page, { timeout: 300000 });
  }
  const reruns = await runs(/Comparing takers|Following students into the later course|Building sequence comparison/);
  ok(reruns === 0, `opening the subtabs At a Glance already ran does not run them again (${reruns} runs)`);

  // A step opens its subtab; Coming Back, which At a Glance does not run,
  // runs once when it opens.
  await runAndWait(page, 'cr_glance_go_coming_back', { timeout: 300000 });
  await waitForIdle(page, { timeout: 300000 });
  const opened = await page.evaluate(() =>
    document.querySelector('#cr_downstream_view .nav-link.active')?.textContent.trim());
  ok(opened === 'Coming Back', `the Coming Back step opens its subtab (${opened})`);
  const comingBack = await runs(/Computing retention trend/);
  ok(comingBack === 1, `Coming Back runs once when it opens (${comingBack} runs)`);

  await openSubTab(page, 'At a Glance', { timeout: 300000 });
  const shot = '/tmp/cedar-downstream-glance.png';
  await page.screenshot({ path: shot, fullPage: true });
  console.log(`screenshot: ${shot}`);

  ok(jsErrors.length === 0, `no uncaught JS errors (${jsErrors.join(' ; ') || 'none'})`);

  // A second session, the same course and campuses: the three comparisons are
  // read from what the first session left, so none of them is built again and
  // the five steps are there once the course's own outcomes are read.
  const second = await launch({ width: 1500, height: 1100 });
  try {
    await connect(second.page, { tab: 'course-dynamics' });
    await setInput(second.page, 'cr_campus', ['ABQ', 'EA']);
    await setInput(second.page, 'cr_course', COURSE);
    await runAndWait(second.page, 'cr_generate_button');
    await watchWaits(second.page);
    await openSubTab(second.page, 'Downstream', { timeout: 300000 });
    await waitForSelector(second.page, '#cr_downstream_glance_ui .downstream-glance', { timeout: 300000 });
    await waitForIdle(second.page, { timeout: 300000 });
    const again = await readWaits(second.page);
    const steps = await second.page.evaluate(() =>
      [...document.querySelectorAll('#cr_downstream_glance_ui .downstream-glance-step')]
        .map((c) => c.classList.contains('downstream-glance-step--pending')));
    const rebuilt = again.labels.filter((t) => /^(Comparing takers|Following students|Building the sequence)/.test(t));
    ok(rebuilt.length === 0,
       `a second session builds none of the three comparisons again (${rebuilt.join(' | ') || 'none built'})`);
    ok(steps.length === 5 && steps.every((pending) => !pending),
       `the second session's five steps are settled (${steps.filter((p) => !p).length} of ${steps.length})`);
    // The first session drew the same page, and built whatever was not there
    // yet: all of that building was behind a wait, so it worked unannounced
    // for no longer than the session that built nothing (5 seconds' allowance).
    ok(first.unannounced <= again.unannounced + 5,
       `whatever the first session built, it built behind a wait (${first.unannounced}s with no wait up; ${again.unannounced}s in the session that built nothing)`);
    ok(second.jsErrors.length === 0, `no uncaught JS errors in the second session (${second.jsErrors.join(' ; ') || 'none'})`);
  } finally {
    await second.browser.close();
  }
} finally {
  await browser.close();
}

console.log(fail.length ? `\n${fail.length} FAILED` : '\nall passed');
process.exit(fail.length ? 1 : 0);
