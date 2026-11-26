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


## One CEDAR app, one port

**Every browser suite targets `http://localhost:3838/`, and only one CEDAR app
runs at a time.** The synthetic stack (`compose.dev.yml`) and the institutional
one (`docker-compose.yml`) are alternatives that share the port, not neighbours
on 3838 and 3839. Switch surfaces by stopping one and starting the other:

```bash
bash scripts/dev.sh up        # synthetic  (stop the institutional app first)
docker compose up -d --build  # institutional (bash scripts/dev.sh down first)
```

Two reasons, both learned the hard way. The harness defaults to 3838, so a
second port meant every demo run depended on remembering `CEDAR_URL`, and
forgetting it pointed institutional assertions at synthetic records — failures
that read as broken features. And two resident apps is precisely the memory
squeeze described below; sharing the port makes Docker refuse the second one
instead of letting both quietly compete for a 3.83 GB VM.

`run-tests.sh` reads the served page (`#cedar_demo_banner` appears only when
`cedar_demo` is TRUE) to identify which surface answered, and refuses a suite
aimed at the other, naming the commands to switch. It blocks only on positive
evidence: an unreadable page identifies nothing and must not stop a run.
`CEDAR_ALLOW_APP_MODE_MISMATCH=1` overrides deliberately; `CEDAR_DEV_PORT` still
moves the demo for a genuine side-by-side comparison.

## The browser stages are memory-bound, and running out does not look like it

**All twelve browser suites pass.** The long-standing "Headcount failure" and
"Roadblocks/Retention timeouts" were never defects in those features — each
passes on its own in under a minute, and the full 17-step tour passes in ~1m45s.
They were one resource failure wearing three costumes.

The chain, measured 2026-09-05:

1. A full report tour grows the Shiny worker by about **1.3 GB** (2.1 GB → 3.4 GB)
   as it runs seventeen reports in one session.
2. The Docker VM here holds **3.83 GB total**. Leave a second CEDAR container up
   — the synthetic demo stack is the usual one, at ~450 MB — and the worker is
   OOM-killed part way through (`docker inspect <c> --format '{{.State.OOMKilled}}'`
   returned `true`).
3. shiny-server restarts the worker. The browser sees `shiny:disconnected`, and
   **`www/cedar-disconnect.js` — a production feature — reloads the page** every
   10s until it reconnects.
4. That reload destroys the execution context under whatever `page.evaluate()`
   is in flight. Puppeteer reports *"Execution context was destroyed, most
   likely because of a navigation"* against the innocent step that happened to
   be running, and every later step fails as a timeout because the reloaded page
   has none of the state it needs.

So the reported failure names a step chosen by timing, not by fault. `lib.mjs`
now counts app-initiated reloads (`appReloads`, `explainAppReload`) and the
report tour rewrites the error to say the session dropped and why; the guards
are pinned in `harness.test.mjs`. `run-tests.sh` prints a resource check before
the browser stages and names other running CEDAR containers.

**After a failed browser stage the runner says what the app's container
shows.** It notes the container before the first suite and, when a stage
fails, prints what changed:

```
What the app's container says (cedar-shiny):
  - The app's R process is not the one the suites began with (pid 275 then, 3120 now).
    Every session open when it went was dropped, so the step that failed is probably not the cause.
  - Docker reports a process in it killed for memory (OOMKilled: true).
  memory now: cedar-shiny  3.41GiB / 3.83GiB
```

| It reports | From |
|---|---|
| The R process is not the one the suites began with, or none is running | the pid of shiny-server's R process (`pgrep` in the container), before and after |
| The container restarted, or stopped | `docker inspect`'s `StartedAt` against its value before the suites; no container on the app's port |
| A process killed for memory, and whether that was before the suites | `OOMKilled`, before and after |
| A disk nearly full | under 2 GiB free where the checkout is: Docker stops, or answers with input/output errors, as it fills |
| The app answering 500, or not at all | one request to the app |

When none of them holds it says so, which is the case for reading the suite's
own output as a real failure. It explains a failure and never changes one:
the stage still fails, and nothing is retried (`test-ci.R` holds each case).

The same limit decides one setting. The app builds Course Dynamics >
Downstream ahead for the courses analysed most when it starts
([built ahead](shiny-modules.md#downstream-for-the-courses-analysed-most)),
which leaves the worker larger before a suite has opened a page: measured
2026-11-25, seven suites in a row peaked at 3.42 GB with no course built ahead,
and the worker was killed once with two built ahead. A development machine
therefore sets `CEDAR_PRELOAD_COURSES=0` in its `.env` (`.env.example` has the
line); production, on 8 GB, builds ten. A restart is also ready sooner.

**Before diagnosing any browser failure:** confirm the app source is current
(`docker compose up -d --build`) and that nothing else large is resident. A
stale container produced a completely separate phantom — Dept Trends "rendered
hidden charts" purely because the image predated the fix.

## A process just started

Every browser run but one meets a process already in use: the app was started
some time ago and a warm-up session has been through it. What a process does
for its first readers was therefore tested by nobody until a deploy, and two
things lived there unseen: R compiled the server function while the second
session waited (ISSUES I81), and the test driver itself lost an input on that
session (I85).

```bash
./run-tests.sh --e2e --fresh     # restart the running app, then its first sessions
./run-tests.sh --all --fresh     # the same on a rebuilt container
```

`--fresh` restarts whichever container answers on the app's port (the
institutional stack, the synthetic one or a one-off test container), waits for
the build-ahead's last job in its log (`[preload] 5 of 5: …`: a session opened
before then waits behind the job running, and a time taken then is the job's),
leaves out the warm-up, and runs `fresh-start.test.mjs` as the process's first
six sessions. A suite named with it runs afterwards. **A restart runs the
source the container was built with**, so the form that tests a diff is
`--all --fresh`; `--changed` says so when `global.R` or `entrypoint.sh` is in
the diff. The wait is 15 minutes at most (`CEDAR_BUILD_AHEAD_TIMEOUT`, in
seconds).

The suite holds two things for each of the first two sessions:

- **An input set the moment `connect()` returns is still set once the page is
  idle** (I85).
- **The server begins as soon after the connection as it does for the four
  sessions after**, give or take a second. R compiles a function before
  running it, so a session that meets the server function uncompiled waits
  for the compiler in exactly this stretch.

Measured 2026-11-25 in the development container (emulated), seconds:

| | Session 1 | Session 2 | Sessions 3 to 6 |
|---|---|---|---|
| Connection to the server beginning, before | 0.4 | 2.8 | 0.1 to 0.2 |
| Connection to the server beginning, after | 0.2 to 0.3 | 0.2 | 0.1 to 0.2 |
| Whole start, before | 6.1 to 7.6 | 6.7 to 8.1 | 4.2 to 6.2 |
| Whole start, after | 6.1 to 6.5 | 4.5 | 4.2 to 5.7 |

"After" is with the server function compiled at start: `global.R` compiles the
function it read (`cedar_compile_server()`, 2 of the 6.3 seconds the start now
spends compiling) and `server.R`'s last line hands it to Shiny
(`cedar_server_to_run()`), because Shiny reads `server.R` itself for the
first session and runs what that read returns. An edited `server.R` is run as
edited.

The whole start is printed and not held. Sessions after the second differ by
a second and a half among themselves, about one in four taking that much
longer, which is as much as the first session still adds (ISSUES M75);
compiling every function at start cost 33 seconds and changed neither. Run it
alone: a second heavy job on the machine moves every number. What it prints
is kept, and shown beside the last run on other code
([what is held, and what is only printed](performance-monitoring.html#what-is-held-and-what-is-only-printed)).

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

`test-architecture.R` counts the `sleep()` calls in every script here but
`lib.mjs`, whose job waiting is. The count may only go down: two are left, a
poll with a timeout in `nav.test.mjs` and a beat before a screenshot in
`shot.mjs`.

**2. `connect()` must settle before you touch inputs.** `isConnected()` goes true
well before the landing tab's first reactive flush. Inputs set inside that window
are overwritten by the app's own initialisation — the symptom is a selectize
still reading "Type to search..." after `setInput`, a page stuck on its empty
state, and a toast claiming the analysis ran. `connect()` waits for the
session's first busy-to-idle cycle, and then for idle.

*A quiet page is not a started session.* Waiting for idle alone was not
enough on a process just started: R compiles the server function as its second
session starts, and the page shows no busy state until that is done. Measured
2026-11-25 on the session straight after the warm-up: connected at 0.5 s, busy
at 3.7 s, the course picker's choices at 5.7 s. "Connected, then quiet for 600
ms" passed at 3.6 s, the test set a course, and the picker's set-up then
emptied it (ISSUES I85: four of four such sessions; none of three with the
wait). A page that looks empty right after a restart: read
`Shiny.shinyapp.$inputValues` for the input the test set before reading the
page.

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

