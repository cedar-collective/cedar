# CEDAR Testing Guide

This directory contains all tests for the CEDAR application.

## Testing Philosophy

CEDAR uses a two-tier testing approach:

| Test Type | Location | Data Source | Purpose |
|-----------|----------|-------------|---------|
| **Unit Tests** | `testthat/test-*.R` | Designed fixtures | Verify functions return correct values |
| **Smoke Checks** | targeted `Rscript -e` commands | Production data when needed | Verify selected active app paths load |

## Quick Start

```bash
# Run all unit tests
Rscript tests/testthat.R
```

---

## Unit Tests (testthat)

Unit tests verify that individual functions work correctly with known inputs.

### Running Unit Tests

```bash
# Run all tests
Rscript tests/testthat.R

# Run specific test file
Rscript -e "testthat::test_file('tests/testthat/test-filtering.R')"
```

Note: CEDAR is a Shiny app, not an R package — `devtools::test()` does not work.

### Test Files

```
tests/testthat/
├── setup.R                    # Loads fixtures, defines helpers
├── fixtures/
│   └── designed_test_data.R   # Hand-crafted test data — single source of truth
├── test-filtering.R           # Data filtering tests
├── test-enrollment.R          # Enrollment analysis tests
├── test-headcount.R           # Headcount analysis tests
├── test-grades.R              # Grade analysis tests
└── ...
```

### Fixtures

All test data is hand-crafted tribbles in `fixtures/designed_test_data.R`,
loaded by `setup.R` as `test_sections`, `test_students`, `test_programs`,
`test_degrees`, `test_faculty`, and `test_lookups`. The file's header comment
pins the expected counts that test files hard-code against — every expected
value is traceable to explicit rows in that one file.

- Version-controlled, never auto-generated — edit the file directly
- When adding rows, update the pinned counts in the header and the hard-coded
  expected values in affected test files
- Edge cases follow the naming conventions in the file (EC-xx numbered edge
  cases, XLxx crosslist scenarios, SVARxx section variety rows)

```r
# Example: We KNOW the fixture has exactly this many HIST sections
expect_equal(nrow(filtered), 4)
```

### Writing Good Unit Tests

```r
test_that("filter_DESRs filters by HIST department correctly", {
  # Filter from the designed fixtures for specific assertions
  opt <- create_test_opt(list(dept_code = "HIST"))
  filtered <- filter_DESRs(test_sections, opt)

  # Assert specific expected values (from designed_test_data.R header comments)
  expect_true(all(filtered$department == "HIST"))
  expect_equal(nrow(filtered), nrow(filter(test_sections, department == "HIST")))
})
```

---

## Smoke Checks

Standalone production-data report scripts were retired with the legacy CLI/Rmd
surfaces. Use focused smoke checks for active paths when needed.

### What Smoke Checks Validate

- All required data files load correctly
- Functions work together without schema mismatches
- Active Shiny support paths compute without crashing
- Output types are correct (plots are plotly/ggplot, tables are data frames)

### When to Use Smoke Checks

- After changing data transformation scripts
- Before deploying to production
- When debugging pipeline issues
- As a smoke test after major changes

---

## Fixture Management

Edit `tests/testthat/fixtures/designed_test_data.R` directly — there is no
regeneration step. Update the pinned expected-value counts in its header
comment and the hard-coded expected values in affected test files, then run
the tests to verify:

```bash
Rscript -e "testthat::test_dir('tests/testthat')"
```

If the data schema changes in `transform-to-cedar.R` (columns added, renamed,
or removed), mirror the change in `designed_test_data.R` — test failures are
the drift signal.

`tests/testthat/create-test-fixtures.R` is a legacy script that sampled real
data into binary `.qs` fixtures; nothing loads its output anymore (see its
header). Do not add fixture rows there.

---

## Docker/Shiny Testing

For Docker container and Shiny app testing, use the shell scripts in the project root:

| Script | Purpose |
|--------|---------|
| `quick-test.sh` | Fast container restart + log check |
| `test-docker-shiny.sh` | Full Docker rebuild + validation |
| `test-docker-shiny-full.sh` | Docker + HTTP endpoint test |

---

## Test Coverage

### Currently Implemented

- **Filtering** (`test-filtering.R`) - Department, term, campus, level, status filters
- **Dept Trends feature support** (`testthat/test-dept-report.R`, `testthat/test-dept-report-plots.R`) - Active helper behavior for the Dept Trends feature

### To Be Implemented

- Enrollment analysis (`test-enrollment.R`)
- Headcount analysis (`test-headcount.R`)
- Grade analysis (`test-grades.R`)
- Seatfinder (`test-seatfinder.R`)

---

## Best Practices

### Test Independence
Each test should be completely independent. Use fixtures from `setup.R`, don't rely on previous test state.

### Arrange-Act-Assert Pattern
```r
test_that("function does something", {
  # Arrange: Set up test data
  opt <- create_test_opt(list(dept_code = "HIST"))

  # Act: Call the function
  result <- my_function(test_sections, opt)

  # Assert: Verify results with KNOWN expected values
  expect_equal(nrow(result), 4)
})
```

### Use Designed Fixtures for Behavioral Tests
Don't test that "filtering works" - test that "filtering HIST returns exactly 4 rows with specific courses."

### Use Smoke Checks for Pipeline Validation
Targeted smoke checks catch schema mismatches between components that unit tests miss.

---

## Troubleshooting

### "Column X doesn't exist" errors

This usually means the transformation script and consuming function are out of sync:

1. Check what columns the function expects
2. Check what columns the data has
3. Update `transform-to-cedar.R` if needed
4. Mirror any column changes in `designed_test_data.R`

### Tests pass but Docker fails

The designed fixtures might have columns that production data doesn't:

1. Run a focused smoke check against the active path using production data
2. Fix any schema mismatches in `transform-to-cedar.R`
3. Regenerate production data
4. Align `designed_test_data.R` with the real schema

---

## File Reference

| File | Purpose | Keep? |
|------|---------|-------|
| `testthat.R` | Test runner entry point | Yes |
| `testthat/setup.R` | Load fixtures, define helpers | Yes |
| `testthat/fixtures/designed_test_data.R` | Hand-crafted test data (source of truth) | Yes |
| `testthat/create-test-fixtures.R` | Legacy real-data sampling script (not in test pipeline) | Legacy |
| `testthat/test-*.R` | Unit test files | Yes |
