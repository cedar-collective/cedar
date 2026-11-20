// A saved start page (cedar_link_menu() in R/modules/ui-helpers.R, the
// start-page block in www/cedar-navigation.js) and the controls' colours.
//
// Asserts Home explains the start page and says none is set; the Dept
// Dashboard's link menu offers Copy link and Make this my start page; making
// it the start page keeps that link in this browser, names it on Home with a
// link and a Clear button, and opening CEDAR with nothing in the address goes
// there, while ?tab=home still opens Home; Clear returns CEDAR to Home. Also
// that a disabled run button is grey, not green, and the CEDAR title is gold.
//
//   node tests/e2e/start-page.test.mjs

import { launch, connect, waitFor, waitForIdle, BASE, expectNavigation } from './lib.mjs';

const fail = [];
const ok = (cond, msg) => { if (!cond) fail.push(msg); console.log(`${cond ? 'ok  ' : 'FAIL'} ${msg}`); };

const { browser, page, jsErrors } = await launch({ width: 1400, height: 1000 });
const status = () => page.evaluate(() => document.getElementById('cedar_start_page_status')?.textContent.trim() || '');
const clearShown = () => page.evaluate(() => { const b = document.getElementById('cedar_start_page_clear'); return !!b && !b.hidden; });
const tabOf = () => page.evaluate(() => new URLSearchParams(window.location.search).get('tab'));

try {
  await connect(page, { tab: 'home' });
  await page.evaluate(() => { try { localStorage.removeItem('cedar-start-page'); } catch (e) {} });
  await connect(page, { tab: 'home' });
  const note = await page.evaluate(() => document.querySelector('.cedar-home-startpage')?.innerText || '');
  ok(/Make this my start page/.test(note), 'Home explains how to choose a start page');
  ok(/No start page is set/.test(await status()) && !(await clearShown()), `Home says none is set (${await status()})`);

  const rgb = (sel) => page.evaluate((s) => { const el = document.querySelector(s); return el ? getComputedStyle(el).color : null; }, sel);
  ok((await rgb('.navbar .cedar-brand-home')) === 'rgb(199, 169, 107)', `the CEDAR title is lichen gold (${await rgb('.navbar .cedar-brand-home')})`);

  await connect(page, { tab: 'dept-dashboard' });
  const menu = await page.$('#dashboard_copy_url_menu');
  ok(!!menu, 'the Dept Dashboard has a link menu');
  await page.click('#dashboard_copy_url_menu');
  await waitFor(page, () => !!document.querySelector('.cedar-link-menu .dropdown-menu.show'));
  const items = await page.evaluate(() => [...document.querySelectorAll('.cedar-link-menu .dropdown-menu.show .dropdown-item')].map((a) => a.innerText.trim()));
  ok(items.join('|') === 'Copy link|Make this my start page', `the menu offers both (${items})`);
  await page.click('#dashboard_copy_url_home');
  const saved = await waitFor(page, () => { try { return !!localStorage.getItem('cedar-start-page'); } catch (e) { return false; } });
  const kept = saved ? JSON.parse(await page.evaluate(() => localStorage.getItem('cedar-start-page'))) : null;
  ok(kept && /^tab=dept-dashboard/.test(kept.query) && /^Dept Dashboard/.test(kept.label), `the link is kept, named (${kept?.label})`);

  // Opening CEDAR with nothing in the address goes to the start page.
  expectNavigation(page);
  await page.goto(BASE, { waitUntil: 'domcontentloaded', timeout: 60000 });
  await waitFor(page, () => !!(window.Shiny && Shiny.shinyapp && Shiny.shinyapp.isConnected && Shiny.shinyapp.isConnected()), { timeout: 180000, interval: 500 });
  await waitForIdle(page).catch(() => {});
  ok((await tabOf()) === 'dept-dashboard', `a bare address opens the start page (${await tabOf()})`);

  await connect(page, { tab: 'home' });
  ok((await tabOf()) === 'home', 'an address naming Home still opens Home');
  ok(/This browser opens CEDAR on Dept Dashboard/.test(await status()) && (await clearShown()),
     `Home names the start page and offers Clear (${await status()})`);
  await page.click('#cedar_start_page_clear');
  ok(/No start page is set/.test(await status()) && !(await clearShown()), 'Clear forgets it');
  expectNavigation(page);
  await page.goto(BASE, { waitUntil: 'domcontentloaded', timeout: 60000 });
  await waitFor(page, () => !!(window.Shiny && Shiny.shinyapp && Shiny.shinyapp.isConnected && Shiny.shinyapp.isConnected()), { timeout: 180000, interval: 500 });
  await waitForIdle(page).catch(() => {});
  ok(!(await tabOf()) || (await tabOf()) === 'home', `with none set, a bare address opens Home (${await tabOf()})`);

  // A run button that cannot be pressed is grey.
  await connect(page, { tab: 'course-dynamics' });
  const disabled = await page.evaluate(() => {
    const b = document.querySelector('button.btn-primary:disabled, button.btn-primary.disabled');
    if (!b) return null;
    const m = getComputedStyle(b).backgroundColor.match(/\d+/g).map(Number);
    return m;
  });
  ok(disabled && Math.max(...disabled.slice(0, 3)) - Math.min(...disabled.slice(0, 3)) < 16,
     `a disabled run button is grey (${disabled})`);

  ok(jsErrors.length === 0, `no page errors (${jsErrors.join('; ')})`);
} catch (e) {
  fail.push(String(e));
  console.log(`FAIL ${e}`);
} finally {
  await page.evaluate(() => { try { localStorage.removeItem('cedar-start-page'); } catch (e) {} }).catch(() => {});
  await browser.close();
}

if (fail.length) {
  console.log(`\n${fail.length} failed`);
  process.exit(1);
}
console.log('\nall passed');
