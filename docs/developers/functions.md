---
title: Function Reference
nav_order: 4
parent: Developer Guide
---

# CEDAR Function Reference

This reference is auto-generated from roxygen2 comments in the source code.

*Generated: 2026-08-31 17:18:53.295311*

---

## bottleneck

### `get_bottlenecks()`

*Source: bottleneck.R*

**Get Enrollment Demand Bottlenecks for a Cohort**

Get Enrollment Demand Bottlenecks for a Cohort  For each course, counts cohort students who are waitlisted but hold no registered seat — the clearest signal of unmet demand. Results are returned per campus and course, sorted by waitlist count.  If the cohort contains multiple labels (from `build_population()` with `include_pre_majors = "split"`), a `$by_label` table is also returned showing results broken out by cohort label.

**Parameters:**

- `cohort` - Data frame. Output of `build_population()`. Must have columns `student_id` and `population_label`.
- `students` - Data frame. The `cedar_students` table.
- `opt` - List of options: \describe{ \item{`term`}{Integer or character vector of term codes to restrict to. Optional; defaults to all terms.} \item{`campus`}{Character vector of campus codes. Optional.} }

**Returns:** Named list: \describe{ \item{`waitlist`}{Data frame of enrollment bottlenecks, sorted descending by `n_waitlisted`. Columns: `campus`, `subject_course`, `n_waitlisted`.} \item{`population_size`}{Named integer vector: number of unique student IDs per cohort label.} \item{`by_label`}{Data frame breaking down waitlist counts by `population_label`. Only present when the cohort has more than one distinct label.} }

**Example:**
```r
\dontrun{
cedar_programs <- qs_read("data/cedar_programs.qs")
cedar_students <- qs_read("data/cedar_students.qs")

cohort <- build_population(cedar_programs, opt = list(type = "health"))
result <- get_bottlenecks(cohort, cedar_students, opt = list())
result$waitlist
result$population_size
}

```

---

### `compute_waitlist_pressure()`

*Source: bottleneck.R*

**Compute Waitlist Pressure for a Student Cohort**

Compute Waitlist Pressure for a Student Cohort  Counts cohort students who are waitlisted for a course and hold no registered seat in that course — i.e., students who couldn't get in. Students who are both waitlisted and registered (hedging across sections) are excluded from the count.

**Parameters:**

- `students` - Data frame. The `cedar_students` table, optionally pre-filtered by term/campus.
- `cohort_ids` - Character vector of student IDs to include.

**Returns:** Data frame sorted descending by `n_waitlisted`: \describe{ \item{`campus`}{Course-delivery campus code.} \item{`subject_course`}{Course identifier, e.g., `"BIOL 2310"`.} \item{`n_waitlisted`}{Unique cohort students waitlisted and not registered for this course.} }

---

## cancellations

### `get_cancellations()`

*Source: cancellations.R*

**Analyze Cancelled Course Sections**

Analyze Cancelled Course Sections  Returns cancelled section rows and summary tables for the Explore > Cancellations page. Cancellation is defined narrowly as section status "C"; related non-active statuses are counted separately for page context.

**Parameters:**

- `sections` - CEDAR sections table.
- `opt` - Filter options compatible with filter_DESRs().

**Returns:** Named list with cancelled sections, summary tables, and status notes.

---

## comparison

### `build_comparison()`

*Source: comparison.R*

**Build a labeled treatment/control tibble with covariates and balance stats**

Build a labeled treatment/control tibble with covariates and balance stats  Joins covariates from cedar_programs at each student's reference term and optionally cedar_applicants. Returns labeled groups and a balance table with standardized mean differences so the caller can assess comparability.  By default, covariates are pulled at the student's entry term (first term in the system). Callers can pass \code{covariate_terms} to use a specific term per student instead — e.g., the term they took course X — which gives a more meaningful snapshot of GPA and credits at the point of comparison.

**Parameters:**

- `treatment_ids` - Character vector of student IDs in the treatment group.
- `pool_ids` - Character vector of eligible control student IDs. Must already exclude treatment_ids and any ineligible students.
- `programs` - cedar_programs data frame.
- `applicants` - cedar_applicants data frame, or NULL to skip admissions covariates.
- `students` - cedar_students data frame, used to determine each student's entry term (first term with any enrollment). If NULL, entry term is derived from programs instead.
- `covariate_terms` - Optional named integer vector or two-column tibble (student_id, covariate_term) giving the term at which to pull program covariates for each student. Overrides the entry-term default for any student present in this argument; students not listed fall back to entry term.

**Returns:** Named list: \describe{ \item{groups}{Tibble: student_id, group ("treatment"/"control"), entry_term, and all available covariates.} \item{balance}{Named list from compute_balance(): smd_table and categorical.} \item{n_treatment}{Integer. Students in treatment group.} \item{n_control}{Integer. Students in control group.} }

---

### `compute_balance()`

*Source: comparison.R*

**Compute covariate balance between treatment and control groups**

Compute covariate balance between treatment and control groups  For binary and continuous covariates, computes group means/proportions and standardized mean differences (SMDs). Absolute SMDs below 0.10 are classified as small observed differences, values from 0.10 through 0.25 require review, and values above 0.25 are classified as substantial observed differences. These descriptive bands do not establish comparability or remove confounding.  SMD formulas: Binary:     (p_t - p_c) / sqrt(p_bar * (1 - p_bar)) Continuous: (mu_t - mu_c) / sqrt((var_t + var_c) / 2)  Categorical covariates (ipeds_race, time_status, etc.) are returned as frequency distributions rather than SMDs — proportions don't reduce to a single meaningful scalar.

**Parameters:**

- `groups` - Tibble from build_comparison() with a "group" column.

**Returns:** Named list: \describe{ \item{smd_table}{Tibble sorted by |SMD| descending: covariate, type, n_treatment, n_control, value_treatment, value_control, unit, smd, balance_band, flagged. SMD retains full precision; display layers round it.} \item{categorical}{Named list of frequency tibbles for categorical covariates.} \item{overall_balance}{The most serious observed SMD band, or unavailable when no SMD can be estimated.} }

---

## course-demographics

### `abbreviate_classification()`

*Source: course-demographics.R*

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

### `get_course_major_mix()`

*Source: course-demographics.R*

**Get Major Mix for a Course Set**

Get Major Mix for a Course Set  Summarizes the major/program mix for students enrolled in a selected set of courses. Counts are enrollment rows, not unique students, so a student taking two selected courses contributes two seats to the mix. The enrollment-row major code is used as the baseline because it is attached to the course term; same-term primary program records are used when available for cleaner names and pre-major labels.

**Parameters:**

- `students` - Data frame of student enrollments from cedar_students.
- `programs` - Data frame of program records from cedar_programs.
- `opt` - Options list. Supports course/term/campus/college filters accepted by filter_class_list(), plus min_n and top_n for display grouping.

**Returns:** Tibble with major_label, n_enrollments, n_students, pct_enrollments.

---

### `create_demographics_color_palette()`

*Source: course-demographics.R*

**Create Consistent Color Palette for Demographics Plots**

Create Consistent Color Palette for Demographics Plots  Generates a consistent color mapping for categories across multiple plots to ensure the same majors/classifications have the same colors in fall, spring, and summer plots.

**Parameters:**

- `demographics_data` - A dataframe from \code{summarize_student_demographics()}.
- `fill_column` - The column name to use for color mapping (e.g., "student_classification" or "major")
- `top_n` - Number of top categories to include in color palette (default: 10)

**Returns:** A named vector of colors where names are category values

**Example:**
```r
color_palette <- create_demographics_color_palette(demographics_data, "major", top_n = 8)
```

---

### `plot_demographics_summary()`

*Source: course-demographics.R*

**Plot Demographics Summary (Donut Charts)**

Plot Demographics Summary (Donut Charts)  Creates interactive donut charts showing the average distribution of student classifications or majors for a course, grouped by term type (fall, spring, summer).  This function does NOT perform calculations. It expects pre-calculated values from \code{\link{summarize_student_demographics}}: \itemize{ \item \code{mean} - Average student count for each category across terms of same term_type \item \code{term_type_pct} - Percentage based on average total enrollment for term_type }

**Parameters:**

- `demographics_data` - Data frame from \code{summarize_student_demographics()}. Must contain columns: fill_column, term_type, mean, term_type_pct, campus, college, subject_course
- `fill_column` - Column name to group by (e.g., "student_classification" or "major")
- `color_palette` - Named vector of colors from \code{create_demographics_color_palette()}
- `filter_column` - Optional list with \code{column} and \code{values} for filtering

**Returns:** Named list of plotly donut charts: fall, spring, summer, by_term

---

### `get_course_demographics()`

*Source: course-demographics.R*

**Get Course Demographics**

Get Course Demographics  Analyzes the demographic composition (majors, classifications, etc.) of students in a course or set of courses over time. Returns counts, means across terms, and percentages of course enrollment — answering "who is in this course?"

**Parameters:**

- `students` - Data frame of student enrollments from cedar_students table.
- `opt` - Options list for filtering and grouping: \itemize{ \item \code{group_cols} - Character vector of columns to group by. If NULL, uses defaults: campus, college, term, term_type, student_classification, major, subject_course, course_title, level \item \code{reg_status_code} - Registration status codes to include (default: STATUS_REGISTERED) \item \code{course} - Course identifier(s) to filter by \item \code{term} - Term code(s) to filter by \item Other filtering options supported by \code{filter_class_list()} }

**Returns:** Data frame with student demographic breakdown including counts, means, and percentages. See \code{\link{summarize_student_demographics}} for column details.

**Example:**
```r
\dontrun{
# Major composition of a course over time
opt <- list(
  course     = "BIOL 2305",
  group_cols = c("campus", "term", "term_type", "major", "subject_course")
)
major_breakdown <- get_course_demographics(cedar_students, opt)

# Classification breakdown across all MATH courses
opt <- list(
  subject    = "MATH",
  group_cols = c("campus", "term", "student_classification", "subject_course")
)
class_breakdown <- get_course_demographics(cedar_students, opt)
}

```

---

### `plot_time_series()`

*Source: course-demographics.R*

**Plot Classification Time Series**

Plot Classification Time Series  Creates line plots showing the actual term-level percentage of students in each classification or major across terms over time.

**Parameters:**

- `demographics_data` - A dataframe from \code{summarize_student_demographics()}.
- `fill_column` - Column to group by (default: "student_classification")
- `value_column` - Column to use for y-axis values (default: "term_pct")
- `top_n` - Number of top categories to display (default: 5)

**Returns:** A plotly object showing time series lines.

---

### `plot_demographics_with_consistent_colors()`

*Source: course-demographics.R*

**Plot Demographics with Consistent Colors Across Terms**

Plot Demographics with Consistent Colors Across Terms  Wrapper that creates demographics donut charts with a consistent color mapping across all term types (fall, spring, summer).

**Parameters:**

- `demographics_data` - A dataframe from \code{summarize_student_demographics()}.
- `fill_column` - The column name to use for fill aesthetic.
- `top_n` - Number of top categories to include (default: 7)
- `filter_column` - Optional list with column name and values to filter (e.g., list(column = "campus", values = c("ABQ")))

**Returns:** A list of plotly charts with consistent colors across term types.

**Example:**
```r
consistent_plots <- plot_demographics_with_consistent_colors(demographics_data, "major", top_n = 8)
```

---

## course-flows

### `summarize_concurrent_courses()`

*Source: course-flows.R*

**Summarize courses taken alongside a selected course**

Summarize courses taken alongside a selected course  Collapses the classification and term-type detail returned by `get_concurrent_courses()` into one campus-course row. Counts use student-term enrollments, so a student who takes the selected course in two terms contributes twice. The denominator includes every registered selected-course student-term in the campus scope, including students who did not take a given companion course.

**Parameters:**

- `concurrent` - Output from `get_concurrent_courses()`.
- `top_n` - Optional maximum number of campus-course rows to retain.

**Returns:** A campus-grained tibble ordered by share of selected-course student-term enrollments.

---

### `get_downstream_pair_audit()`

*Source: course-flows.R*

**Course-level eligibility and order audit for a downstream pair**

Course-level eligibility and order audit for a downstream pair  Counts every student once, independent of instructor attribution. The year table keys a student to the calendar year of their first X attempt and shows whether they had already passed Y strictly earlier or in that same term.

**Parameters:**

- `students` - cedar_students.
- `course_x` - Character. Upstream course.
- `course_y` - Character vector. Selected downstream course(s).
- `opt` - Named list with `campus` and `data_edges`.

**Returns:** List with one-row `summary` and `order_by_year` tibbles.

---

### `get_downstream_course_options()`

*Source: course-flows.R*

**Courses students took after a given course**

**Parameters:**

- `students` - cedar_students.
- `course_x` - Character. The upstream course.
- `opt` - Named list: \describe{ \item{campus}{Character vector of course-delivery campus codes. Pass the same value the analysis will use so the counts agree.} \item{min_n}{Integer. Drop follow-on courses below this many students. Default 15, matching the impact analyses' default.} \item{data_edges}{Optional output of [cedar_data_edges()]. Follow-on enrollment is capped at the longitudinal grade edge (the earlier of `last_enrolled_complete` and `last_graded`), and recent X cohorts without a subsequent regular term by that edge are excluded from the picker denominator. Derived from `students` when omitted.} }

**Returns:** Tibble ordered by same-department first, then share of X's students: subject_course, course_title, department, n_students, pct_of_x, same_dept.  No term-gap column: term codes are YYYYSS, so differencing them does not yield a number of semesters, and a plausible-looking wrong gap is worse than no gap at all. Add it via term_diff() if it is ever needed.

---

## course-impact

### `get_course_sequence_effect()`

*Source: course-impact.R*

**Course Sequence Effect**

Course Sequence Effect  Compares grades in course Y between students who passed course X before their first observed, classifiable Y attempt (treatment) and students whose first such Y attempt occurred without a prior in-scope X pass (control). Surfaces whether completing X meaningfully prepares students for Y.

**Parameters:**

- `students` - cedar_students data frame.
- `programs` - cedar_programs data frame.
- `applicants` - cedar_applicants data frame, or NULL.
- `data_edges` - Optional output of [cedar_data_edges()]. Y outcomes stop at the longitudinal grade edge: the earlier of `last_enrolled_complete` and `last_graded`.
- `opt` - Named list: \describe{ \item{course_x}{Character. The preparatory course. Required.} \item{course_y}{Character. The outcome course. Required.} \item{campus}{Character vector. Optional campus filter.} \item{min_n}{Integer. Minimum students per group (default 15).} \item{filters}{Named list of covariate equality filters. Optional.} }

**Returns:** Named list: \describe{ \item{course_x, course_y}{Course identifiers.} \item{outcomes}{Tibble: group, outcome (pass/dfw), n, pct.} \item{group_profile}{Compact covariate summary per group.} \item{balance}{From compute_balance().} \item{n_treatment, n_control}{Group sizes.} }

---

### `get_instructor_effect()`

*Source: course-impact.R*

**Downstream Success by Instructor**

Downstream Success by Instructor  Among students who took course X and later took course Y, compares grade outcomes in Y between students taught by different instructors in X. Surfaces descriptive differences in downstream outcomes by upstream instructor.  The balance table reveals whether instructor sections self-selected different kinds of students — the most common confounder in multi-section courses.

**Parameters:**

- `students` - cedar_students data frame.
- `programs` - cedar_programs data frame.
- `applicants` - cedar_applicants data frame, or NULL.
- `opt` - Named list: \describe{ \item{course_x}{Character. The upstream course. Required.} \item{course_y}{Character. The downstream outcome course. May name several courses, in which case the analysis becomes a rollup across all of them and each student is counted once, at their earliest enrolment in the set. Required.} \item{campus}{Character vector. Optional campus filter.} \item{min_n}{Integer. Minimum students per instructor who later took Y (default 15). Instructors below this threshold are excluded.} }
- `data_edges` - Optional output of [cedar_data_edges()]. When omitted it is derived from `students`. X cohorts stop at `last_enrolled_complete`; grade outcomes stop at the earlier of that edge and `last_graded`. Cohorts without one subsequent regular term before the complete-enrollment edge are excluded from the continuation denominator.

**Returns:** Named list: \describe{ \item{course_x, course_y}{Course identifiers.} \item{outcomes}{Eligibility, continuation, and observed Y outcomes by each student's first instructor in X.} \item{order_audit_by_year}{Course-level yearly counts of students who passed Y strictly before or in the same term as their first X attempt.} \item{course_summary}{Course-level continuation denominator and rate, independent of instructor attribution and display thresholds.} \item{instructor_counts}{Tibble: instructor_name, n (students who took Y).} \item{balance}{Balance between the two most-common instructors' student pools.} \item{n_treatment, n_control}{Sizes for the reference instructor comparison.} }

---

## course-neighbors

### `plot_concurrent_course_treemap()`

*Source: course-neighbors.R*

**Plot courses taken alongside a selected course**

**Parameters:**

- `concurrent_courses` - Output from `summarize_concurrent_courses()`.
- `opt` - Named list. `max_courses` limits displayed campus-course rows.

**Returns:** A Plotly treemap, or `NULL` when no concurrent courses are present.

---

## course-outcomes

### `get_course_outcomes()`

*Source: course-outcomes.R*

**Analyze outcomes for one or more courses**

Analyze outcomes for one or more courses  Runs all three outcome analyses — persistence, DFW trend, and instructor comparison — and returns them as a named list.  DFW trend and instructor comparison delegate to get_course_outcome_rates() so the DFW formula and component fields match the rest of the app.  Persistence filtering and deduplication are handled internally.

**Parameters:**

- `students` - cedar_students data frame.
- `cedar_faculty` - cedar_faculty data frame, or NULL to skip DFW analyses.
- `opt` - Options list: \itemize{ \item \code{course}  — character vector of subject_course values (required) \item \code{term}    — integer vector; restrict to these terms (optional) \item \code{campus}  — character vector; restrict by campus (optional) \item \code{min_n}   — integer; minimum graded students per group (default 5) \item \code{data_edges} — output of [cedar_data_edges()]; longitudinal grade outputs stop at the earlier of the complete-enrollment and graded edges, while persistence eligibility uses the complete-enrollment edge }

**Returns:** Named list: \describe{ \item{persistence}{Tibble from \code{next_term_persistence()}} \item{dfw_trend}{Tibble: campus, college, subject_course, term, dfw_pct} \item{instructor_dfw}{Tibble: campus, college, subject_course, instructor_id, instructor_name, dfw_pct, course_avg_dfw, dfw_diff} \item{courses}{Character vector of courses analyzed} }

---

### `next_term_persistence()`

*Source: course-outcomes.R*

**Next-term persistence by grade outcome**

Next-term persistence by grade outcome  For each grade outcome (pass / dfw / drop), reports how many students returned to any course the following term. Gives a course-level view of whether bad outcomes actually drive students away.  Uses the full \code{all_students} table (not pre-filtered) as the enrollment source when checking whether a student returned — so next-term returns outside the filtered course set are detected correctly.  Early drops get their own "drop" outcome here, separate from academic DFW, because the persistence question is different for each group.

**Parameters:**

- `filtered` - Deduplicated cedar_students rows for the target course(s).
- `all_students` - Full cedar_students table.
- `opt` - Options list; uses \code{opt$min_n} (default 5), and either `opt$data_edges` or `opt$observation_end_term` to exclude cohorts whose next regular term is not yet complete.

**Returns:** Tibble: campus, subject_course, outcome, n_students, n_returned, pct_returned; sorted by campus, subject_course, outcome.

---

## course-retention

### `summarize_retention_by_term_type()`

*Source: course-retention.R*

**Summarize term-level retention rates across like term types**

Summarize term-level retention rates across like term types  Converts the term rows returned by `get_retention_trend()` into stable Fall/Spring/Summer summaries. Rates are weighted by the starting cohort size, so a 100-student term contributes more than a 10-student term. Each horizon uses only terms for which that future term is observable; `eligible_N` records the corresponding denominator.  Campus is always part of the grouping key. When `by_instructor` is TRUE, instructor identity is preserved as well.

**Parameters:**

- `retention_result` - Result from `get_retention_trend()` or `get_dept_retention_trend()`.
- `by_instructor` - Logical; aggregate separately by instructor.
- `min_n` - Integer; minimum pooled cohort size for a summary row and for each displayed horizon. Small individual terms may contribute to a pooled row as long as the pooled denominator meets this threshold.

**Returns:** One row per campus and term type, optionally per instructor, with `terms`, `n`, `ret_1 ... ret_N`, and `eligible_1 ... eligible_N`.

---

## credit-hours

### `get_credit_hours()`

*Source: credit-hours.R*

**Summarize credit hours by term, campus, college, department, subject, and level**

Summarize credit hours by term, campus, college, department, subject, and level  This is the foundational summary used by all department-level SCH plots. It counts only credit hours earned through passing grades — we don't count withdrawals, failures, or incompletes because those don't represent completed academic work from the department's perspective.  The result includes both individual level rows (lower/upper/grad) AND a "total" row per group that sums across all levels — so downstream callers can choose either view without re-aggregating.

**Parameters:**

- `students` - cedar_students data frame
- `term_start,term_end` - Optional integer term-code bounds.
- `departments,colleges,campuses` - Optional scope filters. When both departments and colleges are supplied, rows matching either are retained.

**Returns:** Long-format data frame with columns: term, campus, college, department, subject_code, level, total_hours. Level values: "lower", "upper", "grad", "total".

---

### `infer_credit_hours_dept_college()`

*Source: credit-hours.R*

**Infer the college that owns a department for SCH comparisons**

Infer the college that owns a department for SCH comparisons  Uses passing SCH in the selected term/campus scope when possible, then falls back to all rows for the department. Weighting by SCH is more robust than counting already-summarized rows, especially when a department has multiple subject codes or uneven course levels.

---

### `build_major_level_data()`

*Source: credit-hours.R*

**Filter and normalize student data for credit-hours-by-major analysis**

Filter and normalize student data for credit-hours-by-major analysis  Before we analyze who is taking courses in a department, we need to narrow the data to the right time window and remove students who didn't pass.  Also fixes a Banner data inconsistency: the College of Education appears under two different strings depending on the export vintage. We normalize to one display name so grouping works correctly.

**Parameters:**

- `students` - cedar_students data frame
- `term_start` - Integer term code for the beginning of the analysis window
- `term_end` - Integer term code for the end of the analysis window

**Returns:** Filtered data frame, ready for major-level analysis

---

### `build_major_summary()`

*Source: credit-hours.R*

**Summarize SCH by major and split into home vs. outside**

Summarize SCH by major and split into home vs. outside  For a given set of course enrollment rows (already filtered to a level like "lower" or "upper"), this function totals the credit hours per major and then divides them into two groups: - "Home" majors: students whose declared major belongs to this department - "Outside" majors: students from other departments who are taking these courses  This is the foundation of the pie charts that show a department's service function to the rest of the university.

**Parameters:**

- `level_data` - Filtered student enrollment rows for one course level Required cols: major, major_name, credits
- `major_codes` - Character vector of major codes that belong to this department (e.g., c("BIOL", "FBIO", "CHBI") for Biology)

**Returns:** Named list with slots: major_summary — all majors with total hours home          — only the department's own majors outside       — all other majors home_hours, outside_hours, total_hours — scalar totals

---

### `build_outside_pie_data()`

*Source: credit-hours.R*

**Group outside majors by display name and decide which get their own slice**

Group outside majors by display name and decide which get their own slice  The raw outside-major data can have dozens of programs. If we gave every small program its own slice, the pie chart would become unreadable. But a hard "top N" cutoff can hide important groups — for example, Nursing students might be the #10 largest group but still represent a meaningful story.  Instead we use a percentage threshold: any program that accounts for at least 3% of total outside SCH gets a named slice. The rest roll into "Other". We cap the named groups at 12 to keep the legend legible.  Each Banner program code gets its own slice. Display names are carried in major_name for use in tables only — plots label by major_code so that code variants (NURS, FNRS, FNAP) are visible separately rather than being silently merged or split by name drift.  The color map built here is shared with the time-series bar chart, so each program code gets the same color in both views.

**Parameters:**

- `outside_summary` - The "outside" slot from build_major_summary() — a data frame with major_code, major_name, and total_hours columns
- `pct_threshold` - Fraction of outside SCH required for a named slice (default 0.03 = 3%)
- `max_named` - Hard cap on the number of named slices (default 12)

**Returns:** Named list: outside_for_pie — complete ranking of all outside programs by code + name; used as the full export table named_outside   — only programs that clear the threshold (capped at max_named) top_outside     — named_outside plus an "Other" row for everything else color_map       — named character vector mapping each major_code to a color outside_total   — scalar: total outside SCH

---

### `build_outside_time_data()`

*Source: credit-hours.R*

**Build the term-by-term data for the outside-major bar chart**

Build the term-by-term data for the outside-major bar chart  The pie charts show averages across the whole analysis window. The time- series bar chart shows the same grouping (same named programs, same "Other" bucket) but laid out term by term so you can see trends over time.  The named programs here must match exactly what build_outside_pie_data() selected, so the two charts tell a consistent story: a program named in the pie also appears as its own bar in the time series.

**Parameters:**

- `level_data` - Filtered student enrollment rows for one course level Required cols: major, major_name, credits, term
- `major_codes` - Home department major codes — excluded from outside count
- `named_outside_codes` - The major_code values from build_outside_pie_data() $named_outside — these are the program codes that get their own bar color

**Returns:** Data frame: term (as a factor), major_group (chr), total_hours (dbl)

---

### `build_credit_hours_wide_table()`

*Source: credit-hours.R*

**Build the wide-format SCH summary table (major × term)**

Build the wide-format SCH summary table (major × term)  This is the export table that appears in the report alongside the charts. It shows each major as a row and each term as a column, so a reader can scan across a row to see how a program's SCH has changed over time.  A "Total" row at the bottom sums every column, and missing values (a major that didn't appear in a particular term) are shown as 0. Rows are sorted by the most recent term so the most active programs appear first.

**Parameters:**

- `filtered_students` - Filtered student rows (all levels combined)

**Returns:** Wide data frame: student_college, major, then one column per term

---

### `compute_major_sch_trends()`

*Source: credit-hours.R*

**Compute SCH growth and decline trends for outside majors**

Compute SCH growth and decline trends for outside majors  This function asks: "Which outside programs are sending more or fewer students to this department compared to the recent past?"  We measure trends over three windows: 1-year, 2-year, and 4-year. Each window compares the average SCH over the most recent N terms against the same-length window immediately before that.  Summer terms are excluded from all windows because summer enrollment behaves very differently from the regular academic year — including summer would distort the averages and make year-over-year comparisons misleading.  We rank by absolute change (e.g., +200 SCH) rather than percentage change (e.g., +20%) to avoid a tiny program with explosive percentage growth appearing more important than a large program with modest but consequential absolute growth.  Window requirements (needs enough history in the data): 1yr: needs ≥ 4 fall/spring terms in the range 2yr: needs ≥ 6 fall/spring terms 4yr: needs ≥ 10 fall/spring terms

**Parameters:**

- `level_data` - Filtered student enrollment rows for one course level
- `major_codes` - Home department codes — only outside majors are analyzed
- `top_n` - How many top growing and declining programs to return (default 5)

**Returns:** list(growing, declining) — each a data frame with top_n rows, or NULL if there isn't enough history to compute any window

---

### `build_indexed_growth_data()`

*Source: credit-hours.R*

**Build the department-vs-college indexed growth comparison data**

Build the department-vs-college indexed growth comparison data  To understand whether a department's SCH growth is impressive or just keeping pace, we compare it against its whole college. We index both series to 100 at the first term — not because the starting value was 100, but so the two lines start at the same point and divergence becomes visible.  A department line above the college line means it's growing faster than average for the college. Below means it's falling behind relative to peers. The chart answers: "Is this department outpacing its college, or lagging?"

**Parameters:**

- `credit_hours_data` - Output of get_credit_hours(), already filtered to the desired term range
- `dept_code` - Department code (e.g., "BIOL")
- `dept_college` - College code this department belongs to (e.g., "AS")

**Returns:** Long-format data frame: term (factor), series (chr), indexed_value (dbl) series values: "<dept_code> Department" and "<dept_college> College"

---

### `build_college_credit_hours()`

*Source: credit-hours.R*

**Build college-wide credit hour data and department comparison frames**

Build college-wide credit hour data and department comparison frames  Produces three related summaries used by the college-level plots:  1. All departments in the college, summed by term — for the stacked bar showing how the whole college's SCH is distributed  2. Just this department's rows — used as the comparison line  3. A year-over-year delta comparison — shows how many percentage points faster or slower the department grew compared to the college as a whole (positive = outpacing the college that year; negative = lagging)

**Parameters:**

- `credit_hours_data` - Output of get_credit_hours(), filtered to term range
- `dept_college` - College code for this department
- `dept_code` - Department code

**Returns:** Named list: college_credit_hours, dept_credit_hours, diff_fr_college_hours

---

### `build_dept_subject_data()`

*Source: credit-hours.R*

**Build subject-level credit hour data for the department's own plots**

Build subject-level credit hour data for the department's own plots  This prepares three differently-shaped views of the same data — all filtered to just this department's courses on main campuses — for three different charts that visualize the same information at different levels of detail.

**Parameters:**

- `credit_hours_data` - Output of get_credit_hours(), filtered to term range
- `dept_code` - Department code

**Returns:** Named list with three data frames: by_subj_level — one row per (term, subject, level), level is NOT "total"; used for the faceted chart showing each subject broken down by lower/upper/grad by_subj_total — one row per (term, subject), level IS "total"; used for the stacked chart and the data export table by_period     — one row per (term, level) with an added period_hours column (the sum across all subjects for that level and term); used for the by-level stacked bar

---

### `plot_outside_majors_pie()`

*Source: credit-hours.R*

**Donut chart: which outside programs are taking courses here?**

Donut chart: which outside programs are taking courses here?  Shows the breakdown of outside-major SCH across all terms in the range. Each named slice is a program that sent enough students to clear the threshold; everything else is rolled into "Other".

**Parameters:**

- `top_outside` - top_outside slot from build_outside_pie_data()
- `color_map` - color_map slot from build_outside_pie_data()
- `level_label` - Display label for the title (e.g., "Lower Division")

**Returns:** plotly donut chart, or NULL if there are no outside majors

---

### `plot_home_outside_pie()`

*Source: credit-hours.R*

**Pie chart: what share of SCH goes to the department's own students?**

Pie chart: what share of SCH goes to the department's own students?  A simple two-slice chart: "Department Majors" vs. "Outside Majors". A service department (like English composition or core science) will show a large outside slice; a specialized program will show a large home slice.

**Parameters:**

- `home_hours,outside_hours,total_hours` - Scalar SCH totals from build_major_summary()
- `level_label` - Display label for the title

**Returns:** plotly pie chart, or NULL if total_hours is 0

---

### `plot_outside_time_series()`

*Source: credit-hours.R*

**Stacked bar: outside major credit hours by term**

Stacked bar: outside major credit hours by term  Shows the same programs as the pie chart but over time, so you can see whether outside-major enrollment is growing, shrinking, or shifting among programs. Uses the same colors as the pie chart for direct visual comparison.

**Parameters:**

- `time_data` - Output of build_outside_time_data()
- `color_map` - color_map slot from build_outside_pie_data()
- `level_label` - Display label for the title

**Returns:** plotly stacked bar chart, or NULL if time_data is empty

---

### `plot_indexed_growth()`

*Source: credit-hours.R*

**Line chart: department vs. college indexed SCH growth**

Line chart: department vs. college indexed SCH growth  Both lines start at 100 (the first term in the analysis window) so their trajectories can be directly compared regardless of their actual sizes. If the department line is above the college line, the department is growing faster than its college peers.

**Parameters:**

- `indexed_data` - Output of build_indexed_growth_data()
- `dept_code` - Used to identify the department series by name

**Returns:** ggplot line + point chart

---

### `plot_college_credit_hours()`

*Source: credit-hours.R*

**Stacked bar: all departments in the college, showing each department's share**

Stacked bar: all departments in the college, showing each department's share  Provides context for the department's SCH within its college — is this a large department, a medium one, or a small one relative to peers?

**Parameters:**

- `college_credit_hours` - college_credit_hours slot from build_college_credit_hours()

**Returns:** ggplotly interactive bar chart

---

### `plot_college_comp()`

*Source: credit-hours.R*

**Bar chart: how much faster or slower is the department growing vs. its college?**

Bar chart: how much faster or slower is the department growing vs. its college?  Bars above zero mean the department grew faster than the college average that year; bars below zero mean it grew slower. A consistently positive department is gaining share; a consistently negative one is losing share.

**Parameters:**

- `diff_fr_college_hours` - diff_fr_college_hours slot from build_college_credit_hours()

**Returns:** ggplot bar chart

---

### `plot_chd_by_subj_faceted()`

*Source: credit-hours.R*

**Faceted bar chart: credit hours by subject code and course level**

Faceted bar chart: credit hours by subject code and course level  Creates one panel per subject code (e.g., BIOL, BIOC, BIOM), with bars stacked by level (lower/upper/grad) so you can see both the volume and the mix for each subject area.

**Parameters:**

- `by_subj_level` - by_subj_level slot from build_dept_subject_data()
- `palette` - RColorBrewer palette name for the level fill colors

**Returns:** ggplot with one facet panel per subject code

---

### `plot_chd_by_subj_stacked()`

*Source: credit-hours.R*

**Stacked bar: total credit hours by subject code across all levels**

Stacked bar: total credit hours by subject code across all levels  A simpler view than the faceted chart — all subjects stacked in one bar per term, useful for seeing which subject area dominates and how the mix shifts over time.

**Parameters:**

- `by_subj_total` - by_subj_total slot from build_dept_subject_data()

**Returns:** ggplot stacked bar chart

---

### `plot_chd_by_level()`

*Source: credit-hours.R*

**Stacked bar: total credit hours by course level (lower/upper/grad)**

Stacked bar: total credit hours by course level (lower/upper/grad)  Shows the balance between undergraduate and graduate instruction over time. A shift in this chart might signal a change in the department's graduate program size or a major curriculum redesign.

**Parameters:**

- `by_period` - by_period slot from build_dept_subject_data()
- `subj_codes` - Subject codes shown in the chart title for reference
- `palette` - RColorBrewer palette name

**Returns:** ggplot stacked bar chart

---

### `credit_hours_by_major()`

*Source: credit-hours.R*

**Credit Hours by Major**

Credit Hours by Major  The main function for the "who is taking our courses" analysis. Runs the full pipeline three times — once for lower division, once for upper division, and once for all undergrad combined — then assembles all plots and tables.

**Parameters:**

- `students` - cedar_students data frame (pre-filtered to this department)
- `dept_code` - Department code (e.g., "BIOL")
- `term_start,term_end` - Integer term codes for the analysis window (inclusive)

**Returns:** list with: $plots:  sch_outside_pct_lower_plot, sch_dept_pct_lower_plot, sch_top_majors_lower_plot, sch_outside_pct_upper_plot, sch_dept_pct_upper_plot, sch_top_majors_upper_plot, sch_outside_pct_plot, sch_dept_pct_plot $tables: credit_hours_data_w, sch_major_trends_lower, sch_outside_full_lower, sch_major_trends_upper, sch_outside_full_upper

---

### `plot_chd_by_fac_faceted()`

*Source: credit-hours.R*

**Credit Hours by Faculty Category**

Credit Hours by Faculty Category  Shows how SCH production is distributed across faculty job categories — tenure-track, lecturer, adjunct, etc. Requires the cedar_faculty table, which is built from HR data and is not always available.

**Parameters:**

- `data_objects` - List containing cedar_students and cedar_faculty
- `dept_code` - Department code
- `subj_codes` - Subject codes for plot titles
- `term_start,term_end` - Integer term codes (inclusive)
- `palette` - RColorBrewer palette name

**Returns:** list($plots): chd_by_fac_facet_plot (breakdown by level), chd_by_fac_plot (totals stacked by job category)

---

### `get_credit_hours_for_dept_trends()`

*Source: credit-hours.R*

**Credit Hours for Dept Trends**

Credit Hours for Dept Trends  Produces the full set of department-level SCH plots: how the department compares to its college over time, broken down by subject code and level.

**Parameters:**

- `class_lists` - cedar_students data frame (full — not pre-filtered to dept)
- `dept_code` - Department code (e.g., "BIOL")
- `subj_codes` - Subject codes used in plot titles (informational only)
- `term_start,term_end` - Integer term codes for the analysis window (inclusive)
- `palette` - RColorBrewer palette name for bar chart colors

**Returns:** list with: $plots:  college_credit_hours_plot, college_credit_hours_comp_plot, college_dept_dual_plot, chd_by_year_facet_subj_plot, chd_by_year_subj_plot, chd_by_period_plot $tables: chd_by_period_table

---

### `get_credit_hours_for_dept_report()`

*Source: credit-hours.R*

**Legacy wrapper for retired Rmd department report callers**

---

## credit-timeline

### `credit_timeline_validity()`

*Source: credit-timeline.R*

**Build a Per-Term Credit Position for Students**

Build a Per-Term Credit Position for Students  One row per (student, enrolled term) giving how many credits the student had *entering* that term — the figure that answers "where were they when they did this" — and after completing it.

**Parameters:**

- `term_credits` - Data frame. `cedar_student_term_credits`, **unsliced by term** where possible — see `opt$student_first_terms`.
- `programs` - Data frame or NULL. `cedar_programs`, used only to recover each student's transfer block. NULL yields a UNM-only timeline with `transfer_credits = 0` and `total_*` equal to `unm_*`, which is honest but understates anyone who arrived with credit.
- `opt` - List. Accepts `student_ids`, `min_data_term`, and `student_first_terms`, with the same meanings as in [build_credit_timeline()].

**Returns:** Tibble of `student_id` and `timeline_valid`.

---

### `attach_credit_position()`

*Source: credit-timeline.R*

**Attach a Credit Position to Rows Keyed by Student and Term**

Attach a Credit Position to Rows Keyed by Student and Term  Join helper for the common case: a table of events (a major change, a course enrollment, a declaration) that needs "how far along were they".

**Parameters:**

- `events` - Data frame with `student_id` and a term column.
- `timeline` - Data frame from [build_credit_timeline()].
- `term_col` - Character. Name of the term column on `events`. Default `"term"`.
- `basis` - Character. `"total"` (default, includes transfer) or `"unm"`.

**Returns:** `events` with `credits_entering` and `timeline_valid` added. Rows with no matching timeline entry get NA rather than being dropped — an event in a term the student had no graded enrollment in is real and should stay visible, just without a credit position.

---

## data-edges

### `cedar_data_edges()`

*Source: data-edges.R*

**Where the loaded data starts and stops**

**Parameters:**

- `students` - Data frame. `cedar_students`. Required.
- `degrees` - Data frame or NULL. `cedar_degrees`, for `last_degree`.
- `min_graded_share` - Numeric 0-1. Share of a term's enrollment rows that must carry a final grade before the term counts as gradeable. Default `0.5`. The threshold is not finely balanced: on current data finished terms sit at 83-91% and in-flight terms at 0-7%, so anything from ~0.2 to ~0.8 picks the same edge.
- `max_term` - Optional integer. Ignore anything after this — pass a configured end term to keep a deliberately restricted report window.
- `min_days_after_start` - Integer. How long after a term begins its data must have been pulled before the term counts as settled. Default `14`, which clears add/drop. Needs an `as_of_date` column; without one `last_enrolled_complete` is NULL rather than a guess.

**Returns:** Named list: `first_enrolled`, `last_enrolled`, `last_graded`, `last_degree` (NULL when `degrees` is not supplied), and `graded_by_term`, a tibble of `term` / `rows` / `graded_share` so a caller can show its work rather than asserting an edge. Any edge that cannot be determined is NULL, never a guess.

---

### `cedar_edge_note()`

*Source: data-edges.R*

**One-line description of an edge, for display**

One-line description of an edge, for display  Surfaces that cap a view should say which edge they used and why, so a reader sees a data state rather than assuming a stale pipeline.

**Parameters:**

- `edges` - Output of [cedar_data_edges()].
- `which` - Character. `"graded"` or `"enrolled"`.

**Returns:** Character string, or NULL if that edge is unavailable.

---

### `cedar_longitudinal_edge()`

*Source: data-edges.R*

**Right edge for an analysis that needs later observations**

Right edge for an analysis that needs later observations  Descriptive enrollment may show the current or upcoming term. A longitudinal analysis may not: its right edge is the most recent term whose enrollment has settled. If the analysis also reads grades, both conditions must hold, so the earlier of the settled-enrollment and graded edges is used.

**Parameters:**

- `edges` - Output of [cedar_data_edges()].
- `grade_dependent` - Logical. Does the analysis read grades?

**Returns:** Integer term code, or NULL when the required edge is unavailable.

---

### `cedar_longitudinal_edge_note()`

*Source: data-edges.R*

**One-line description of the longitudinal observation edge**

**Parameters:**

- `edges` - Output of [cedar_data_edges()].
- `grade_dependent` - Logical. Does the analysis read grades?

**Returns:** Character string, or NULL if the required edge is unavailable.

---

## data-integrity

### `check_student_id_integrity()`

*Source: data-integrity.R*

**Check whether CEDAR tables share one student ID space**

Check whether CEDAR tables share one student ID space  Compares each table's student IDs, term by term, against a spine table whose ID space is treated as canonical.   The diagnostic signature of a broken ID space is a term with records and \emph{exactly zero} matches. A table covering a genuinely different population — applicants who never enrolled, say — lands somewhere in the middle in every term and never at zero. A hash mismatch is all-or-nothing per term, because every row in that term came from the same ingest.  So a table is reported as \code{"split"} only when it has both zero-match terms and full-match terms. That mixture cannot be explained by population differences: the same table joins perfectly in some terms and not at all in others, which means it holds two ID spaces.

**Parameters:**

- `spine` - Data frame whose ID space is canonical. Pass `cedar_students`: the class lists are the only source ingested as one continuous series, and every other student table is meant to join to them.
- `tables` - Named list of data frames to check. Names are used as labels.
- `opt` - Options list: \itemize{ \item \code{id_col}     — character; default "student_id" \item \code{term_col}   — character; default "term" \item \code{spine_name} — character; label for the spine, default "spine" }

**Returns:** Named list: \itemize{ \item \code{by_term} — tibble: table, term, n_ids, n_matched, pct_matched, term_status ("full", "partial", "none") \item \code{by_table} — tibble: table, n_terms, n_terms_full, n_terms_partial, n_terms_none, n_ids, n_ids_matched, pct_ids_matched, verdict \item \code{spine} — list(name, n_ids, n_terms) \item \code{n_tables_split} — count of tables with verdict "split" }

---

## degrees

### `count_degrees()`

*Source: degrees.R*

**Count Degrees Awarded**

Count Degrees Awarded  Counts degrees awarded by term and degree type for deduplication purposes.

**Parameters:**

- `degrees_data` - Data frame with degree award data (CEDAR naming conventions). Must include columns: term, student_id, student_college, department, program_code, major_code, award_category, degree, major, second_major, first_minor, second_minor.

**Returns:** Data frame with columns: - `term` (integer) - Term code - `major` (string) - Major name - `degree` (string) - Degree type (BA, BS, MA, MS, PhD, etc.) - `majors` (integer) - Count of degrees awarded

**Details:**

This function: 1. Selects relevant columns from degrees data 2. Removes duplicate rows (due to student attributes in source data) 3. Counts degrees by term, major_code, and degree type  The function intentionally does NOT filter by college to capture students from other colleges who have an A&S program as a second major, certificate, etc.  **Note:** Summarization uses `major_code` for grouping. Downstream filtering in `get_degrees_for_dept_report()` filters by `major_code %in% prog_codes` to restrict mappings.  **TODO:** Currently optimized for A&S degrees. Make useful for all colleges. **TODO:** Determine handling of minors, certificates, and other non-degree programs.

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

**Generate Degree Visualizations for Dept Trends**

Generate Degree Visualizations for Dept Trends  Prepares degree analysis data, plots, and tables for Dept Trends. Creates visualizations showing degrees awarded over time, broken down by major and degree type.

**Parameters:**

- `degrees_data` - Data frame with degree award data (CEDAR naming conventions). See `count_degrees()` for required columns.
- `dept_name` - Character. Department name for plot titles.
- `prog_codes` - Character vector. Program (major) codes to filter by (e.g., c("MATH", "AMAT")).
- `term_start` - Integer. Starting term code for filtering (e.g., 201980).
- `term_end` - Integer. Ending term code for filtering (e.g., 202580).
- `palette` - Character. Brewer palette name or explicit color vector. Use NULL to inherit the shared CEDAR palette.

**Returns:** List with structure: list( plots  = list(degree_summary_faceted_by_major_plot, degree_summary_filtered_program_stacked_plot), tables = list(degree_summary_filtered_program) )

**Details:**

This function: 1. Calls `count_degrees()` to get degree counts 2. Filters by term range 3. Filters by prog_codes (major_code) 4. Creates faceted line chart (one facet per major) 5. Creates stacked bar chart (aggregated across programs)  Both plots are converted to interactive plotly objects for better exploration.

**Example:**
```r
\dontrun{
degrees <- readRDS(paste0(cedar_data_dir, "cedar_degrees.Rds"))
result <- get_degrees_for_dept_report(
  degrees,
  dept_name  = "Mathematics & Statistics",
  prog_codes = c("MATH", "AMAT"),
  prog_codes = c("Mathematics", "Applied Mathematics"),
  term_start = 201980,
  term_end   = 202580,
  palette    = NULL
)
result$plots$degree_summary_faceted_by_major_plot
result$tables$degree_summary_filtered_program
}

```

---

## demographics

### `summarize_student_demographics()`

*Source: demographics.R*

**Summarize Student Demographics**

Summarize Student Demographics  Flexible demographic summary function that groups students by any specified columns (majors, classifications, or other demographic fields) and calculates enrollment counts, means across terms, and percentages of course enrollment. This provides insight into "who" is taking courses over time.  Lives in branches/ because it is consumed by multiple cones (course-demographics.R and waitlist.R).

**Parameters:**

- `filtered_students` - Data frame of student enrollments from cedar_students table, already filtered by desired criteria. Must include: student_id, term, campus, college, subject_course, and any demographic columns used in grouping.
- `opt` - Options list containing: \itemize{ \item \code{group_cols} - Character vector of column names to group by. If NULL, uses default: campus, college, term, term_type, major, student_classification, subject_course, course_title, level }

**Returns:** Data frame with student demographic breakdown including: \describe{ \item{count}{Number of distinct students in this group for THIS SPECIFIC TERM} \item{mean}{Average count across all terms OF THE SAME TERM_TYPE (e.g., avg across all falls). This is the key value used for plotting "average students per term type".} \item{registered}{Total course enrollment for this specific term} \item{registered_mean}{Average course enrollment across terms of same term_type} \item{term_pct}{Percentage of course enrollment this group represents IN THIS TERM (count / registered * 100)} \item{term_type_pct}{AVERAGE percentage across all terms of this term_type (mean / registered_mean * 100). This is what the pie charts display.} } Plus all columns specified in group_cols.  The \code{mean} and \code{term_type_pct} columns answer: "On average, what percentage of students in HIST 1105 are freshmen in fall semesters?" This averages across Fall 2022, Fall 2023, Fall 2024, etc. to give a stable "typical" value.

---

## enrl

### `add_census_enrl()`

*Source: enrl.R*

**Add a census-point enrollment column**

Add a census-point enrollment column  Reconstructed census enrollment is still registered at extract time (\code{registered} — RE/RS/RR) plus late drops (\code{dr_late} — DG/DW). Early drops (DR/DD) are excluded. This uses class-list status counts only; Regstats saturation separately combines DESR enrolled with class-list late drops. Different extract dates can prevent those measures from agreeing. Neither formula recovers a frozen census roster or actual peak occupancy.

**Parameters:**

- `df` - A course-term enrollment table carrying \code{registered} and \code{dr_late} (e.g. a \code{\link{calc_cl_enrls}} result or \code{cedar_cl_enrls_base}).

**Returns:** \code{df} with a \code{census_enrl} column added.

---

### `add_classlist_lifecycle_enrl()`

*Source: enrl.R*

**Add the three interpretable class-list lifecycle counts**

Add the three interpretable class-list lifecycle counts  Banner class-list extracts contain one final/current registration status per student-course record, not frozen rosters from three dates. Consequently the outer two columns are explicit proxies: \itemize{ \item \code{first_day_proxy}: everyone ever registered in the extract, calculated as still registered plus all early and late drops. It can include pre-term registration churn and is not a literal day-one roster. \item \code{census_enrl}: still registered plus late drops. Late drops were present at census; early drops were not. \item \code{last_day_or_current_enrl}: still registered at extract time. This is a last-day count for completed terms and a current count for an active term. }

**Parameters:**

- `df` - A course-term enrollment table carrying \code{registered}, \code{dr_late}, and \code{dr_all}.

**Returns:** \code{df} with the three lifecycle columns added.

---

### `capacity_saturation_metrics()`

*Source: enrl.R*

**Calculate reusable census-capacity saturation metrics**

**Parameters:**

- `census_enrl` - Census-point enrollment counts.
- `capacity` - Scheduled seat capacity at the same course-term grain.
- `constrained_threshold` - Fill rate at which enrollment is plausibly censored by the seat ceiling.
- `max_plausible_fill` - Fill rates above this value indicate unreliable capacity rather than a defensible ceiling.

**Returns:** A tibble with census fill, remaining census seats, and capacity quality/constraint flags.

---

### `calc_census_enrl_baselines()`

*Source: enrl.R*

**Historical census-enrollment baselines per course and term type**

Historical census-enrollment baselines per course and term type  Summarizes each course's census enrollment (see \code{\link{add_census_enrl}}) across its offerings into three things a "typical enrollment" readout needs: \itemize{ \item \code{census_hist} / \code{census_hist_terms} — the census series and its terms, ordered oldest→newest and including any target term so a sparkline can mark it in place; \item \code{census_mean} — mean comparison enrollment; \item \code{n_hist_terms} — number of comparison terms. } Grouping is same-term-type by default so falls compare to falls; part of term is added to the grouping automatically when the data carries it. Data finer than the grouping (e.g. multiple part-of-term rows when \code{part_term} is not a key) is summed per term first so the series lists one census figure per term.

**Parameters:**

- `df` - Course-term enrollment rows (e.g. \code{cedar_cl_enrls_base} or a \code{\link{calc_cl_enrls}} result). Needs \code{registered}, \code{dr_late}, \code{term}, and the grouping keys.
- `target_terms` - With \code{prior_only = TRUE}, select the terms to report (NULL reports every term). Otherwise, exclude these terms from the all-history reference mean/count; this legacy mode can include terms later than the target.
- `keys` - Grouping columns; \code{part_term} is appended when present.
- `prior_only` - When TRUE, give each term its own strictly earlier comparison mean, population SD, and count. The full series remains available for context.

**Returns:** One row per group (or group/term in prior-only mode) with \code{census_mean}, \code{n_hist_terms}, and the \code{census_hist} / \code{census_hist_terms} list-columns. Prior-only mode also returns \code{census_sd}; fewer than two prior observations gives NA SD. The legacy reference mean is rounded to one decimal; prior-only statistics retain precision.

---

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
opt <- list(dept_code = "BIOL", term = "202510")
courses_filtered <- filter_DESRs(cedar_sections, opt)
courses_compressed <- compress_aop_pairs(courses_filtered, opt)
}

```

---

### `sum_xl_dedup_total()`

*Source: enrl.R*

**Summarize Courses by Grouping Columns**

Summarize Courses by Grouping Columns  Generic summary function that aggregates course section data by specified grouping columns. Calculates section counts, enrollment statistics, and availability metrics.

**Parameters:**

- `courses` - Data frame of course sections. Must include columns used in grouping plus: enrolled, crosslist_code, available, waitlist_count
- `opt` - Options list containing: \itemize{ \item \code{group_cols} - Character vector of column names to group by. If NULL, uses default: campus, college, term, term_type, subject, subject_course, course_title, level, gen_ed_area }
- `own` - Per-row own enrollment, used for rows with no crosslist group.
- `group_total` - Per-row crosslist-combined enrollment (total_enrl).
- `xl_key` - Crosslist group key (e.g. "term|campus|code"); NA for non-crosslisted rows.

**Returns:** Data frame summarized by group_cols with columns: \describe{ \item{sections}{Total number of sections in group} \item{xl_sections}{Number of crosslisted sections (crosslist_code != "0")} \item{reg_sections}{Number of regular (non-crosslisted) sections} \item{avg_size}{Average enrollment per section (rounded to 1 decimal)} \item{total_enrl}{Crosslist-aware total: each crosslist group's combined enrollment counted once, plus own enrollment of non-crosslisted sections. For a cross-course crosslist this includes partner-course students, so it can exceed \code{enrolled}.} \item{enrolled}{Total enrollment across all sections (own students only)} \item{avail}{Total available seats across all sections} \item{waiting}{Total waitlist count across all sections} } Plus all columns specified in group_cols.

**Details:**

This function replaces many previous aggregation variants by providing a flexible grouping mechanism. Group by course_title to differentiate topics courses that share the same subject_course code.  The function uses \code{group_by_at} with dynamic column selection, making it adaptable to different analysis needs (e.g., department-level, course-level, section-level summaries).

**Example:**
```r
\dontrun{
# Summarize by course across all terms. Campus is part of the key — see the
# CEDAR-wide campus policy in AGENTS.md; a course taught in Albuquerque and at
# a branch is two offerings, not one.
opt <- list(group_cols = c("campus", "subject_course", "course_title"))
summary <- summarize_courses(cedar_sections, opt)

# Summarize by department and term (default grouping)
opt <- list(group_cols = NULL)  # Uses default
summary <- summarize_courses(cedar_sections, opt)
}

Course-level total enrollment with each crosslist group counted once

Every section row in a crosslist group carries the group's combined
enrollment in total_enrl (transform-to-cedar.R sets it to
pmax(ENROLLED, XL_TOTAL_ENROLLMENT)). Summing total_enrl over the rows of a
group therefore multiply-counts it — once per section. A same-course
internal group of 4 sections sharing a combined total of 96 sums to 384
(this is what made BIOL 2305 report ~4x its real enrollment).

Within one aggregation cell, count each crosslist group's combined total
once (max over the group's identical values) and use each non-crosslisted
row's own enrollment. Cross-course groups keep their intended semantics:
each course's cell contains its own rows of the group, so each course sees
the combined total once.

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

### `filter_enrollment_crosslist_view()`

*Source: enrl.R*

**Filter Enrollment DESR rows for a crosslist subtab**

Filter Enrollment DESR rows for a crosslist subtab  Accepts either the lowercase columns returned by aggregated get_enrl() calls or the display aliases used by section-level results.

**Parameters:**

- `data` - Enrollment DESR rows.
- `view` - One of home, split, xl-home, away, or all.

**Returns:** Rows belonging to the requested crosslist view.

---

### `get_enrl_for_dept_report()`

*Source: enrl.R*

**Get Enrollment Summary and Plots for Dept Trends**

Get Enrollment Summary and Plots for Dept Trends  Creates enrollment analysis and visualizations for Dept Trends. Aggregates enrollment data by course, generates top enrollment charts, and produces class size distribution histograms.

**Parameters:**

- `courses` - Data frame of course sections from cedar_sections table.
- `dept_code` - Character. Department code to analyze (e.g., "ENGL").
- `palette` - Character. Brewer palette name or explicit color vector. Use NULL to inherit the shared CEDAR palette.
- `term_start` - Integer. First term code to include (e.g., 201980). Fall/spring only — summers are excluded regardless.
- `term_end` - Integer. Last term code to include (e.g., 202480).

**Returns:** List with structure: list( plots  = list(highest_total_enrl_plot, highest_mean_enrl_plot, highest_mean_histo_plot), tables = list() )

**Details:**

This function performs the following steps: \enumerate{ \item Strips summer terms from the sections data \item Builds opt list with department filter, term range, and default grouping columns \item Calls \code{get_enrl()} to filter and aggregate enrollment data \item Identifies top 10 courses by total and average enrollment \item Creates bar charts for highest enrollment courses \item Creates histogram of class size distribution by level \item Converts histogram to interactive plotly widget }  Default grouping columns are: subject, subject_course, course_title, level, gen_ed_area  Note: AOP (All Online Programs) courses are compressed by default (opt$x = "compress").

**Example:**
```r
\dontrun{
result <- get_enrl_for_dept_report(cedar_sections, "ENGL", NULL, 201980, 202480)
result$plots$highest_total_enrl_plot
}

```

---

### `prepare_enrollment_level_trend_series()`

*Source: enrl.R*

**Prepare campus-aware enrollment-by-level trend series**

Prepare campus-aware enrollment-by-level trend series  Collapses enrollment to one point per term, campus, and course level. Campus is a required series key so multi-campus selections cannot be connected into or summarized as a single line.

**Parameters:**

- `level_data` - Enrollment summary with term, level, campus, and enrolled.

**Returns:** A data frame ready for the Trend Explorer level chart, or NULL.

---

### `build_enrollment_level_trend_plot()`

*Source: enrl.R*

**Build the Trend Explorer campus-by-level enrollment chart**

Build the Trend Explorer campus-by-level enrollment chart  Campus controls line color and level creates separate traces within each campus, making both dimensions visible without joining campuses together.

**Parameters:**

- `level_data` - Enrollment summary accepted by `prepare_enrollment_level_trend_series()`.

**Returns:** A Plotly object, or NULL when there is no usable data.

---

### `get_current_enrl_vs_avg()`

*Source: enrl.R*

**Compare current-term enrollment to recent same-season averages**

Compare current-term enrollment to recent same-season averages  For each course offered in `current_term`, computes the historical average enrollment across recent prior terms of the same term type and returns above- and below-average rows. Campuses are never merged: ABQ history compares only with ABQ, EA only with EA, and so on.

**Parameters:**

- `course_history` - Per-campus course enrollment history, one row per subject_course x course_title x campus x term. Must include `campus`.
- `current_term` - Integer term code.
- `n_years` - Recent years to include in the same-season baseline.
- `min_prior_terms` - Minimum prior same-season offerings required.

**Returns:** Named list with `above` and `below` data frames.

---

### `get_enrl()`

*Source: enrl.R*

**Get Enrollment Data**

Get Enrollment Data  Main entry point for enrollment analysis. Filters course sections according to specified criteria, handles missing columns gracefully, optionally compresses AOP (All Online Programs) course pairs, and can aggregate data by specified grouping columns.

**Parameters:**

- `courses` - Data frame of course sections from cedar_sections table. Must include columns: campus, college, department, term, subject_course, etc.
- `opt` - List of filtering and processing options: \itemize{ \item \code{dept_code} - Department code(s) to filter by \item \code{term} - Term code(s) to filter by \item \code{campus} - Campus code(s) to filter by \item \code{status} - Course status (default: "A" for active) \item \code{uel} - Use exclude list (default: TRUE) \item \code{aop} - AOP compression mode ("compress" to compress paired sections) \item \code{group_cols} - Vector of column names to group by for aggregation }

**Returns:** Data frame of enrollment data. If \code{opt$group_cols} is specified, returns aggregated summary with columns: sections, xl_sections, reg_sections, avg_size, enrolled, avail, waiting. Otherwise returns section-level data with columns dynamically selected based on availability.

**Details:**

The function performs the following steps: \enumerate{ \item Validates options and sets defaults (status = "A", uel = TRUE) \item Filters courses using \code{filter_DESRs()} with provided options \item Dynamically selects columns that exist in the data \item Computes derived columns if source columns exist: \itemize{ \item \code{available} = capacity - enrolled \item \code{total_enrl} = copy of enrolled (if crosslist data missing) } \item Optionally compresses AOP course pairs into single rows \item Removes duplicate rows and sorts consistently \item Optionally aggregates by \code{group_cols} using \code{summarize_courses()} }  Missing columns are handled gracefully - the function will compute derived columns when possible or create placeholders to ensure downstream code works.

**Example:**
```r
\dontrun{
# Get section-level enrollment for a department
opt <- list(dept_code = "HIST", term = "202510", status = "A")
enrl_data <- get_enrl(cedar_sections, opt)

# Get aggregated enrollment by course
opt <- list(
  dept_code = "HIST",
  group_cols = c("campus", "subject_course", "course_title", "term")
)
summary_data <- get_enrl(cedar_sections, opt)

# Compress AOP course pairs
opt <- list(dept_code = "BIOL", aop = "compress")
compressed_data <- get_enrl(cedar_sections, opt)
}

```

---

### `add_avg_section_size()`

*Source: enrl.R*

**Add the standard average section-size measure**

Add the standard average section-size measure  Department and course dashboards use the same definition: crosslist-aware total enrollment divided by the number of active home sections.

**Parameters:**

- `history` - Enrollment history returned by `get_enrl()` with `sections` and `total_enrl` columns.

**Returns:** `history` with `avg_section_size` added.

---

### `get_course_section_history()`

*Source: enrl.R*

**Build reusable section history for one course**

Build reusable section history for one course  Uses the canonical DESR enrollment path (`get_enrl()`) and keeps campuses as separate rows. This is the course-level counterpart to the section history used by the department dashboard.

**Parameters:**

- `sections` - `cedar_sections`.
- `opt` - Standard CEDAR filter options including `course`.

**Returns:** One row per campus, term, and course with total enrollment, active section count, and average section size.

---

### `get_course_section_counts()`

*Source: enrl.R*

**Get courses below enrollment threshold**

Get courses below enrollment threshold  Identifies courses with enrollment below a specified threshold, grouped by campus, department, course title, and instructional method.

**Parameters:**

- `courses` - Data frame of course sections (DESRs)
- `opt` - Options list with filtering parameters
- `threshold` - Numeric enrollment threshold (default 15)
- `sections` - Data frame of course sections (cedar_sections). Must include: status, crosslist_group, crosslist_primary, term, subject_course, course_title, campus, total_enrl.

**Returns:** Data frame with columns: \itemize{ \item \code{term} — term code \item \code{subject_course} — e.g. "HIST 1110" \item \code{course_title} — full course title (needed to distinguish topics courses) \item \code{campus} — campus code \item \code{n_sections} — count of active home sections \item \code{course_enrl} — sum of total_enrl across those sections }

**Example:**
```r
counts <- get_course_section_counts(cedar_sections)
low_enrl <- low_enrl %>%
  left_join(counts, by = c("term", "subject_course", "course_title", "campus")) %>%
  mutate(n_sections = coalesce(n_sections, 1L),
         course_enrl = coalesce(course_enrl, total_enrl))
```

---

### `build_low_enrollment_alerts()`

*Source: enrl.R*

**Build low-enrollment alert rows for shared tab/dashboard use**

Build low-enrollment alert rows for shared tab/dashboard use  Wraps `get_low_enrollment_courses()` with the level/split thresholds, course section context, severity coding, and optional prior-history labels used by the Enrollment tab. Callers can keep the tab's 25% buffer rows or request strict threshold-only output for compact dashboard cards.

**Parameters:**

- `min_enrl` - Minimum section enrollment to include. Defaults to 1 so active zero-enrollment schedule artifacts stay out of alert tables; pass 0 to inspect them explicitly.

---

### `drop_shell_sections()`

*Source: enrl.R*

**Drop shell / placeholder sections**

Drop shell / placeholder sections  Shell sections are active rows with zero enrollment and no instructor assigned — scheduling placeholders left in the schedule build, not real offerings. They must be removed before building enrollment history so a placeholder term is not counted as a real zero-enrollment offering. Cancelled sections are intentionally kept: they carry a meaningful "C" in the history string.

**Parameters:**

- `sections` - Section rows; must include \code{status}, \code{total_enrl}, \code{instructor_name}.

**Returns:** \code{sections} with shell rows removed.

---

### `summarize_term_enrl_series()`

*Source: enrl.R*

**Per-term active-enrollment series for a course (or course group)**

Per-term active-enrollment series for a course (or course group)  Collapses section rows to one row per group×term, recording whether the term had any active section (\code{has_active}) and the active-only enrollment total (\code{term_enrl} = sum of \code{total_enrl} over status "A" rows). Optionally keeps only the most recent \code{n_terms} per group, returned oldest→newest.  This is the shared history spine behind \code{\link{get_course_enrollment_history}} (a single pre-filtered course, \code{keys = character(0)}) and \code{\link{get_enrollment_concerns}} (many courses at once, keyed by \code{subject_course}, \code{course_title}, \code{campus}).

**Parameters:**

- `sections` - Section rows pre-filtered to the desired scope (campus, course, crosslist home, shell sections dropped). Must include \code{status}, \code{total_enrl}, \code{term}, and every column named in \code{keys}.
- `keys` - Grouping columns identifying a course. Empty (default) groups by term only, for a single already-filtered course.
- `n_terms` - Keep only the most recent \code{n_terms} per group; \code{NULL} keeps every term.

**Returns:** One row per group×term with \code{has_active} and \code{term_enrl}, ordered oldest→newest within each group.

---

### `format_term_history()`

*Source: enrl.R*

**Format an enrollment history series as display text**

Format an enrollment history series as display text  Renders a term-by-term series as \code{"12, C, 10 (Fa22, Sp23, Fa23)"}: the active enrollment values first for easy scanning, and "C" for terms with no active section. Shared by \code{\link{get_enrollment_concerns}} and \code{\link{format_enrollment_history}} so every history string reads the same. Call this helper instead of building \code{"term: value"} strings inline.

**Parameters:**

- `term` - Term codes (vector), ordered oldest→newest.
- `enrl` - Active enrollment per term (vector, parallel to \code{term}).
- `has_active` - Logical per term: did the term have an active section? \code{NULL} treats every term as active (no cancelled "C" markers).

**Returns:** A single string; \code{"No history"} when \code{term} is empty.

---

### `get_enrollment_concerns()`

*Source: enrl.R*

**Get enrollment concerns for a future term**

Get enrollment concerns for a future term  Analyzes a future term's scheduled courses against historical enrollment patterns from prior terms of the same type (fall/spring/summer). Returns each scheduled course with its historical average enrollment, trend, and history text for display in the concerns tab.

**Parameters:**

- `courses` - Data frame of course sections (cedar_sections)
- `opt` - Options list with filters (term, course_campus, dept, etc.)
- `n_history_terms` - Number of prior same-type terms to average (default 4)

**Returns:** Data frame with schedule + historical stats per course

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
- `crse_title` - Course title. For topics courses (Banner "T:" convention) the history is narrowed to this exact title so each rotating topic keeps its own trend; ignored for regular courses, whose titles get reworded across terms.
- `im` - Instructional method code
- `n_terms` - Number of historical terms to retrieve (default 3)

**Returns:** Data frame with TERM and enrolled columns

---

### `format_enrollment_history()`

*Source: enrl.R*

**Create enrollment history string for display**

Create enrollment history string for display  Thin adapter over \code{\link{format_term_history}} for a data frame produced by \code{\link{get_course_enrollment_history}} (columns \code{term}, \code{enrolled}, and optionally \code{has_active}).

**Parameters:**

- `history_data` - Data frame with \code{term} and \code{enrolled} columns, and optionally \code{has_active}.

**Returns:** Character string with the enrollment trend (e.g. "12, C (Fa22, Sp23)").

---

## enrollment-projections

### `get_course_enrollment_projections()`

*Source: enrollment-projections.R*

**Project Class-List Demand and Section Need for Pressured Courses**

Project Class-List Demand and Section Need for Pressured Courses  Answers one question: for an explicit target term and course scope, which course markets show enrollment pressure, what unique class-list demand does each candidate project, and which method has the best leakage-safe backtest record?

**Parameters:**

- `inputs` - Output of `prepare_enrollment_projection_inputs()`.
- `target_term` - Explicit YYYYSS target term.
- `scope_courses` - Courses eligible for pressure screening.
- `force_courses` - Courses included even when pressure thresholds do not fire.
- `opt` - Projection method and threshold options.

**Returns:** A list containing pressure screen, published projections, delivery components, all current candidates, historical backtests, recent audit history, and performance.

---

## gen-ed-grads

### `get_gen_ed_grad_cohort()`

*Source: gen-ed-grads.R*

**Build the Readable-Graduate Cohort for a Department**

Build the Readable-Graduate Cohort for a Department  Graduates of `opt$dept_code` whose whole UNM enrollment history is inside the data window — see the sampling rule at the top of this file.

**Parameters:**

- `students` - Data frame. The `cedar_students` table. Supplies the enrollment bookends that decide whether a graduate's record is complete.
- `degrees` - Data frame. The `cedar_degrees` table.
- `opt` - List of options: \describe{ \item{`dept_code`}{Character. Department code (e.g. `"HIST"`). Required.} \item{`degree_abbr`}{Character vector. Restrict to these degree types (e.g. `"BA"`). Optional.} \item{`major_code`}{Character vector. Restrict to these programs within the department (e.g. `"ASTR"` inside `"PHYS"`). Optional.} \item{`undergraduate_only`}{Logical, default `TRUE`. Gen Ed is an undergraduate requirement, so a master's or doctoral graduate has no Gen Ed obligation and contributes a structural zero to every average. Measured on History: 16 of the 17 graduate degrees in the cohort had zero Gen Ed on record, pulling the mean down by roughly a fifth for a reason that has nothing to do with what undergraduates take.} }

**Returns:** Tibble with one row per graduate and columns `student_id`, `population_label`, `grad_term`, `first_unm_term`. Shaped to be passed straight to a population-aware cone such as [get_course_timing()].  Carries a `cohort_meta` attribute: `dept_code`, `min_data_term`, `max_data_term`, `n_awarded` (all awarded graduates in scope), `n_no_records` (awarded graduates absent from `cedar_students`), `n_left_truncated` (awarded graduates whose first enrollment is the first term in the data, so their start is unreadable), `n_post_grad_entry` (graduates whose only visible enrollment postdates the degree — they finished before the window and came back later), and `n_cohort`.

---

### `get_gen_ed_grad_uptake()`

*Source: gen-ed-grads.R*

**Gen Ed Uptake Among a Graduate Cohort**

Gen Ed Uptake Among a Graduate Cohort  For a cohort from [get_gen_ed_grad_cohort()], what share took each Gen Ed course and how many Gen Ed courses a graduate takes.  A course is counted once per student no matter how many times they sat it, so `pct_cohort` reads as "this share of graduates took this course at least once" and the per-student count is distinct courses, not attempts. Retakes and withdrawals are included: the question is what graduates take, and a course that a third of graduates have to attempt twice is part of that answer. Only enrollments up to and including each student's graduation term count — post- degree coursework is not part of the degree these numbers describe.

**Parameters:**

- `students` - Data frame. The `cedar_students` table.
- `cohort` - Data frame. Output of [get_gen_ed_grad_cohort()]; needs `student_id` and `grad_term`.
- `gen_ed_lu` - Data frame. Gen Ed course lookup with `subject_course`, `area`, `area_label` — from `gen_ed_course_lookup()`.
- `opt` - List of options: \describe{ \item{`campus`}{Character vector of course-delivery campus codes. NULL includes every campus; pass NULL only for a deliberate UNM-wide aggregate.} \item{`dept_code`}{Character. When set, `by_course` gains an `is_dept_course` flag marking Gen Ed taught by the graduates' own unit.} \item{`min_n`}{Integer. Courses taken by fewer than this many cohort students are dropped from `by_course`. Default `1` (keep everything) — small-cell suppression is the caller's policy, not this cone's.} }

**Returns:** Named list: \describe{ \item{`by_course`}{One row per Gen Ed course: `subject_course`, `course_title`, `department`, `area`, `area_label`, `is_dept_course`, `n_students`, `pct_cohort`.} \item{`per_student`}{One row per cohort member who took any Gen Ed: `student_id`, `n_courses`, `n_areas`, `n_dept_courses`.} \item{`summary`}{Single-row tibble: `n_cohort`, `n_with_any`, `mean_courses`, `median_courses`, `mean_areas`. The two means divide by `n_cohort`, not `n_with_any`, so a graduate with no recorded Gen Ed counts as a zero rather than vanishing from the average.} \item{`summary_dept`}{The same shape, restricted to Gen Ed taught by the graduates' own unit, plus `dept_share_pct` — the share of all Gen Ed course-takings by this cohort that the unit taught itself. NULL when `opt$dept_code` is not set, because there is no own unit to restrict to.} }

---

## gpa-timeline

### `build_gpa_timeline()`

*Source: gpa-timeline.R*

**Build a Per-Term Cumulative GPA for Students**

Build a Per-Term Cumulative GPA for Students  One row per (student, term in which they earned graded hours) giving the credit-weighted cumulative GPA entering and after that term.

**Parameters:**

- `students` - Data frame. `cedar_students`. Needs `student_id`, `term`, `final_grade` and `credits`.
- `opt` - List of options: \describe{ \item{`student_ids`}{Character vector. Restrict to these students. Strongly recommended — the full class list is large.} \item{`min_data_term`}{Integer. First term present in the data, used to set `timeline_valid`. Defaults to the earliest term in `students`.} \item{`student_first_terms`}{Data frame of `student_id` / `first_unm_term`. **Required if you pre-filtered `students` by term** — see [credit_timeline_validity()], which this shares.} }

**Returns:** Tibble with `student_id`, `term`, `term_gpa`, `graded_hours`, `gpa_entering`, `gpa_after`, `graded_hours_entering` and `timeline_valid`. `gpa_entering` is NA in a student's first graded term — there is no prior record to average, and 0.0 would be a failing student rather than an unknown one.

---

### `attach_gpa_position()`

*Source: gpa-timeline.R*

**Attach Cumulative GPA to an Event Table**

Attach Cumulative GPA to an Event Table  Joins `gpa_entering` onto rows keyed by student and term, taking the most recent graded term at or before the event term — a student with no graded hours in the event term itself still has a record walking into it.

**Parameters:**

- `events` - Data frame with `student_id` and a term column.
- `gpa_timeline` - Output of [build_gpa_timeline()].
- `term_col` - Character. Name of the term column in `events`.

**Returns:** `events` with `gpa_entering` and `timeline_valid` added. Both are NA / FALSE where no usable prior record exists.

---

## headcount

### `normalize_headcount_opt()`

*Source: headcount.R*

**Normalize Headcount Filter Options**

**Parameters:**

- `programs` - CEDAR program records used to validate college values.
- `opt` - Filter options; empty selections become NULL.
- `lookups` - Optional college-code-to-name lookup.

**Returns:** Normalized filter options.

---

### `filter_programs_by_opt()`

*Source: headcount.R*

**Filter Programs Data by Options**

Filter Programs Data by Options  Helper function that applies institutional and program filters to CEDAR programs data.

**Parameters:**

- `programs` - Data frame of student program enrollment data (CEDAR format)
- `opt` - Options list with possible filters: \itemize{ \item campus - Values from student_campus to include \item college - Values from student_college, or codes resolved through lookups \item dept_code - Vector of department codes to include \item major - Vector of major program names to include \item minor - Vector of minor program names to include \item concentration - Vector of concentration names to include }
- `lookups` - Optional college-code and program-to-department lookups.

**Returns:** List with: \describe{ \item{data}{Filtered data frame} \item{has_program_filter}{Boolean indicating if program-specific filters were applied} }

**Details:**

**Filtering strategy**  Campus and college are row-level filters. Because these attributes are the same across all program rows for a student in a given term, row-level filtering is equivalent to student-level filtering and safe to apply directly.  Dept is a row-level filter: program rows must match by dept_code or the program-to-department lookup. Cross-dept combinations (e.g. History major + Anthropology minor) are handled by using the major/minor/concentration filters directly instead of the dept filter.  Major, minor, and concentration each independently find matching student-term pairs, then intersect them. A student must satisfy every active program filter in the same term (AND across filters; OR among selections within one filter). Records with a missing student ID or term cannot establish membership and are excluded when a program filter is active. Only rows for the primary filter are returned (major > minor > concentration), so the plot does not add secondary program types as separate series.

---

### `summarize_headcount()`

*Source: headcount.R*

**Summarize Headcount Data**

Summarize Headcount Data  Helper function that groups and counts students from filtered programs data.

**Parameters:**

- `df` - Filtered programs data frame (from filter_programs_by_opt)
- `has_program_filter` - Boolean indicating if program filters were applied
- `group_by` - Character vector of column names to group by. When NULL: - No program filter: groups by c("term", "student_level", "program_type") - Program filter active: groups by c("term", "student_level", "program_type", "program_name") Pass explicitly for custom aggregations (e.g. SFR: c("term", "dept_code", "student_level")).
- `lookups` - Optional list with \code{program_name_lookup} (program_name → dept_code) and \code{dept_name_lookup} (dept_code → dept_name), used only to roll a broad program selection up to department totals (see Details).

**Returns:** Data frame with columns from group_by plus student_count (distinct student IDs)

**Details:**

**Department/unit rollup**  When no explicit \code{group_by} is given and a program filter selects more than \code{UNIT_ROLLUP_THRESHOLD} distinct programs (e.g. every major in a college), faceting one panel per program doesn't scale. In that case the data is regrouped by the program's owning department (via \code{program_name_lookup}) instead of by individual program, and \code{attr(result, "rolled_up_by_dept")} is set to TRUE so \code{\link{make_headcount_plots_by_level}} can facet/label by department.

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

### `format_headcount_export()`

*Source: headcount.R*

**Format Headcount Results for CSV Export**

**Parameters:**

- `result` - Result list returned by \code{get_headcount()}.

**Returns:** Data frame suitable for a user-facing CSV download.

---

### `get_headcount()`

*Source: headcount.R*

**Get Student Headcount**

Get Student Headcount  Main orchestrating function for calculating student headcount from CEDAR programs data.

**Parameters:**

- `programs` - Student program enrollment data in CEDAR format. Required columns: student_id, term, student_level, program_type, program_name, dept_code. Optional columns: student_college, student_campus, degree.
- `opt` - Options list for filtering: \itemize{ \item campus - Filter by values from student_campus \item college - Filter by student_college values or mapped college codes \item dept_code - Filter program rows by department code(s) or the program-to-department lookup; omit for cross-department combinations \item major - Filter by major program name(s) \item minor - Filter by minor program name(s) \item concentration - Filter by concentration name(s) } Multiple program filters (major + minor, etc.) are combined with AND logic: only students satisfying all specified filters in the same term are counted. Multiple choices within one filter use OR. The plot reflects the primary filter (major > minor > concentration).
- `group_by` - Optional character vector of columns to group by. Defaults to c("term", "student_level", "program_type", "program_name") when a program filter is active, or c("term", "student_level", "program_type") otherwise. Pass explicitly for custom aggregations (e.g. SFR: c("term", "dept_code", "student_level")).

**Returns:** List with: \describe{ \item{data}{Data frame with student_count and grouping columns} \item{no_program_filter}{TRUE when no major/minor/concentration filter was applied} \item{metadata}{List with total_students, programs_included, filters_applied} }

**Details:**

Delegates to \code{\link{filter_programs_by_opt}}, \code{\link{summarize_headcount}}, and \code{\link{format_headcount_result}}. See \code{\link{filter_programs_by_opt}} for details on the student-term filtering strategy.

**Example:**
```r
\dontrun{
# All programs in a department
result <- get_headcount(cedar_programs, list(dept_code = "HIST"))

# History majors who also have an Anthropology minor
result <- get_headcount(cedar_programs, list(major = "History", minor = "Anthropology"))

# SFR aggregation
result <- get_headcount(
  cedar_programs,
  opt      = list(),
  group_by = c("term", "dept_code", "student_level")
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

### `make_headcount_sparklines()`

*Source: headcount.R*

**Headcount Sparkline for Department Dashboard**

Headcount Sparkline for Department Dashboard  Creates a compact static ggplot showing term-by-term headcount for a department's major and minor programs. Faceted by student level (Undergraduate / Graduate), with separate lines for Majors and Minors. Summer terms are already excluded by \code{get_headcount_series()}. Intended for embedding in the "Explore Your Unit" dashboard summary.

**Parameters:**

- `series` - Data frame returned by \code{get_headcount_series()} in dept-dashboard.R. Columns: term, group, student_level_clean, program_cat, count.

**Returns:** A ggplot object, or NULL if series is NULL/empty.

---

### `get_headcount_data_for_dept_report()`

*Source: headcount.R*

**Count Students by Program (Legacy Function)**

Count Students by Program (Legacy Function)  Legacy headcount function for backward compatibility with older code. Uses mapped DEPT and PRGM codes for filtering.

**Parameters:**

- `academic_studies_data` - Academic studies data with original column names
- `opt` - Options list for filtering (passed to get_headcount). Can include filters for campus, college, etc. If empty, dept_code is used.
- `programs` - Student program enrollment data in CEDAR format. Required columns: student_id, term, student_level, program_type, program_name. This is typically the academic_studies dataset with CEDAR naming.
- `dept_code` - Character. Department code for filtering (e.g., "HIST", "MATH").
- `term_start` - Integer. Starting term code for filtering (e.g., 201980).
- `term_end` - Integer. Ending term code for filtering (e.g., 202580).

**Returns:** List with structure: list( plots  = list(hc_progs_under_long_majors_plot, hc_progs_under_long_minors_plot, hc_progs_grad_long_majors_plot,   hc_progs_grad_long_minors_plot), tables = list(hc_progs_under, hc_progs_under_long_majors, hc_progs_under_long_minors, hc_progs_grad,  hc_progs_grad_long_majors,  hc_progs_grad_long_minors) )

**Details:**

**CEDAR Data Model Only**  This function requires CEDAR-formatted data and will error if legacy column names are provided. There are no fallbacks - CEDAR naming is mandatory.  Workflow: 1. Validates CEDAR column structure (errors with clear message if missing) 2. Calls get_headcount() to get aggregated headcount data 3. Filters by term range 4. Splits into undergraduate/graduate and major/minor subsets 5. Creates plotly plots for each subset 6. Returns plots and tables as a plain list  **Column Mappings (Legacy → CEDAR):** - term_code → term - Student Level → student_level - major_type → program_type - major_name → program_name

---

## major-changes

### `detect_major_changes()`

*Source: major-changes.R*

**Detect major changes for each student across their academic timeline**

Detect major changes for each student across their academic timeline  Compares each student's primary major term-over-term. A change is recorded when program_name differs from the prior term. Each row in the output represents one change event.

**Parameters:**

- `programs` - cedar_programs data frame.
- `cohort` - Optional tibble(student_id, cohort_label). If provided, only students in the cohort are analyzed.
- `term_credits` - Optional. `cedar_student_term_credits`. Supplies the credit position at each change via [build_credit_timeline()]. When NULL the credit columns are returned as NA rather than being read off the frozen cumulative columns on `programs` — see the note below.
- `opt` - Options list: \itemize{ \item \code{campus}  — character; filter by student_campus \item \code{college} — character; filter by student_college \item \code{dept_code} — character; filter by dept_code \item \code{observation_end_term} — integer; exclude program records after the settled longitudinal enrollment edge }

**Returns:** Tibble with one row per major change event: student_id, change_term, prev_term, from_major, to_major, unm_credits_before_change, total_credits_before_change (credits entering the term before the change posted, UNM-only and UNM + transfer), credits_position_valid, student_college, student_campus, dept_code, student_level, degree   This function used to read `inst_credits_attempted` / `overall_credits_attempted` at the change term and lag them by one term, on the stated reasoning that "because these columns are running totals, lag() subtracts exactly that student's lagged-term load". They are not running totals. Academic Studies stamps the student's total as of the pull onto every historical row, so within one full re-pull the value moves across a student's own terms only 16% of the time. `lag()` on a frozen column subtracts zero, and the reported "credits before the change" was approximately the student's FINAL credit total — overstating the position at a student's first term by a median of 84 credits. See the field reliability contract in AGENTS.md.

---

### `avg_credits_before_major()`

*Source: major-changes.R*

**Average credits at time of arriving in each major (via change)**

**Parameters:**

- `changes` - Tibble from detect_major_changes()
- `opt` - Options list; uses opt$min_n (default 5)

**Returns:** Tibble: to_major, avg_unm_credits, median_unm_credits, avg_total_credits, median_total_credits, n_changes, n_students. Credits are lag-adjusted attempted hours (see detect_major_changes()).

---

### `majors_moved_out_of()`

*Source: major-changes.R*

**Most common majors students leave**

**Parameters:**

- `changes` - Tibble from detect_major_changes()
- `opt` - Options list; uses opt$min_n (default 5)

**Returns:** Tibble: from_major, n_exits, ranked by frequency

---

### `major_change_pathways()`

*Source: major-changes.R*

**Most common A → B major change pathways**

**Parameters:**

- `changes` - Tibble from detect_major_changes()
- `opt` - Options list; uses opt$min_n (default 3)

**Returns:** Tibble: from_major, to_major, n_changes, avg_unm_credits, avg_total_credits. Credits are lag-adjusted attempted hours at the move.

---

### `pathways_by_college()`

*Source: major-changes.R*

**Major change pathways broken out by college**

**Parameters:**

- `changes` - Tibble from detect_major_changes()
- `opt` - Options list; uses opt$min_n (default 3)

**Returns:** Tibble: student_college, from_major, to_major, n_changes, avg_unm_credits, avg_total_credits (lag-adjusted attempted hours)

---

### `time_to_first_change()`

*Source: major-changes.R*

**Terms from first enrollment to first major change**

Terms from first enrollment to first major change  Uses term_diff() for accurate term counting (summers excluded by default).

**Parameters:**

- `programs` - cedar_programs data frame
- `cohort` - Optional tibble(student_id, cohort_label)
- `opt` - Options list (passed through to detect_major_changes)

**Returns:** Tibble: student_id, first_term, first_change_term, terms_until_change, from_major, to_major

---

### `tag_major_changers()`

*Source: major-changes.R*

**Tag students by whether they ever changed major**

**Parameters:**

- `programs` - cedar_programs data frame
- `cohort` - Optional tibble(student_id, cohort_label)
- `opt` - Options list (passed through to detect_major_changes)

**Returns:** Tibble: student_id, changed_major, n_changes, n_majors_held, majors_held (comma-separated sequence)

---

### `get_major_change_courses()`

*Source: major-changes.R*

**Courses students were enrolled in during the term they changed majors**

Courses students were enrolled in during the term they changed majors  Joins major change events to cedar_students by student_id + change_term. Useful for identifying courses correlated with leaving or arriving in a major.  To analyze departures from a major, filter changes to from_major == X before calling. To analyze arrivals, filter to to_major == X.

**Parameters:**

- `changes` - Tibble from detect_major_changes(). Pre-filter to the from_major or to_major of interest before passing in.
- `students` - cedar_students data frame
- `opt` - Options list: \itemize{ \item \code{min_n} — integer; minimum students per course (default 5) }

**Returns:** Tibble: subject_course, course_title, n_students, pct_of_changers, sorted by n_students descending

---

### `get_pre_change_courses()`

*Source: major-changes.R*

**Courses students were taking in the term before a major switch appeared**

Courses students were taking in the term before a major switch appeared  Answers "is there anything in common in what students were taking right before they switched?" — and, just as importantly, gives the reader a way to see when the answer is no.  The anchor term is `prev_term`, not `change_term`. A switch posts to Banner the term AFTER the student actually moves, so `prev_term` is the last term on the old major: the term whose coursework was in progress while the decision was being made. `get_major_change_courses()` uses `change_term` instead and therefore describes the term after the move.  Every course is reported against a baseline: its ordinary rate in this population. Note the two denominators differ, and they are not both per student. `pct_before_switch` is per *switch* — of the change events whose prior term has visible coursework, how many included this course. `pct_other_terms` is per *student-term* — of every (student, term) pair in the whole population, switchers and stayers alike, minus the switch-adjacent pairs, how many included this course. A student enrolled eight terms contributes eight to that denominator.  Without the baseline the table is just a ranking of large required courses, and any list of common courses looks like a finding. `ratio` near 1 means the course is no more common before a switch than at any other time.  This is association only. The comparison does not adjust for when in a career the terms fall, and switches cluster early, so lower-division courses carry an upward bias in `ratio` that has nothing to do with switching.

**Parameters:**

- `changes` - Tibble from detect_major_changes(). Pre-filter to the direction of interest (e.g. departures from a unit) before passing in.
- `students` - cedar_students data frame.
- `population` - Population tibble (needs `student_id`). Supplies the comparison universe for the baseline column: every student here, whether or not they switched, contributes their terms to `pct_other_terms`. Pass the full analysis population, not the changers — restricting it to switchers turns the baseline into a within-person comparison, which is a different (and much smaller) question.
- `opt` - Options list: \itemize{ \item \code{min_n} — integer; minimum switches per course (default 5) }

**Returns:** Named list: \itemize{ \item \code{courses} — tibble: subject_course, course_title, n_switches, pct_before_switch, pct_other_terms, ratio, n_other_terms_with_course. The two shares are adjacent on purpose; comparing them is the analysis \item \code{n_switches} — change events with a usable prior term \item \code{n_switches_with_courses} — of those, how many have class-list enrollment in that term. This is the denominator of \code{pct_before_switch} \item \code{n_students} — distinct students behind those events \item \code{n_baseline_terms} — student-terms in the comparison baseline }

---

### `get_declaration_context()`

*Source: major-changes.R*

**Snapshot of credits and prior course history at the moment students first**

Snapshot of credits and prior course history at the moment students first declared the focal program

**Parameters:**

- `programs` - cedar_programs filtered to population students
- `students` - cedar_students (full, will be filtered internally)
- `population` - Population tibble from build_population() — needs first_unm_term for terms-to-declaration calculation
- `focal_subjects` - Character vector of subject codes that belong to the focal unit (e.g. c("HIST") for a History population). Used to split prior courses into in-unit vs outside.
- `opt` - Options list; uses opt$min_n (default 5)

**Returns:** Named list: credits (summary tibble), courses_focal, courses_other, n_declarers, focal_subjects

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

## pathway

### `plot_curriculum_map()`

*Source: pathway.R*

**Plot Curriculum Map Heatmap**

Plot Curriculum Map Heatmap  Visualizes course timing data as a heatmap: relative term on the x-axis, course on the y-axis (sorted by median term taken), and cell fill showing what percentage of eligible cohort students took that course in that term.

**Parameters:**

- `timing_data` - Data frame. Output of `get_course_timing()`.
- `opt` - List of options: \describe{ \item{`title`}{Character. Plot title. Default: `"Curriculum Map"`.} \item{`pct_label_threshold`}{Numeric (0-1). Only show percentage labels inside cells above this value. Default: `0.05` (5%).} \item{`fill_color`}{Character. High-end fill color. Defaults to the CEDAR green (`CEDAR_COLORS["green"]`). Can be any ggplot2-compatible color.} \item{`facet_by_subject`}{Logical. If `TRUE`, facet rows by subject code (e.g., all BIOL courses grouped, then CHEM, etc.). Default: `FALSE`.} \item{`top_n`}{Integer. Maximum number of courses to display. Courses are ranked by their peak `pct_pop` across all terms; only the top `top_n` are shown. Default: `40`.} \item{`min_pct`}{Numeric (0–1). Courses where no term exceeds this percentage are dropped before applying `top_n`. Default: `0.05`.} }

**Returns:** A ggplot2 object. Use `ggsave()` to save or display in RStudio viewer.

**Example:**
```r
\dontrun{
timing <- get_course_timing(cedar_students, cohort, opt = list())
plot_curriculum_map(timing)

# Save to file
p <- plot_curriculum_map(timing, opt = list(title = "Radiologic Sciences Pathway"))
ggsave("output/radiology-pathway.png", p, width = 12, height = 8)

# Subject-only view
plot_curriculum_map(timing %>% filter(subject_code %in% c("BIOL","CHEM","PHYS")))
}

```

---

### `get_course_pairs()`

*Source: pathway.R*

**Get Ordered Course Pairs for a Student Population**

Get Ordered Course Pairs for a Student Population  Identifies the most common ordered course sequences — cases where a student took course A in one term and course B in a later term. This captures the implicit prerequisite chains that students actually follow, as opposed to the formally catalogued ones.  Only courses taken by at least `opt$min_n` population students are included. Only pairs where the A→B pattern occurred at least `opt$min_pair_n` times are returned.

**Parameters:**

- `students` - Data frame. The `cedar_students` table.
- `cohort` - Data frame. Output of `build_population()`. Defines the student population to analyze — a program-based filter, not an entry-term cohort.
- `opt` - List of options: \describe{ \item{`min_n`}{Integer. Minimum population students who took course A for it to be included as a pair source. Default: `15`.} \item{`min_pair_n`}{Integer. Minimum population students exhibiting the A→B pattern for the pair to appear in results. Default: `10`.} \item{`max_term_gap`}{Integer. Maximum number of relative terms between A and B. Default: `4` (pairs more than 4 terms apart are unlikely to be meaningfully sequential).} \item{`campus`}{Character vector of course-delivery campus codes. Scopes which enrollment rows are counted. This is the campus that taught the section, not the student's home campus — the two differ on roughly 28% of enrollment rows, so a population scoped by home campus still pulls in branch-delivered course rows without it. NULL includes every campus; pass NULL only for a deliberate UNM-wide aggregate.} \item{`subject_code`}{Character vector. Restrict to courses in these subjects. Optional.} \item{`censor_term`}{Integer term code of the last complete data term. When supplied, A-side enrollments (and the `pct_a_to_b` denominator) are restricted to terms with `max_term_gap` complete regular terms of follow-up, so recently-taken courses don't show deflated follow-on rates purely because the data ends (right-censoring). Optional; NULL preserves uncensored behavior.} }

**Returns:** Data frame sorted by `n_students` descending, with columns: \describe{ \item{`course_a`}{First course in the pair.} \item{`course_b`}{Second course (taken after A).} \item{`n_students`}{Population students who took A and then took B.} \item{`n_took_a`}{Total population students who took course A (denominator).} \item{`pct_a_to_b`}{`n_students / n_took_a`: of students who took A, what fraction went on to take B?} \item{`median_term_gap`}{Median number of relative terms between taking A and taking B.} }

**Example:**
```r
\dontrun{
population <- build_population(cedar_programs,
                           opt = list(type = "health",
                                      health_programs = "Radiologic Sciences"))
pairs <- get_course_pairs(cedar_students, population, opt = list())
# Top transitions out of BIOL 2310
pairs %>% filter(course_a == "BIOL 2310")
}

```

---

### `get_event_adjacent_courses()`

*Source: pathway.R*

**Get Courses Adjacent to Student Entry or Exit Events**

Get Courses Adjacent to Student Entry or Exit Events  Finds courses taken in the term(s) immediately before a population-level change event and compares their frequency across two groups. For entry events: converters (pre-majors who eventually declared) vs. non-converters (pre-majors who left without declaring). For exit events: students who left vs. students who stayed.  Lift > 1 means the course appears disproportionately in the primary group (converters for entry, leavers for exit) relative to the comparison group. This is a correlation, not evidence of causation.

**Parameters:**

- `students` - Data frame. The `cedar_students` table.
- `population` - Data frame. Output of `build_population()`. Must have columns `student_id`, `outcome`, `first_unit_term`, `last_unit_term`. `entry_status` is not required — groups are assigned by outcome alone, so all entry paths (pre_major, switched_in, undecided) are included.
- `event` - Character. `"entry"` (default) or `"exit"`.
- `window` - Integer. Number of non-summer terms to look back from the event term. Default: `1L` (the single term immediately preceding).
- `include_event_term` - Logical. Whether to include the event term itself. Default: `FALSE`. Setting `TRUE` mixes gateway courses with first-term required courses.
- `min_n` - Integer. Minimum students per group for a course to appear. Default: `5L`.
- `campus` - Character vector of course-delivery campus codes. Scopes which enrollment rows are counted and is part of the output grouping. NULL includes every campus — pass NULL only for a deliberate UNM-wide aggregate. Note this is the campus that taught the section, not the student's home campus; the two differ on roughly 28% of enrollment rows.

**Returns:** Wide data frame with one row per course and columns for each group's student count (`n_students_*`), group size (`n_group_*`), rate (`pct_*`), and `lift`. Attributes include `ep_meta` (list with n per group, n excluded for no prior term). Returns an empty data frame if no qualifying students are found.

---

### `assign_relative_terms()`

*Source: pathway.R*

**Assign Relative Term Numbers to Enrollment Records**

Assign Relative Term Numbers to Enrollment Records  For each student, ranks their enrolled terms chronologically (1 = first term, 2 = second, etc.) and adds a `relative_term` column.  UNM term codes are YYYYSS format (e.g., 202510 = Spring 2025, 202560 = Summer, 202580 = Fall). Numeric sort order is chronological order, so no external lookup is needed.  Summer terms (SS = "60") can be excluded from the counter — they don't advance the relative term number but summer courses are still assigned to the relative term of the preceding non-summer term.

**Parameters:**

- `enrolled` - Data frame with columns: `student_id`, `term`.
- `include_summer` - Logical. Whether summer counts as its own relative term. Default: `FALSE`.

**Returns:** `enrolled` with a `relative_term` integer column added.

---

## pathways

### `pathways_level_filter()`

*Source: pathways.R*

**Translate Pathways course-level UI choice to CEDAR level values**

**Parameters:**

- `level_choice` - Character scalar from a Pathways level selector.

**Returns:** Character vector for opt$level, or NULL for all levels.

---

### `pathways_observation_boundary()`

*Source: pathways.R*

**Latest term whose outcomes are fully observable**

Latest term whose outcomes are fully observable  Right-censoring guard shared by the Pathways analyses: an outcome measured by "what happened in later terms" (returned next term, later took course B, later entered the major) is only observable for records with enough complete regular terms after them. Records after this boundary would all look like non-returns / non-entries simply because the data ends.

**Parameters:**

- `latest_complete_term` - Integer term code of the last complete data term (typically `subtract_term(cedar_current_term)`).
- `follow_up_terms` - Integer. How many complete regular (fall/spring) terms of follow-up the analysis needs. 1 for next-term outcomes (stop-out), the A-to-B gap for course pairs, etc.

**Returns:** Integer term code: the latest term with full follow-up. NULL if latest_complete_term is NULL/NA.

---

### `apply_pathways_population_window()`

*Source: pathways.R*

**Apply Pathways analysis term and population membership window**

**Parameters:**

- `data` - Data frame with student_id and term columns.
- `population` - Population data frame from build_population().
- `analysis_through` - Optional maximum term to include.
- `term_col` - Name of the term column in data.

**Returns:** data filtered to analysis_through and relevant_until.

---

### `filter_pathways_analysis_population()`

*Source: pathways.R*

**Apply Pathways analysis population subgroup filters**

**Parameters:**

- `population` - Population data frame from build_population().
- `split_by` - Population split mode; "entry" excludes unclear entry rows.
- `selected_label` - Optional population_label selected in the status bar.

**Returns:** Filtered population.

---

### `resolve_pathways_focal_programs()`

*Source: pathways.R*

**Resolve focal program names for a Pathways population option**

**Parameters:**

- `population_opt` - Option list used to build the population.
- `programs` - cedar_programs.
- `pop_programs` - Optional cedar_programs already filtered to population IDs.

**Returns:** Character vector of program names.

---

### `resolve_pathways_focal_dept_codes()`

*Source: pathways.R*

**Resolve focal department codes for a Pathways population option**

**Parameters:**

- `population_opt` - Option list used to build the population.
- `programs` - cedar_programs.
- `pop_programs` - Optional cedar_programs already filtered to population IDs.

**Returns:** Character vector of dept_code values.

---

### `resolve_pathways_focal_subjects()`

*Source: pathways.R*

**Resolve focal course subject prefixes for Pathways analyses**

**Parameters:**

- `population_opt` - Option list used to build the population.
- `programs` - cedar_programs.
- `lookups` - cedar_lookups list; must include subject_lookup.
- `pop_programs` - Optional cedar_programs already filtered to population IDs.

**Returns:** Character vector of subject_code values.

---

### `resolve_pathways_gen_ed_courses()`

*Source: pathways.R*

**Resolve department gen ed courses from focal subject prefixes**

**Parameters:**

- `focal_subjects` - Character vector of subject prefixes.
- `gen_ed_courses` - Character vector of gen ed subject_course codes.

**Returns:** Character vector of gen ed subject_course values.

---

### `pathways_coverage_facts()`

*Source: pathways.R*

**Summarise what the data window can and cannot see about a population**

Summarise what the data window can and cannot see about a population  Pathways answers questions about student trajectories, and a trajectory is only readable if its start and end are both inside the data. For a typical department population neither holds for a large minority: measured on the shared data, 41-44% of students were already enrolled in the first term CEDAR has, and 27-39% are still enrolled in the last one.  Those two facts bound every timing claim on the tab, and neither is visible from the outcome counts — a left-truncated student looks like a first-semester freshman, and a right-censored one looks like a continuing student. This returns the counts so the page can state them rather than leaving the reader to assume full coverage.

**Parameters:**

- `population` - Data frame from `build_population()`. Uses `first_unm_term` and `last_record_term` when present.
- `min_data_term,max_data_term` - Integer term codes bounding the data.

**Returns:** Named list: `n`, `n_truncated`, `pct_truncated`, `n_censored`, `pct_censored`, `n_complete` (students whose whole record is inside the window), `pct_complete`, plus the two boundary terms. Counts are NA when the population lacks the bookend columns, so callers can omit the note rather than print a confident zero.

---

### `latest_graded_term()`

*Source: pathways.R*

**Latest term whose grades are actually posted**

Latest term whose grades are actually posted  Thin wrapper over [cedar_data_edges()]'s `last_graded`. The shared helper is the canonical one — see the right-edge policy in AGENTS.md — and this exists so Pathways callers read in their own vocabulary.

**Returns:** Integer term code, or NULL when no term clears the threshold.

---

## population-trend

### `make_population_trend()`

*Source: population-trend.R*

**Plot student population mix over time for a department's majors**

**Parameters:**

- `programs` - cedar_programs data frame (must include student_population).
- `dept_code` - Department code (e.g., "HIST", "GES").
- `program_type` - Which program type to include. Default "Major" (primary majors only). Pass NULL to include all types (majors + minors + concentrations).
- `student_level` - Filter to "Undergraduate" (default) or NULL for all levels.

**Returns:** A ggplot proportional stacked bar chart.

---

## population

### `get_ongoing_ids()`

*Source: population.R*

**Get Ongoing Student IDs**

Get Ongoing Student IDs  Returns all students currently engaged with a focal program in the most recent data term. Includes two groups: - Declared focal students whose last program record is max_data_term - Pre-major-only students whose focal pre-major record is max_data_term (these students haven't had a chance to declare yet)

**Parameters:**

- `programs` - Data frame. cedar_programs.
- `focal_names` - Character vector. Focal program names.
- `max_data_term` - Integer. The most recent term in the data.

**Returns:** Character vector of student IDs.

---

### `get_graduated_ids()`

*Source: population.R*

**Get Graduated Student IDs**

Get Graduated Student IDs  Returns students who received a focal-program degree within the graduation window: [last_declared_term, last_declared_term + 100]. The +100 window covers the typical 1–2 term lag between a student's last program record and when their degree is formally conferred.  Only counts graduation_status values that represent a real outcome: "Awarded", "Pending", "Sought". Excludes "Hold Pending" (admin block) and "Record Clear" (application withdrawn).

**Parameters:**

- `programs` - Data frame. cedar_programs.
- `degrees` - Data frame or NULL. cedar_degrees. Returns empty vector if NULL.
- `focal_names` - Character vector. Focal program names.
- `focal_codes` - Character vector. Focal program codes (optional). When supplied and the degrees table has a major_code column, restricts matches to degrees in those codes.

**Returns:** Character vector of student IDs.

---

### `get_switched_out_ids()`

*Source: population.R*

**Get Switched-Out Student IDs (detection only)**

Get Switched-Out Student IDs (detection only)  Returns students who have a declared non-focal program record at any term strictly after their last declared focal term. This is a detection function — priority over other outcomes (ongoing, graduated) is applied by the orchestrator, not here.

**Parameters:**

- `programs` - Data frame. cedar_programs.
- `focal_names` - Character vector. Focal program names.

**Returns:** Character vector of student IDs.

---

### `get_never_declared_ids()`

*Source: population.R*

**Get Never-Declared Student IDs**

Get Never-Declared Student IDs  Returns students who appeared only as a pre-major in the focal program — never declared — and whose last focal pre-major record predates max_data_term. Students with a pre-major record IN max_data_term are classified as ongoing (current pre-majors), not never_declared.

**Parameters:**

- `programs` - Data frame. cedar_programs.
- `focal_names` - Character vector. Focal program names.
- `max_data_term` - Integer. The most recent term in the data.

**Returns:** Character vector of student IDs.

---

### `get_entry_pathways()`

*Source: population.R*

**Get Entry Pathways for Declared Focal Students**

Get Entry Pathways for Declared Focal Students  Returns a data frame of student_id + entry_pathway for every student who ever declared the focal program. Pre-major-only students are excluded.  Pathway rules (applied in priority order): pre_major   — had a focal pre-major record strictly before first declaration switched_in — had a non-focal declared major strictly before first declaration direct      — everything else (first UNM major was the focal program)  Note: never_declared is NOT an entry_pathway returned by this function — it is assigned by build_population() to historical pre-major-only students.

**Parameters:**

- `programs` - Data frame. cedar_programs.
- `focal_names` - Character vector. Focal program names.

**Returns:** Data frame with columns student_id (chr) and entry_pathway (chr).

---

### `classify_origin()`

*Source: population.R*

**Classify Student UNM Origin**

Classify Student UNM Origin  Returns "transfer", "unm", or "unknown" for each student based on the student_population field in cedar_programs. Uses the student's earliest term across ALL programs — not just focal — so a student who enrolled at UNM as a transfer before declaring the focal program is correctly classified.

**Parameters:**

- `programs` - Data frame. cedar_programs (all programs, not just focal).
- `candidate_ids` - Character vector. Student IDs to classify.

**Returns:** Data frame with columns student_id (chr) and origin (chr).

---

### `classify_entry_method()`

*Source: population.R*

**Classify How a Student First Arrived at the Focal Unit**

Classify How a Student First Arrived at the Focal Unit  Returns one of three values for each student: first_program — no prior program record of any kind (declared or pre-major, in any unit) before their first focal record. This is their first academic program affiliation. switched_in   — had at least one prior program record somewhere before arriving at the focal unit. unclear       — their first focal record coincides with the earliest term in the full programs table, so prior history is unobservable.  The unclear flag applies only to students who appear "direct" — if a student already has positive evidence of a prior program (switched_in) or a focal pre-major record, that evidence stands regardless of the data boundary.

**Parameters:**

- `programs` - Data frame. cedar_programs (all programs, not just focal).
- `focal_names` - Character vector. Focal program names.
- `min_data_term` - Integer. Earliest term in the full programs table.

**Returns:** Data frame with columns student_id (chr) and entry_method (chr).

---

### `classify_entry_status()`

*Source: population.R*

**Classify Whether a Student First Engaged as a Pre-Major or Declared Major**

Classify Whether a Student First Engaged as a Pre-Major or Declared Major  Returns "pre_major" if the student's first focal program record was a pre-major record, "major" if it was a declared major. Purely about their first record — does not consider later declarations.

**Parameters:**

- `programs` - Data frame. cedar_programs (all programs, not just focal).
- `focal_names` - Character vector. Focal program names.

**Returns:** Data frame with columns student_id (chr) and entry_status (chr).

---

### `build_population()`

*Source: population.R*

**Build a Student Population**

Build a Student Population  Constructs a population data frame from cedar_programs using the outcome-oriented pipeline. Returns one row per student with: student_id, population_label, outcome, origin (unm/transfer/unknown), entry_method (first_program/switched_in/unclear), entry_status (pre_major/major), first_unm_term, first_unit_term, last_unit_term, last_declared_term, last_record_term, relevant_until

**Parameters:**

- `programs` - Data frame. cedar_programs.
- `degrees` - Data frame or NULL. cedar_degrees.
- `students` - Data frame or NULL. cedar_students. Supplies UNM-wide enrollment bookends and enrollment-based continuation evidence.
- `opt` - List of options: type          — "preset", "dept", or "major". Default "preset". program_names — required for preset/major types. dept_code     — required for dept type. outcomes      — character vector of outcomes to include. Default: all six outcomes (graduated, switched_out, stopped_out, ongoing, chose_elsewhere, left_undeclared). split_by      — "none" (default), "outcome", "entry", "entry_status", or "transfer". When "entry", population_label is set to entry_method per student. When "entry_status", population_label is set to whether the student first appeared as a declared major or pre-major. When "transfer", population_label is set to origin per student. campus        — character vector. Filter by student_campus. Optional. student_level — character vector. Filter by student_level before outcome detection. Common values: "Undergraduate", "Graduate". When omitted, all levels are included and undergrad/grad students are mixed in a single population. Pass "Undergraduate" to build a clean undergrad cohort for a department that also has grad programs.

**Returns:** Data frame with one row per student.

---

### `get_focal_programs()`

*Source: population.R*

**Get Focal Program Names for a Population Build**

Get Focal Program Names for a Population Build  Resolves focal program names from opt depending on type. Returns a data frame of distinct program_name + major_code values that are in scope.

**Parameters:**

- `programs` - Data frame. cedar_programs.
- `opt` - List of options (type, program_names, dept_code).

**Returns:** Data frame with columns program_name and major_code.

---

### `build_demographic_population()`

*Source: population.R*

**Build a Demographic Population**

Build a Demographic Population  Identifies students based on demographic indicators stored in cedar_programs. Membership is resolved as "ever" — a student qualifies if they had the indicator in ANY term, not just the most recent.

**Parameters:**

- `programs` - Data frame. cedar_programs.
- `opt` - Options list: pell_eligible, first_gen, time_status, ipeds_race, gender, campus, student_level, term.
- `students` - Data frame or NULL. cedar_students, used for UNM-wide first/last enrollment bookends.

**Returns:** Population tibble with one row per student. Program-specific outcome and entry fields are NA; UNM-wide bookends are populated when possible.

---

## seatfinder

### `get_courses_common()`

*Source: seatfinder.R*

**Get Courses Common to Both Terms**

Get Courses Common to Both Terms  Finds courses offered in both comparison terms and calculates year-over-year enrollment changes. This helps identify enrollment trends and capacity needs.

**Parameters:**

- `term_courses` - Named list with two data frames: \itemize{ \item \code{start} - Courses from starting term \item \code{end} - Courses from ending term }
- `enrl_summary` - Data frame of enrollment summary data with columns: campus, college, term, part_term, subject_course, course_title, gen_ed_area, enrolled

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

Seatfinder workflow: \enumerate{ \item Parse term parameter (single term vs comparison range) \item Get enrollment summary with configurable grouping (via get_enrl) \item Merge DFW rates from shared course outcome data \item Identify courses common to both terms (via get_courses_common) \item Identify new and discontinued courses (via get_courses_diff) \item Pivot to calculate availability changes (avail_diff) \item Filter and sort gen ed courses by availability }  Use cases for seatfinder: \itemize{ \item **Semester Planning**: Which courses need additional sections? \item **Capacity Analysis**: How does seat availability compare to last year? \item **Gen Ed Management**: Which gen ed courses have open seats? \item **Enrollment Forecasting**: What are enrollment trends by course type? \item **New Course Planning**: Which courses are new this term? }  **Important**: Always uses the exclude list (opt$uel = TRUE) and active courses only (opt$status = "A"). Aggregates section enrollments by course type.

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

**Get SFR Data for Legacy Department-Level Analysis**

Get SFR Data for Legacy Department-Level Analysis  Generates student-faculty ratio plots and data for department-specific reports. Creates separate visualizations for undergraduate and graduate students, plus a scatter plot showing the department in context of the full college.

**Parameters:**

- `data_objects` - Named list containing cedar_programs and cedar_faculty data.
- `dept_code` - Character. Department code (e.g., "HIST", "MATH").

**Returns:** List with structure: list( plots  = list(ug_sfr_plot, grad_sfr_plot, sfr_scatterplot), tables = list() ) If insufficient data, plot values will be character strings instead of ggplot objects.

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
result <- get_sfr_data_for_dept_report(data_objects, "HIST")
print(result$plots$ug_sfr_plot)
print(result$plots$grad_sfr_plot)
print(result$plots$sfr_scatterplot)
}

```

---

## stopout

### `get_stopout()`

*Source: stopout.R*

**Roadblocks: First-Outcome Stop-Out Comparisons**

Roadblocks: First-Outcome Stop-Out Comparisons  For each course and delivery campus, compare next-regular-term stop-out after DFW versus pass, separately for a selected population and other students. Each student contributes their first eligible observed outcome to exactly one group. Scope, population-window filtering, and both right edges precede this selection. This is not necessarily the student's first lifetime attempt.  Agreeing first-term outcomes collapse to one observation; conflicting first-term outcomes exclude that student/course/campus comparison. Later repeats remain evidence of return but do not change the selected outcome. Counts, rates, DFW context, and tests all use these same observations.  Return means registered or late-drop enrollment anywhere at UNM in the next fall or spring. A degree in the outcome term also prevents a stop-out flag. Nonreturn is an observed absence, not proof of permanent departure.  The chi-squared test (Yates correction) compares DFW versus pass WITHIN each population; it does not test whether the population and baseline gaps differ. Tests require at least five students in each outcome group and both return states. Small expected cells can still make the approximation unreliable. P-values are unadjusted across courses; neither a gap nor the ranking score establishes that a course caused a student to leave.

**Parameters:**

- `students` - Full `cedar_students` enrollment history. If course outcomes are term-windowed, supply the full-history `cedar_next_term` separately: otherwise filtering away return terms silently creates false stop-outs.
- `population` - Output of [build_population()], with `student_id` and `population_label`. Callers apply population membership windows to outcome rows before this function; the return lookup must remain unwindowed.
- `degrees` - Optional degree records; a degree in the outcome term counts as completion rather than stop-out.
- `opt` - List of options: `term`, `campus`, `level`, and `subject_code` restrict course outcomes; `min_n` (default 15) is the minimum selected population students per course/campus; `min_dfw_n` (default 5) is the minimum selected DFW students; `graded_through` caps outcomes; `observation_end_term` requires the next regular term to be observable. Reporting thresholds do not guarantee statistical validity. Standalone callers must supply appropriate edges.
- `cedar_grades` - Optional preclassified outcomes with the current saved outcome-policy version, already respecting the caller's population window.
- `cedar_next_term` - Optional full-history next-term return lookup.

**Returns:** List containing `by_course` (one row per campus/course), `population_size`, eligible anchor `term_range`, and `observation_info` (coverage counts before size thresholds). Course rows contain `pop_` and `baseline_` columns: `n_dfw`, `n_pass`, `n_graded`, `dfw_rate`, `dfw_stopout_rate`, `pass_stopout_rate`, `stopout_gap`, and `p_value`. Statistics retain full precision; round only for display.

---

### `prepare_roadblock_results()`

*Source: stopout.R*

**Prepare Roadblock Ranking Metrics**

Prepare Roadblock Ranking Metrics  Uses the first-observation context already in the input and computes the population's excess stop-out gap over the same-course baseline. A missing baseline stays missing: treating it as zero would turn "not estimable" into an apparently adverse comparison.

**Parameters:**

- `stopout_by_course` - Course rows returned in `get_stopout()$by_course`.

**Returns:** Input rows with `excess_gap` and `impact_score`, ordered by descending estimable impact. Impact is a descriptive ranking score, not a causal estimate.

---

### `get_dfw_rates()`

*Source: stopout.R*

**Get DFW Rates by Course for a Population**

Get DFW Rates by Course for a Population  For each course taken by population students, computes the DFW rate among population students and the baseline (all other students in the same courses). A student with ANY eligible DFW counts in the numerator, even if they also passed. This standalone ever-DFW measure is not the Roadblocks first-outcome context. Sorted by population DFW rate descending.  Shares `classify_outcomes()` with `get_stopout()`. Does not require a next-term lookup. Callers must cap input at the grade edge; it does not require the complete follow-up window used by Roadblocks.

**Parameters:**

- `students` - Data frame. The `cedar_students` table.
- `population` - Data frame. Output of `build_population()`. Must have `student_id`.
- `opt` - List of options: \describe{ \item{`level`}{Character vector. Course levels to include. Optional.} \item{`campus`}{Character vector. Campus codes to include. Optional.} \item{`min_n`}{Integer. Min population students graded in a course. Default: `10`.} \item{`min_dfw_n`}{Integer. Min population DFW students. Default: `5`.} }

**Returns:** Data frame with one row per campus and course, columns: `campus`, `subject_course`, `pop_n_graded`, `pop_n_dfw`, `pop_dfw_rate`, `baseline_n_graded`, `baseline_n_dfw`, `baseline_dfw_rate`.

---

### `select_stopout_observations()`

*Source: stopout.R*

**Select First Eligible Roadblocks Observations**

Select First Eligible Roadblocks Observations  Input must already respect the course scope, population window, grade edge, and complete follow-up edge. Keep one outcome per student/course/campus at the first eligible term. Agreeing records in that term collapse to one; conflicting pass/DFW records exclude the entire comparison, without advancing to a later term. Later enrollment remains in the separate full-history return lookup. Coverage counts refer to scoped outcome records before size thresholds.

**Parameters:**

- `graded` - Classified, eligible outcome records.

**Returns:** List with `data` (selected observations), `term_range` (eligible anchors before selection), and `info` (coverage counts and a display-ready note). Counts include population and other students across the scoped input; they are student-course-campus observations, not unique people across courses.

---

### `classify_outcomes()`

*Source: stopout.R*

**Classify Student Enrollment Records as Pass or DFW**

Classify Student Enrollment Records as Pass or DFW  Takes enrollment records and labels each as `"pass"` or `"dfw"` using the canonical CEDAR classification (`classify_enrollment_outcomes()` in trunk/utils.R — see the "CEDAR-wide DFW policy" note in AGENTS.md). A+ through C and CR pass. Every other recorded non-audit grade, including incomplete and no-credit outcomes, is DFW/nonpassing. AUD is excluded regardless of registration status. Blank/NA grades are excluded unless the record is a late drop.  Late drops (`STATUS_DROP_LATE`) are DFW. Early drops (`STATUS_DROP_EARLY`) are excluded entirely: a drop before the deadline posts no grade and is not an academic outcome.

**Parameters:**

- `students` - Data frame. The `cedar_students` table.

**Returns:** Data frame with columns: `student_id`, `term`, `campus`, `subject_course`, `outcome` (`"pass"` or `"dfw"`).

---

### `build_next_term_lookup()`

*Source: stopout.R*

**Build a Next-Term Enrollment Lookup**

Build a Next-Term Enrollment Lookup  For each student-term pair present in the data, determines the next regular academic term and whether the student enrolled in it. Uses `add_next_term_col()` from `utils.R`.  Summer terms are excluded from the "next term" mapping — a student who doesn't enroll in summer is not considered a stop-out.

**Parameters:**

- `students` - Data frame. The full `cedar_students` table (not pre-filtered by term — we need the full enrollment history to check the next term).

**Returns:** Data frame with columns: `student_id`, `term`, `returned_next_term` (logical: `TRUE` if the student had any enrollment the following term).

---

### `compute_stopout_for_group()`

*Source: stopout.R*

**Compute Stop-Out Rates for One Group in One Course**

Compute Stop-Out Rates for One Group in One Course  Given one selected observation per student in a single population and course/campus, computes DFW context and stop-out rates on that same set, plus a within-group chi-squared test. Repeated or incomplete observations are rejected rather than silently reweighting the denominators.

**Parameters:**

- `course_group` - Data frame. First eligible observations selected by `get_stopout()` for one group in one course/campus. Must have columns: `student_id`, `term`, `outcome`, and `stopped_out` (pre-joined by caller).
- `prefix` - Character. Column name prefix for the returned values (`"cohort"` or `"baseline"`).

**Returns:** Single-row tibble with columns: `{prefix}_n_dfw`, `{prefix}_n_pass`, `{prefix}_n_graded`, `{prefix}_dfw_rate`, `{prefix}_dfw_stopout_rate`, `{prefix}_pass_stopout_rate`, `{prefix}_stopout_gap`, `{prefix}_p_value`

---

## transform-to-cedar

### `generate_program_map()`

*Source: transform-to-cedar.R*

**Build program_map from academic_studies**

Build program_map from academic_studies  Parses Banner program codes from raw academic_studies data and resolves each to college_code, dept_code, degree_level, program_type, and canonical_code. Called by transform_to_cedar() when program_map.qs is absent.

**Parameters:**

- `as_file` - Path to academic_studies file (qs or Rds)
- `ext` - File extension: ".qs" or ".Rds"
- `subj_dept_map` - Data frame from subj_dept_map.R
- `premaj_canon` - Named character vector from program_code_maps.R
- `xvar_explicit` - Named character vector from program_code_maps.R
- `extra_p2d` - Named character vector from program_code_maps.R
- `known_suffixes` - Character vector of valid college suffixes
- `real_F_progs` - Character vector of F-prefix codes that are not pre-majors
- `get_lev` - Function that maps degree description → degree level string

**Returns:** A tibble with columns: program_code, college_code, dept_code, major_code, degree_abbr, degree_level, program_type, canonical_code

---

### `transform_applicants()`

*Source: transform-to-cedar.R*

**Transforms admissions applicant data to the CEDAR model.**

Transforms admissions applicant data to the CEDAR model. Encrypts student ID, derives term, renames columns to snake_case, and keeps only the admissions covariates consumed by comparison analyses.

**Parameters:**

- `applicants` - Raw admissions_applicants data frame (output of parse-data.R)
- `data_dir` - Path to data directory
- `ext` - File extension

**Returns:** list(saved = list(applicants = <meta>))

---

### `transform_to_cedar()`

*Source: transform-to-cedar.R*

**Transform MyReports data to CEDAR model**

Transform MyReports data to CEDAR model  Loads parsed source files, calls each transform function, and saves cedar_* files. Runs daily after parse-data.R. Overwrites existing cedar_* files.

**Parameters:**

- `data_dir` - Path to data directory (default: from config)
- `use_qs` - Use .qs format (default: from config)
- `tables` - Character vector of tables to run (default: all) Options: "sections", "students", "programs", "degrees", "faculty", "applicants", "lookups"

**Returns:** Invisibly: named list of save metadata for each table written

---

## waitlist

### `get_unique_waitlisted()`

*Source: waitlist.R*

**Get Unique Waitlisted Students Not Registered**

Get Unique Waitlisted Students Not Registered  Identifies students who are waitlisted for a course but not registered, providing counts by campus and course. This helps identify "true" waitlist demand by excluding students who are registered for another section.

**Parameters:**

- `filtered_students` - Data frame of student enrollments from cedar_students table, already filtered by opt parameters. Must include columns: campus, term, subject_course, course_title, student_id, registration_status
- `opt` - Options list (currently unused but kept for consistency)
- `sections` - Optional cedar_sections table; only needed if filtered_students lacks a course_title column (titles are joined by term/subject_course)

**Returns:** Data frame with columns: \itemize{ \item \code{campus} - Campus code \item \code{college} - College code (only when the input carries a college column) \item \code{term} - Term code \item \code{part_term} - Part of term (only when the input carries a part_term column) \item \code{subject_course} - Course identifier \item \code{count} - Number of unique students waitlisted only (not registered) } Sorted by campus, subject_course, and descending count.

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

### `ensure_course_title()`

*Source: waitlist.R*

**Ensure course_title column is present for waitlist summaries**

Ensure course_title column is present for waitlist summaries  cedar_students normally carries course_title; if the input lacks it, titles are joined from the sections table, which must then be supplied explicitly.

**Parameters:**

- `df` - Student enrollment rows.
- `sections` - cedar_sections table; only required when df has no course_title.

---

### `get_true_waitlisted_rows()`

*Source: waitlist.R*

**Select true waitlist-demand rows**

Select true waitlist-demand rows  Keeps waitlisted students who do not also hold a registered row for the same campus, term, part of term (when present), and course. Registration codes are preferred; the display status is supported for backward-compatible callers.

**Parameters:**

- `df` - Student enrollment rows containing waitlist and registered statuses.
- `sections` - Optional sections table used when course titles are absent.

---

### `summarize_waitlist_courses()`

*Source: waitlist.R*

**Summarize true waitlist demand by course**

Summarize true waitlist demand by course  Counts distinct students for each course overview row while carrying optional college and part-of-term dimensions when the input provides them.

**Parameters:**

- `waitlisted_students` - True waitlist-demand rows.

**Returns:** One row per course grouping with a distinct-student `count`.

---

### `summarize_waitlist_groups()`

*Source: waitlist.R*

**Summarize true waitlist demand by demographic groups**

Summarize true waitlist demand by demographic groups  Focused count-only alternative to the full demographic enrollment summary.

**Parameters:**

- `waitlisted_students` - True waitlist-demand rows.
- `group_cols` - Columns defining the requested demographic breakdown.

**Returns:** One row per group with a distinct-student `count`.

---

### `scope_waitlist_enrollment_base()`

*Source: waitlist.R*

**Scope the enrollment base to waitlist course keys**

Scope the enrollment base to waitlist course keys  Keeps every historical term for the course keys present in a waitlist result, while dropping unrelated courses before census-history aggregation begins.

**Parameters:**

- `enrl_base` - Precomputed course-term enrollment rows.
- `count_df` - Waitlist course-overview rows.

**Returns:** A list containing scoped `data` and the shared `match_keys`.

---

### `attach_enrollment_history()`

*Source: waitlist.R*

**Attach per-course census-enrollment context to the waitlist course overview**

Attach per-course census-enrollment context to the waitlist course overview  Enriches the waitlist count table with each course's current-term census enrollment, its historical average census enrollment (same term type, viewed term excluded), the count of reference terms behind that average, and the same-term-type census series used to draw a sparkline in the UI. This reference can include later terms when reviewing an older target; Regstats instead uses a strictly prior baseline. The count uses registered plus late drops (see \code{\link{add_census_enrl}}), not a frozen census or the mixed-source reconstruction used by Regstats saturation.  Enrollment history comes from the precomputed \code{cedar_cl_enrls_base} table (built in global.R) when it is in scope; outside the running app (tests, standalone scripts) it is recomputed via \code{\link{calc_cl_enrls}}, scoped to just the courses in the overview so the fallback stays cheap.

**Parameters:**

- `count_df` - Waitlist course-overview table (one row per campus/college/ term/part_term/subject_course) from \code{\link{get_unique_waitlisted}}.
- `students` - Student enrollment rows, used to recompute enrollment history when no precomputed base table is available.

**Returns:** \code{count_df} with added columns \code{census_enrl} (current-term census enrollment), \code{census_enrl_mean} (historical average, viewed term excluded), \code{n_hist_terms} (reference terms behind the average), and the \code{trend_hist} / \code{trend_terms} list-columns the module renders as a sparkline. Returned unchanged when no enrollment source is available.

---

### `inspect_waitlist()`

*Source: waitlist.R*

**Inspect Waitlist by Major and Classification**

Inspect Waitlist by Major and Classification  Comprehensive waitlist analysis that breaks down waitlisted students by their major and classification. This provides insight into which student populations are being waitlisted and helps with enrollment planning and advising.

**Parameters:**

- `students` - Data frame of student enrollments from cedar_students table. Must include columns: campus, college, term, term_type, major, student_classification, subject_course, course_title, level, and registration_status_code (or the backward-compatible registration_status).
- `opt` - Options list for filtering: \itemize{ \item \code{course} - Course identifier(s) (e.g., "MATH 1430") \item \code{term} - Term code(s) (e.g., 202510) \item \code{subject} - Subject code(s) (e.g., "MATH") \item Other filtering options supported by \code{filter_class_list()} }
- `sections` - Optional cedar_sections table; only needed if students lacks a course_title column (titles are joined by term/subject_course)

**Returns:** Named list with three elements: \itemize{ \item \code{majors} - Data frame summarizing waitlist by major/program. Columns: campus, term, subject_course, course_title, major, count \item \code{classifications} - Data frame summarizing waitlist by student level. Columns: campus, term, subject_course, course_title, student_classification, count \item \code{count} - Data frame of unique waitlisted students (see \code{\link{get_unique_waitlisted}}), enriched (when \code{sections} is supplied) with \code{n_sections} (active sections offered), \code{avg_size} (mean enrolled per section), and \code{sections_needed} (additional sections to clear the waitlist at the average size). }

**Details:**

This function performs the following steps: \enumerate{ \item Filters students using \code{filter_class_list()} with provided options \item Restricts to waitlisted students only (registration_status = "Wait Listed") \item Groups data by campus, college, term, course, and demographics \item Counts distinct true-waitlist students twice: \itemize{ \item Once grouped by major (major) \item Once grouped by classification (student_classification) } \item Computes unique course-level waitlist counts \item Returns cleaned summaries with unnecessary columns removed }  The returned data is useful for: \itemize{ \item Understanding which majors have highest waitlist demand \item Identifying whether freshmen vs upperclassmen are being waitlisted \item Planning section additions or seat reservations \item Advising students about course availability }

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
