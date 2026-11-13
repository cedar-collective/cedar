# CEDAR R Test Suite

Unit tests for CEDAR functions using the testthat framework.

See [../README.md](../README.md) for the standard procedure.

## Quick Reference

```bash
# Run the standard gate from the repository root
./run-tests.sh

# Focused iteration only
Rscript --vanilla -e "testthat::test_file('tests/testthat/test-filtering.R')"
```

## Test Files

| File | Tests |
|------|-------|
| `test-filtering.R` | Department, term, campus, level, status filters |
| `test-enrollment.R` | Enrollment analysis |
| `test-headcount-comprehensive.R` | Headcount analysis |
| `test-course-outcomes.R` | Grade and DFW analysis |
| `test-dept-report.R` | Dept Trends feature support |

## Key Files

- `setup.R` - Loads the fixtures, builds the tables derived from them, sources the scenario tables, and defines `create_test_opt()`
- `helper-*.R` - What a test does, never what it reads: functions that run the code under test, stamp a stated series on a fixed row or write a temporary file, with ids and option lists, in `helper-<topic>.R` (no helper types a table); scenario edges in `helper-scenario-edges.R`; packages and sourced files in `helper-load-functions.R`. A `test-*.R` file holds `test_that()` blocks only ([where test code lives](../../docs/developers/testing.md#where-test-code-lives))
- `fixtures/designed_test_data.R` - Hand-crafted test data with known values: the test database
- `fixtures/scenario_tables.R` - The fixed tables one test file reads, typed by hand or derived once from the database; no functions
- `create-test-fixtures.R` - Legacy real-data sampling script; not part of the test pipeline (see its header)
