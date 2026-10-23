// Freshness must be in the initial document, independent of Shiny responses.
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { execFileSync } from 'node:child_process';
import { launch, connect, setInput, click, clickNavTab, openSubTab, waitForIdle, readReactable, colIndex, BASE } from './lib.mjs';

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
  check('initial HTML already contains all five freshness rows', initial.rows === 5);
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
  await openSubTab(page, 'Feature Details');
  await page.waitForFunction(() => {
    const table = document.getElementById('feature_usage_table');
    return table && table.innerText.trim().length > 0 && !table.classList.contains('recalculating');
  });
  const details = await page.evaluate(() => document.getElementById('feature_usage_table').innerText);
  check('on-demand event preview renders without a read error', !details.includes('Error loading data'));
  const stats = await page.evaluate(() => document.getElementById('usage_stats_output').innerText);
  check('shared full-range usage statistics render', !stats.includes('Error loading stats') && stats.includes('Sessions'));
  await openSubTab(page, 'Usage Overview');
  await waitForIdle(page);
  const overview = await page.evaluate(() => document.getElementById('usage_overview_ui').innerText);
  check('on-demand usage summary renders', overview.includes('Active sessions') || overview.includes('No usage data'));

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

  const queueStarted = performance.now();
  await openSubTab(page, 'Catalog Review');
  await readyAll(['catalog_review-rules-table']);
  check('Catalog Review opens on the actual visualization rules rather than parser flags',
    await page.$eval('#catalog_review-rules-summary', el => el.innerText.includes('does not require per-rule approval')));
  await page.$eval('#catalog_review-rules-catalog', el => el.selectize.setValue('history-ba-2026'));
  await waitForIdle(page);
  await page.waitForFunction(() => document.getElementById('catalog_review-rules-summary')?.innerText.includes('History B.A.'));
  check('selected planning scenario shows the math starting-point label',
    await page.$eval('#catalog_review-rules-summary', el =>
      el.innerText.includes('Math: Calculus-ready') && !el.innerText.includes('Math: NA')));
  const ruleList = await readReactable(page, 'catalog_review-rules-table');
  check('History rules show readable requirements and the catalog wording',
    colIndex(ruleList.headers, 'Readable rule') >= 0 && colIndex(ruleList.headers, 'Catalog wording') >= 0 &&
    ruleList.rows.some(row => row.join(' ').includes('History major')));
  await page.screenshot({ path: '/tmp/cedar-admin-visualization-rules.png', fullPage: true });
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
    const store = path.resolve('data/catalog-normalizations/unm');
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
  await openSubTab(page, 'Extraction diagnostics');
  await page.waitForFunction(() => {
    const text = document.getElementById('catalog_review-status')?.innerText || '';
    return /No catalog scans|All extracted requirements|Catalog review unavailable/.test(text);
  }, { timeout: 180000 });
  const catalogStatus = await page.$eval('#catalog_review-status', el => el.innerText);
  check('catalog review reports source errors instead of an empty successful queue',
    !catalogStatus.includes('Catalog review unavailable'));
  if (catalogStatus.includes('No catalog scans')) {
    check('an absent optional archive explains how to supply it', catalogStatus.includes('scan-degree-catalog.R'));
  } else {
    check('catalog review labels all extraction unreviewed and verifies saved evidence',
      catalogStatus.includes('All extracted requirements are unreviewed') && catalogStatus.includes('hashes verified'));
    await readyAll(['catalog_review-interpretation']);
    console.log(`TIMING  catalog review first queue: ${Math.round(performance.now() - queueStarted)} ms`);
    await page.waitForFunction(() => Object.keys(document.getElementById('catalog_review-program')?.selectize?.options || {}).some(Boolean));
    const firstProgram = await page.$eval('#catalog_review-program', el => Object.values(el.selectize.options).find(x => x.value)?.value);
    assert.ok(firstProgram, 'captured degrees populate the program selector');
    await page.$eval('#catalog_review-program', (el, value) => el.selectize.setValue(value), firstProgram);
    await page.$eval('#catalog_review-kind', el => el.selectize.setValue('Degree'));
    await page.$eval('#catalog_review-phase', el => el.selectize.setValue('Degree'));
    await openSubTab(page, 'All requirement sections');
    await readyAll(['catalog_review-sections']);
    const sectionRows = await page.$eval('#catalog_review-sections', el => el.innerText);
    check('degree filters retain complete requirement sections for validation',
      sectionRows.includes('Section has not been validated') && sectionRows.includes('Inspect'));
    await page.click('#catalog_review-sections button.btn-outline-secondary');
    await readyCatalogModal();
    const evidence = await page.$eval('.modal.show', el => ({ text: el.innerText,
      links: [...el.querySelectorAll('a')].map(a => ({ text: a.innerText, href: a.href })) }));
    check('Inspect shows full context, draft structure, pointer and source hash',
      ['captured catalog section', 'draft structure', 'source sha-256', '/degreerequirements']
        .every(text => evidence.text.toLowerCase().includes(text)));
    check('evidence links to both the published program and the captured public record',
      evidence.links.some(a => a.text === 'Open catalog page' && a.href.includes('#/programs/')) &&
      evidence.links.some(a => a.text === 'Public source record' && a.href.startsWith('https://')));
    await page.screenshot({ path: '/tmp/cedar-admin-catalog-evidence.png', fullPage: true });
    await page.keyboard.press('Escape');
    await page.waitForFunction(() => !document.querySelector('#shiny-modal'));
    await page.$eval('#catalog_review-program', el => el.selectize.setValue(''));
    await page.$eval('#catalog_review-kind', el => el.selectize.setValue(''));
    await page.$eval('#catalog_review-phase', el => el.selectize.setValue(''));
    // Older immutable analyses intentionally keep their original draft grammar.
    // New analyses expose the grade as a constraint in the evidence tree too.
    if (/Extractor: 1\.[1-9][0-9]*\./.test(catalogStatus)) {
      await openSubTab(page, 'All requirement sections');
      await readyAll(['catalog_review-sections']);
      await page.type('#catalog_review-sections input.rt-search', 'Earned a minimum grade of C in each of the following:');
      await waitForIdle(page);
      const gradeRows = await readReactable(page, 'catalog_review-sections');
      if (gradeRows.rows[0]?.at(-1) === 'Inspect') {
        await page.click('#catalog_review-sections button.btn-outline-secondary');
        await readyCatalogModal();
        const gradeTree = await page.$eval('.modal.show details pre', el => el.textContent);
        check('recognized grade requirements remain visible as constraints in the draft tree',
          gradeTree.includes('[minimum grade C]') && gradeTree.includes('Course:'));
        await page.keyboard.press('Escape');
        await page.waitForFunction(() => !document.querySelector('#shiny-modal'));
      }
      await page.click('#catalog_review-sections input.rt-search', { clickCount: 3 });
      await page.keyboard.press('Backspace');
      await waitForIdle(page);
    }
    if (catalogStatus.includes('shared status milestones are recognized')) {
      await openSubTab(page, 'Milestones');
      await readyAll(['catalog_review-milestones']);
      const search = '#catalog_review-milestones input.rt-search';
      // Both cases use published grammar, not institution-specific codes.
      for (const [query, expected, screenshot] of [
        ['Must have a class standing of Junior', 'class_standing:is:Junior', '/tmp/cedar-admin-catalog-standing.png'],
        ['Program admission milestone', 'program_admission:', '/tmp/cedar-admin-catalog-admission.png']
      ]) {
        const hasSearch = await page.$(search);
        if (!hasSearch) break; // This catalog may contain no supported status gates.
        await page.click(search, { clickCount: 3 });
        await page.keyboard.press('Backspace');
        await page.type(search, query);
        await waitForIdle(page);
        const milestoneRows = await readReactable(page, 'catalog_review-milestones');
        if (milestoneRows.rows[0]?.at(-1) !== 'Inspect') continue;
        await page.click('#catalog_review-milestones button.btn-outline-secondary');
        await readyCatalogModal();
        const milestone = await page.$eval('.modal.show', el => ({
          text: el.textContent, tree: el.querySelector('details pre')?.textContent
        }));
        check(`${query}: Inspect retains a shared milestone and full rule context`,
          milestone.text.includes('Shared milestone:') && milestone.text.includes(expected) &&
          milestone.tree.includes('Status milestone:') && milestone.text.includes('Captured catalog section'));
        if (expected.startsWith('program_admission:')) {
          check('program admission Inspect supplies policy evidence or explicit missing-policy context',
            milestone.text.includes('Linked program admission policy') || milestone.text.includes('No admission policy section was supplied'));
        }
        await page.screenshot({ path: screenshot, fullPage: true });
        await page.keyboard.press('Escape');
        await page.waitForFunction(() => !document.querySelector('#shiny-modal'));
      }
      if (await page.$(search)) {
        await page.click(search, { clickCount: 3 });
        await page.keyboard.press('Backspace');
        await waitForIdle(page);
      }
    }
    await openSubTab(page, 'Source checks');
    await readyAll(['catalog_review-source']);
    const sourceChecks = await page.$eval('#catalog_review-source', el => el.innerText);
    check('source checks expose flags separately from narrative interpretation',
      sourceChecks.includes('Catalog inclusion flag') || sourceChecks.includes('No items match'));
    await openSubTab(page, 'Requirements to interpret');
    await readyAll(['catalog_review-interpretation']);
    const pageOne = await readReactable(page, 'catalog_review-interpretation');
    const nextAvailable = await page.$eval('#catalog_review-interpretation', el => {
      const next = [...el.querySelectorAll('button')].find(b => b.textContent.trim() === 'Next');
      if (!next || next.disabled) return false;
      next.click(); return true;
    });
    if (nextAvailable) {
      await page.waitForFunction(previous => {
        const cell = document.querySelector('#catalog_review-interpretation .rt-tbody .rt-tr .rt-td');
        return cell && cell.innerText.trim() !== previous;
      }, {}, pageOne.rows[0][0]);
      const pageTwo = await readReactable(page, 'catalog_review-interpretation');
      await page.click('#catalog_review-interpretation button.btn-outline-secondary');
      await readyCatalogModal();
      const selectedTitle = await page.$eval('.modal.show .modal-title', el => el.innerText.trim());
      check('Inspect on a later table page opens the correct source item', selectedTitle === pageTwo.rows[0][0]);
      await page.keyboard.press('Escape');
      await page.waitForFunction(() => !document.querySelector('#shiny-modal'));
    }
    // Returning to the page must preserve the selected degree and loaded view.
    await page.$eval('#catalog_review-program', (el, value) => el.selectize.setValue(value), firstProgram);
    await waitForIdle(page);
    await openSubTab(page, 'Mappings');
    const returnStarted = performance.now();
    await openSubTab(page, 'Catalog Review');
    await readyAll(['catalog_review-interpretation']);
    await page.waitForFunction(() => document.getElementById('catalog_review-status')?.innerText.includes('All extracted requirements are unreviewed'));
    check('returning to catalog review preserves the degree filter',
      await page.$eval('#catalog_review-program', el => el.selectize.getValue()) === firstProgram);
    console.log(`TIMING  catalog review return: ${Math.round(performance.now() - returnStarted)} ms`);
    const returnedRows = await readReactable(page, 'catalog_review-interpretation');
    if (returnedRows.rows[0]?.at(-1) === 'Inspect') {
      await page.click('#catalog_review-interpretation button.btn-outline-secondary');
      await readyCatalogModal();
      check('Inspect remains functional after returning to the review queue',
        await page.$eval('.modal.show .modal-title', el => el.innerText.trim()) === returnedRows.rows[0][0]);
      await page.keyboard.press('Escape');
      await page.waitForFunction(() => !document.querySelector('#shiny-modal'));
    }
    await page.screenshot({ path: '/tmp/cedar-admin-catalog-review.png', fullPage: true });
  }

  await clickNavTab(page, 'Projections');
  await waitForIdle(page);
  const projection = await page.evaluate(() => {
    const scope = document.getElementById('enrollment_projections-scope');
    const status = document.getElementById('enrollment_projections-bundle_status');
    return (scope?.innerText || '') + (status?.innerText || '');
  });
  check('deferred projections initialize when opened',
    projection.includes('demand') || projection.includes('No validated enrollment projection bundle'));
  check('no browser JavaScript errors', jsErrors.length === 0);
  console.log(`${passed} passed; screenshot /tmp/cedar-admin-freshness.png`);
} catch (error) {
  if (!page.isClosed()) await page.screenshot({ path: '/tmp/cedar-admin-failure.png', fullPage: true });
  throw error;
} finally {
  fs.rmSync(exchangeFixture, { force: true });
  if (importedFixture && /^[a-f0-9]{64}$/.test(importedFixture.key) && /^[a-f0-9]{64}$/.test(importedFixture.unit)) {
    const store = path.resolve('data/catalog-normalizations/unm');
    const proposalDir = path.join(store, 'proposals', importedFixture.unit, importedFixture.key);
    const manifest = path.join(proposalDir, 'proposal-manifest.json');
    if (fs.existsSync(manifest) && JSON.parse(fs.readFileSync(manifest, 'utf8')).model === fixtureModel) {
      fs.rmSync(proposalDir, { recursive: true });
      fs.rmSync(path.join(store, 'reviews', importedFixture.key), { recursive: true, force: true });
    }
  }
  await browser.close();
}
