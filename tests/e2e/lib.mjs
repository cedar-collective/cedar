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

export const CHROME = process.env.CHROME_PATH ||
  '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome';
export const BASE = process.env.CEDAR_URL || 'http://localhost:3838/';

export const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

// Poll an in-page predicate until it returns truthy or we time out.
export async function waitFor(page, fn, { timeout = 15000, interval = 250 } = {}) {
  const start = Date.now();
  while (Date.now() - start < timeout) {
    try { if (await page.evaluate(fn)) return true; } catch {}
    await sleep(interval);
  }
  return false;
}

// Launch headless system Chrome and return { browser, page, jsErrors }.
// jsErrors accumulates any uncaught page errors — assert it's empty at the end.
export async function launch({ width = 1440, height = 1000 } = {}) {
  const browser = await puppeteer.launch({
    executablePath: CHROME, headless: true,
    args: ['--no-sandbox', '--disable-dev-shm-usage'],
  });
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
  await sleep(settle); // let the landing tab settle

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

// Every tab's markup is in the DOM at once, including tabs you are not on.
// These scope a query to the ACTIVE tab pane so a hidden tab's element cannot
// masquerade as the one you are looking at — the reason clicking the first
// button labelled "Run" hits whichever tab happened to define one first.
export function activeText(page) {
  return page.evaluate(() => {
    const pane = [...document.querySelectorAll('.tab-pane.active')]
      .find((p) => p.offsetParent !== null);
    return (pane || document.body).innerText;
  });
}

export function queryActive(page, sel) {
  return page.evaluate((s) => {
    const pane = [...document.querySelectorAll('.tab-pane.active')]
      .find((p) => p.offsetParent !== null) || document.body;
    return [...pane.querySelectorAll(s)]
      .filter((n) => n.offsetParent !== null)
      .map((n) => n.textContent.trim());
  }, sel);
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
  return page.evaluate((t) => {
    // Restrict to visible links: hidden tabs keep their sub-tab markup in the
    // DOM, so an unfiltered search can click a sub-tab on a tab you are not on.
    const links = [...document.querySelectorAll('a.nav-link, .nav-tabs a, .nav-pills a')]
      .filter((a) => a.offsetParent !== null)
      .filter((a) => !a.closest('.navbar'));   // top-level nav is not a sub-tab
    const link = links.find((a) => a.textContent.trim() === t);
    if (!link) {
      const avail = links.map((a) => a.textContent.trim()).filter(Boolean).join(', ');
      throw new Error(`no VISIBLE sub-tab "${t}". Visible sub-tabs: ${avail || '(none)'}`);
    }
    link.click();
  }, text);
}

// Wait for a CSS selector to appear (and, by default, be non-empty).
export function waitForSelector(page, sel, { timeout = 60000, nonEmpty = true } = {}) {
  return waitFor(page, (s, ne) => {
    const el = document.querySelector(s);
    if (!el) return false;
    return ne ? el.innerText.trim().length > 0 : true;
  }, { timeout }).then((ok) => {
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
