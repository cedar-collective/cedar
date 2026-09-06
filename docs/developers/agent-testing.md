---
title: Testing for Agents
parent: Developer Guide
nav_order: 29
---

# Testing for Agents

The complete test-infrastructure reference, moved out of `AGENTS.md` so it does not sit in every context window. `AGENTS.md` keeps the hard rules and the command table; everything else — fixture conventions, the three environments, the per-change blast-radius table, module loading, ad-hoc workflows — is here. See also [testing.md](testing.md) for philosophy and [e2e-testing.md](e2e-testing.md) for the browser harness.

# Test Infrastructure

All test data is hand-crafted tribbles in `tests/testthat/fixtures/designed_test_data.R` — that single file IS the test database and the source of truth. `setup.R` sources it and exposes the tables as `test_sections`, `test_sections_sf` (seatfinder-specific 2024/2025 terms), `test_students`, `test_programs`, `test_degrees`, `test_faculty`, plus `test_lookups` and a `data_objects` list. Every expected value is traceable to explicit rows in that file — no sampling, no binary fixtures, no regeneration step.

**Pinned counts:** the header of `designed_test_data.R` is a large comment block of expected values (row counts by dept/term/campus/status/level, crosslist scenario summaries, regstats design values, etc.) that test files hard-code against. When you add or change rows, update the pinned counts in that header AND the hard-coded expected values in affected test files, in the same change.

**Stable terms:** 202010, 202060, 202080, 202110 (Spring/Summer/Fall 2020, Spring 2021). `test_sections_sf` additionally uses 2024/2025 terms for seatfinder tests.

**Departments:** sections/students center on HIST, MATH, ANTH, NURS, with variety rows in PSYC, BIOL, MGMT, ENGL, POLS, AMST. `test_faculty` covers HIST, MATH, ANTH, PSYC, BIOL, NURS, MGMT, ENGL, POLS — MGMT and POLS have only Term Teacher rows, so they are excluded from permanent-faculty counts.

**Adding an edge case:** add rows directly in the relevant table's section of `designed_test_data.R`, following the established naming conventions:
- **EC-xx** — numbered edge cases (e.g., EC-04..EC-06 are the combined C-suffix course patterns). Continue the sequence from the highest existing number. The numbering began in the legacy `create-test-fixtures.R` (EC-01..03), so do not reuse those numbers.
- **XLxx** — crosslist/split scenarios (XL01..XL06).
- **SVARxx** — section variety rows (unusual statuses, NA fields).

Document the new rows and their expected values in the pinned-counts header, then update hard-coded expectations in affected tests.

**Schema drift:** there is no regeneration script and no separate drift check — test failures are the signal. If `transform-to-cedar.R` renames, removes, or adds a column that code under test depends on, mirror the change in `designed_test_data.R` (the authoritative schema source is `transform-to-cedar.R`).

**Legacy pipeline (do not use):** `tests/testthat/create-test-fixtures.R` previously sampled real CEDAR data into binary `cedar_*_test.qs` fixture files. Nothing loads those anymore — the script is kept only as the documented recipe for drawing a stratified real-data sample, should that ever be revived. Never add fixture rows or edge cases there; they will not be seen by any test.

**Rules:**
- Test expected values are hard-coded from running functions against fixtures, then committed. If a value changes, it means the function or fixture changed — investigate before updating.
- `uel=FALSE` in filter tests: the `uel=TRUE` default applies the `excluded_courses` list and mutates `subject_course`. Filter logic tests should use `make_opt(uel = FALSE)` to isolate from this behavior.
- If required columns are missing from fixtures, add them to `designed_test_data.R` matching the schema in `transform-to-cedar.R`. Do not add fallback logic in tests or fixtures.
- **Domain data belongs in `designed_test_data.R`; one function's input contract does not.** The failure this rule exists to prevent is a test that passes because the fixture *cannot express the bug* — not the mere presence of a tibble in a test file. Ask: **does this case describe a property of real data that other analytics also need?**

  **Yes → put it in `fixtures/designed_test_data.R`.** Raw enrollment, section, program, or degree rows. Multi-campus delivery, waitlisted students, crosslists, repeat enrolments — these are facts about how UNM data looks, and every analytic that touches them needs the same shape. Building them locally guarantees the next test re-invents them, and guarantees the shared fixture keeps producing vacuous passes. Worked example: `cedar_students` was 100% ABQ, so every campus-grouping test written against it asserted nothing; MC01–MC03 fixed that and the tests only became real once they moved.

  **No → build it locally, at the top of the file, with its expected values documented directly above.** Legitimate cases, all present in the suite today:
  - **Intermediate frames.** `compute_stopout_for_group()` takes a pre-joined frame with `outcome` and `stopped_out` already derived. That shape is one function's contract, not domain data; putting it in the shared fixture would dress a made-up intermediate up as real data.
  - **Expected-value tables.** The table you assert *against*.
  - **Test scaffolding.** `test-data-loading.R` writes temp `.Rds` files to exercise the loader.
  - **Scenarios needing terms outside the fixture's stable set.** The relative-term sequences in `test-pathway.R` and the data-boundary rows in `test-population.R` depend on term spacing the shared fixture deliberately does not have. `test-pathway.R` documents this in its header — follow that pattern and say why.

  When in doubt, the tell is reusability: if a second test file would want the same rows, it is domain data.

  **The reasoning is written up for humans in `docs/developers/testing.md` → "What belongs in the shared fixture, and what doesn't".** Short version: none of CEDAR's test data is real — it is all hand-written, deliberately, because sampled binary fixtures were opaque. So the question is never *is this data real?* but *does this data have a real-world counterpart it has to be faithful to?* Boundary tables (`cedar_students`, `cedar_sections`, …) do, and must keep looking like the institution. A frame that only exists mid-pipeline does not, and belongs beside the test that defines it. Keep the two documents in step if either changes.
- **Never write throwaway/scratch tests, and don't fragment the code or fixtures just to make something testable.** When you add or change behavior, expand the *real* suite that exercises it against the *real* fixtures — don't spin up a temporary `test-tmp-*.R`, a one-off inline scenario, or a helper extracted solely so a unit test can reach it, then delete it. If the fixtures can't yet represent the case (e.g. they had no waitlisted students because the status-code→text map only knew `RE`), fix the fixtures so they mirror actual data — that is the trivial, correct path, and it makes the case reusable. Concretely: the waitlist supply columns are covered by real NURS 2010 202080 waitlist rows in `designed_test_data.R` + assertions in `test-waitlist.R`, not by an isolated helper or a scratch file.

## Running tests

### Standard Testing Procedure

**Hard rule for agents: NEVER WRITE CUSTOM TESTING SCRIPTS.** Do not create
temporary runners, one-off browser scripts, local shell wrappers, copied e2e
variants, Python probes, R scratch tests, or bespoke "smoke" commands to verify
CEDAR. They become a second, untrusted test system and waste release time.

The only allowed test entry points are the committed gates below, focused
`testthat::test_file()` / `test_dir()` calls against committed test files, and
the committed scripts already in `tests/e2e/`. If a case is worth testing, add
or update a real committed test in `tests/testthat/` or `tests/e2e/` and run it
through the standard harness. If a custom diagnostic is genuinely needed for
exploration, keep it in the session scratchpad, never in the repo, and do not
present it as release verification.

Follow this procedure exactly:

1. **Before testing:** start from the host repo root.

   ```bash
   cd /Users/fwgibbs/Dropbox/projects/cedar-project/cedar
   ```

2. **During a tight edit loop:** run only the focused committed test file or
   filter that covers the touched behavior.

   ```bash
   Rscript --vanilla -e "testthat::test_file('tests/testthat/test-<name>.R')"
   Rscript --vanilla -e "testthat::test_dir('tests/testthat', filter='<name|area>')"
   ```

   This is an iteration tool, not release evidence.

3. **Before saying a code change is done:** run the standard gate.

   ```bash
   ./run-tests.sh
   ```

   This is mandatory for non-trivial code changes. It runs the e2e selector
   check first, then the full R suite.

4. **For UI, routing, module wiring, browser behavior, screenshots, or anything
   that depends on Shiny rendering:** run the browser gate through the standard
   entrypoint.

   ```bash
   ./run-tests.sh --e2e smoke
   ./run-tests.sh --e2e <suite-name>
   ```

   The app must already answer on `http://localhost:3838/`.

5. **For release candidates, pre-merge release branches, Docker/source changes,
   or after changing R/Shiny source that the running container may not have
   loaded:** run the release gate.

   ```bash
   ./run-tests.sh --all
   ```

   This rebuilds the container from the current working tree, waits for the app,
   and then runs the browser suites. `./run-tests.sh --all smoke` is allowed for
   a broad smoke check, but it is not the final release gate.

6. **When reporting results:** name the exact command, pass/fail counts, known
   skips, whether Chrome/app setup succeeded, and whether the app image was
   rebuilt. If a browser run fails before Chrome launches, report it as setup
   failure, not app failure. If a browser run used an old running container,
   say it is not release evidence.

Quick command reference:

```bash
./run-tests.sh          # selector check + R suite      ~40s, no app needed
./run-tests.sh --e2e    # + browser suites              ~10min, app must be up
./run-tests.sh --all    # + rebuild the container first
./run-tests.sh --e2e reports-smoke     # one named suite
```

Stages run cheapest-first on purpose. Jumping straight to the browser to "just
check the app" is the expensive mistake: a stale selector and a logic regression
both present there as an ambiguous timeout that reads like a broken feature.

### The two paths that cost an hour every time they are forgotten

| Where | Path | Applies to |
|---|---|---|
| **Host** | `/Users/fwgibbs/Dropbox/projects/cedar-project/cedar` | everything you run locally — `run-tests.sh`, `Rscript`, `node tests/e2e/*` |
| **Inside the container** | `/srv/shiny-server/cedar` | any `docker compose exec` |

`cd` to the host path first, always: `setup.R`, `load_funcs()`, the fixtures and
every e2e helper resolve relative to it. Inside the container the app is **not**
at `/srv/shiny-server` — that is the stock Shiny sample directory, and running
there gives `No test files found`, which reads like a broken image rather than a
wrong `-w`:

```bash
docker compose exec -T -w /srv/shiny-server/cedar cedar-shiny Rscript -e '...'
```

### `--vanilla` is required, and renv is not the answer

Cedar is a **Shiny app, not an R package**. `devtools::test()`, `pkgload::load_all()`, `library(cedar)`, and `testthat::test_local()` all fail — there is no `DESCRIPTION` file. Use `testthat::test_file()` / `test_dir()`, and always:

```bash
Rscript --vanilla -e 'testthat::test_dir("tests/testthat")'
```

`--vanilla` skips `.Rprofile`, which otherwise activates renv. The system library
has everything the suite needs, and the run takes ~35s.

**Never run `renv::deactivate()` to fix a library error.** It rewrites
`.Rprofile` as a side effect — commenting out every `source("renv/activate.R")`
— and that edit is easy to sweep into an unrelated commit, silently disabling
renv activation for the whole project. This has already happened once (commit
`e4237fd`, reverted). If `Rscript` reports a missing package, you almost
certainly omitted `--vanilla`, or you named the wrong package: the data files are
**qs2**, not qs, and `qs::qread()` fails with the unhelpful "QS format not
detected".

### Ad-hoc checks against real data

Do not hand-roll the bootstrap; it has four separate gotchas. Source the helper:

```bash
Rscript --vanilla -e 'source("scripts/cedar-repl.R"); nrow(cedar_students)'
```

It sets `cedar_base_dir` and `cedar_data_dir` (both required globals with no
defaults), loads the CEDAR functions, and lazily exposes the cedar tables.
For method development, keep a vanilla R process alive, source this helper once,
materialize only the required tables, and re-source changed branch/cone files
without reloading the data. The full workflow, evidence boundaries, invalidation
rules, and projection example are in `docs/developers/testing.md` under
**Computational Prototyping Without Shiny**.

### Text-first feature previews

For a computation-heavy feature, stabilize a canonical non-Shiny text preview
before building or revising its Shiny surface. The preview must be a committed
production formatter over the feature payload or validated saved artifact, not
a scratch script and not a second implementation of the analysis. It should
show the scope, terms, measures, selected method, confidence/caveats, and recent
evidence that the UI is expected to expose.

The formatter owns display formatting only. It never recomputes business logic,
and neither tests nor the eventual UI may parse its rendered text; both consume
the underlying typed payload. Exercise the formatter with committed `testthat`
expectations, then print it from the persistent real-data lab while iterating.
This is the preferred fast loop for computational and table-contract work.

A text preview is computational evidence, not UI evidence. Changes to layout,
reactivity, accessibility, CSS, routing, or browser behavior still require the
Dockerized app and browser checks below. Do not add a one-off preview script
when a canonical formatter exists. `format_enrollment_projection_preview()` is
the worked example.

### Enrollment projection contract

Projection work has a stricter reusable-artifact boundary:

- The forecast target is unique total class-list demand, not DESR final
  enrollment and not census. Expected census is a separately saved retention
  conversion.
- Capacity is an audit and planning comparison, never a demand predictor. A
  reached-capacity overprojection is labeled `Capacity-bounded`; never display
  its one-sided technical zero as ordinary 0% error.
- Observed-enrollment methods select the published demand row. Broad population,
  major/classification, and feeder methods are structural evidence and do not
  silently replace or average with the selected observed method.
- Every Spring population candidate must preserve matched/unmatched components,
  use only preceding terms, and survive `validate_spring_cohort_rows()`.
  Course-level broad-versus-major/classification coupling is saved with its
  aftcast count and WAPE difference; the UI never derives it.
- Weak rows remain visible with confidence `None` and a reason. Do not withhold
  them, relabel them Low, or invent a reassuring default.
- Miss explanations say `Potential explanation` or `Potential contributor` and
  retain their underlying enrollment/capacity changes. They are not causal
  claims.
- Shiny and Course Dynamics read validated artifacts through
  `load_latest_enrollment_projection_bundle()` and
  `build_enrollment_projection_view()`. They never fit, aftcast, pressure-screen,
  calibrate, or select a model in a user session.
- Morning projection refreshes run through `scripts/build-enrollment-projections.R
  --refresh` after successful data transformation. The policy in
  `config/enrollment-projections.yml` defaults to the next Spring after
  `cedar_data_edges()$last_enrolled_complete`, with that edge as the cutoff.
  `R/features/enrollment-projection-refresh.R` resolves the policy and compares
  canonical prepared inputs and model-source hashes before fitting. Target-term
  registrations and schedule context are relevant inputs too; pull dates and
  unrelated post-cutoff registrations are not. Reused bundles are never rewritten.
- `model_version` changes for calculation, selection, calibration, or scoring
  behavior; `schema_version` changes for artifact shape. Every published bundle
  retains validated hashes and embedded normalized source for the model files.
  Official vintages should be built from a clean commit, but dirty development
  artifacts remain auditable through their embedded source.
- A new method is incomplete until the registry, branch candidate, rolling
  aftcast, bundle validator, text preview, designed fixture, real-data audit,
  and any affected UI/browser test agree.

The full executable contract is in
`docs/developers/enrollment-projections.md`; empirical findings and rejected
assumptions are in `docs/developers/forecasting-lessons.md`. Keep the latter as
an evidence ledger, not a second roadmap.

### The three environments

Three separate environments. None of them is expensive — the whole R suite is
28 seconds and a rebuild-and-look loop is about a minute — so the failure mode
is not overspending, it is skipping the environment that would have caught the
bug. A UI change verified only by a green R suite is unverified.

| Environment | Used for | Cost | Ready when |
|---|---|---|---|
| **`Rscript --vanilla`** | cones, branches, reports, everything in `tests/testthat` | ~28s full suite | always — no setup |
| **Dockerized app** | anything rendered: UI, routing, CSS, module wiring | ~65s rebuild | `docker ps` shows `cedar-shiny` *and* it was rebuilt since your last code change |
| **Headless Chrome** | driving the running app, screenshots | ~12s per run | `tests/e2e/node_modules` exists |

**Never `renv`.** The project renv library is not a supported run path and is
expected to be broken — it symlinks into a macOS cache that gets purged, so
every repair breaks again at the next purge. `--vanilla` uses the system
library, which has everything the tests need. This is a dated decision recorded
below; do not "fix" renv to run tests, and in particular never reach for
`renv::deactivate()` — see the warning under "Running tests" above for what it
does to `.Rprofile`.

**The container bakes source with `COPY`.** Only `data/` is bind-mounted, so a
running container does **not** pick up code changes — a container that has been
up for hours is running whatever the source looked like when it was built. This
is the single easiest way to spend an hour debugging a change that was never
deployed. Check before trusting anything you see:

```bash
docker ps --format '{{.Names}}\t{{.Status}}'   # is it up, and how old?
./rebuild-and-test.sh                           # rebuild + restart + wait (~65s)
```

Measured 2026-08-01 after a one-line code change: ~25s for
`docker compose up -d --build`, then ~40s before the app answers HTTP 200.
Only the `COPY` layer and the few steps after it re-run; the R-package installs
above them are cached. A **cold** build that rebuilds those package layers is
several minutes, but that only happens after a prune or a Dockerfile change —
do not plan around it, and do not treat one slow build as the normal cost.

At about a minute, looking at the app is cheap. Do it whenever a change touches
anything rendered rather than saving it up.

### Looking at the app

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

### Which test do I run?

**The full R suite takes 28 seconds. Run it.** Measured 2026-08-01 on 787 files
/ 2,233 assertions, twice, warm and cold — not "a few minutes", which is what
this document used to claim and which pushed agents into narrow runs that miss
blast radius. There is no budget argument for skipping it.

Use a narrower run only for a tight edit-test loop, where 1s beats 28s on the
tenth iteration:

| Scope | Time |
|---|---|
| `test_file()`, one file | ~1s |
| `test_dir(filter=...)`, a few files | ~3s |
| `test_dir()`, everything | **~28s** |

What actually needs thought is whether the R suite is *enough* for the change
you made — several kinds of change it cannot see:

| You changed | Also do this | Why |
|---|---|---|
| One cone / branch function | nothing extra | Pure functions over fixtures — the suite covers it |
| A `group_cols`, join key, or grouping grain | an ad-hoc real-data check | Fixtures are small and often single-valued on the axis you changed, so they pass while production breaks. This is how a campus-blind grouping shipped green. |
| A `list(...)` return shape from a cone | grep the renderers that read it | Tests check the cone; nothing checks that the UI still reads every field. A balance table was returned and silently dropped by the UI for months with the suite green. |
| Module UI / `ui.R` / `server.R` | parse check, render the UI function, then look at it | Module code is **not** loaded by the test suite (see below), so the suite passing says nothing about it |
| CSS only | check no later rule overrides yours, then look at it | testthat cannot see any of it |
| Anything user-visible, before a release | rebuild the container and actually look | |

### Commands

```bash
# One file — the default while iterating
Rscript --vanilla -e "testthat::test_file('tests/testthat/test-course-retention.R')"

# Several files by name pattern
Rscript --vanilla -e "testthat::test_dir('tests/testthat', filter='retention|pathway')"

# Everything (~28s) — the default
Rscript --vanilla -e "testthat::test_dir('tests/testthat')"
```

Add `stop_on_failure = FALSE` when you want the whole run to finish and report, rather than aborting at the first failure.

### The suite does NOT load Shiny modules

`helper-load-functions.R` calls `load_funcs(cedar_base_dir, modules = FALSE)`. So `subtab_header()`, `gen_ed_pct_col()`, `deptProfileGenEdUI()` and every other module/UI function is **absent** during tests. A test that calls one fails with "could not find function", and that is not a bug in the test.

To exercise a UI function, re-run the loader with modules on — do not hand-source individual `R/modules/*.R` files, which pulls in a dependency chain (`fmt_term`, `report_time_estimates`, …) and wastes several attempts:

```r
setwd("tests/testthat")
for (f in list.files(".", "^helper")) source(f)
suppressPackageStartupMessages({library(shiny); library(reactable); library(bslib)})
load_funcs(cedar_base_dir, modules = TRUE)      # cedar_base_dir set by the helper

h <- as.character(deptProfileGenEdUI("g"))
grepl("cedar-subtab-title", h)                   # assert what should have rendered
```

### Ad-hoc checks against fixtures or real data

Some questions cannot be answered from a test failure diff: *how many rows does this actually affect*, *does this grouping change a real number*, *is this leak material*. Those need a scratch script, and writing one is correct — it is how the campus leak was quantified and how a repeater double-count was found. Keep them in the scratchpad directory, never in `tests/`.

The helpers set `cedar_base_dir` from the working directory, so `setwd("tests/testthat")` first:

```r
setwd("tests/testthat")
for (f in list.files(".", "^helper")) source(f)   # cone/branch functions
source("setup.R")                                  # fixtures: test_students, test_sections, ...
suppressMessages(library(dplyr))

# Real data lives at ../../data/*.qs and is qs2 format.
# qs::qread() and qs2::qd_read() both fail on these files.
students <- qs2::qs_read("../../data/cedar_students.qs")
```

Run it with `Rscript --vanilla <script.R>`.

Two things the helper does not do for you, both of which look like broken code:

- **`optparse` is not loaded.** Anything reaching `filter_class_list()` —
  including `prepare_course_attempts()` — fails with
  `could not find function "print_help"`. Add `library(optparse)`.
- **An empty `opt` is a CLI path, not a no-op.** `prepare_course_attempts(s, list())`
  hits `filter_DESRs`/`filter_class_list`'s "no filters supplied" branch, which
  calls `print_help(opt_parser)` and dies on a global that only exists under the
  CLI. Pass at least one real filter: `list(course = "ENGL 1120")`.

### Prove a new test actually catches the bug

A test written alongside a fix usually passes for the wrong reason. Before trusting it, reintroduce the bug and confirm it fails:

```bash
cp R/cones/thing.R /tmp/thing.bak
# revert the fix by hand or with a small sed/python edit
Rscript --vanilla -e "testthat::test_file('tests/testthat/test-thing.R')"   # expect FAIL
cp /tmp/thing.bak R/cones/thing.R
Rscript --vanilla -e "testthat::test_file('tests/testthat/test-thing.R')"   # expect PASS
```

Do this for any test guarding a join key, a grouping grain, or a dedup — those are the ones that silently pass when the fixture is too simple to express the failure.

### Fixtures too simple to express the case

A fixture that cannot represent the bug produces a test that passes forever without checking anything. The shared fixture is single-campus, so every campus-grouping test written against it is vacuous. When you hit this, extend `designed_test_data.R` so the case is representable and reusable — that is the documented path, not a tibble built inside the test file.

### After a failing run

A failed run writes `tests/testthat/_problems/` and `tests/testthat/testthat-problems.rds`. Neither is gitignored, so delete them before staging:

```bash
rm -rf tests/testthat/_problems tests/testthat/testthat-problems.rds
```

### What NOT to do

- Do not `source('setup.R')` from the shell **outside** `tests/testthat` — the paths resolve wrong. From inside that directory it is the correct way to load fixtures.
- Do not `source('global.R')` — it triggers the interactive setup wizard.
- Do not hand-source `R/modules/*.R` to reach a UI function; use `load_funcs(..., modules = TRUE)`.
- Do not run R just to discover an expected value for a new assertion. Assert something obviously wrong (`expect_equal(result, NULL)`) and read the real value out of the failure diff. This is different from an ad-hoc data investigation, which is legitimate and described above.
- Do not leave scratch scripts in `tests/`.

**renv — always use `--vanilla` for local scripts and tests (decision 2026-07-12).**
The project renv library is **not** the supported local run path and is expected
to be broken at any given time. Root cause: the renv library is symlinks into
`~/Library/Caches/org.R-project.R/R/renv/cache`, and macOS periodically purges
that cache, leaving dangling links — so every "repair" (re-restore) breaks again
at the next purge. Docker deliberately does not use renv ("Docker provides the
reproducibility layer" — see `Dockerfile.shiny`), and the system library has
everything tests need, so `Rscript --vanilla` is the standard. `renv.lock` is
kept as the record of known-good package versions. If someone wants a working
RStudio+renv setup, the durable fix is `RENV_CONFIG_CACHE_ENABLED=FALSE` in
`.Renviron` (copies instead of cache symlinks) followed by `renv::restore()` —
do not just re-restore with the cache enabled.

