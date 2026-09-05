// Synthetic first-hour acceptance checks. Explicit demo suite, never real data.
import assert from 'node:assert/strict';
import { launch, connect, waitFor, waitForSelector, clickNavTab, BASE } from './lib.mjs';

const { browser, page, jsErrors } = await launch();
let passed = 0;
const check = (name, condition) => {
  assert.ok(condition, name);
  passed++;
  console.log(`PASS  ${name}`);
};
try {
  await connect(page, { tab: 'home', expect: 'Home' });
  const banner = await page.$('#cedar_demo_banner');
  assert.ok(banner, `Expected an isolated synthetic instance at ${BASE}; demo banner missing`);
  check('synthetic notice is visible', await banner.evaluate(el => el.checkVisibility()));
  check('notice identifies synthetic data and fixed current term',
    await banner.evaluate(el => /Synthetic data/.test(el.innerText) && /Fall 2026/.test(el.innerText)));
  await clickNavTab(page, 'Data & Usage');
  check('all five data tables have refresh information', await page.evaluate(() => {
    const rows = [...document.querySelectorAll('#data_status_table tbody tr')];
    return rows.length === 5 && rows.every(row => !row.innerText.includes('Not loaded'));
  }));
  await connect(page, { tab: 'course-dynamics',
    search: 'tab=course-dynamics&autorun=true&campus=ABQ&course=MATH%20375' });
  await waitForSelector(page, '#cr_overview_metrics .stat-card', { timeout: 90000 });
  const cards = await page.$eval('#cr_overview_metrics', el => el.innerText);
  check('course overview uses current demo term', /Fall 2026/.test(cards));
  check('crosslist and selected-code counts are explained', /crosslist total/i.test(cards) && /MATH 375/.test(cards));
  check('known crosslist counts appear', /\b30\b/.test(cards) && /\b32\b/.test(cards) && /\b20\b/.test(cards));
  await waitForSelector(page,
    '#cr_overview_enrollment_plot.js-plotly-plot, #cr_overview_enrollment_plot .js-plotly-plot',
    { timeout: 90000 });
  check('historical enrollment plot renders', true);
  check('loading overlay clears', await waitFor(page, () => {
    const overlay = document.getElementById('cr-loading-overlay');
    return overlay && getComputedStyle(overlay).display === 'none';
  }, { timeout: 30000 }));
  check('no visible Shiny errors', await page.evaluate(() =>
    [...document.querySelectorAll('.shiny-output-error')].every(el => !el.checkVisibility())));
  await page.screenshot({ path: '/tmp/cedar-synthetic-demo.png', fullPage: true });
  check('no browser errors', jsErrors.length === 0);
  console.log(`${passed} passed; screenshot /tmp/cedar-synthetic-demo.png`);
} finally {
  await browser.close();
}
