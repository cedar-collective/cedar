// Waitlists deep-link regression.
// Exercises the shared controller through a Shiny module and server-side selectize.
import {
  launch, connect, waitFor,
} from './lib.mjs';

const COURSE = process.env.CEDAR_SMOKE_COURSE || 'CHEM 1215L';
const SEARCH = [
  'tab=waitlists',
  'autorun=true',
  'campus=ABQ,EA',
  `course=${encodeURIComponent(COURSE)}`,
].join('&');

(async () => {
  const { browser, page, jsErrors } = await launch();

  try {
    // What the overlay says once the page is there and before Shiny connects,
    // read after the page's own DOM-ready handlers have run. An autorun link
    // opens it from the <head> script; it said a bare "Loading…" until it
    // closed, with no estimate and no running count (ISSUES I83).
    await page.evaluateOnNewDocument(() => {
      document.addEventListener('DOMContentLoaded', () => setTimeout(() => {
        const box = document.getElementById('waitlist-loading-overlay');
        window.__overlayAtReady = {
          shown: !!box && box.style.display !== 'none',
          label: document.getElementById('waitlist-loading-label')?.textContent ?? null,
        };
      }, 0));
    });
    await connect(page, { tab: 'waitlists', search: SEARCH });

    const atReady = await page.evaluate(() => window.__overlayAtReady ?? null);
    if (!atReady?.shown) throw new Error(`Waitlists deep link did not open its loading overlay at once: ${JSON.stringify(atReady)}`);
    if (!/~\d+/.test(atReady.label ?? '')) {
      throw new Error(`Waitlists deep-link overlay gives no estimate before Shiny connects: "${atReady.label}"`);
    }

    const restored = await waitFor(page, (expectedCourse) => {
      const course = document.getElementById('waitlist-wl_course');
      const campus = document.getElementById('waitlist-wl_campus');
      if (!course?.selectize || !campus?.selectize) return false;
      const rawCourses = course.selectize.getValue();
      const courses = Array.isArray(rawCourses) ? rawCourses : [rawCourses];
      const rawCampuses = campus.selectize.getValue();
      const campuses = Array.isArray(rawCampuses) ? rawCampuses : [rawCampuses];
      return courses.length === 1 && courses.includes(expectedCourse) &&
        campuses.length === 2 && campuses.includes('ABQ') && campuses.includes('EA');
    }, { timeout: 30000, interval: 250, args: [COURSE] });
    if (!restored) {
      const actual = await page.evaluate(() => {
        const course = document.getElementById('waitlist-wl_course');
        const campus = document.getElementById('waitlist-wl_campus');
        return {
          course: course?.selectize?.getValue() ?? null,
          campus: campus?.selectize?.getValue() ?? null,
          linkBootstrap: Shiny?.shinyapp?.$inputValues?.cedar_link_bootstrap ?? null,
          url: window.location.href,
        };
      });
      throw new Error(`Waitlists deep-link filters were not restored: ${JSON.stringify(actual)}`);
    }

    const rendered = await waitFor(page, () => {
      const output = document.getElementById('waitlist-wl_output');
      return output?.innerText.includes('Course Overview') &&
        !output.innerText.includes('Select a course or term');
    }, { timeout: 120000, interval: 500 });
    if (!rendered) throw new Error('Waitlists deep link did not run its ordinary report path');

    const overlayCleared = await waitFor(page, () => {
      const overlay = document.getElementById('waitlist-loading-overlay');
      return !!overlay && getComputedStyle(overlay).display === 'none';
    }, { timeout: 30000, interval: 250 });
    if (!overlayCleared) throw new Error('Waitlists loading overlay did not clear');
    if (jsErrors.length > 0) throw new Error(`uncaught page errors: ${jsErrors.join(' | ')}`);

    console.log(`PASS  Waitlists deep link autoruns: ${COURSE}`);
  } catch (error) {
    await page.screenshot({ path: '/tmp/cedar-waitlist-deeplink-failure.png' })
      .catch(() => {});
    throw error;
  } finally {
    await browser.close();
  }
})().catch((error) => {
  console.error('WAITLIST DEEP-LINK ERROR:', error);
  process.exit(1);
});
