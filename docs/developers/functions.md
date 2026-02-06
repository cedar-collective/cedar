---
title: Function Reference
nav_order: 4
parent: Developer Guide
---

# CEDAR Function Reference

This reference is auto-generated from roxygen2 comments in the source code.

*Generated: 2026-02-04 10:58:03.752177*

---

## credit-hours

### `get_enrolled_cr()`

*Source: credit-hours.R*

**Get Enrolled Credit Hours**

Get Enrolled Credit Hours  Analyzes credit hour enrollments for students. Returns summary statistics on student enrollment credits.

**Parameters:**

- `filtered_students` - Data frame of student enrollments (CEDAR format) Must contain columns: student_id, term, total_credits, term_type
- `courses` - List of course codes to filter (optional)
- `opt` - Options list (optional)

**Returns:** Wide-format data frame with enrollment counts by term and credit load

**Details:**

CEDAR-only function - requires CEDAR column names: - student_id (not `Student ID`) - term (not `Academic Period Code`) - total_credits (not `Total Credits`) - term_type (must be present)

**Example:**
```r
\dontrun{
enrollment_stats <- get_enrolled_cr(students, courses, opt)
}
```

---

### `get_credit_hours()`

*Source: credit-hours.R*

**Get Credit Hours Summary**

Get Credit Hours Summary  Creates a summary of earned credit hours from class lists (CEDAR format). Filters for passing grades and summarizes by term, campus, college, department, level, and subject.

**Parameters:**

- `students` - Data frame of student enrollments (CEDAR class_lists format) Must contain columns: final_grade, term, campus, college, department, level, subject_code, credits

**Returns:** Data frame with credit hours summarized by term, campus, college, department, subject, and level Includes a "total" level that aggregates across all course levels

**Details:**

CEDAR-only function - requires CEDAR column names: - final_grade (not `Final Grade`) - term (not `Academic Period Code`) - campus (not `Course Campus Code`) - college (not `Course College Code`) - department (not DEPT) - subject_code (not `Subject Code`) - credits (not `Course Credits`)  Only counts credit hours for passing grades (defined in passing_grades global).

**Example:**
```r
\dontrun{
credit_hours <- get_credit_hours(class_lists)
}
```

---

### `credit_hours_by_major()`

*Source: credit-hours.R*

**Credit Hours By Major**

Credit Hours By Major  Analyzes earned credit hours broken down by student major. Shows which majors are earning credit hours in department courses.

**Parameters:**

- `students` - Data frame of student enrollments (CEDAR class_lists format) Must contain columns: department, term, final_grade, credits, major, student_college
- `d_params` - Department parameters list containing: - dept_code: Department code to filter - term_start: Starting term (inclusive) - term_end: Ending term (inclusive) - prog_names: Vector of program names for major comparison

**Returns:** d_params list with added elements: - tables$credit_hours_data_w: Wide-format credit hours by major and term - plots$sch_outside_pct_plot: Pie chart of non-major credit hour distribution - plots$sch_dept_pct_plot: Pie chart comparing major vs non-major credit hours

**Details:**

CEDAR-only function - requires CEDAR column names: - department (not DEPT) - term (not `Academic Period Code`) - final_grade (not `Final Grade`) - credits (not `Course Credits`) - major (should be in CEDAR format) - student_college (not `Student College`)

**Example:**
```r
\dontrun{
d_params <- credit_hours_by_major(class_lists, d_params)
}
```

---

### `credit_hours_by_fac()`

*Source: credit-hours.R*

**Credit Hours By Faculty**

Credit Hours By Faculty  Analyzes credit hours taught by different faculty job categories. Shows credit hour production broken down by faculty type (tenure track, lecturer, etc.).

**Parameters:**

- `data_objects` - List containing: - class_lists: CEDAR student enrollments - cedar_faculty: CEDAR faculty data with job_category
- `d_params` - Department parameters list containing: - dept_code: Department code to filter - term_start: Starting term (inclusive) - term_end: Ending term (inclusive) - subj_codes: Subject codes for plot titles - palette: Color palette for plots

**Returns:** d_params list with added plots: - chd_by_fac_facet_plot: Bar chart faceted by course level - chd_by_fac_plot: Stacked bar chart of total credit hours

**Details:**

CEDAR-only function - requires CEDAR column names: - In class_lists: final_grade, term, department, campus, college, level, credits, instructor_id - In cedar_faculty: term, instructor_id, department, job_category

**Example:**
```r
\dontrun{
d_params <- credit_hours_by_fac(data_objects, d_params)
}
```

---

### `get_credit_hours_for_dept_report()`

*Source: credit-hours.R*

**Get Credit Hours for Department Report**

Get Credit Hours for Department Report  Main function for credit hours analysis in department reports. Creates multiple plots and tables analyzing credit hour production.

**Parameters:**

- `class_lists` - Data frame of student enrollments (CEDAR format) Must contain columns: final_grade, term, campus, college, department, level, subject_code, credits
- `d_params` - Department parameters list containing: - term_start: Starting term (inclusive) - term_end: Ending term (inclusive) - dept_code: Department code to filter - subj_codes: Subject codes for filtering - palette: Color palette for plots

**Returns:** d_params list with added elements: - plots$college_credit_hours_plot: Bar chart of college credit hours - plots$college_credit_hours_comp_plot: Department vs college comparison - plots$college_dept_dual_plot: Dual y-axis comparison plot - plots$chd_by_year_facet_subj_plot: Credit hours faceted by subject - plots$chd_by_year_subj_plot: Credit hours stacked by subject - plots$chd_by_period_plot: Credit hours by course level - tables$chd_by_period_table: Credit hours table by period

**Details:**

CEDAR-only function - requires CEDAR column names: - term (not `Academic Period Code`) - campus (not `Course Campus Code`) - college (not `Course College Code`) - department (not DEPT) - subject_code (not `Subject Code`) - All lowercase with underscores

**Example:**
```r
\dontrun{
d_params <- get_credit_hours_for_dept_report(class_lists, d_params)
}
```

---

## datatable_helpers

### `apply_column_colors()`

*Source: datatable_helpers.R*

**Apply color coding to a column using preset or custom scheme**

**Parameters:**

- `dt` - A DT::datatable object
- `column` - Character string of column name to color code
- `scheme` - Character name of preset scheme OR list with thresholds/colors/reverse_scale
- `bold` - Logical, if TRUE makes the column text bold

**Returns:** Modified datatable object with color formatting applied

**Example:**
```r
# Using preset scheme
dt %>% apply_column_colors("avail", "availability")

# Using custom scheme
dt %>% apply_column_colors("my_col", list(
  thresholds = c(10, 20),
  colors = c('red', 'yellow', 'green'),
  reverse_scale = FALSE
))
```

---

### `create_styled_datatable()`

*Source: datatable_helpers.R*

**Create a styled datatable with automatic color coding**

Create a styled datatable with automatic color coding  Applies color schemes based on column names matching preset patterns. Can also accept custom column-to-scheme mappings.

**Parameters:**

- `data` - Data frame to display
- `column_schemes` - Named list mapping column names to scheme names or NULL for auto-detection
- `pageLength` - Integer, number of rows per page (default 50)

**Returns:** Styled datatable object

**Example:**
```r
# Auto-detect columns
create_styled_datatable(my_data)

# Custom mappings
create_styled_datatable(my_data, column_schemes = list(
  "seats_left" = "availability",
  "students" = "enrollment"
))
```

---

## degrees

### `count_degrees()`

*Source: degrees.R*

**Count Degrees Awarded**

Count Degrees Awarded  Counts degrees awarded by term, major, and degree type. Filters for relevant programs using the major_to_program_map and handles both first and second majors.

**Parameters:**

- `degrees_data` - Data frame with degree award data (CEDAR naming conventions). Must include columns: term, student_id, student_college, department, program_code, award_category, degree, major, major_code, second_major, first_minor, second_minor.

**Returns:** Data frame with columns: - `term` (integer) - Term code - `major` (string) - Major name - `degree` (string) - Degree type (BA, BS, MA, MS, PhD, etc.) - `majors` (integer) - Count of degrees awarded

**Details:**

This function: 1. Selects relevant columns from degrees data 2. Removes duplicate rows (due to student attributes in source data) 3. Filters for programs defined in major_to_program_map 4. Counts degrees by term, major, and degree type  The function intentionally does NOT filter by college to capture students from other colleges who have an A&S program as a second major, certificate, etc.  **Note:** Summarization uses the `major` field rather than `major_code` to avoid variations like "PSY" vs "PSYC". The major field is more reliable due to standardized mappings.  **TODO:** Currently optimized for A&S degrees. Make useful for all colleges. **TODO:** Determine handling of minors, certificates, and other non-degree programs.

**Example:**
```r
\dontrun{
# Load degrees data
degrees <- readRDS(paste0(cedar_data_dir, "cedar_degrees.Rds"))

# Count degrees awarded
degree_summary <- count_degrees(degrees)

# View most recent term
degree_summary %>%
  filter(term == max(term)) %>%
  arrange(desc(majors))
}

```

---

### `get_degrees_for_dept_report()`

*Source: degrees.R*

**Generate Degree Visualizations for Department Report**

Generate Degree Visualizations for Department Report  Prepares degree analysis data, plots, and tables for department reports. Creates visualizations showing degrees awarded over time, broken down by major and degree type.

**Parameters:**

- `degrees_data` - Data frame with degree award data (CEDAR naming conventions). See `count_degrees()` for required columns.
- `d_params` - List containing department report parameters. Required fields: - `term_start` (integer) - Starting term code (e.g., 201980) - `term_end` (integer) - Ending term code (e.g., 202580) - `prog_names` (character vector) - Program names to include (e.g., c("Mathematics", "Physics")) - `prog_codes` (character vector) - Program codes for plot titles - `dept_name` (string) - Department name for plot titles - `palette` (string) - ColorBrewer palette name for plots - `plots` (list) - Existing plots list (will be updated) - `tables` (list) - Existing tables list (will be updated)

**Returns:** Updated d_params list with new plots and tables added:  **Plots added:** - `degree_summary_faceted_by_major_plot` - Faceted line chart showing degrees awarded over time for each major/degree type combination - `degree_summary_filtered_program_stacked_plot` - Stacked bar chart showing total degrees awarded by degree type across all programs  **Tables added:** - `degree_summary_filtered_program` - Summary table with columns: term, degree, majors_total

**Details:**

This function: 1. Calls `count_degrees()` to get degree counts 2. Filters by term range (term_start to term_end) 3. Filters by program names from d_params 4. Creates faceted line chart (one facet per major) 5. Creates stacked bar chart (aggregated across programs) 6. Adds plots and tables to d_params object  **Visualizations:** - **Faceted line chart**: Shows trends for each major separately, colored by degree type. Useful for seeing how individual programs grow/shrink over time. - **Stacked bar chart**: Shows overall degree production by type, aggregated across all programs. Useful for seeing department-wide trends.  Both plots are converted to interactive plotly objects for better exploration.

**Example:**
```r
\dontrun{
# Load data
degrees <- readRDS(paste0(cedar_data_dir, "cedar_degrees.Rds"))

# Set up parameters
d_params <- list(
  term_start = 201980,
  term_end = 202580,
  prog_names = c("Mathematics", "Applied Mathematics"),
  prog_codes = c("MATH", "AMAT"),
  dept_name = "Mathematics & Statistics",
  palette = "Set2",
  plots = list(),
  tables = list()
)

# Generate visualizations
d_params <- get_degrees_for_dept_report(degrees, d_params)

# Access outputs
faceted_plot <- d_params$plots$degree_summary_faceted_by_major_plot
stacked_plot <- d_params$plots$degree_summary_filtered_program_stacked_plot
degree_table <- d_params$tables$degree_summary_filtered_program
}

```

---

## dept-report

### `set_payload()`

*Source: dept-report.R*

**Initialize Department Report Parameters**

Initialize Department Report Parameters  Creates the d_params structure with department metadata, program mappings, and empty containers for tables and plots. This is the first step in department report generation.

**Parameters:**

- `dept_code` - Character. Department code (e.g., "HIST", "MATH")
- `prog_focus` - Character or NULL. Optional program code to focus on a specific program within the department (e.g., "HIST" for History major only)

**Returns:** List containing: - `dept_code` - Department code - `dept_name` - Full department name - `subj_codes` - Subject codes associated with department - `prog_focus` - Program focus (if specified) - `prog_names` - Program names from major_to_program_map - `prog_codes` - Program codes - `tables` - Empty list (will be populated by cone functions) - `plots` - Empty list (will be populated by cone functions) - `term_start` - Start term from config - `term_end` - End term from config - `palette` - Color palette from config

**Details:**

Uses global mapping variables: - `prgm_to_dept_map` - Maps program codes to departments - `major_to_program_map` - Maps major names to program codes - `subj_to_dept_map` - Maps subject codes to departments - `dept_code_to_name` - Maps department codes to full names

**Example:**
```r
\dontrun{
# All programs in History department
d_params <- set_payload("HIST")

# Focus on specific program
d_params <- set_payload("HIST", prog_focus = "HIST")
}

```

---

### `create_dept_report_data()`

*Source: dept-report.R*

**Generate Department Report Data (Interactive)**

Generate Department Report Data (Interactive)  Generates all tables and plots for department reports by calling individual cone functions (headcount, degrees, credit hours, grades, enrollment, SFR). This function is used by the Shiny app for interactive report generation.

**Parameters:**

- `data_objects` - List containing required data sources: - `academic_studies` - Student program enrollment (headcount) - `degrees` - Graduate data with CEDAR naming (cedar_degrees) - `class_lists` - Course enrollment data (credit hours, grades) - `cedar_faculty` - Faculty HR data with CEDAR naming (SFR, DFW analysis) - `DESRs` - Demand-enrollment data (enrollment trends)
- `opt` - Options list with: - `dept` (required) - Department code (e.g., "HIST") - `prog` (optional) - Program focus code - `shiny` (optional) - Boolean indicating Shiny context

**Returns:** d_params list with populated tables and plots: - All fields from `set_payload()` - `tables` - Named list of data frames from all analyses - `plots` - Named list of plotly/ggplot objects from all analyses

**Details:**

**Processing workflow:** 1. Calls `set_payload()` to initialize structure 2. Headcount: `get_headcount_data_for_dept_report()` 3. Degrees: `get_degrees_for_dept_report()` 4. Credit Hours: `get_credit_hours_for_dept_report()`, `credit_hours_by_major()`, `credit_hours_by_fac()` 5. Grades: `get_grades_for_dept_report()` (DFW analysis) 6. Enrollment: `get_enrl_for_dept_report()` 7. SFR: `get_sfr_data_for_dept_report()`  **CEDAR Migration Notes:** - Uses CEDAR dataset keys exclusively: cedar_faculty, cedar_students, cedar_programs, cedar_sections, cedar_degrees - No legacy fallbacks; all data must be in CEDAR format with lowercase column names - Requires `department` column (CEDAR) in cedar_students for filtering  **Typical outputs include:** - Headcount tables/plots by program and level - Degree award trends by major and type - Credit hour production by term - DFW rates by course and instructor type - Enrollment trends by term type - Student-faculty ratios over time

**Example:**
```r
\dontrun{
# Load data (CEDAR naming only)
data_objects <- list(
  cedar_programs = readRDS(paste0(cedar_data_dir, "cedar_programs.Rds")),
  cedar_degrees = readRDS(paste0(cedar_data_dir, "cedar_degrees.Rds")),
  cedar_students = readRDS(paste0(cedar_data_dir, "cedar_students.Rds")),
  cedar_faculty = readRDS(paste0(cedar_data_dir, "cedar_faculty.Rds")),
  cedar_sections = readRDS(paste0(cedar_data_dir, "cedar_sections.Rds"))
)

# Generate report data
opt <- list(dept = "HIST", shiny = TRUE)
d_params <- create_dept_report_data(data_objects, opt)

# Access outputs
names(d_params$tables)
names(d_params$plots)
d_params$plots$degree_summary_faceted_by_major_plot
}

```

---

## enrl

### `compress_aop_pairs()`

*Source: enrl.R*

**Compress AOP Course Pairs**

Compress AOP Course Pairs  Compresses paired AOP (All Online Programs) course sections into single rows. AOP courses typically consist of a MOPS (Modular Online Pair Section) and a paired online section that are crosslisted. This function combines them into a single row for cleaner reporting and analysis.

**Parameters:**

- `courses` - Data frame of course sections. Must include columns: term, crosslist_code, delivery_method, crn, enrolled, total_enrl
- `opt` - Options list (currently unused but kept for consistency)

**Returns:** Data frame with AOP pairs compressed. Non-AOP courses are unchanged. Compressed rows have: \itemize{ \item \code{enrolled} = total_enrl (combined enrollment) \item \code{sect_enrl} = enrollment of kept section \item \code{pair_enrl} = enrollment of merged partner section }

**Details:**

The compression process: \enumerate{ \item Identifies MOPS delivery method courses (AOP sections) \item Filters for crosslisted AOP courses (crosslist_code != "0") \item Groups paired sections by term and crosslist_code \item Keeps first section (by delivery_method sort order) \item Combines enrollment: sets enrolled = total_enrl for kept row \item Adds sect_enrl and pair_enrl columns showing split \item Merges back with non-AOP courses }  AOP sections without a crosslisted partner are left as single sections.

**Example:**
```r
\dontrun{
# Compress AOP pairs in filtered course data
opt <- list(dept = "BIOL", term = "202510")
courses_filtered <- filter_DESRs(cedar_sections, opt)
courses_compressed <- compress_aop_pairs(courses_filtered, opt)
}

```

---

### `summarize_courses()`

*Source: enrl.R*

**Summarize Courses by Grouping Columns**

Summarize Courses by Grouping Columns  Generic summary function that aggregates course section data by specified grouping columns. Calculates section counts, enrollment statistics, and availability metrics.

**Parameters:**

- `courses` - Data frame of course sections. Must include columns used in grouping plus: enrolled, crosslist_code, available, waitlist_count
- `opt` - Options list containing: \itemize{ \item \code{group_cols} - Character vector of column names to group by. If NULL, uses default: campus, college, term, term_type, subject, subject_course, course_title, level, gen_ed_area }

**Returns:** Data frame summarized by group_cols with columns: \describe{ \item{sections}{Total number of sections in group} \item{xl_sections}{Number of crosslisted sections (crosslist_code != "0")} \item{reg_sections}{Number of regular (non-crosslisted) sections} \item{avg_size}{Average enrollment per section (rounded to 1 decimal)} \item{enrolled}{Total enrollment across all sections} \item{avail}{Total available seats across all sections} \item{waiting}{Total waitlist count across all sections} } Plus all columns specified in group_cols.

**Details:**

This function replaces many previous aggregation variants by providing a flexible grouping mechanism. Group by course_title to differentiate topics courses that share the same subject_course code.  The function uses \code{group_by_at} with dynamic column selection, making it adaptable to different analysis needs (e.g., department-level, course-level, section-level summaries).

**Example:**
```r
\dontrun{
# Summarize by course across all terms
opt <- list(group_cols = c("subject_course", "course_title"))
summary <- summarize_courses(cedar_sections, opt)

# Summarize by department and term (default grouping)
opt <- list(group_cols = NULL)  # Uses default
summary <- summarize_courses(cedar_sections, opt)
}

```

---

### `aggregate_courses()`

*Source: enrl.R*

**Aggregate Courses (Wrapper)**

Aggregate Courses (Wrapper)  Wrapper function that validates group_cols parameter and calls summarize_courses(). This function ensures that aggregation is only attempted when grouping columns are specified.

**Parameters:**

- `courses` - Data frame of course sections
- `opt` - Options list. Must contain \code{group_cols} element with column names

**Returns:** Data frame aggregated by group_cols (see \code{\link{summarize_courses}})

**Details:**

This is primarily a validation wrapper. It stops execution with an error if group_cols is NULL, ensuring the caller provides explicit grouping instructions.

---

### `get_enrl_for_dept_report()`

*Source: enrl.R*

**Get Enrollment Summary and Plots for Department Report**

Get Enrollment Summary and Plots for Department Report  Creates enrollment analysis and visualizations for department reports. Aggregates enrollment data by course, generates top enrollment charts, and produces class size distribution histograms. The plots are added to the d_params object for use in automated department reports.

**Parameters:**

- `courses` - Data frame of course sections from cedar_sections table.
- `d_params` - Department parameters list containing: \itemize{ \item \code{dept_code} - Department code to analyze \item \code{palette} - Color palette for plots (e.g., "Set2", "Dark2") \item \code{plots} - Named list where enrollment plots will be added }

**Returns:** Modified d_params list with three new plots added to d_params$plots: \itemize{ \item \code{highest_total_enrl_plot} - Bar chart of top 10 courses by total enrollment \item \code{highest_mean_enrl_plot} - Bar chart of top 10 courses by average section size \item \code{highest_mean_histo_plot} - Histogram of average class sizes by course level }

**Details:**

This function performs the following steps: \enumerate{ \item Builds opt list with department filter and default grouping columns \item Calls \code{get_enrl()} to filter and aggregate enrollment data \item Identifies top 10 courses by total and average enrollment \item Creates bar charts for highest enrollment courses \item Creates histogram of class size distribution by level \item Converts histogram to interactive plotly widget \item Adds all plots to d_params$plots list }  Default grouping columns are: subject, subject_course, course_title, level, gen_ed_area  Note: AOP (All Online Programs) courses are compressed by default (opt$x = "compress").

**Example:**
```r
\dontrun{
# Typical usage in department report workflow
d_params <- list(
  dept_code = "ENGL",
  palette = "Set2",
  plots = list()
)
d_params <- get_enrl_for_dept_report(cedar_sections, d_params)
# d_params$plots now contains three enrollment visualizations
}

```

---

### `make_enrl_plot_from_cls()`

*Source: enrl.R*

**Create Enrollment Plot from Class List Data**

Create Enrollment Plot from Class List Data  Generates an interactive enrollment visualization from student class list (CL) registration statistics. Creates a faceted bar chart showing enrollment by term and campus, with courses distinguished by color.

**Parameters:**

- `reg_stats_summary` - Data frame of registration statistics aggregated from class list data. Expected columns include: \itemize{ \item \code{term} - Term code \item \code{registered} - Number of registered students \item \code{subject_course} - Course identifier (e.g., "ENGL 1110") \item \code{campus} - Campus location }
- `opt` - Options list (currently unused but kept for consistency with other enrollment plotting functions)

**Returns:** Named list containing one element: \itemize{ \item \code{cl_enrl} - Interactive plotly bar chart (or NULL if no data) }

**Details:**

The function creates a bar chart with: \itemize{ \item X-axis: Term (angled 45 degrees) \item Y-axis: Student count \item Fill color: Course (subject_course) \item Facets: Campus (fixed scales) \item Interactive hover information via plotly \item Horizontal legend positioned at bottom }  If the input data frame is empty (0 rows), returns NULL for the plot.

**Example:**
```r
\dontrun{
# After calculating CL enrollment statistics
reg_stats <- calc_cl_enrls(students)
plots <- make_enrl_plot_from_cls(reg_stats, opt = list())
plots$cl_enrl  # Display the interactive plot
}

```

---

### `make_enrl_plot()`

*Source: enrl.R*

**Create Enrollment Plot from Aggregated Data**

Create Enrollment Plot from Aggregated Data  Generates an interactive line chart showing enrollment trends over time from pre-aggregated enrollment summary data. Creates faceted visualizations with flexible grouping and optional faceting by any categorical field.

**Parameters:**

- `summary` - Data frame of aggregated enrollment data (output from \code{get_enrl()}). Must include columns specified in \code{opt$group_cols}, plus \code{enrolled}.
- `opt` - Options list containing: \itemize{ \item \code{group_cols} - Character vector of grouping columns. MUST include "term" and at least one other column (required) \item \code{facet_field} - Optional field to facet by (e.g., "campus", "level") \item \code{facet_scales} - Facet scale behavior: "fixed", "free", "free_x", "free_y" (default: "fixed") \item \code{facet_ncol} - Number of facet columns (default: NULL for auto) }

**Returns:** Named list containing one element: \itemize{ \item \code{enrl} - Interactive plotly line chart (or NULL if invalid data/opts) }

**Details:**

This function creates an enrollment trend visualization with the following features: \itemize{ \item Line chart with enrollment over time (term on x-axis) \item Lines colored/grouped by the first non-term column in group_cols \item Optional faceting by any categorical field (campus, level, etc.) \item Interactive plotly widget with hover details \item Horizontal legend at bottom \item 45-degree angled x-axis labels }  The function performs validation and will return NULL if: \itemize{ \item summary is missing or not a data frame \item group_cols is NULL \item group_cols doesn't include "term" \item group_cols has fewer than 2 elements \item summary data frame has 0 rows }

**Example:**
```r
\dontrun{
# Basic enrollment trend by course
opt <- list(
  term = c("202310", "202320", "202410"),
  group_cols = c("term", "subject_course")
)
summary <- get_enrl(cedar_sections, opt)
plots <- make_enrl_plot(summary, opt)
plots$enrl

# Faceted by campus with free y-axis scales
opt$facet_field <- "campus"
opt$facet_scales <- "free_y"
opt$facet_ncol <- 2
plots <- make_enrl_plot(summary, opt)
}

```

---

### `get_enrl()`

*Source: enrl.R*

**Get Enrollment Data**

Get Enrollment Data  Main entry point for enrollment analysis. Filters course sections according to specified criteria, handles missing columns gracefully, optionally compresses AOP (All Online Programs) course pairs, and can aggregate data by specified grouping columns.

**Parameters:**

- `courses` - Data frame of course sections from cedar_sections table. Must include columns: campus, college, department, term, subject_course, etc.
- `opt` - List of filtering and processing options: \itemize{ \item \code{dept} - Department code(s) to filter by \item \code{term} - Term code(s) to filter by \item \code{campus} - Campus code(s) to filter by \item \code{status} - Course status (default: "A" for active) \item \code{uel} - Use exclude list (default: TRUE) \item \code{aop} - AOP compression mode ("compress" to compress paired sections) \item \code{group_cols} - Vector of column names to group by for aggregation }

**Returns:** Data frame of enrollment data. If \code{opt$group_cols} is specified, returns aggregated summary with columns: sections, xl_sections, reg_sections, avg_size, enrolled, avail, waiting. Otherwise returns section-level data with columns dynamically selected based on availability.

**Details:**

The function performs the following steps: \enumerate{ \item Validates options and sets defaults (status = "A", uel = TRUE) \item Filters courses using \code{filter_DESRs()} with provided options \item Dynamically selects columns that exist in the data \item Computes derived columns if source columns exist: \itemize{ \item \code{available} = capacity - enrolled \item \code{total_enrl} = copy of enrolled (if crosslist data missing) } \item Optionally compresses AOP course pairs into single rows \item Removes duplicate rows and sorts consistently \item Optionally aggregates by \code{group_cols} using \code{summarize_courses()} }  Missing columns are handled gracefully - the function will compute derived columns when possible or create placeholders to ensure downstream code works.

**Example:**
```r
\dontrun{
# Get section-level enrollment for a department
opt <- list(dept = "HIST", term = "202510", status = "A")
enrl_data <- get_enrl(cedar_sections, opt)

# Get aggregated enrollment by course
opt <- list(
  dept = "HIST",
  group_cols = c("campus", "subject_course", "course_title", "term")
)
summary_data <- get_enrl(cedar_sections, opt)

# Compress AOP course pairs
opt <- list(dept = "BIOL", aop = "compress")
compressed_data <- get_enrl(cedar_sections, opt)
}

```

---

### `get_low_enrollment_courses()`

*Source: enrl.R*

**Get courses below enrollment threshold**

Get courses below enrollment threshold  Identifies courses with enrollment below a specified threshold, grouped by campus, department, course title, and instructional method.

**Parameters:**

- `courses` - Data frame of course sections (DESRs)
- `opt` - Options list with filtering parameters
- `threshold` - Numeric enrollment threshold (default 15)

**Returns:** Data frame of low-enrollment courses with enrollment history

---

### `get_course_enrollment_history()`

*Source: enrl.R*

**Get enrollment history for a specific course**

Get enrollment history for a specific course  Retrieves the last N terms of enrollment data for a specific course offering.

**Parameters:**

- `courses` - Data frame of course sections (DESRs)
- `campus` - Campus code
- `dept` - Department code
- `subj_crse` - Subject and course number (e.g., "HIST 1105")
- `crse_title` - Course title
- `im` - Instructional method code
- `n_terms` - Number of historical terms to retrieve (default 3)

**Returns:** Data frame with TERM and enrolled columns

---

### `format_enrollment_history()`

*Source: enrl.R*

**Create enrollment history string for display**

Create enrollment history string for display  Generates a text representation of enrollment history (e.g., "12 → 10 → 8")

**Parameters:**

- `history_data` - Data frame with TERM and enrolled columns

**Returns:** Character string with enrollment trend

---

## filter

### `filter_by_term()`

*Source: filter.R*

**Filter a Data Frame by Term(s)**

Filter a Data Frame by Term(s)  Filters rows in a data frame to include only those matching the specified term or terms in a given column.

**Parameters:**

- `df` - A data frame to filter.
- `term` - A single term value or a vector of term values to filter by (e.g., "202510" or c("202510", "202520")).
- `term_col` - The name of the column in `df` containing term values. Default is "TERM".

**Returns:** A filtered data frame containing only rows where `term_col` matches one of the values in `term`.

**Example:**
```r
# Filter for a single term:
filter_by_term(df, "202510")
# Filter for multiple terms:
filter_by_term(df, c("202510", "202520"))
# Specify a custom term column:
filter_by_term(df, "202510", term_col = "Academic Period Code")
```

---

### `filter_data()`

*Source: filter.R*

**Generic filter for a MyReports data frame.**

**Parameters:**

- `df` - The data frame to filter (DESRs or class list).
- `opt` - The options list.
- `opt_col_map` - Named list mapping opt param names to column names in df.
- `special_filters` - (Optional) Named list of functions for special-case filtering.

**Returns:** Filtered data frame.

---

## gradebook

### `count_grades()`

*Source: gradebook.R*

**Count Grades by Grouping Columns**

Count Grades by Grouping Columns  Summarizes grade counts from student data by specified grouping columns. This is a pure function that operates on pre-filtered data.

**Parameters:**

- `students` - Data frame with final_grade column plus grouping columns
- `group_cols` - Character vector of column names to group by

**Returns:** Data frame with grade counts grouped by specified columns: \describe{ \item{...group_cols...}{All specified grouping columns} \item{final_grade}{The grade value} \item{count}{Number of students with this grade} }

**Example:**
```r
\dontrun{
group_cols <- c("term", "subject_course", "instructor_last_name")
counts <- count_grades(filtered_students, group_cols)
}
```

---

### `categorize_grades()`

*Source: gradebook.R*

**Categorize Grades into Passed, Failed, and Dropped**

Categorize Grades into Passed, Failed, and Dropped  Takes grade counts and separates them into passed, failed, early dropped, and late dropped categories. This is a pure function for testability.

**Parameters:**

- `grade_counts` - Data frame from count_grades() with final_grade and count columns
- `group_cols` - Character vector of column names used for grouping
- `passing_grades` - Character vector of grades considered passing (e.g., c("A", "B", "C"))

**Returns:** Data frame with columns: \describe{ \item{...group_cols...}{All specified grouping columns} \item{passed}{Count of students with passing grades} \item{failed}{Count of students with failing grades (excludes early drops)} \item{early_dropped}{Count of students who dropped early (DR status, shown as "Drop")} \item{late_dropped}{Count of students who withdrew late (W grade)} }

**Details:**

Grade categorization: - Passed: grades in passing_grades list - Failed: grades NOT in passing_grades AND NOT "Drop" (includes W, F, D, etc.) - Early dropped: "Drop" grade (from DR registration status) - Late dropped: "W" grade specifically

**Example:**
```r
\dontrun{
categorized <- categorize_grades(grade_counts, group_cols, passing_grades)
}
```

---

### `calculate_dfw()`

*Source: gradebook.R*

**Calculate DFW Percentage**

Calculate DFW Percentage  Adds dfw_pct column to categorized grade data. Formula: dfw_pct = failed / (passed + failed) * 100

**Parameters:**

- `categorized` - Data frame from categorize_grades() with passed and failed columns

**Returns:** Same data frame with added "dfw_pct" column

**Details:**

The DFW calculation excludes early drops (DR status) since those students are not counted in enrollment totals.

**Example:**
```r
\dontrun{
dfw_summary <- calculate_dfw(categorized)
}
```

---

### `prepare_students_for_grading()`

*Source: gradebook.R*

**Prepare Student Data for Grade Analysis**

Prepare Student Data for Grade Analysis  Filters and preprocesses student enrollment data for DFW calculations. This is a pure function that handles all preprocessing steps.

**Parameters:**

- `students` - Data frame from cedar_students table
- `opt` - Options list for filtering (passed to filter_class_list)

**Returns:** Data frame of prepared students ready for grade counting, or empty data frame if no students match filters

**Details:**

Preprocessing steps: \enumerate{ \item Filter students using filter_class_list() with provided options \item Restrict to Fall 2019 or later (term >= 201980, after Gen Ed implementation) \item Convert DR (Drop) registration status to "Drop" final grade \item Remove duplicate student records per section (by student_id, campus, college, crn) \item Merge with grades_to_points lookup table for grade point values }

**Example:**
```r
\dontrun{
opt <- list(course = "MATH 1430", term = 202510)
prepared <- prepare_students_for_grading(cedar_students, opt)
}
```

---

### `merge_faculty_data()`

*Source: gradebook.R*

**Merge Faculty Job Category Data with Grade Counts**

Merge Faculty Job Category Data with Grade Counts  Adds instructor job category (TT/NTT) from HR data to grade counts.

**Parameters:**

- `grade_counts` - Data frame with grade counts including instructor_id and term
- `cedar_faculty` - Data frame from cedar_faculty table with job_category

**Returns:** grade_counts with job_category column added (if merge successful), or original grade_counts if no matches found (non-A&S units)

**Example:**
```r
\dontrun{
grade_counts_with_job <- merge_faculty_data(grade_counts, cedar_faculty)
}
```

---

### `build_aggregation_list()`

*Source: gradebook.R*

**Build Aggregation List from DFW Summary**

Build Aggregation List from DFW Summary  Creates multiple aggregated views of grade data at different granularities.

**Parameters:**

- `dfw_summary` - Data frame with DFW statistics
- `grade_counts` - Data frame with grade counts for section counting

**Returns:** Named list with aggregated tables: \describe{ \item{course_inst_avg}{Averages by course and instructor (across all terms)} \item{inst_type}{Averages by course, term, and instructor type (job_category)} \item{course_term}{Averages by course and term} \item{course_avg}{Overall course averages (across all terms)} \item{course_avg_by_term}{Course averages for each individual term} }

**Example:**
```r
\dontrun{
aggregations <- build_aggregation_list(dfw_summary, grade_counts)
}
```

---

### `aggregate_grades()`

*Source: gradebook.R*

**Aggregate Grade Data by Grouping Columns**

Aggregate Grade Data by Grouping Columns  Aggregates DFW (Drop/Fail/Withdraw) summary data by specified grouping columns, calculating totals for passed, failed, and dropped students, plus overall DFW percentage.

**Parameters:**

- `dfw_summary` - Data frame with columns: passed, failed, early_dropped, late_dropped plus any columns specified in opt$group_cols
- `opt` - Options list containing: \itemize{ \item \code{group_cols} - Character vector of column names to group by }

**Returns:** Data frame aggregated by group_cols with columns: \describe{ \item{passed}{Total passed students} \item{failed}{Total failed students} \item{early_dropped}{Total early drops (DR status)} \item{late_dropped}{Total late drops (W grade)} \item{DFW \%}{Percentage calculated as failed/(passed+failed)*100} } Plus all grouping columns.

**Details:**

This function validates that all requested group_cols exist in the data before aggregating. Missing columns are automatically removed with a warning. The DFW percentage calculation excludes early drops (DR) since those students are not counted in enrollment totals.

---

### `get_grades()`

*Source: gradebook.R*

**Get Grade Data and Calculate DFW Statistics**

Get Grade Data and Calculate DFW Statistics  Main controller function for grade analysis. Filters student enrollment data, calculates DFW (Drop/Fail/Withdraw) statistics, merges with CEDAR faculty data for instructor categorization, and produces multiple aggregated views of grade data.

**Parameters:**

- `students` - Data frame from cedar_students table with columns: student_id, campus, college, term, crn, subject_course, final_grade, registration_status_code, instructor_last_name, instructor_id
- `cedar_faculty` - Data frame from cedar_faculty table with columns: instructor_id, term, job_category
- `opt` - Options list for filtering and grouping: \itemize{ \item \code{course} - Course identifier(s) to filter by \item \code{dept} - Department code to filter by \item \code{term} - Term code(s) to filter by \item Other filter options supported by \code{filter_class_list()} }

**Returns:** Named list with grade data at various aggregation levels: \describe{ \item{counts}{Grade counts by campus, college, term, course, instructor, grade} \item{dfw_summary}{DFW summary with passed, failed, early_dropped, late_dropped counts} \item{course_inst_avg}{Averages by course and instructor (across all terms)} \item{inst_type}{Averages by course, term, and instructor type (job_cat)} \item{course_term}{Averages by course and term} \item{course_avg}{Overall course averages (across all terms)} \item{course_avg_by_term}{Course averages for each individual term} }

**Details:**

The function performs the following workflow: \enumerate{ \item Filters students using \code{filter_class_list()} with provided options \item Restricts to Fall 2019 or later (after Gen Ed implementation: term >= 201980) \item Converts DR (Drop) registration status to "Drop" final grade \item Removes duplicate student records per section \item Merges with grades_to_points lookup table \item Summarizes grade counts by campus, college, term, course, instructor \item Merges with HR data to add instructor job category (job_cat) \item Separates grades into passed, failed, early drops, and late drops \item Calculates DFW percentage: failed/(passed+failed)*100 \item Produces multiple aggregated views using \code{aggregate_grades()} \item Adds section counts per instructor }  **Important**: DFW % calculation excludes early drops (DR status) since those students are not counted in enrollment totals.  Passing grades are defined in includes/lists.R (typically A+, A, A-, B+, B, B-, C+, C, C-, D+, D, D-, S, CR)

**Example:**
```r
\dontrun{
# Get grades for a specific course
opt <- list(course = "MATH 1430", term = 202510)
grades <- get_grades(cedar_students, cedar_faculty, opt)

# View DFW summary
head(grades$dfw_summary)

# Get grades for a department
opt <- list(dept = "HIST")
dept_grades <- get_grades(cedar_students, cedar_faculty, opt)
}

```

---

## headcount

### `filter_programs_by_opt()`

*Source: headcount.R*

**Filter Programs Data by Options**

Filter Programs Data by Options  Helper function that applies institutional and program filters to CEDAR programs data.

**Parameters:**

- `programs` - Data frame of student program enrollment data (CEDAR format)
- `opt` - Options list with possible filters: \itemize{ \item campus - Vector of campus codes to include \item college - Vector of college codes to include \item dept - Vector of department codes to include \item major - Vector of major program names to include \item major_codes - Vector of major program codes to include (preferred over major for reliability). Supports prefix matching: "HIST-BA", "HIST-MA" will also match minor code "HIST" \item minor - Vector of minor program names to include \item concentration - Vector of concentration names to include }

**Returns:** List with: \describe{ \item{data}{Filtered data frame} \item{has_program_filter}{Boolean indicating if program-specific filters were applied} }

**Details:**

Applies filters in two stages: 1. Institutional filters (campus, college, department) 2. Program filters (major, minor, concentration)  Program filters are applied inclusively - they keep the specified programs while preserving other program types for the same students.

---

### `summarize_headcount()`

*Source: headcount.R*

**Summarize Headcount Data**

Summarize Headcount Data  Helper function that groups and counts students from filtered programs data.

**Parameters:**

- `df` - Filtered programs data frame (from filter_programs_by_opt)
- `has_program_filter` - Boolean indicating if program filters were applied
- `group_by` - Character vector of column names to group by. Default: c("term", "student_level", "program_type", "program_name") For aggregate summaries, use: c("term", "student_level", "program_type")

**Returns:** Data frame with columns based on group_by plus student_count

**Details:**

If no program filters were applied, summarizes by program type only. If program filters were applied, includes program_name in grouping.

---

### `format_headcount_result()`

*Source: headcount.R*

**Format Headcount Result with Metadata**

Format Headcount Result with Metadata  Helper function that packages headcount data with metadata.

**Parameters:**

- `summarized` - Summarized headcount data frame
- `df` - Original filtered data (for metadata calculation)
- `has_program_filter` - Boolean indicating if program filters were applied
- `opt` - Options list used for filtering

**Returns:** List with data and metadata: \describe{ \item{data}{Summarized headcount data frame} \item{no_program_filter}{Boolean - TRUE if no program filters applied} \item{metadata}{List with total_students, programs_included, filters_applied} }

---

### `get_headcount()`

*Source: headcount.R*

**Get Student Headcount**

Get Student Headcount  Main function for calculating student headcount from CEDAR programs data. Flexible orchestrating function that filters, summarizes, and packages headcount data for various use cases.

**Parameters:**

- `programs` - Student program enrollment data in CEDAR format. Required columns: student_id, term, student_level, program_type, program_name. Optional columns: student_college, student_campus, department, degree, program_code.
- `opt` - Options list for filtering and behavior: \itemize{ \item campus - Filter by campus code(s) \item college - Filter by college code(s) \item dept - Filter by department code(s) \item major - Filter by major program name(s) \item major_codes - Filter by major program code(s) - PREFERRED over major for consistency. Uses prefix matching to include related minors/programs (e.g., "HIST" matches "HIST-BA", "HIST-MA") \item minor - Filter by minor program name(s) \item concentration - Filter by concentration name(s) }
- `group_by` - Optional character vector of column names to group by. Default behavior groups by term, student_level, program_type, and program_name (if program filters applied) or just program_type (if no program filters). For custom aggregations (e.g., SFR), specify columns explicitly.

**Returns:** List with headcount data and metadata: \describe{ \item{data}{Data frame with student_count column and grouping columns} \item{no_program_filter}{Boolean indicating if program-specific filters were applied} \item{metadata}{List with total_students, programs_included, filters_applied} }

**Details:**

**CEDAR Data Model Only**  This function requires CEDAR-formatted data with lowercase column names. No fallbacks to legacy naming - CEDAR is mandatory.  **Architecture:**  This is an orchestrating function that delegates to smaller helper functions: - \code{\link{filter_programs_by_opt}}: Applies filters - \code{\link{summarize_headcount}}: Groups and counts - \code{\link{format_headcount_result}}: Packages with metadata  **Workflow:** 1. Selects relevant CEDAR columns (student_id, term, program fields, etc.) 2. Applies institutional filters (campus, college, department) 3. Applies program filters (major, minor, concentration) 4. Groups and counts unique students 5. Returns structured result with metadata  **Use Cases:** - Department reports: Filter by dept/program, get detailed breakdown - SFR calculations: Specify custom group_by for aggregated counts - General headcount: No filters, get all programs  **Deprecated Functions:**  \code{count_heads_by_program()} is deprecated and now simply calls \code{get_headcount()}. Update your code to use \code{get_headcount()} directly.

**Example:**
```r
\dontrun{
# Department report headcount (detailed)
result <- get_headcount(
  programs = cedar_programs,
  opt = list(dept = "HIST", major = "History")
)

# SFR headcount (aggregated by term and dept)
result <- get_headcount(
  programs = cedar_programs,
  opt = list(),
  group_by = c("term", "department", "student_level")
)
}

```

---

### `make_headcount_plots_by_level()`

*Source: headcount.R*

**Create Headcount Plots by Student Level**

Create Headcount Plots by Student Level  Creates separate interactive plots for undergraduate and graduate students, with appropriate visualization choices for each level.

**Parameters:**

- `result` - Result list from count_heads_by_program() containing data and metadata

**Returns:** Named list with plotly plots: \describe{ \item{undergrad}{Undergraduate enrollment plot (stacked bars by program)} \item{graduate}{Graduate enrollment plot (dodged bars by program)} }

**Details:**

Undergraduate plots use stacked bars faceted by program for density. Graduate plots use dodged bars for easier comparison of smaller cohorts.

---

### `make_headcount_plot()`

*Source: headcount.R*

**Create Single Combined Headcount Plot**

Create Single Combined Headcount Plot  Creates a single stacked bar chart showing enrollment across all programs and levels.

**Parameters:**

- `summarized` - Summarized data frame from count_heads_by_program()

**Returns:** Interactive plotly plot or NULL if no data

**Details:**

This is a simplified plotting function that creates a single view. For more detailed analysis, use make_headcount_plots_by_level() instead.

---

### `get_headcount_data_for_dept_report()`

*Source: headcount.R*

**Count Students by Program (Legacy Function)**

Count Students by Program (Legacy Function)  Legacy headcount function for backward compatibility with older code. Uses mapped DEPT and PRGM codes for filtering.

**Parameters:**

- `academic_studies_data` - Academic studies data with original column names
- `opt` - Options list for filtering (passed to count_heads_by_program). Can include filters for campus, college, etc.
- `programs` - Student program enrollment data in CEDAR format. Required columns: student_id, term, student_level, program_type, program_name. This is typically the academic_studies dataset with CEDAR naming.
- `d_params` - Department report parameters list with: \itemize{ \item term_start - Start term for filtering \item term_end - End term for filtering \item prog_names - Vector of program names to include \item tables - Existing tables list (will be updated) \item plots - Existing plots list (will be updated) }

**Returns:** Updated d_params with added tables and plots: \describe{ \item{tables}{ \itemize{ \item hc_progs_under - All undergrad programs \item hc_progs_under_long_majors - Undergrad majors only \item hc_progs_under_long_minors - Undergrad minors only \item hc_progs_grad - All grad programs \item hc_progs_grad_long_majors - Grad majors only \item hc_progs_grad_long_minors - Grad minors only } } \item{plots}{Corresponding plotly plots for each table above} }

**Details:**

**CEDAR Data Model Only**  This function requires CEDAR-formatted data and will error if legacy column names are provided. There are no fallbacks - CEDAR naming is mandatory.  Workflow: 1. Validates CEDAR column structure (errors with clear message if missing) 2. Calls get_headcount() to get aggregated headcount data 3. Filters by term range and program names 4. Splits into undergraduate/graduate and major/minor subsets 5. Creates plotly plots for each subset 6. Returns all data and plots via d_params  **Column Mappings (Legacy → CEDAR):** - term_code → term - Student Level → student_level - major_type → program_type - major_name → program_name

---

## load-funcs

### `load_funcs()`

*Source: load-funcs.R*

**Load All CEDAR R Functions**

Load All CEDAR R Functions  Loads all R source files for the CEDAR application in the correct dependency order: lists first, then branches (utilities), then cones (analysis functions).

**Parameters:**

- `cedar_base_dir` - Character. The base directory of the CEDAR project. All source paths are constructed relative to this directory.

**Returns:** NULL (invisibly). Called for side effect of loading functions.

**Details:**

Loading order: 1. **lists/** - Static data: column mappings, term codes, grade definitions 2. **branches/** - Core utilities: caching, filtering, data loading 3. **cones/** - Analysis functions: headcount, degrees, enrollment, etc.

**Example:**
```r
\dontrun{
# From project root
load_funcs(getwd())

# From Shiny app
load_funcs(cedar_base_dir)
}

```

---

## majors

### `detect_major_changes()`

*Source: majors.R*

**Detect major changes for each student across their academic timeline**

**Parameters:**

- `df` - Data frame (academic_studies) with student program data
- `major_col` - Character string, column name for primary major (default "Major")
- `id_col` - Character string, column name for student ID (default "ID")
- `term_col` - Character string, column name for term code (default "term_code")
- `credits_col` - Character string, column name for credits attempted (default "Credits Attempted")

**Returns:** Data frame with one row per major change event

**Example:**
```r
changes <- detect_major_changes(academic_studies)
changes_filtered <- detect_major_changes(academic_studies, opt = list(college = "Arts and Sciences"))
```

---

### `avg_credits_before_major()`

*Source: majors.R*

**Calculate average credits before entering each major (for first-time major changers)**

**Parameters:**

- `changes_df` - Data frame from detect_major_changes()
- `min_n` - Minimum number of observations to report (default 5)

**Returns:** Data frame summarizing avg credits by destination major

---

### `majors_moved_out_of()`

*Source: majors.R*

**Identify most common majors students move OUT OF**

**Parameters:**

- `changes_df` - Data frame from detect_major_changes()
- `min_n` - Minimum number of observations to report (default 5)

**Returns:** Data frame of source majors ranked by frequency

---

### `major_change_pathways()`

*Source: majors.R*

**Identify most common major change pathways (A → B)**

**Parameters:**

- `changes_df` - Data frame from detect_major_changes()
- `min_n` - Minimum number of observations to report (default 3)

**Returns:** Data frame of pathways ranked by frequency

---

### `pathways_by_college()`

*Source: majors.R*

**Analyze major change pathways by college**

**Parameters:**

- `changes_df` - Data frame from detect_major_changes()
- `min_n` - Minimum number of observations to report (default 3)
- `use_translated` - Logical, use Translated College vs Actual College (default TRUE)

**Returns:** Data frame of pathways by college

---

### `time_to_first_change()`

*Source: majors.R*

**Calculate time to first major change (in terms)**

**Parameters:**

- `df` - Data frame (academic_studies)
- `id_col` - Character string, column name for student ID (default "ID")
- `term_col` - Character string, column name for term code (default "term_code")
- `major_col` - Character string, column name for major (default "Major")

**Returns:** Data frame with student_id, first_term, first_change_term, terms_until_change

---

### `tag_major_changers()`

*Source: majors.R*

**Identify students who changed major vs. those who didn't (cohort tagging)**

**Parameters:**

- `df` - Data frame (academic_studies)
- `id_col` - Character string, column name for student ID (default "ID")
- `term_col` - Character string, column name for term code (default "term_code")
- `major_col` - Character string, column name for major (default "Major")

**Returns:** Data frame with student_id, changed_major (boolean), n_changes, majors_held (comma-separated)

---

### `major_change_report()`

*Source: majors.R*

**Generate comprehensive major change report**

**Parameters:**

- `df` - Data frame (academic_studies)
- `opt` - Optional list of filter parameters (campus, college, dept)
- `min_n` - Minimum observations for summaries (default 5)

**Returns:** Named list of analysis results

---

## outcomes

### `get_outcomes()`

*Source: outcomes.R*

**Student Outcomes Analysis**

Student Outcomes Analysis  This function analyzes student outcomes and persistence patterns after course completion. Leverages existing gradebook.R infrastructure for consistent grade processing.

**Parameters:**

- `students` - Data frame containing class list data with enrollment and grade information
- `opt` - List containing filtering and analysis options

**Returns:** List containing outcomes analysis tables and summaries

**Example:**
```r
\dontrun{
opt <- list(courses = c("MATH 1215", "ENGL 1110"))
outcomes_data <- get_outcomes(students, opt)
}
```

---

### `analyze_failure_persistence_with_grades()`

*Source: outcomes.R*

**Analyze Failure Persistence with Grade Data**

Analyze Failure Persistence with Grade Data  Uses gradebook infrastructure to track students who fail courses

**Parameters:**

- `students` - Filtered student data
- `grades_data` - Grade data from get_grades()

**Returns:** Data frame with failure persistence analysis

---

### `analyze_dfw_trends()`

*Source: outcomes.R*

**Analyze DFW Trends Over Time**

Analyze DFW Trends Over Time  Uses gradebook course_term data to show DFW trends

**Parameters:**

- `grades_data` - Grade data from get_grades()

**Returns:** Data frame with DFW trends over time

---

### `analyze_instructor_outcomes()`

*Source: outcomes.R*

**Analyze Instructor Impact on Outcomes**

Analyze Instructor Impact on Outcomes  Uses gradebook instructor-level data to compare outcomes

**Parameters:**

- `grades_data` - Grade data from get_grades()

**Returns:** Data frame with instructor outcome analysis

---

### `analyze_next_term_enrollment_with_grades()`

*Source: outcomes.R*

**Analyze Next Term Enrollment with Grade Categories**

Analyze Next Term Enrollment with Grade Categories  Uses CEDAR's grade categorization for enrollment analysis

**Parameters:**

- `students` - Filtered student data

**Returns:** Data frame with next term enrollment analysis

---

### `plot_outcomes_for_course_report()`

*Source: outcomes.R*

**Plot Outcomes for Course Report**

Plot Outcomes for Course Report  Creates visualizations leveraging gradebook infrastructure

**Parameters:**

- `outcomes` - Outcomes list from get_outcomes()
- `opt` - Options list

**Returns:** Plotly object with outcomes visualization

---

## parse-data

### `process_reports()`

*Source: parse-data.R*

**process_reports**

process_reports  Main function to process MyReports data files. - Loads configuration and required packages. - Determines environment (Docker/local) and sets directories. - Finds and processes .xlsx files for specified report types. - Converts Excel files to CSV, parses data, and saves results as Rds. - Handles encryption of sensitive ID columns. - Designed for command line use.

**Parameters:**

- `report` - Character vector of report types to process (e.g., "desr", "cl", "as", "deg").
- `guide` - Logical; if TRUE, prints usage instructions.

**Returns:** None. Side effects: saves processed data, prints progress messages.

---

## regstats

### `get_high_fall_sophs()`

*Source: regstats.R*

**Identify High-Enrollment Fall Sophomore Courses**

Identify High-Enrollment Fall Sophomore Courses  Finds fall courses with high sophomore enrollment (100+ students) that could be considered for summer offerings. This helps with planning summer schedules by identifying courses with strong demand from students who will be juniors in fall.

**Parameters:**

- `students` - Data frame of student enrollments from cedar_students table. Must include columns: campus, college, term, term_type, student_classification, subject_course, course_title, level
- `courses` - Data frame of course sections (currently unused but kept for consistency)
- `opt` - Options list (currently unused - function uses hardcoded filters)

**Returns:** Data frame with single column: \itemize{ \item \code{subject_course} - Course identifiers with 100+ fall sophomores }

**Details:**

The function: \enumerate{ \item Filters for "Sophomore, 2nd Yr" classification \item Filters for fall term only \item Uses \code{rollcall()} to calculate mean enrollment by course \item Returns courses with mean > 100 sophomores }  The 100-student threshold is somewhat arbitrary and could be refined based on institutional capacity for summer offerings.

**Example:**
```r
\dontrun{
# Find popular sophomore fall courses
opt <- list()
high_soph_courses <- get_high_fall_sophs(cedar_students, cedar_sections, opt)

# These courses could be summer offerings
print(high_soph_courses$subject_course)
}

```

---

### `get_after_bumps()`

*Source: regstats.R*

**Identify Courses Taken After Enrollment Bumps**

Identify Courses Taken After Enrollment Bumps  For courses experiencing enrollment bumps (unusually high registration), identifies the top 5 courses that students take next. This helps with capacity planning by anticipating downstream enrollment pressure from bump courses.

**Parameters:**

- `bumps` - Data frame of bump courses (output from get_reg_stats()$bumps). Must include column: subject_course
- `students` - Data frame of student enrollments from cedar_students table
- `courses` - Data frame of course sections from cedar_sections table
- `opt` - Options list passed through to \code{where_to()} for filtering

**Returns:** Data frame with single column: \itemize{ \item \code{subject_course} - Unique courses frequently taken after bump courses }

**Details:**

For each bump course, the function: \enumerate{ \item Calls \code{where_to()} to find courses students take next \item Ranks by average contribution to those next courses \item Selects top 5 downstream courses \item Aggregates across all bump courses and returns unique list }  This is useful for enrollment forecasting - if MATH 1430 has a bump and students typically take MATH 1440 next, MATH 1440 will likely see increased demand next term.

**Example:**
```r
\dontrun{
# Get bump courses and their downstream effects
opt <- list(term = "202510", course_college = "AS")
flagged <- get_reg_stats(cedar_students, cedar_sections, opt)
after_bumps <- get_after_bumps(flagged$bumps, cedar_students, cedar_sections, opt)

# These courses may need capacity increases next term
print(after_bumps$subject_course)
}

```

---

### `get_reg_stats()`

*Source: regstats.R*

**Detect Registration Anomalies and Enrollment Concerns**

Detect Registration Anomalies and Enrollment Concerns  Analyzes historical enrollment patterns to identify courses with unusual registration behavior including bumps (higher than normal), dips (lower than normal), drops (higher early/late withdrawal), squeezes (high enrollment with low capacity), and waitlists. This is the primary tool for identifying enrollment concerns that need administrative attention.

**Parameters:**

- `students` - Data frame of student enrollments from cedar_students table. Must include columns: campus, college, term, term_type, subject_course, course_title, level, student_id, registration_status
- `courses` - Data frame of course sections from cedar_sections table. Must include columns: campus, college, term, subject_course, gen_ed_area, enrolled, waiting, avail
- `opt` - Options list for filtering and thresholds: \itemize{ \item \code{term} - Term code(s) to analyze (e.g., 202510) \item \code{course} - Course identifier(s) to analyze (e.g., "MATH 1430") \item \code{course_college} - College code(s) to filter (e.g., "AS") \item \code{course_campus} - Campus code(s) to filter (e.g., "MAIN") \item \code{level} - Course level(s) to filter (e.g., "undergrad") \item \code{thresholds} - Custom threshold list (see Details) }

**Returns:** Named list with anomaly data frames and metadata: \itemize{ \item \code{early_drops} - Courses with unusually high early drops \item \code{late_drops} - Courses with unusually high late drops \item \code{dips} - Courses with unusually low enrollment \item \code{bumps} - Courses with unusually high enrollment \item \code{waits} - Courses with significant waitlists \item \code{squeezes} - Courses with low seat availability relative to historical drops \item \code{all_flagged_courses} - Character vector of all flagged course identifiers \item \code{tiered_summary} - Summary of concerns by severity tier \item \code{high_fall_sophs} - Popular fall sophomore courses (non-Shiny only) \item \code{thresholds} - Thresholds used for detection \item \code{cache_info} - Cache metadata including age and parameters }

**Details:**

## Detection Methodology The function uses population standard deviation to identify statistical anomalies: \itemize{ \item \strong{Bumps/Drops:} Flags values >= +1 SD above mean ("high" anomalies) \item \strong{Dips:} Flags values <= -1 SD below mean ("low" anomalies) \item \strong{Concern Tiers:} \itemize{ \item Critical: ±1.5 SD (immediate attention needed) \item Moderate: ±1.0 SD (notable change) \item Marginal: ±0.5 SD (minor change worth monitoring) } }  ## Default Thresholds Default thresholds from \code{cedar_regstats_thresholds}: \itemize{ \item \code{min_impacted} = 20 (minimum student impact for bumps/dips/drops) \item \code{pct_sd} = 1 (minimum standard deviations for flagging) \item \code{min_squeeze} = 0.3 (minimum squeeze ratio: avail/historical_drops) \item \code{min_wait} = 20 (minimum waitlist size) \item \code{section_proximity} = 0.3 (proximity threshold for sections) }  ## Custom Thresholds Custom thresholds can be provided via \code{opt$thresholds}. If custom thresholds differ from defaults, caching is bypassed to ensure fresh calculations.  ## Caching Results are cached for 24 hours when using standard thresholds. Cache files are stored in \code{cedar_data_dir/regstats/} with names based on filtering parameters (college, term, level, campus). Old cache files are automatically cleaned up, keeping only the 20 most recent files.  ## Anomaly Types Explained \itemize{ \item \strong{Early Drops:} High withdrawal before census (dr_early) \item \strong{Late Drops:} High withdrawal after census (dr_late) \item \strong{Dips:} Lower than normal registration (may indicate declining interest) \item \strong{Bumps:} Higher than normal registration (may indicate unmet demand) \item \strong{Waits:} Significant waitlists (definite capacity shortage) \item \strong{Squeezes:} Low seat availability relative to typical drops (calculated as avail/dr_all_mean < threshold) }

**Example:**
```r
\dontrun{
# Analyze all Arts & Sciences courses for Fall 2025
opt <- list(term = "202510", course_college = "AS")
flagged <- get_reg_stats(cedar_students, cedar_sections, opt)

# View courses with enrollment bumps
head(flagged$bumps)

# Check waitlist concerns
print(flagged$waits)

# See all flagged courses
print(flagged$all_flagged_courses)

# View summary by concern tier
print(flagged$tiered_summary)

# Use custom thresholds (bypasses cache)
custom_opt <- list(
  term = "202510",
  thresholds = list(
    min_impacted = 30,
    pct_sd = 1.5,
    min_wait = 30,
    min_squeeze = 0.2
  )
)
custom_flagged <- get_reg_stats(cedar_students, cedar_sections, custom_opt)
}

```

---

### `create_regstat_report()`

*Source: regstats.R*

**Generate Registration Statistics Report**

Generate Registration Statistics Report  Creates a comprehensive PDF/HTML report of registration anomalies and enrollment concerns by calling \code{get_reg_stats()} and rendering the regstats Rmd template.

**Parameters:**

- `students` - Data frame of student enrollments from cedar_students table
- `courses` - Data frame of course sections from cedar_sections table
- `opt` - Options list passed through to \code{get_reg_stats()} and report rendering: \itemize{ \item \code{term} - Term code(s) to analyze \item \code{course_college} - College code(s) to filter \item \code{arrange} - Optional column name for custom sorting \item Other filtering options (see \code{\link{get_reg_stats}}) }

**Returns:** NULL (side effect: renders report to output directory)

**Details:**

The function: \enumerate{ \item Calls \code{get_reg_stats()} to detect anomalies \item Optionally sorts results by \code{opt$arrange} column \item Packages data into format expected by Rmd template \item Calls \code{create_report()} to render regstats-report.Rmd \item Saves output to \code{cedar_output_dir/regstats-reports/} }  Report includes: \itemize{ \item Summary of flagged courses by anomaly type \item Detailed tables for bumps, dips, drops, waits, squeezes \item Tiered concern summaries (critical/moderate/marginal) \item Thresholds used for detection }

**Example:**
```r
\dontrun{
# Generate report for Fall 2025 Arts & Sciences
opt <- list(term = "202510", course_college = "AS")
create_regstat_report(cedar_students, cedar_sections, opt)

# Report saved to: cedar_output_dir/regstats-reports/output.pdf
}

```

---

## rollcall

### `abbreviate_classification()`

*Source: rollcall.R*

**Abbreviate Student Classification Labels**

Abbreviate Student Classification Labels  Converts verbose MyReports classification labels to shorter display labels to prevent layout issues in pie charts and legends.

**Parameters:**

- `classification` - Character vector of student classification values

**Returns:** Character vector with abbreviated labels

**Example:**
```r
abbreviate_classification("Freshman, 1st Yr, 1st Sem")  # Returns "Freshman"
abbreviate_classification("Junior, 3rd Yr.")  # Returns "Junior"
```

---

### `summarize_student_demographics()`

*Source: rollcall.R*

**Summarize Student Demographics**

Summarize Student Demographics  Flexible demographic summary function that groups students by any specified columns (majors, classifications, or other demographic fields) and calculates enrollment counts, means across terms, and percentages of course enrollment. This provides insight into "who" is taking courses over time.

**Parameters:**

- `filtered_students` - Data frame of student enrollments from cedar_students table, already filtered by desired criteria. Must include: student_id, term, campus, college, subject_course, and any demographic columns used in grouping.
- `opt` - Options list containing: \itemize{ \item \code{group_cols} - Character vector of column names to group by. If NULL, uses default: campus, college, term, term_type, major, student_classification, subject_course, course_title, level }

**Returns:** Data frame with student demographic breakdown including: \describe{ \item{count}{Number of distinct students in this group for THIS SPECIFIC TERM} \item{mean}{Average count across all terms OF THE SAME TERM_TYPE (e.g., avg across all falls). This is the key value used for plotting "average students per term type".} \item{registered}{Total course enrollment for this specific term} \item{registered_mean}{Average course enrollment across terms of same term_type} \item{term_pct}{Percentage of course enrollment this group represents IN THIS TERM (count / registered * 100)} \item{term_type_pct}{AVERAGE percentage across all terms of this term_type (mean / registered_mean * 100). This is what the pie charts display.} } Plus all columns specified in group_cols.  The \code{mean} and \code{term_type_pct} columns answer: "On average, what percentage of students in HIST 1105 are freshmen in fall semesters?" This averages across Fall 2022, Fall 2023, Fall 2024, etc. to give a stable "typical" value.

**Details:**

The function performs the following steps: \enumerate{ \item Groups students by specified columns and counts distinct student_ids \item Removes term from grouping and calculates mean counts across terms \item Calls \code{calc_cl_enrls()} to get total course enrollment counts \item Merges demographic counts with enrollment totals \item Calculates percentages: what % of course enrollment does each group represent \item Sorts by campus, college, term, course, and descending percentage }  This function is useful for answering questions like: \itemize{ \item "What majors are taking MATH 1430?" \item "Are freshmen or seniors more represented in this course?" \item "How has the major composition of BIOL 1110 changed over time?" \item "What percentage of course enrollment comes from each college?" }

**Example:**
```r
\dontrun{
# Summarize by major
opt <- list(
  course = "MATH 1430",
  group_cols = c("campus", "college", "term", "major", "subject_course")
)
filtered <- filter_class_list(cedar_students, opt)
major_summary <- summarize_student_demographics(filtered, opt)

# Summarize by classification
opt$group_cols <- c("campus", "term", "student_classification", "subject_course")
class_summary <- summarize_student_demographics(filtered, opt)
}

```

---

### `create_rollcall_color_palette()`

*Source: rollcall.R*

**Create Consistent Color Palette for Rollcall Plots**

Create Consistent Color Palette for Rollcall Plots  Generates a consistent color mapping for categories across multiple plots to ensure the same majors/classifications have the same colors in fall, spring, and summer plots.

**Parameters:**

- `rollcall_data` - A dataframe containing rollcall data across all term types.
- `fill_column` - The column name to use for color mapping (e.g., "Student Classification" or "Major")
- `top_n` - Number of top categories to include in color palette (default: 10)

**Returns:** A named vector of colors where names are category values

**Example:**
```r
color_palette <- create_rollcall_color_palette(rollcall_data, "Major", top_n = 8)
```

---

### `plot_rollcall_summary()`

*Source: rollcall.R*

**are calculated against total average enrollment (not just top 5).**

**Parameters:**

- `rollcall_data` - Data frame from \code{summarize_student_demographics()}. Must contain columns: fill_column, term_type, mean, term_type_pct, campus, college, subject_course
- `fill_column` - Column name to group by (e.g., "student_classification" or "major")
- `color_palette` - Named vector of colors from \code{create_rollcall_color_palette()}
- `filter_column` - Optional list with \code{column} and \code{values} for filtering (e.g., \code{list(column = "campus", values = c("ABQ"))})

**Returns:** Named list of plotly donut charts: \itemize{ \item \code{fall} - Chart for fall terms (NULL if no data) \item \code{spring} - Chart for spring terms (NULL if no data) \item \code{summer} - Chart for summer terms (NULL if no data) \item \code{by_term} - List of all charts keyed by term_type }

**Example:**
```r
\dontrun{
# Get rollcall data with pre-calculated averages
rollcall_data <- summarize_student_demographics(filtered_students, opt)

# Create consistent color palette
color_palette <- create_rollcall_color_palette(rollcall_data, "major")

# Generate plots
plots <- plot_rollcall_summary(rollcall_data, "major", color_palette)
plots$fall   # Fall term chart
plots$spring # Spring term chart
}

```

---

### `rollcall()`

*Source: rollcall.R*

**Rollcall: Student Demographics Over Time**

Rollcall: Student Demographics Over Time  Main rollcall function that analyzes student demographics (majors, classifications, etc.) in courses over time. Filters students by specified criteria, removes historical data before Fall 2019, and creates demographic summaries with enrollment percentages.

**Parameters:**

- `students` - Data frame of student enrollments from cedar_students table. Must include: student_id, term, campus, college, subject_course, registration_status_code, and any demographic columns for grouping.
- `opt` - Options list for filtering and grouping: \itemize{ \item \code{group_cols} - Character vector of columns to group by. If NULL, uses defaults: campus, college, term, term_type, student_classification, major, subject_course, course_title, level \item \code{reg_status_code} - Registration status codes to include (default: c("RE", "RS")) \item \code{term} - Term code(s) to filter by \item \code{course} - Course identifier(s) to filter by \item Other filtering options supported by \code{filter_class_list()} }

**Returns:** Data frame with student demographic breakdown including counts, means, and percentages. See \code{\link{summarize_student_demographics}} for details.

**Details:**

The function performs the following steps: \enumerate{ \item Sets default group_cols if not provided \item Sets default reg_status_code (registered students only) \item Filters students using \code{filter_class_list()} \item Removes data from before Fall 2019 (term < 201980) \item Calls \code{summarize_student_demographics()} to aggregate \item Returns demographic summary with percentages }  Use this function to answer questions like: \itemize{ \item "What majors are taking MATH 1430 and how has that changed?" \item "Are we seeing more upperclassmen in intro courses over time?" \item "Which colleges' students are enrolled in this gen ed course?" }

**Example:**
```r
\dontrun{
# Analyze major composition of a course over time
opt <- list(
  course = "BIOL 2305",
  group_cols = c("campus", "term", "term_type", "major", "subject_course")
)
major_breakdown <- rollcall(cedar_students, opt)

# Analyze classification changes across all MATH courses
opt <- list(
  subject = "MATH",
  group_cols = c("campus", "term", "student_classification", "subject_course")
)
class_breakdown <- rollcall(cedar_students, opt)
}

```

---

### `plot_time_series()`

*Source: rollcall.R*

**Plot Classification Time Series**

Plot Classification Time Series  Creates line plots showing the percentage of students in each classification across terms over time.

**Parameters:**

- `rollcall_data` - A dataframe from summarize_student_demographics containing rollcall data with term info.
- `value_column` - The column to use for y-axis values (default: "term_pct")
- `top_n` - Number of top classifications/majors to display (default: 8)

**Returns:** A plotly object showing time series lines.

**Example:**
```r
plot_time_series(rollcall_data, fill_column = "student_classification", value_column = "term_type_pct", top_n = 6)
```

---

### `plot_rollcall_with_consistent_colors()`

*Source: rollcall.R*

**Plot Rollcall Summary with Consistent Colors Across Terms**

Plot Rollcall Summary with Consistent Colors Across Terms  Wrapper function that creates rollcall plots with consistent color mapping across all term types (fall, spring, summer).

**Parameters:**

- `rollcall_data` - A dataframe containing rollcall data for all terms.
- `fill_column` - The column name to use for fill aesthetic.
- `top_n` - Number of top categories to include (default: 7)
- `filter_column` - Optional list with column name and values to filter data (e.g., list(column = "campus", values = c("ABQ", "TAOS")))

**Returns:** A list of plots with consistent colors across term types.

**Example:**
```r
consistent_plots <- plot_rollcall_with_consistent_colors(rollcall_data, "major", top_n = 8)
# With campus filter:
campus_filter <- list(column = "campus", values = c("ABQ"))
filtered_plots <- plot_rollcall_with_consistent_colors(rollcall_data, "major", 7, campus_filter)
```

---

## seatfinder

### `get_courses_common()`

*Source: seatfinder.R*

**Get Courses Common to Both Terms**

Get Courses Common to Both Terms  Finds courses offered in both comparison terms and calculates year-over-year enrollment changes. This helps identify enrollment trends and capacity needs.

**Parameters:**

- `term_courses` - Named list with two data frames: \itemize{ \item \code{start} - Courses from starting term \item \code{end} - Courses from ending term }
- `enrl_summary` - Data frame of enrollment summary data with columns: campus, college, term, subject_course, gen_ed_area, enrolled

**Returns:** Data frame of courses common to both terms with enrollment difference calculated. Includes column \code{enrl_diff_from_last_year} showing change in enrollment between terms.

**Details:**

Uses set intersection to find courses in both terms, merges with enrollment data, and computes year-over-year enrollment differences using lag().

---

### `get_courses_diff()`

*Source: seatfinder.R*

**Get Course Differences Between Terms**

Get Course Differences Between Terms  Identifies courses offered in one term but not the other, helping track new course offerings and discontinued courses.

**Parameters:**

- `term_courses` - Named list with two data frames: \itemize{ \item \code{start} - Courses from starting term \item \code{end} - Courses from ending term }

**Returns:** Named list with two elements: \itemize{ \item \code{prev} - Courses offered in start term but NOT in end term (discontinued) \item \code{new} - Courses offered in end term but NOT in start term (new offerings) }

**Details:**

Uses set difference (setdiff) to find courses unique to each term. This helps identify: \itemize{ \item New course offerings that need capacity planning \item Discontinued courses that may affect student progression \item Changes in gen ed course availability }

---

### `normalize_inst_method()`

*Source: seatfinder.R*

**Normalize Delivery Method Codes**

Normalize Delivery Method Codes  Standardizes delivery method codes by grouping variants of face-to-face instruction under a single "f2f" category.

**Parameters:**

- `courses` - Data frame with delivery_method column

**Returns:** Data frame with added \code{method} column containing normalized values

**Details:**

Creates a new \code{method} column that normalizes delivery_method by: \itemize{ \item "0" → "f2f" \item "ENH" (Enhanced) → "f2f" \item "HYB" (Hybrid) → "f2f" \item All other values preserved as-is }  This grouping helps aggregate enrollment across similar delivery modes.

---

### `seatfinder()`

*Source: seatfinder.R*

**Analyze Course Seat Availability Across Terms**

Analyze Course Seat Availability Across Terms  Main seatfinder function that performs comprehensive seat availability analysis by comparing course offerings between terms (typically year-over-year). Helps identify capacity needs, enrollment trends, and gen ed course availability.

**Parameters:**

- `students` - Data frame from cedar_students table (used for DFW rate calculation)
- `courses` - Data frame from cedar_sections table with enrollment and capacity data
- `cedar_faculty` - Data frame from cedar_faculty table (used for instructor job category in grades)
- `opt` - Options list with required and optional parameters: \itemize{ \item \code{term} - (Required) Term code or range (e.g., "202510" or "202410,202510") If single term, compares to same term previous year (term - 100) \item \code{part_term} - (Optional) Part of term filter (e.g., "1H", "2H", "FT") \item \code{department} - (Optional) Department filter \item \code{subject} - (Optional) Subject filter \item \code{group_cols} - (Optional) Custom grouping columns Defaults to: campus, college, term, subject_course, part_term, level, gen_ed_area }

**Returns:** Named list with six data frames: \describe{ \item{type_summary}{Courses with availability differences by part_term. Columns: campus, college, term, part_term, subject_course, avail, dfw_pct, avail_diff (change from previous year), enrolled, gen_ed_area} \item{courses_common}{Courses offered in both terms with enrollment changes. Includes enrl_diff_from_last_year showing YoY enrollment trends} \item{courses_prev}{Courses offered in start term but NOT in end term (discontinued)} \item{courses_new}{Courses offered in end term but NOT in start term (new offerings)} \item{gen_ed_summary}{Gen ed courses with available seats, sorted by area and availability} \item{gen_ed_likely}{Gen ed courses currently at zero capacity (may open later)} }

**Details:**

Seatfinder workflow: \enumerate{ \item Parse term parameter (single term vs comparison range) \item Get enrollment summary with configurable grouping (via get_enrl) \item Merge DFW rates from grades data (via get_grades) \item Identify courses common to both terms (via get_courses_common) \item Identify new and discontinued courses (via get_courses_diff) \item Pivot to calculate availability changes (avail_diff) \item Filter and sort gen ed courses by availability }  Use cases for seatfinder: \itemize{ \item **Semester Planning**: Which courses need additional sections? \item **Capacity Analysis**: How does seat availability compare to last year? \item **Gen Ed Management**: Which gen ed courses have open seats? \item **Enrollment Forecasting**: What are enrollment trends by course type? \item **New Course Planning**: Which courses are new this term? }  **Important**: Always uses the exclude list (opt$uel = TRUE) and active courses only (opt$status = "A"). Aggregates section enrollments by course type.

**Example:**
```r
\dontrun{
# Compare Fall 2025 to Fall 2024 (default one-year comparison)
opt <- list(term = "202580", part_term = "FT", department = "MATH")
results <- seatfinder(cedar_students, cedar_sections, cedar_faculty, opt)

# View courses with largest availability decreases
head(results$type_summary %>% arrange(avail_diff))

# Compare specific terms
opt <- list(term = "202410,202510")  # Spring 2024 vs Spring 2025
results <- seatfinder(cedar_students, cedar_sections, cedar_faculty, opt)

# Check gen ed availability
head(results$gen_ed_summary)
}

```

---

### `create_seatfinder_report()`

*Source: seatfinder.R*

**Create Seatfinder Report**

Create Seatfinder Report  Generates a formatted seatfinder report by calling seatfinder() and passing results to an R Markdown template for rendering.

**Parameters:**

- `students` - Data frame from cedar_students table
- `courses` - Data frame from cedar_sections table
- `cedar_faculty` - Data frame from cedar_faculty table
- `opt` - Options list passed to seatfinder (see \code{\link{seatfinder}} for details) Must include: term, and optionally part_term (aliased as "pt" for filenames)

**Returns:** Invisibly returns the report file path (via create_report)

**Details:**

This wrapper function: \enumerate{ \item Calls seatfinder() to generate all analyses \item Packages results into d_params for R Markdown \item Sets output filename and directory \item Generates report via create_report() }  Output filename format: `seatfinder-{term}-{part_term}.html` Default output directory: `{cedar_output_dir}/seatfinder-reports/`

**Example:**
```r
\dontrun{
# Generate report for Fall 2025 full term MATH courses
opt <- list(term = "202580", pt = "FT", department = "MATH")
create_seatfinder_report(cedar_students, cedar_sections, cedar_faculty, opt)
# Creates: seatfinder-202580-FT.html
}

```

---

## sfr

### `get_perm_faculty_count()`

*Source: sfr.R*

**Get Permanent Faculty Count from CEDAR Faculty Table**

Get Permanent Faculty Count from CEDAR Faculty Table  Calculates FTE (full-time equivalent) counts for permanent faculty by summing appointment percentages. Uses the cedar_faculty table with normalized CEDAR column names.

**Parameters:**

- `cedar_faculty` - Data frame from cedar_faculty table with columns: term, department, job_category, appointment_pct

**Returns:** Data frame with columns: \itemize{ \item \code{term} - Term code \item \code{department} - Department code (lowercase) \item \code{total} - FTE count (sum of appointment percentages) } Returns NULL if cedar_faculty is NULL, empty, or missing required columns.

**Details:**

Permanent faculty categories included in FTE calculation: \itemize{ \item professor \item associate_professor \item assistant_professor \item lecturer }  Excluded categories (non-permanent): \itemize{ \item term_teacher \item tpt (temporary part-time) \item grad (graduate assistants) \item professor_emeritus }  FTE calculation example: A professor at 100% appointment + a lecturer at 50% appointment = 1.5 FTE for that department/term.

**Example:**
```r
\dontrun{
# Calculate permanent faculty FTE
perm_fac <- get_perm_faculty_count(cedar_faculty)

# View FTE by department for recent term
perm_fac %>% filter(term == 202510) %>% arrange(desc(total))
}

```

---

### `get_sfr()`

*Source: sfr.R*

**Calculate Student-Faculty Ratios**

Calculate Student-Faculty Ratios  Calculates student-faculty ratios (SFR) by merging headcount data with permanent faculty FTE counts. Separates majors and minors for detailed analysis.

**Parameters:**

- `data_objects` - Named list containing: \itemize{ \item \code{academic_studies} - Academic study data for headcount calculation \item \code{cedar_faculty} - CEDAR faculty table with normalized columns }

**Returns:** Data frame with columns: \itemize{ \item \code{term} - Term code (CEDAR naming) \item \code{department} - Department code (CEDAR naming, lowercase) \item \code{student_level} - Student level (Undergraduate/Graduate/GASM) \item \code{program_type} - Type: "all_majors" or "all_minors" \item \code{program_name} - Program name \item \code{total} - Faculty FTE count \item \code{students} - Student headcount \item \code{sfr} - Student-faculty ratio (students/total) } Returns NULL if headcount or faculty data is unavailable.

**Details:**

**CEDAR Data Model Only**  This function requires CEDAR-formatted data with lowercase column names.  Workflow: \enumerate{ \item Calls \code{get_headcount()} to get student headcount by department \item Calls \code{get_perm_faculty_count()} to get faculty FTE \item Merges headcount with faculty data (both use CEDAR naming) \item Filters out summer terms (term ending in 60) \item Separates majors from minors \item Calculates SFR = students / faculty_fte }  Major types included: \itemize{ \item Majors: "Major", "Second Major" \item Minors: "First Minor", "Second Minor" }  **Note**: Summer terms are excluded as they're not meaningful for SFR analysis.

**Example:**
```r
\dontrun{
# Calculate SFRs
data_objects <- list(
  academic_studies = academic_studies_data,
  cedar_faculty = cedar_faculty
)
sfr_data <- get_sfr(data_objects)

# View undergraduate major SFRs for Fall 2025
sfr_data %>%
  filter(term == 202510, `Student Level` == "Undergraduate", major_type == "all_majors") %>%
  arrange(desc(sfr))
}

```

---

### `get_sfr_data_for_dept_report()`

*Source: sfr.R*

**Get SFR Data for Department Reports**

Get SFR Data for Department Reports  Generates student-faculty ratio plots and data for department-specific reports. Creates separate visualizations for undergraduate and graduate students, plus a scatter plot showing the department in context of the full college.

**Parameters:**

- `data_objects` - Named list containing academic_studies and cedar_faculty data
- `d_params` - Department report parameters list with: \itemize{ \item \code{dept_code} - Department code (e.g., "HIST", "MATH") \item \code{plots} - Existing plots list (will be updated) }

**Returns:** Updated d_params list with added plots: \itemize{ \item \code{ug_sfr_plot} - Undergraduate SFR bar chart by term and major type \item \code{grad_sfr_plot} - Graduate SFR bar chart by term and major type \item \code{sfr_scatterplot} - Department in college context (all terms, majors only) } If insufficient data, plots will contain error messages instead of ggplot objects.

**Details:**

Plot specifications:  **Undergraduate SFR Plot**: \itemize{ \item X-axis: term \item Y-axis: sfr (students per faculty) \item Fill: major_type (all_majors vs all_minors) \item Grouped bar chart }  **Graduate SFR Plot**: \itemize{ \item Same structure as undergraduate plot \item Filtered for Graduate/GASM student level }  **SFR Scatterplot** (College Context): \itemize{ \item Shows all college departments as gray points/lines \item Highlights target department in color \item Y-axis limited to 0-50 (except PSYC which often has higher ratios) \item Uses major data only (excludes minors) }

**Example:**
```r
\dontrun{
# Generate SFR plots for History department
data_objects <- list(
  academic_studies = academic_studies_data,
  cedar_faculty = cedar_faculty
)
d_params <- list(dept_code = "HIST", plots = list())
d_params <- get_sfr_data_for_dept_report(data_objects, d_params)

# Access plots
print(d_params$plots$ug_sfr_plot)
print(d_params$plots$grad_sfr_plot)
print(d_params$plots$sfr_scatterplot)
}

```

---

## transform-to-cedar

### `transform_to_cedar()`

*Source: transform-to-cedar.R*

**Transform MyReports data to CEDAR model**

Transform MyReports data to CEDAR model  Reads existing parsed data files (DESRs, class_lists, etc.) and creates new CEDAR model files (cedar_sections, cedar_students, etc.)  This script is designed to run daily after parse-data.R completes. It will OVERWRITE existing cedar_* files with the latest data.

**Parameters:**

- `data_dir` - Path to data directory (default: from config)
- `use_qs` - Use .qs format (default: from config)

**Returns:** List of CEDAR data objects

---

## utils

### `add_acad_year()`

*Source: utils.R*

**Add academic year column based on term codes**

Add academic year column based on term codes  This function takes a data frame and a column containing term codes (e.g., "202380" for Fall 2023) and adds a new column `acad_year` representing the academic year (e.g., "2023-2024"). The academic year is determined by the semester code: - "80" (fall): academic year starts with the term year - "10" (spring) and "60" (summer): academic year ends with the term year If the semester code is not recognized, NA is assigned.

**Parameters:**

- `df` - Data frame containing term codes
- `term_col` - Column name (unquoted or quoted) containing term codes

**Returns:** Data frame with added `acad_year` column

---

## waitlist

### `get_unique_waitlisted()`

*Source: waitlist.R*

**Get Unique Waitlisted Students Not Registered**

Get Unique Waitlisted Students Not Registered  Identifies students who are waitlisted for a course but not registered, providing counts by campus and course. This helps identify "true" waitlist demand by excluding students who are registered for another section.

**Parameters:**

- `filtered_students` - Data frame of student enrollments from cedar_students table, already filtered by opt parameters. Must include columns: campus, term, subject_course, course_title, student_id, registration_status
- `opt` - Options list (currently unused but kept for consistency)

**Returns:** Data frame with columns: \itemize{ \item \code{campus} - Campus code \item \code{subject_course} - Course identifier \item \code{count} - Number of unique students waitlisted only (not registered) } Sorted by campus, subject_course, and descending count.

**Details:**

The function performs the following steps: \enumerate{ \item Identifies unique waitlisted students (registration_status = "Wait Listed") \item Identifies registered students (registration_status contains "Registered") \item Uses set difference to find students waitlisted but not registered \item Groups by campus and course, counting unique students \item Sorts results for easy interpretation }  This is useful for understanding "real" waitlist demand - students who want the course but couldn't get in, as opposed to those who are registered elsewhere.

**Example:**
```r
\dontrun{
# Get waitlist counts for MATH courses
opt <- list(subject = "MATH", term = "202510")
filtered <- filter_class_list(cedar_students, opt)
waitlist_counts <- get_unique_waitlisted(filtered, opt)
}

```

---

### `inspect_waitlist()`

*Source: waitlist.R*

**Inspect Waitlist by Major and Classification**

Inspect Waitlist by Major and Classification  Comprehensive waitlist analysis that breaks down waitlisted students by their major and classification. This provides insight into which student populations are being waitlisted and helps with enrollment planning and advising.

**Parameters:**

- `students` - Data frame of student enrollments from cedar_students table. Must include columns: campus, college, term, term_type, major, student_classification, subject_course, course_title, level, registration_status
- `opt` - Options list for filtering: \itemize{ \item \code{course} - Course identifier(s) (e.g., "MATH 1430") \item \code{term} - Term code(s) (e.g., 202510) \item \code{subject} - Subject code(s) (e.g., "MATH") \item Other filtering options supported by \code{filter_class_list()} }

**Returns:** Named list with three elements: \itemize{ \item \code{majors} - Data frame summarizing waitlist by major/program. Columns: campus, term, subject_course, course_title, major, count \item \code{classifications} - Data frame summarizing waitlist by student level. Columns: campus, term, subject_course, course_title, student_classification, count \item \code{count} - Data frame of unique waitlisted students (see \code{\link{get_unique_waitlisted}}) }

**Details:**

This function performs the following steps: \enumerate{ \item Filters students using \code{filter_class_list()} with provided options \item Restricts to waitlisted students only (registration_status = "Wait Listed") \item Groups data by campus, college, term, course, and demographics \item Calls \code{summarize_student_demographics()} twice: \itemize{ \item Once grouped by major (major) \item Once grouped by classification (student_classification) } \item Computes unique waitlisted counts via \code{get_unique_waitlisted()} \item Returns cleaned summaries with unnecessary columns removed }  The returned data is useful for: \itemize{ \item Understanding which majors have highest waitlist demand \item Identifying whether freshmen vs upperclassmen are being waitlisted \item Planning section additions or seat reservations \item Advising students about course availability }

**Example:**
```r
\dontrun{
# Analyze waitlist for specific course
opt <- list(course = "MATH 1430", term = 202510)
waitlist_analysis <- inspect_waitlist(cedar_students, opt)

# View by major
head(waitlist_analysis$majors)

# View by classification
head(waitlist_analysis$classifications)

# Analyze all BIOL courses in a term
opt <- list(subject = "BIOL", term = "202510")
bio_waitlist <- inspect_waitlist(cedar_students, opt)
}

```

---

