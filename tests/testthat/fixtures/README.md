# Test Fixtures

All test data is now loaded from designed_test_data.R, which is hand-crafted to match real CEDAR data structure and stable term values. No .qs files are used; all tests reference the test_* variables defined in designed_test_data.R.

## The Pipeline

```
designed_test_data.R  (single source of test data)
       ↓
setup.R  (loads designed_test_data.R as test_* variables)
       ↓
All tests reference test_* variables directly
```

**Stable terms:** 202010, 202060, 202080, 202110 (Spring/Summer/Fall 2020, Spring 2021).
These are completed academic periods — data will never change. All values in designed_test_data.R are based on these periods.

## Fixtures

| Variable         | Contents |
|------------------|----------|
| `test_sections`  | Sections from HIST, MATH, ANTH, NURS |
| `test_students`  | Students enrolled in those sections |
| `test_programs`  | Program declarations for those students + health-college sample |
| `test_degrees`   | Degrees awarded in stable terms |
| `test_faculty`   | Faculty in those departments and terms |

`test_programs` includes College of Nursing and College of Population Health
students so cohort, bottleneck, and health-domain tests run against real data.

## Using Fixtures in Tests

```r
# In setup.R, designed_test_data.R is loaded as test_* variables:
test_sections   # section data
test_students   # student data
test_programs   # program data
test_degrees    # degree data
test_faculty    # faculty data

# Write assertions against the real data:
hist_sections <- filter(test_sections, department == "HIST", term == 202010)
result <- filter_DESRs(test_sections, opt = list(dept = "HIST", term = 202010))
expect_equal(nrow(result), nrow(hist_sections))
```

## Changing Fixtures

There is no regeneration step — edit `designed_test_data.R` directly, then run
the tests to validate:

```bash
Rscript -e "testthat::test_dir('tests/testthat')"
```

When adding rows, follow the naming conventions already in the file
(**EC-xx** for numbered edge cases — continue the sequence; **XLxx** for
crosslist/split scenarios; **SVARxx** for section variety rows), update the
pinned expected-value counts in the file's header comment, and update any
hard-coded expected values in affected test files.

`create-test-fixtures.R` (one directory up) is a legacy script that sampled
real data into binary `.qs` fixtures. Nothing loads its output anymore — never
add fixture rows there.

## Rules

**Never create rows in test code.** If a scenario is missing, check whether
it exists in the real data for the stable terms. If it does, add it to designed_test_data.R.
If it genuinely doesn't exist in real data, the test is testing a scenario that can't happen.

**Never use `bind_rows` to augment a fixture.** All data should be defined in designed_test_data.R.

**If required columns are missing,** fix designed_test_data.R. Do not add fallback logic in tests.
