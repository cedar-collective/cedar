# Code Review: enrl.R

## Executive Summary

**Overall Assessment**: The code is functional but has significant inconsistencies in documentation, messaging, code style, and structure. Recommend refactoring for maintainability and consistency.

**Priority Issues**:
1. **Inconsistent function documentation** (some roxygen, some none, some incomplete)
2. **Inconsistent messaging style** (some with [enrl.R] prefix, some without)
3. **Dead/commented code** throughout file
4. **Spacing and formatting inconsistencies**
5. **Mixed code styles** (some functions well-structured, others not)

**Strengths**:
- Core logic is sound after CEDAR migration
- Good use of dplyr pipelines
- Includes helpful inline comments
- Last 3 functions have excellent roxygen documentation

---

## 1. Documentation Issues

### 1.1 Inconsistent Roxygen Documentation

**Problem**: Only 4 of 10 functions have roxygen documentation, and quality varies greatly.

| Function | Has Roxygen? | Quality |
|----------|-------------|---------|
| `calc_cl_enrls` | ✅ Yes | Excellent - complete with @param, @return, @details, @examples |
| `compress_aop_pairs` | ❌ No | None |
| `summarize_courses` | ❌ No | Only inline comment |
| `aggregate_courses` | ❌ No | Only inline comment |
| `get_enrl_for_dept_report` | ❌ No | None |
| `make_enrl_plot_from_cls` | ❌ No | None |
| `make_enrl_plot` | ❌ No | Only inline comment |
| `get_enrl` | ❌ No | **Main function, no docs!** |
| `get_low_enrollment_courses` | ✅ Yes | Good - has @param, @return |
| `get_course_enrollment_history` | ✅ Yes | Good - complete documentation |
| `format_enrollment_history` | ✅ Yes | Good - complete documentation |

**Recommendation**: Add consistent roxygen docs to all functions, especially `get_enrl` (the main entry point).

### 1.2 Outdated Documentation

**Line 608**: Still references old column name `TERM` in roxygen
```r
#' @return Data frame with TERM and enrolled columns
```
Should be: `term` (lowercase)

**Line 6**: Parameter name mismatch
```r
#' @param students A data frame...
```
But function signature is:
```r
calc_cl_enrls <- function(filtered_students, reg_status = NULL)
```

---

## 2. Messaging Inconsistencies

### 2.1 Inconsistent Message Prefixes

Some functions use `[enrl.R]` prefix, others don't:

**With `[enrl.R]` prefix** (consistent):
- Lines 35, 38, 44, 49, 55, 60, etc. in `calc_cl_enrls()`
- Lines 174, 180, 186, 190 in `summarize_courses()`
- Lines 207, 210, 214, 219 in `aggregate_courses()`
- Lines 292, 325, etc. in plotting functions
- Lines 411, 421, 427, 432, etc. in `get_enrl()`
- Lines 525, 537, 541, 548, 562 in `get_low_enrollment_courses()`

**WITHOUT `[enrl.R]` prefix** (inconsistent):
- Lines 118, 163 in `compress_aop_pairs()`
- Lines 228, 238 in `get_enrl_for_dept_report()`
- Lines 581, 599 in `get_course_enrollment_history()`

**Recommendation**: Use `[enrl.R]` prefix consistently in ALL message() calls, or remove it from all.

### 2.2 Message Capitalization Inconsistency

- Line 228: `"welcome to get_enrl_for_dept_report!"` (lowercase)
- Line 35: `"[enrl.R] Welcome to calc_cl_enrls!"` (capitalized)
- Line 411: `"[enrl.R] Welcome to get_enrl!"` (capitalized)

**Recommendation**: Standardize to either "Welcome" or "Starting" with consistent capitalization.

---

## 3. Code Style Issues

### 3.1 Spacing Inconsistencies

**Function definitions**:
```r
compress_aop_pairs <- function (courses,opt) {      # Line 117 - space before (
calc_cl_enrls <- function(filtered_students, ...)  # Line 23 - no space
get_enrl <- function (courses,opt,group_cols=NULL) # Line 401 - space before (, missing spaces around =
```

**Recommendation**: Standardize to `function(args)` (no space before parenthesis, spaces around `=`).

**Around operators**:
```r
summarize(count = n(), .groups="keep")  # Line 46 - no space around =
mutate(mean = round(mean(count),digits=1))  # Line 51 - inconsistent spacing
group_cols <- c(...)  # Line 179 - spaces around =
```

**Recommendation**: Always use spaces around `=` in function calls.

**Pipeline operators**:
```r
courses <- courses %>%  group_by(...)  # Line 129 - extra spaces
courses <- courses %>% filter(...)     # Line 132 - single space (good)
```

**Recommendation**: Consistent single space around `%>%`.

### 3.2 Commented Code Throughout File

**Dead code that should be removed**:
- Lines 25-31: Testing code in `calc_cl_enrls`
- Lines 120-125: Testing code in `compress_aop_pairs`
- Lines 149-150: Commented print statements
- Lines 294-299: Testing code in `make_enrl_plot_from_cls`
- Lines 327-332: Testing code in `make_enrl_plot`
- Lines 392: Commented return statement
- Lines 403-410: Testing code in `get_enrl`
- Lines 527-533: Testing code in `get_low_enrollment_courses`
- Lines 559-560: Testing code

**Recommendation**: Remove all commented testing code. Use proper test files instead (which we now have!).

### 3.3 Return Statement Style

Inconsistent spacing in return statements:
```r
return (reg_stats_summary)  # Line 113 - space before (
return(summary)             # Line 201 - no space (correct)
return (plots)              # Line 395 - space before (
return(courses)             # Line 505 - no space (correct)
```

**Recommendation**: Standardize to `return(value)` (no space).

### 3.4 Inconsistent Comment Style

Multiple comment styles throughout:
```r
# get distinct rows within courses...     # Line 37 - lowercase, ellipsis
# count students in each term...          # Line 43 - lowercase, ellipsis
# for clarity, combine aop and...         # Line 127 - lowercase, ellipsis
# Main summary across sections            # Line 189 - capitalized, no ellipsis
# Validate input                          # Line 337 - capitalized, no ellipsis
### AOP COMPRESSION                       # Line 471 - ALL CAPS, triple ###
###################################       # Lines 400, 510 - Section dividers
############# aggregate function...       # Line 205 - Many # symbols
```

**Recommendation**: Use consistent comment style:
- Single `#` for inline comments
- Double `##` for subsection headers
- Triple `###` for major section headers
- Capitalize first word, end with period (not ellipsis)

---

## 4. Structural Issues

### 4.1 Function Organization

File organization is somewhat logical but could be improved:

**Current order**:
1. `calc_cl_enrls` (student-level)
2. `compress_aop_pairs` (helper)
3. `summarize_courses` (helper)
4. `aggregate_courses` (wrapper)
5. `get_enrl_for_dept_report` (specialized)
6. `make_enrl_plot_from_cls` (plotting)
7. `make_enrl_plot` (plotting)
8. `get_enrl` (MAIN FUNCTION - should be earlier!)
9. `get_low_enrollment_courses` (specialized)
10. `get_course_enrollment_history` (helper)
11. `format_enrollment_history` (helper)

**Recommended order**:
1. Main public functions first (`get_enrl`, `calc_cl_enrls`)
2. Specialized public functions (`get_low_enrollment_courses`, `get_enrl_for_dept_report`)
3. Helper/internal functions (`summarize_courses`, `aggregate_courses`, `compress_aop_pairs`)
4. Plotting functions (grouped together)
5. Utility functions (`format_enrollment_history`)

**Recommendation**: Reorganize with clear section headers.

### 4.2 Function Complexity

`get_enrl()` is the main entry point but is quite complex (107 lines):
- Handles defaults
- Validates old parameters
- Filters data
- Dynamically builds column lists
- Handles missing columns
- Compresses AOP courses
- Selects columns
- Removes duplicates
- Optionally aggregates

**Recommendation**: Consider breaking into smaller functions:
- `validate_enrl_options()` - Handle defaults and validation
- `prepare_enrl_columns()` - Handle column selection and missing columns
- `get_enrl()` - Main orchestration (much simpler)

---

## 5. Logic/Behavior Issues

### 5.1 Unused Parameter

**Line 401**: `group_cols=NULL` parameter
```r
get_enrl <- function (courses,opt,group_cols=NULL) {
```

This parameter is **never used** in the function body. The function uses `opt$group_cols` instead.

**Recommendation**: Remove unused parameter or document why it exists.

### 5.2 Redundant else if

**Line 106**:
```r
else if (!is.null(reg_status)) {
```

This is redundant since we're already in an `else` block. Should just be `else`.

### 5.3 Magic Numbers

**Throughout file**: Hard-coded status codes and values
```r
c("RE","RS")    # Line 61 - What are these?
c("DR")         # Line 65 - Early drop code
c("DG","DW")    # Line 70 - Late drop codes
c("WL")         # Line 80 - Waitlist code
"MOPS"          # Line 132 - What does this mean?
"0"             # Line 137 - Crosslist indicator
```

**Recommendation**: Define these as named constants at the top of the file:
```r
# Registration status codes
REG_CODES_REGISTERED <- c("RE", "RS")
REG_CODES_EARLY_DROP <- c("DR")
REG_CODES_LATE_DROP <- c("DG", "DW")
REG_CODE_WAITLIST <- "WL"

# Delivery method codes
DELIVERY_METHOD_AOP <- "MOPS"  # All Online Programs

# Crosslist indicators
CROSSLIST_NONE <- "0"
```

### 5.4 Inconsistent NA Handling

- Line 92: Uses `[is.na(...)] <- 0` (base R)
- Throughout: Uses `coalesce()` for NA handling (tidyverse)

**Recommendation**: Use consistent approach (prefer tidyverse `replace_na()` or `coalesce()`).

---

## 6. Specific Function Issues

### 6.1 `calc_cl_enrls()` (Lines 23-114)

**Issues**:
- Parameter name mismatch in docs (`students` vs `filtered_students`)
- Very long function (92 lines) doing multiple things
- Uses `merge()` repeatedly (can be slow with large data)
- Variable name `de` (line 65) is cryptic

**Strengths**:
- Excellent roxygen documentation
- Clear message progression
- Good use of filter/summarize pipeline

**Recommendations**:
- Rename parameter to `students` to match docs, or update docs
- Consider using `left_join()` instead of `merge()`
- Use descriptive names: `drops_early` instead of `de`

### 6.2 `compress_aop_pairs()` (Lines 117-166)

**Issues**:
- **No roxygen documentation**
- Unclear what "AOP" means without context (All Online Programs)
- Complex logic that's hard to follow
- Dead testing code (lines 120-125)

**Strengths**:
- Inline comments explain steps
- Handles edge cases (no partner)

**Recommendations**:
- Add full roxygen documentation
- Define AOP acronym in docs
- Remove testing code
- Add example of what compression does

### 6.3 `summarize_courses()` (Lines 173-202)

**Issues**:
- **No roxygen documentation**
- Only brief inline comment
- Uses deprecated `group_by_at()` (line 191)

**Strengths**:
- Clean pipeline
- Good default handling
- Informative messages

**Recommendations**:
- Add roxygen docs
- Migrate `group_by_at()` to `group_by(across(all_of(...)))`
- Explain what xl_sections vs reg_sections means

### 6.4 `aggregate_courses()` (Lines 206-222)

**Issues**:
- **No roxygen documentation**
- Seems like an unnecessary wrapper around `summarize_courses()`
- Stops execution with error if group_cols is null (harsh!)

**Question**: Is this function even needed? It just calls `summarize_courses()` and validates one parameter.

**Recommendations**:
- Consider removing and calling `summarize_courses()` directly
- OR document why wrapper exists
- Change `stop()` to warning and return empty data frame

### 6.5 `get_enrl_for_dept_report()` (Lines 226-288)

**Issues**:
- **No roxygen documentation**
- Creates plots inside data function (mixing concerns)
- Hard-coded "since 2019" in axis labels (line 252, 261)
- Commented out title code (lines 248, 257, 270)
- Modifies input parameter `d_params` and returns it (side effects)

**Strengths**:
- Creates useful visualizations
- Good use of ggplotly for interactivity

**Recommendations**:
- Add roxygen docs
- Split into separate functions: `get_enrl_summary()` and `create_enrl_plots()`
- Remove or parameterize "since 2019"
- Document what `d_params` is and its expected structure

### 6.6 `make_enrl_plot_from_cls()` (Lines 291-319)

**Issues**:
- **No roxygen documentation**
- Unclear what "cls" means (class lists?)
- Dead testing code (lines 294-299)
- Returns `plots$cl_enrl` twice (line 316 and implicitly via return)

**Recommendations**:
- Add roxygen docs explaining cls vs regular enrollment
- Remove testing code
- Remove line 316 (redundant)

### 6.7 `make_enrl_plot()` (Lines 324-396)

**Issues**:
- **No roxygen documentation**
- Long function (73 lines)
- Dead testing code (lines 327-332)
- Commented code (line 392, 359)
- Comment without period on line 352

**Strengths**:
- Good input validation
- Flexible faceting options
- Informative messages

**Recommendations**:
- Add roxygen docs
- Remove dead/commented code
- Extract facet setup into separate function

### 6.8 `get_enrl()` (Lines 401-507)

**Issues**:
- **No roxygen documentation** ⚠️ **CRITICAL - This is the main function!**
- Very long (107 lines)
- Dead testing code (lines 403-410)
- Unused parameter `group_cols`
- Deprecated `group_by_at()` reference (though not directly used here)
- Complex logic mixing multiple concerns

**Strengths**:
- Robust handling of missing columns (our recent addition)
- Good default value setting
- Backward compatibility checks
- Clear progression through steps

**Recommendations**:
- **URGENT**: Add comprehensive roxygen documentation
- Remove testing code
- Remove unused `group_cols` parameter
- Extract column handling into `prepare_enrl_columns()` helper
- Extract validation into `validate_enrl_options()` helper

### 6.9 `get_low_enrollment_courses()` (Lines 524-564)

**Issues**:
- Dead testing code (lines 527-533, 559-560)
- Modifies `opt` parameter (side effects)

**Strengths**:
- **Good roxygen documentation**
- Clear logic
- Helpful comments

**Recommendations**:
- Remove testing code
- Consider copying `opt` to avoid side effects: `opt <- modifyList(opt, list(...))`

### 6.10 `get_course_enrollment_history()` (Lines 580-601)

**Issues**:
- Documentation still references old column name `TERM`

**Strengths**:
- **Excellent roxygen documentation**
- Clean, focused function
- Good use of NSE (`!!campus`, etc.)

**Recommendations**:
- Update docs to use lowercase `term`

### 6.11 `format_enrollment_history()` (Lines 611-624)

**Strengths**:
- **Excellent roxygen documentation**
- Simple, single-purpose function
- Good edge case handling

**No issues** - this is a model function!

---

## 7. Deprecated Code Issues

### 7.1 Using `group_by_at()`

**Line 191**:
```r
summary <- courses %>% ungroup() %>% group_by_at(group_cols) %>%
```

`group_by_at()` is superseded by `across()`. Should be:
```r
summary <- courses %>% ungroup() %>% group_by(across(all_of(group_cols))) %>%
```

---

## 8. Priority Recommendations

### Immediate (Critical)

1. **Add roxygen documentation to `get_enrl()`** - Main function must have docs
2. **Remove all commented/dead testing code** - Creates confusion
3. **Standardize message() prefixes** - Use `[enrl.R]` everywhere
4. **Fix parameter name mismatch** in `calc_cl_enrls()` docs

### High Priority

5. **Update `group_by_at()` to modern tidyverse** - Line 191
6. **Standardize function spacing** - `function(args)` not `function (args)`
7. **Remove unused `group_cols` parameter** from `get_enrl()`
8. **Define magic numbers as constants** - Registration codes, delivery methods
9. **Fix return statement spacing** - `return(value)` not `return (value)`

### Medium Priority

10. **Add roxygen docs to all functions** - Especially helpers
11. **Reorganize file** - Main functions first, helpers last
12. **Update old column name in docs** - `TERM` → `term`
13. **Standardize comment style** - Capitalize, use period not ellipsis
14. **Consider splitting `get_enrl()`** - Extract validation and column prep

### Low Priority

15. **Review `aggregate_courses()` necessity** - May be redundant wrapper
16. **Split `get_enrl_for_dept_report()`** - Separate data and plotting
17. **Add examples to all functions** - Show typical usage
18. **Consider using `replace_na()` consistently** - Instead of base R approach

---

## 9. Suggested Refactored Structure

```r
# ============================================================================
# ENROLLMENT ANALYSIS FUNCTIONS
# ============================================================================
#
# This file provides functions for analyzing course enrollment data in the
# CEDAR data model. Main entry point is get_enrl().

# Constants ------------------------------------------------------------------

REG_CODES_REGISTERED <- c("RE", "RS")
REG_CODES_EARLY_DROP <- c("DR")
REG_CODES_LATE_DROP <- c("DG", "DW")
REG_CODE_WAITLIST <- "WL"
DELIVERY_METHOD_AOP <- "MOPS"
CROSSLIST_NONE <- "0"

# Main Public Functions ------------------------------------------------------

#' Get Enrollment Data
#'
#' Main entry point for enrollment analysis. Filters, processes, and
#' optionally aggregates course enrollment data.
#'
#' @param courses Data frame of course sections from cedar_sections
#' @param opt List of options controlling filtering and aggregation
#' @return Data frame of enrollment data, optionally aggregated
#' @export
get_enrl <- function(courses, opt) {
  # Implementation...
}

#' Calculate Course-Level Enrollment Statistics
#' [existing excellent documentation]
calc_cl_enrls <- function(students, reg_status = NULL) {
  # Implementation...
}

# Specialized Functions ------------------------------------------------------

#' Get Low Enrollment Courses
#' [existing good documentation]
get_low_enrollment_courses <- function(courses, opt, threshold = 15) {
  # Implementation...
}

#' Get Enrollment Data for Department Report
#' [NEW documentation needed]
get_enrl_summary_for_dept <- function(courses, dept_code) {
  # Extract data logic only
}

# Helper Functions -----------------------------------------------------------

#' Summarize Courses by Group
#' [NEW documentation needed]
summarize_courses <- function(courses, opt) {
  # Implementation...
}

#' Compress AOP Course Pairs
#' [NEW documentation needed]
compress_aop_pairs <- function(courses, opt) {
  # Implementation...
}

# Validation and Preparation Helpers -----------------------------------------

validate_enrl_options <- function(opt) {
  # Extract validation logic
}

prepare_enrl_columns <- function(courses) {
  # Extract column handling logic
}

# Plotting Functions ---------------------------------------------------------

#' Create Enrollment Plots for Department Report
#' [NEW documentation needed]
create_dept_enrl_plots <- function(summary_data, d_params) {
  # Extract plotting logic
}

#' Create Enrollment Plot from Class Lists
#' [NEW documentation needed]
make_enrl_plot_from_cls <- function(reg_stats_summary, opt) {
  # Implementation...
}

#' Create Enrollment Plot
#' [NEW documentation needed]
make_enrl_plot <- function(summary, opt) {
  # Implementation...
}

# Utility Functions ----------------------------------------------------------

#' Get Enrollment History for Course
#' [existing good documentation]
get_course_enrollment_history <- function(...) {
  # Implementation...
}

#' Format Enrollment History String
#' [existing excellent documentation]
format_enrollment_history <- function(history_data) {
  # Implementation...
}
```

---

## 10. Testing Considerations

Now that we have test infrastructure, the commented testing code should be removed and proper tests should be written for:

- Edge cases (empty data, single course, etc.)
- Column handling (missing columns, computed columns)
- AOP compression logic
- Aggregation at different levels
- Plot generation (if possible)

Tests already exist for main `get_enrl()` function, but could be expanded.

---

## 11. Conclusion

**Summary of Issues**:
- 📚 Documentation: 6/10 functions lack roxygen docs, including main function
- 💬 Messaging: Inconsistent prefix usage and capitalization
- 🎨 Style: Spacing, return statements, comment style all inconsistent
- 🗑️ Dead Code: ~50 lines of commented testing code
- 🏗️ Structure: Main function buried in middle, could be better organized
- ⚠️ Deprecated: Using superseded `group_by_at()`
- 🔢 Magic Numbers: Hard-coded status codes need named constants

**Estimated Refactoring Effort**:
- **Quick wins** (2-3 hours): Remove dead code, fix spacing, add constants
- **Medium effort** (1 day): Add roxygen docs, standardize messaging
- **Larger refactor** (2-3 days): Reorganize file, split complex functions

**Recommendation**: Start with quick wins and documentation, then consider larger structural improvements over time.

The code **works correctly** after our CEDAR migration, but would benefit greatly from consistency improvements for long-term maintainability.
