// Screenshot any tab of the running CEDAR app for visual inspection.
//
//   node tests/e2e/shot.mjs <tab-slug> [out.png]
//
// e.g. node tests/e2e/shot.mjs pathways /tmp/cedar-pathways.png
// Loads ?tab=<slug>, waits for the app to connect and render, then writes a PNG.
// Note: this only LOADS a tab — it does not click buttons or set inputs. To
// screenshot a populated table, drive the inputs first (see README → "Driving
// inputs and reading output back") and call page.screenshot() yourself.
import { launch, connect, sleep } from './lib.mjs';

const tab = process.argv[2] || 'home';
const out = process.argv[3] || `/tmp/cedar-${tab}.png`;

(async () => {
  const { browser, page } = await launch();
  await connect(page, { tab });
  await sleep(1500); // extra beat for the active tab to finish rendering
  await page.screenshot({ path: out });
  console.log('saved', out);
  await browser.close();
})().catch((e) => { console.error('SHOT ERROR:', e); process.exit(1); });
