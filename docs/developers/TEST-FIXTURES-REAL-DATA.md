---
title: Testing
nav_order: 6
parent: Developer Guide
---

# Test Fixtures: Designed Data

**Status:** Current — all unit tests run against hand-crafted designed fixtures

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

**Never construct fixture tibbles inside test files.** All test data lives in
`designed_test_data.R`; tests filter from the `test_*` variables.

## Running Tests

CEDAR is a Shiny app, not an R package — `devtools::test()`,
`pkgload::load_all()`, and `library(cedar)` do not work.

```bash
# All tests
Rscript -e "testthat::test_dir('tests/testthat')"

# One file
Rscript -e "testthat::test_file('tests/testthat/test-population.R')"
```

For UI and routing behavior, see the browser-based E2E harness in
`tests/e2e/`.

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
