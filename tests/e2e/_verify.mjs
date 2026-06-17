// Clean re-verification of the lib helpers, mirroring the enrollment pattern that
// already returned HIST rows earlier this session. Throwaway.
import { launch, connect, setInput, click, readReactable, colIndex, sleep } from './lib.mjs';

const { browser, page, jsErrors } = await launch();
await connect(page, { tab: 'enrollment' });

await setInput(page, 'enrl_dept', 'HIST');
await sleep(1500);
await click(page, 'enrl_button');

// Native puppeteer wait — the exact predicate that worked before.
await page.waitForFunction(
  () => document.querySelectorAll('#enrl_summary .rt-tbody .rt-tr').length > 0,
  { timeout: 60000 },
);

const { headers, rows } = await readReactable(page, 'enrl_summary', { limit: 3 });
const c = colIndex(headers, 'course'), t = colIndex(headers, 'term');
console.log('PASS rows:', rows.length);
console.log(rows.map((r) => `${r[c]} | ${r[t]}`).join('\n'));
console.log('jsErrors:', jsErrors.length);
await browser.close();
