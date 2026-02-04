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
| `test-dept-report.R` | Dept report components (placeholder) |

## Key Files

- `setup.R` - Loads fixtures and defines `create_test_opt()` helper
- `fixtures/known_test_data.R` - Hand-crafted test data with known values
- `fixtures/cedar_*_test.qs` - Schema fixtures from real data
- `create-test-fixtures.R` - Regenerates schema fixtures
