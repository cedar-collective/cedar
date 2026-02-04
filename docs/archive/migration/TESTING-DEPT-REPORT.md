# Testing Department Reports

This guide explains how to test `dept-report.R` to ensure it generates all required data for the Shiny app and RMarkdown reports.

## Overview

The department report system has three main components:

1. **`set_payload(dept_code, prog_focus)`** - Creates the d_params structure with metadata
2. **`create_dept_report_data(data_objects, opt)`** - Generates all plots/tables (used by Shiny)
3. **`create_dept_report(data_objects, opt)`** - Full report generation including RMarkdown rendering

## Testing Methods

### Method 1: Standalone Test Script (Recommended for Quick Testing)

The easiest way to test is using the standalone script:

```bash
cd /Users/fwgibbs/Dropbox/projects/cedar
Rscript tests/test-dept-report-standalone.R
```

**What it does:**
- Loads your actual CEDAR data
- Runs `create_dept_report_data()` for a test department
- Validates all outputs
- Reports any issues
- Shows what plots/tables were generated

**Customize the test:**
Edit the top of `test-dept-report-standalone.R`:
```r
TEST_DEPT <- "MATH"  # Change to test different departments
TEST_PROG_FOCUS <- NULL  # Or specify like "MATH"
```

### Method 2: Interactive R Console

For exploratory testing:

```r
# Load CEDAR
source("includes/init.R")

# Load data
data_objects <- list(
  academic_studies = readRDS(paste0(cedar_data_dir, "academic_studies.Rds")),
  degrees = readRDS(paste0(cedar_data_dir, "cedar_degrees.Rds")),
  class_lists = readRDS(paste0(cedar_data_dir, "class_lists.Rds")),
  cedar_faculty = readRDS(paste0(cedar_data_dir, "cedar_faculty.Rds")),
  DESRs = readRDS(paste0(cedar_data_dir, "DESRs.Rds"))
)

# Test options
opt <- list(dept = "HIST", prog = NULL, shiny = TRUE)

# Generate data
d_params <- create_dept_report_data(data_objects, opt)

# Inspect results
str(d_params, max.level = 2)

# View specific outputs
names(d_params$tables)
names(d_params$plots)

# View a plot
d_params$plots$degree_summary_faceted_by_major_plot

# View a table
View(d_params$tables$degree_summary_filtered_program)

# Check table structure
head(d_params$tables$hc_progs_under_long_majors)
```

### Method 3: testthat Suite

For automated regression testing:

```r
# Run all dept-report tests
testthat::test_file("tests/testthat/test-dept-report.R")

# Or run entire test suite
devtools::test()
```

### Method 4: Shiny App Integration Test

Test the full Shiny workflow:

1. **Start the app:**
   ```r
   shiny::runApp()
   ```

2. **Navigate to Department Reports tab**

3. **Select a department** (e.g., "HIST")

4. **Click "Generate Report"**

5. **Verify:**
   - No errors in R console
   - Plots/tables render in UI
   - Download HTML button works

6. **Check browser console** (F12) for JavaScript errors

## What to Check

### 1. Required Outputs

Every successful dept-report should generate these outputs:

**Headcount Section:**
- `hc_progs_under_long_majors` (table)
- `hc_progs_under_long_minors` (table)
- `hc_progs_grad_long_majors` (table)
- Corresponding plots

**Degrees Section:**
- `degree_summary_faceted_by_major_plot` (plot)
- `degree_summary_filtered_program_stacked_plot` (plot)
- `degree_summary_filtered_program` (table)

**Credit Hours Section:**
- Various credit hour tables/plots

**Grades Section:**
- DFW analysis tables/plots

**Enrollment Section:**
- Enrollment trend plots/tables

**SFR Section:**
- `sfr_plot` (plot)
- SFR tables

### 2. Data Types

**Plots must be:**
- `plotly` objects (most common)
- OR `ggplot` objects
- OR `htmlwidget` objects

**Tables must be:**
- `data.frame` objects
- With appropriate columns
- Non-zero rows (if data exists for that dept)

### 3. CEDAR Naming

Verify migration to CEDAR naming:

```r
# Check dept-report.R source
dept_report_source <- readLines("R/cones/dept-report.R")

# Should use cedar_faculty (CEDAR naming)
any(grepl("cedar_faculty", dept_report_source))  # TRUE

# Should NOT use hr_data (old naming)
any(grepl('data_objects\\[\\["hr_data"\\]\\]', dept_report_source))  # FALSE
```

## Common Issues

### Issue 1: No Outputs Generated

**Symptom:** `d_params$tables` and `d_params$plots` are empty

**Causes:**
- Test department has no data
- Filters are too restrictive
- Data not in expected format

**Fix:**
- Try a different department (HIST, MATH, PHYS)
- Check that your data files have records for that dept
- Verify data column names match CEDAR conventions

### Issue 2: "cedar_faculty not found"

**Symptom:** Error about missing `cedar_faculty` in data_objects

**Fix:**
Run the transformation script:
```r
source("R/data-parsers/transform-hr-to-cedar.R")
```

This creates `cedar_faculty.Rds` from `hr_data.Rds`

### Issue 3: Plots Are NULL

**Symptom:** Plot exists in `d_params$plots` but is NULL

**Causes:**
- No data available for that visualization
- Data filtered out (e.g., no undergraduate programs)

**This is OK!** The code handles this gracefully. Plots should be NULL if no data.

### Issue 4: "Column DEPT not found"

**Symptom:** Error filtering by DEPT column

**Fix:**
dept-report.R needs updating for CEDAR naming. The class_lists data should use lowercase `department` instead of `DEPT`.

Update line 79-80 in dept-report.R:
```r
# OLD:
filtered_cl_by_dept <- data_objects[["class_lists"]] %>%
  filter(DEPT == dept_code)

# NEW (CEDAR):
filtered_cl_by_dept <- data_objects[["class_lists"]] %>%
  filter(department == dept_code)
```

### Issue 5: get_grades_for_dept_report Error

**Symptom:** Error about hr_data parameter

**Fix:**
Update line 98 in dept-report.R:
```r
# OLD:
d_params <- get_grades_for_dept_report(filtered_cl_by_dept,
                                       data_objects[["hr_data"]], opt, d_params)

# NEW:
d_params <- get_grades_for_dept_report(filtered_cl_by_dept,
                                       data_objects[["cedar_faculty"]], opt, d_params)
```

## Interpreting Results

### Good Output Example

```
=== Output Analysis ===
Tables generated (12):
  ✓ hc_progs_under_long_majors: 45 rows × 8 cols
  ✓ degree_summary_filtered_program: 30 rows × 3 cols
  ...

Plots generated (8):
  ✓ degree_summary_faceted_by_major_plot: plotly
  ✓ sfr_plot: ggplot
  ...

Total outputs: 20
✓ Report data generated successfully!
```

### Warning Output (Usually OK)

```
Tables generated (8):
  ✓ hc_progs_under_long_majors: 45 rows × 8 cols
  ⚠ hc_progs_under_long_minors: NULL
  ...
```

This means no minor data for this department - that's fine!

### Error Output (Needs Fix)

```
✗ create_dept_report_data failed!
Error: object 'hr_data' not found
```

This means you need to fix the migration to use `cedar_faculty`.

## Validation Checklist

Before considering dept-report ready:

- [ ] Standalone test runs without errors
- [ ] At least some tables/plots generated
- [ ] All plots are plotly/ggplot objects (or NULL)
- [ ] All tables are data frames (or NULL)
- [ ] Uses `cedar_faculty` not `hr_data`
- [ ] Uses CEDAR column names (lowercase, underscores)
- [ ] Works in Shiny app
- [ ] HTML download works
- [ ] testthat tests pass

## Next Steps

After testing locally:

1. **Fix any issues** found during testing
2. **Test with multiple departments** to ensure generality
3. **Test with edge cases:**
   - Department with no programs
   - Department with only graduate programs
   - Department with no degrees awarded
4. **Commit changes** with clear messages
5. **Update documentation** if behavior changed

## Need Help?

If you encounter issues:

1. Run the standalone test to get detailed diagnostics
2. Check the error messages for specific issues
3. Verify your data files exist and have correct column names
4. Review the migration summary docs (HEADCOUNT-MIGRATION-SUMMARY.md, etc.)
5. Check that all cone functions are using CEDAR naming

## Related Documentation

- **CEDAR Data Model:** `docs/data-model.md`
- **Migration Summaries:** `docs/*-MIGRATION-SUMMARY.md`
- **Cone Documentation:** Roxygen docs in `R/cones/*.R`
