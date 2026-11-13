---
title: Testing
nav_order: 6
parent: Developer Guide
---

# Testing

What the test data is and why, which checks a change needs, how to run them,
and how to work on a calculation outside Shiny. The hard rules are in
`AGENTS.md` under **Tests**; the browser harness is
[E2E and Browser Testing](e2e-testing.html).

---

## The test data

All unit test data lives in one file,
`tests/testthat/fixtures/designed_test_data.R`. It defines every CEDAR table as
hand-crafted tribbles; `tests/testthat/setup.R` sources it and exposes:

| Variable | Contents |
|----------|----------|
| `test_sections` | Sections centred on HIST, MATH, ANTH, NURS, with variety rows in PSYC, BIOL, MGMT, ENGL, POLS, AMST |
| `test_sections_sf` | Seatfinder sections using 2024/2025 terms |
| `test_students` | Students enrolled in those sections |
| `test_programs` | Program declarations, including health-college samples |
| `test_degrees` | Degrees awarded in stable terms |
| `test_faculty` | Faculty in HIST, MATH, ANTH, PSYC, BIOL, NURS, MGMT, ENGL, POLS; MGMT and POLS have only Term Teacher rows, so they drop out of permanent-faculty counts |
| `test_dims` | The demo institution's mapping files as dimension tables |
| `data_objects` | The tables as the app holds them |

There is no generation step, no binary fixture and no dependency on production
data: the file **is** the test database. Every expected value is traceable to
explicit rows, so a failure is diagnosable by reading the file.

- **Stable terms:** 202010, 202060, 202080, 202110 (Spring, Summer, Fall 2020,
  Spring 2021): completed periods whose real counterparts never change.
- **Pinned counts:** the file's header is a block of expected values (rows by
  department, term, campus, status and level; crosslist scenarios; Regstats
  design values) that test files assert against.
- **Schema:** mirrors `R/data-parsers/transform-to-cedar.R`. When a column is
  added, renamed or removed there, mirror it here; test failures are the drift
  signal. A missing column is added to the fixture, never papered over with
  fallback logic in a test.
- **The synthetic institution** ([synthetic-institution.md](synthetic-institution.html))
  is these same rows, adapted by `dev/demo-data.R` into five traceable
  cohorts. Unit tests keep the small populations.

**Institution configuration is the one exception.** Files an institution
authors, rather than rows its data produces, are tested against the demo
institution's own files: the Degree Explorer suite reads
`institution/demo/degree_*.csv` through `test_degree_catalog` /
`test_degree_roadmaps`, so a real institution's catalog review never breaks a
unit test. Its schedules are worked by hand in the header of
`test-degree-explorer.R`; edit the two together.

### Use real catalog codes

Scenario tables keep their own departments so their pinned counts cannot
disturb HIST's, but those departments are **real UNM subjects and unit
codes**: Regstats uses SOCI, multi-campus SPAN, retention COMM/`CJ`, Roadblocks
ECON, major change GEOG/`GES`, Gen Ed graduates LING, and PHIL for "some other
department". These rows *are* the demo institution, so an invented code such as
`RSTA` ships as a department the app cannot name (names come from `units.csv`,
and `ui.R`'s `.dept_choices` keeps only codes found there). Regstats was once
unselectable in the synthetic app for exactly this reason.

Prefer a pair whose subject differs from its unit where the scenario allows:
COMM → `CJ` and GEOG → `GES` exist because, before them, every fixture code had
`subject == dept_code`, so code that wrongly filtered `subject_course` by
`dept_code` passed the suite.

### What belongs in the shared fixture, and what doesn't

None of CEDAR's test data is real: every row is hand-written, deliberately,
because the sampled binary fixtures it replaced were opaque. So the question is
never "is this data real?" It is:

> **Does this data have a real-world counterpart it has to be faithful to?**

**Yes: it enters the system.** `cedar_registrations`, `cedar_sections`,
`cedar_programs`, `cedar_degrees` are the shapes institutional data arrives in.
Multi-campus delivery, waitlisted students, crosslists and repeat enrolments
are facts about how the data looks, and every analytic touching them needs the
same shape. These belong in `designed_test_data.R`; tests filter from the
`test_*` variables.

**No: it exists only inside the pipeline.** Build it in a function in the test
file's helper (`helper-<topic>.R`, [where test code lives](#where-test-code-lives)),
with its expected values documented directly above and a comment saying why it
is local. The legitimate cases:

- **Intermediate frames.** `compute_stopout_for_group()` takes a frame with
  `outcome` and `stopped_out` already derived; that shape is one function's
  contract, and in the shared fixture it would pass for institutional data.
- **Expected-value tables,** the thing you assert *against*.
- **Scaffolding.** `test-data-loading.R` writes throwaway `.Rds` files for the
  loader to find.
- **Term spacing the stable terms lack.** The relative-term sequences in
  `test-pathway.R` and the data-boundary rows in `test-population.R`; the
  former's header shows the pattern.

When in doubt, the tell is reusability: if a second test file would want the
same rows, they are domain data.

**The failure this guards against** is narrower than "invented data is bad":
*a fixture that cannot express the bug produces a test that passes forever.* In
July 2026 `cedar_registrations` was 100% ABQ, so every campus-grouping test asserted
nothing. Once the fixture gained a second campus (MC01–MC03), the same tests
immediately caught a join that dropped campus and attached the wrong comparison
rate. When a fixture cannot represent a case (it once had no waitlisted
students, because the status map knew only `RE`), extend the fixture; don't
build a one-off scenario or extract a helper solely so a test can reach it.

### Changing fixtures

Edit `designed_test_data.R` directly, then, in the same change:

1. Name new rows by the file's conventions, continuing each sequence:
   **EC-xx** numbered edge cases (EC-01..03 were used by the legacy sampler;
   don't reuse them), **XLxx** crosslist/split scenarios, **SVARxx** section
   variety rows (unusual statuses, NA fields).
2. Update the pinned counts in the header.
3. Update the hard-coded expectations in the affected tests.

Expected values are hard-coded from running the function against the fixtures,
then committed. If one changes, the function or fixture changed: investigate
before updating. To learn the value for a new assertion, assert something
obviously wrong and read the real value from the failure diff.

Filter tests use `filtering_opt()`, which sets `uel = FALSE`: the `uel = TRUE`
default applies the excluded-courses list and changes `subject_course`.

`tests/testthat/create-test-fixtures.R` once sampled real data into binary
`cedar_*_test.qs` files. Nothing loads them; the script is kept, under a legacy
banner, only as the recipe for a stratified real-data sample. Never add rows to
it.

### Where test code lives

**A test file holds `test_that()` blocks and nothing else** (a `context()` line
and `testthat::local_edition()` aside). `test-architecture.R` fails on any
other expression at a test file's top level: a function, an object, a
`library()` or a `source()`. Whatever tests share has one of four homes, and
testthat loads all four before every test file, whichever file is run:

| What | Where |
|---|---|
| Rows that enter the system, and the tables the transform builds from them (student terms, attempts, course terms, flows) | `fixtures/designed_test_data.R`, exposed by `setup.R` as `test_*` and `data_objects` |
| A builder, an option list or a constant that tests share: a pipeline-internal frame, a scenario's population, a scaffolded mapping file | `helper-<topic>.R`, named for the test file it serves |
| The right edges a designed scenario is read through | `helper-scenario-edges.R`, one list per scenario |
| Packages, and the source files `load_funcs()` leaves out | `helper-load-functions.R` |

Three rules keep the helpers dependable:

- **Anything built from the fixtures is a function, never an object.** Helper
  files load before `setup.R`, in alphabetical order, so an object that read a
  fixture or called a production function at load would stop every test file.
  A function costs nothing until a test calls it, and a builder that breaks
  fails the tests that use it and no others. A helper file's top level is
  function definitions and literal values.
- **Helper names are global to the suite.** Prefix a name with its scenario or
  topic (`hp2_population()`, `ss_attempts()`, `roadmap_plan()`), and `grep` the
  helper files before adding one: the builder may exist.
- **A helper selects and shapes; it never reimplements a calculation.** The
  expected values stay in the test, beside the assertion.

A scratch session loads the same homes the same way, from `tests/testthat`,
into an environment of its own (`setup.R` assigns with `<<-`, which fails when
it is sourced straight into the global environment):

```r
e <- new.env(parent = globalenv())
invisible(testthat::source_test_helpers(".", env = e))
invisible(testthat::source_test_setup(".", env = e))
local(print(hp2_population()), envir = e)
```

Until 2026-11 these definitions sat at the top of 57 of the 86 test files (141
functions, 60 objects). A scratch session could not reach them; two files held
different values under one name (`mc02_edges`); the same builder was written
out in two files; and a file run alone attached different packages from the
same file run in the suite, because `library()` and `source()` calls in one
test file stayed in effect for every file after it.

---

## Which checks a change needs

Choose checks by the behavior changed. A fresh container and the breadth of
browser coverage are separate decisions.

| Change / occasion | Required checks |
|---|---|
| Calculation or data contract | Focused committed R tests while editing; `./run-tests.sh` once when finished |
| UI, routing or module wiring | R gate plus `./run-tests.sh --e2e <suite>` covering the change; look at layout changes |
| Representative app check | `./run-tests.sh --e2e` (same as `--e2e smoke`): Enrollment and Course Dynamics |
| PR acceptance | The synthetic CI gate ([below](#pull-request-checks-without-institutional-data)) |
| Release candidate or major pipeline change | `./run-tests.sh --all`: rebuild and run every institutional browser suite |
| Dependency, R or Docker toolchain | Native and Docker dependency checks, their R gates and synthetic acceptance; the institutional release gate stays separate |
| Documentation or presentation only | Check links or appearance; no full run for prose, spacing or colour |

What the R suite cannot see:

| You changed | Also do this | Why |
|---|---|---|
| A `group_cols`, join key or grouping grain | a real-data check | Fixtures are often single-valued on the axis you changed; a campus-blind grouping once shipped green |
| A cone's `list(...)` return shape | grep the renderers that read it | A balance table was returned and silently dropped by the UI for months with the suite green |
| Module UI, `ui.R`, `server.R` | parse, render the UI function, look | Module code is not loaded by the suite ([below](#the-suite-does-not-load-shiny-modules)) |
| CSS | check no later rule overrides yours, then look | testthat cannot see it |
| Anything user-visible, before a release | rebuild the container and look | |

### `run-tests.sh`

Run from the host repository root.

```bash
./run-tests.sh                         # selector check + full R suite
./run-tests.sh --project-library       # same, with the prepared native library
./run-tests.sh --changed               # stages chosen from the diff
./run-tests.sh --e2e                   # R gate + short smoke (two reports)
./run-tests.sh --e2e dept-trends       # R gate + one suite (one --e2e at a time)
./run-tests.sh --e2e reports           # full 16-scenario institutional report tour
./run-tests.sh --all                   # rebuild + every institutional browser suite
./run-tests.sh --all smoke             # rebuild + smoke only
```

Focused report scopes are `dept-trends`, `roadblocks`, `retention` and
`headcount`; other named suites include `nav`, `admin`, `credit-timeline`
(Course Timing wiring and the truncation disclosure, one population setup),
`harness` (run it when `tests/e2e/lib.mjs` changes) and `demo`.

The gate stops at the first failed suite and the report tour at its first
failed step; neither retries. Diagnose app, setup or resource failures before
an explicit rerun. A timeout does not identify its cause: report its duration
separately from correctness. Report the command, pass/fail counts, meaningful
skips, whether Chrome and the app came up and whether the app ran current
source; never call focused or synthetic success a full institutional pass.

**`--changed`** reads the diff and prints one line of reasoning per file:

| changed | selected |
|---|---|
| `R/cones/**`, `R/branches/**`, `tests/testthat/**` | R suite only, no browser |
| `ui.R`, `server.R`, `R/modules/**`, `www/**` | R suite + browser |
| `tests/e2e/<name>.test.mjs` | that suite; R suite skipped |
| `tests/e2e/lib.mjs` | `harness` |
| `renv.lock`, `Dockerfile*`, `scripts/r-environment.R` | dependency check + R suite |
| `dev/**` | R suite + `demo` |
| `docs/**`, `*.md` only | nothing |

It selects; it never certifies. It cannot know a cone change moved a rendered
number, so widen it by hand when the blast radius is larger than the paths.

Observed costs on the development machine, for judging what to skip, not as
budgets: R suite ~2 min; `check-ids` under a second; app warm-up ~14 s; the
institutional report tour ~1 m 45 s; the other browser suites together
~3 m 40 s. The gate polls the app for responsiveness between suites rather than
sleeping.

### The three environments

| Environment | Used for | Ready when |
|---|---|---|
| **`Rscript --vanilla`** | cones, branches, features, everything in `tests/testthat` | system packages installed, or the prepared native library selected |
| **Dockerized app** | anything rendered: UI, routing, CSS, module wiring | `docker ps` shows `cedar-shiny` *and* it was rebuilt since your last code change |
| **Headless Chrome** | driving the running app, screenshots | `tests/e2e/node_modules` exists |

A UI change verified only by a green R suite is unverified.

**The container bakes source with `COPY`.** Only data is mounted, so a running
container does not pick up code changes; one up for hours runs whatever the
source was when it was built. Check before trusting anything you see:

```bash
docker ps --format '{{.Names}}\t{{.Status}}'   # is it up, and how old?
./rebuild-and-test.sh                           # rebuild + restart + wait
```

Application-only changes reuse cached package layers. A test-script or
documentation edit needs no rebuild, and rebuilding does not imply running
every suite. Chrome setup failures are reported separately from app failures.

| Where | Path | Applies to |
|---|---|---|
| **Host** | `/Users/fwgibbs/Dropbox/projects/cedar-project/cedar` | `run-tests.sh`, `Rscript`, `node tests/e2e/*` |
| **Container** | `/srv/shiny-server/cedar` | any `docker compose exec` |

`setup.R`, `load_funcs()`, the fixtures and every e2e helper resolve relative to
the host root, so `cd` there first. Inside the container the app is **not** at
`/srv/shiny-server` (the stock Shiny sample directory); running there gives
`No test files found`, which reads like a broken image:

```bash
docker compose exec -T -w /srv/shiny-server/cedar cedar-shiny Rscript -e '...'
```

Looking at the app (`node tests/e2e/shot.mjs <tab>`), the `connect()` options
and the memory limits of the browser stages are on
[E2E and Browser Testing](e2e-testing.html).

---

## Running the R suite

CEDAR is a Shiny app, not an R package: `devtools::test()`,
`pkgload::load_all()`, `library(cedar)` and `testthat::test_local()` all fail,
because there is no `DESCRIPTION`. Always use `--vanilla`, which skips
`.Rprofile` and automatic data loading:

```bash
# One file: the default while iterating
Rscript --vanilla -e "testthat::test_file('tests/testthat/test-course-retention.R')"

# Several files by name pattern
Rscript --vanilla -e "testthat::test_dir('tests/testthat', filter='retention|pathway')"

# Everything: once after a non-trivial change (./run-tests.sh does this too)
Rscript --vanilla -e "testthat::test_dir('tests/testthat')"
```

Add `stop_on_failure = FALSE` to finish the run and report every failure.
Repeat the full gate only for later code changes or an unresolved failure, not
for each browser retry.

### The suite does not load Shiny modules

`helper-load-functions.R` calls `load_funcs(cedar_base_dir, modules = FALSE)`,
so `deptProfileGenEdUI()` and nearly every other module function is absent; a
test calling one fails with "could not find function". The helper then sources
three module files for the pure helpers the suite tests (`ui-helpers.R`,
`admin.R`, `dept-trends.R`); a test file never sources one itself. To exercise
any other UI function, rerun the loader with modules on, rather than
hand-sourcing `R/modules/*.R` (which pulls a dependency chain):

```r
setwd("tests/testthat")
for (f in list.files(".", "^helper")) source(f)
suppressPackageStartupMessages({library(shiny); library(reactable); library(bslib)})
load_funcs(cedar_base_dir, modules = TRUE)      # cedar_base_dir set by the helper

h <- as.character(deptProfileGenEdUI("g"))
grepl("cedar-subtab-title", h)                   # assert what should have rendered
```

### Prove a new test catches the bug

A test written alongside a fix often passes for the wrong reason. Reintroduce
the bug and confirm it fails; this is mandatory for a guard on a join key, a
grouping grain or a dedup:

```bash
cp R/cones/thing.R /tmp/thing.bak
# revert the fix by hand
Rscript --vanilla -e "testthat::test_file('tests/testthat/test-thing.R')"   # expect FAIL
cp /tmp/thing.bak R/cones/thing.R
Rscript --vanilla -e "testthat::test_file('tests/testthat/test-thing.R')"   # expect PASS
```

### After a failing run

A failed run writes `tests/testthat/_problems/` and
`tests/testthat/testthat-problems.rds`, neither ignored by git. Delete them
before staging:

```bash
rm -rf tests/testthat/_problems tests/testthat/testthat-problems.rds
```

### What not to do

- Never write custom testing scripts: temporary runners, one-off browser
  scripts, shell wrappers, copied e2e variants, Python probes, R scratch tests,
  bespoke smoke commands. They become a second, untrusted test system. The entry
  points are the gates above, `test_file()` / `test_dir()` on committed files,
  and `tests/e2e/`. Exploratory diagnostics stay in a scratchpad, never in the
  repository, and are never presented as verification.
- Don't `source("setup.R")` from outside `tests/testthat` (the paths resolve
  wrong); from inside it is the way to load the fixtures.
- Don't `source("global.R")`: it starts the interactive setup wizard.
- Don't hand-source `R/modules/*.R`; use `load_funcs(..., modules = TRUE)`.

---

## Keeping coverage useful

Preserve numerical, data-integrity and meaningful input-contract tests. Prefer
observed behavior over assertions about source text, CSS values, variable names
or prose. Extend an existing suite and reuse its population setup before adding
a file.

Within one scenario, compute the result once and check its output contract once,
collecting related expectations in a small table as the Enrollment, Pathways and
Regstats tests do; keep different inputs and policy boundaries separate.
Combining assertions without removing repeated work does not make testing
faster.

Retire obligations as well as setup. Code exercised by a behavior test needs no
separate file- or function-existence check. Test a generic renderer's distinct
branches with representative inputs, not once per configured record. Keep a
regression in the layer that owns the behavior; integration tests prove wiring
without repeating the component's checklist.

### The page's words are snapshots

A sentence a reader sees (a summary, a saved reason, a note, a plot's trace
names) is held with `expect_snapshot()`, never with `expect_match()` or a
pasted string. The test still asserts the numbers behind the sentence and any
negative (a word that must not appear); the snapshot holds the wording. The
file needs `testthat::local_edition(3)` at its top, and `setup.R` sets
`NOT_CRAN` so the snapshot is compared rather than skipped.

- The first run writes `tests/testthat/_snaps/<file>.md`; commit it. A run
  with no snapshot file fails in CI, so a new snapshot test ships with its file.
- A wording change fails with a diff. Read the diff, then
  `Rscript --vanilla -e 'testthat::snapshot_accept("<file>")'` and commit the
  updated `.md` alongside the change; the review is the diff of that file.
- Group one test's variants in one `expect_snapshot({ ... })` block with a
  label per `cat()`, so the snapshot reads as the page's cases.
- Pin nothing volatile: a date computed at run time, a count read from
  institutional data, a path.

Before touching a projection sentence, `grep` its words in `_snaps/`: the four
projection files (`test-projection-inputs.R`, `-model.R`, `-view.R`,
`-page-text.R`) hold every sentence the Projections page and Course Dynamics
show.

### The measure of the suite

The number of tests and expectations says nothing about the suite's cost. Watch
the **test lines changed per PR**: when a wording or shape change edits more
test lines than source lines, a fact is pinned in more than one layer, and the
fix is to move it to the one that owns it (`AGENTS.md`, one layer per fact),
not to update every copy. Run time matters only when a file stops being run
while iterating.

---

## Pull-request checks without institutional data

`.github/workflows/pr-checks.yml` runs **Synthetic checks** on PRs targeting
`main`, documentation-only ones included. It tests the proposed merge on a
disposable GitHub-hosted runner with read-only permissions and no deployment
secrets; a first-time fork contribution may need a maintainer to approve the
run. Requiring the check is a repository-admin ruleset step.

The workflow builds the app image, starts the isolated synthetic demo and runs
the same `run-tests.sh` gate: selector validation, the full R suite, then the
demo browser checks. R runs in the image; Node and Chrome on the host. App logs
and the demo screenshot are kept for seven days. Reproduce it locally:

```bash
npm ci --prefix tests/e2e
docker build --platform linux/amd64 -f Dockerfile.shiny --target app -t cedar:pr-test .
CEDAR_DEV_IMAGE=cedar:pr-test docker compose --env-file /dev/null -p cedar-demo -f compose.dev.yml up -d --no-build --pull never
./run-tests.sh --test-image cedar:pr-test --e2e demo
```

`--test-image` uses the image's baked-in source, so rebuild it after editing;
it does not reduce the R suite. Synthetic acceptance does **not** replace the
institutional release gate or production-scale reconciliation.

On a memory-constrained Docker host (a 4 GB VM), run the synthetic and
institutional gates one after the other: the full-data worker, the demo worker
and the Docker R suite together can run out of memory. Stop the demo worker
without removing data before the institutional gate:

```bash
docker compose --env-file /dev/null -p cedar-demo -f compose.dev.yml stop cedar-dev
```

A restart screen during browser tests can mean the worker was killed for
memory; check the container's OOM state before reading missing controls as a UI
regression ([e2e-testing.md](e2e-testing.html)).

---

## Dependencies

`renv.lock` pins the Docker application's packages and R version. Docker runs
`scripts/r-environment.R restore-docker` during its build, before copying app
source. Native setup is `Rscript --vanilla scripts/r-environment.R restore`: it
copies exact installed matches and restores missing versions into
`renv/library/cedar/R-<version>/<platform>/`, never cache symlinks, and never
rewrites startup files, system libraries, data or the old renv library.
`check` / `check-native` are read-only drift checks; a readiness marker rejects
a native library prepared against a different lockfile. `.Rprofile` prefers a
prepared native library and never downloads packages. Setup never runs inside
the test gate. Procedures: [installation.md](installation.html).

- `./run-tests.sh` tests system R; `--project-library` the pinned native
  library. Use one native environment for routine work.
- **Never run `renv::deactivate()` or a bare `renv::restore()`** to fix a
  library error: it rewrites `.Rprofile` (commit `e4237fd`, reverted). Use the
  setup helper.
- Don't snapshot an arbitrary system environment over the lockfile.
- Data files are **qs2**, not qs: `qs::qread()` fails with "QS format not
  detected".

---

## Working on a calculation without Shiny

Shiny is the presentation boundary, not the development loop. Branches, cones,
backtests and artifact builders must be usable and testable without the app;
don't develop a calculation through repeated Shiny restarts. Two environments
serve different purposes:

1. **Designed-fixture tests** are deterministic, committed evidence.
2. **A persistent real-data lab** is for exploration, performance and method
   development against the local snapshot. It guides development and is not
   release evidence.

| Layer | Purpose | Data | Evidence |
|---|---|---|---|
| Focused unit tests | Formulas, edge cases, policy invariants | Designed fixtures | Committed `testthat` expectations |
| Persistent lab | Real distributions, performance, method choices | Local CEDAR snapshot | Reproducible commands and summarized findings |
| Artifact tests | Build, validate, save, reload | Fixtures and `tempdir()` | Round-trip and metadata assertions |
| Release gate | The whole source and UI | Dockerized app and browser | `./run-tests.sh --all` |

An exploratory result becomes production behavior only once a committed test
represents it. A real-data run cannot replace a fixture test, and a fixture test
cannot say whether a method is useful on the current population.

### The persistent real-data lab

Don't hand-roll the bootstrap; it has four gotchas. For a one-off question:

```bash
Rscript --vanilla -e 'source("scripts/cedar-repl.R"); nrow(cedar_registrations)'
```

`cedar-repl.R` sets `cedar_base_dir` and `cedar_data_dir` (required globals with
no defaults), loads lists, trunk, branches, cones and features with
`modules = FALSE`, and binds each CEDAR table lazily, so a table is read on
first use. For method development keep one `R --vanilla --quiet` process
alive, source the helper once, and re-source only the changed file:

```r
source("scripts/cedar-repl.R")
prepared_inputs <- prepare_example_inputs(students = cedar_registrations, sections = cedar_sections)
result <- get_example_answer(prepared_inputs, opt = list(...))

source("R/cones/example-question.R")      # after an edit; tables stay loaded
result <- get_example_answer(prepared_inputs, opt = list(...))
```

`load_funcs(cedar_base_dir, modules = FALSE)` reloads several changed files
without reloading tables; don't re-source `cedar-repl.R` to reload code. Build
expensive, method-independent inputs (census histories, student-term spines,
course-flow tables) once and hold them; rebuild them only when their code,
parameters or data change. For a focused projection formula audit, pass
`opt$projection_methods` to `backtest_course_projection_methods()` so unrelated
methods are not recomputed. Restart R when a `.qs` file changes (a resident
table is a snapshot) and when checking clean-session behavior or memory.

Questions a test diff cannot answer (how many rows does this affect, does this
grouping change a real number) need a scratch script, kept in the session
scratchpad. To combine fixtures with real data from a script:

```r
setwd("tests/testthat")
e <- new.env(parent = globalenv())                  # see "Where test code lives"
invisible(testthat::source_test_helpers(".", env = e))   # functions, test builders
invisible(testthat::source_test_setup(".", env = e))     # test_students, test_sections, ...
students <- qs2::qs_read("../../data/cedar_registrations.qs")   # qs2; qs::qread fails
local(nrow(dplyr::semi_join(students, test_students, by = "subject_course")), envir = e)
```

Two things the helpers don't do, both of which look like broken code:
`optparse` is not loaded (anything reaching `filter_class_list()`, including
`prepare_course_attempts()`, fails with `could not find function "print_help"`;
add `library(optparse)`), and an empty `opt` is a CLI path, not a no-op
(`prepare_course_attempts(s, list())` reaches the "no filters supplied" branch
and dies; pass at least one filter, `list(course = "ENGL 1120")`).

**Rules for lab code.** Analytical functions keep the layer rules: branches and
cones take every table as an argument and never read the lab's globals. Lab
helpers select tables and parameters and call production functions; they never
reimplement a calculation. Never copy institutional rows into committed tests,
docs or snapshots; add faithful designed rows instead. Keep disposable
diagnostics under `output/` or the scratchpad, and record the data cutoff,
target term, campus scope and method version in any diagnostic compared across
sessions.

### Text-first feature previews

A computation-heavy feature gets one canonical text preview before its Shiny
surface: a committed production formatter over the feature payload or validated
saved artifact, never a scratch script or a second implementation. It formats,
labels, orders and selects columns; it never recomputes. Tests and the UI
consume the typed payload and never parse the text.

A useful preview shows enough context to rule out a plausible but ambiguous
table: target and cutoff terms, scope, measure, selected method, accuracy and
signed bias, caveats and recent evidence. Cover its shape and critical labels
with fixture tests; print it from the lab while iterating, without committing
real rows. It is computational evidence, not UI evidence: layout, reactivity,
accessibility, CSS and routing still need the app. The worked example:

```r
bundle <- read_enrollment_projection_bundle("output/projections/enrollment-projections-202710-latest.qs")
print_enrollment_projection_preview(bundle, courses = c("MATH 1215", "CHEM 1215"))
```

### The projection workflow

Projections are built entirely outside Shiny; the contract and its rules are
[Enrollment Projection Architecture](enrollment-projections.html#the-rules-in-brief).
The sequence: prepare reusable inputs (class lists, census, capacity,
student-terms, rosters, populations, the unfiltered preceding-term series);
apply the pressure screen and keep its reasons; run candidate methods only for
the screened roster; backtest each at explicit `as_of_term` cutoffs; audit WAPE,
signed bias, variability and direction; replay selection at every fold using
only earlier aftcasts; build, validate, save and reload a versioned bundle.

```bash
Rscript --vanilla scripts/build-enrollment-projections.R \
  --target-term 202680 --as-of-term 202660 --group critical_courses
Rscript --vanilla -e "testthat::test_dir('tests/testthat', filter='enrollment-projections|architecture')"
```

A named group supplies the roster and campus scope; explicit `--courses` runs
also need `--campuses` and `--market-id`, and those courses are forced through
the screen for diagnosis. The builder and the lab call the same functions; Shiny
only reads the published bundle. `test-architecture.R` keeps projection code
free of Shiny and globals; the `test-projection-*.R` files (inputs, model, view, page text) own formula,
cutoff, selection, empty-scope and artifact-contract behavior. A method change
is incomplete until both the fixture tests and the real-data aftcast are rerun.
