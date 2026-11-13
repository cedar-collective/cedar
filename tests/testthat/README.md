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

- `setup.R` - Loads the fixtures and the tables built from them, and defines `create_test_opt()`
- `helper-*.R` - Everything else tests share: builders, option lists and constants in `helper-<topic>.R`, scenario edges in `helper-scenario-edges.R`, packages and sourced files in `helper-load-functions.R`. A `test-*.R` file holds `test_that()` blocks only ([where test code lives](../../docs/developers/testing.md#where-test-code-lives))
- `fixtures/designed_test_data.R` - Hand-crafted test data with known values — the single source of all test data
- `create-test-fixtures.R` - Legacy real-data sampling script; not part of the test pipeline (see its header)
