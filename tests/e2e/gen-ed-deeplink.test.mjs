// Explore > Gen Ed: the opening scope, the Term types control and the share link.
// A plain visit opens on every term with Fall and Spring ticked; a link with
// term_type=fall restores that one box, runs, and draws Fall terms only; the
// link button copies the same scope back out.
import {
  launch, connect, waitFor,
} from './lib.mjs';

const SEARCH = [
  'tab=gen-ed',
  'autorun=true',
  'campus=ABQ,EA',
  'term_type=fall',
].join('&');

const ticked = (page) => page.evaluate(() =>
  [...document.querySelectorAll('#gen_ed-ge_term_type input[type=checkbox]')]
    .filter((el) => el.checked).map((el) => el.value).sort());

let failures = 0;
function check(ok, label) {
  console.log(`${ok ? 'ok  ' : 'FAIL'} ${label}`);
  if (!ok) failures += 1;
}

(async () => {
  const { browser, page, jsErrors } = await launch();

  try {
    // A plain visit: the defaults, before any run.
    await connect(page, { tab: 'gen-ed' });
    const opening = await page.evaluate(() => {
      const from = document.getElementById('gen_ed-ge_from_term')?.selectize;
      const first = from ? Object.keys(from.options).sort()[0] : null;
      return { from: from?.getValue() ?? null, first };
    });
    check(!!opening.from && opening.from === opening.first,
      `From term opens on the first term (${opening.from})`);
    check(JSON.stringify(await ticked(page)) === JSON.stringify(['fall', 'spring']),
      'Term types open on Fall and Spring');
    check(await page.$('#gen_ed-ge_copy_url') !== null, 'the link button is beside Run');

    // A shared link: one term type, restored and run.
    await connect(page, { tab: 'gen-ed', search: SEARCH });
    const restored = await waitFor(page, () => {
      const boxes = [...document.querySelectorAll('#gen_ed-ge_term_type input[type=checkbox]')];
      const on = boxes.filter((el) => el.checked).map((el) => el.value);
      return on.length === 1 && on[0] === 'fall';
    }, { timeout: 30000, interval: 250 });
    check(restored, 'the link restores Term types to Fall alone');

    const drawn = await waitFor(page, () => {
      const el = document.getElementById('gen_ed-enrl_modality');
      return !!el?.data && el.data.length > 0 && el.data.some((t) => (t.x || []).length > 0);
    }, { timeout: 120000, interval: 500 });
    check(drawn, 'the linked run draws Enrollment by Modality');
    const labels = await page.evaluate(() =>
      [...new Set((document.getElementById('gen_ed-enrl_modality')?.data || [])
        .flatMap((t) => [...(t.x || [])]))]);
    check(labels.length > 1 && labels.every((x) => /^Fa/.test(String(x))),
      `every term on the chart is a Fall term (${labels.length} terms)`);

    const overlayCleared = await waitFor(page, () => {
      const overlay = document.getElementById('gen_ed-loading-overlay');
      return !!overlay && getComputedStyle(overlay).display === 'none';
    }, { timeout: 30000, interval: 250 });
    check(overlayCleared, 'the loading overlay clears');

    // The link button shares the same scope.
    await page.evaluate(() => {
      window.cedarCopiedLink = null;
      navigator.clipboard.writeText = (text) => { window.cedarCopiedLink = text; return Promise.resolve(); };
    });
    await page.click('#gen_ed-ge_copy_url');
    const copied = await waitFor(page, () => !!window.cedarCopiedLink)
      ? new URL(await page.evaluate(() => window.cedarCopiedLink)) : null;
    check(!!copied && copied.searchParams.get('tab') === 'gen-ed' &&
      copied.searchParams.get('autorun') === 'true' &&
      copied.searchParams.get('term_type') === 'fall' &&
      copied.searchParams.get('campus') === 'ABQ,EA' &&
      !!copied.searchParams.get('from_term') && !!copied.searchParams.get('to_term'),
      `the link button copies the scope (${copied ? copied.search : 'nothing copied'})`);

    check(jsErrors.length === 0, `no uncaught JS errors (${jsErrors.join(' | ') || 'none'})`);
  } catch (error) {
    await page.screenshot({ path: '/tmp/cedar-gen-ed-deeplink-failure.png', fullPage: true })
      .catch(() => {});
    throw error;
  } finally {
    await browser.close();
  }

  if (failures > 0) {
    console.error(`\n${failures} check(s) failed`);
    process.exit(1);
  }
  console.log('\nall passed');
})().catch((error) => {
  console.error('GEN ED DEEP-LINK ERROR:', error);
  process.exit(1);
});
