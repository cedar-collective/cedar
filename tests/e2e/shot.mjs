// Screenshot any tab of the running CEDAR app for visual inspection.
//
//   node tests/e2e/shot.mjs <tab-slug> [out.png]
//
// e.g. node tests/e2e/shot.mjs pathways /tmp/cedar-pathways.png
// Loads ?tab=<slug> (the forward tabMap restores the tab), waits for the app to
// connect and render, then writes a PNG.
import puppeteer from 'puppeteer-core';

const CHROME = process.env.CHROME_PATH || '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome';
const BASE = process.env.CEDAR_URL || 'http://localhost:3838/cedar/';
const tab = process.argv[2] || 'home';
const out = process.argv[3] || `/tmp/cedar-${tab}.png`;
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

(async () => {
  const browser = await puppeteer.launch({
    executablePath: CHROME, headless: true,
    args: ['--no-sandbox', '--disable-dev-shm-usage'],
  });
  const page = await browser.newPage();
  await page.setViewport({ width: 1440, height: 1000 });
  await page.goto(`${BASE}?tab=${tab}`, { waitUntil: 'domcontentloaded', timeout: 60000 });
  // Wait until Shiny connects (URL keeps a tab param after the connect handler runs).
  const start = Date.now();
  while (Date.now() - start < 180000) {
    if (await page.evaluate(() => location.search.includes('tab='))) break;
    await sleep(1000);
  }
  await sleep(3500); // let the active tab render
  await page.screenshot({ path: out });
  console.log('saved', out);
  await browser.close();
})().catch((e) => { console.error('SHOT ERROR:', e); process.exit(1); });
