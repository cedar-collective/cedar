// Saved-artifact regression checks for Registration > Projections.
//
//   node tests/e2e/enrollment-projections.test.mjs
import {
  launch, connect, clickNavTab, setInput, waitFor, waitForIdle,
  waitForSelector, readReactable, colIndex, requireIds, openSubTab,
} from './lib.mjs';

const results = [];
let failed = 0;
function check(name, ok, detail = '') {
  results.push({ name, ok: !!ok });
  if (!ok) failed++;
  console.log(`${ok ? 'PASS' : 'FAIL'}  ${name}${detail ? `  - ${detail}` : ''}`);
}

// A row click opens the course's evidence in a modal over the table.
function evidenceShown() {
  const modal = document.querySelector('.modal.show');
  const title = modal ? modal.querySelector('.modal-title') : null;
  return !!(title && /projection evidence/i.test(title.innerText) &&
    document.getElementById('enrollment_projections-detail'));
}

async function closeEvidence(page) {
  await page.evaluate(() => {
    const close = document.querySelector('.modal.show .modal-footer button');
    if (close) close.click();
  });
  await waitFor(page, () => !document.querySelector('.modal.show') &&
    !document.querySelector('.modal-backdrop'), { timeout: 10000 });
}

(async () => {
  const { browser, page, jsErrors } = await launch({ width: 1440, height: 1000 });
  await connect(page, { tab: 'projections', expect: 'Projections', settle: 4500 });

  const ids = [
    'enrollment_projections-target_term',
    'enrollment_projections-group',
    'enrollment_projections-department',
    'enrollment_projections-course',
    'enrollment_projections-projection_table',
    'enrollment_projections-scenario_population',
    'enrollment_projections-scenario_growth',
    'enrollment_projections-scenario_horizon',
    'enrollment_projections-scenario_measure',
  ];
  await requireIds(page, ids);
  await waitForSelector(
    page,
    '#enrollment_projections-projection_table .rt-tbody .rt-tr',
    { timeout: 120000 }
  );
  await waitForSelector(
    page,
    'details.enrollment-projection-method-guide',
    { timeout: 60000 }
  );

  check(
    'standalone projections route remains canonical',
    await page.evaluate(() => location.search === '?tab=projections')
  );

  const pageChrome = await page.evaluate(() => {
    const filters = document.querySelector('.enrollment-projection-filters');
    const guide = document.querySelector('details.enrollment-projection-guide');
    return {
      title: filters ? filters.querySelector('h1')?.innerText.trim() : '',
      subtitle: filters ? filters.querySelector('.filter-subtitle')?.innerText.trim() : '',
      guideTitle: guide ? guide.querySelector('summary')?.innerText.trim() : '',
      guideOpen: guide ? guide.open : null,
    };
  });
  check('title is presented in the green filter bar',
    pageChrome.title === 'Enrollment Projections', pageChrome.title || '(missing)');
  check('filter bar carries a brief page description',
    pageChrome.subtitle.startsWith('Sections to plan for each course'), pageChrome.subtitle);
  check('the column guide is a collapsed, purpose-labelled info panel',
    pageChrome.guideTitle.includes('Reading the table: what each column means') &&
      pageChrome.guideOpen === false, pageChrome.guideTitle || '(missing)');

  const methodGuide = await page.evaluate(() => {
    const guide = document.querySelector('details.enrollment-projection-method-guide');
    const summary = guide ? guide.querySelector('summary')?.innerText.trim() : '';
    const initiallyOpen = guide ? guide.open : null;
    if (guide) guide.open = true;
    return {
      summary,
      initiallyOpen,
      text: guide ? guide.innerText : '',
    };
  });
  check('projection-method guide sits below the table as a collapsed accordion',
    methodGuide.initiallyOpen === false && methodGuide.summary.includes('Projection methods'),
    methodGuide.summary || '(missing)');
  check('method guide explains the three managed candidate families',
    ['2 candidates', 'Prior same-season is the default']
      .every((phrase) => methodGuide.text.includes(phrase)),
    methodGuide.text.slice(0, 700));
  check('method guide describes both registered methods',
    ['Prior same-season', 'Prior same-season + floor + Fall deltas']
      .every((label) => methodGuide.text.includes(label)));

  const initialContext = await page.evaluate(() => {
    const group = document.getElementById('enrollment_projections-group');
    const scope = document.getElementById('enrollment_projections-scope');
    const target = document.getElementById('enrollment_projections-target_term');
    const modelInfo = scope && scope.querySelector('.enrollment-projection-model-info');
    return {
      group: group ? group.value : null,
      scope: scope ? scope.innerText.trim() : '',
      modelNote: modelInfo ? modelInfo.getAttribute('title') : '',
      target: target ? target.value : null,
      // Read the choices from selectize, not from select.options: selectize
      // keeps only the selected item in the underlying <select>, so .options
      // reports one entry no matter how many seasons are published.
      targetChoices: target && target.selectize
        ? Object.values(target.selectize.options)
            .map((option) => ({ value: String(option.value), label: String(option.label) }))
        : [],
    };
  });
  check('Always monitored is the default course group',
    initialContext.group === 'always_monitored', initialContext.group || '(missing)');
  // One bundle publishes per season and neither supersedes the other, so the
  // institutional app must offer both and the scope stripe must name the one
  // actually loaded. A stripe that disagrees with the selector means the page is
  // showing a different term than it claims.
  const choiceLabels = initialContext.targetChoices.map((choice) => choice.label);
  check('target term selector offers both published seasons',
    choiceLabels.some((label) => /^Spring \d{4}$/.test(label)) &&
      choiceLabels.some((label) => /^Fall \d{4}$/.test(label)) &&
      choiceLabels.every((label) => /^(Spring|Fall) \d{4}$/.test(label)),
    choiceLabels.join(', ') || '(empty)');
  const selectedLabel = initialContext.targetChoices.find(
    (choice) => choice.value === initialContext.target)?.label ?? '';
  check('scope stripe names the selected target term',
    selectedLabel !== '' && initialContext.scope.includes(selectedLabel),
    `${selectedLabel} | ${initialContext.scope.split('\n')[0]}`);

  // Switching seasons must load the OTHER bundle, not refilter this one. The
  // term is read from the selector rather than hardcoded, so this keeps working
  // as the published targets roll forward.
  const otherSeason = initialContext.targetChoices.find(
    (choice) => choice.value !== initialContext.target);
  if (!otherSeason) {
    check('a second published season is available to switch to', false, '(only one)');
  } else {
    // The stripe names the season and the table has rows under it.
    const seasonShown = (label) => {
      const scope = document.getElementById('enrollment_projections-scope');
      return Boolean(scope && scope.innerText.includes(label) && document.querySelector(
        '#enrollment_projections-projection_table .rt-tbody .rt-tr'));
    };
    await setInput(page, 'enrollment_projections-target_term', otherSeason.value);
    await waitForIdle(page);
    // A freshly started app can still be reading the other bundle when the page
    // first goes idle; wait for its label rather than read once.
    await waitFor(page, seasonShown, { timeout: 60000, args: [otherSeason.label] });
    const switched = await page.evaluate(() => {
      const scope = document.getElementById('enrollment_projections-scope');
      const rows = document.querySelectorAll(
        '#enrollment_projections-projection_table .rt-tbody .rt-tr');
      return { scope: scope ? scope.innerText.trim() : '', rows: rows.length };
    });
    check(`switching to ${otherSeason.label} loads that season's bundle`,
      switched.scope.includes(otherSeason.label) && switched.rows > 0,
      `${switched.scope.split('\n')[0]} | ${switched.rows} rows`);

    // Open a row's evidence on THIS season too. The two bundles do not carry the
    // same evidence -- a two-step-horizon season has no structural candidates at
    // all -- so a detail panel that assumes they exist fails on one season and
    // passes on the other.
    const otherDetail = await page.evaluate(() => {
      const cell = document.querySelector(
        '#enrollment_projections-projection_table .rt-tbody .rt-tr .rt-td');
      if (!cell) return false;
      cell.click();
      return true;
    });
    await waitForIdle(page, { timeout: 60000 });
    const otherOpened = otherDetail && await waitFor(page, evidenceShown, { timeout: 30000 });
    check(`a row opens its evidence on ${otherSeason.label} as well`,
      otherOpened, otherDetail ? '' : '(no row to click)');
    if (otherOpened) await closeEvidence(page);
    // Restore the opening season; every later check reads that bundle.
    await setInput(page, 'enrollment_projections-target_term', initialContext.target);
    await waitForIdle(page);
    await waitFor(page, seasonShown, { timeout: 60000, args: [selectedLabel] });
  }
  // The comparable-history floor is fixed by policy (Spring 2022), but the
  // through-term moves with every data refresh as the settled enrollment edge
  // advances. Pin the floor and the shape, not the end term, or this fails
  // every time the data is updated and reads like a broken feature.
  check('scope names the historical data window',
    /Data window: Spring 2022 through (Spring|Summer|Fall) \d{4}/.test(initialContext.scope),
    initialContext.scope);
  check('scope names the pooled campuses as ABQ + EA',
    initialContext.scope.includes('ABQ + EA') &&
      !initialContext.scope.toLowerCase().includes('online market'), initialContext.scope);
  check('model label exposes saved source provenance',
    initialContext.modelNote.includes('Exact normalized model source is embedded'),
    initialContext.modelNote);

  let table = await readReactable(page, 'enrollment_projections-projection_table');
  const requiredHeaders = [
    'Course', 'Sections', 'Plan adds', 'Seats (day 1)', 'Registrations',
    'Flags', 'Reliability', 'Seat consistency',
  ];
  // The Day-1 fill header carries its term, so it is matched by prefix.
  const hasFillHeader = table.headers.some((h) => /^day-1 fill\b/i.test(h));
  check(
    'projection table leads with the decision and keeps reliability beside seat consistency',
    hasFillHeader &&
      requiredHeaders.every((header) => colIndex(table.headers, header) >= 0) &&
      colIndex(table.headers, 'Sections') < colIndex(table.headers, 'Reliability') &&
      colIndex(table.headers, 'Seat consistency') === colIndex(table.headers, 'Reliability') + 1,
    table.headers.join(' | ')
  );
  // Stability and depth are in the course detail, not the table.
  check('stability and depth are not table columns',
    !['Stability', 'Depth'].some((header) => colIndex(table.headers, header) >= 0),
    table.headers.join(' | '));
  // Ratings read as the number behind them, coloured by the rating; fill is a
  // column, so no flag repeats it.
  const ratingCells = await page.evaluate(() => {
    const root = document.getElementById('enrollment_projections-projection_table');
    const headers = [...root.querySelectorAll('.rt-thead .rt-th')].map((c) => c.innerText.trim());
    const at = (name) => headers.findIndex((h) => h.toLowerCase().startsWith(name));
    const rows = [...root.querySelectorAll('.rt-tbody .rt-tr')];
    const cell = (row, i) => row.querySelectorAll('.rt-td')[i];
    const fillHeader = root.querySelectorAll('.rt-thead .rt-th')[at('day-1 fill')];
    return {
      reliability: rows.map((r) => cell(r, at('reliability')).innerText.trim()),
      seats: rows.map((r) => cell(r, at('seat consistency')).innerText.trim()),
      flags: rows.map((r) => cell(r, at('flags')).innerText.trim()),
      fillHeader: fillHeader ? fillHeader.innerText.replace(/\s+/g, ' ').trim() : '',
    };
  });
  check('reliability cells show how far off, or Unrated',
    ratingCells.reliability.length > 0 &&
      ratingCells.reliability.every((v) => /^\d+\.\d% off$/.test(v) || v === 'Unrated'),
    ratingCells.reliability.join(', '));
  check('seat consistency cells show how many terms the seats moved, or Unrated',
    ratingCells.seats.every((v) => /^moved \d+ of \d+$/.test(v) || v === 'Unrated'),
    ratingCells.seats.join(', '));
  check('the Day-1 fill header names the term the plans start from',
    /^Day-1 fill \((Spring|Fall) \d{4}\)$/i.test(ratingCells.fillHeader),
    ratingCells.fillHeader);
  check('no flag repeats a column',
    !ratingCells.flags.some((f) => /last term|waiting|as seats moved|off by 20%/i.test(f)),
    ratingCells.flags.join(' / '));
  const findings = await page.evaluate(() => {
    const box = document.getElementById('enrollment_projections-projection_findings');
    const scope = document.getElementById('enrollment_projections-scope');
    return {
      text: box ? box.innerText : '',
      link: Boolean(box && box.querySelector('#enrollment_projections-open_draft')),
      scope: scope ? scope.innerText : '',
    };
  });
  check('the page says how many of the worst misses followed the seats',
    /had past forecasts more than \d+% off|has had past forecasts more than \d+% off|has not had past forecasts/.test(findings.text),
    findings.text);
  check('the scope says when the projection was built and which draft it was set beside',
    /built [A-Z][a-z]+ \d{1,2}, \d{4}/.test(findings.scope) &&
      /draft schedule (as of [A-Z][a-z]+ \d{1,2}, \d{4}|not yet in the data)/.test(findings.scope),
    findings.scope);
  if (findings.link) {
    check('the draft verdict leads the Projections tab',
      findings.text.startsWith('The draft schedule'), findings.text);
    await page.evaluate(() => document.getElementById('enrollment_projections-open_draft').click());
    const draftShown = await waitFor(page, () => {
      const pane = document.getElementById('enrollment_projections-draft_table');
      return Boolean(pane && pane.checkVisibility());
    }, { timeout: 30000 });
    check('the draft link opens the draft comparison', draftShown);
    await openSubTab(page, 'Projections');
    await waitForIdle(page);
  }
  // The method and its evidence live in the course modal; the department sits
  // under the course and the range under the registrations, so the table
  // fits a laptop window.
  check(
    'the summary keeps method detail and secondary values out of their own columns',
    !['Basis', 'Why', 'Dept', 'vs last', 'Likely range', 'Trend',
      'Saturation floor', 'Regime check', 'Recommendation']
      .some((header) => colIndex(table.headers, header) >= 0),
    table.headers.join(' | ')
  );
  // Four recent same-season terms in one cell: first-day enrollment over
  // sections, under the four term labels in the header.
  const historyCells = await page.evaluate(() => {
    const root = document.getElementById('enrollment_projections-projection_table');
    if (!root) return null;
    const header = [...root.querySelectorAll('.rt-thead .rt-th')]
      .find((cell) => /first day \/ sections/i.test(cell.innerText));
    const grids = [...root.querySelectorAll('.rt-tbody .projection-history-grid')];
    return {
      header: header ? header.innerText.replace(/\s+/g, ' ').trim() : null,
      headerTerms: header ? header.querySelectorAll('.projection-history-grid > span').length : 0,
      rows: root.querySelectorAll('.rt-tbody .rt-tr').length,
      grids: grids.length,
      slots: grids.every((grid) => grid.children.length === 4),
      sections: grids.some((grid) => /\d+ sec/.test(grid.innerText)),
      markupAsText: [...root.querySelectorAll('.rt-tbody .rt-td')]
        .some((cell) => /<(svg|span|div)/.test(cell.innerText)),
    };
  });
  check('recent first days and sections sit in one compact column',
    historyCells && historyCells.headerTerms === 4 &&
      historyCells.grids === historyCells.rows && historyCells.slots &&
      historyCells.sections && !historyCells.markupAsText,
    JSON.stringify(historyCells));
  // The table must fit a laptop window: no horizontal scroll at 1440 or 1366.
  const tableOverflow = async () => page.evaluate(() => {
    const table = document.querySelector('#enrollment_projections-projection_table .rt-table');
    return table ? table.scrollWidth - table.clientWidth : null;
  });
  const overflowWide = await tableOverflow();
  await page.setViewport({ width: 1366, height: 1000 });
  await waitForIdle(page);
  const overflowLaptop = await tableOverflow();
  await page.setViewport({ width: 1440, height: 1000 });
  await waitForIdle(page);
  check('the projection table fits a laptop window without horizontal scrolling',
    overflowWide !== null && overflowWide <= 1 && overflowLaptop <= 1,
    `overflow 1440: ${overflowWide}px, 1366: ${overflowLaptop}px`);
  check('saved projection rows render', table.rows.length > 0, `${table.rows.length} visible`);
  const naturalTableFlow = await page.evaluate(() => {
    const root = document.getElementById('enrollment_projections-projection_table');
    const body = root && root.querySelector('.rt-tbody');
    const guide = document.querySelector('details.enrollment-projection-method-guide');
    if (!root || !body || !guide) return null;
    const rootRect = root.getBoundingClientRect();
    const bodyRect = body.getBoundingClientRect();
    const guideRect = guide.getBoundingClientRect();
    return {
      rootHeight: rootRect.height,
      bodyHeight: bodyRect.height,
      guideAfterTable: guideRect.top >= rootRect.bottom,
    };
  });
  check('projection rows contribute their full height to normal page flow',
    naturalTableFlow && naturalTableFlow.rootHeight >= naturalTableFlow.bodyHeight &&
      naturalTableFlow.bodyHeight > 0 && naturalTableFlow.guideAfterTable,
    naturalTableFlow ? JSON.stringify(naturalTableFlow) : '(missing table layout)');

  // Clicking a row in the table AS IT OPENS is the ordinary way into the
  // evidence, and it was not covered: the existing click below happens only
  // after a course filter has narrowed the table to one row, so a click that
  // works on a single row and fails on a full table would pass unnoticed.
  const detailFromRow = await page.evaluate(() => {
    const cell = document.querySelector(
      '#enrollment_projections-projection_table .rt-tbody .rt-tr .rt-td');
    if (!cell) return null;
    const course = cell.innerText.trim();
    cell.click();
    return course;
  });
  await waitForIdle(page, { timeout: 60000 });
  const detailOpened = await waitFor(page, evidenceShown, { timeout: 30000 });
  check('clicking a row in the unfiltered table opens its evidence',
    detailOpened, detailFromRow || '(no row to click)');
  // Rendering the evidence is not the same as showing it. Evidence that opened
  // far below the fold, with nothing moving the viewport, looked like a click
  // that did nothing (reported twice); the modal must be on screen.
  const detailPlacement = await page.evaluate(() => {
    const detail = document.getElementById('enrollment_projections-detail');
    if (!detail) return null;
    const box = detail.getBoundingClientRect();
    return {
      top: Math.round(box.top),
      viewport: window.innerHeight,
      scrollY: Math.round(window.scrollY),
      offscreen: box.top > window.innerHeight,
    };
  });
  check('the evidence panel is reachable without hunting for it',
    detailPlacement && !detailPlacement.offscreen,
    detailPlacement ? JSON.stringify(detailPlacement) : '(no detail element)');
  if (detailOpened) await closeEvidence(page);

  await setInput(page, 'enrollment_projections-group', 'all_saved');
  await waitFor(page, () => {
    const root = document.getElementById('enrollment_projections-projection_table');
    return root && root.querySelectorAll('.rt-tbody .rt-tr').length > 25;
  }, { timeout: 60000 });
  table = await readReactable(page, 'enrollment_projections-projection_table');
  check('larger groups render all rows in the page flow', table.rows.length > 25,
    `${table.rows.length} visible`);
  check('projection table has no internal pagination controls',
    await page.evaluate(() => {
      const root = document.getElementById('enrollment_projections-projection_table');
      return root && !root.querySelector('.rt-pagination');
    }));
  const allSavedRows = table.rows.length;
  await setInput(page, 'enrollment_projections-group', 'always_monitored');
  await waitForIdle(page, { timeout: 60000 });
  await waitFor(page, (n) => {
    const root = document.getElementById('enrollment_projections-projection_table');
    const rows = root ? root.querySelectorAll('.rt-tbody .rt-tr').length : 0;
    return rows > 0 && rows < n;
  }, { timeout: 60000, args: [allSavedRows] });
  // No rating filters: the table opens on what the plan adds, largest
  // first, and a rating column sorts weakest first rather than alphabetically.
  const openingSort = await page.evaluate(() => {
    const root = document.getElementById('enrollment_projections-projection_table');
    const header = root && [...root.querySelectorAll('.rt-thead .rt-th')]
      .find((cell) => /^plan adds$/i.test(cell.innerText.trim()));
    return header ? header.getAttribute('aria-sort') : null;
  });
  check('the table opens sorted by what the plan adds, largest first',
    openingSort === 'descending', String(openingSort));
  await page.evaluate(() => {
    const root = document.getElementById('enrollment_projections-projection_table');
    const header = [...root.querySelectorAll('.rt-thead .rt-th')]
      .find((cell) => /^reliability$/i.test(cell.innerText.trim()));
    if (!header) throw new Error('no Reliability header');
    header.click();
  });
  const reliabilitySorted = await waitFor(page, () => {
    const root = document.getElementById('enrollment_projections-projection_table');
    const header = [...root.querySelectorAll('.rt-thead .rt-th')]
      .find((cell) => /^reliability$/i.test(cell.innerText.trim()));
    return header && header.getAttribute('aria-sort') === 'descending';
  }, { timeout: 10000 });
  // A cell shows the number; its rating is the badge's tone.
  const reliabilityOrder = reliabilitySorted && await page.evaluate(() => {
    const root = document.getElementById('enrollment_projections-projection_table');
    const index = [...root.querySelectorAll('.rt-thead .rt-th')]
      .findIndex((cell) => /^reliability$/i.test(cell.innerText.trim()));
    return [...root.querySelectorAll('.rt-tbody .rt-tr')].map((row) => {
      const badge = row.querySelectorAll('.rt-td')[index].querySelector('.projection-axis');
      const tone = badge ? [...badge.classList].find((c) => c.startsWith('projection-axis--')) : null;
      return tone ? tone.replace('projection-axis--', '') : 'missing';
    });
  });
  const reliabilityRank = { poor: 3, mid: 2, good: 1, none: 0 };
  check(
    'Reliability sorts weakest first, unrated last',
    Array.isArray(reliabilityOrder) && reliabilityOrder.length > 1 &&
      reliabilityOrder.every((value, i) => i === 0 ||
        reliabilityRank[reliabilityOrder[i - 1]] >= reliabilityRank[value]),
    Array.isArray(reliabilityOrder) ? reliabilityOrder.join(', ') : String(reliabilityOrder)
  );

  await setInput(page, 'enrollment_projections-course', ['CHEM 1215']);
  await waitForIdle(page, { timeout: 60000 });
  const oneCourse = await waitFor(page, () => {
    const root = document.getElementById('enrollment_projections-projection_table');
    const rows = root ? root.querySelectorAll('.rt-tbody .rt-tr') : [];
    return rows.length === 1 && rows[0].innerText.includes('CHEM 1215');
  }, { timeout: 60000 });
  check('course filter narrows the saved artifact', oneCourse);

  await page.evaluate(() => {
    const cell = document.querySelector(
      '#enrollment_projections-projection_table .rt-tbody .rt-tr .rt-td'
    );
    if (!cell) throw new Error('no projection row to select');
    cell.click();
  });
  await waitForIdle(page, { timeout: 60000 });
  await waitForSelector(
    page,
    '#enrollment_projections-history_table .rt-tbody .rt-tr',
    { timeout: 60000 }
  );
  // The method plot, movement diagnostic, and candidate table sit in the
  // collapsed Analyst detail accordion, and the method/course evidence trail
  // sits in its own collapsed panel beside it; Shiny renders nothing inside a
  // closed <details> -- so open both before waiting on or reading any of it.
  const movementPanel = await page.evaluate(() => {
    const panel = document.querySelector('details.enrollment-projection-movement');
    const evidence = document.querySelector('details.enrollment-projection-evidence');
    if (panel) panel.open = true;
    if (evidence) evidence.open = true;
    return {
      found: !!panel,
      title: panel ? panel.querySelector('summary')?.innerText.trim() : '',
      evidenceFound: !!evidence,
    };
  });
  check('course detail includes the analyst detail accordion',
    movementPanel.found && movementPanel.title.includes('movement diagnostic'),
    movementPanel.title || '(missing)');
  check('course detail includes the method/course evidence accordion',
    movementPanel.evidenceFound);
  await waitForSelector(
    page,
    '#enrollment_projections-candidate_table .rt-tbody .rt-tr',
    { timeout: 60000 }
  );
  await page.evaluate(() => {
    document.getElementById('enrollment_projections-method_history_plot')
      ?.scrollIntoView({ block: 'center' });
  });
  await waitForSelector(
    page,
    '#enrollment_projections-method_history_plot .main-svg',
    { timeout: 60000, nonEmpty: false }
  );
  await waitForSelector(
    page,
    '#enrollment_projections-movement_table .rt-tbody .rt-tr',
    { timeout: 60000 }
  );
  const movement = await readReactable(page, 'enrollment_projections-movement_table');
  check('movement diagnostic exposes capacity, upstream enrollment, and DFW',
    ['Δ enrl', 'Δ cap', 'University students', 'Incoming freshmen',
      'Prior-term DFW (n / rate)', 'Next-term repeaters (n / share)']
      .every((header) => colIndex(movement.headers, header) >= 0),
    movement.headers.join(' | '));
  const detailSummaryText = await page.evaluate(() => {
    const detail = document.getElementById('enrollment_projections-detail');
    return detail ? detail.innerText : '';
  });
  check('course detail retains planning, bias, and population-fit evidence',
    ['Status', 'Sections', 'Planned registrations', 'How this plan was built',
      'Forecast registrations', 'Selected method', 'Saturation floor',
      'Fall deltas', 'Regime check']
      // innerText applies CSS text-transform: the headline labels read in capitals.
      .every((label) => detailSummaryText.toLowerCase().includes(label.toLowerCase())),
    detailSummaryText.slice(0, 500));
  await waitForSelector(page, '.modal.show .modal-footer button', { timeout: 60000 });

  const history = await readReactable(page, 'enrollment_projections-history_table');
  const expectedHistoryOrder = [
    'Term', 'Forecast method', 'Forecast then', 'Error', 'How scored',
    'Ever registered', 'First day', 'Census', 'Final / last day',
    'Sections', 'Capacity', 'First-day fill', 'Potential explanation',
  ];
  check(
    'history places aftcast and error before actual enrollment',
    expectedHistoryOrder.every((name, i) =>
      history.headers[i] && history.headers[i].toLowerCase() === name.toLowerCase()),
    history.headers.join(' | ')
  );
  // Capacity-bounded is an overprojection on a term whose first day filled
  // 98% of the seats or more. Check that property row by row rather than
  // expecting one particular course to have such a term: CHEM 1215 filled
  // 98.8% in Spring 2026, but its aftcasts there did not overshoot.
  const historyOffset = history.rows.length
    ? history.rows[0].length - history.headers.length : 0;
  const historyCell = (row, name) =>
    row[colIndex(history.headers, name) + historyOffset].trim();
  const percentValue = (text) => {
    const value = Number.parseFloat(text.replace(/[^0-9.+-]/g, ''));
    return Number.isFinite(value) ? value : null;
  };
  const boundedMismatches = history.rows.filter((row) => {
    const bounded = historyCell(row, 'How scored') === 'Capacity-bounded';
    const error = percentValue(historyCell(row, 'Error'));
    const fill = percentValue(historyCell(row, 'First-day fill'));
    const over = error !== null && error > 0;
    if (bounded) return !over || fill === null || fill < 98;
    // 98.0% can be a rounded 97.96%; only an unambiguous fill must be labeled.
    return over && fill !== null && fill >= 98.1 &&
      historyCell(row, 'How scored') !== 'Not forecast';
  });
  check(
    'capacity-bounded labels exactly the overprojected terms that filled 98% on day one',
    history.rows.length > 0 && boundedMismatches.length === 0,
    boundedMismatches.map((row) => row.join(' | ')).join(' / ') || `${history.rows.length} rows`
  );

  const detailEvidence = await page.evaluate(() => {
    const detail = document.getElementById('enrollment_projections-detail');
    const plot = document.getElementById('enrollment_projections-method_history_plot');
    const traces = plot ? [...plot.querySelectorAll('.legendtext')]
      .map((node) => node.textContent.trim()) : [];
    return { text: detail ? detail.innerText : '', traces };
  });
  check('detail says aftcasts are scored against ever-registered demand',
    detailEvidence.text.includes('against ever-registered demand') &&
      detailEvidence.text.includes('judged on the first day of classes'));
  check('detail explains all three axes separately for CHEM 1215',
    detailEvidence.text.includes('Stability:') &&
      detailEvidence.text.includes('Depth:') &&
      detailEvidence.text.includes('Reliability:'));
  check('historical plot includes all enrollment lifecycle measures',
    ['Ever registered (model target)', 'First day (seats judged here)', 'Census',
      'Final / last day']
      .every((name) => detailEvidence.traces.includes(name)),
    detailEvidence.traces.join(' | '));
  check('historical plot highlights the selected method',
    detailEvidence.traces.some((name) => name.endsWith('(selected)')),
    detailEvidence.traces.join(' | '));

  const candidates = await readReactable(page, 'enrollment_projections-candidate_table');
  const candidateText = candidates.rows.flat().join(' ');
  // 0.20.0 retired every candidate but the spine and its adjusted form.
  check('both candidates are inspectable',
    candidates.rows.length === 2 &&
      candidateText.includes('Prior same-season + floor + Fall deltas'),
    `${candidates.rows.length} rows: ${candidateText.slice(0, 200)}`);

  // Closing the modal returns the reader to the table exactly where they were.
  const scrollBefore = await page.evaluate(() => Math.round(window.scrollY));
  await closeEvidence(page);
  const returnedToTable = await page.evaluate((before) => {
    const firstRow = document.querySelector(
      '#enrollment_projections-projection_table .rt-tbody .rt-tr');
    return !document.querySelector('.modal.show') &&
      !document.querySelector('.modal-backdrop') &&
      !!firstRow && Math.abs(Math.round(window.scrollY) - before) <= 1;
  }, scrollBefore);
  check('closing the evidence returns to the same place in the table', returnedToTable);

  // ---- Scenario sub-tab --------------------------------------------------
  await openSubTab(page, 'Scenario');
  const scenarioRows = async () => readReactable(page, 'enrollment_projections-scenario_table');

  await setInput(page, 'enrollment_projections-scenario_growth', 0);
  await waitForIdle(page);
  const flat = await scenarioRows();
  const yearColumns = flat.headers.filter((h) => /^(Spring|Fall) \d{4}$/.test(h));
  check('scenario table lays out one column per horizon year',
    yearColumns.length >= 2, flat.headers.join(' | '));
  // Zero growth must reproduce the published projection in EVERY year. If a row
  // moves at 0%, growth is being applied to students the population does not
  // contain -- the failure that would make a 10% assumption look like a 10%
  // enrollment increase.
  const flatRow = flat.rows[0] || [];
  const flatValues = yearColumns.map((h) => flatRow[colIndex(flat.headers, h)]);
  check('zero growth is flat across the whole horizon',
    flatValues.length > 0 && new Set(flatValues).size === 1,
    flatValues.join(' -> '));

  await setInput(page, 'enrollment_projections-scenario_growth', 10);
  await waitForIdle(page);
  const grown = await scenarioRows();
  const grownRow = grown.rows[0] || [];
  const grownValues = yearColumns.map(
    (h) => Number(String(grownRow[colIndex(grown.headers, h)]).replace(/,/g, '')));
  check('growth raises later years but never year one',
    grownValues.length > 1 &&
      grownValues[0] === Number(String(flatValues[0]).replace(/,/g, '')) &&
      grownValues[grownValues.length - 1] > grownValues[0],
    grownValues.join(' -> '));

  await setInput(page, 'enrollment_projections-scenario_measure', 'sections');
  await waitForIdle(page);
  const sections = await scenarioRows();
  const sectionValues = yearColumns.map(
    (h) => Number(String(sections.rows[0][colIndex(sections.headers, h)]).replace(/,/g, '')));
  check('sections measure reports whole sections that never decrease',
    sectionValues.every((v) => Number.isInteger(v)) &&
      sectionValues.every((v, i) => i === 0 || v >= sectionValues[i - 1]),
    sectionValues.join(' -> '));

  // Returning from the Scenario sub-tab and clicking a row is an ordinary path
  // through this page, and it exercises the projection table after its panel has
  // been hidden and shown again.
  await openSubTab(page, 'Projections');
  const detailAfterScenario = await page.evaluate(() => {
    const rows = document.querySelectorAll(
      '#enrollment_projections-projection_table .rt-tbody .rt-tr');
    if (!rows.length) return false;
    const cell = rows[0].querySelector('.rt-td');
    if (!cell) return false;
    cell.click();
    return true;
  });
  await waitForIdle(page, { timeout: 60000 });
  const reopened = detailAfterScenario && await waitFor(page, evidenceShown, { timeout: 30000 });
  check('a row still opens its evidence after visiting the Scenario sub-tab',
    reopened, detailAfterScenario ? '' : '(no row to click)');
  if (reopened) await closeEvidence(page);

  await clickNavTab(page, 'Enrollment');
  await waitFor(page, () => location.search === '?tab=enrollment', { timeout: 30000 });
  const enrollmentState = await page.evaluate(() => {
    const gather = document.getElementById('enrl_button');
    const tabs = [...document.querySelectorAll('#enrl_output_tabs a.nav-link')]
      .map((link) => link.textContent.trim());
    return {
      gatherVisible: !!gather && gather.checkVisibility({
        checkOpacity: true, checkVisibilityCSS: true,
      }),
      tabs,
    };
  });
  check('Enrollment Gather controls remain visible', enrollmentState.gatherVisible);
  check('Enrollment no longer contains a Projections subtab',
    !enrollmentState.tabs.includes('Projections'), enrollmentState.tabs.join(' | '));

  check('no uncaught JavaScript errors', jsErrors.length === 0, jsErrors.slice(0, 3).join(' | '));

  await browser.close();
  console.log(`\n${results.filter((result) => result.ok).length}/${results.length} checks passed`);
  process.exit(failed ? 1 : 0);
})().catch((error) => {
  console.error('TEST HARNESS ERROR:', error);
  process.exit(2);
});
