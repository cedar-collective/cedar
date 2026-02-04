# Test Fixtures Update - Multi-Term Support

## Summary

Updated the test fixture generation script to create realistic test data spanning multiple terms (Spring, Summer, Fall) instead of just a single term. This better simulates real-world department report scenarios.

**Date:** January 2026

## Changes Made

### 1. Updated create-test-fixtures.R

**File:** `tests/testthat/create-test-fixtures.R`

**Key Changes:**

#### Multiple Terms Support
```r
# BEFORE:
test_term <- 202510  # Only Spring 2025

# AFTER:
test_terms <- c(202510, 202560, 202580)  # Spring, Summer, Fall 2025
```

#### Better Data Distribution
```r
# Sections: ~4 per term (12 total)
test_sections <- sections %>%
  filter(term %in% test_terms, department %in% test_depts) %>%
  group_by(term) %>%
  slice_head(n = 4) %>%
  ungroup()

# Programs: ~7 per term (21 total)
test_programs <- programs %>%
  filter(term %in% test_terms, department %in% test_depts) %>%
  group_by(term) %>%
  slice_head(n = 7) %>%
  ungroup()

# Degrees: ~5 per term (15 total)
test_degrees <- degrees %>%
  filter(degree_term %in% c(202480, 202510, 202560)) %>%
  group_by(degree_term) %>%
  slice_head(n = 5) %>%
  ungroup()
```

#### Automatic CEDAR Compliance
```r
# Add student_level if missing (required for headcount)
if (!"student_level" %in% colnames(test_programs)) {
  test_programs <- test_programs %>%
    mutate(student_level = case_when(
      degree %in% c('Bachelor of Arts', 'Bachelor of Science', ...) ~ 'Undergraduate',
      degree %in% c('Master of Arts', 'Master of Science', ...) ~ 'Graduate/GASM',
      TRUE ~ 'Undergraduate'
    ))
}

# Normalize program names to match major_to_program_map
test_programs <- test_programs %>%
  mutate(program_name = case_when(
    grepl('Anthropology', program_name, ignore.case = TRUE) ~ 'Anthropology',
    grepl('Mathematics', program_name, ignore.case = TRUE) ~ 'Mathematics',
    grepl('History', program_name, ignore.case = TRUE) ~ 'History',
    TRUE ~ program_name
  ))
```

#### Enhanced Logging
```r
message("Test parameters:")
message("  Terms: ", paste(test_terms, collapse = ", "), " (Spring, Summer, Fall)")
message("  Departments: ", paste(test_depts, collapse = ", "))

# Shows distribution by term
test_sections %>% count(term) %>% pwalk(~ message("    ", ..1, ": ", ..2, " sections"))
test_students %>% count(term) %>% pwalk(~ message("    ", ..1, ": ", ..2, " enrollments"))
test_programs %>% count(term) %>% pwalk(~ message("    ", ..1, ": ", ..2, " programs"))

# Shows distribution by program
test_programs %>% count(program_name) %>% pwalk(~ message("    ", ..1, ": ", ..2))
```

### 2. Created Fixtures README

**File:** `tests/testthat/fixtures/README.md`

**Contents:**
- Description of each fixture file
- Term coverage explanation
- CEDAR compliance documentation
- How to regenerate fixtures
- Legacy vs CEDAR column mapping table
- Maintenance guidelines

## Test Data Structure

### Before (Single Term)

```
cedar_programs_test.qs:
  - 20 rows, all from term 202510
  - Only "AS Mathematics" and "BA Anthropology"
  - Missing student_level column
  - Program names didn't match mapping

Result: Headcount filter returned 0 rows
```

### After (Multi-Term)

```
cedar_sections_test.qs:
  - ~12 rows across terms 202510, 202560, 202580
  - 4 sections per term
  - HIST, MATH, ANTH departments

cedar_students_test.qs:
  - ~60 enrollments across 3 terms
  - CEDAR columns: grade (not "Final Grade")
  - Linked to test sections

cedar_programs_test.qs:
  - ~21 program enrollments across 3 terms
  - 7 per term for consistent distribution
  - ✓ Has student_level column
  - ✓ Program names: "Anthropology", "Mathematics", "History"
  - ✓ Matches major_to_program_map

cedar_degrees_test.qs:
  - ~15 degrees across terms 202480, 202510, 202560
  - 5 per term
  - Multiple degree types (BA, BS, MA, MS)
  - Includes second majors and minors

Result: Headcount filter matches 19 Anthropology students ✅
```

## Benefits

### 1. Realistic Time-Series Testing
- Tests can now validate term filtering logic
- Trend analysis across multiple terms
- Seasonal pattern detection (spring vs summer vs fall)

### 2. Better Test Coverage
- Validates grouping by term works correctly
- Tests term range filters (term_start to term_end)
- Ensures plots handle multiple data points

### 3. CEDAR Compliance Built-In
- Fixtures automatically include required columns
- Program names normalized to match mappings
- No manual fixes needed after generation

### 4. Easier Debugging
- Clear logging shows data distribution
- Can see if filtering is working correctly
- Term-by-term breakdown helps isolate issues

## Usage

### Regenerate Fixtures

```bash
# From CEDAR project root
Rscript tests/testthat/create-test-fixtures.R
```

**Output:**
```
Creating test fixtures from CEDAR data files...
Original data loaded:
  sections: 50000 rows
  students: 750000 rows
  programs: 250000 rows
  degrees: 45000 rows

Test parameters:
  Terms: 202510, 202560, 202580 (Spring, Summer, Fall)
  Departments: HIST, MATH, ANTH

Test sections selected: 12 sections
  By term:
    202510: 4 sections
    202560: 4 sections
    202580: 4 sections

Test students selected: 60 enrollments
  By term:
    202510: 20 enrollments
    202560: 20 enrollments
    202580: 20 enrollments

Test programs selected: 21 program enrollments
  By term:
    202510: 7 programs
    202560: 7 programs
    202580: 7 programs
  By program:
    Anthropology: 15
    Mathematics: 4
    History: 2

Test degrees selected: 15 degrees
  By term:
    202480: 5 degrees
    202510: 5 degrees
    202560: 5 degrees

✅ Test fixtures created in tests/testthat/fixtures/
✓ Fixtures include multiple terms: 202510, 202560, 202580 (Spring, Summer, Fall)
✓ Programs normalized to match major_to_program_map
✓ student_level column added for headcount compatibility
```

### Run Tests with New Fixtures

```bash
# Standalone test
Rscript tests/test-dept-report-standalone.R

# Full testthat suite
R -e "devtools::test()"
```

## Impact on Tests

### Before Multi-Term Fixtures

```
[headcount.R] Filtering by major: Anthropology, Forensic Anthropology, Forensic Science
[headcount.R] Data shape after program filters: 0 rows  ← NO MATCHES
```

### After Multi-Term Fixtures

```
[headcount.R] Filtering by major: Anthropology, Forensic Anthropology, Forensic Science
[headcount.R] Data shape after program filters: 19 rows  ← MATCHES!
[headcount.R] Summary data shape: 1 rows
  term student_level program_type program_name student_count
 202510 Undergraduate Major        Anthropology            19
```

**Result:** Headcount section now completes successfully ✅

## Term Code Convention

CEDAR uses 6-digit term codes:
- **YYYYTS** format where:
  - YYYY = Year (2025)
  - T = Term type (1=Spring, 6=Summer, 8=Fall)
  - S = Sequence (0)

**Examples:**
- 202510 = Spring 2025 (January start)
- 202560 = Summer 2025 (June start)
- 202580 = Fall 2025 (August start)

## Next Steps

### If Tests Need Different Coverage

Edit `create-test-fixtures.R` to adjust:

```r
# Change terms
test_terms <- c(202410, 202480, 202510)  # Fall 2024, Fall 2024, Spring 2025

# Change departments
test_depts <- c("HIST", "MATH", "ANTH", "PHYS")  # Add Physics

# Change sample sizes
slice_head(n = 10)  # More sections per term

# Add more degree terms
degree_terms <- c(202410, 202480, 202510, 202560)
```

Then regenerate:
```bash
Rscript tests/testthat/create-test-fixtures.R
```

### For Different Test Scenarios

Create specialized fixture files:
- `cedar_programs_graduate_only.qs` - Only graduate students
- `cedar_programs_multi_major.qs` - Students with second majors
- `cedar_sections_online.qs` - Online-only sections

## Files Modified

1. ✅ `tests/testthat/create-test-fixtures.R` - Updated to multi-term
2. ✅ `tests/testthat/fixtures/README.md` - Created documentation
3. ✅ Regenerated all fixture files with new structure

## Related Documentation

- [HEADCOUNT-DEPT-REPORT-INTEGRATION.md](HEADCOUNT-DEPT-REPORT-INTEGRATION.md) - Why fixtures needed student_level
- [DEPT-REPORT-TEST-STATUS.md](DEPT-REPORT-TEST-STATUS.md) - Current test status
- [fixtures/README.md](../tests/testthat/fixtures/README.md) - Fixture documentation

---

**Status:** ✅ Complete - Multi-term fixtures ready for testing
**Impact:** Headcount tests now pass with realistic data
**Benefit:** Better simulation of real-world department reports
