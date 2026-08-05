// Shared helpers for driving the running CEDAR app with a headless browser.
//
// Import these instead of re-deriving the connect/setInput/click/read boilerplate
// in every script. See README.md → "Driving inputs and reading output back" for a
// copy-paste recipe. All helpers run against the dockerized app at
// http://localhost:3838/ (override with CEDAR_URL).
//
//   import { launch, connect, setInput, click, clickNavTab, clickSubTab,
//            waitForSelector, readReactable, colIndex, sleep } from './lib.mjs';
import puppeteer from 'puppeteer-core';
import fs from 'node:fs';

export const CHROME = process.env.CHROME_PATH ||
  '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome';
export const BASE = process.env.CEDAR_URL || 'http://localhost:3838/';

export const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

// Poll an in-page predicate until it returns truthy or we time out.
// `args` are forwarded to the predicate inside the page, the same way
// page.evaluate() forwards them — the predicate runs in the browser and cannot
// close over anything from this file.
export async function waitFor(page, fn, { timeout = 15000, interval = 250, args = [] } = {}) {
  const start = Date.now();
  while (Date.now() - start < timeout) {
    try { if (await page.evaluate(fn, ...args)) return true; } catch {}
    await sleep(interval);
  }
  return false;
}

// Launch headless system Chrome and return { browser, page, jsErrors }.
// jsErrors accumulates any uncaught page errors — assert it's empty at the end.
export async function launch({ width = 1440, height = 1000 } = {}) {
  if (!fs.existsSync(CHROME)) {
    throw new Error(
      `E2E browser setup failed: Chrome was not found at ${CHROME}. ` +
      `Set CHROME_PATH to a Chrome or Chromium executable and retry.`);
  }

  let browser;
  try {
    browser = await puppeteer.launch({
      executablePath: CHROME, headless: true,
      args: ['--no-sandbox', '--disable-dev-shm-usage'],
    });
  } catch (e) {
    throw new Error(
      `E2E browser setup failed: could not launch Chrome at ${CHROME}. ` +
      `If this is running in a managed sandbox, allow GUI/browser launch and retry. ` +
      `The app was not exercised by this e2e suite. Original error: ${e.message}`);
  }
  const page = await browser.newPage();
  await page.setViewport({ width, height });
  const jsErrors = [];
  page.on('pageerror', (e) => jsErrors.push(String(e)));
  return { browser, page, jsErrors };
}

// Navigate to ?tab=<tab> and wait for Shiny to actually connect. The FIRST
// connection runs global.R (heavy data load), so the default timeout is generous.
// We wait on Shiny.shinyapp.isConnected() — NOT on `tab=` in the URL: navigating
// straight to ?tab=<tab> puts the param there before Shiny connects, so the URL
// is a false signal here (it's only a real signal from the bare URL, which
// ui.R stamps with ?tab=home after connecting). After this returns, the active
// tab's outputs still need a beat to render — see the recipe.
export async function connect(page, opts = {}) {
  // Reject a URL string loudly. This signature destructures, so passing
  // `connect(page, 'http://localhost:3838/?tab=gen-ed')` used to leave `tab`
  // at its 'home' default — a string has no `.tab` — and every assertion
  // afterwards described the Home page while looking like a routing bug.
  if (typeof opts === 'string') {
    throw new Error(
      `connect() takes options, not a URL. Use connect(page, { tab: '<slug>' }). ` +
      `Received: ${opts}`);
  }
  const { tab = 'home', timeout = 180000, expect = null, settle = 2500 } = opts;

  await page.goto(`${BASE}?tab=${tab}`, { waitUntil: 'domcontentloaded', timeout: 60000 });
  const ok = await waitFor(page,
    () => !!(window.Shiny && Shiny.shinyapp &&
             typeof Shiny.shinyapp.isConnected === 'function' && Shiny.shinyapp.isConnected()),
    { timeout, interval: 500 });
  if (!ok) throw new Error('Shiny did not connect within timeout');

  // Settle properly, not on a timer. isConnected() goes true well before the
  // landing tab has finished its first reactive flush, and inputs set during
  // that window are overwritten when the app's own initialisation lands — the
  // symptom is a selectize that still reads "Type to search..." after setInput,
  // and a page stuck on its empty state while the toast says the analysis ran.
  // The sleep is kept as a floor because Shiny reports idle between flushes.
  await sleep(settle);
  await waitForIdle(page, { timeout: 120000 }).catch(() => {});

  // Verify the tab actually activated. Without this a bad slug, a routing
  // regression, or a too-short settle all present as "everything is on Home"
  // and the caller happily asserts against the wrong page.
  const active = await activeTab(page);
  if (tab !== 'home' && active === 'Home') {
    throw new Error(
      `connect({ tab: '${tab}' }) landed on Home. Either the slug is wrong ` +
      `(see CEDAR_TAB_SLUGS in R/trunk/url-state.R) or the tab needs a longer ` +
      `settle: connect(page, { tab: '${tab}', settle: 6000 }).`);
  }
  if (expect && active !== expect) {
    throw new Error(`expected to land on "${expect}" but active tab is "${active}"`);
  }
  return active;
}

// The label of the currently active top-level nav tab, or '(none)'.
export function activeTab(page) {
  return page.evaluate(() => {
    const a = [...document.querySelectorAll('.navbar a')]
      .find((x) => x.getAttribute('aria-selected') === 'true');
    return a ? a.textContent.trim() : '(none)';
  });
}

// ── One definition of "visible" ──────────────────────────────────────────────
//
// `el.offsetParent !== null` is the classic test and it is WRONG here: it also
// returns null for anything inside a position:fixed or sticky ancestor, which in
// bslib includes the sub-tab bars. Using it silently filtered out every sub-tab
// on Course Dynamics, so clickSubTab() reported "Visible sub-tabs: (none)" on a
// page that plainly showed seven of them — and that is why several tests grew
// their own hand-rolled tab clickers instead of calling the helper.
//
// Element.checkVisibility() is the real answer (Chrome 105+); the rect check is
// the fallback. This string is injected into page.evaluate bodies because those
// run in the browser and cannot close over anything in this file.
const VIS = `const __vis = (el) => el && (el.checkVisibility
  ? el.checkVisibility({ checkOpacity: true, checkVisibilityCSS: true })
  : !!(el.offsetWidth || el.offsetHeight || el.getClientRects().length));`;

// Every tab's markup is in the DOM at once, including tabs you are not on.
// These scope a query to the ACTIVE tab pane so a hidden tab's element cannot
// masquerade as the one you are looking at — the reason clicking the first
// button labelled "Run" hits whichever tab happened to define one first.
export function activeText(page) {
  return page.evaluate(new Function(`${VIS}
    const pane = [...document.querySelectorAll('.tab-pane.active')].find(__vis);
    return (pane || document.body).innerText;`));
}

export function queryActive(page, sel) {
  return page.evaluate(new Function('s', `${VIS}
    const pane = [...document.querySelectorAll('.tab-pane.active')].find(__vis) || document.body;
    return [...pane.querySelectorAll(s)].filter(__vis).map((n) => n.textContent.trim());`), sel);
}

// Set a Shiny input. `id` is the FULL input id including any module namespace,
// e.g. 'enrl_dept' (top level) or 'pathways-population-dept_code' (nested module).
// priority:'event' forces the input to fire even if the value is unchanged.
export function setInput(page, id, value, { priority = 'event' } = {}) {
  return page.evaluate((i, v, p) => window.Shiny.setInputValue(i, v, { priority: p }),
    id, value, priority);
}

// Click any element by DOM id — typically an actionButton (e.g. 'enrl_button',
// 'pathways-population-build_btn').
export function click(page, id) {
  return page.evaluate((i) => {
    const el = document.getElementById(i);
    if (!el) throw new Error(`no element #${i}`);
    el.click();
  }, id);
}

// Click a TOP-LEVEL nav tab by its page_navbar value (e.g. 'Pathways', 'Regstats').
export function clickNavTab(page, name) {
  return page.evaluate((n) => {
    const el = document.querySelector(`.navbar [data-value="${n}"]`);
    if (!el) throw new Error(`no top-nav link for ${n}`);
    el.click();
  }, name);
}

// Click a SUB-TAB (a navset_tab/tabsetPanel inside a module) by its visible text,
// e.g. 'Major Changes', 'Course Timing'. Sub-tab outputs are suspendWhenHidden by
// default, so they don't compute until you switch to them — that's what makes an
// auto-running tab actually run.
export function clickSubTab(page, text) {
  return page.evaluate(new Function('t', `${VIS}
    // Restrict to visible links: hidden tabs keep their sub-tab markup in the
    // DOM, so an unfiltered search can click a sub-tab on a tab you are not on.
    const links = [...document.querySelectorAll('a.nav-link, .nav-tabs a, .nav-pills a')]
      .filter(__vis)
      .filter((a) => !a.closest('.navbar'));   // top-level nav is not a sub-tab
    const link = links.find((a) => a.textContent.trim() === t);
    if (!link) {
      const avail = links.map((a) => a.textContent.trim()).filter(Boolean).join(', ');
      throw new Error('no VISIBLE sub-tab "' + t + '". Visible sub-tabs: ' + (avail || '(none)'));
    }
    link.click();`), text);
}

// ── Waiting for Shiny, properly ──────────────────────────────────────────────
//
// Read this before adding another sleep().
//
// Shiny tells you when it is working: <html> carries `shiny-busy` while a
// reactive flush is in flight, and each output carries `recalculating` while its
// own value is being recomputed. Polling those is the only reliable "is it done"
// signal. Everything else we tried is a guess:
//
//   sleep(N)                  races the app; N is tuned to one machine.
//   wait for non-empty text   passes INSTANTLY on the previous run's output,
//                             which is how a stale scope bar read "629 students
//                             analyzed" for a run that produced 401.
//
// ONE TRAP, and it is the reason this needs a helper rather than a one-liner:
// outputs on hidden tabs are suspended, and a suspended output keeps its
// `recalculating` class indefinitely. Counting every .recalculating in the DOM
// therefore never reaches zero on any page with an unopened sub-tab. Only
// VISIBLE recalculating outputs count.

// Wait until Shiny has been idle for `quiet` ms. Use after any click/setInput
// that triggers work, instead of guessing a sleep.
export async function waitForIdle(page, { timeout = 180000, quiet = 600 } = {}) {
  const start = Date.now();
  let quietSince = null;
  let last = null;

  while (Date.now() - start < timeout) {
    last = await page.evaluate(new Function(`${VIS}
      return {
        busy: document.documentElement.classList.contains('shiny-busy'),
        // Visible only — a suspended output on a hidden tab recalculates forever.
        pending: [...document.querySelectorAll('.recalculating')]
          .filter(__vis).map((el) => el.id || el.className).slice(0, 5),
      };`));

    if (!last.busy && last.pending.length === 0) {
      if (quietSince === null) quietSince = Date.now();
      if (Date.now() - quietSince >= quiet) return true;
    } else {
      quietSince = null;
    }
    await sleep(200);
  }

  throw new Error(
    `Shiny still busy after ${timeout}ms ` +
    `(shiny-busy=${last && last.busy}, pending: ${(last && last.pending.join(', ')) || 'none'})`);
}

// Click a button (or set an input) and wait for the resulting work to finish.
// This is the standard way to run an analysis in a test.
export async function runAndWait(page, buttonId, opts = {}) {
  await click(page, buttonId);
  // Give Shiny a beat to mark itself busy before we start checking for idle,
  // otherwise we can observe the pre-click idle state and return immediately.
  await sleep(400);
  await waitForIdle(page, opts);
}

// Open a sub-tab and wait until its pane is actually visible AND its outputs
// have finished. clickSubTab() alone only fires the click: the pane is still
// display:none for a moment, its outputs are still suspended, and innerText on a
// hidden element returns '' — which reads exactly like "the tab rendered nothing".
export async function openSubTab(page, text, opts = {}) {
  await clickSubTab(page, text);

  const shown = await waitFor(page, new Function('t', `${VIS}
    const links = [...document.querySelectorAll('a.nav-link, .nav-tabs a, .nav-pills a')]
      .filter((a) => !a.closest('.navbar'));
    const link = links.find((a) => a.textContent.trim() === t);
    if (!link) return false;
    const sel = link.getAttribute('data-bs-target') || link.getAttribute('href');
    if (!sel || !sel.startsWith('#')) return __vis(link);
    return __vis(document.querySelector(sel));`),
    { timeout: opts.timeout ?? 60000, args: [text] });

  if (!shown) throw new Error(`sub-tab "${text}" never became visible`);
  await waitForIdle(page, opts);
}

// Assert that every id exists in the DOM, naming near-misses when one does not.
// A test that drives a renamed id otherwise fails as a timeout, which reads like
// a broken feature rather than a stale selector.
export async function requireIds(page, ids) {
  const missing = await page.evaluate((wanted) => {
    const all = [...document.querySelectorAll('[id]')].map((e) => e.id);
    return wanted
      .filter((id) => !document.getElementById(id))
      .map((id) => {
        const stem = id.split('-').pop().split('_').slice(0, 2).join('_');
        const near = all.filter((a) => a.includes(stem)).slice(0, 4);
        return { id, near };
      });
  }, ids);

  if (missing.length > 0) {
    throw new Error('missing element id(s):\n' + missing
      .map((m) => `  #${m.id}${m.near.length ? `  — did you mean: ${m.near.join(', ')}` : ''}`)
      .join('\n'));
  }
}

// Wait for a CSS selector to appear (and, by default, be non-empty).
export function waitForSelector(page, sel, { timeout = 60000, nonEmpty = true } = {}) {
  return waitFor(page, (s, ne) => {
    const el = document.querySelector(s);
    if (!el) return false;
    return ne ? el.innerText.trim().length > 0 : true;
  }, { timeout, args: [sel, nonEmpty] }).then((ok) => {
    if (!ok) throw new Error(`selector "${sel}" did not appear within ${timeout}ms`);
  });
}

// Read a reactable's header labels and the first `limit` data rows from #<outputId>.
// Returns { headers: string[], rows: string[][] }. NOTE: header text often comes
// back UPPERCASED by CSS (innerText reflects text-transform) — match columns with
// colIndex() below, which is case-insensitive.
export function readReactable(page, outputId, { limit = 30 } = {}) {
  return page.evaluate((id, lim) => {
    const root = document.getElementById(id);
    if (!root) return { error: `no #${id}` };
    const headers = [...root.querySelectorAll('.rt-th')]
      .map((h) => h.innerText.trim()).filter(Boolean);
    const rows = [...root.querySelectorAll('.rt-tbody .rt-tr')].slice(0, lim)
      .map((tr) => [...tr.querySelectorAll('.rt-td')].map((td) => td.innerText.trim()));
    return { headers, rows };
  }, outputId, limit);
}

// Case-insensitive column lookup for the headers returned by readReactable().
export function colIndex(headers, name) {
  return headers.map((h) => h.toLowerCase()).indexOf(name.toLowerCase());
}
