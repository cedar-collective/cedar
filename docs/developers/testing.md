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
Rscript -e "testthat::test_dir('tests/testthat')"
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

Always use `--vanilla`. The project's renv library is not a supported run path
and is expected to be broken: it symlinks into a macOS cache that gets purged,
so each repair breaks again at the next purge. The system library has
everything the tests need.

```bash
# Everything (~28s) — the default
Rscript --vanilla -e "testthat::test_dir('tests/testthat')"

# One file (~1s) — for a tight edit-test loop
Rscript --vanilla -e "testthat::test_file('tests/testthat/test-population.R')"
```

**The full suite is 28 seconds**, so there is no reason to skip it. Narrow runs
are for iteration speed, not for saving a budget.

### Three environments

| Environment | Used for | Cost |
|---|---|---|
| `Rscript --vanilla` | cones, branches, reports — everything in `tests/testthat` | ~28s |
| Dockerized app | anything rendered: UI, routing, CSS, module wiring | ~65s rebuild |
| Headless Chrome (`tests/e2e/`) | driving the running app, screenshots | ~12s per run |

Two things the R suite cannot see, both of which have shipped bugs green:

- **Shiny modules are not loaded.** The helper calls
  `load_funcs(..., modules = FALSE)`, so UI functions do not exist during tests.
  Re-run the loader with `modules = TRUE` to exercise one.
- **The container bakes source with `COPY`.** Only `data/` is mounted, so a
  running container does not pick up code changes. Check `docker ps` for its
  age and run `./rebuild-and-test.sh` before trusting anything you see — about
  65s (25s build, 40s waiting for the app), so it is worth doing routinely. A
  cold build that rebuilds the cached R-package layers takes several minutes,
  but only after a prune or a Dockerfile change.

For UI and routing behaviour, see the browser harness in `tests/e2e/` and its
README.

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
