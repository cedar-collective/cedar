// Regression tests for the harness itself.
//
// Every check here corresponds to a mistake that was actually made against a
// running app on 2026-08-01, each of which produced a confident wrong answer
// rather than an error:
//
//   * connect() was passed a URL string. It destructures its options, so `tab`
//     silently fell back to 'home' and three rounds of assertions described the
//     Home page. It briefly looked like deep-link routing was broken for every
//     tab; it was not.
//   * A button was clicked by visible text. Every tab's markup is in the DOM at
//     once, so the click landed on a hidden tab's "Run".
//   * A $$eval over the whole document was sliced for readability, hiding a
//     control that was present and nearly getting it reported as missing.
//
// Documentation did not prevent any of these — the docs already said so. These
// are the guards that make them fail loudly instead.
//
//   node tests/e2e/harness.test.mjs      # exit code = pass/fail

import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import {
  launch, connect, activeTab, queryActive, clickSubTab, clickNavTab, appReloads, explainAppReload,
  readStartHistory, recordStarts, lastRunOnOtherCode, compareStarts,
} from './lib.mjs';

let pass = 0, fail = 0;
const ok  = (label, extra = '') => { pass++; console.log(`PASS  ${label}${extra ? '  — ' + extra : ''}`); };
const bad = (label, why)        => { fail++; console.log(`FAIL  ${label}  — ${why}`); };

const mustThrow = async (label, fn, needle) => {
  try { await fn(); bad(label, 'no error thrown'); }
  catch (e) {
    e.message.includes(needle) ? ok(label, e.message.slice(0, 60))
                               : bad(label, `wrong error: ${e.message.slice(0, 70)}`);
  }
};

// What a start took last time: fresh-start's history, in a file of its own
// here. Two runs on other code are kept, one of them of four sessions; the
// run to compare with is the latest that timed as many sessions.
{
  const file = path.join(fs.mkdtempSync(path.join(os.tmpdir(), 'cedar-starts-')), 'history.jsonl');
  const earlier = { at: '2026-11-20T15:00:00.000Z', code: 'aaa1111', started: [7.6, 8.1, 4.2, 6.2, 4.4, 4.2], began: [0.4, 2.8, 0.1, 0.2, 0.1, 0.1] };
  const four = { at: '2026-11-22T15:00:00.000Z', code: 'ccc3333', started: [7, 8, 5, 5], began: [0.4, 2.8, 0.1, 0.2] };
  const now = { at: '2026-11-25T15:00:00.000Z', code: 'bbb2222+changes', started: [6.3, 4.5, 4.2, 5.7, 4.4, 4.6], began: [0.3, 0.2, 0.1, 0.2, 0.1, 0.1] };

  readStartHistory(file).length === 0 ? ok('a history not yet written reads as no runs')
                                      : bad('a history not yet written reads as no runs', 'rows');
  for (const run of [earlier, four, now]) recordStarts(file, run);
  const history = readStartHistory(file);
  const before = lastRunOnOtherCode(history, now.code, 6);
  history.length === 3 && before && before.code === 'aaa1111'
    ? ok('the run to compare with is the latest on other code with as many sessions', before.code)
    : bad('the run to compare with is the latest on other code with as many sessions', JSON.stringify(before));

  const said = compareStarts(now, before).join('\n');
  const expected = [
    'whole start, sessions 1 to 6: 6.3 4.5 4.2 5.7 4.4 4.6 s  (bbb2222+changes)',
    'the last run on other code:   7.6 8.1 4.2 6.2 4.4 4.2 s  (aaa1111, 2026-11-20)',
    'since then: first session -1.3 s, second -3.6 s, the later ones +0.2 s at the median',
    'printed, not held: sessions of one process differ by a second and a half among themselves',
  ].join('\n');
  said === expected ? ok('a start is printed beside the last run on other code')
                    : bad('a start is printed beside the last run on other code', said);

  const alone = lastRunOnOtherCode(history.filter((r) => r.code === now.code), now.code, 6);
  alone === null && compareStarts(now, alone)[1].startsWith('no run on other code')
    ? ok('with no run on other code, it says there is nothing to compare')
    : bad('with no run on other code, it says there is nothing to compare', JSON.stringify(alone));

  fs.appendFileSync(file, '{"at": "2026-11-26"\n');
  await mustThrow('a line that is not a run is refused, by its line number',
    async () => readStartHistory(file), 'line 4 is not a record of a run');
}

const { browser, page } = await launch();
try {
  await mustThrow('connect() rejects a URL string',
    () => connect(page, 'http://localhost:3838/?tab=gen-ed'), 'takes options, not a URL');

  await mustThrow('connect() rejects a slug that lands on Home',
    () => connect(page, { tab: 'no-such-tab' }), 'landed on Home');

  const landed = await connect(page, { tab: 'gen-ed', expect: 'Gen Ed' });
  landed === 'Gen Ed' ? ok('connect() returns the landed tab', landed)
                      : bad('connect() returns the landed tab', landed);

  // ISSUES I85: connect() returns once the server has run the session's start
  // (a busy-to-idle cycle), which a quiet page does not show on a process
  // that is still compiling.
  const cycles = await page.evaluate(() => window.__cedarStartCycles);
  cycles >= 1 ? ok('connect() returns after the session has started', `${cycles} busy-to-idle cycle(s)`)
              : bad('connect() returns after the session has started', `cycles seen: ${cycles}`);

  const all = await page.$$eval('label', ns => ns.length);
  const act = (await queryActive(page, 'label')).length;
  act > 0 && act < all ? ok('queryActive() scopes to the active tab', `${act} of ${all}`)
                       : bad('queryActive() scopes to the active tab', `${act} of ${all}`);

  await mustThrow('clickSubTab() refuses a sub-tab on another tab',
    () => clickSubTab(page, 'Course Timing'), 'no VISIBLE sub-tab');

  (await activeTab(page)) === 'Gen Ed'
    ? ok('activeTab() reports the real active tab')
    : bad('activeTab() reports the real active tab', await activeTab(page));

  // A reload the test did not ask for is the app reloading itself, which is
  // what www/cedar-disconnect.js does after the Shiny session drops. Left
  // undetected it surfaces as "Execution context was destroyed" blamed on an
  // unrelated step — the false "Headcount failure" this guard exists to stop.
  appReloads(page) === 0
    ? ok('declared navigations are not counted as app reloads')
    : bad('declared navigations are not counted as app reloads', String(appReloads(page)));

  // Switching tabs rewrites the address bar with history.pushState; no page
  // loads. Counting that as a reload blamed an unrendered Low Enrollment panel
  // on an OOM-killed worker that never existed (2026-10-23).
  await clickNavTab(page, 'Home');
  await page.waitForFunction(() => new URLSearchParams(location.search).get('tab') === 'home',
    { timeout: 15000, polling: 250 });
  appReloads(page) === 0
    ? ok('an address-bar update is not counted as an app reload')
    : bad('an address-bar update is not counted as an app reload', String(appReloads(page)));

  // The navbar title is the way home (its Home tab link is hidden): clicking
  // it is a tab change like any other, not a page load.
  await clickNavTab(page, 'Gen Ed');
  await page.waitForFunction(() => new URLSearchParams(location.search).get('tab') !== 'home',
    { timeout: 15000, polling: 250 });
  await page.click('.cedar-brand-home');
  await page.waitForFunction(() => new URLSearchParams(location.search).get('tab') === 'home',
    { timeout: 15000, polling: 250 });
  (await activeTab(page)) === 'Home' && appReloads(page) === 0
    ? ok('the CEDAR title opens Home without a page load')
    : bad('the CEDAR title opens Home without a page load', `${await activeTab(page)}, ${appReloads(page)} reloads`);
  const homeLinkShown = await page.$eval('#main_navbar a[data-value="Home"]', (a) => a.checkVisibility());
  !homeLinkShown
    ? ok('the separate Home tab link is not shown')
    : bad('the separate Home tab link is not shown', 'visible');

  await page.reload({ waitUntil: 'domcontentloaded' });
  appReloads(page) === 1
    ? ok('an undeclared reload is detected', '1 app reload')
    : bad('an undeclared reload is detected', String(appReloads(page)));

  const rewritten = explainAppReload(page, new Error('Execution context was destroyed'));
  rewritten.message.includes('reloaded itself')
    ? ok('explainAppReload() renames the misleading error')
    : bad('explainAppReload() renames the misleading error', rewritten.message.slice(0, 70));
} finally {
  await browser.close();
}

console.log(`\n${pass}/${pass + fail} harness checks passed`);
process.exit(fail === 0 ? 0 : 1);
