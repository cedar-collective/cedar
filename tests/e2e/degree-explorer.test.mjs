// Adaptive semester planning and the separate, population-aware Course paths subtab.
// Use --course-paths-only for a focused check of the nested Pathways report.
//
// Computer Science, History, Philosophy and Business are compiled boards
// (institution/unm/degree_drafts/, since #309): their tiles are named by rule
// (cs_361l, intro_1, science_1, hist_491, asian_1, busa_4988). The math and
// English routes (calc1, math1215, engl1, englX) and the hand-built boards
// (Biology, Anthropology, Physics, the health programs) keep their own names.
// The compiled tile ids come from the board files, not the app source:
// check-ids-ignore: asian_1, busa_4988, cs_361l, cs_481, csci_2293, csci_2310, hist_491, knowledge_1, logic_1, math_1522, phil_2210, science_1, stat_345
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
// Gen Ed heads the board, then math/writing, elective/minor cards and the
// program's own courses; each semester's reading order follows the rows.
const bandsInOrder = () => page.evaluate(() => {
  const cards = selector => [...document.querySelectorAll(selector)];
  const foundation = el => ['math', 'writing'].includes(el.dataset.rowGroup);
  const genEd = cards('[data-card-type="allowance"][data-purpose="gen_ed"]');
  const electives = cards('[data-card-type="allowance"][data-purpose="elective"]');
  const mathWriting = cards('[data-card-type="course"]').filter(foundation);
  const program = cards('[data-card-type="course"]').filter(el => !foundation(el));
  const above = (upper, lower) => !upper.length || !lower.length ||
    Math.max(...upper.map(el => el.getBoundingClientRect().bottom)) <
      Math.min(...lower.map(el => el.getBoundingClientRect().top));
  return genEd.length > 0 && electives.length > 0 && program.length > 0 &&
    above(genEd, [...mathWriting, ...electives, ...program]) &&
    above(mathWriting, electives) && above(electives, program) &&
    cards('.cedar-roadmap-courses').every(term => [...term.children].every((el, i, tiles) =>
      i === 0 || Number(tiles[i - 1].dataset.row) < Number(el.dataset.row)));
});
const checkCommunicationOverlap = async () => {
  check(await page.$eval('[data-node="communication_elective_1"]', el => el.dataset.optionCount === '3' &&
    ['COMM1130', 'ENGL2120', 'ENGL2210'].every(text => el.innerText.includes(text))) &&
    await page.$$eval('[data-purpose="gen_ed"][data-gen-ed-area="I"]', els =>
      els.some(el => el.innerText.includes('May be covered by a program choice'))),
    'CS Communication lists all three choices and the Gen Ed slot it may cover says so');
};
const checkAnthropologyCoverage = async () => {
  const prior = await page.$eval('[data-roadmap]', el => ({math: el.dataset.mathStart, english: el.dataset.englishStart, season: el.dataset.startSeason}));
  // Reset placement so this scenario matches the source-linked default
  // example: four unfilled three-credit areas, other space stays elective.
  await choose('degree_explorer-dx_math_start', 'calculus');
  await choose('degree_explorer-dx_english_start', 'composition');
  await choose('degree_explorer-dx_start_season', 'fall');
  check(await page.$$eval('[data-purpose="gen_ed"]', els => els.length === 4 &&
    els.reduce((sum, el) => sum + Number(el.dataset.credits), 0) === 12) &&
    await page.$$eval('[data-purpose="elective"]', els => els.length > 0 &&
      els.every(el => Number(el.dataset.credits) < 3 || el.innerText.includes(
        el.dataset.allowancePhase === 'advanced' ? 'upper level may count' : 'Gen Ed not required'))),
    'Anthropology identifies four Gen Ed areas; other cards are elective/minor space, upper level later');
  check(await page.$eval('.cedar-roadmap-coverage', el => el.innerText.includes('19 of 31') &&
    el.innerText.includes('48 credits') && el.innerText.includes('27 more needed')) &&
    await page.$eval('[data-node="antharch"]', el => el.innerText.includes('Also Gen Ed')),
    'the plan explains overlapping major/Gen Ed credits and the standard college upper-level balance');
  const electiveId = await page.$$eval('[data-purpose="elective"]', els =>
    els.find(el => Number(el.dataset.credits) >= 3).dataset.node);
  await popup(electiveId);
  await page.evaluate(() => Reactable.setFilter('degree_explorer-course_history_table', 'course_level', 'upper'));
  await waitFor(page, () => [...document.querySelectorAll('#degree_explorer-course_history_table .rt-tbody .rt-tr')]
    .some(row => row.innerText.includes('upper')));
  const options = await readReactable(page, 'degree_explorer-course_history_table');
  const levelColumn = colIndex(options.headers, 'Level');
  check(!options.error && levelColumn >= 0 && options.rows.some(row => row[levelColumn] === 'upper') &&
    await page.$eval('.cedar-roadmap-dialog-summary', el => el.innerText.includes('does not have to be Gen Ed or lower division')),
    'elective options include upper-level courses and clearly state that Gen Ed is optional');
  await closePopup();
  await page.screenshot({ path: '/tmp/cedar-degree-anthropology-coverage.png', fullPage: true });
  await choose('degree_explorer-dx_english_start', prior.english);
  await choose('degree_explorer-dx_start_season', prior.season);
  await choose('degree_explorer-dx_math_start', prior.math);
};
const checkAdminSharedRules = async () => {
  await connect(page, { tab: 'data-usage' });
  await openSubTab(page, 'Catalog Review');
  await waitForSelector(page, '#catalog_review-rules-table .rt-table');
  await page.$eval('#catalog_review-rules-catalog', el => el.selectize.setValue('anthropology-ba-2026'));
  await waitForIdle(page);
  await page.evaluate(() => Reactable.setSearch('catalog_review-rules-table', 'Shared Gen Ed allocation'));
  await waitFor(page, () => document.getElementById('catalog_review-rules-table').innerText.includes('Shared Gen Ed allocation'));
  const sharedRules = await readReactable(page, 'catalog_review-rules-table');
  check(!sharedRules.error && sharedRules.rows.length === 8 &&
    sharedRules.rows.every(row => row.join(' ').includes('Shared Gen Ed allocation')) &&
    await page.$eval('#catalog_review-rules-table', el => [...el.querySelectorAll('a')]
      .some(link => link.href.includes('/programs/Sk0wRqKHs'))),
    'Admin exposes the same eight source-linked Gen Ed allocation rules as the degree graph');
  await page.screenshot({ path: '/tmp/cedar-degree-admin-shared-rules.png', fullPage: false });
};
const checkDegreeExplorer = async () => {
  await connect(page, { tab: 'degree-explorer' });
  await waitForSelector(page, '[data-roadmap][data-ready]');
  // The math picker opens on College Algebra, the start degree_roadmap_starts.csv
  // marks (`opens`). The scenarios below were written from the calculus start.
  check(await page.$eval('#degree_explorer-dx_math_start', el => el.value) === 'algebra' &&
    await page.$eval('[data-roadmap]', el => el.dataset.mathStart === 'algebra'),
    'the page opens on the College Algebra math start');
  await choose('degree_explorer-dx_math_start', 'calculus');
  // The degrees read alphabetically; a college narrows them to its own.
  const labels = id => page.evaluate(id => Object.values(document.getElementById(id).selectize.options)
    .sort((a, b) => a.$order - b.$order).map(o => o.label), id);
  const degrees = await labels('degree_explorer-dx_catalog_id');
  check(degrees.length > 10 && degrees.every((label, i) => i === 0 ||
      degrees[i - 1].localeCompare(label, 'en', { sensitivity: 'base' }) <= 0),
    `the ${degrees.length} degrees are listed alphabetically`);
  await page.evaluate(() => document.getElementById('degree_explorer-dx_college').selectize.setValue('EN'));
  check(await waitFor(page, () => {
      const z = document.getElementById('degree_explorer-dx_catalog_id').selectize;
      const labels = Object.values(z.options).map(o => o.label);
      return labels.length >= 2 && labels.length < 10 && labels.some(l => l.startsWith('Computer Science'));
    }, { timeout: 30000 }),
    'School of Engineering narrows the degree list to its own degrees, Computer Science among them');
  await choose('degree_explorer-dx_catalog_id', 'cs-bs-2026');
  // Back to every college: the degree in view stays.
  await page.evaluate(() => document.getElementById('degree_explorer-dx_college').selectize.setValue('all'));
  check(await waitFor(page, () => Object.keys(document.getElementById('degree_explorer-dx_catalog_id').selectize.options).length > 10) &&
    await page.$eval('#degree_explorer-dx_catalog_id', el => el.value) === 'cs-bs-2026',
    'All colleges restores every degree and keeps Computer Science in view');
  await waitForIdle(page);
  // Condensed cards first: code, title and credits only, empty rows collapsed.
  const tileHeights = () => page.$$eval('.cedar-roadmap-course', els => els.map(el => el.getBoundingClientRect().height));
  const condensedHeights = await tileHeights();
  check(await page.$eval('[data-roadmap]', el => el.dataset.view === 'condensed') &&
    Math.max(...condensedHeights) < 90 &&
    await page.$$eval('.cedar-roadmap-course .cedar-roadmap-prereq-count, .cedar-roadmap-course .cedar-roadmap-chain-badge',
      els => els.length > 0 && els.every(el => getComputedStyle(el).display === 'none')),
    `the board opens with condensed cards (tallest ${Math.round(Math.max(...condensedHeights))}px), detail hidden`);
  check(await soundRows() && await alignedHeaders() &&
    await page.$$eval('.cedar-roadmap-course', els => els.every(el => {
      const tile = el.getBoundingClientRect(), term = el.closest('.cedar-roadmap-semester').getBoundingClientRect();
      return tile.left >= term.left - 1 && tile.right <= term.right + 1;
    })),
    'condensed rows still align, and every card stays inside its semester column');
  const linkCount = await page.$eval('.cedar-roadmap-links', el => JSON.parse(el.textContent).length);
  check(linkCount > 0 && await page.$$eval('.cedar-roadmap-connectors path', (els, n) =>
    els.length === n && els.every(el => el.classList.contains('cedar-roadmap-link-faint')), linkCount),
    `condensed cards draw all ${linkCount} prerequisite links faintly with nothing hovered`);
  await hoverCourse('cs_361l');
  check(await page.$$eval('.cedar-roadmap-connectors path', (els, n) => els.length === n &&
      els.some(el => el.classList.contains('cedar-roadmap-link-before')) &&
      els.some(el => el.classList.contains('cedar-roadmap-link-faint')), linkCount) &&
    await page.$eval('.cedar-roadmap-connectors', el => el.classList.contains('has-chain')),
    'a hovered chain is drawn over the faint links');
  check(await page.$$eval('.cedar-roadmap-connectors path', els => els.length > 0) &&
    await page.$eval('.cedar-roadmap-hover', el => el.querySelector('.cedar-roadmap-hover-before').innerText.includes('CSCI 1230')),
    'condensed cards keep the hover preview and its prerequisite arrows');
  await page.mouse.move(0, 0);
  await page.screenshot({ path: '/tmp/cedar-degree-condensed.png', fullPage: true });
  await page.click('[data-roadmap-view="detailed"]');
  check(await waitFor(page, () => document.querySelector('[data-roadmap]').dataset.chainNode === '' &&
    !document.querySelector('.cedar-roadmap-connectors .cedar-roadmap-link-faint')),
    'Detailed cards draw no faint links; lines appear only for a hovered chain');
  check(await waitFor(page, () => document.querySelector('[data-roadmap]').dataset.view === 'detailed' &&
    getComputedStyle(document.querySelector('.cedar-roadmap-course .cedar-roadmap-prereq-count')).display !== 'none') &&
    Math.max(...await tileHeights()) > Math.max(...condensedHeights),
    'Detailed restores every line of each card');
  check(await page.$$eval('.cedar-roadmap-semester', els => els.length === 8),
    'one degree starts with an eight-semester visual roadmap');
  check(await page.$$eval('.cedar-roadmap-semester', els => els.every(el => Number(el.dataset.plannedCredits) <= 16)),
    'every semester stays at or below 16 credits including other degree work');
  check(await alignedHeaders(), 'all year/semester headers and first tile rows align');
  await checkCommunicationOverlap();

  check(await alignedCourses(['engl1', 'engl2']) && await soundRows(),
    'English composition courses share a row and all course rows align without clipping');
  check(await page.$$eval('[data-course-level="upper"]', els =>
    els.length > 0 && els.every(el => Number(el.dataset.semester) >= 5)),
    'upper-level degree courses begin in year three or later');
  check(await page.$$eval('[data-card-type="allowance"][data-purpose="elective"][data-allowance-phase="advanced"]', els =>
    els.length > 0 && els.every(el => el.innerText.includes('Elective / minor') &&
      (el.innerText.includes('upper level may count') || Number(el.dataset.credits) < 3))),
    'later semesters show elective/minor space as full-size cards, with upper-level options');
  check(await page.$$eval('[data-card-type="allowance"]', els => els.length > 0 && els.every(el =>
    el.tagName === 'BUTTON' && el.getAttribute('aria-haspopup') === 'dialog')),
    'Gen Ed and elective/minor allowances are clickable course slots in the shared grid');
  check(await bandsInOrder(),
    'Gen Ed heads the board, then math/writing, elective/minor cards and the program, in reading order');
  await page.screenshot({ path: '/tmp/cedar-degree-gen-ed-top.png', fullPage: true });
  check(await page.$$eval('.cedar-roadmap-semester', terms => terms.every(term =>
    [...term.querySelectorAll('.cedar-roadmap-course')].reduce((sum, card) =>
      sum + Number(card.dataset.credits), 0) === Number(term.dataset.plannedCredits))),
    'course tiles and remaining allowances exactly account for every semester credit');
  await hoverCourse('cs_361l');
  check(await page.$eval('.cedar-roadmap-hover', el => !el.hidden &&
    el.querySelector('.cedar-roadmap-hover-before').innerText.includes('CSCI 1230') &&
    el.querySelector('.cedar-roadmap-hover-after').innerText.includes('CS 362')) &&
    await page.$eval('[data-node="csci_1230"]', el => el.classList.contains('is-before')) &&
    await page.$eval('[data-node="cs_362"]', el => el.classList.contains('is-after')) &&
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
  await hoverCourse('cs_361l');
  await page.mouse.move(0, 0);
  check(await waitFor(page, () => document.querySelector('.cedar-roadmap-hover').hidden &&
    document.querySelector('[data-roadmap]').dataset.chainNode === ''),
    'leaving an unselected course clears its temporary chain preview');
  await page.focus('.cedar-roadmap-scroll');
  await page.keyboard.press('Tab');
  const firstTile = await page.$eval('.cedar-roadmap-courses > *', el => el.dataset.node);
  check(await waitFor(page, id => document.querySelector('[data-roadmap]').dataset.previewNode === id,
    { args: [firstTile] }) && await page.$eval(`[data-node="${firstTile}"]`, el =>
      document.activeElement === el && !!el.getAttribute('aria-describedby')),
    'keyboard entry reaches the first tile in reading order with an accessible preview');
  const genEdOption = await page.$eval('[data-card-type="allowance"][data-purpose="gen_ed"]', el => el.dataset.node);
  await page.focus(`[data-node="${genEdOption}"]`);
  check(await waitFor(page, id => document.querySelector('[data-roadmap]').dataset.previewNode === id,
    { args: [genEdOption] }) && await page.$eval(`[data-node="${genEdOption}"]`, el =>
      document.activeElement === el && !!el.getAttribute('aria-describedby')),
    'keyboard focus on a Gen Ed option gives it an accessible preview');
  await page.focus('[data-node="calc1"]');
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
  check(await page.$eval('.cedar-roadmap-evidence', el => el.innerText.includes('MATH1512')) &&
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
  await hoverCourse('cs_361l');
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
  check(await page.$eval('[data-roadmap]', el => el.dataset.view === 'detailed' && !el.classList.contains('cedar-roadmap--condensed')),
    'the chosen card view survives a redrawn board');
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
    ['Gen Ed area', 'Level', 'Credits', 'Seats offered', 'Filled · first day', 'Campus', 'PoT'].every(name => colIndex(suggestions.headers, name) >= 0) &&
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
  const programmingTerm = await semester('csci_2293');
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
  check(await alignedCourses(['math1215', 'math1220', 'math1250', 'calc1', 'math_1522']) &&
    await alignedCourses(['engl1', 'engl2']) && await soundRows(),
    'added math keeps the whole preparation/calculus sequence horizontal without shifting English');
  await popup('csci_2310');
  const discreteState = await page.$eval('[data-history-node="csci_2310"]', el => el.dataset.historyState);
  const discreteTable = discreteState === 'ready' ? await readReactable(page, 'degree_explorer-course_history_table') : null;
  const discreteCourse = discreteTable ? colIndex(discreteTable.headers, 'Course') : -1;
  check(discreteState === 'empty'
    ? await page.$eval('[data-history-node="csci_2310"]', el => el.innerText.includes('Renamed courses'))
    : discreteCourse >= 0 && discreteTable.rows.length > 0 && discreteTable.rows.every(row => row[discreteCourse] === 'CSCI 2310'),
    'course history uses the exact current identifier without inferring an older equivalent');
  await closePopup();
  // The compiled reading lists each science course and lab as its own option.
  await popup('science_1');
  check(await page.$eval('[data-node="science_1"]', el => el.dataset.optionCount === '19' &&
    el.innerText.includes('14 science credits') && el.innerText.includes('paired labs')) &&
    await page.$eval('.cedar-roadmap-option-detail', el => el.querySelectorAll('li').length === 19 &&
      el.querySelectorAll('a').length === 19 && el.innerText.includes('ASTR 2110L')),
    'science cards state the shared 14-credit lab rule and the popup lists all 19 courses and labs');
  check(await page.$eval('.cedar-roadmap-dialog-summary', el => !el.hidden && el.innerText.includes('Gen Ed approval')),
    'science choices say an open choice is not counted as Gen Ed coverage');
  const scienceHistory = await page.$eval('[data-history-node="science_1"]', el => el.dataset.historyState);
  check(['empty', 'ready'].includes(scienceHistory) &&
    await page.$eval('[data-history-node="science_1"]', el => el.innerText.includes('alternatives')),
    'science alternatives use separate course histories');
  await (await page.$('.cedar-roadmap-option-detail')).screenshot({ path: '/tmp/cedar-degree-science-options.png' });
  await closePopup();
  await page.hover('[data-node="science_1"]');
  await page.screenshot({ path: '/tmp/cedar-degree-science-card.png', fullPage: false });
  check(await soundRows(), 'the science choices keep every course row aligned without clipping');
  await page.keyboard.press('Escape');
  await page.setViewport({ width: 390, height: 844 });
  await waitForIdle(page);
  check(await alignedHeaders() && await soundRows() &&
    await page.evaluate(() => document.documentElement.scrollWidth <= window.innerWidth + 1),
    'science choices keep aligned rows and contained scrolling on narrow screens');
  await popup('science_1');
  check(await page.$eval(MODAL, el => {
    const r = el.getBoundingClientRect();
    return r.left >= 0 && r.right <= window.innerWidth && r.top >= 0 && r.bottom <= window.innerHeight &&
      el.querySelectorAll('.cedar-roadmap-option-detail a').length === 19;
  }), 'the narrow science popup keeps all 19 options within its own scroll area');
  await (await page.$(MODAL)).screenshot({ path: '/tmp/cedar-degree-science-mobile.png' });
  await closePopup();
  await page.setViewport({ width: 1440, height: 1000 });
  const [calcTerm, calc2Term, statTerm] = await Promise.all(['calc1', 'math_1522', 'stat_345'].map(semester));
  check(calcTerm === 4 && calc2Term > calcTerm && statTerm > calc2Term,
    `math-dependent courses move with the preparation sequence (Calculus I ${calcTerm}, II ${calc2Term}, STAT 345 ${statTerm})`);
  check(await semester('csci_2293') === programmingTerm, 'unrelated computing course stays where it was');
  await choose('degree_explorer-dx_english_start', 'stretch');
  check((await Promise.all(['englX', 'englY', 'engl2'].map(semester))).join(',') === '1,2,3',
    'English stretch entry is shown as three successive course tiles');
  await popup('cs_481');
  check(await page.$eval('[data-node="cs_481"]', el => el.getAttribute('aria-pressed') === 'true') &&
    await page.$eval('[data-node="cs_341l"]', el => el.classList.contains('is-related')),
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
  check(await page.$eval('.cedar-roadmap-evidence-basis', el => el.innerText.includes('Preparation added by the selected starting route')) &&
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
  check(await bandsInOrder(), 'the board keeps its bands in order on narrow, extended plans');
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
  // The link button is a menu: Copy link, or Make this my start page.
  await page.click('#degree_explorer-dx_copy_url_menu');
  await page.waitForSelector('#degree_explorer-dx_copy_url', { visible: true });
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
    ['history-ba-2026', 'hist_491', 'HIST491'],
    ['philosophy-ba-2026', 'phil_2210', 'PHIL2210'],
    ['business-bba-2026', 'busa_4988', 'BUSA4988'],
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
    if (id === 'anthropology-ba-2026') await checkAnthropologyCoverage();
    if (id === 'history-ba-2026') {
      await hoverCourse('hist_491');
      check(await page.$eval('.cedar-roadmap-hover-conditions', el => !el.hidden && el.innerText.includes('2+ upper-division history courses')) &&
        await page.$$eval('[data-node^="upper_electives_"].is-qualifying', els => els.length === 6) &&
        await page.$$eval('.cedar-roadmap-connectors path[data-to="hist_491"]', els => els.length === 0),
        'hover preserves the course-count condition and qualifying pool without inventing named prerequisites');
    }
    await popup(node);
    check(await page.$eval('.cedar-roadmap-evidence-quote', (el, proof) => el.innerText.includes(proof), proof) &&
      await page.$eval('.cedar-roadmap-evidence-location', el => el.href.includes('/programs/')),
      `${id} course popup cites the actual program requirement`);
    if (id === 'history-ba-2026') {
      check(await page.$eval('[data-node="hist_491"]', el => el.dataset.planningLevel === 'conditional' &&
        el.dataset.prerequisites === '0' && !el.innerText.includes('2 prereqs')),
        'HIST 491 shows a distinct coursework condition instead of two named prerequisites');
      check(await page.$$eval('[data-node^="upper_electives_"].is-qualifying', els => els.length === 6) &&
        await page.$$eval('.cedar-roadmap-connectors path[data-to="hist_491"]', els => els.length === 0),
        'selecting HIST 491 highlights the qualifying pool without named-course arrows');
      check(await page.$eval('.cedar-roadmap-condition-detail', el => el.innerText.includes('permission') &&
        el.innerText.includes('a minimum of two upper-division courses')),
        'condition details cite course-count and departmental-permission requirements separately');
      await (await page.$(MODAL)).screenshot({ path: '/tmp/cedar-degree-history-condition-popup.png' });
    }
    if (id === 'philosophy-ba-2026') {
      // ISSUES I64: every 400-level elective waits for the senior-level semester.
      check(await page.$$eval('[data-node^="elective_count_400_"]', els => els.length === 2 &&
        els.every(el => Number(el.dataset.semester) >= 6 && el.dataset.courseLevel === 'upper')),
        'the two 400-level Philosophy electives start in semester 6 or later');
      await closePopup();
      check(await page.$eval('[data-node="asian_1"]', el => el.innerText.includes('Choose 1 of 3 courses') &&
        ['PHIL333', 'PHIL334', 'PHIL336'].every(code => el.innerText.includes(code)) &&
        el.dataset.planningLevel === 'unresolved'),
        'the Asian philosophy tile shows the complete three-course choice instead of requiring PHIL 333');
      await hoverCourse('asian_1');
      check(await page.$eval('.cedar-roadmap-hover-before', el => el.innerText.includes('Depends on the course chosen')) &&
        await page.$eval('.cedar-roadmap-hover-options', el => ['PHIL 333', 'PHIL 334', 'PHIL 336'].every(code => el.innerText.includes(code))),
        'a course-set hover keeps the complete alternatives and does not claim a fixed prerequisite chain');
      await popup('asian_1');
      check(await page.$eval('.cedar-roadmap-option-detail', el => el.querySelectorAll('li').length === 3 &&
        ['Buddhist Philosophy', 'Indian Philosophy', 'Chinese Philosophy'].every(title => el.innerText.includes(title)) &&
        [...el.querySelectorAll('a')].every(a => a.href.includes('/courses/'))),
        'the full Asian philosophy options have titles, credits and individual catalog description links');
      const optionHistory = await page.$eval('[data-history-node="asian_1"]', el => el.dataset.historyState);
      check(optionHistory === 'empty' || (optionHistory === 'ready' &&
        await page.$eval('[data-history-node="asian_1"]', el => el.innerText.includes('alternatives'))),
        'course-set history identifies the alternatives rather than treating them as a required bundle');
      await (await page.$(MODAL)).screenshot({ path: '/tmp/cedar-degree-philosophy-options-popup.png' });
      await closePopup();
      await popup('knowledge_1');
      check(await page.$eval('.cedar-roadmap-option-detail', el => el.querySelectorAll('li').length === 4 &&
        el.innerText.includes('PHIL 352') && el.innerText.includes('PHIL 455')),
        'a set popup shows every option');
      await closePopup();
      await page.screenshot({ path: '/tmp/cedar-degree-philosophy-options.png', fullPage: true });
      // Narrow semester columns exercise the three-line ellipsis on a real
      // four-option set, while the popup keeps all four names.
      await page.setViewport({ width: 390, height: 844 });
      const preview = await page.$eval('[data-node="knowledge_1"] .cedar-roadmap-option-preview', el => ({
        title: el.title, clamp: Number(getComputedStyle(el).webkitLineClamp),
        totalHeight: el.scrollHeight, height: el.clientHeight,
      }));
      const rowsAligned = await soundRows();
      const clipped = preview.title.includes('PHIL 455') && preview.clamp === 3 && preview.totalHeight > preview.height;
      if (!clipped || !rowsAligned) console.log('Option preview geometry:', { ...preview, rowsAligned });
      check(clipped && rowsAligned,
        'long option lists use an ellipsis within the card while preserving the full set and row alignment');
      await page.setViewport({ width: 1440, height: 1000 });
      await popup('logic_1');
      check(await page.$eval('.cedar-roadmap-option-detail', el => el.innerText.includes('3–4 credits') && el.innerText.includes('upper-level') &&
        el.innerText.includes('lower-level')),
        'logic alternatives disclose variable credits and that one option is upper level');
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
      check(await page.$eval('[data-node="busa_4988"]', el => el.dataset.planningLevel === 'red' && Number(el.dataset.prerequisites) > 8),
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
  check(await page.$eval('.cedar-roadmap-evidence', el => el.innerText.includes('Illustrative general education course') &&
    el.innerText.includes('does not require it')),
    'History statistics is visibly an illustrative Gen Ed choice, not a named major requirement');
  await closePopup();
  await page.evaluate(() => window.scrollTo({ top: 0 }));
  await page.screenshot({ path: '/tmp/cedar-degree-history.png', fullPage: false });
  await page.click('#degree_explorer-show_rules');
  await waitForSelector(page, '#degree_explorer-plan_rules .rt-table');
  check(await page.$eval('#degree_explorer-plan_rules', el => el.textContent.includes('Readable rule') && el.textContent.includes('lower-division History credits')),
    'the chart opens readable rules from its own active scenario');
  await closePopup();
  for (const [catalog, sample] of [
    ['population-health-bs-2026', 'PH 475'],
    ['medical-laboratory-bs-2026', 'MEDL 453'],
    ['nursing-bsn-2026', 'NMNC 4510'],
    ['radiologic-nuclear-bs-2026', 'NUCM 400']
  ]) {
    await choose('degree_explorer-dx_catalog_id', catalog);
    check(await page.$eval('[data-roadmap]', (el, code) => el.innerText.includes(code), sample), `${catalog}: named health courses are visible`);
    check(await page.$$eval('.cedar-roadmap-semester', els => els.every(el => Number(el.dataset.plannedCredits) <= 16)),
      `${catalog}: all semester workloads stay within 16 credits`);
    check(await alignedHeaders() && await soundRows(), `${catalog}: headers and course rows remain aligned`);
    if (catalog === 'nursing-bsn-2026') {
      check(await page.$eval('[data-node="nursing-level-1"]', el => el.innerText.includes('NMNC 3110') && el.innerText.includes('BIOL 2225')),
        'Nursing retains the complete required same-level course block');
      await page.screenshot({ path: '/tmp/cedar-degree-nursing.png', fullPage: false });
    }
    if (catalog === 'population-health-bs-2026') check(await page.$eval('[data-node="poph-missing-1"]', el => el.innerText.includes('unknown')),
      'broken Population Health catalog entries stay visible as explicitly unresolved placeholders');
    await choose('degree_explorer-dx_math_start', 'intermediate');
    check(await page.$$eval('.cedar-roadmap-semester', els => els.every(el => Number(el.dataset.plannedCredits) <= 16)),
      `${catalog}: additional math preparation also respects the credit maximum`);
    await choose('degree_explorer-dx_math_start', 'algebra');
  }
  // A field's B.A. and B.S. share a name in Banner but not program codes: each
  // map states its own and never its sibling's.
  const programCodes = () => page.$$eval('p.text-hint', els => {
    const note = els.find(el => el.innerText.startsWith('Banner program codes for this degree'));
    return note ? note.innerText.split(/[\s,;:.]+/) : [];
  });
  for (const [catalog, own, sibling] of [
    ['psychology-ba-2026', 'BA-PSY-AS', 'BS-PSY-AS'],
    ['psychology-bs-2026', 'BS-PSY-AS', 'BA-PSY-AS'],
    ['criminology-ba-2026', 'BA-CRIM-AS', null],
    ['chemistry-ba-2026', 'BA-CHEM-AS', 'BS-CHEM-AS'],
    ['chemistry-bs-2026', 'BS-CHEM-AS', 'BA-CHEM-AS'],
    ['biochemistry-bs-2026', 'BS-BIOC-AS', null],
    ['political-science-ba-2026', 'BA-POLS-AS', null],
    ['electrical-engineering-bs-2026', 'BSEE-EE-EN', null],
    ['mechanical-engineering-bs-2026', 'BSME-ME-EN', null],
    ['exercise-science-bs-2026', 'BS-ES-EH', null],
    ['film-digital-arts-ba-2026', 'BA-FDMA-FA', 'BFA-FDMA-FA'],
    ['film-digital-arts-bfa-2026', 'BFA-FDMA-FA', 'BA-FDMA-FA'],
    ['architecture-ba-2026', 'BAA-ARCT-AP', null]
  ]) {
    await choose('degree_explorer-dx_catalog_id', catalog);
    const codes = await programCodes();
    check(codes.includes(own) && (!sibling || !codes.includes(sibling)),
      `${catalog}: states its own Banner program codes${sibling ? ', not ' + sibling : ''}`);
    check(await page.$$eval('.cedar-roadmap-semester', els => els.every(el => Number(el.dataset.plannedCredits) <= 16)) &&
      await alignedHeaders() && await soundRows(), `${catalog}: aligned board within 16 credits`);
    await choose('degree_explorer-dx_math_start', 'intermediate');
    check(await page.$$eval('.cedar-roadmap-semester', els => els.every(el => Number(el.dataset.plannedCredits) <= 16)) &&
      await alignedHeaders() && await soundRows(), `${catalog}: additional math preparation keeps the board aligned within 16 credits`);
    await choose('degree_explorer-dx_math_start', 'algebra');
  }
  await connect(page, { search: 'tab=degree-explorer&catalog_id=business-bba-2026&math_start=algebra&english_start=stretch' });
  await waitForSelector(page, '[data-roadmap][data-ready][data-catalog="business-bba-2026"][data-math-start="algebra"][data-english-start="stretch"]');
  // The compiled board does not yet hold its writing choice behind Composition
  // II (ISSUES I67); the link's own restoration is what is checked here.
  check(await semester('math1350') === 1 && await semester('engl2') === 3 &&
    await page.$eval('[data-roadmap]', el => el.dataset.englishStart === 'stretch' && el.dataset.mathStart === 'algebra'),
    'a new-program deep link restores its statistics route and the English stretch sequence');
  await checkAdminSharedRules();
};
try {
  if (process.argv.includes('--shared-requirements-only')) {
    await connect(page, { tab: 'degree-explorer' });
    await waitForSelector(page, '[data-roadmap][data-ready]');
    // These scenarios were written from the calculus start; the page opens on College Algebra.
    await choose('degree_explorer-dx_math_start', 'calculus');
    // The page opens on the first degree alphabetically; the overlap is CS's.
    await choose('degree_explorer-dx_catalog_id', 'cs-bs-2026');
    // The overlap labels are on the Detailed cards, which the full run has
    // switched to by the time it reaches them.
    await page.click('[data-roadmap-view="detailed"]');
    await waitFor(page, () => document.querySelector('[data-roadmap]').dataset.view === 'detailed');
    await checkCommunicationOverlap();
    await (await page.$('[data-node="communication_elective_1"]')).screenshot({ path: '/tmp/cedar-degree-communication-overlap.png' });
    await choose('degree_explorer-dx_catalog_id', 'anthropology-ba-2026');
    await checkAnthropologyCoverage();
    check(await alignedHeaders() && await soundRows(), 'shared requirement cards preserve aligned headers and course rows');
    check(await page.$$eval('.cedar-roadmap-semester', terms => terms.every(term =>
      Number(term.dataset.plannedCredits) <= 16 &&
      [...term.querySelectorAll('.cedar-roadmap-course')].reduce((sum, card) =>
        sum + Number(card.dataset.credits), 0) === Number(term.dataset.plannedCredits))),
      'shared requirement cards preserve every semester credit and the 16-credit cap');
    await (await page.$('[data-node="antharch"]')).screenshot({ path: '/tmp/cedar-degree-anthropology-overlap-card.png' });
    await checkAdminSharedRules();
    check(jsErrors.length === 0, 'no uncaught JavaScript errors');
  } else {
  if (!process.argv.includes('--course-paths-only')) await checkDegreeExplorer();
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
  const overlayClosed = () => waitFor(page, () => {
    const overlay = document.getElementById('pathways-course_paths-loading-overlay');
    return overlay && getComputedStyle(overlay).display === 'none';
  }, { timeout: 10000 });
  if (!await overlayClosed()) throw new Error('Course paths finished rendering but its loading dialog never closed');
  check(true, 'Course paths closes its nested loading dialog and reveals the completed plot');
  const scope = await page.$eval('#pathways-course_paths-path_scope', el => el.innerText);
  check(scope.includes('observed students') && scope.includes('Through') && scope.includes('suppressed'),
    'Course paths uses the shared population and reports the data edge and suppression');
  const table = await readReactable(page, 'pathways-course_paths-path_courses');
  check(!table.error && table.rows.length > 0 && colIndex(table.headers, 'Campus') >= 0,
    'moved course detail retains observed data and delivery campus');
  check(['Title', 'Level', 'Gen Ed', 'Degree plan'].every((h) => colIndex(table.headers, h) >= 0),
    'each listed course is described: title, level, Gen Ed area and degree plan');
  const listed = table.rows.length;
  await setInput(page, 'pathways-course_paths-detail_gen_ed', 'gen_ed');
  await waitForIdle(page, { timeout: 30000 });
  const genEdOnly = await readReactable(page, 'pathways-course_paths-path_courses');
  const genEdCol = colIndex(genEdOnly.headers, 'Gen Ed');
  check(!genEdOnly.error && genEdOnly.rows.every((row) => row[genEdCol] && row[genEdCol] !== '\u2014'),
    `"Gen Ed only" lists only Gen Ed courses (${genEdOnly.rows?.length} of ${listed} rows shown)`);
  await setInput(page, 'pathways-course_paths-detail_gen_ed', 'all');
  await waitForIdle(page, { timeout: 30000 });
  const selectedCampuses = await page.$eval('#pathways-course_paths-campus', el => el.selectize.getValue());
  await setInput(page, 'pathways-course_paths-campus', []);
  await runAndWait(page, 'pathways-course_paths-button');
  check(await overlayClosed() && await page.$$eval('.shiny-notification', els =>
    els.some(el => el.innerText.includes('Select at least one delivery campus'))),
    'an invalid course-paths request closes its loading dialog and shows the reason');
  await setInput(page, 'pathways-course_paths-campus', selectedCampuses);
  await runAndWait(page, 'pathways-course_paths-button', { timeout: 180000 });
  check(await overlayClosed(), 'a repeated Course paths run also dismisses its loading dialog');
  await page.$eval('#pathways-course_paths-path_scope', el => el.scrollIntoView({ block: 'start' }));
  await page.screenshot({ path: '/tmp/cedar-course-paths.png', fullPage: false });
  check(jsErrors.length === 0, 'no uncaught JavaScript errors');
  }
} catch (error) {
  failures.push(error.message);
  console.error(error);
  await page.screenshot({ path: '/tmp/cedar-degree-explorer-failure.png', fullPage: false });
} finally {
  await browser.close();
}
console.log(`${passed} passed, ${failures.length} failed`);
if (failures.length) process.exitCode = 1;
