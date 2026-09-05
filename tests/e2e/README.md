# E2E browser checks (dockerized app)

Headless-browser checks that drive the **running** CEDAR app at
`http://localhost:3838/`. They use `puppeteer-core` against the system
Chrome (`/Applications/Google Chrome.app`) — no browser is downloaded.

## One-time setup

```bash
cd tests/e2e && npm install      # installs puppeteer-core only (node_modules is gitignored)
```

## Standard browser gate

`./run-tests.sh --all admin` rebuilds the local app and verifies that the
freshness table exists with JavaScript disabled, appears on Admin navigation
while offline, and that the deferred usage/projection panels still initialize.
It saves `/tmp/cedar-admin-freshness.png` for visual review.

From the repository root:

```bash
./run-tests.sh --e2e       # short smoke against the current app
./run-tests.sh --all       # rebuild the app, then run every browser suite
./run-tests.sh --e2e nav   # one named committed suite during iteration
node tests/e2e/shot.mjs pathways      # screenshot a tab → /tmp/cedar-pathways.png for visual inspection
```

Only the `COPY . .` layer of `Dockerfile.shiny` re-runs on a code change (the
R-package layer caches), so rebuilds after the first cold build are fast.

Override the target with `CEDAR_URL=... node tests/e2e/nav.test.mjs`.
Override the browser with `CHROME_PATH=/path/to/chrome` when the default macOS
Chrome path is not right.

If Chrome cannot launch, the harness exits with an `E2E browser setup failed`
message before touching the app. In managed/sandboxed environments that usually
means browser/GUI launch was not allowed for that run; retry with that permission
before treating the result as an app failure.

`reports-smoke.test.mjs` also accepts:

```bash
CEDAR_SMOKE_DEPT=HIST CEDAR_SMOKE_COURSE="HIST 1110" CEDAR_SMOKE_TERM=202680 node tests/e2e/reports-smoke.test.mjs
```

It checks operations only: set filters, click the report action, and verify that
an expected table, plot, or populated UI region appears. It does not assert
specific analytic values.

`waitlist-reconciliation.test.mjs` selects a real High Waitlists row in Regstats,
follows its linked count, and asserts that Waitlists restores the same course,
term, campus, college, part-of-term, department, and level scope and reproduces
the count, even when stale Waitlists filters existed before the jump. Override
the configured term or display floor with `CEDAR_RECON_TERM` and
`CEDAR_RECON_MIN_WAIT` when needed.

`enrollment-projections.test.mjs` opens the read-only Registration > Projections page,
verifies the saved-artifact filters and audit columns, and checks the row-level
history and six candidate methods. Run it alone with
`./run-tests.sh --e2e enrollment-projections`.

## Scope and failures

Default smoke runs Enrollment and Course Dynamics only. Use `--e2e reports`
for the full 16-scenario institutional report tour, or `--e2e dept-trends`,
`--e2e roadblocks`, `--e2e retention`, and `--e2e headcount` for focused checks.
`--all` still rebuilds and runs all institutional suites. `--all smoke` rebuilds
and checks only smoke. The `credit-timeline` suite also checks truncation
exclusions using its existing population; there is no separate truncation run.

Suites stop at the first failure without automatic retries. After diagnosis,
rerun the relevant committed script; do not repeat a successful R gate unless
code changed. Browser scripts are read from the host, so editing only those
scripts does not require rebuilding application source. Report durations as
observations, not evidence that a timeout is an application defect.

## What `nav.test.mjs` covers

- Bare URL is stamped with `?tab=home` once Shiny connects.
- Clicking a top-level tab pushes `?tab=<slug>` (pushState writer in `ui.R`).
- Browser **Back** re-activates the previous tab (popstate handler).
- Regstats → Waitlists cross-navigation (the waitlist count link's mechanism)
  lands on `?tab=waitlists`, and **Back** returns to Regstats — the round trip
  requested for the high-waitlist link.
- No uncaught JS errors on the page.

## What `shot.mjs` does

`node tests/e2e/shot.mjs <tab-slug> [out.png]` loads `?tab=<slug>`, waits for the
app to connect and render, and writes a PNG (default `/tmp/cedar-<slug>.png`).
Slugs: `home`, `dept-dashboard`, `dept-trends`, `enrollment`, `registration`,
`pathways`, `open-seats`, `cancellations`, `waitlists`, `gen-ed`, `headcount`,
`course-dynamics`, `data-usage`.

`shot.mjs` only **loads** a tab. Most tables are empty until you set filters and
click a "gather"/"run" button, so for anything beyond the landing state you drive
the inputs yourself — see below.

## Driving inputs and reading output back

`lib.mjs` has the reusable pieces so you don't re-derive them each time. Import
it and follow this shape — set inputs → click the button → wait for the output →
read it (or `page.screenshot()`):

```js
// tests/e2e/my-check.mjs   →   run with:  node tests/e2e/my-check.mjs
import { launch, connect, setInput, click, clickSubTab,
         waitForSelector, readReactable, colIndex, sleep } from './lib.mjs';

const { browser, page, jsErrors } = await launch();
await connect(page, { tab: 'enrollment' });          // waits for Shiny (first load runs global.R)

// 1. Set inputs by their FULL id (include the module namespace) and fire the query.
await setInput(page, 'enrl_dept', 'HIST');
await click(page, 'enrl_button');                    // the "Gather Enrollments" actionButton

// 2. Wait for the output to render, then read it back.
await waitForSelector(page, '#enrl_summary .rt-tbody .rt-tr');
const { headers, rows } = await readReactable(page, 'enrl_summary');
const c = colIndex(headers, 'course'), t = colIndex(headers, 'term');
rows.forEach((r) => console.log(r[c], '|', r[t]));   // inspect Course | Term order

console.log('jsErrors:', jsErrors);                  // assert this is empty
await browser.close();
```

### The gotchas these helpers encode

- **Find input/button ids in the source, not by guessing.** They're the first arg
  to `selectInput`/`actionButton`/etc. Module inputs are namespaced: an input
  defined with `ns("dept_code")` inside `populationSelectorServer("population", …)`
  mounted under `pathwaysUI("pathways", …)` has the full id
  `pathways-population-dept_code`. `grep -n 'ns("' R/modules/<mod>.R` lists them.
- **`setInput` works regardless of dropdown choices.** Selectize choices are often
  loaded server-side (`choices = c()` then `updateSelectizeInput`), but
  `Shiny.setInputValue` sets the value directly — no need to wait for choices.
- **Sub-tab outputs don't compute until the sub-tab is visible** (they're
  `suspendWhenHidden` by default). Use `clickSubTab(page, 'Major Changes')` to
  trigger an auto-running tab, then `waitForSelector` on one of its outputs.
- **Reactable DOM:** container is `#<outputId>`, headers are `.rt-th`, rows are
  `.rt-tbody .rt-tr`, cells `.rt-td`. Header text comes back **UPPERCASED** (CSS
  `text-transform` shows through `innerText`) — match columns with `colIndex()`,
  which is case-insensitive.
- **Do not create one-off browser scripts.** Extend a committed `*.test.mjs` and
  run it through `./run-tests.sh --e2e <suite-name>`. The standard gate verifies
  that every committed browser suite is included in the release run.

## Synthetic development acceptance

After `bash scripts/dev.sh up`, run
`CEDAR_URL=http://localhost:3839/ ./run-tests.sh --e2e demo`.
This registered suite requires the synthetic banner, loaded freshness table,
and the known MATH/CS 375 crosslist totals and historical plot. It is explicit
because the default release suites use institution-specific courses. Requires
the usual host Chrome/Node setup; the Docker-only contributor test command runs
the selector and R gate, not browser suites.

The PR workflow runs this same demo suite on a hosted runner without production
credentials. `run-tests.sh --test-image <built-image> --e2e demo` runs the full
R suite inside Docker while retaining host Chrome/Node for the browser stage;
set `CEDAR_URL` to the demo instance. See the developer Testing guide for the
complete build/start/test commands. The real-data Gen Ed graduate suite uses
the shared Shiny-idle and visible-subtab helpers, and captures selected scope,
notifications, and a screenshot if it fails.
