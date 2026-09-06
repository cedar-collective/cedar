---
title: E2E and Browser Testing
parent: Developer Guide
nav_order: 27
---

# E2E and Browser Testing

Driving the running app with headless Chrome: the four traps that cause every flake, the screenshot and assertion helpers, and one-time setup. The committed suites live in `tests/e2e/`.

## Looking at the app

```bash
node tests/e2e/shot.mjs <tab-slug>     # screenshot a tab -> /tmp/cedar-<tab>.png  (~12s)
node tests/e2e/nav.test.mjs            # assert top-nav routing; exit code = pass/fail
```

Read the resulting PNG directly — that is the visual inspection step, and it is
the only way to catch a colour, spacing, or layout regression.

To assert on rendered content rather than eyeball it, write a short script **in
`tests/e2e/`** (not `/tmp` — the imports are relative to that directory) using
the helpers in `lib.mjs`: `launch`, `connect`, `clickSubTab`, `setInput`,
`click`, `waitForSelector`, `readReactable`, `colIndex`. Delete it when done.
The harness now enforces the three traps that used to cost the most time —
each throws with an actionable message instead of returning a confident wrong
answer. `node tests/e2e/harness.test.mjs` guards them.

- **`connect(page, { tab: 'gen-ed' })` takes options, not a URL.** Passing a URL
  string throws. It used to leave `tab` at its `'home'` default (a string has no
  `.tab`), so assertions described the Home page and it looked like routing was
  broken app-wide.
- **`connect()` verifies where it landed.** A slug that ends up on Home throws
  and names the likely cause. Pass `expect: 'Gen Ed'` to assert the exact tab,
  or a longer `settle:` for a slow one. It returns the tab it landed on.
- **Scope queries to the visible tab.** Every tab's markup is in the DOM at
  once. Use `queryActive(page, sel)` and `activeText(page)` rather than a raw
  `$$eval` — on Gen Ed that is 6 labels instead of 136 — and never slice a raw
  result for readability, which is how a control that was present nearly got
  reported missing. `clickSubTab()` now refuses a sub-tab belonging to another
  tab and lists the visible ones.
- **Module inputs are namespaced**: the id is `gen_ed-ge_button`, not
  `ge_button`. `click(page, id)` throws on a missing id, so prefer it over
  finding a button by its visible text.


## E2E rules — the four that cause every flake

Written after a session lost hours to all four. `tests/e2e/lib.mjs` now solves
each one; use the helper instead of re-deriving it.

**1. Never `sleep()` to wait for Shiny. Use `waitForIdle()` / `runAndWait()`.**
Shiny publishes its own state: `shiny-busy` on `<html>`, `recalculating` on each
output. A fixed sleep races the app, and "wait for non-empty text" passes
*instantly on the previous run's output* — that is how a scope bar read "629
students analyzed" for a run that produced 401.

*The trap the helper exists for:* outputs on hidden tabs are suspended and keep
`recalculating` forever, so counting every `.recalculating` in the DOM never
reaches zero. Only **visible** ones count.

**2. `connect()` must settle before you touch inputs.** `isConnected()` goes true
well before the landing tab's first reactive flush. Inputs set inside that window
are overwritten by the app's own initialisation — the symptom is a selectize
still reading "Type to search..." after `setInput`, a page stuck on its empty
state, and a toast claiming the analysis ran. `connect()` now waits for idle.

**3. `offsetParent !== null` is not a visibility test.** It also returns null
inside `position: fixed`/`sticky` ancestors, which in bslib includes the sub-tab
bars — so `clickSubTab()` reported "Visible sub-tabs: (none)" on a page showing
seven of them, and tests grew their own hand-rolled tab clickers in response. Use
`Element.checkVisibility()`; `lib.mjs` injects one shared definition.

**4. Selectors rot silently. Run `node tests/e2e/check-ids.mjs`.** Four ids in
`reports-smoke` had rotted unnoticed: two sat inside a `.some()` and passed while
testing nothing, two failed as timeouts that looked like broken Core Surfaces.
The checker runs in seconds and names the likely replacement. It is stage 1 of
`run-tests.sh` for that reason. For a string a test asserts is *absent*, declare
it: `// check-ids-ignore: inst_gpa, overall_credits_earned`.

Also: `openSubTab()` clicks, waits for the pane to be visible, and waits for
idle — `clickSubTab()` alone only fires the click, and `innerText` on a
still-hidden pane returns `''`, which is indistinguishable from a tab that
rendered nothing.

## E2E / browser testing — setup and reference

The when/what/cost of the browser environment is in *The three environments*
above; this is the setup and the sharp edges.

One-time setup (`node_modules` is gitignored):

```bash
cd tests/e2e && npm install
```

The harness uses `puppeteer-core` against system Chrome — no browser download
and no extension needed. Override defaults with `CEDAR_URL` and `CHROME_PATH`.

`node tests/e2e/harness.test.mjs` checks the harness guards themselves; run it
if you change `lib.mjs`.

`tests/e2e/README.md` → "Driving inputs and reading output back" has a
copy-paste recipe for setting a filter, clicking run, and reading the rendered
table, plus the gotchas that cost the most time: namespaced module input ids,
server-side selectize choices, `suspendWhenHidden` sub-tabs, and reactable DOM
selectors with uppercased headers.

Notes:
- The app serves at `http://localhost:3838/`. Data is mounted from
  `CEDAR_DATA_DIR` (`.env`); source is **not** mounted — see the rebuild note
  above.
- The first connection after a restart runs `global.R` (heavy data load), so
  that request is slow. The scripts wait for it.
- If `docker compose up --build` fails with a blob "input/output error", the
  Docker store is out of disk: `docker compose down && docker builder prune -af`,
  then rebuild.

