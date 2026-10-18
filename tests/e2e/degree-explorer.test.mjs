// Adaptive semester planning and the separate, population-aware Course paths subtab.
import {
  launch, connect, openSubTab, waitForIdle, waitForSelector, runAndWait,
  readReactable, colIndex, waitFor, setInput,
} from './lib.mjs';

const { browser, page, jsErrors } = await launch();
page.on('pageerror', error => console.error('Browser error:', error.stack || String(error)));
let passed = 0;
const failures = [];
function check(ok, message) {
  if (ok) passed++; else failures.push(message);
  console.log(`${ok ? 'PASS' : 'FAIL'} ${message}`);
}
const choose = async (id, value) => {
  await page.evaluate((id, value) => document.getElementById(id).selectize.setValue(value), id, value);
  const rendered = await waitFor(page, () => {
    const board = document.querySelector('[data-roadmap][data-ready]');
    return board && board.dataset.catalog === document.getElementById('degree_explorer-dx_catalog_id').value &&
      board.dataset.mathStart === document.getElementById('degree_explorer-dx_math_start').value &&
      board.dataset.englishStart === document.getElementById('degree_explorer-dx_english_start').value &&
      board.dataset.startSeason === document.getElementById('degree_explorer-dx_start_season').value;
  }, { timeout: 30000 });
  if (!rendered) throw new Error(`Roadmap did not redraw after ${id} changed`);
  await waitForIdle(page);
};
// The popup is the standard CEDAR modal, rendered by the server for each click.
const MODAL = '#shiny-modal .modal-content';
const waitForPopup = async id => {
  await waitForSelector(page, `#shiny-modal.show [data-dialog-node="${id}"]`);
  await waitForSelector(page, `#shiny-modal [data-history-node="${id}"]`, { timeout: 60000 });
  if (await page.$eval(`[data-history-node="${id}"]`, el => el.dataset.historyState === 'ready')) {
    await waitForSelector(page, '#degree_explorer-course_history_table .rt-table', { timeout: 60000 });
    await waitForIdle(page);
  }
};
const popup = async id => {
  await page.click(`[data-node="${id}"]`);
  await waitForPopup(id);
};
const hoverCourse = async id => {
  await page.hover(`[data-node="${id}"]`);
  if (!await waitFor(page, id => document.querySelector('[data-roadmap]').dataset.previewNode === id,
    { timeout: 10000, args: [id] })) throw new Error(`No chain preview for ${id}`);
};
const closePopup = async () => {
  await page.keyboard.press('Escape');
  if (!await waitFor(page, () => !document.querySelector('#shiny-modal'))) throw new Error('Course popup did not close');
};
const alignedHeaders = () => page.evaluate(() => {
  const headers = [...document.querySelectorAll('.cedar-roadmap-semester-header')].map(el => el.getBoundingClientRect());
  const starts = [...document.querySelectorAll('.cedar-roadmap-courses')].map(el => el.getBoundingClientRect().top);
  return new Set(headers.map(r => r.height)).size === 1 && Math.max(...starts) - Math.min(...starts) < 1;
});
const semester = id => page.$eval(`[data-node="${id}"]`, el => Number(el.dataset.semester));
const alignedCourses = ids => page.evaluate(ids => {
  const cards = ids.map(id => document.querySelector(`[data-node="${id}"]`));
  if (cards.some(card => !card)) return false;
  const tops = cards.map(card => card.getBoundingClientRect().top);
  return Math.max(...tops) - Math.min(...tops) < 1;
}, ids);
const soundRows = () => page.evaluate(() => {
  const rows = new Map();
  return [...document.querySelectorAll('.cedar-roadmap-course')].every(card => {
    const rect = card.getBoundingClientRect();
    const row = rows.get(card.dataset.row) || { top: rect.top, height: rect.height, semesters: new Set() };
    const valid = Math.abs(rect.top - row.top) < 1 && Math.abs(rect.height - row.height) < 1 &&
      rect.height >= card.scrollHeight && !row.semesters.has(card.dataset.semester);
    row.semesters.add(card.dataset.semester); rows.set(card.dataset.row, row);
    return valid;
  });
});
try {
  await connect(page, { tab: 'degree-explorer' });
  await waitForSelector(page, '[data-roadmap][data-ready]');
  check(await page.$$eval('.cedar-roadmap-semester', els => els.length === 8),
    'one degree starts with an eight-semester visual roadmap');
  check(await page.$$eval('.cedar-roadmap-semester', els => els.every(el => Number(el.dataset.plannedCredits) <= 16)),
    'every semester stays at or below 16 credits including other degree work');
  check(await alignedHeaders(), 'all year/semester headers and first tile rows align');
  check(await alignedCourses(['engl1', 'engl2']) && await soundRows(),
    'English composition courses share a row and all course rows align without clipping');
  check(await page.$$eval('[data-course-level="upper"]', els =>
    els.length > 0 && els.every(el => Number(el.dataset.semester) >= 5)),
    'upper-level degree courses begin in year three or later');
  check(await page.$$eval('.cedar-roadmap-flex', els => els.every(el =>
    Number(el.closest('.cedar-roadmap-semester').getAttribute('aria-label').split(' ')[1]) < 5
      ? el.innerText.includes('Gen Ed / lower-level') : el.innerText.includes('Upper-level / minor'))),
    'Gen Ed allowances appear early and later allowances identify upper-level work');
  check(await page.$$eval('[data-card-type="allowance"]', els => els.length > 0 && els.every(el =>
    Number(el.dataset.semester) < 5 && el.tagName === 'BUTTON' && el.getAttribute('aria-haspopup') === 'dialog')) &&
    await page.$$eval('.cedar-roadmap-flex[data-allowance-phase="foundation"]', els => els.length === 0),
    'early Gen Ed allowances are clickable course slots in the shared grid');
  check(await page.$$eval('.cedar-roadmap-semester', terms => terms.every(term =>
    [...term.querySelectorAll('.cedar-roadmap-course, .cedar-roadmap-flex')].reduce((sum, card) =>
      sum + Number(card.dataset.credits), 0) === Number(term.dataset.plannedCredits))),
    'course tiles and remaining allowances exactly account for every semester credit');
  await hoverCourse('java1');
  check(await page.$eval('.cedar-roadmap-hover', el => !el.hidden &&
    el.querySelector('.cedar-roadmap-hover-before').innerText.includes('CSCI 1210') &&
    el.querySelector('.cedar-roadmap-hover-after').innerText.includes('CSCI 2260')) &&
    await page.$eval('[data-node="computing0"]', el => el.classList.contains('is-before')) &&
    await page.$eval('[data-node="java2"]', el => el.classList.contains('is-after')) &&
    await page.$$eval('#shiny-modal, [data-history-node]', els => els.length === 0),
    'hover previews prerequisites and dependent courses without opening a modal or loading enrollment history');
  await page.screenshot({ path: '/tmp/cedar-degree-hover-chain.png', fullPage: false });
  await page.hover('.cedar-roadmap-hover');
  await waitForIdle(page);
  check(await page.$eval('.cedar-roadmap-hover', el => !el.hidden),
    'the preview stays readable when the pointer moves into it');
  await page.keyboard.press('Escape');
  check(await waitFor(page, () => document.querySelector('.cedar-roadmap-hover').hidden),
    'Escape dismisses a mouse preview even when keyboard focus is outside the board');
  await hoverCourse('java1');
  await page.mouse.move(0, 0);
  check(await waitFor(page, () => document.querySelector('.cedar-roadmap-hover').hidden &&
    document.querySelector('[data-roadmap]').dataset.chainNode === ''),
    'leaving an unselected course clears its temporary chain preview');
  await page.focus('.cedar-roadmap-scroll');
  await page.keyboard.press('Tab');
  check(await waitFor(page, () => document.querySelector('[data-roadmap]').dataset.previewNode === 'calc1') &&
    await page.$eval('[data-node="calc1"]', el => document.activeElement === el && !!el.getAttribute('aria-describedby')),
    'keyboard focus provides the same chain preview and accessible description');
  await page.keyboard.press('Escape');
  check(await page.$eval('.cedar-roadmap-hover', el => el.hidden), 'Escape dismisses the hover preview without opening enrollment data');
  await page.keyboard.press('Enter');
  await waitForPopup('calc1');
  check(await page.evaluate(() => {
    const dialog = document.querySelector('.cedar-roadmap-dialog');
    return document.querySelector('.cedar-roadmap-hover').hidden &&
      dialog.querySelector('.cedar-roadmap-history').getBoundingClientRect().top <
        dialog.querySelector('.cedar-roadmap-detail').getBoundingClientRect().top;
  }), 'activating a course opens enrollment history first and keeps catalog evidence available below');
  check(await page.$eval('.cedar-roadmap-evidence', el => el.innerText.includes('Mathematics sequence') && el.innerText.includes('MATH1512')) &&
    await page.$eval('.cedar-roadmap-evidence-location', el => el.href.includes('/programs/')),
    'a degree course quotes its requirement on the program page');
  const historyTable = await readReactable(page, 'degree_explorer-course_history_table');
  check(!historyTable.error && colIndex(historyTable.headers, 'Seats offered') >= 0 &&
    colIndex(historyTable.headers, 'Filled · first day') >= 0 && colIndex(historyTable.headers, 'First-day fill') >= 0 &&
    colIndex(historyTable.headers, 'Season frequency') >= 0,
    'one standard history table shows seats offered, first-day filled, fill percent and seasonal frequency');
  check(await page.$$eval('.cedar-roadmap-dialog .rt-table', els => els.length === 1) &&
    !historyTable.headers.some(header => header.toLowerCase().includes('census')),
    'the history popup uses a single CEDAR table with first-day measures');
  check(await page.$eval('.cedar-roadmap-history', el => !el.innerText.includes('student_id')),
    'history payload contains aggregate information only');
  await (await page.$(MODAL)).screenshot({ path: '/tmp/cedar-degree-course-popup.png' });
  await closePopup();
  check(await page.$eval('[data-node="calc1"]', el => document.activeElement === el),
    'Escape closes the popup and returns keyboard focus to its course');
  await hoverCourse('java1');
  await page.mouse.move(0, 0);
  check(await waitFor(page, () => document.querySelector('[data-roadmap]').dataset.chainNode === 'calc1') &&
    await page.$eval('[data-node="calc1"]', el => el.getAttribute('aria-pressed') === 'true'),
    'a temporary hover restores the last clicked course when the pointer leaves');
  await popup('calc1');
  check(await page.$eval('.cedar-roadmap-history', el => !el.innerText.includes('Loading')),
    'reopening the same course keeps its cached history visible');
  await closePopup();
  check(await semester('calc1') === 1, 'calculus-ready placement starts Calculus I in semester one');
  check(await page.$$eval('.cedar-roadmap-connectors path', els => els.length > 0),
    'selected course sequence has visible connectors');
  check(await page.$$eval('.cedar-roadmap-board details', els => els.length === 0),
    'the roadmap is visible without opening requirement accordions');
  const originalCalcTerm = await semester('calc1');
  await choose('degree_explorer-dx_start_season', 'spring');
  // textContent, not innerText: the year label is styled uppercase, and
  // innerText returns the rendered "YEAR 1 · SPRING".
  check(await page.$eval('.cedar-roadmap-year', el => el.textContent.includes('Spring')) &&
    await semester('calc1') === originalCalcTerm && await alignedHeaders(),
    'the start-season control labels the semesters without changing their course order or header alignment');
  const allowance = await page.$$eval('[data-card-type="allowance"]', els =>
    els.find(el => Number(el.dataset.credits) >= 3).dataset.node);
  const allowanceSeason = await page.$eval(`[data-node="${allowance}"]`, el => el.dataset.season);
  await hoverCourse(allowance);
  check(await page.$eval('.cedar-roadmap-hover-before', el => el.innerText.includes('Depends on the course chosen')) &&
    await page.$$eval('.cedar-roadmap-connectors path', els => els.length === 0) &&
    await page.$$eval(`[data-history-node="${allowance}"]`, els => els.length === 0),
    'hovering a Gen Ed slot explains the unselected choice without inventing prerequisites or loading suggestions');
  await popup(allowance);
  const suggestions = await readReactable(page, 'degree_explorer-course_history_table');
  const lastOffered = colIndex(suggestions.headers, 'Last offered');
  check(!suggestions.error && suggestions.rows.length > 0 &&
    ['Gen Ed area', 'Credits', 'Seats offered', 'Filled · first day', 'Campus', 'PoT'].every(name => colIndex(suggestions.headers, name) >= 0) &&
    lastOffered >= 0 && suggestions.rows.every(row => row[lastOffered].toLowerCase().includes(allowanceSeason)),
    'allowance popup lists matching-season Gen Ed choices with credits, seats, first-day enrollments and campus/session context');
  check(await page.$$eval('.cedar-roadmap-dialog .cedar-roadmap-detail', els => els.length === 0) &&
    await page.$eval('.cedar-roadmap-history', el => el.innerText.includes('not major-specific recommendations') && !el.innerText.includes('student_id')),
    'suggestions have no borrowed catalog quote and clearly disclose their historical, unreviewed status');
  await (await page.$(MODAL)).screenshot({ path: '/tmp/cedar-degree-gened-suggestions.png' });
  await page.setViewport({ width: 390, height: 844 });
  check(await page.$eval(MODAL, el => {
    const r = el.getBoundingClientRect(); return r.top >= 0 && r.left >= 0 && r.bottom <= window.innerHeight && r.right <= window.innerWidth;
  }), 'the Gen Ed suggestion popup stays inside a narrow screen with its own scrolling');
  await (await page.$(MODAL)).screenshot({ path: '/tmp/cedar-degree-gened-suggestions-mobile.png' });
  await page.setViewport({ width: 1440, height: 1000 });
  await closePopup();
  await choose('degree_explorer-dx_start_season', 'fall');
  const remainder = await page.$$eval('[data-card-type="allowance"]', els =>
    els.find(el => Number(el.dataset.credits) < 3).dataset.node);
  await popup(remainder);
  const remainderTable = await readReactable(page, 'degree_explorer-course_history_table');
  const creditFit = colIndex(remainderTable.headers, 'Credit fit');
  check(await page.$eval('.cedar-roadmap-history', el => el.innerText.includes('rather than a complete course')) &&
    creditFit >= 0 && remainderTable.rows.every(row => row[creditFit] === 'Needs more credits'),
    'small credit remainders are not portrayed as complete courses or quietly expanded to fit suggestions');
  await closePopup();
  await page.screenshot({ path: '/tmp/cedar-degree-gened-slots.png', fullPage: true });
  const programmingTerm = await semester('java1');
  await choose('degree_explorer-dx_math_start', 'intermediate');
  check((await Promise.all(['math1215', 'math1220', 'math1250', 'calc1'].map(semester))).join(',') === '1,2,3,4',
    'math entry adds the actual algebra, trig/precalculus and calculus sequence');
  check(await page.$$eval('.cedar-roadmap-semester', els => els.length > 8 && els.every(el => Number(el.dataset.plannedCredits) <= 16)),
    'extra math extends the workload beyond eight semesters without an overload');
  check(await page.$eval('[data-node="math1215"]', el => el.dataset.planningLevel === 'green' && el.innerText.includes('Chain start')) &&
    await page.$eval('[data-node="calc1"]', el => el.dataset.planningLevel === 'red' && el.dataset.prerequisites === '3'),
    'an entry course clearly starts a large chain while calculus signals its prerequisite burden');
  check(await page.evaluate(() => getComputedStyle(document.querySelector('[data-node="math1215"]')).backgroundColor !==
    getComputedStyle(document.querySelector('[data-node="calc1"]')).backgroundColor),
    'prerequisite planning changes tile fill color, not just a small border');
  check(await alignedHeaders(), 'extended nine-semester headers stay aligned');
  check(await alignedCourses(['math1215', 'math1220', 'math1250', 'calc1', 'calc2']) &&
    await alignedCourses(['engl1', 'engl2']) && await soundRows(),
    'added math keeps the whole preparation/calculus sequence horizontal without shifting English');
  await popup('java1');
  const javaState = await page.$eval('[data-history-node="java1"]', el => el.dataset.historyState);
  const javaTable = javaState === 'ready' ? await readReactable(page, 'degree_explorer-course_history_table') : null;
  const javaCourse = javaTable ? colIndex(javaTable.headers, 'Course') : -1;
  check(javaState === 'empty'
    ? await page.$eval('[data-history-node="java1"]', el => el.innerText.includes('Renamed courses'))
    : javaCourse >= 0 && javaTable.rows.length > 0 && javaTable.rows.every(row => row[javaCourse] === 'CSCI 1260'),
    'course history uses the exact current identifier without inferring an older equivalent');
  await closePopup();
  await popup('science1');
  check(await page.$eval('[data-node="science1"]', el => el.dataset.optionCount === '11' &&
    el.innerText.includes('14+ science credits') && el.innerText.includes('2 lecture/lab pairs')) &&
    await page.$eval('.cedar-roadmap-option-detail', el => el.querySelectorAll('li').length === 11 &&
      el.querySelectorAll('a').length === 19 &&
      el.querySelector('[data-option="chem1215"]').innerText.includes('4 credits together') &&
      el.querySelector('[data-option="chem1215"]').querySelectorAll('a').length === 2),
    'science cards summarize the shared 14-credit lab rule and the popup groups all 19 courses into 11 complete alternatives');
  check(await page.$eval('.cedar-roadmap-option-detail', el => el.innerText.includes('advanced options are not enumerated') &&
    el.innerText.includes('different science course')) &&
    await page.$eval('.cedar-roadmap-dialog-summary', el => !el.hidden && el.innerText.includes('2 lecture/lab pairs')),
    'science choices disclose distinct selections, the shared lab requirement and the unenumerated advanced alternatives');
  const scienceHistory = await page.$eval('[data-history-node="science1"]', el => el.dataset.historyState);
  check(['empty', 'ready'].includes(scienceHistory) &&
    await page.$eval('[data-history-node="science1"]', el => el.innerText.includes('alternatives')),
    'enumerated science alternatives use separate course histories including their paired labs');
  await (await page.$('.cedar-roadmap-option-detail')).screenshot({ path: '/tmp/cedar-degree-science-options.png' });
  await closePopup();
  await page.hover('[data-node="science1"]');
  await page.screenshot({ path: '/tmp/cedar-degree-science-card.png', fullPage: false });
  check(await alignedCourses(['science1', 'science2', 'science3', 'science4']) && await soundRows(),
    'the expanded science choices keep all four slots aligned without clipping or changing the 14-credit allowance');
  await page.keyboard.press('Escape');
  await page.setViewport({ width: 390, height: 844 });
  await waitForIdle(page);
  check(await alignedHeaders() && await soundRows() &&
    await page.evaluate(() => document.documentElement.scrollWidth <= window.innerWidth + 1) &&
    await page.$eval('[data-node="science1"] .cedar-roadmap-option-preview', el =>
      getComputedStyle(el).webkitLineClamp === '3' && el.scrollHeight > el.clientHeight),
    'science choices keep a three-line preview, aligned rows and contained scrolling on narrow screens');
  await popup('science1');
  check(await page.$eval(MODAL, el => {
    const r = el.getBoundingClientRect();
    return r.left >= 0 && r.right <= window.innerWidth && r.top >= 0 && r.bottom <= window.innerHeight &&
      el.querySelectorAll('.cedar-roadmap-option-detail a').length === 19;
  }), 'the narrow science popup preserves all lecture and lab options within its own scroll area');
  await (await page.$(MODAL)).screenshot({ path: '/tmp/cedar-degree-science-mobile.png' });
  await closePopup();
  await page.setViewport({ width: 1440, height: 1000 });
  check(await semester('linear') === 6 && await semester('numerical') === 7,
    'math-dependent upper-level courses move with the preparation sequence');
  check(await semester('java1') === programmingTerm, 'unrelated computing entry stays available');
  await choose('degree_explorer-dx_english_start', 'stretch');
  check((await Promise.all(['englX', 'englY', 'engl2'].map(semester))).join(',') === '1,2,3',
    'English stretch entry is shown as three successive course tiles');
  await popup('os');
  check(await page.$eval('[data-node="os"]', el => el.getAttribute('aria-pressed') === 'true') &&
    await page.$eval('[data-node="architecture"]', el => el.classList.contains('is-related')),
    'selecting a course highlights its prerequisite chain');
  check(await page.$eval('.cedar-roadmap-detail', el => el.innerText.includes('CS 341L')),
    'selected course explains its prerequisite and links to the catalog');
  check(await page.$eval('.cedar-roadmap-evidence-quote', el => el.innerText.includes('CS481')) &&
    await page.$eval('.cedar-roadmap-evidence-location', el => el.href.includes('/programs/')) &&
    await page.$eval('.cedar-roadmap-detail-course', el => el.href.includes('/courses/')),
    'degree evidence and course-description links remain distinct');
  await (await page.$('.cedar-roadmap-detail')).screenshot({ path: '/tmp/cedar-degree-catalog-proof.png' });
  await closePopup();
  await popup('math1215');
  check(await page.$eval('.cedar-roadmap-evidence-basis', el => el.innerText.includes('Preparation for MATH 1220')) &&
    await page.$eval('.cedar-roadmap-evidence-quote', el => el.innerText.includes('MATH1215')) &&
    await page.$eval('.cedar-roadmap-evidence-location', el => el.href.includes('/courses/')),
    'preparation cites the downstream prerequisite, rather than claiming it is a major course');
  await closePopup();
  await page.evaluate(() => window.scrollTo({ top: 0 }));
  await page.screenshot({ path: '/tmp/cedar-degree-roadmap-evidence.png', fullPage: true });
  await choose('degree_explorer-dx_catalog_id', 'biology-bs-2026');
  check(await page.$$eval('[data-roadmap]', els => els.length === 1) && await semester('bio1') === 1,
    'another degree uses the same single-program semester interface');
  check(await page.$$eval('[data-node="chem1"]', els => els.length === 1 && els[0].innerText.includes('Paired')),
    'chemistry lecture and lab are visibly paired in one semester');
  check(await semester('molecular') >= 5 && await page.$$eval('[data-course-level="upper"]', els =>
    els.every(el => Number(el.dataset.semester) >= 5)),
    'Biology uses the same later-stage rule for upper-level courses and groups');
  await popup('chem1');
  const pairedTable = await readReactable(page, 'degree_explorer-course_history_table');
  check(!pairedTable.error && colIndex(pairedTable.headers, 'Course') >= 0 && colIndex(pairedTable.headers, 'Campus') >= 0 &&
    colIndex(pairedTable.headers, 'PoT') >= 0,
    'paired course history retains exact course, campus and session columns');
  check(await page.$$eval('#degree_explorer-course_history_table input', els => els.length >= 2),
    'one history table can filter courses and campuses without switching between tables');
  await closePopup();
  check(await page.$$eval('[data-node="math1215"]', els => els.length === 1),
    'switching degrees preserves the student starting points');
  await choose('degree_explorer-dx_english_start', 'complete');
  check(await page.$eval('#degree_explorer-roadmap', el => el.innerText.includes('6 already completed')) &&
    await page.$$eval('.cedar-roadmap-semester', els => els.reduce((total, el) => total + Number(el.dataset.plannedCredits), 0) === 125),
    'completed English subtracts prior credits instead of replacing it with other work');
  await choose('degree_explorer-dx_english_start', 'stretch');
  await page.setViewport({ width: 390, height: 844 });
  await waitForIdle(page);
  check(await page.evaluate(() => document.documentElement.scrollWidth <= window.innerWidth + 1),
    'mobile layout confines wide roadmap scrolling to its own region');
  check(await alignedHeaders(), 'mobile year/semester headers retain identical heights');
  check(await alignedCourses(['englX', 'englY', 'engl2']) && await soundRows(),
    'stretch English stays in one aligned row on narrow screens without clipping wrapped course details');
  await popup('calc1');
  check(await page.$eval(MODAL, el => {
    const r = el.getBoundingClientRect(); return r.top >= 0 && r.bottom <= window.innerHeight && r.left >= 0 && r.right <= window.innerWidth;
  }), 'mobile popup stays within the screen with its own scroll area');
  await (await page.$(MODAL)).screenshot({ path: '/tmp/cedar-degree-course-popup-mobile.png' });
  await page.$eval('#shiny-modal .modal-body', el => { el.scrollTop = el.scrollHeight; });
  await closePopup();
  await popup('calc1');
  check(await page.$eval('#shiny-modal .modal-body', el => el.scrollTop === 0),
    'reopening a scrolled popup starts at enrollment history');
  await closePopup();
  await page.screenshot({ path: '/tmp/cedar-degree-roadmap-mobile.png', fullPage: false });
  await page.setViewport({ width: 1440, height: 1000 });

  await connect(page, { search: 'tab=degree-explorer&catalog_id=biology-bs-2026&math_start=algebra&english_start=composition2&start_season=spring' });
  // The link restores its fields in order; the season is last, so wait for it too.
  await waitForSelector(page, '[data-roadmap][data-ready][data-catalog="biology-bs-2026"][data-math-start="algebra"][data-english-start="composition2"][data-start-season="spring"]');
  check(await page.$eval('#degree_explorer-dx_catalog_id', el => el.selectize.getValue()) === 'biology-bs-2026' &&
    await semester('calc1') === 3 && await semester('engl2') === 1 &&
    await page.$eval('[data-roadmap]', el => el.dataset.startSeason === 'spring'),
    'deep links restore the degree, both starting points and starting season without a run button');
  // Capture what the copy button writes instead of reading the system clipboard.
  await page.evaluate(() => {
    window.cedarCopiedLink = null;
    navigator.clipboard.writeText = text => { window.cedarCopiedLink = text; return Promise.resolve(); };
  });
  await page.click('#degree_explorer-dx_copy_url');
  const copiedLink = await waitFor(page, () => !!window.cedarCopiedLink)
    ? new URL(await page.evaluate(() => window.cedarCopiedLink)) : null;
  check(!!copiedLink && copiedLink.searchParams.get('tab') === 'degree-explorer' &&
    copiedLink.searchParams.get('catalog_id') === 'biology-bs-2026' &&
    copiedLink.searchParams.get('math_start') === 'algebra' &&
    copiedLink.searchParams.get('english_start') === 'composition2' &&
    copiedLink.searchParams.get('start_season') === 'spring',
    'the copy button shares the degree, both starting points and the starting season');

  await choose('degree_explorer-dx_math_start', 'intermediate');
  const addedPrograms = [
    ['history-ba-2026', 'historiography', 'HIST491'],
    ['philosophy-ba-2026', 'philknowledge', 'PHIL352'],
    ['business-bba-2026', 'buscapstone', 'BUSA4988'],
    ['anthropology-ba-2026', 'anthstrategy', 'ANTH320'],
    ['physics-bs-2026', 'physmethods', 'PHYS366'],
  ];
  for (const [id, node, proof] of addedPrograms) {
    await choose('degree_explorer-dx_catalog_id', id);
    check(await page.$$eval('[data-roadmap]', els => els.length === 1) &&
      await page.$$eval('.cedar-roadmap-semester', els => els.every(el => Number(el.dataset.plannedCredits) <= 16)) &&
      await page.$$eval('[data-course-level="upper"]', els => els.length > 0 && els.every(el => Number(el.dataset.semester) >= 5)) &&
      await alignedHeaders() && await soundRows(), `${id} uses the same aligned board, 16-credit budget and later upper-level stage`);
    check(await page.$eval('#degree_explorer-dx_math_start', el => el.selectize.getValue()) === 'intermediate' &&
      await semester('math1215') === 1, `${id} preserves the selected placement when switching degrees`);
    if (id !== 'physics-bs-2026') {
      check(await page.$$('[data-node="calc1"]').then(els => els.length === 0) &&
        await semester('math1350') === 2, `${id} shows Intermediate Algebra then statistics without a calculus chain`);
    } else {
      check(await semester('calc1') === 4 && await page.$$('.cedar-roadmap-semester').then(els => els.length >= 10),
        'Physics preparation extends the calculus and physics chain to ten or more semesters');
      check(await alignedCourses(['physem1', 'physem2']) && await alignedCourses(['physquantum1', 'physquantum2']) &&
        await page.evaluate(() => document.querySelector('[data-node="physode"]').dataset.row !==
          document.querySelector('[data-node="physlinear"]').dataset.row),
        'Physics sequences stay horizontal while concurrent mathematics courses occupy separate rows');
    }
    if (id === 'history-ba-2026') {
      await hoverCourse('historiography');
      check(await page.$eval('.cedar-roadmap-hover-conditions', el => !el.hidden && el.innerText.includes('2+ upper-level History courses')) &&
        await page.$$eval('[data-node^="histupper"].is-qualifying', els => els.length === 6) &&
        await page.$$eval('.cedar-roadmap-connectors path[data-to="historiography"]', els => els.length === 0),
        'hover preserves the course-count condition and qualifying pool without inventing named prerequisites');
    }
    await popup(node);
    check(await page.$eval('.cedar-roadmap-evidence-quote', (el, proof) => el.innerText.includes(proof), proof) &&
      await page.$eval('.cedar-roadmap-evidence-location', el => el.href.includes('/programs/')),
      `${id} course popup cites the actual program requirement`);
    if (id === 'history-ba-2026') {
      check(await page.$eval('[data-node="historiography"]', el => el.dataset.planningLevel === 'conditional' &&
        el.dataset.prerequisites === '0' && el.innerText.includes('2+ upper-level History courses') && !el.innerText.includes('2 prereqs')),
        'HIST 491 shows a distinct coursework condition instead of two named prerequisites');
      check(await page.$$eval('[data-node^="histupper"].is-qualifying', els => els.length === 6) &&
        await page.$$eval('.cedar-roadmap-connectors path[data-to="historiography"]', els => els.length === 0),
        'selecting HIST 491 highlights the qualifying pool without named-course arrows');
      check(await page.$eval('.cedar-roadmap-condition-detail', el => el.innerText.includes('permission') &&
        el.innerText.includes('a minimum of two upper-division courses')),
        'condition details cite course-count and departmental-permission requirements separately');
      await (await page.$(MODAL)).screenshot({ path: '/tmp/cedar-degree-history-condition-popup.png' });
    }
    if (id === 'philosophy-ba-2026') {
      check(await page.$eval('[data-node="philbuddhist"]', el => el.innerText.includes('Choose 1 of 3 courses') &&
        ['PHIL 333', 'PHIL 334', 'PHIL 336'].every(code => el.innerText.includes(code)) &&
        el.dataset.planningLevel === 'unresolved'),
        'the Asian philosophy tile shows the complete three-course choice instead of requiring PHIL 333');
      check(await page.$eval('.cedar-roadmap-option-detail', el => el.querySelectorAll('li').length === 4 &&
        el.innerText.includes('PHIL 352') && el.innerText.includes('PHIL 455') && el.innerText.includes('PHIL2210')),
        'a set popup shows every option and keeps PHIL 352’s prerequisite attached to that option');
      await closePopup();
      await hoverCourse('philbuddhist');
      check(await page.$eval('.cedar-roadmap-hover-before', el => el.innerText.includes('Depends on the course chosen')) &&
        await page.$eval('.cedar-roadmap-hover-options', el => ['PHIL 333', 'PHIL 334', 'PHIL 336'].every(code => el.innerText.includes(code))),
        'a course-set hover keeps the complete alternatives and does not claim a fixed prerequisite chain');
      await popup('philbuddhist');
      check(await page.$eval('.cedar-roadmap-option-detail', el => el.querySelectorAll('li').length === 3 &&
        ['Buddhist Philosophy', 'Indian Philosophy', 'Chinese Philosophy'].every(title => el.innerText.includes(title)) &&
        [...el.querySelectorAll('a')].every(a => a.href.includes('/courses/view/'))),
        'the full Asian philosophy options have titles, credits and individual catalog description links');
      const optionHistory = await page.$eval('[data-history-node="philbuddhist"]', el => el.dataset.historyState);
      check(optionHistory === 'empty' || (optionHistory === 'ready' &&
        await page.$eval('[data-history-node="philbuddhist"]', el => el.innerText.includes('alternatives'))),
        'course-set history identifies the alternatives rather than treating them as a required bundle');
      await (await page.$(MODAL)).screenshot({ path: '/tmp/cedar-degree-philosophy-options-popup.png' });
      await closePopup();
      await page.screenshot({ path: '/tmp/cedar-degree-philosophy-options.png', fullPage: true });
      // Narrow semester columns exercise the three-line ellipsis treatment on a
      // real four-option set, while the modal retains all four complete names.
      await page.setViewport({ width: 390, height: 844 });
      const preview = await page.$eval('[data-node="philknowledge"] .cedar-roadmap-option-preview', el => ({
        title: el.title, clamp: Number(getComputedStyle(el).webkitLineClamp),
        totalHeight: el.scrollHeight, height: el.clientHeight, width: el.clientWidth,
      }));
      const rowsAligned = await soundRows();
      const clipped = preview.title.includes('PHIL 455') && preview.clamp === 3 && preview.totalHeight > preview.height;
      if (!clipped || !rowsAligned) console.log('Option preview geometry:', { ...preview, rowsAligned });
      check(clipped && rowsAligned,
        'long option lists use an ellipsis within the card while preserving the full set and row alignment');
      await (await page.$('[data-node="philknowledge"]')).screenshot({ path: '/tmp/cedar-degree-philosophy-ellipsis.png' });
      await page.setViewport({ width: 1440, height: 1000 });
      await popup('phillogic');
      check(await page.$eval('.cedar-roadmap-option-detail', el => el.innerText.includes('3–4 credits') && el.innerText.includes('upper-level')) &&
        await page.$eval('[data-node="phillogic"]', el => el.innerText.includes('Level varies')),
        'logic alternatives disclose variable credits and the upper-level option instead of silently treating both as introductory');
    }
    await closePopup();
    if (id === 'history-ba-2026') {
      await page.evaluate(() => window.scrollTo({ top: 0 }));
      await page.screenshot({ path: '/tmp/cedar-degree-history-conditions.png', fullPage: false });
    }
    if (id === 'business-bba-2026') {
      check(await page.$eval('[data-node="math1350"]', el => el.dataset.basis === 'degree' &&
        !el.innerText.includes('Suggested Gen Ed') && getComputedStyle(el).borderTopStyle === 'solid'),
        'Business statistics retains the solid styling of a named program requirement');
      check(await page.$eval('[data-node="buscapstone"]', el => el.dataset.planningLevel === 'red' && Number(el.dataset.prerequisites) > 8),
        'Business capstone visibly reflects its full prerequisite chain');
      await page.evaluate(() => window.scrollTo({ top: 0 }));
      await page.screenshot({ path: '/tmp/cedar-degree-business.png', fullPage: false });
    }
  }
  await page.$eval('[data-node="physmethods"]', el => el.scrollIntoView({ inline: 'center', block: 'nearest' }));
  await page.screenshot({ path: '/tmp/cedar-degree-physics.png', fullPage: false });
  await choose('degree_explorer-dx_math_start', 'algebra');
  await choose('degree_explorer-dx_catalog_id', 'history-ba-2026');
  check(await semester('math1350') === 1 &&
    await page.$eval('#degree_explorer-dx_math_start', el => el.selectize.getValue()) === 'algebra',
    'college-algebra placement remains selected and selects the shorter statistics route');
  check(await page.$eval('[data-node="math1350"]', el => el.dataset.basis === 'general' &&
    el.innerText.includes('Suggested Gen Ed') && getComputedStyle(el).borderTopStyle === 'dashed' && getComputedStyle(el).opacity === '1'),
    'a Gen Ed suggestion is visibly labelled and lighter with readable text');
  await popup('math1350');
  check(await page.$eval('.cedar-roadmap-evidence', el => el.innerText.includes('Illustrative Gen Ed math choice')),
    'History statistics is visibly an illustrative Gen Ed choice, not a named major requirement');
  await closePopup();
  await page.evaluate(() => window.scrollTo({ top: 0 }));
  await page.screenshot({ path: '/tmp/cedar-degree-history.png', fullPage: false });
  await connect(page, { search: 'tab=degree-explorer&catalog_id=business-bba-2026&math_start=algebra&english_start=stretch' });
  await waitForSelector(page, '[data-roadmap][data-ready][data-catalog="business-bba-2026"][data-math-start="algebra"][data-english-start="stretch"]');
  check(await semester('math1350') === 1 && await semester('engl2') === 3 && await semester('buswriting') === 4,
    'a new-program deep link restores its statistics route and the full English-to-business-writing sequence');

  await connect(page, { tab: 'pathways' });
  await setInput(page, 'pathways-population-population_type', 'dept');
  await setInput(page, 'pathways-population-dept_code', process.env.CEDAR_DEPT || 'HIST');
  await setInput(page, 'pathways-population-population_scope', 'all');
  await setInput(page, 'pathways-population-student_level', 'Undergraduate');
  await waitForIdle(page);
  await runAndWait(page, 'pathways-population-build_btn', { timeout: 180000 });
  await openSubTab(page, 'Course paths');
  await runAndWait(page, 'pathways-course_paths-button', { timeout: 180000 });
  await waitForSelector(page, '#pathways-course_paths-path_plot .heatmaplayer', { nonEmpty: false });
  const scope = await page.$eval('#pathways-course_paths-path_scope', el => el.innerText);
  check(scope.includes('observed students') && scope.includes('Through') && scope.includes('suppressed'),
    'Course paths uses the shared population and reports the data edge and suppression');
  const table = await readReactable(page, 'pathways-course_paths-path_courses');
  check(!table.error && table.rows.length > 0 && colIndex(table.headers, 'Campus') >= 0,
    'moved course detail retains observed data and delivery campus');
  await page.$eval('#pathways-course_paths-path_scope', el => el.scrollIntoView({ block: 'start' }));
  await page.screenshot({ path: '/tmp/cedar-course-paths.png', fullPage: false });
  check(jsErrors.length === 0, 'no uncaught JavaScript errors');
} catch (error) {
  failures.push(error.message);
  console.error(error);
  await page.screenshot({ path: '/tmp/cedar-degree-explorer-failure.png', fullPage: false });
} finally {
  await browser.close();
}
console.log(`${passed} passed, ${failures.length} failed`);
if (failures.length) process.exitCode = 1;
