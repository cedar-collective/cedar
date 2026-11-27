// Freshness must be in the initial document, independent of Shiny responses.
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { execFileSync } from 'node:child_process';
import { launch, connect, setInput, click, clickNavTab, openSubTab, waitForIdle, readReactable, colIndex, BASE, cedarDataDir } from './lib.mjs';

const { browser, page, jsErrors } = await launch();
let passed = 0;
const exchangeFixture = path.join(os.tmpdir(), `cedar-ai-review-${process.pid}.json`);
const fixtureModel = `CEDAR browser fixture ${process.pid}-${Date.now()}`;
let importedFixture = null;
const check = (name, value) => {
  assert.ok(value, name);
  passed++;
  console.log(`PASS  ${name}`);
};
const readyCatalogModal = () => page.waitForFunction(() => {
  const modal = document.querySelector('.modal.show');
  return modal && getComputedStyle(modal).opacity === '1' &&
    modal.getAnimations({ subtree: true }).every(animation => animation.playState !== 'running');
});
try {
  // With scripts disabled there can be no websocket, output binding, or widget.
  await page.setJavaScriptEnabled(false);
  await page.goto(`${BASE}?tab=data-usage`, { waitUntil: 'domcontentloaded', timeout: 180000 });
  const initial = await page.evaluate(() => {
    const table = document.getElementById('data_status_table');
    return { rows: table?.querySelectorAll('tbody tr').length,
      text: table?.textContent, tag: table?.tagName,
      output: table?.className.includes('shiny') };
  });
  check('initial HTML already contains all four freshness rows', initial.rows === 4);
  check('freshness is a plain table, not a Shiny output', initial.tag === 'TABLE' && !initial.output);
  check('initial HTML includes source dates or explicit missing states',
    /\d{4}-\d{2}-\d{2}|Not available/.test(initial.text));

  await page.setJavaScriptEnabled(true);
  await connect(page, { tab: 'home', expect: 'Home' });
  await page.setOfflineMode(true);
  const revealMs = await page.evaluate(async () => {
    const start = performance.now();
    document.querySelector('.navbar [data-value="Data & Usage"]').click();
    await new Promise(resolve => requestAnimationFrame(() => requestAnimationFrame(resolve)));
    const table = document.getElementById('data_status_table');
    if (!table.checkVisibility()) {
      const ancestors = [];
      for (let el = table; el; el = el.parentElement) {
        const css = getComputedStyle(el);
        if (el.classList.contains('tab-pane') || css.display === 'none') {
          ancestors.push({ id: el.id, class: el.className, display: css.display, visibility: css.visibility });
        }
      }
      throw new Error(`Freshness table is hidden after Admin navigation: ${JSON.stringify({ ancestors,
        selected: [...document.querySelectorAll('[role="tab"][aria-selected="true"]')].map(el => el.textContent.trim()) })}`);
    }
    return performance.now() - start;
  });
  check(`freshness reveals without network/server response (${Math.round(revealMs)} ms)`, revealMs < 1000);
  await page.setOfflineMode(false);
  await page.screenshot({ path: '/tmp/cedar-admin-freshness.png', fullPage: true });

  await connect(page, { tab: 'data-usage', expect: 'Data & Usage' });
  // One Usage tab: the dashboard, its tables and the event log under one date
  // range, all from one read of the log.
  await openSubTab(page, 'Usage');
  await page.waitForFunction(() => {
    const table = document.getElementById('feature_usage_table');
    return table && table.innerText.trim().length > 0 && !table.classList.contains('recalculating');
  });
  await waitForIdle(page);
  const details = await page.evaluate(() => document.getElementById('feature_usage_table').innerText);
  check('on-demand event preview renders without a read error', !details.includes('Error loading data'));
  const overview = await page.evaluate(() => document.getElementById('usage_overview_ui').innerText);
  check('on-demand usage summary renders', overview.includes('Active sessions') || overview.includes('No usage data'));
  const usage = await page.evaluate(() => ({
    dates: document.getElementById('usage_overview_ui').closest('.tab-pane').querySelectorAll('.shiny-date-input input').length,
    tabs: [...document.querySelectorAll('#data_usage_tabs a')].map((a) => a.textContent.trim()),
    sameTab: document.getElementById('usage_overview_ui').closest('.tab-pane') === document.getElementById('feature_usage_table').closest('.tab-pane'),
  }));
  check(`the dashboard and the event log share one tab (${usage.tabs.join(', ')})`,
        usage.sameTab && usage.tabs.includes('Usage') && !usage.tabs.includes('Feature Details') && !usage.tabs.includes('Usage Overview') &&
        // Join Integrity was retired: the transform checks the IDs at every run.
        !usage.tabs.includes('Join Integrity'));
  check(`one date range filters both (${usage.dates} date inputs)`, usage.dates === 2);
  // This session's own visit is in today's log: the dashboard counts it and
  // the event log lists it, so the two read the same range.
  check('the dashboard and the event log read the same range',
        overview.includes('No usage data') === details.includes('No log data found'));

  // Mapping decisions link what to supply to the line (or file) that takes it;
  // the decision is an edit there, never in the running app. Programs, course
  // subjects and college values are separate tabs; other problems no mapping
  // can fix are a separate table.
  await openSubTab(page, 'Mappings');
  const readyAll = ids => page.waitForFunction((ids) => ids.every(id => {
    const el = document.getElementById(id);
    return el && el.innerText.trim().length > 0 && !el.classList.contains('recalculating');
  }), { timeout: 180000 }, ids);
  await readyAll(['mapping_decisions_programs_table', 'mapping_other_summary']);
  const linksIn = id => page.evaluate((id) =>
    [...document.querySelectorAll(`#${id} a`)].map(a => a.href), id);
  const linkOk = href => /\/edit\/.+\.csv$/.test(href) || /\.csv\?plain=1#L\d+$/.test(href);
  const work = await page.evaluate(() => ({
    summary: document.getElementById('mapping_decisions_summary').innerText,
    other: document.getElementById('mapping_other_summary').innerText,
  }));
  const programLinks = await linksIn('mapping_decisions_programs_table');
  check('mapping decisions summarise what is waiting', /mapping decision\(s\)|No mapping decisions/.test(work.summary));
  check('each program decision links to the line or file that takes it',
    programLinks.length > 0 && programLinks.every(linkOk));
  await openSubTab(page, 'Course subjects');
  await readyAll(['mapping_decisions_subjects_table']);
  // Headers display in capitals, and innerText reports what is displayed.
  const subjects = await page.evaluate(() =>
    document.getElementById('mapping_decisions_subjects_table').innerText);
  const subjectLinks = await linksIn('mapping_decisions_subjects_table');
  check('course subjects have their own table, by teaching college',
    /taught in college/i.test(subjects) || subjects.includes('No course subject decisions'));
  check('each subject decision links to the line or file that takes it', subjectLinks.every(linkOk));
  check('other problems are listed separately', /other problem\(s\)/.test(work.other));
  // Code history: every code_history.csv row, proposed first, each linked to
  // its line, with when the schedule lists each code.
  await readyAll(['code_history_summary', 'code_history_table']);
  const history = await page.evaluate(() => ({
    summary: document.getElementById('code_history_summary').innerText,
    table: document.getElementById('code_history_table').innerText,
  }));
  const historyLinks = await linksIn('code_history_table');
  check('code history summarises confirmed and proposed rows',
    /\d+ successions: \d+ confirmed, \d+ proposed/.test(history.summary));
  check('code history shows when each code was offered',
    /old code offered/i.test(history.table) && /new code offered/i.test(history.table));
  check('each code history row links to its line',
    historyLinks.length > 0 && historyLinks.every(href => /code_history\.csv\?plain=1#L\d+$/.test(href)));
  await openSubTab(page, 'Program to Dept');
  await readyAll(['program_dept_mapping_table']);
  const programRef = await page.evaluate(() =>
    document.getElementById('program_dept_mapping_table').innerText);
  check('program mappings show program and department names',
    /program name/i.test(programRef) && /dept name/i.test(programRef));
  // The rules that place rows without a mapping-file row, with their counts,
  // and the campus codes with where each is counted.
  await readyAll(['counting_rules_table']);
  const rules = await page.evaluate(() => document.getElementById('counting_rules_table').innerText);
  check('counting rules list each rule with what it touches',
    ['Concentrations', 'Cross-listed courses', 'Students with no program record', 'Home campus']
      .every(rule => rules.includes(rule)) && /affects now/i.test(rules));
  await openSubTab(page, 'Campuses');
  await readyAll(['campus_mapping_table']);
  const campusRef = await page.evaluate(() => document.getElementById('campus_mapping_table').innerText);
  check('campus codes show their group and default scope',
    campusRef.includes('ABQ') && /in default scope/i.test(campusRef));
  await page.screenshot({ path: '/tmp/cedar-admin-mappings.png', fullPage: true });

  await openSubTab(page, 'Catalog Review');
  await readyAll(['catalog_review-rules-table']);
  check('Catalog Review opens on the actual visualization rules rather than parser flags',
    await page.$eval('#catalog_review-rules-summary', el => el.innerText.includes('does not require per-rule approval')));
  await page.$eval('#catalog_review-rules-catalog', el => el.selectize.setValue('history-ba-2026'));
  await waitForIdle(page);
  await page.waitForFunction(() => document.getElementById('catalog_review-rules-summary')?.innerText.includes('History B.A.'));
  check('selected planning scenario shows the math starting-point label',
    await page.$eval('#catalog_review-rules-summary', el =>
      el.innerText.includes('Math: College-algebra-ready') && !el.innerText.includes('Math: NA')));
  const ruleList = await readReactable(page, 'catalog_review-rules-table');
  check('History rules show readable requirements and the catalog wording',
    colIndex(ruleList.headers, 'Readable rule') >= 0 && colIndex(ruleList.headers, 'Catalog wording') >= 0 &&
    ruleList.rows.some(row => row.join(' ').includes('History major')));
  await page.screenshot({ path: '/tmp/cedar-admin-visualization-rules.png', fullPage: true });

  // Catalog questions: every reading's open items, by who can settle each.
  // An institution with no compiled readings shows the empty state instead.
  await openSubTab(page, 'Catalog questions');
  if (await page.$('#catalog_review-questions-questions')) {
    await readyAll(['catalog_review-questions-questions', 'catalog_review-questions-boards']);
    const questionList = await readReactable(page, 'catalog_review-questions-questions');
    const who = colIndex(questionList.headers, 'Who can settle it');
    check('Catalog questions lists open questions with who can settle each and the file to change',
      questionList.rows.length > 0 && who >= 0 && colIndex(questionList.headers, 'Change it in') >= 0 &&
      questionList.rows.every(row => /\.json · (rule|question|passage) |the catalog page, then a new catalog scan/.test(row.join(' '))));
    await page.$eval('#catalog_review-questions-settled_by', el => el.selectize.setValue('catalog'));
    await waitForIdle(page);
    await page.waitForFunction(() => !document.getElementById('catalog_review-questions-questions')?.classList.contains('recalculating'));
    const catalogOnly = await readReactable(page, 'catalog_review-questions-questions');
    check('"The catalog" keeps only the questions the catalog can settle',
      catalogOnly.rows.length > 0 && catalogOnly.rows.every(row => row[who] === 'The catalog'));
    // A degree total the catalog states two ways is one of them, found by the
    // catalog scan and named by no reading (it replaced Extraction diagnostics).
    const questionSearch = '#catalog_review-questions-questions input.rt-search';
    const totalsQuery = 'gives this degree two totals';
    await page.type(questionSearch, totalsQuery);
    await page.waitForFunction(() => document.querySelector('#catalog_review-questions-questions .rt-tbody')?.innerText.includes('two totals'));
    const totals = await readReactable(page, 'catalog_review-questions-questions');
    check('a degree total the catalog states two ways is a question for the catalog, changed on its page',
      totals.rows.length > 0 && totals.rows.every(row => row[who] === 'The catalog' &&
        row.join(' ').includes('the catalog page, then a new catalog scan')));
    await page.focus(questionSearch);
    await page.keyboard.press('End');
    for (let i = 0; i < totalsQuery.length; i++) await page.keyboard.press('Backspace');
    await page.waitForFunction((sel) => document.querySelector(sel)?.value === '', {}, questionSearch);
    check('clearing the search shows every question the catalog can settle again',
      (await readReactable(page, 'catalog_review-questions-questions')).rows.length === catalogOnly.rows.length);
    const boardList = await readReactable(page, 'catalog_review-questions-boards');
    check('each board compiled from a reading is listed with what it leaves out',
      boardList.rows.length > 0 && colIndex(boardList.headers, 'What the board leaves out') >= 0);
    await page.screenshot({ path: '/tmp/cedar-admin-catalog-questions.png', fullPage: true });
  } else {
    check('Catalog questions says when no readings are compiled',
      await page.evaluate(() => document.body.innerText.includes('No catalog readings are compiled for this institution.')));
  }
  await openSubTab(page, 'Draft interpretations');
  await page.waitForFunction(() => document.getElementById('catalog_review-normalization-status')?.innerText.trim());
  const reviewProgram = '#catalog_review-normalization-program';
  const hasPackets = await page.$eval(reviewProgram, el => el.options.length > 0);
  if (hasPackets) {
    await page.waitForFunction(() => document.querySelector('#catalog_review-normalization-evidence blockquote'));
    check('program review opens with captured evidence and keeps the planner unchanged',
      await page.$eval('#catalog_review-normalization-status', el => el.innerText.includes('No proposal changes a semester plan')));
    const selectedProgram = await page.$eval(reviewProgram, el => el.value);
    check('file import and per-rule approval controls are deferred',
      !await page.$('#catalog_review-normalization-response') &&
      !await page.$('#catalog_review-normalization-import') &&
      !await page.$('#catalog_review-normalization-approve') &&
      !await page.$('#catalog_review-normalization-confirm'));
    await page.waitForFunction(() => document.getElementById('catalog_review-normalization-review_status')?.innerText.includes('Draft —'));
    check('a versioned program draft loads automatically with catalog comparison',
      (await readReactable(page, 'catalog_review-normalization-rules')).rows.length > 0);
    check('unresolved cases prevent whole-unit sign-off',
      !await page.$('#catalog_review-normalization-approve_unit') &&
      (await readReactable(page, 'catalog_review-normalization-issues')).rows.length > 0);
    await page.screenshot({ path: '/tmp/cedar-admin-program-review.png', fullPage: true });

    // Exercise save/sign-off using a uniquely attributed, disposable response.
    // This deliberately informational fixture is not an academic interpretation.
    // The retained maintenance CLI stages it; upload controls stay absent.
    const store = path.join(cedarDataDir(), 'catalog-normalizations/unm');
    const programPacket = JSON.parse(fs.readFileSync(path.join(store, 'programs', selectedProgram, 'packet.json'), 'utf8'));
    const unit = programPacket.units[0]; const packet = unit.request;
    const proposal = {
      schema_version: '1.0.0',
      nodes: packet.source_blocks.map((block, i) => ({ id: `fixture-${i}`, parent_id: '', entity_id: block.entity_id,
        phase: block.phase === 'info' ? 'information' : block.phase, kind: 'information', label: block.text,
        minimum: null, maximum: null, unit: 'none', comparison: 'none', value: 'Disposable browser workflow fixture only',
        minimum_grade: '', course_refs: [], program_ref: '', timing: 'not_applicable',
        citations: [{ block_id: block.id, quote: block.text }] })),
      coverage: packet.source_blocks.map((block, i) => ({ block_id: block.id, disposition: 'information',
        node_ids: [`fixture-${i}`], explanation: 'Disposable browser workflow fixture only' })), questions: []
    };
    fs.writeFileSync(exchangeFixture, JSON.stringify(proposal));
    execFileSync('Rscript', ['--vanilla', 'scripts/normalize-degree-catalog.R', 'import', '--root', store,
      '--program', selectedProgram, '--unit', unit.key, '--response', exchangeFixture, '--model', fixtureModel],
      { timeout: 120000, stdio: 'pipe' });
    const proposalRoot = path.join(store, 'proposals', unit.key);
    const fixtureKey = fs.readdirSync(proposalRoot).find(key => {
      const file = path.join(proposalRoot, key, 'proposal-manifest.json');
      return fs.existsSync(file) && JSON.parse(fs.readFileSync(file, 'utf8')).model === fixtureModel;
    });
    assert.ok(fixtureKey, 'maintenance CLI preserved the disposable response');
    importedFixture = { key: fixtureKey, unit: unit.key };
    await click(page, 'catalog_review-normalization-refresh');
    await page.waitForFunction(key => !!document.getElementById('catalog_review-normalization-proposal')?.selectize?.options[key], {}, fixtureKey);
    await page.$eval('#catalog_review-normalization-proposal', (el, value) => el.selectize.setValue(value), fixtureKey);
    await page.waitForFunction(() => document.getElementById('catalog_review-normalization-review_status')?.innerText.includes('0 review cases'));
    check('routine rules need a single sign-off and no per-passage confirmation',
      !!await page.$('#catalog_review-normalization-approve_unit') && !await page.$('#catalog_review-normalization-reviewed'));
    await page.type('#catalog_review-normalization-reviewer', 'CEDAR browser test');
    await page.type('#catalog_review-normalization-note', 'Designed browser fixture; not an academic review.');
    await setInput(page, 'catalog_review-normalization-reviewer', 'CEDAR browser test');
    await setInput(page, 'catalog_review-normalization-note', 'Designed browser fixture; not an academic review.');
    await page.click('#catalog_review-normalization-rules .rt-tbody .rt-tr');
    await page.waitForFunction(() => document.getElementById('catalog_review-normalization-selected_rule')?.innerText.includes('fixture-0'));
    const source = await page.$eval('#catalog_review-normalization-evidence blockquote', el => el.textContent);
    check('selecting a rule displays its exact catalog evidence beside it', source === packet.source_blocks[0].text);
    await click(page, 'catalog_review-normalization-question_rule');
    await page.waitForFunction(() => document.getElementById('catalog_review-normalization-review_status')?.innerText.includes('review revision 1'));
    check('a reviewer flag reopens attention and blocks sign-off', !await page.$('#catalog_review-normalization-approve_unit'));
    await click(page, 'catalog_review-normalization-clear_rule');
    await page.waitForFunction(() => document.getElementById('catalog_review-normalization-review_status')?.innerText.includes('review revision 2'));
    await click(page, 'catalog_review-normalization-edit');
    await readyCatalogModal();
    await page.type('#catalog_review-normalization-edit_label', ' [workflow fixture]');
    await setInput(page, 'catalog_review-normalization-edit_label', packet.source_blocks[0].text + ' [workflow fixture]');
    await click(page, 'catalog_review-normalization-save_edit');
    await page.waitForFunction(() => !document.querySelector('#shiny-modal'));
    await page.waitForFunction(() => document.getElementById('catalog_review-normalization-review_status')?.innerText.includes('review revision 3'));
    await click(page, 'catalog_review-normalization-approve_unit');
    await page.waitForFunction(() => document.getElementById('catalog_review-normalization-review_status')?.innerText.includes('Complete unit signed off'));
    await page.waitForFunction(() => document.getElementById('catalog_review-normalization-reviewed')?.getAttribute('href')?.includes('download'));
    const reviewed = await page.$eval('#catalog_review-normalization-reviewed', async el => (await fetch(el.href)).json());
    check('one sign-off records the reviewer and covers the complete unit',
      reviewed.status === 'human_reviewed' && reviewed.review_decisions.approval === 'unit' &&
      reviewed.last_review.reviewer === 'CEDAR browser test' && reviewed.review_revision === 4);
    await connect(page, { tab: 'data-usage', expect: 'Data & Usage' });
    await openSubTab(page, 'Catalog Review');
    await openSubTab(page, 'Draft interpretations');
    await page.waitForFunction(() => document.getElementById('catalog_review-normalization-program')?.options.length > 0);
    await page.$eval(reviewProgram, (el, value) => el.selectize.setValue(value), selectedProgram);
    await page.waitForFunction(() => document.getElementById('catalog_review-normalization-review_status')?.innerText.includes('review revision 4'));
    check('whole-unit sign-off survives a new Shiny session', true);
  }
  await clickNavTab(page, 'Projections');
  await waitForIdle(page);
  const projection = await page.evaluate(() => {
    const scope = document.getElementById('enrollment_projections-scope');
    const status = document.getElementById('enrollment_projections-bundle_status');
    return (scope?.innerText || '') + (status?.innerText || '');
  });
  // The scope line a loaded bundle writes ("Spring 2027 projections | Data
  // window: ..."), or the empty state when no bundle validates.
  check('deferred projections initialize when opened',
    projection.includes('projections | Data window') || projection.includes('No validated enrollment projection bundle'));
  check('no browser JavaScript errors', jsErrors.length === 0);
  console.log(`${passed} passed; screenshot /tmp/cedar-admin-freshness.png`);
} catch (error) {
  if (!page.isClosed()) await page.screenshot({ path: '/tmp/cedar-admin-failure.png', fullPage: true });
  throw error;
} finally {
  fs.rmSync(exchangeFixture, { force: true });
  if (importedFixture && /^[a-f0-9]{64}$/.test(importedFixture.key) && /^[a-f0-9]{64}$/.test(importedFixture.unit)) {
    const store = path.join(cedarDataDir(), 'catalog-normalizations/unm');
    const proposalDir = path.join(store, 'proposals', importedFixture.unit, importedFixture.key);
    const manifest = path.join(proposalDir, 'proposal-manifest.json');
    if (fs.existsSync(manifest) && JSON.parse(fs.readFileSync(manifest, 'utf8')).model === fixtureModel) {
      fs.rmSync(proposalDir, { recursive: true });
      fs.rmSync(path.join(store, 'reviews', importedFixture.key), { recursive: true, force: true });
    }
  }
  await browser.close();
}
