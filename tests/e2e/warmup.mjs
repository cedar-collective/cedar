// Warm the app before the browser suites run.
//
//   node tests/e2e/warmup.mjs
//
// The first websocket connection after a rebuild — or after the worker has been
// idle long enough to be recycled — runs global.R, which loads every cedar table.
// Whichever suite happens to go first then pays that cost inside its own step
// budget and fails as "timed out waiting for <first output>", which reads like a
// broken report rather than a cold start. The failure moves around depending on
// suite order, so it is easy to chase for a while.
//
// This absorbs the cold start in a stage that is allowed to be slow, so every
// suite afterwards starts against a warm worker. run-tests.sh runs it for you.

import { launch, connect, waitForIdle } from './lib.mjs';

const t0 = Date.now();
const { browser, page } = await launch({ width: 1200, height: 900 });

try {
  await connect(page, { tab: 'home', timeout: 300000 });
  await waitForIdle(page, { timeout: 300000 });
  console.log(`app warm after ${((Date.now() - t0) / 1000).toFixed(1)}s`);
} finally {
  await browser.close();
}
