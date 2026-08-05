# testthat Unit Tests

Unit tests for CEDAR functions using the testthat framework.

See [../README.md](../README.md) for the complete testing guide.

## Quick Reference

```bash
# Run all tests
Rscript tests/testthat.R

# Run specific test file
Rscript -e "testthat::test_file('tests/testthat/test-filtering.R')"
```

## Test Files

| File | Tests |
|------|-------|
| `test-filtering.R` | Department, term, campus, level, status filters |
| `test-enrollment.R` | Enrollment analysis (placeholder) |
| `test-headcount.R` | Headcount analysis (placeholder) |
| `test-grades.R` | Grade analysis (placeholder) |
| `test-dept-report.R` | Dept Trends feature support |

## Key Files

- `setup.R` - Loads fixtures and defines `create_test_opt()` helper
- `fixtures/designed_test_data.R` - Hand-crafted test data with known values — the single source of all test data
- `create-test-fixtures.R` - Legacy real-data sampling script; not part of the test pipeline (see its header)
