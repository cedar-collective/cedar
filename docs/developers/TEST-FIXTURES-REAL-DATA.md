---
title: Testing
nav_order: 6
parent: Developer Guide
---

# Test Fixtures: Real Data Only Approach

**Date:** January 2026
**Status:** ✅ COMPLETE - All fixtures derived from real CEDAR data

## Summary

All test fixtures are now derived from real CEDAR data files. No hardcoded test data exists - every fixture is created by sampling from actual production data, ensuring tests validate real data structures.

## Philosophy

**All test data must come from real data, not hardcoded values.**

This ensures:
- ✅ Tests validate actual data structures
- ✅ Tests catch real-world edge cases
- ✅ Tests stay synchronized with production data
- ✅ No drift between test and production schemas
- ✅ Reproducible test data generation

## Test Fixtures Created

All fixtures stored in: `tests/testthat/fixtures/`

| Fixture File | Source | Rows | Derivation Method |
|-------------|--------|------|-------------------|
| cedar_sections_test.qs | cedar_sections.qs | 12 | 4 sections per term (3 terms) from HIST, MATH, ANTH |
| cedar_students_test.qs | cedar_students.qs | 60 | 20 students per term enrolled in test sections |
| cedar_programs_test.qs | cedar_programs.qs | 21 | 7 program enrollments per term from test depts |
| cedar_degrees_test.qs | cedar_degrees.qs | 15 | 5 degrees per term from test depts |
| cedar_faculty_test.qs | cedar_faculty.qs | 24 | 3 faculty per term/dept combination |

## Fixture Generation Process

### Script: `tests/testthat/create-test-fixtures.R`

**Process:**

1. **Load full CEDAR data files**
   ```r
   sections <- qread("data/cedar_sections.qs")    # 274,772 rows
   students <- qread("data/cedar_students.qs")    # 2,940,164 rows
   programs <- qread("data/cedar_programs.qs")    # 466,973 rows
   degrees <- qread("data/cedar_degrees.qs")      # 62,616 rows
   faculty <- qread("data/cedar_faculty.qs")      # 37,675 rows
   ```

2. **Define test parameters**
   ```r
   test_terms <- c(202510, 202560, 202580)  # Spring, Summer, Fall 2025
   test_depts <- c("HIST", "MATH", "ANTH")   # Three test departments
   ```

3. **Sample sections**
   - Filter by test terms and departments
   - Take 4 sections per term (12 total)
   - Ensures even distribution across terms

4. **Sample students**
   - Filter to students enrolled in test sections
   - Take 20 students per term (60 total)
   - Maintains referential integrity (section_id links)
   - Adds realistic grade data (completed vs in-progress terms)

5. **Sample programs**
   - Filter by test terms and departments
   - Take 7 program enrollments per term (21 total)
   - Normalizes program names to match mappings

6. **Sample degrees**
   - Filter by test departments (handles name mapping)
   - Take 5 degrees per term (15 total)
   - Maps degree_term → term, degree_type → degree

7. **Sample faculty**
   - Filter by test terms and departments
   - Take 3 faculty per term/dept (24 total)
   - Real instructor records with job categories

### Running Fixture Generation

```bash
cd /Users/fwgibbs/Dropbox/projects/cedar
Rscript tests/testthat/create-test-fixtures.R
```

**Expected Output:**
```
Creating test fixtures from CEDAR data files...
All fixtures derived from real data - no hardcoded test data

Original data loaded:
  sections: 274772 rows
  students: 2940164 rows
  programs: 466973 rows
  degrees: 62616 rows
  faculty: 37675 rows

✅ Test fixtures created in tests/testthat/fixtures/
   - cedar_sections_test.qs (12 rows)
   - cedar_students_test.qs (60 rows)
   - cedar_programs_test.qs (21 rows)
   - cedar_degrees_test.qs (15 rows)
   - cedar_faculty_test.qs (24 rows)

✓ ALL test fixtures derived from real CEDAR data - no hardcoded test data
```

## Benefits of Real Data Fixtures

### 1. Schema Validation
Tests catch breaking changes to data structure:
```r
# If cedar_students.qs loses subject_code column,
# test fixtures will also lose it, and tests will fail
# This is GOOD - it means tests are validating real data!
```

### 2. Real-World Edge Cases
Test data includes actual edge cases from production:
- Students with multiple majors
- Cross-listed courses
- Part-term sections
- Graduate/professional degrees
- Multiple job categories for faculty

### 3. Automatic Synchronization
When production data changes:
- Re-run `create-test-fixtures.R`
- Fixtures automatically update with new structure
- Tests validate against current reality

### 4. No Test Data Maintenance
**Before (Hardcoded):**
```r
# Had to manually create test data
test_faculty <- data.frame(
  instructor_id = c("inst1", "inst2"),  # Fake IDs
  job_category = c("professor", "lecturer"),  # May not match real categories
  # ... manually maintain 10+ columns
)
```

**After (Derived):**
```r
# Just sample from real data
test_faculty <- faculty %>%
  filter(term %in% test_terms, department %in% test_depts) %>%
  group_by(term, department) %>%
  slice_head(n = 3)
```

### 5. Realistic Relationships
Fixtures maintain real relationships:
- Students → Sections (via section_id)
- Sections → Faculty (via instructor_id)
- Students → Programs (via student_id)
- All foreign keys are real, not fabricated

## Transformation Pipeline

The correct workflow for data → fixtures:

```
Source Data (MyReports)
         ↓
R/data-parsers/transform-to-cedar.R
         ↓
CEDAR Data Files (data/cedar_*.qs)
         ↓
tests/testthat/create-test-fixtures.R
         ↓
Test Fixtures (tests/testthat/fixtures/cedar_*_test.qs)
         ↓
Tests (tests/testthat/test-*.R, tests/test-dept-report-standalone.R)
```

## Script Consolidation

### Removed Duplicate Scripts

The following scripts were **removed** because `R/data-parsers/transform-to-cedar.R` handles all transformations comprehensively:

- ❌ `R/transform-hr-to-cedar.R` (duplicate)
- ❌ `R/enhance-cedar-students.R` (handled by transform-to-cedar.R)
- ❌ `R/enhance-cedar-programs.R` (handled by transform-to-cedar.R)
- ❌ `R/enhance-cedar-degrees.R` (handled by transform-to-cedar.R)

### Single Source of Truth

**Use:** `R/data-parsers/transform-to-cedar.R`

This script handles:
1. DESRs → cedar_sections
2. class_lists → cedar_students
3. academic_studies → cedar_programs
4. degrees → cedar_degrees
5. hr_data → cedar_faculty

**All transformations in one place, run as part of daily data pipeline.**

## Test Usage

### Department Report Standalone Test

**File:** `tests/test-dept-report-standalone.R`

**Before (Mock Data):**
```r
# Created fake faculty data
data_objects$cedar_faculty <- unique_instructors %>%
  mutate(
    instructor_name = paste0("Instructor ", row_number()),
    job_category = sample(c("professor", "lecturer"), n(), replace = TRUE)
  )
```

**After (Real Data):**
```r
# Loads real faculty fixture
data_objects$cedar_faculty <- qread(file.path(fixtures_dir, "cedar_faculty_test.qs"))
```

**Benefits:**
- Tests validate real faculty data structure
- Tests catch if job_category values change
- Tests work with actual instructor IDs
- No maintenance of mock data logic

## Maintenance

### When to Regenerate Fixtures

Regenerate fixtures when:

1. **Production data schema changes**
   ```bash
   Rscript tests/testthat/create-test-fixtures.R
   ```

2. **Need different test coverage**
   Edit `create-test-fixtures.R` to change:
   - `test_terms` - which terms to include
   - `test_depts` - which departments to sample
   - Sample sizes (n=4, n=20, etc.)

3. **After running transform-to-cedar.R**
   ```bash
   # Daily workflow:
   Rscript R/data-parsers/transform-to-cedar.R  # Transform source → CEDAR
   Rscript tests/testthat/create-test-fixtures.R  # Create test fixtures
   ```

### Quality Checks

After regenerating fixtures, verify:

```bash
# Check fixture sizes
ls -lh tests/testthat/fixtures/cedar_*_test.qs

# Run tests to ensure they pass
Rscript tests/test-dept-report-standalone.R
R -e "devtools::test()"
```

## Best Practices

### DO ✅

1. **Always derive fixtures from real CEDAR data**
   ```r
   test_data <- real_data %>% filter(...) %>% sample_n(100)
   ```

2. **Maintain referential integrity**
   ```r
   # Students should reference actual section_ids from test_sections
   test_students <- students %>%
     filter(section_id %in% test_sections$section_id)
   ```

3. **Document sampling strategy**
   ```r
   # Comment why you chose these parameters
   test_terms <- c(202510, 202560, 202580)  # Spring, Summer, Fall for seasonal variation
   ```

4. **Keep fixtures small but realistic**
   - Small: Fast test execution
   - Realistic: Multiple terms, depts, edge cases

### DON'T ❌

1. **Never hardcode test data**
   ```r
   # BAD
   test_faculty <- data.frame(
     instructor_id = c("fake1", "fake2"),
     ...
   )
   ```

2. **Never skip fixture regeneration after schema changes**
   - If you add/remove columns from CEDAR data
   - Always regenerate fixtures to stay in sync

3. **Never commit large fixtures**
   - Keep fixtures under 1MB each
   - Sample appropriately from full data

4. **Never create transformation scripts outside data-parsers/**
   - Use `R/data-parsers/transform-to-cedar.R`
   - Don't create duplicate transformation logic

## Related Documentation

- [GLOBAL-CEDAR-IMPLEMENTATION-COMPLETE.md](GLOBAL-CEDAR-IMPLEMENTATION-COMPLETE.md) - Global.R CEDAR setup
- [CREDIT-HOURS-MIGRATION-COMPLETE.md](CREDIT-HOURS-MIGRATION-COMPLETE.md) - Credit hours CEDAR migration
- [TEST-FIXTURES-UPDATE.md](TEST-FIXTURES-UPDATE.md) - Multi-term fixtures documentation

---

**Status:** ✅ Complete
**All Fixtures:** Derived from real CEDAR data
**No Hardcoded Data:** Zero mock/fake test data
**Transformation:** Consolidated in transform-to-cedar.R
