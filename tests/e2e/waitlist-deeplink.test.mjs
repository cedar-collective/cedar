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
    await connect(page, { tab: 'waitlists', search: SEARCH });

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
