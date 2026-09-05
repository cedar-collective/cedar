---
title: Testing
nav_order: 6
parent: Developer Guide
---

# Testing

**Status:** Current — all unit tests run against hand-crafted designed fixtures.

Covers what the test data is and why, what belongs in the shared fixture versus
a single test file, how to change fixtures, and how to run the suite.

## Summary

All unit test data lives in a single file:
`tests/testthat/fixtures/designed_test_data.R`. It defines every CEDAR table
as hand-crafted tribbles, and `tests/testthat/setup.R` sources it and exposes
the tables as `test_sections`, `test_students`, `test_programs`,
`test_degrees`, `test_faculty`, plus `test_lookups` and a `data_objects` list.

There is no fixture generation step, no binary fixture files, and no
dependency on production data — the file **is** the test database.

The [synthetic developer institution](synthetic-institution.md) uses these same
authored records. Its adapter completes missing app metadata and copies whole
histories into five traceable cohorts. Unit tests continue using their original
small populations; the expanded institution supports exploration and integration.

## Philosophy

**Every expected value is traceable to explicit rows.**

- No sampling, no random seeds — failures are diagnosable by reading the
  fixture file, without running the full data pipeline.
- The header of `designed_test_data.R` is a pinned block of expected values
  (row counts by department, term, campus, status, level; crosslist scenario
  summaries; regstats design values). Test files hard-code assertions against
  those pinned counts.
- The fixture schema mirrors the authoritative schema in
  `R/data-parsers/transform-to-cedar.R`. If a column is added, renamed, or
  removed there, mirror the change in `designed_test_data.R` — test failures
  are the drift signal.

## What belongs in the shared fixture, and what doesn't

The rule "don't build test data inside test files" is easy to misread as *use
real data instead of invented data*. That isn't it — and the History section at
the bottom of this page explains why. **None of CEDAR's test data is real.**
Every row in `designed_test_data.R` is hand-written. The project deliberately
moved *away* from sampling production data because binary fixtures were opaque.

So the question is never "is this data real?" It is:

> **Does this data have a real-world counterpart it has to be faithful to?**

**Yes — it enters the system.** `cedar_students`, `cedar_sections`,
`cedar_programs`, `cedar_degrees` are the shapes institutional data arrives in.
There is a real version of each, so the fixture can be faithful or unfaithful to
it, and that is checkable. Real UNM data spans ten campuses; a fixture with one
campus is unfaithful in a way that matters. These belong in
`designed_test_data.R`, where every analytic touching them gets the same shape.

**No — it only exists inside the pipeline.** `compute_stopout_for_group()` takes
a frame with `outcome` and `stopped_out` already derived by an upstream step.
There is no real-world version of that frame; its shape is defined entirely by
the function that produces it. Asking whether it "mirrors real data" has no
answer. Putting it in the shared fixture would be worse than leaving it local —
it would sit beside genuine institutional tables while being an implementation
detail, and the next reader would take it for something it isn't.

The same reasoning covers expected-value tables (the thing you assert *against*),
test scaffolding (`test-data-loading.R` writes throwaway `.Rds` files so the
loader has something to find), and scenarios that turn on term spacing the
stable terms deliberately don't provide (relative-term sequences in
`test-pathway.R`, data-boundary rows in `test-population.R`).

### The failure this actually guards against

Not "invented data is bad." Something narrower and easier to miss:

> **A fixture that cannot express the bug produces a test that passes forever
> without checking anything.**

A worked example from July 2026. `cedar_students` was 100% ABQ. Campus-grouping
tests written against it passed — because a single-campus fixture cannot tell a
campus-aware grouping from a campus-blind one. The tests were decorative. They
only started testing anything once the fixture gained a second campus (MC01–MC03
at the end of `designed_test_data.R`), at which point they immediately caught a
join that had been dropping campus and attaching the wrong comparison rate.

That is why the boundary tables are the ones under discipline. They are what has
to keep looking like the institution, so that tests written against them fail
when the code stops handling the institution correctly.

**When in doubt, the tell is reusability:** if a second test file would want the
same rows, it is domain data and belongs in the shared fixture.

## Fixture Contents

| Variable | Contents |
|----------|----------|
| `test_sections` | Sections centered on HIST, MATH, ANTH, NURS, with variety rows in PSYC, BIOL, MGMT, ENGL, POLS, AMST |
| `test_sections_sf` | Seatfinder-specific sections using 2024/2025 terms |
| `test_students` | Students enrolled in those sections |
| `test_programs` | Program declarations, including health-college samples |
| `test_degrees` | Degrees awarded in stable terms |
| `test_faculty` | Faculty across nine departments (MGMT and POLS are Term Teachers only) |

**Stable terms:** 202010, 202060, 202080, 202110 (Spring/Summer/Fall 2020,
Spring 2021) — completed academic periods whose real-world counterparts never
change.

## Changing Fixtures

Edit `designed_test_data.R` directly, then run the tests:

```bash
cd <project root>
Rscript --vanilla -e "testthat::test_dir('tests/testthat')"
```

When adding rows:

1. Follow the naming conventions already in the file:
   - **EC-xx** — numbered edge cases (continue the sequence from the highest
     existing number)
   - **XLxx** — crosslist/split scenarios
   - **SVARxx** — section variety rows (unusual statuses, NA fields)
2. Update the pinned expected-value counts in the file's header comment.
3. Update hard-coded expected values in affected test files.

**Domain data goes here, not in test files.** Anything representing a shape real
institutional data arrives in belongs in `designed_test_data.R`; tests filter
from the `test_*` variables. Intermediate frames, expected-value tables, and
scaffolding stay local to their test file — see *What belongs in the shared
fixture* above, and say in a comment why the data is local.

## Running Tests

CEDAR is a Shiny app, not an R package — `devtools::test()`,
`pkgload::load_all()`, `library(cedar)`, and `testthat::test_local()` all fail;
there is no `DESCRIPTION` file.

### Choose the smallest relevant browser check

Run from the repository root through `run-tests.sh`. Calculation changes use
focused committed R tests during editing and the full R suite once at the end.
UI or module-wiring changes also need the relevant browser scenario. For prose
or CSS-only work, check links or inspect the affected appearance; do not run the
full application tour solely because a file changed.

```bash
./run-tests.sh                         # selector check + full R suite
./run-tests.sh --project-library       # same gate with prepared native packages
./run-tests.sh --e2e                   # R gate + short smoke (two reports)
./run-tests.sh --e2e dept-trends       # R gate + the changed report
./run-tests.sh --e2e credit-timeline   # credit wiring and truncation disclosure
./run-tests.sh --e2e reports           # full institutional report tour
./run-tests.sh --all                   # rebuild + all institutional browser suites
./run-tests.sh --all smoke             # rebuild + short smoke only
```

The short smoke checks Enrollment (DESR and class-list output) and Course
Dynamics (overview and enrollment detail). The broader report tour retains all
16 scenarios, including Roadblocks, Retention, and combined Headcount filters.
Focused report names are `dept-trends`, `roadblocks`, `retention`, and
`headcount`. Other named suites such as `nav`, `admin`, and `demo` still work.
Course Timing's wiring and truncation checks share one population setup in
`credit-timeline`.

Keep full institutional validation for release candidates and major data-pipeline
changes. A routine source edit needs current application code and the relevant
browser check. The gate stops at the first failed suite without automatic retries;
diagnose the failure before rerunning the focused committed script. A timeout
may indicate application work, a harness problem, or resource pressure. Report
its observed duration and cause when known, separately from correctness.

Use one native environment for routine checks. System R remains the default;
`--project-library` selects the prepared copied library and verifies its pins.
Dependency, R-version, or Docker-toolchain changes require native/Docker checks
and synthetic acceptance; do not repeat that comparison for unrelated edits.
Setup never runs inside the test gate. See [native setup](installation.html#prepare-the-same-r-packages-as-docker).

For a tight edit loop:

```bash
Rscript --vanilla -e "testthat::test_file('tests/testthat/test-population.R')"
```

Recent native gates took roughly two minutes. Runtime varies by host, library,
data, and cache state; the historical 28–35-second estimates are obsolete.

### Keep the environment current

R tests load functions without Shiny modules by default. Browser checks verify
that the selected controls and outputs actually work; R success alone does not
verify UI wiring. Explicitly load modules when an R test needs a UI function.

The ordinary Docker app bakes application source into its image. After changing
that source, use `./rebuild-and-test.sh` before the relevant browser check.
Changing host-run browser scripts or documentation alone does not require a
rebuild. Rebuilding does not imply running every browser suite.

Chrome setup failures must be reported separately from app failures. State the
command, result, meaningful skips, and whether the app used current source.
Focused success does not establish full release success.

### Keep coverage useful

Preserve numerical, data-integrity, and meaningful input-contract tests. Remove
assertions that merely repeat source spelling, CSS spacing, internal variable
names, or prose. Extend an existing relevant suite and reuse population setup
before adding another file. Do not create separate runners or scratch browser
scripts. The known Headcount filter failure and Roadblocks/Retention timeouts
remain tracked in `ROADMAP.md`; narrowing routine checks does not resolve them.

Within one scenario, calculate the result once and check its output contract
once. Collect related numerical expectations in a small table, as in the
Enrollment, Pathways, and Regstats tests. Keep different inputs and policy
boundaries separate. The aim is less repeated computation and maintenance;
combining assertions without removing repeated work does not make testing faster.

Retire obligations as well as repeated setup. Code exercised by a behavior test
does not need separate file/function-existence checks. Test a generic renderer's
distinct branches with representative inputs; do not repeat its checks for every
configured record. Keep calculation regressions in the layer that owns them and
use integration tests to prove wiring, without repeating the component checklist.

## Pull-request checks without institutional data

`.github/workflows/pr-checks.yml` runs **Synthetic checks** on PRs targeting
`main`, including documentation-only changes. It tests the proposed merge on a
disposable GitHub-hosted runner, with read-only repository permissions and no
deployment secrets. First-time fork contributions may need a maintainer to
approve the workflow run.

The workflow builds the normal app image, starts the isolated synthetic demo,
and invokes the same `run-tests.sh` gate: selector validation, the full R suite,
then the demo browser checks. R runs in the built image; Node and Chrome run on
the host. App logs and the demo screenshot are retained for seven days. The
production deployment workflow remains separate.

With Docker, Node, and Chrome installed, reproduce that path locally from the
repository root:

```bash
npm ci --prefix tests/e2e
docker build --platform linux/amd64 -f Dockerfile.shiny --target app -t cedar:pr-test .
CEDAR_DEV_IMAGE=cedar:pr-test docker compose --env-file /dev/null -p cedar-demo -f compose.dev.yml up -d --no-build --pull never
CEDAR_URL=http://localhost:3839/ ./run-tests.sh --test-image cedar:pr-test --e2e demo
```

Rebuild the test image after editing: `--test-image` deliberately uses its
baked-in source, not a host mount. It does not skip or reduce the R suite. This
route needs no host R or institutional data and does not change the ordinary
native-R test path. Synthetic acceptance does **not** replace the full
institutional release gate or production-scale reconciliation.

On memory-constrained Docker hosts, run synthetic acceptance and institutional
release checks sequentially. A 4 GB Docker VM can run out of memory when the
full-data Shiny worker, demo worker, and Docker R suite run together. After the
synthetic gate, stop its worker without removing data:

```bash
docker compose --env-file /dev/null -p cedar-demo -f compose.dev.yml stop cedar-dev
```

Then run the institutional release gate. A restart screen during browser tests
can mean the R worker was killed for memory pressure; inspect the container's
OOM state before interpreting missing controls as a UI regression.

## Computational Prototyping Without Shiny

Shiny is the presentation and integration boundary, not the development loop for
analytical code. Branches, cones, backtests, and artifact builders must be usable
and testable without starting the app. Do not use repeated Shiny restarts to
develop a calculation that can be exercised directly in R.

CEDAR has two deliberately separate non-UI environments:

1. **Designed-fixture tests** provide deterministic release evidence. They are
   fast, inspectable, committed, and independent of local institutional data.
2. **A persistent real-data lab** supports exploration, performance measurement,
   and repeated method development against the local CEDAR snapshot. Its results
   guide development but are not release evidence.

The Dockerized app and browser tests come later, after the computational behavior
is stable and the feature has a UI to integrate.

### Persistent Real-Data Lab

Start one long-lived vanilla R process from the repository root:

```bash
R --vanilla --quiet
```

Then bootstrap the non-Shiny environment once:

```r
source("scripts/cedar-repl.R")
```

`cedar-repl.R` loads lists, trunk, branches, cones, and features with
`modules = FALSE`. Local CEDAR tables are exposed through lazy bindings, so each
table is read only on first use:

```r
nrow(cedar_sections)  # materializes cedar_sections
nrow(cedar_students)  # materializes cedar_students
```

Keep that R process alive while editing. Re-source only the changed analytical
file, then rerun the focused calculation:

```r
source("R/branches/example-analysis.R")
source("R/cones/example-question.R")

prepared_inputs <- prepare_example_inputs(
  students = cedar_students,
  sections = cedar_sections
)

result <- get_example_answer(prepared_inputs, opt = list(...))

# After editing a method, retain the loaded tables and prepared inputs.
source("R/branches/example-analysis.R")
result <- get_example_answer(prepared_inputs, opt = list(...))
```

If several function files changed, calling
`load_funcs(cedar_base_dir, modules = FALSE)` is also inexpensive and does not
reload materialized tables. Do not re-source `scripts/cedar-repl.R` inside the
same session merely to reload code: its job is to establish the session and lazy
table bindings.

Prepared inputs are part of the speed strategy. Expensive, method-independent
work such as canonical census histories, student-term population spines, or
course-flow tables should be constructed once and held in memory. Rebuild them
only when their preparation code, parameters, or source data changes. Formula
changes should normally require only re-sourcing the method file.

Spring inputs precompute preceding-Fall population cells and matched/unmatched
course cohorts once. For a focused formula audit, pass
`opt$projection_methods` to `backtest_course_projection_methods()` so unrelated
student-level methods are not recomputed. Omitting it runs the complete
registered method set, as publication does.

Restart the R process when any underlying `.qs` data file changes. A resident
table is a snapshot; it does not refresh itself when the file on disk is
replaced. Also restart when validating clean-session behavior or memory use.

### Rules for Lab Code

- Analytical functions retain the normal CEDAR layer rules. Branches and cones
  receive every table as an argument and never read the REPL's global tables.
- Lab helpers may select local tables and parameters, but they call production
  branch/cone functions rather than reimplementing calculations.
- Use `--vanilla`. Keep system R, or explicitly select the prepared native
  library before loading packages (see the installation guide). Do not activate
  the old cache-linked renv library or reload data just to test an edited function.
- Never copy local institutional rows into committed tests, documentation, or
  snapshots. Add faithful designed rows to `designed_test_data.R` instead.
- Store disposable real-data diagnostics under `output/`, not `tests/` or
  `data/`, and do not treat them as assertions.
- Record the data cutoff, target term, campus scope, and method version in any
  diagnostic that will be compared across sessions.

### Text-First Feature Previews

Computation-heavy features should expose one canonical text preview before a
Shiny table is built. This gives method and payload changes a fast, inspectable
development loop while source data and prepared inputs remain resident in the
R session.

The preview function belongs in production code and accepts the same feature
payload or validated saved artifact that the UI will consume. It may format,
label, order, and select display columns; it must not calculate a second answer.
The underlying payload remains the contract. Tests and UI code must never parse
the rendered text back into data.

A useful preview includes enough context to prevent a plausible but ambiguous
table: target and cutoff terms, scope, enrollment measure, selected method,
accuracy and signed bias, confidence or caveats, and recent comparable evidence.
Its shape and critical labels should be covered by designed-fixture tests. Real
institutional rows may be printed in the persistent lab for diagnosis, but are
not committed as snapshots.

For enrollment projections, the worked example is:

```r
bundle <- read_enrollment_projection_bundle(
  "output/projections/enrollment-projections-202710-latest.qs"
)
print_enrollment_projection_preview(
  bundle,
  courses = c("MATH 1215", "CHEM 1215")
)
```

This preview verifies computation and the table contract without starting
Shiny. It does not verify column sizing, responsive behavior, accessibility,
reactivity, routing, or styling; those remain Docker and browser work for the
existing Registration > Projections module.

### Validation Layers for a Computational Feature

| Layer | Purpose | Data | Required evidence |
|---|---|---|---|
| Focused unit tests | Prove formulas, edge cases, and policy invariants | Designed fixtures | Committed `testthat` expectations |
| Persistent lab | Explore real distributions, performance, and method choices | Local CEDAR snapshot | Reproducible commands and summarized findings |
| Artifact tests | Prove build, validation, save, and reload behavior | Designed fixtures and `tempdir()` | Round-trip and metadata assertions |
| Release gate | Verify the complete source and UI environment | Dockerized app plus browser fixtures | `./run-tests.sh --all` |

An exploratory result becomes production behavior only after it is represented
in a committed test. A successful real-data run cannot replace a fixture test,
and a fixture test cannot answer whether a method is useful on the current local
population. Both are necessary, for different reasons.

### Projection Workflow Example

Enrollment projections should follow this sequence entirely outside Shiny:

1. Prepare reusable class-list, census, registration-capacity, student-term,
   target-roster, broad-population, major/classification, and feeder inputs.
2. Apply the inexpensive pressure screen and retain its inclusion reasons.
3. Run candidate projection methods only for the resulting course-market roster.
4. Backtest each method using an explicit historical `as_of_term` cutoff.
5. Audit WAPE, signed bias, error variability, and directional consistency.
6. Rolling-test any proposed calibration using only earlier aftcasts.
7. Select and explain the row-level method and any validated adjustment.
8. Build a versioned projection bundle and validate its schema and metadata.
9. Save and reload the bundle in a round-trip test before the app consumes it.

The standalone builder and the persistent lab must call the same branch and cone
functions. The builder owns publication; Shiny only reads the published bundle.
Before changing the projection module, inspect the saved bundle through
`print_enrollment_projection_preview()` and keep its formatter expectations
green. The module should consume the same typed tables and labels, never the
rendered Markdown text.
The projection test suite should cover at least census semantics, cross-campus
student deduplication, delivery-component reconciliation, feeder deduplication,
Spring broad-population and cohort-flow reconciliation and applicability,
historical leakage, pressure-screen
inclusion, signed-error direction, rolling calibration leakage, structural
capacity-censoring guards, method selection, and artifact round trips before a
projection display contract changes in the app.

The current publisher is runnable from the repository root:

```bash
Rscript --vanilla scripts/build-enrollment-projections.R \
  --target-term 202680 \
  --as-of-term 202660 \
  --group critical_courses
```

The named group supplies the exact Gen Ed/FYEX/gateway roster and ABQ/EA campus
scope. It pressure-screens the roster before running student-level methods.
Explicit `--courses` runs must also provide `--campuses` and `--market-id`;
those selected courses are forced through so an analyst can diagnose a row below
the usual thresholds.

Published bundles contain the pressure-screen audit, one selected projection per
course market, every campus/part-term delivery component, every current
candidate method, rolling-origin backtests, and row-level performance metrics.
Raw class-list WAPE, registration-cap-censored WAPE, and uncensored-term
WAPE are stored separately; they answer different questions and must not be
collapsed into one confidence score. WAPE remains unsigned and is paired with
weighted signed bias, directional consistency, and the term-level signed error
history. Raw and adjusted projections remain side by side, and calibration may
be applied only after a leakage-safe rolling improvement test. Structural-demand
calibration must fit and validate only on usable terms whose class-list
registrations did not reach scheduled capacity.
The target term and exact method-specific aftcast terms must accompany row-level
accuracy. See
[Enrollment Projection Architecture](enrollment-projections.html) for the
demand-censoring and method-pairing contract. The Shiny module and a future
Course Dynamics panel must read this contract through
`read_enrollment_projection_bundle()`; it must not invoke the models or rebuild
their tables.

Run the focused computational and architecture checks while iterating:

```bash
Rscript --vanilla -e \
  "testthat::test_dir('tests/testthat', filter='enrollment-projections|architecture')"
```

`tests/testthat/test-architecture.R` keeps projection code independent of Shiny
and global data. `tests/testthat/test-enrollment-projections.R` owns formula,
cutoff, selection, empty-scope, and artifact-contract behavior. Changes to a
method are incomplete until both the designed fixture and real-data aftcast have
been rerun.

## History: the Real-Data Pipeline (legacy)

Before designed fixtures, unit tests loaded binary fixture files
(`cedar_*_test.qs`) sampled from real CEDAR data by
`tests/testthat/create-test-fixtures.R`. That approach was replaced because
binary fixtures are opaque: expected values could not be traced to visible
rows, and regeneration coupled the test suite to local production data.

The `.qs` files have been deleted. The sampling script is kept, with a
prominent legacy banner, purely as the documented recipe for drawing a
stratified real-data sample in case that pipeline is ever revived. **Do not
add fixture rows or edge cases to it** — nothing in the test suite loads its
output.
