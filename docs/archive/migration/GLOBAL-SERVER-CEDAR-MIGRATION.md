# Global.R and Server.R CEDAR Migration Guide

**Date:** January 2026
**Status:** 🟡 Planning - Ready for Implementation

## Overview

This document outlines the changes needed to update `global.R` and `server.R` to enforce CEDAR-only data model throughout the Shiny application.

## Current State

### Data Loading (global.R)

**Current file list:**
```r
file_list <- c("DESRs", "class_lists", "academic_studies", "degrees", "forecasts", "hr_data")
```

**Issues:**
1. Loads files with **legacy names** (e.g., `class_lists.qs`, `hr_data.Rds`)
2. No validation that data is in CEDAR format
3. Mixed naming conventions throughout application

### Data Usage (server.R)

**Current usage:**
```r
# Department Reports
d_params <- create_dept_report_data(data_objects, opt)

# Course Reports
c_params <- create_course_report_data(data_objects, opt)

# Data status check
get_data_status(data_objects)
```

**Issues:**
1. `data_objects` contains mixed legacy/CEDAR data
2. No validation at server startup
3. `course-report.R` still uses legacy `hr_data` key

## Proposed CEDAR Data Model

### File Naming Convention

| Legacy File Name | CEDAR File Name | data_objects Key | Purpose |
|-----------------|-----------------|------------------|---------|
| `DESRs.qs` | `cedar_sections.qs` | `DESRs` | Course sections |
| `class_lists.qs` | `cedar_students.qs` | `class_lists` | Student enrollments |
| `academic_studies.qs` | `cedar_programs.qs` | `academic_studies` | Program enrollments |
| `degrees.qs` | `cedar_degrees.qs` | `degrees` | Degrees awarded |
| `hr_data.Rds` | `cedar_faculty.qs` | `cedar_faculty` | Faculty data |
| `forecasts.qs` | `forecasts.qs` | `forecasts` | Enrollment forecasts |

**Key Design Decision:**
- **File names** use explicit `cedar_*` prefix for clarity
- **data_objects keys** preserve legacy names for backwards compatibility
- This allows gradual migration of consuming code

### Why Preserve Legacy Keys?

The cones (dept-report.R, credit-hours.R, etc.) currently reference `data_objects[["class_lists"]]`, `data_objects[["academic_studies"]]`, etc. By keeping these keys while changing the underlying file names, we can:

1. ✅ Enforce CEDAR format at data loading (global.R)
2. ✅ Validate column structure before app starts
3. ✅ Avoid breaking existing cones that reference legacy keys
4. 🔄 Gradually update individual cones to use descriptive names

## Implementation Plan

### Phase 1: Update global.R ✅ READY

**File:** [global-CEDAR.R](../global-CEDAR.R) (new version created)

**Key Changes:**

1. **CEDAR File Mapping**
```r
# Map data_objects keys to CEDAR file names
cedar_file_map <- list(
  DESRs = "cedar_sections",
  class_lists = "cedar_students",
  academic_studies = "cedar_programs",
  degrees = "cedar_degrees",
  cedar_faculty = "cedar_faculty",
  forecasts = "forecasts"
)
```

2. **Data Validation**
```r
# Validate CEDAR structure before app starts
validation_specs <- list(
  DESRs = c("section_id", "term", "department", "instructor_id", "subject_course"),
  class_lists = c("student_id", "term", "department", "grade", "credits", "subject_code"),
  academic_studies = c("term", "student_level", "program_type", "program_name"),
  degrees = c("term", "degree", "program"),
  cedar_faculty = c("term", "instructor_id", "department", "job_category")
)

for (key in names(validation_specs)) {
  validate_cedar_data(data_objects[[key]], key, validation_specs[[key]])
}
```

3. **Remove Legacy hr_data Assignment**
```r
# BEFORE:
hr_data <- data_objects[["hr_data"]]

# AFTER:
cedar_faculty <- data_objects[["cedar_faculty"]]  # CEDAR naming
# hr_data removed - use cedar_faculty instead
```

**Benefits:**
- ✅ Fails fast if data is not in CEDAR format
- ✅ Clear error messages show exactly what's wrong
- ✅ Prevents application from starting with invalid data
- ✅ Documents expected CEDAR structure

### Phase 2: Update course-report.R

**File:** `R/cones/course-report.R`

**Current Issue:**
```r
hr_data <- data_objects[["hr_data"]]  # Line 26 - LEGACY
```

**Required Change:**
```r
# BEFORE:
hr_data <- data_objects[["hr_data"]]

# AFTER:
cedar_faculty <- data_objects[["cedar_faculty"]]
```

**Then update all references:**
```r
# Update throughout course-report.R:
hr_data -> cedar_faculty
job_cat -> job_category
```

### Phase 3: Create CEDAR Data Files

**Required Transformation Scripts:**

1. **transform-sections-to-cedar.R** (if doesn't exist)
   - Input: `DESRs.qs` (legacy)
   - Output: `cedar_sections.qs`
   - Ensure columns: `section_id`, `term`, `department`, `instructor_id`, `subject_course`, etc.

2. **transform-students-to-cedar.R** (if doesn't exist)
   - Input: `class_lists.qs` (legacy)
   - Output: `cedar_students.qs`
   - Ensure columns: `student_id`, `term`, `grade`, `credits`, `subject_code`, `level`, etc.

3. **transform-programs-to-cedar.R** (if doesn't exist)
   - Input: `academic_studies.qs` (legacy)
   - Output: `cedar_programs.qs`
   - Ensure columns: `term`, `student_level`, `program_type`, `program_name`, etc.

4. **transform-degrees-to-cedar.R** (if doesn't exist)
   - Input: `degrees.qs` (may already be CEDAR)
   - Output: `cedar_degrees.qs`
   - Ensure columns: `term`, `degree`, `program`, etc.

5. **transform-hr-to-cedar.R** ✅ MAY EXIST
   - Input: `hr_data.Rds` (legacy)
   - Output: `cedar_faculty.qs`
   - Ensure columns: `term`, `instructor_id`, `department`, `job_category`

### Phase 4: Update server.R

**File:** `server.R`

**No major changes needed** - server.R already uses `data_objects` correctly:
```r
# These calls are already CEDAR-compatible
d_params <- create_dept_report_data(data_objects, opt)  # Line 2534
c_params <- create_course_report_data(data_objects, opt)  # Line 1184
```

**Optional Enhancement:**
Add validation check at server startup:
```r
server <- function(input, output, session) {

  # Validate data_objects structure
  observe({
    required_keys <- c("DESRs", "class_lists", "academic_studies",
                       "degrees", "cedar_faculty")
    missing_keys <- setdiff(required_keys, names(data_objects))

    if (length(missing_keys) > 0) {
      showNotification(
        paste("Missing required data:", paste(missing_keys, collapse = ", ")),
        type = "error",
        duration = NULL
      )
    }
  })

  # ... rest of server code
}
```

## Migration Steps

### Step 1: Create CEDAR Data Files

```bash
# From cedar project root
cd /Users/fwgibbs/Dropbox/projects/cedar

# Check which transformation scripts exist
ls R/transform-*-to-cedar.R

# Run transformations to create CEDAR files
Rscript R/transform-sections-to-cedar.R    # if exists
Rscript R/transform-students-to-cedar.R    # if exists
Rscript R/transform-programs-to-cedar.R    # if exists
Rscript R/transform-degrees-to-cedar.R     # if exists
Rscript R/transform-hr-to-cedar.R          # if exists

# Verify CEDAR files were created
ls -lh data/cedar_*.qs
```

**Expected output:**
```
data/cedar_sections.qs
data/cedar_students.qs
data/cedar_programs.qs
data/cedar_degrees.qs
data/cedar_faculty.qs
```

### Step 2: Backup Current global.R

```bash
cp global.R global-LEGACY-backup.R
```

### Step 3: Deploy Updated global.R

```bash
# Replace global.R with CEDAR version
cp global-CEDAR.R global.R
```

### Step 4: Test Locally

```bash
# Start R and test data loading
R
```

```r
# In R console:
source("global.R")

# Should see validation messages:
# [global.R] ✓ DESRs validated: 274772 rows, 34 columns
# [global.R] ✓ class_lists validated: 1846801 rows, 26 columns
# [global.R] ✓ academic_studies validated: 466973 rows, 8 columns
# [global.R] ✓ degrees validated: 62616 rows, 20 columns
# [global.R] ✓ cedar_faculty validated: XXXXX rows, X columns
# [global.R] ✅ All CEDAR data validated successfully
```

### Step 5: Update course-report.R

```r
# Edit R/cones/course-report.R
# Change line 26 from:
hr_data <- data_objects[["hr_data"]]

# To:
cedar_faculty <- data_objects[["cedar_faculty"]]

# Update all references throughout the file:
# hr_data -> cedar_faculty
# job_cat -> job_category
```

### Step 6: Test Application

```bash
# Run Shiny app locally
R -e "shiny::runApp()"
```

**Test checklist:**
- [ ] App starts without errors
- [ ] Department reports load successfully
- [ ] Course reports load successfully
- [ ] Headcount section works
- [ ] Credit hours section works
- [ ] Degrees section works
- [ ] Enrollment section works
- [ ] No references to legacy column names in errors

### Step 7: Create _small Versions (Optional)

For faster dev/test cycles:

```r
# Create small versions of CEDAR files
library(tidyverse)
library(qs)

# Sections - sample 10% of rows
sections <- qread("data/cedar_sections.qs")
sections_small <- sections %>% slice_sample(prop = 0.1)
qsave(sections_small, "data/cedar_sections_small.qs")

# Students - sample 10% of rows
students <- qread("data/cedar_students.qs")
students_small <- students %>% slice_sample(prop = 0.1)
qsave(students_small, "data/cedar_students_small.qs")

# Programs - sample 10% of rows
programs <- qread("data/cedar_programs.qs")
programs_small <- programs %>% slice_sample(prop = 0.1)
qsave(programs_small, "data/cedar_programs_small.qs")

# Degrees - sample 10% of rows
degrees <- qread("data/cedar_degrees.qs")
degrees_small <- degrees %>% slice_sample(prop = 0.1)
qsave(degrees_small, "data/cedar_degrees_small.qs")

# Faculty - sample 10% of rows
faculty <- qread("data/cedar_faculty.qs")
faculty_small <- faculty %>% slice_sample(prop = 0.1)
qsave(faculty_small, "data/cedar_faculty_small.qs")
```

Then in `config/shiny_config.R`:
```r
cedar_use_small_data <- TRUE  # Use _small files for dev/test
```

## Breaking Changes

### For Users

**None** - Users interact with the Shiny UI, which is unchanged.

### For Developers

1. **Data Files Must Be in CEDAR Format**
   - Application will not start if CEDAR validation fails
   - Clear error messages show exactly what's missing

2. **hr_data Variable Removed**
   ```r
   # BEFORE (global.R):
   hr_data <- data_objects[["hr_data"]]

   # AFTER:
   cedar_faculty <- data_objects[["cedar_faculty"]]
   ```

3. **File Names Changed**
   - Must use `cedar_*.qs` file names
   - Transformation scripts required for legacy data

### For Docker Deployment

**No changes needed** - Docker deployment already uses data_dir path, just needs:
1. CEDAR-formatted data files in `/srv/shiny-server/cedar/data/`
2. Files named with `cedar_*` prefix

## Validation Examples

### Success Case

```
[global.R] Loading DESRs from CEDAR file: cedar_sections (use_small: FALSE)...
[global.R] Data path: /path/to/data/cedar_sections.qs
loading cedar_sections.qs...
[global.R] Loaded cedar_sections.qs in 2.34 seconds.
[global.R] ✓ DESRs validated: 274772 rows, 34 columns

[global.R] Loading class_lists from CEDAR file: cedar_students (use_small: FALSE)...
[global.R] Data path: /path/to/data/cedar_students.qs
loading cedar_students.qs...
[global.R] Loaded cedar_students.qs in 8.12 seconds.
[global.R] ✓ class_lists validated: 1846801 rows, 26 columns

[global.R] ✅ All CEDAR data validated successfully
```

### Failure Case - Missing Columns

```
[global.R] Loading class_lists from CEDAR file: cedar_students...
loading cedar_students.qs...
[global.R] Loaded cedar_students.qs in 8.12 seconds.
Error: [global.R] class_lists is missing required CEDAR columns: subject_code, level, major
  Expected CEDAR format with lowercase column names.
  Found columns: student_id, term, department, grade, credits, ...
  Run CEDAR transformation scripts to create properly formatted data.
```

**Fix:** Run transformation script to add missing columns:
```bash
Rscript R/transform-students-to-cedar.R
```

### Failure Case - File Not Found

```
[global.R] Loading cedar_faculty from CEDAR file: cedar_faculty...
[global.R] Data path: /path/to/data/cedar_faculty.qs
Error in qread("data/cedar_faculty.qs"): file.exists(file) is not TRUE
```

**Fix:** Create CEDAR faculty file:
```bash
Rscript R/transform-hr-to-cedar.R
```

## Rollback Plan

If issues arise after deployment:

```bash
# Restore legacy global.R
cp global-LEGACY-backup.R global.R

# Restart Shiny app
# App will load legacy data files again
```

**Note:** This requires legacy data files (DESRs.qs, class_lists.qs, hr_data.Rds) to still exist.

## Benefits of CEDAR Migration

### 1. Data Quality Assurance
- ✅ Validation happens at startup, not at runtime
- ✅ Clear error messages guide troubleshooting
- ✅ Prevents silent failures from missing columns

### 2. Consistency
- ✅ All data in uniform CEDAR format
- ✅ Column naming conventions enforced
- ✅ No mixed legacy/CEDAR data

### 3. Maintainability
- ✅ Explicit file naming makes data provenance clear
- ✅ Transformation scripts document data pipeline
- ✅ Easier to onboard new developers

### 4. Performance
- ✅ QS format faster than RDS
- ✅ Consistent column types across datasets
- ✅ Smaller file sizes with optimized formats

## Next Steps

1. **Check Transformation Scripts**
   ```bash
   ls R/transform-*-to-cedar.R
   ```
   - Identify which scripts exist
   - Create missing scripts as needed

2. **Run Transformations**
   - Execute scripts to create CEDAR data files
   - Verify column structure matches validation specs

3. **Test with Small Data**
   - Set `cedar_use_small_data <- TRUE` in config
   - Create `_small` versions for testing
   - Verify app functionality

4. **Update course-report.R**
   - Change `hr_data` to `cedar_faculty`
   - Update column references

5. **Deploy to Production**
   - Backup current global.R
   - Deploy updated global.R
   - Monitor for issues

## Related Documentation

- [CREDIT-HOURS-CEDAR-MIGRATION.md](CREDIT-HOURS-CEDAR-MIGRATION.md) - Credit hours migration
- [HEADCOUNT-DEPT-REPORT-INTEGRATION.md](HEADCOUNT-DEPT-REPORT-INTEGRATION.md) - Headcount integration
- [FINAL-SESSION-SUMMARY.md](FINAL-SESSION-SUMMARY.md) - Previous session summary

---

**Status:** 🟡 Ready for Implementation
**Priority:** High - Enables full CEDAR migration
**Estimated Effort:** 2-4 hours (depending on transformation scripts needed)
