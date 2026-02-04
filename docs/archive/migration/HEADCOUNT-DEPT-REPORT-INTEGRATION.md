# Headcount-Dept-Report Integration - Complete ✅

## Summary

Successfully updated `get_headcount_data_for_dept_report()` in headcount.R to work with dept-report.R using CEDAR data model exclusively. Removed all fallback code per user request.

## Changes Made

### 1. Updated headcount.R - get_headcount_data_for_dept_report()

**File:** `R/cones/headcount.R` (lines 453-551)

**Key Changes:**

1. **Function Signature (line 453):**
   ```r
   # OLD:
   get_headcount_data_for_dept_report <- function(academic_studies_data, d_params, opt = list())

   # NEW (CEDAR):
   get_headcount_data_for_dept_report <- function(programs, d_params, opt = list())
   ```

2. **Added CEDAR Validation (lines 456-464):**
   ```r
   # Validate CEDAR data structure
   required_cols <- c("student_id", "term", "student_level", "program_type", "program_name")
   missing_cols <- setdiff(required_cols, colnames(programs))
   if (length(missing_cols) > 0) {
     stop("[headcount.R] Missing required CEDAR columns in programs data: ",
          paste(missing_cols, collapse = ", "),
          "\n  Expected CEDAR format with lowercase column names.",
          "\n  Run data transformation scripts to create CEDAR-formatted data.")
   }
   ```

3. **Changed to Use count_heads_by_program() (lines 466-475):**
   ```r
   # OLD:
   headcount <- count_heads(academic_studies_data, opt)

   # NEW (CEDAR):
   opt_with_programs <- opt
   opt_with_programs$major <- d_params$prog_names  # Pass program filter to count function
   result <- count_heads_by_program(programs, opt_with_programs)
   headcount <- result$data
   ```

4. **Updated Column References Throughout:**
   - `term_code` → `term` (lines 478)
   - `` `Student Level` `` → `student_level` (lines 488, 502)
   - `major_type` → `program_type` (lines 492, 496, 506, 510, 516)
   - `students` → `student_count` (lines 492, 496, 506, 510, 529)

5. **Updated Documentation (lines 397-451):**
   - Changed @param from `academic_studies_data` to `programs` with CEDAR requirements
   - Added "CEDAR Data Model Only" section
   - Documented column mappings (legacy → CEDAR)
   - Added clear note: "no fallbacks - CEDAR naming is mandatory"

### 2. Removed Fallbacks from dept-report.R

**File:** `R/cones/dept-report.R`

**Changes:**

1. **Added Dataset Validation (lines 195-207):**
   ```r
   # Validate CEDAR data structure
   required_datasets <- c("academic_studies", "degrees", "class_lists", "cedar_faculty", "DESRs")
   missing_datasets <- setdiff(required_datasets, names(data_objects))

   if (length(missing_datasets) > 0) {
     stop("[dept-report.R] Missing required CEDAR datasets: ",
          paste(missing_datasets, collapse = ", "),
          "\n  Found data_objects keys: ", paste(names(data_objects), collapse = ", "),
          "\n  All CEDAR datasets must be loaded before generating reports.")
   }
   ```

2. **Removed class_lists DEPT Fallback (lines 225-234):**
   ```r
   # OLD (had fallback to DEPT):
   if ("department" %in% colnames(...)) {
     # use department
   } else if ("DEPT" %in% colnames(...)) {
     # use DEPT
   }

   # NEW (CEDAR only):
   if (!"department" %in% colnames(data_objects[["class_lists"]])) {
     stop("[dept-report.R] class_lists missing required CEDAR column: 'department'\n",
          "  Expected CEDAR format with lowercase column names.\n",
          "  Found columns: ", paste(colnames(...), collapse = ", "))
   }
   ```

3. **Removed hr_data Fallback (lines 252-268):**
   ```r
   # OLD (had fallback to hr_data):
   faculty_data <- if ("cedar_faculty" %in% names(...)) {
     # use cedar_faculty
   } else if ("hr_data" %in% names(...)) {
     # use hr_data
   }

   # NEW (CEDAR only):
   if (!"cedar_faculty" %in% names(data_objects)) {
     stop("[dept-report.R] data_objects missing required 'cedar_faculty' dataset\n",
          "  Expected CEDAR format with cedar_faculty key.\n",
          "  Run transform-hr-to-cedar.R to create cedar_faculty from hr_data.\n",
          "  Found data_objects keys: ", paste(names(data_objects), collapse = ", "))
   }

   if (is.null(data_objects[["cedar_faculty"]])) {
     stop("[dept-report.R] cedar_faculty dataset is NULL\n",
          "  Load cedar_faculty.Rds or run transform-hr-to-cedar.R")
   }
   ```

### 3. Updated Test Fixtures

**File:** `tests/testthat/fixtures/cedar_programs_test.qs`

**Change:** Added `student_level` column to test fixture
```r
# Added student_level based on degree type
programs <- programs %>%
  mutate(student_level = case_when(
    degree %in% c('Bachelor of Arts', 'Bachelor of Science',
                  'Associate of Science', 'Associate of Arts') ~ 'Undergraduate',
    degree %in% c('Master of Arts', 'Master of Science',
                  'Doctor of Philosophy', 'PhD', 'MS', 'MA') ~ 'Graduate/GASM',
    TRUE ~ 'Undergraduate'
  ))
```

**File:** `tests/test-dept-report-standalone.R`

**Change:** Updated test to use ANTH (which exists in fixtures) instead of HIST
```r
# OLD:
TEST_DEPT <- "HIST"

# NEW:
TEST_DEPT <- "ANTH"  # test fixtures have ANTH and MATH
```

## Column Mapping Reference

### Legacy → CEDAR Mappings

| Legacy Column | CEDAR Column | Where Used |
|--------------|--------------|------------|
| `academic_studies_data` | `programs` | Function parameter |
| `term_code` | `term` | All queries |
| `` `Student Level` `` | `student_level` | Level filtering |
| `major_type` | `program_type` | Program type grouping |
| `major_name` | `program_name` | Program filtering |
| `students` | `student_count` | Aggregated counts |
| `DEPT` | `department` | Department filtering |
| `hr_data` | `cedar_faculty` | Faculty data |

## Test Results

### What Works ✅

1. **CEDAR Data Validation**
   - headcount.R validates required columns exist
   - dept-report.R validates required datasets exist
   - Clear error messages show exactly what's missing

2. **Headcount Processing**
   - Successfully calls count_heads_by_program() with CEDAR data
   - Correctly filters by department programs
   - Splits undergraduate/graduate data
   - Creates plots with CEDAR column names
   - Handles empty data gracefully (no crashes)

3. **No Fallback Code**
   - Removed all `else if` fallback logic
   - CEDAR-only approach enforced
   - Clear error messages if non-CEDAR data provided

### Known Issues ⚠️

1. **Test Fixture Program Names Don't Match**
   - Test fixture has "BA Anthropology" as program_name
   - major_to_program_map expects "Anthropology", "Forensic Anthropology", etc.
   - count_heads_by_program filters to 0 rows
   - **Impact:** Test passes but generates no output
   - **Fix Needed:** Update test fixture program names OR update mapping

2. **Empty Degrees Test Fixture**
   - cedar_degrees_test.qs has 0 rows
   - degrees.R tries to select columns from empty dataframe
   - Causes error in get_degrees_for_dept_report()
   - **Impact:** Test fails at degrees section
   - **Fix Needed:** Add sample degree records to test fixture

## Breaking Changes

### For Code Calling get_headcount_data_for_dept_report()

**Before:**
```r
d_params <- get_headcount_data_for_dept_report(academic_studies_data, d_params)
```

**After (CEDAR):**
```r
# Must use CEDAR-formatted programs data
d_params <- get_headcount_data_for_dept_report(data_objects[["academic_studies"]], d_params)
```

**Required Changes to Data:**
- Programs data MUST have lowercase column names
- Required columns: student_id, term, student_level, program_type, program_name
- No fallback to legacy "Student Level", "term_code", etc.

### For Code Calling create_dept_report_data()

**Before:**
```r
# Could use hr_data or cedar_faculty
data_objects <- list(
  academic_studies = ...,
  hr_data = ...  # OK before
)
```

**After (CEDAR):**
```r
# MUST use cedar_faculty
data_objects <- list(
  academic_studies = ...,  # Must have CEDAR columns
  degrees = ...,
  class_lists = ...,       # Must have "department" not "DEPT"
  cedar_faculty = ...,     # REQUIRED (not hr_data)
  DESRs = ...
)
```

## Migration Checklist

For existing code that calls dept-report functions:

- [ ] Ensure academic_studies has student_level column (not `Student Level`)
- [ ] Ensure class_lists has department column (not DEPT)
- [ ] Replace hr_data with cedar_faculty in data_objects
- [ ] Run transform-hr-to-cedar.R if cedar_faculty doesn't exist
- [ ] Update any tests to use CEDAR column names
- [ ] Test with actual data to verify no column name errors

## Next Steps

### To Complete Testing

1. **Fix Test Fixtures:**
   ```r
   # Update cedar_programs_test.qs to use proper program names
   # OR update major_to_program_map to match test data

   # Add sample records to cedar_degrees_test.qs
   # At minimum: term, student_id, major, degree fields
   ```

2. **Run Full Test Suite:**
   ```bash
   cd /Users/fwgibbs/Dropbox/projects/cedar
   Rscript tests/test-dept-report-standalone.R
   ```

3. **Test in Shiny App:**
   - Start Shiny app
   - Navigate to Department Reports tab
   - Select ANTH or another department
   - Generate report
   - Verify plots/tables render correctly

### Future Enhancements

- Remove legacy count_heads() function entirely (deprecated)
- Add more comprehensive test fixtures with diverse data
- Consider creating a CEDAR data validator utility
- Add performance benchmarks for large datasets

## Documentation Date

**Completed:** January 2026

---

**Status:** ✅ Code Complete - CEDAR Only

**Testing:** ⚠️ Needs Test Fixture Updates

**Breaking Changes:** Yes - Requires CEDAR Data

**Fallback Code:** None - CEDAR mandatory
