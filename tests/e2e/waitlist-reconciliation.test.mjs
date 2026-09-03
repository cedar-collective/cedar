// Cross-tab waitlist reconciliation.
//
// Selects a real High Waitlists row from Regstats, follows its Waiting link,
// and proves that Waitlists restores the row's visible scope and count. The
// course is chosen from the running data so this checks the deployed dataset
// rather than a fixture-specific example.
import {
  launch, connect, setInput, runAndWait, openSubTab, waitFor,
  waitForSelector, readReactable, colIndex,
} from './lib.mjs';

const TERM = process.env.CEDAR_RECON_TERM || null;
const MIN_WAIT = Number(process.env.CEDAR_RECON_MIN_WAIT || 5);

function requiredColumn(table, name) {
  const index = colIndex(table.headers || [], name);
  if (index < 0) {
    throw new Error(`missing ${name} column; headers: ${(table.headers || []).join(' | ')}`);
  }
  return index;
}

function countValue(value) {
  const parsed = Number(String(value).replace(/[^0-9.-]/g, ''));
  if (!Number.isFinite(parsed)) throw new Error(`could not parse count: ${value}`);
  return parsed;
}

function inputPartTerm(displayValue) {
  if (displayValue === 'Full') return '1';
  if (displayValue === '—') return '';
  return displayValue;
}

(async () => {
  const { browser, page, jsErrors } = await launch();

  try {
    await connect(page, { tab: 'registration', expect: 'Regstats' });

    // Seed conflicting Waitlists state before the jump. The link must replace
    // it with the Regstats report scope, not silently combine the new row with
    // filters left behind by an earlier Waitlists visit.
    await setInput(page, 'waitlist-wl_dept', ['STALE']);
    await setInput(page, 'waitlist-wl_level', ['graduate']);

    // Match the Waitlists display floor and keep the ordinary Regstats defaults
    // for campus/level. An optional term override supports installations whose
    // configured registration term is not the active waitlist term.
    await setInput(page, 'regstats-rs_min_wait', MIN_WAIT);
    if (TERM) await setInput(page, 'regstats-rs_term', [TERM]);
    await runAndWait(page, 'regstats-rs_dashboard_button', { timeout: 180000 });
    await waitForSelector(page, '#regstats-rs_dashboard', { timeout: 120000 });

    await openSubTab(page, 'High Waitlists', { timeout: 120000 });
    await waitForSelector(page, '#regstats-rs_waits_table .rt-tbody .rt-tr', {
      timeout: 120000,
    });

    const source = await readReactable(page, 'regstats-rs_waits_table', { limit: 10 });
    if (source.error) throw new Error(source.error);
    if (!source.rows?.length) {
      throw new Error(
        `Regstats returned no waitlist rows at Min Waiting ${MIN_WAIT}` +
        (TERM ? ` for term ${TERM}` : ' for its configured default term')
      );
    }

    const sourceCols = {
      term: requiredColumn(source, 'Term'),
      campus: requiredColumn(source, 'Campus'),
      college: requiredColumn(source, 'College'),
      course: requiredColumn(source, 'Course'),
      title: requiredColumn(source, 'Title'),
      pt: requiredColumn(source, 'PoT'),
      waiting: requiredColumn(source, 'Waiting'),
    };
    const sourceRow = source.rows[0];
    const expected = Object.fromEntries(
      Object.entries(sourceCols).map(([name, index]) => [name, sourceRow[index]])
    );
    expected.waiting = countValue(expected.waiting);
    const sourceFilters = await page.evaluate(() => {
      const values = (id) => {
        const el = document.getElementById(id);
        const raw = el?.selectize ? el.selectize.getValue() : el?.value;
        return (Array.isArray(raw) ? raw : [raw])
          .map((value) => String(value ?? ''))
          .filter(Boolean)
          .sort();
      };
      return {
        dept: values('regstats-rs_dept'),
        level: values('regstats-rs_level'),
      };
    });

    const clicked = await page.evaluate(() => {
      const link = document.querySelector(
        '#regstats-rs_waits_table .rt-tbody .rt-tr:first-child a'
      );
      if (!link) return false;
      link.click();
      return true;
    });
    if (!clicked) throw new Error('first Regstats waitlist row had no drill link');

    const restored = await waitFor(page, (scope) => {
      const active = [...document.querySelectorAll('.navbar [data-value]')]
        .find((el) => el.getAttribute('aria-selected') === 'true');
      if (active?.getAttribute('data-value') !== 'Waitlists') return false;

      const valueOf = (id) => {
        const el = document.getElementById(id);
        const raw = el?.selectize ? el.selectize.getValue() : el?.value;
        return (Array.isArray(raw) ? raw : [raw])
          .map((value) => String(value ?? ''))
          .filter(Boolean)
          .sort();
      };
      const same = (actual, expectedValues) =>
        JSON.stringify(actual) === JSON.stringify(expectedValues);
      return valueOf('waitlist-wl_course').includes(scope.course) &&
        valueOf('waitlist-wl_term').includes(scope.term) &&
        valueOf('waitlist-wl_campus').includes(scope.campus) &&
        valueOf('waitlist-wl_college').includes(scope.college) &&
        valueOf('waitlist-wl_pt').includes(scope.pt) &&
        same(valueOf('waitlist-wl_dept'), scope.dept) &&
        same(valueOf('waitlist-wl_level'), scope.level);
    }, {
      timeout: 120000,
      interval: 300,
      args: [{
        ...expected,
        pt: inputPartTerm(expected.pt),
        dept: sourceFilters.dept,
        level: sourceFilters.level,
      }],
    });
    if (!restored) {
      const actual = await page.evaluate(() => {
        const read = (id) => {
          const el = document.getElementById(id);
          return el?.selectize ? el.selectize.getValue() : el?.value ?? null;
        };
        return {
          course: read('waitlist-wl_course'), term: read('waitlist-wl_term'),
          campus: read('waitlist-wl_campus'), college: read('waitlist-wl_college'),
          pt: read('waitlist-wl_pt'), dept: read('waitlist-wl_dept'),
          level: read('waitlist-wl_level'), url: location.href,
        };
      });
      throw new Error(`Waitlists did not restore source scope: ${JSON.stringify(actual)}`);
    }

    await waitForSelector(page, '#waitlist-wl_count .rt-tbody .rt-tr', {
      timeout: 120000,
    });
    const destination = await readReactable(page, 'waitlist-wl_count', { limit: 30 });
    if (destination.error) throw new Error(destination.error);
    const destCols = {
      term: requiredColumn(destination, 'Term'),
      campus: requiredColumn(destination, 'Campus'),
      college: requiredColumn(destination, 'College'),
      course: requiredColumn(destination, 'Course'),
      title: requiredColumn(destination, 'Title'),
      pt: requiredColumn(destination, 'PoT'),
      waiting: requiredColumn(destination, 'Waitlisted'),
    };

    const matching = destination.rows.filter((row) =>
      row[destCols.term] === expected.term &&
      row[destCols.campus] === expected.campus &&
      row[destCols.college] === expected.college &&
      row[destCols.course] === expected.course &&
      row[destCols.title] === expected.title &&
      row[destCols.pt] === expected.pt
    );
    if (matching.length !== 1) {
      throw new Error(
        `expected one matching Waitlists row, found ${matching.length}; ` +
        `source=${JSON.stringify(expected)} destination=${JSON.stringify(destination.rows)}`
      );
    }

    const actualCount = countValue(matching[0][destCols.waiting]);
    if (actualCount !== expected.waiting) {
      throw new Error(
        `waitlist count mismatch for ${expected.course}: ` +
        `Regstats=${expected.waiting}, Waitlists=${actualCount}`
      );
    }
    if (jsErrors.length > 0) throw new Error(`uncaught page errors: ${jsErrors.join(' | ')}`);

    console.log(
      `PASS  Regstats → Waitlists reconciles ${expected.course} ${expected.term} ` +
      `${expected.campus}/${expected.college}/${expected.pt}: ${actualCount}`
    );
  } catch (error) {
    await page.screenshot({ path: '/tmp/cedar-waitlist-reconciliation-failure.png', fullPage: true })
      .catch(() => {});
    throw error;
  } finally {
    await browser.close();
  }
})().catch((error) => {
  console.error('WAITLIST RECONCILIATION ERROR:', error);
  process.exit(1);
});
