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

**No: it exists only inside the pipeline.** Write it once, as a fixed object in
`fixtures/scenario_tables.R` ([where test code lives](#where-test-code-lives)),
under the heading of the test file that reads it, with its expected values
documented directly above and a comment saying why it is not in the shared
fixture. The legitimate cases:

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

**A test reads fixed data, and a helper is something a test does.** Four
rules, each enforced by `test-architecture.R`:

1. **A test file holds `test_that()` blocks and nothing else** (a `context()`
   line and `testthat::local_edition()` aside): no function, object,
   `library()` or `source()` at its top level.
2. **Every table a test reads is a fixed object,** built once before any test
   runs and the same object for every test. It is never a function.
3. **A helper function takes an argument or does something.** A function with
   no argument returns the same thing every call, so a table written as one is
   fixed data and belongs with the tables. The twelve helpers that take no
   argument each run something (the function under test, a script, a skip);
   they are listed by name in `helper_actions_without_arguments`
   (`helper-architecture.R`), and the list may only get shorter.
4. **No helper types a table.** A function that types a table from its
   arguments (`tibble()`, `tribble()`, `data.frame()`) is data chosen at call
   time, and a table held by a helper object is a fixture in the wrong file.
   Both go with the tables. The two functions that still call a constructor
   are not data a test reads, and are listed in
   `helper_functions_typing_a_table`.

Everything loads before every test file, whichever file is run:

| What | Where |
|---|---|
| Rows that enter the system | `fixtures/designed_test_data.R`, exposed by `setup.R` as `test_*` and `data_objects` |
| The tables the transform builds from them (student terms, attempts, course terms, flows) | Built once in `setup.R`, by the production builders |
| A table one test file reads: a frame typed by hand as the input of one function, or a population, an attempts table or a mapping-file list derived from the fixtures | `fixtures/scenario_tables.R`, one section per test file, sourced once at the end of `setup.R` |
| The right edges a designed scenario is read through | `helper-scenario-edges.R`, one list per scenario |
| What a test does: run the function under test with its options, stamp a stated series on a fixed row, write to a temporary directory, read a plot. Also ids and option lists | `helper-<topic>.R`, named for the test file it serves |
| Packages, and the source files `load_funcs()` leaves out | `helper-load-functions.R` |

What follows from a table being fixed:

- **A test that needs a variant says so in its own body:**
  `pathway_students %>% filter(term < 202510L)`, or
  `mutate(scenario_test_composition, n_students = c(3L, 30L))`. The fixed
  table is the base and the test states the one thing it changes. R copies on
  modify, so a test cannot change a table for the test after it.
- **Several designed variants of one table are one named list,** typed once:
  `mapping_programs$invalid`, `spine_scenarios$sequence`,
  `dfw_demo_rows$threshold`. Each row's reason is a comment beside the row,
  as in the designed fixtures.
- **A test that states a series, not a table, stamps it on a fixed row:**
  `projection_test_history(c(20, 24), terms = c(202210L, 202310L))` repeats
  `projection_history_row` once per term and writes the series into its count
  columns. The row is typed in the scenario tables; the helper only repeats
  and overwrites, so the shape of a prepared history row has one home.
- **A scenario table that cannot be built stops every test file,** as a broken
  fixture does. Derive one through the builders, readers and filters that
  produce the input of the function under test (`build_population()`,
  `build_attempts()`, `build_cedar_dims()`, `cedar_data_edges()`), never
  through the function under test itself: its output stays an action in a
  helper (`ch_result()`, `gpa_timeline()`), so breaking it fails its own tests
  and no others.
- **Names are global to the suite.** Prefix a name with its scenario or topic
  (`hp2_population`, `ss_attempts`, `roadmap_plan()`), and `grep` the scenario
  tables and the helpers before adding one: it may exist.
- **A helper selects and shapes; it never reimplements a calculation.** The
  expected values stay in the test, beside the assertion.

The scenario tables add under a second to setup. A scratch session loads the
same homes the same way, from `tests/testthat`, into an environment of its own
(`setup.R` assigns with `<<-`, which fails when it is sourced straight into the
global environment):

```r
e <- new.env(parent = globalenv())
invisible(testthat::source_test_helpers(".", env = e))
invisible(testthat::source_test_setup(".", env = e))
local(print(hp2_population), envir = e)
```

Until 2026-11 these definitions sat at the top of 57 of the 86 test files (141
functions, 60 objects). A scratch session could not reach them; two files held
different values under one name (`mc02_edges`); the same builder was written
out in two files; and a file run alone attached different packages from the
same file run in the suite, because `library()` and `source()` calls in one
test file stayed in effect for every file after it. A first pass moved them
into helper files as functions. 78 of those took no argument and returned the
same table every call, so the data a test read was still spread over 34 files
and rebuilt on every call; they became the fixed objects above. Eighteen more
took arguments and typed a table from them (`program_rows("FHIS", leads_to =
"NOPE")`); their tables became fixed objects too, each checked equal to what
its function had returned.

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
| What the app or a session does as it starts (`global.R`, `entrypoint.sh`, the last line of `server.R`, `connect()` in `tests/e2e/lib.mjs`) | `./run-tests.sh --all --fresh`: rebuild, then the new process's first sessions ([a process just started](e2e-testing.md#a-process-just-started)) |
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
./run-tests.sh --e2e --fresh           # restart the app, then time its first sessions
./run-tests.sh --all --fresh           # the same on a rebuilt container (tests the diff)
```

Focused report scopes are `dept-trends`, `roadblocks`, `retention` and
`headcount`; other named suites include `nav`, `admin`, `credit-timeline`
(Course Timing wiring and the truncation disclosure, one population setup),
`harness` (run it when `tests/e2e/lib.mjs` changes) and `demo`. `fresh-start`
runs only with `--fresh`, first, and is no part of `--all`'s tour.

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
| `global.R`, `entrypoint.sh` | R suite, and a note that the app's start changed: run `--all --fresh` and the demo gate afterwards |
| a file the projection model is hashed from (`bash scripts/projection-model-source.sh` prints the list) | what its path selects, marked `PROJECTION MODEL SOURCE`, and a note that the deploy after the merge rebuilds both projection bundles |
| `docs/**`, `*.md` only | nothing |

The diff is this branch's since it left `origin/main` (as of the last fetch)
or the local `main`, whichever is the later: a local `main` left weeks behind
would put everyone's work since into it. The pull-request checks say the same
about model source where a merger sees it, as a check named `Deploy: rebuilds
both projection bundles (about 45 minutes)` or `Deploy: no projection rebuild`.

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

### One heavy job at a time

A development machine with 8 GB runs one of these at a time: the R suite, a
browser tour, a real-data script on the host, a table rebuild, a projection
build. Run two and the result is a failure that names neither:

- A projection bundle build took about 2.5 hours beside the R gate and host
  scripts, and 21 minutes alone the next day (2026-10-24 and 25). It is one
  emulated R process at 100% of a core. Time a build alone before concluding
  a change slowed it.
- A host real-data script beside a report tour cost the app its R process (a
  second start in `docker logs`) and failed one step with "Execution context
  was destroyed"; the same tour alone passed (2026-11-14).
- The full rebuild of the saved tables beside the R gate and the synthetic
  stack was killed for memory after 35 minutes of swapping (2026-11-04).
- A projection build beside the local app is killed in the Docker VM (exit
  137, no R error): `docker compose stop cedar-shiny` first.

**Do not edit a file a run is reading.** `Rscript` reads a script as it
executes it, so editing `R/data-parsers/transform-to-cedar.R` or a
`scripts/*.R` file during its own run ends the run with a parse error no
`parse()` reproduces ("unexpected '}'"), after the work was saved, and with
exit status 1. The same goes for a source file mounted into a running
container and a test file a suite is reading.

**Check the disk before an image build or a browser run** (`df -h`). Docker's
build cache grows with every image build. On a full disk `docker ps` hangs
with no error (the VM has stopped), or a build fails with "input/output
error" and the app answers 500. `docker builder prune -af` returns the most.

### Testing a branch in a git worktree

A worktree has the tracked files only. Three things the main checkout has and
it lacks:

| Missing | Symptom | Do |
|---|---|---|
| `config/config.R`, `config/shiny_config.R` | an image built from the worktree starts and the app stops | copy them in |
| `tests/e2e/node_modules` | "warm up app" fails with `Cannot find package 'puppeteer-core'` | link the main checkout's (a link is not matched by the ignore rule: never `git add` it) |
| `data/` | the `admin` suite ends with ENOENT on `data/catalog-normalizations/…` | link the main checkout's `data`, and add `data` to `.git/info/exclude` |

**No image build is needed to browser-test a branch.** The app image runs any
checkout's source when it is mounted over the baked copy. From the main
checkout, start the local app with a compose override that mounts the
worktree's `R/`, `www/`, `docs/`, `institution/`, `global.R`, `ui.R` and
`server.R` read-only over `/srv/shiny-server/cedar/…`:

```bash
docker compose -f docker-compose.yml -f <override>.yml up -d --no-build cedar-shiny
docker inspect cedar-shiny --format '{{range .Mounts}}{{println .Source}}{{end}}'   # names the worktree?
./run-tests.sh --e2e <suite>                # from the worktree
docker compose up -d --no-build cedar-shiny # back to the image's own source
```

The override is a few lines and belongs in a scratch directory. A mounted
`entrypoint.sh` needs the executable bit, which the repository's copy does not
carry: mount a `chmod 755` copy. An image is built from a worktree only when
the image itself changes (a dependency, the Dockerfile).

**The synthetic stack without a build.** `bash scripts/dev.sh up` builds. Its
source is mounted from the checkout anyway, so the image already on the
machine serves: stop the institutional app (same port), then from the worktree

```bash
docker compose --env-file /dev/null -p cedar-demo -f compose.dev.yml up -d --no-build --force-recreate
./run-tests.sh --e2e demo
docker compose --env-file /dev/null -p cedar-demo -f compose.dev.yml down
```

**A one-off R script on real data, on uncommitted code.** The
`cedar-projections` service bakes source too. Mount the working tree over it,
with the app stopped for memory:

```bash
docker compose stop cedar-shiny
docker compose run --rm --no-deps -T -v "$PWD:/srv/shiny-server/cedar:ro" \
  cedar-projections scripts/<script>.R <args> </dev/null
docker compose start cedar-shiny
```

Keep its output out of the repository and out of pull requests: the
repository is public and the counts are institutional.

**Several open pull requests, tested together.** In a clean worktree, branch
from `origin/main`, merge each pull request's branch, and run the gates on
that tree. Merge the pull requests in the same order, then compare
`origin/main^{tree}` with the tested tree: identical means what deployed is
what was tested. Merged back to back they leave one deploy, because each push
cancels the run before it while that run is still in its test job.

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

A test written alongside a fix often passes for the wrong reason: the fixture
is single-valued on the axis the bug needed, or the assertion reads something
the bug never touched. Put the bug back and see the test fail. This is
mandatory for a guard on a join key, a grouping grain or a dedup, and worth
doing for every line a fix or a rewrite changed.

`scripts/check-test-catches.R` does it from a list of breaks, each one piece
of text in one file and the tests that should then fail:

```yaml
- name: the scope joined on the student alone
  file: R/cones/course-band-dfw.R
  old: 'by = c("student_id", "term")'
  new: 'by = "student_id"'
  tests: [test-course-band-dfw.R]
- name: the enrolled filter dropped
  file: R/branches/student-terms.R
  old: |-
    rows <- student_terms %>% filter(enrolled)
  new: |-
    rows <- student_terms
  tests: [test-student-terms.R, test-return-rates.R]
```

```bash
Rscript --vanilla scripts/check-test-catches.R /path/to/breaks.yml
```

```
2 breaks against 3 test files, in a copy of the tree. The checkout is not edited.

As the tree stands: test-course-band-dfw.R passes (9 tests).
…
1. the scope joined on the student alone  [R/cones/course-band-dfw.R]
   CAUGHT by test-course-band-dfw.R:
     BD02: the students read are those of the level and home campus asked for

2. the enrolled filter dropped  [R/branches/student-terms.R]
   CAUGHT by test-student-terms.R:
     RS01: a scope is the enrolled student-terms of a level and a home campus
   NOT CAUGHT: test-return-rates.R passes with the break in place.

2 of 2 breaks caught.
```

- **The checkout is never edited.** The script copies the tree (what git
  tracks, plus new files git does not ignore) to a temporary directory, runs
  the named tests there as the tree stands, and breaks only the copy. So an
  interrupted run leaves nothing to restore, uncommitted work is safe, a
  container that mounts the checkout never sees a break, and no `_problems/`
  is left behind.
- **`old` must be in the file exactly once**; write enough of the line to make
  it so. A `|` block ends with a line break and `|-` does not.
- **A test that fails as the tree stands stops the run**: under a break its
  failure would prove nothing.
- **Each run has a time limit** (`--timeout`, 300 seconds; an entry may carry
  its own `timeout`). A break can send code somewhere slow: one once started a
  projection build and ran eight minutes. Past the limit is not a catch.
- **A break is caught when a test fails or errors with it in place.** If the
  test file cannot run at all (the break stops the suite's set-up), no test is
  shown to hold it, and it is reported as stopped, with R's error.
- Exit status 0 when every break is caught, 1 when one is not, 2 when the
  breaks file cannot be used.

A break that is not caught means the fixture cannot express the bug: add the
row that can to `fixtures/scenario_tables.R` and run it again. The breaks file
is a working note. Keep it out of the repository (the text it matches goes
stale with the next edit) and list the breaks, and how many were caught, in
the pull request.

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
- Don't wait a fixed time in a test. A test held to three seconds failed on a
  busy machine (ISSUES M74). Wait for the state itself: look, wait, look again,
  and give up after a stated number of tries, as `set_file_time_back()` does
  (`helper-projection-refresh.R`). `test-architecture.R` holds the number of
  `Sys.sleep()` calls in each test file, and it may only go down.

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
first use.

**The host reads the repository's `data/`; the app reads `CEDAR_DATA_DIR`.**
`cedar-repl.R` takes its tables from `data/` under the checkout. The container
mounts the directory `.env` names as `CEDAR_DATA_DIR`, which need not be the
same one. Where they differ, a number from the host disagrees with the app for
no reason in the code: compare the dates of the two directories' files before
believing either, or run the script in the container
([a one-off R script on real data](#testing-a-branch-in-a-git-worktree)).

For method development keep one `R --vanilla --quiet` process
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

---

## Traps, by symptom

Each of these has cost an hour, most of them more than once. The symptom
rarely names its cause.

| What you see | What it is | Where |
|---|---|---|
| `devtools::test()` or `test_local()` fails; "No test files found" in the container | CEDAR is not a package: run `Rscript --vanilla` from the repository root, and in the container from `/srv/shiny-server/cedar` | [Running the R suite](#running-the-r-suite), [the three environments](#the-three-environments) |
| "QS format not detected" | data files are qs2: `qs2::qs_read()` | [Dependencies](#dependencies) |
| `could not find function` for a module's UI function | the R suite does not load modules | [the suite does not load Shiny modules](#the-suite-does-not-load-shiny-modules) |
| The setup wizard starts, or paths resolve wrong | `source("global.R")`, or `source("setup.R")` from outside `tests/testthat` | [what not to do](#what-not-to-do) |
| A fix does not show in the browser | the container runs the source it was built with | [the three environments](#the-three-environments) |
| A library error after a package change | never `renv::deactivate()` or a bare `renv::restore()` | [Dependencies](#dependencies) |
| Untracked `_problems/` and `testthat-problems.rds` | left by a failing run | [after a failing run](#after-a-failing-run) |
| A parse error no `parse()` reproduces, at the end of a long run | the script was edited while it ran | [one heavy job at a time](#one-heavy-job-at-a-time) |
| A job killed with exit 137 and no R error | memory: two heavy jobs at once | [one heavy job at a time](#one-heavy-job-at-a-time) |
| `docker ps` hangs; a build fails with "input/output error"; the app answers 500 | the disk is full | [one heavy job at a time](#one-heavy-job-at-a-time) |
| `Cannot find package 'puppeteer-core'`; ENOENT under `data/` | a worktree lacks what git ignores | [testing a branch in a git worktree](#testing-a-branch-in-a-git-worktree) |
| A host real-data number that disagrees with the app | the host reads the repository's `data/`, the app reads `CEDAR_DATA_DIR` | [the persistent real-data lab](#the-persistent-real-data-lab) |
| "Execution context was destroyed"; a page back on its empty state | the app's R process was replaced under the browser | [the browser stages are memory-bound](e2e-testing.html#the-browser-stages-are-memory-bound-and-running-out-does-not-look-like-it) |
| `frame got detached` | the machine slept | [before a browser run](e2e-testing.html#before-a-browser-run-on-a-development-machine) |
| An input a test set is empty; a picker reads "Type to search..." | the test touched the page before the session had started | [E2E rules](e2e-testing.html#e2e-rules--the-four-that-cause-every-flake) |
| A browser timeout on a control that exists | a selector rotted: `node tests/e2e/check-ids.mjs` | [E2E rules](e2e-testing.html#e2e-rules--the-four-that-cause-every-flake) |
