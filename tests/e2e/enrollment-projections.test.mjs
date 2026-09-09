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

(async () => {
  const { browser, page, jsErrors } = await launch({ width: 1440, height: 1000 });
  await connect(page, { tab: 'projections', expect: 'Projections', settle: 4500 });

  const ids = [
    'enrollment_projections-target_term',
    'enrollment_projections-group',
    'enrollment_projections-department',
    'enrollment_projections-course',
    'enrollment_projections-stability',
    'enrollment_projections-accuracy',
    'enrollment_projections-download',
    'enrollment_projections-projection_table_anchor',
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
    pageChrome.subtitle.includes('Saved course-demand projections'), pageChrome.subtitle);
  check('methodology and column guide use a collapsed info panel',
    pageChrome.guideTitle.includes('How projections work and how to read the table') &&
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
    ['3 historical baselines', '3 diagnostic upstream indicators',
      '3 selectable anchored blends', 'Raw upstream indicators never win']
      .every((phrase) => methodGuide.text.includes(phrase)),
    methodGuide.text.slice(0, 700));
  check('method guide describes all nine registered methods',
    ['Prior same-season', 'Seasonal median', 'Seasonal trend',
      'Spring population growth', 'Spring cohort flow', 'Feeder transitions',
      'Prior season + population change', 'Prior season + cohort change',
      'Prior season + feeder change']
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
    await setInput(page, 'enrollment_projections-target_term', otherSeason.value);
    await waitForIdle(page);
    const switched = await page.evaluate(() => {
      const scope = document.getElementById('enrollment_projections-scope');
      const rows = document.querySelectorAll(
        '#enrollment_projections-projection_table .rt-tbody .rt-tr');
      return { scope: scope ? scope.innerText.trim() : '', rows: rows.length };
    });
    check(`switching to ${otherSeason.label} loads that season's bundle`,
      switched.scope.includes(otherSeason.label) && switched.rows > 0,
      `${switched.scope.split('\n')[0]} | ${switched.rows} rows`);
    // Restore the opening season; every later check reads that bundle.
    await setInput(page, 'enrollment_projections-target_term', initialContext.target);
    await waitForIdle(page);
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
    'Course', 'Projection', 'Expected census', 'Method', 'Aftcast accuracy',
    'Stability', 'Depth', 'Accuracy', 'Planning sects',
  ];
  check(
    'projection table exposes the audit columns',
    requiredHeaders.every((header) => colIndex(table.headers, header) >= 0),
    table.headers.join(' | ')
  );
  check(
    'summary replaces audit prose with four same-season enrollment/section columns',
    table.headers.filter((header) =>
      header.toLowerCase().includes('first day / sects')).length === 4 &&
      !['Bias correction', 'Population fit', 'Recommendation']
        .some((header) => colIndex(table.headers, header) >= 0),
    table.headers.join(' | ')
  );
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
  await setInput(page, 'enrollment_projections-group', 'always_monitored');
  await waitForIdle(page, { timeout: 60000 });

  await setInput(page, 'enrollment_projections-stability', ['Volatile']);
  await waitFor(page, () => {
    const root = document.getElementById('enrollment_projections-projection_table');
    const headers = root ? [...root.querySelectorAll('.rt-thead .rt-th')]
      .map((cell) => cell.innerText.trim().toLowerCase()) : [];
    const stabilityIndex = headers.indexOf('stability');
    const rows = root ? [...root.querySelectorAll('.rt-tbody .rt-tr')] : [];
    return stabilityIndex >= 0 && rows.length > 0 && rows.every((row) => {
      const cells = [...row.querySelectorAll('.rt-td')];
      return cells[stabilityIndex] &&
        cells[stabilityIndex].innerText.trim().toLowerCase() === 'volatile';
    });
  }, { timeout: 60000 });
  table = await readReactable(page, 'enrollment_projections-projection_table');
  const stabilityIndex = colIndex(table.headers, 'Stability');
  const selectionOffset = table.rows[0].length - table.headers.length;
  check(
    'the volatile-history attention list filters to Volatile rows only',
    table.rows.length > 0 &&
      table.rows.every((row) =>
        row[stabilityIndex + selectionOffset].trim().toLowerCase() === 'volatile')
  );

  // The axes are independent: filtering to Volatile must not also filter the
  // evidence axes, or the table would be quietly answering a narrower question.
  const accuracyIndex = colIndex(table.headers, 'Accuracy');
  const depthIndex = colIndex(table.headers, 'Depth');
  check(
    'volatile rows still span more than one depth or accuracy value',
    new Set(table.rows.map((row) => row[depthIndex + selectionOffset].trim())).size > 1 ||
      new Set(table.rows.map((row) => row[accuracyIndex + selectionOffset].trim())).size > 1
  );

  await setInput(page, 'enrollment_projections-stability', null);
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
  const movementPanel = await page.evaluate(() => {
    const panel = document.querySelector('details.enrollment-projection-movement');
    if (panel) panel.open = true;
    return {
      found: !!panel,
      title: panel ? panel.querySelector('summary')?.innerText.trim() : '',
    };
  });
  check('course detail includes the enrollment movement accordion',
    movementPanel.found && movementPanel.title.includes('Enrollment movement diagnostic'),
    movementPanel.title || '(missing)');
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
    ['Planning recommendation', 'Bias correction', 'Population fit']
      .every((label) => detailSummaryText.includes(label)), detailSummaryText.slice(0, 500));
  await waitForSelector(page, '.enrollment-projection-back', { timeout: 60000 });

  const history = await readReactable(page, 'enrollment_projections-history_table');
  const expectedHistoryOrder = [
    'Term', 'Aftcast', 'Raw error', 'Assessment',
    'First day / ever registered', 'Census', 'Final / last day',
    'Sections', 'Capacity', 'Fill', 'Potential explanation',
  ];
  check(
    'history places aftcast and error before actual enrollment',
    expectedHistoryOrder.every((name, i) =>
      history.headers[i] && history.headers[i].toLowerCase() === name.toLowerCase()),
    history.headers.join(' | ')
  );
  check(
    'capacity-bounded history is labeled rather than shown as zero error',
    history.rows.some((row) => row.join(' ').includes('Capacity-bounded'))
  );

  const detailEvidence = await page.evaluate(() => {
    const detail = document.getElementById('enrollment_projections-detail');
    const plot = document.getElementById('enrollment_projections-method_history_plot');
    const traces = plot ? [...plot.querySelectorAll('.legendtext')]
      .map((node) => node.textContent.trim()) : [];
    return { text: detail ? detail.innerText : '', traces };
  });
  check('detail says aftcasts are scored against the first-day proxy',
    detailEvidence.text.includes('against the first day / ever registered proxy'));
  check('detail explains all three axes separately for CHEM 1215',
    detailEvidence.text.includes('Stability:') &&
      detailEvidence.text.includes('Depth:') &&
      detailEvidence.text.includes('Accuracy:'));
  check('historical plot includes all enrollment lifecycle measures',
    ['First day / ever registered (model target)', 'Census', 'Final / last day']
      .every((name) => detailEvidence.traces.includes(name)),
    detailEvidence.traces.join(' | '));
  check('historical plot highlights the selected method',
    detailEvidence.traces.some((name) => name.endsWith('(selected)')),
    detailEvidence.traces.join(' | '));

  const candidates = await readReactable(page, 'enrollment_projections-candidate_table');
  const candidateText = candidates.rows.flat().join(' ');
  check('broad-population candidate is visible', candidateText.includes('Spring population growth'));
  check('major/classification candidate is visible', candidateText.includes('Spring cohort flow'));
  check('all nine candidates are inspectable', candidates.rows.length === 9,
    `${candidates.rows.length} rows`);

  await page.evaluate(() => {
    document.querySelector('.enrollment-projection-back').click();
  });
  const returnedToTable = await waitFor(page, () =>
    {
      const firstRow = document.querySelector(
        '#enrollment_projections-projection_table .rt-tbody .rt-tr'
      );
      const detail = document.getElementById('enrollment_projections-detail');
      const rowRect = firstRow ? firstRow.getBoundingClientRect() : null;
      return location.hash === '#enrollment_projections-projection_table_anchor' &&
        document.activeElement &&
        document.activeElement.id === 'enrollment_projections-projection_table_anchor' &&
        rowRect && rowRect.top >= 0 && rowRect.top < window.innerHeight &&
        detail && detail.innerText.includes('Select a projection row');
    },
  { timeout: 10000 });
  check('projection evidence includes navigation back to the table', returnedToTable);

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
