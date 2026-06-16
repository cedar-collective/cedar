// Headless E2E checks for the top-nav URL routing in the running CEDAR app.
// Drives the dockerized app (http://localhost:3838/cedar/) with system Chrome.
//
//   node tests/e2e/nav.test.mjs
//
// Verifies: bare URL is stamped with ?tab=home on connect; clicking a top-level
// tab pushes ?tab=<slug>; browser Back re-activates the prior tab (popstate); and
// the Regstats→Waitlists cross-navigation (the waitlist count link) is Back-able
// to Regstats. Exits non-zero if any check fails.
import puppeteer from 'puppeteer-core';

const CHROME = process.env.CHROME_PATH || '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome';
const BASE = process.env.CEDAR_URL || 'http://localhost:3838/cedar/';

const results = [];
let failed = 0;
function check(name, ok, detail = '') {
  results.push({ name, ok: !!ok });
  if (!ok) failed++;
  console.log(`${ok ? 'PASS' : 'FAIL'}  ${name}${detail ? `  — ${detail}` : ''}`);
}
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
async function waitFor(page, fn, { timeout = 15000, interval = 250 } = {}) {
  const start = Date.now();
  while (Date.now() - start < timeout) {
    try { if (await page.evaluate(fn)) return true; } catch {}
    await sleep(interval);
  }
  return false;
}
const search = (page) => page.evaluate(() => location.search);
const activeTab = (page) => page.evaluate(() => {
  // A tab inside a nav_menu marks BOTH the dropdown parent toggle and the leaf
  // item active — prefer the leaf (skip .dropdown-toggle) to get the real tab.
  const els = [...document.querySelectorAll(
    '.navbar [data-value].active, .navbar [data-value][aria-selected="true"]')];
  const leaf = els.find((e) => !e.classList.contains('dropdown-toggle')) || els[0];
  return leaf ? leaf.getAttribute('data-value') : null;
});
const clickTab = (page, name) => page.evaluate((n) => {
  const el = document.querySelector(`.navbar [data-value="${n}"]`);
  if (!el) throw new Error(`no nav link for ${n}`);
  el.click();
}, name);
const back = (page) => page.evaluate(() => history.back());

(async () => {
  const browser = await puppeteer.launch({
    executablePath: CHROME,
    headless: true,
    args: ['--no-sandbox', '--disable-dev-shm-usage'],
  });
  const page = await browser.newPage();
  const jsErrors = [];
  page.on('pageerror', (e) => jsErrors.push(String(e)));

  console.log('navigating to', BASE);
  await page.goto(BASE, { waitUntil: 'domcontentloaded', timeout: 60000 });

  // 1. Shiny connects and my code stamps the bare URL with ?tab=home.
  //    The first connection runs global.R (heavy data load) — allow time.
  const connected = await waitFor(page, () => location.search.includes('tab='),
    { timeout: 180000, interval: 1000 });
  check('bare URL gets ?tab= stamped on connect', connected, await search(page));
  check('  → stamped to ?tab=home', (await search(page)) === '?tab=home', await search(page));

  // 2. Clicking a top-level tab pushes ?tab=<slug> (pushState writer).
  await clickTab(page, 'Pathways');
  check('click Pathways → ?tab=pathways',
    await waitFor(page, () => location.search === '?tab=pathways'), await search(page));

  await clickTab(page, 'Regstats');
  check('click Regstats → ?tab=registration',
    await waitFor(page, () => location.search === '?tab=registration'), await search(page));

  // 3. Browser Back returns to Pathways AND re-activates that tab (popstate).
  await back(page);
  check('Back → URL ?tab=pathways',
    await waitFor(page, () => location.search === '?tab=pathways'), await search(page));
  check('Back → Pathways tab active', (await activeTab(page)) === 'Pathways', await activeTab(page));

  // 4. Regstats → Waitlists cross-nav (the waitlist count link fires this input),
  //    then Back must return to Regstats. Tests the exact mechanism the link relies on.
  await clickTab(page, 'Regstats');
  await waitFor(page, () => location.search === '?tab=registration');
  await page.evaluate(() =>
    window.Shiny.setInputValue('waitlist-wl_navigate', { course: '', term: '' }, { priority: 'event' }));
  check('waitlist nav → ?tab=waitlists',
    await waitFor(page, () => location.search === '?tab=waitlists', { timeout: 20000 }), await search(page));
  check('  → Waitlists tab active', (await activeTab(page)) === 'Waitlists', await activeTab(page));

  await back(page);
  check('Back from Waitlists → ?tab=registration',
    await waitFor(page, () => location.search === '?tab=registration'), await search(page));
  check('  → Regstats tab active', (await activeTab(page)) === 'Regstats', await activeTab(page));

  check('no uncaught JS errors on page', jsErrors.length === 0, jsErrors.slice(0, 3).join(' | '));

  await browser.close();
  console.log(`\n${results.filter((r) => r.ok).length}/${results.length} checks passed`);
  process.exit(failed ? 1 : 0);
})().catch((e) => { console.error('TEST HARNESS ERROR:', e); process.exit(2); });
