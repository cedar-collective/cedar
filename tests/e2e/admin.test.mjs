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

  // Program mappings awaiting a decision link to their line in the repository;
  // the decision is an edit there, never in the running app.
  await openSubTab(page, 'Mappings');
  await page.waitForFunction(() => {
    const table = document.getElementById('program_mapping_queue_table');
    return table && table.innerText.trim().length > 0 && !table.classList.contains('recalculating');
  });
  const review = await page.evaluate(() => {
    const links = [...document.querySelectorAll('#program_mapping_queue_table a')].map(a => a.href);
    const summary = document.getElementById('program_mapping_queue_summary');
    return { links, edit: summary?.querySelector('a')?.href, text: summary?.innerText ?? '' };
  });
  check('program mapping queue renders its summary', /to decide|Every program mapping is decided/.test(review.text));
  check('summary links to the file in the GitHub editor', /\/edit\/.+\/programs\.csv$/.test(review.edit ?? ''));
  check('each program in the file links to its line', review.links.length === 0 ||
    review.links.every(href => /programs\.csv\?plain=1#L\d+$/.test(href)));
  // The audit of values the mapping files do not cover is computed live.
  await page.waitForFunction(() => {
    const summary = document.getElementById('mapping_audit_summary');
    return summary && summary.innerText.trim().length > 0 && !summary.classList.contains('recalculating');
  }, { timeout: 120000 });
  const audit = await page.evaluate(() => ({
    text: document.getElementById('mapping_audit_summary').innerText,
    links: [...document.querySelectorAll('#mapping_audit_table a')].map(a => a.href),
  }));
  check('mapping audit summarises what it checked', /unmapped value\(s\)/.test(audit.text) && /Checked: /.test(audit.text));
  // A row to edit links to its line; a fix that is a new row opens the file.
  // What to supply is the link: to the line, or to the file for a new row.
  check('each audit row links its Needs to the line or file that takes it',
    audit.links.every(href => /\/edit\/.+\.csv$/.test(href) || /\.csv\?plain=1#L\d+$/.test(href)));
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
