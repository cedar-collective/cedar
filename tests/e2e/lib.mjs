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
export async function connect(page, { tab = 'home', timeout = 180000 } = {}) {
  await page.goto(`${BASE}?tab=${tab}`, { waitUntil: 'domcontentloaded', timeout: 60000 });
  const ok = await waitFor(page,
    () => !!(window.Shiny && Shiny.shinyapp &&
             typeof Shiny.shinyapp.isConnected === 'function' && Shiny.shinyapp.isConnected()),
    { timeout, interval: 500 });
  if (!ok) throw new Error('Shiny did not connect within timeout');
  await sleep(2500); // let the landing tab settle
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
    const link = [...document.querySelectorAll('a.nav-link, .nav-tabs a, .nav-pills a')]
      .find((a) => a.textContent.trim() === t);
    if (!link) throw new Error(`no sub-tab link "${t}"`);
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
