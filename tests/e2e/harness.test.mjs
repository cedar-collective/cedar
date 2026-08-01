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

import { launch, connect, activeTab, queryActive, clickSubTab } from './lib.mjs';

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

const { browser, page } = await launch();
try {
  await mustThrow('connect() rejects a URL string',
    () => connect(page, 'http://localhost:3838/?tab=gen-ed'), 'takes options, not a URL');

  await mustThrow('connect() rejects a slug that lands on Home',
    () => connect(page, { tab: 'no-such-tab' }), 'landed on Home');

  const landed = await connect(page, { tab: 'gen-ed', expect: 'Gen Ed' });
  landed === 'Gen Ed' ? ok('connect() returns the landed tab', landed)
                      : bad('connect() returns the landed tab', landed);

  const all = await page.$$eval('label', ns => ns.length);
  const act = (await queryActive(page, 'label')).length;
  act > 0 && act < all ? ok('queryActive() scopes to the active tab', `${act} of ${all}`)
                       : bad('queryActive() scopes to the active tab', `${act} of ${all}`);

  await mustThrow('clickSubTab() refuses a sub-tab on another tab',
    () => clickSubTab(page, 'Course Timing'), 'no VISIBLE sub-tab');

  (await activeTab(page)) === 'Gen Ed'
    ? ok('activeTab() reports the real active tab')
    : bad('activeTab() reports the real active tab', await activeTab(page));
} finally {
  await browser.close();
}

console.log(`\n${pass}/${pass + fail} harness checks passed`);
process.exit(fail === 0 ? 0 : 1);
