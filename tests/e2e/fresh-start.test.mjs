// The first sessions of a just-started process.
//
//   ./run-tests.sh --e2e --fresh fresh-start
//
// --fresh restarts the app, waits for its build-ahead to end and leaves out
// the warm-up, so the six sessions opened here are the process's first six.
// Run against a process already in use, all six take the same and it passes:
// it then says nothing about a start.
//
// Asserts, for each of the first two sessions
//   1. An input set the moment connect() returns is still set once the page
//      is idle. The second session of a process used to lose it: R was still
//      compiling the server function when the test took a quiet page for a
//      started session (ISSUES I85).
//   2. The server begins as soon after the connection as it does for the four
//      sessions after. R compiles a function before it runs it, so a session
//      that meets the server function uncompiled waits for the compiler here:
//      2.8 seconds against 0.1 in the development container, once per restart
//      (ISSUES I81). global.R compiles it at start and server.R's last line
//      hands it to Shiny.
//
// Prints, and does not hold, each session's whole start. The sessions after
// the second differ among themselves by a second and a half (4.2 to 5.9
// seconds, 2026-11-25), which is as much as the first session still adds
// (ISSUES M75), so no allowance separates the two.

import { launch, connect, setInput, waitForIdle, sessionStart } from './lib.mjs';

const SESSIONS = 6;
// From the websocket opening to the page's first busy state, held to the
// longest of the later four plus this.
const WAIT_SECONDS = 1.0;
const PICKED = 'HIST 1110';

const fail = [];
const ok = (cond, msg) => { if (!cond) fail.push(msg); console.log(`${cond ? 'ok  ' : 'FAIL'} ${msg}`); };

const waited = [];
for (let n = 1; n <= SESSIONS; n++) {
  const { browser, page } = await launch({ width: 1200, height: 900 });
  try {
    await connect(page, { tab: 'home', timeout: 300000 });
    const at = await sessionStart(page);
    waited.push(at.busy - at.connected);
    console.log(`     session ${n}: started ${at.started.toFixed(1)} s after it was opened; ` +
      `the server began ${(at.busy - at.connected).toFixed(1)} s after the connection`);

    // cr_course is a picker the server fills once per session, with a message
    // that empties it: the input a too-early test loses.
    await setInput(page, 'cr_course', PICKED);
    await waitForIdle(page, { timeout: 120000 });
    const kept = await page.evaluate(() => window.Shiny.shinyapp.$inputValues.cr_course);
    ok(kept === PICKED, `session ${n}: a course set when connect() returned is still set (${JSON.stringify(kept)})`);
  } finally {
    await browser.close();
  }
}

const later = waited.slice(2);
const allowed = Math.max(...later) + WAIT_SECONDS;
for (const n of [1, 2]) {
  ok(waited[n - 1] <= allowed,
    `session ${n}: the server began ${waited[n - 1].toFixed(1)} s after the connection; ` +
    `for the four after it, ${later.map((x) => x.toFixed(1)).join(', ')} s (allowed ${allowed.toFixed(1)} s)`);
}

if (fail.length) { console.log(`\n${fail.length} failed`); process.exit(1); }
console.log('\nall passed');
