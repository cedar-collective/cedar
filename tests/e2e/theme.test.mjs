// Light and dark mode (www/cedar-theme.js, the tokens in www/cedar-custom.css).
//
// Asserts the page follows the system setting until the reader chooses; the
// navbar toggle switches the mode and the choice survives a reload and a
// system change; in the dark a table's header and a plotly figure read the
// dark tokens (the figure's background clear, its text light); and back in
// light mode the figure gets exactly the colours the server drew.
//
//   node tests/e2e/theme.test.mjs

import { launch, connect, waitFor, waitForIdle, waitForSelector } from './lib.mjs';

const fail = [];
const ok = (cond, msg) => { if (!cond) fail.push(msg); console.log(`${cond ? 'ok  ' : 'FAIL'} ${msg}`); };

const { browser, page, jsErrors } = await launch({ width: 1400, height: 1000 });
const mode = () => page.evaluate(() => document.documentElement.getAttribute('data-bs-theme'));
const figure = () => page.evaluate(() => {
  const gd = (() => { const r = document.getElementById('retention_dashboard-overall_plot'); return r?.classList.contains('js-plotly-plot') ? r : r?.querySelector('.js-plotly-plot'); })();
  return gd && gd._fullLayout ? { paper: gd._fullLayout.paper_bgcolor, font: gd._fullLayout.font.color } : null;
});
const header = () => page.evaluate(() => {
  const h = document.querySelector('#retention_dashboard-signs_table .rt-th');
  return h ? getComputedStyle(h).backgroundColor : null;
});

try {
  await page.emulateMediaFeatures([{ name: 'prefers-color-scheme', value: 'dark' }]);
  await connect(page, { tab: 'home' });
  await page.evaluate(() => { try { localStorage.removeItem('cedar-theme'); } catch (e) {} });
  await connect(page, { tab: 'home' });
  ok(await mode() === 'dark', 'with no choice made, a dark system setting gives dark mode');
  await page.emulateMediaFeatures([{ name: 'prefers-color-scheme', value: 'light' }]);
  ok(await waitFor(page, () => document.documentElement.getAttribute('data-bs-theme') === 'light', { timeout: 5000 }),
     'and it follows the system to light until the reader chooses');

  await page.click('.cedar-theme-toggle');
  ok(await mode() === 'dark', 'the navbar toggle switches to dark');
  const label = await page.$eval('.cedar-theme-toggle', (b) => b.getAttribute('aria-label'));
  ok(label === 'Switch to light mode', `the toggle names what it will do (${label})`);
  await page.emulateMediaFeatures([{ name: 'prefers-color-scheme', value: 'light' }]);

  await connect(page, { tab: 'retention', expect: 'Retention' });
  ok(await mode() === 'dark', 'the choice survives a reload, against a light system setting');
  await waitForSelector(page, '#retention_dashboard-overall_finding .finding-card', { timeout: 300000 });
  await waitForIdle(page, { timeout: 300000 });
  await waitFor(page, () => !!document.querySelector('#retention_dashboard-signs_table .rt-th'), { timeout: 120000 });
  const darkFig = await waitFor(page, () => {
    const gd = (() => { const r = document.getElementById('retention_dashboard-overall_plot'); return r?.classList.contains('js-plotly-plot') ? r : r?.querySelector('.js-plotly-plot'); })();
    return gd && gd._fullLayout && gd._fullLayout.paper_bgcolor === 'rgba(0, 0, 0, 0)';
  }, { timeout: 30000 });
  const fig = await figure();
  ok(darkFig, `a chart drawn in the dark has a clear background (${fig?.paper})`);
  ok(fig && fig.font !== '#444', `and light text (${fig?.font})`);
  const darkHead = await header();
  ok(darkHead === 'rgb(59, 55, 47)', `a table header reads the dark header token (${darkHead})`);
  const bodyBg = await page.evaluate(() => getComputedStyle(document.body).backgroundColor);
  ok(bodyBg === 'rgb(22, 26, 24)', `the page is dark (${bodyBg})`);

  await page.click('.cedar-theme-toggle');
  ok(await mode() === 'light', 'the toggle switches back to light');
  const lightFig = await waitFor(page, () => {
    const gd = (() => { const r = document.getElementById('retention_dashboard-overall_plot'); return r?.classList.contains('js-plotly-plot') ? r : r?.querySelector('.js-plotly-plot'); })();
    return gd && gd._fullLayout && gd._fullLayout.paper_bgcolor === '#fff';
  }, { timeout: 10000 });
  ok(lightFig, `the chart gets back the colours the server drew (${(await figure())?.paper})`);
  ok(await header() === 'rgb(112, 104, 88)', 'the table header is the light header again');
  ok(await page.evaluate(() => localStorage.getItem('cedar-theme')) === 'light', 'light is remembered as a choice too');

  ok(jsErrors.length === 0, `no page errors (${jsErrors.join('; ')})`);
} catch (e) {
  fail.push(String(e));
  console.log(`FAIL ${e}`);
} finally {
  await browser.close();
}

if (fail.length) {
  console.log(`\n${fail.length} failed`);
  process.exit(1);
}
console.log('\nall passed');
