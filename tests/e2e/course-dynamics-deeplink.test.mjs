// Course Dynamics deep-link regression.
// Verifies the browser -> ordered restore -> shared server run-trigger path.
import {
  launch, connect, waitFor, waitForSelector,
} from './lib.mjs';

const COURSE = process.env.CEDAR_SMOKE_COURSE || 'CHEM 1215L';
const SEARCH = [
  'tab=course-dynamics',
  'autorun=true',
  'campus=ABQ,EA',
  `course=${encodeURIComponent(COURSE)}`,
].join('&');

(async () => {
  const { browser, page, jsErrors } = await launch();

  try {
    await connect(page, { tab: 'course-dynamics', search: SEARCH });

    const restored = await waitFor(page, (expectedCourse) => {
      const course = document.getElementById('cr_course');
      const campus = document.getElementById('cr_campus');
      if (!course?.selectize || !campus?.selectize) return false;
      const rawCampuses = campus.selectize.getValue();
      const campuses = Array.isArray(rawCampuses) ? rawCampuses : [rawCampuses];
      return course.selectize.getValue() === expectedCourse &&
        campuses.length === 2 &&
        campuses.includes('ABQ') && campuses.includes('EA');
    }, { timeout: 30000, interval: 250, args: [COURSE] });
    if (!restored) {
      const actual = await page.evaluate(() => {
        const course = document.getElementById('cr_course');
        const campus = document.getElementById('cr_campus');
        return {
          course: course?.selectize?.getValue() ?? null,
          campus: campus?.selectize?.getValue() ?? null,
          linkBootstrap: Shiny?.shinyapp?.$inputValues?.cedar_link_bootstrap ?? null,
          url: window.location.href,
        };
      });
      throw new Error(`deep-link filters were not restored: ${JSON.stringify(actual)}`);
    }

    const linkBootstrapped = await waitFor(page, () =>
      !!Shiny?.shinyapp?.$inputValues?.cedar_link_bootstrap?.search,
    { timeout: 30000, interval: 250 });
    if (!linkBootstrapped) throw new Error('browser link controller never bootstrapped');

    await waitForSelector(page, '#cr_overview_metrics .stat-card', { timeout: 120000 });
    await waitForSelector(page,
      '#cr_overview_enrollment_plot.js-plotly-plot, #cr_overview_enrollment_plot .js-plotly-plot',
      { timeout: 120000 });
    await waitForSelector(page,
      '#cr_overview_sections_plot.js-plotly-plot, #cr_overview_sections_plot .js-plotly-plot',
      { timeout: 120000 });
    await waitForSelector(page,
      '#cr_overview_avg_size_plot.js-plotly-plot, #cr_overview_avg_size_plot .js-plotly-plot',
      { timeout: 120000 });

    const overlayCleared = await waitFor(page, () => {
      const overlay = document.getElementById('cr-loading-overlay');
      return !!overlay && getComputedStyle(overlay).display === 'none';
    }, { timeout: 30000, interval: 250 });
    if (!overlayCleared) throw new Error('Course Dynamics loading overlay did not clear');
    if (jsErrors.length > 0) throw new Error(`uncaught page errors: ${jsErrors.join(' | ')}`);

    console.log(`PASS  Course Dynamics deep link autoruns: ${COURSE}`);
  } catch (error) {
    await page.screenshot({ path: '/tmp/cedar-course-dynamics-deeplink-failure.png' })
      .catch(() => {});
    throw error;
  } finally {
    await browser.close();
  }
})().catch((error) => {
  console.error('COURSE DYNAMICS DEEP-LINK ERROR:', error);
  process.exit(1);
});
