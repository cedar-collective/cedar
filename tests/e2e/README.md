# E2E browser checks (dockerized app)

Headless-browser checks that drive the **running** CEDAR app at
`http://localhost:3838/`. They use `puppeteer-core` against the system
Chrome (`/Applications/Google Chrome.app`) — no browser is downloaded.

## One-time setup

```bash
cd tests/e2e && npm install      # installs puppeteer-core only (node_modules is gitignored)
```

## Reproducible dev loop

From the repo root, after editing code:

```bash
./rebuild-and-test.sh                 # rebuild image with current source, restart, wait for app
node tests/e2e/nav.test.mjs           # assert top-nav URL routing behavior (exits non-zero on failure)
node tests/e2e/reports-smoke.test.mjs # drive active report surfaces and wait for populated outputs
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
- **One-offs are throwaway.** Keep ad-hoc check scripts in `tests/e2e/` only while
  iterating (so `node_modules` resolves), then delete them. Promote a check to a
  committed `*.test.mjs` only if it should run again.
