// Freshness must be in the initial document, independent of Shiny responses.
import assert from 'node:assert/strict';
import { launch, connect, clickNavTab, openSubTab, waitForIdle, BASE } from './lib.mjs';

const { browser, page, jsErrors } = await launch();
let passed = 0;
const check = (name, value) => {
  assert.ok(value, name);
  passed++;
  console.log(`PASS  ${name}`);
};
try {
  // With scripts disabled there can be no websocket, output binding, or widget.
  await page.setJavaScriptEnabled(false);
  await page.goto(`${BASE}?tab=data-usage`, { waitUntil: 'domcontentloaded', timeout: 180000 });
  const initial = await page.evaluate(() => {
    const table = document.getElementById('data_status_table');
    return { rows: table?.querySelectorAll('tbody tr').length,
      text: table?.textContent, tag: table?.tagName,
      output: table?.className.includes('shiny') };
  });
  check('initial HTML already contains all five freshness rows', initial.rows === 5);
  check('freshness is a plain table, not a Shiny output', initial.tag === 'TABLE' && !initial.output);
  check('initial HTML includes source dates or explicit missing states',
    /\d{4}-\d{2}-\d{2}|Not available/.test(initial.text));

  await page.setJavaScriptEnabled(true);
  await connect(page, { tab: 'home', expect: 'Home' });
  await page.setOfflineMode(true);
  const revealMs = await page.evaluate(async () => {
    const start = performance.now();
    document.querySelector('.navbar [data-value="Data & Usage"]').click();
    await new Promise(resolve => requestAnimationFrame(() => requestAnimationFrame(resolve)));
    const table = document.getElementById('data_status_table');
    if (!table.checkVisibility()) throw new Error('Freshness table is hidden after Admin navigation');
    return performance.now() - start;
  });
  check(`freshness reveals without network/server response (${Math.round(revealMs)} ms)`, revealMs < 1000);
  await page.setOfflineMode(false);
  await page.screenshot({ path: '/tmp/cedar-admin-freshness.png', fullPage: true });

  await connect(page, { tab: 'data-usage', expect: 'Data & Usage' });
  await openSubTab(page, 'Feature Details');
  await page.waitForFunction(() => {
    const table = document.getElementById('feature_usage_table');
    return table && table.innerText.trim().length > 0 && !table.classList.contains('recalculating');
  });
  const details = await page.evaluate(() => document.getElementById('feature_usage_table').innerText);
  check('on-demand event preview renders without a read error', !details.includes('Error loading data'));
  const stats = await page.evaluate(() => document.getElementById('usage_stats_output').innerText);
  check('shared full-range usage statistics render', !stats.includes('Error loading stats') && stats.includes('Sessions'));
  await openSubTab(page, 'Usage Overview');
  await waitForIdle(page);
  const overview = await page.evaluate(() => document.getElementById('usage_overview_ui').innerText);
  check('on-demand usage summary renders', overview.includes('Active sessions') || overview.includes('No usage data'));

  // Mapping decisions link what to supply to the line (or file) that takes it;
  // the decision is an edit there, never in the running app. Other problems
  // no mapping can fix are a separate table.
  await openSubTab(page, 'Mappings');
  await page.waitForFunction(() => {
    const ready = id => { const el = document.getElementById(id);
      return el && el.innerText.trim().length > 0 && !el.classList.contains('recalculating'); };
    return ready('mapping_decisions_table') && ready('mapping_other_summary');
  }, { timeout: 180000 });
  const work = await page.evaluate(() => ({
    summary: document.getElementById('mapping_decisions_summary').innerText,
    links: [...document.querySelectorAll('#mapping_decisions_table a')].map(a => a.href),
    other: document.getElementById('mapping_other_summary').innerText,
  }));
  check('mapping decisions summarise what is waiting', /mapping decision\(s\)|No mapping decisions/.test(work.summary));
  check('each decision links to the line or file that takes it', work.links.length > 0 &&
    work.links.every(href => /\/edit\/.+\.csv$/.test(href) || /\.csv\?plain=1#L\d+$/.test(href)));
  check('other problems are listed separately', /other problem\(s\)/.test(work.other));
  await page.screenshot({ path: '/tmp/cedar-admin-mappings.png', fullPage: true });

  await clickNavTab(page, 'Projections');
  await waitForIdle(page);
  const projection = await page.evaluate(() => {
    const scope = document.getElementById('enrollment_projections-scope');
    const status = document.getElementById('enrollment_projections-bundle_status');
    return (scope?.innerText || '') + (status?.innerText || '');
  });
  check('deferred projections initialize when opened',
    projection.includes('demand') || projection.includes('No validated enrollment projection bundle'));
  check('no browser JavaScript errors', jsErrors.length === 0);
  console.log(`${passed} passed; screenshot /tmp/cedar-admin-freshness.png`);
} finally {
  await browser.close();
}
