// Saved-artifact regression checks for Registration > Projections.
//
//   node tests/e2e/enrollment-projections.test.mjs
import {
  launch, connect, clickNavTab, setInput, waitFor, waitForIdle,
  waitForSelector, readReactable, colIndex, requireIds,
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
    'enrollment_projections-group',
    'enrollment_projections-department',
    'enrollment_projections-course',
    'enrollment_projections-confidence',
    'enrollment_projections-download',
    'enrollment_projections-projection_table_anchor',
    'enrollment_projections-projection_table',
  ];
  await requireIds(page, ids);
  await waitForSelector(
    page,
    '#enrollment_projections-projection_table .rt-tbody .rt-tr',
    { timeout: 120000 }
  );

  check(
    'standalone projections route remains canonical',
    await page.evaluate(() => location.search === '?tab=projections')
  );

  const initialContext = await page.evaluate(() => {
    const group = document.getElementById('enrollment_projections-group');
    const scope = document.getElementById('enrollment_projections-scope');
    const modelInfo = scope && scope.querySelector('.enrollment-projection-model-info');
    return {
      group: group ? group.value : null,
      scope: scope ? scope.innerText.trim() : '',
      modelNote: modelInfo ? modelInfo.getAttribute('title') : '',
    };
  });
  check('Always monitored is the default course group',
    initialContext.group === 'always_monitored', initialContext.group || '(missing)');
  check('scope names the historical data window',
    initialContext.scope.includes('Data window: Spring 2022 through Fall 2026'),
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
    'Confidence', 'Bias correction', 'Population fit', 'Recommendation',
  ];
  check(
    'projection table exposes the audit columns',
    requiredHeaders.every((header) => colIndex(table.headers, header) >= 0),
    table.headers.join(' | ')
  );
  check('saved projection rows render', table.rows.length > 0, `${table.rows.length} visible`);

  await setInput(page, 'enrollment_projections-group', 'all_saved');
  await waitFor(page, () => {
    const root = document.getElementById('enrollment_projections-projection_table');
    return root && root.querySelectorAll('.rt-tbody .rt-tr').length === 25;
  }, { timeout: 60000 });
  table = await readReactable(page, 'enrollment_projections-projection_table');
  check('larger groups show 25 rows by default', table.rows.length === 25,
    `${table.rows.length} visible`);
  await setInput(page, 'enrollment_projections-group', 'always_monitored');
  await waitForIdle(page, { timeout: 60000 });

  await setInput(page, 'enrollment_projections-confidence', ['None']);
  await waitFor(page, () => {
    const root = document.getElementById('enrollment_projections-projection_table');
    const headers = root ? [...root.querySelectorAll('.rt-thead .rt-th')]
      .map((cell) => cell.innerText.trim().toLowerCase()) : [];
    const confidenceIndex = headers.indexOf('confidence');
    const rows = root ? [...root.querySelectorAll('.rt-tbody .rt-tr')] : [];
    return confidenceIndex >= 0 && rows.length > 0 && rows.every((row) => {
      const cells = [...row.querySelectorAll('.rt-td')];
      return cells[confidenceIndex] &&
        cells[confidenceIndex].innerText.trim().toLowerCase() === 'none';
    });
  }, { timeout: 60000 });
  table = await readReactable(page, 'enrollment_projections-projection_table');
  const confidenceIndex = colIndex(table.headers, 'Confidence');
  const selectionOffset = table.rows[0].length - table.headers.length;
  check(
    'confidence None rows remain visible',
    table.rows.length > 0 &&
      table.rows.every((row) =>
        row[confidenceIndex + selectionOffset].trim().toLowerCase() === 'none')
  );

  await setInput(page, 'enrollment_projections-confidence', null);
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
  await waitForSelector(page, '.enrollment-projection-back', { timeout: 60000 });

  const history = await readReactable(page, 'enrollment_projections-history_table');
  const expectedHistoryOrder = [
    'Term', 'Aftcast', 'Raw error', 'Assessment', 'Class list', 'Census',
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

  const candidates = await readReactable(page, 'enrollment_projections-candidate_table');
  const candidateText = candidates.rows.flat().join(' ');
  check('broad-population candidate is visible', candidateText.includes('Spring population growth'));
  check('major/classification candidate is visible', candidateText.includes('Spring cohort flow'));
  check('all six candidates are inspectable', candidates.rows.length === 6,
    `${candidates.rows.length} rows`);

  await page.evaluate(() => {
    document.querySelector('.enrollment-projection-back').click();
  });
  const returnedToTable = await waitFor(page, () =>
    location.hash === '#enrollment_projections-projection_table_anchor',
  { timeout: 10000 });
  check('projection evidence includes navigation back to the table', returnedToTable);

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
