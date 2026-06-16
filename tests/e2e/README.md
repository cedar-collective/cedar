# E2E browser checks (dockerized app)

Headless-browser checks that drive the **running** CEDAR app at
`http://localhost:3838/cedar/`. They use `puppeteer-core` against the system
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
node tests/e2e/shot.mjs pathways      # screenshot a tab → /tmp/cedar-pathways.png for visual inspection
```

Only the `COPY . .` layer of `Dockerfile.shiny` re-runs on a code change (the
R-package layer caches), so rebuilds after the first cold build are fast.

Override the target with `CEDAR_URL=... node tests/e2e/nav.test.mjs`.

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
`course-dynamics`, `healthcare`, `data-usage`.
