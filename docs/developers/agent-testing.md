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

Scenario tables keep their own departments so their pinned counts cannot disturb
HIST's, but those departments are **real UNM subjects and dept codes**, never
scenario names: regstats uses SOCI, multi-campus SPAN, retention COMM/`CJ`,
roadblocks ECON, major-change GEOG/`GES`, gen-ed-grads LING, and PHIL for the
"some other department" rows.

**Use real catalog codes for any new scenario.** This is not cosmetic. These
rows *are* the demo institution (`dev/demo-data.R` adapts this file), so an
invented code such as `RSTA` ships as a department the app cannot name:
`dept_name_lookup` is built from `R/lists/subj_dept_map.R`, and `ui.R`'s
`.dept_choices` keeps only codes found there. The transform prints "Unknown dept
codes" and continues, so the first visible symptom is a department missing from
every dropdown — Regstats was unselectable in the synthetic app for exactly this
reason. A real code needs no demo-layer patch: the name and college resolve on
their own.

Prefer a pair whose `subject_code` differs from its `dept_code` where the
scenario allows it. COMM→`CJ` and GEOG→`GES` are deliberate: they are the
`dept_code` ≠ subject-prefix case the campus/lookup rules warn about, and before
they existed every fixture code had `subject == dept_code`, so code that wrongly
filtered `subject_course` by `dept_code` passed the suite.

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

Choose checks by the behavior changed. A fresh container and the breadth of
browser coverage are separate decisions.

| Change / occasion | Required checks |
|---|---|
| Calculation or data contract | Focused committed R tests while editing; `./run-tests.sh` once when finished |
| UI, routing, or module wiring | R gate plus `./run-tests.sh --e2e <suite>` covering the changed behavior; inspect layout changes visually |
| Representative app check | `./run-tests.sh --e2e` (same as `--e2e smoke`): Enrollment and Course Dynamics |
| PR acceptance | Existing Docker/synthetic CI gate |
| Release candidate or major data-pipeline change | `./run-tests.sh --all`: rebuild and run the full institutional browser suite |
| Dependency / R / Docker toolchain change | Verify pinned native and Docker environments; run their R gates and synthetic acceptance. Institutional release checks remain a separate release requirement |
| Documentation or presentation-only edit | Check links or affected appearance; no full R/browser run solely for prose, spacing, or color |

- Run from the host repository root. During iteration use committed
  `testthat::test_file()` / `test_dir(filter=...)` calls with `--vanilla`.
- After a non-trivial code change, run the full R gate once. Repeat it only for
  subsequent code changes or an unresolved failure, not for every browser retry.
  Choose one native environment for ordinary work; testing both system R and
  pinned native R is not an everyday requirement.
- Browser scripts run from the host. If **application** source baked into Docker
  changed, rebuild before checking it with `./rebuild-and-test.sh`, then select
  the relevant browser suite. A test-script or documentation edit does not
  require rebuilding the app. `--all smoke` rebuilds and runs only smoke.
- `--e2e reports` runs the full 16-scenario institutional report tour without a
  rebuild. Focused report scopes are `dept-trends`, `roadblocks`, `retention`,
  and `headcount`. Existing named browser suites, including `nav`, `admin`,
  `credit-timeline`, and `demo`, remain selectable. `credit-timeline` also covers
  the truncation disclosure; it builds the population once.
- The gate stops at the first failed suite; the report tour stops at the first
  failed step. Neither is automatically retried. Diagnose app/setup/resource failures before an explicit rerun. Report
  observed duration separately; a timeout does not identify its cause.
- Report the command and result, relevant skips, and whether the app source was
  current. Do not call focused or synthetic success a full institutional pass.


### Run the checks the change implies, not the ones you can remember

`./run-tests.sh --changed` reads the diff and selects stages from it, printing
one line of reasoning per file. It exists because deciding by hand is harder
than typing `--all`, so a one-line calculation edit was paying for a full
browser tour it could not possibly exercise.

| changed | selected |
|---|---|
| `R/cones/**`, `R/branches/**`, `tests/testthat/**` | R suite only — **no browser** |
| `ui.R`, `server.R`, `R/modules/**`, `www/**` | R suite + browser |
| `tests/e2e/<name>.test.mjs` | that suite; R suite skipped |
| `tests/e2e/lib.mjs` | `harness` |
| `renv.lock`, `Dockerfile*`, `scripts/r-environment.R` | dependency check + R suite |
| `dev/**` | R suite + `demo` |
| `docs/**`, `*.md` only | nothing |

It selects; it never certifies. It cannot know a cone change moved a rendered
number, so widen it by hand when the blast radius is larger than the paths
suggest, and it is not a release pass.

Observed costs on this machine, for judging what to skip: R suite ~2 min;
`check-ids` under a second; app warmup ~14s; the full institutional tour ~1m45s;
all ten non-report browser suites ~3m40s. Suites no longer wait a fixed 6s
between runs — that cost ~66s per full run and contradicted the rule against
sleeping for Shiny; the gate polls the app for responsiveness instead.

**PR acceptance:** `.github/workflows/pr-checks.yml` runs the canonical gate on
the proposed merge using the isolated synthetic app. `--test-image <image>`
uses the same R test body inside a prebuilt image, with no host data mounts;
Node/Chrome remain on the host. Rebuild that image after application or R-test
edits. Keep this workflow secret-free, read-only, hosted, and separate from
production deployment. Its stable check name is `Synthetic checks`; requiring
it is a repository-admin ruleset step.

**Keep tests proportional.** Preserve numerical, data-integrity, and meaningful
input-contract coverage. Prefer observed behavior over assertions about exact
source text, CSS values/spacing, variable names, or explanatory prose. Extend
an existing relevant suite before adding a file. Shared setup should be run
once when multiple assertions use the same population. Use the committed
runner; do not add a second runner or silently omit release coverage.
Do not add file/function-existence tests for code already exercised by behavior
tests, or repeat a generic renderer's checks for every configured record. Test
its distinct branches with representative inputs. Keep a regression at the layer
that owns the behavior; integration tests should add evidence about wiring, not
repeat the component's full checklist.

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

### `--vanilla` and explicit dependency selection

Cedar is a **Shiny app, not an R package**. `devtools::test()`, `pkgload::load_all()`, `library(cedar)`, and `testthat::test_local()` all fail — there is no `DESCRIPTION` file. Use `testthat::test_file()` / `test_dir()`, and always:

```bash
Rscript --vanilla -e 'testthat::test_dir("tests/testthat")'
```

`--vanilla` skips `.Rprofile` and automatic data loading. `./run-tests.sh` keeps
system R as its default; `./run-tests.sh --project-library` explicitly selects
the prepared, copied native library and checks its versions against `renv.lock`.
Both run the same suite. Setup is separate and never occurs in the test gate.

**Never run `renv::deactivate()` to fix a library error.** It rewrites
`.Rprofile` as a side effect. This already caused an unrelated startup regression
(commit `e4237fd`, reverted). Use the explicit setup helper below for missing or
drifting packages. The data files are
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

Three separate environments catch different failures. Cost depends on the
machine, architecture/emulation, data, and cold caches; do not turn one measured
runtime into a guarantee. A UI change verified only by a green R suite is unverified.

| Environment | Used for | Cost | Ready when |
|---|---|---|---|
| **`Rscript --vanilla`** | cones, branches, reports, everything in `tests/testthat` | machine-dependent | system packages installed, or explicit prepared native library selected |
| **Dockerized app** | anything rendered: UI, routing, CSS, module wiring | depends on cached layers | `docker ps` shows `cedar-shiny` *and* it was rebuilt since your last code change |
| **Headless Chrome** | driving the running app, screenshots | depends on selected suite and data | `tests/e2e/node_modules` exists |

**No cache-linked runtime activation.** `renv` is used only by explicit setup
and image builds. The copied native library and Docker share `renv.lock`; the
old project library is left untouched. Do not use `renv::deactivate()` or bare
`renv::restore()` to repair tests; use the shared installer described below.

**The container bakes source with `COPY`.** Only `data/` is bind-mounted, so a
running container does **not** pick up code changes — a container that has been
up for hours is running whatever the source looked like when it was built. This
is the single easiest way to spend an hour debugging a change that was never
deployed. Check before trusting anything you see:

```bash
docker ps --format '{{.Names}}\t{{.Status}}'   # is it up, and how old?
./rebuild-and-test.sh                           # rebuild + restart + wait
```

Application-only changes normally reuse cached package layers. Cold dependency
builds are more expensive. Rebuild when the app source changes, then run the
selected check; this does not require the full release tour.
### Looking at the app

```bash
node tests/e2e/shot.mjs <tab-slug>     # screenshot a tab -> /tmp/cedar-<tab>.png
node tests/e2e/nav.test.mjs            # assert top-nav routing; exit code = pass/fail
```

Read the resulting PNG directly — that is the visual inspection step, and it is
the only way to catch a colour, spacing, or layout regression.

For rendered behavior, extend an existing committed `tests/e2e/*.test.mjs`
using the shared helpers in `lib.mjs`; do not create and delete scratch browser
scripts. Run `harness` when those shared helpers change.

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

Use the Standard Testing Procedure above. Recent native R gates took roughly
two minutes; browser and Docker times vary with data, cache state, emulation,
and memory pressure. Old timings are not budgets or guarantees.

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

# Everything — once after non-trivial code changes
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

**Shared dependencies (2026-09 alignment; supersedes the cache-linked setup).**
`renv.lock` pins the tested Docker application packages and R version. Docker
uses `scripts/r-environment.R restore-docker` during its build to restore and
verify the system library, before copying app source. No runtime activation.
Native setup is `Rscript --vanilla scripts/r-environment.R restore`: it copies
exact installed matches and restores missing versions into
`renv/library/cedar/R-<version>/<platform>/`, never cache symlinks. It does not
rewrite startup files, system libraries, data, or the old renv library.
`check` / `check-native` are read-only drift checks. A readiness marker rejects
native libraries prepared against a different lockfile. `.Rprofile` prefers a
prepared native library, preserves interactive data loading when configured,
and never downloads packages; `--vanilla` keeps CLI/test startup explicit.
Use `./run-tests.sh --project-library` for pinned native tests; plain
`./run-tests.sh` still tests system R. In a vanilla analysis lab, source the
helper and call `cedar_use_native_library()` before loading any packages, then
source `scripts/cedar-repl.R` once and retain data while re-sourcing functions.
Do not snapshot an arbitrary system environment over the lockfile. Dependency
changes require native and Docker dependency checks and tests; run the full
institutional gate when preparing a release. See
[installation.md](installation.md) for setup and update procedures.

