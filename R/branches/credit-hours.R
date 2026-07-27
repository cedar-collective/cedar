# =============================================================================
# CREDIT HOURS ANALYSIS
# =============================================================================
#
# This file answers one central question for each department report:
# "How many student credit hours (SCH) does this department produce, and who
# is doing the work of taking those courses?"
#
# A student credit hour = one student × one credit in one course. A 3-credit
# course with 30 students = 90 SCH. This is the primary workload metric for
# academic departments.
#
# WHAT WE TRACK
# -------------
# 1. Total SCH production — broken down by term, subject code, and course level
#    (lower division = 100-299, upper division = 300-499, graduate = 500+)
#
# 2. Who is taking the courses — broken down by student major, so a department
#    can see whether it mostly serves its own students or draws from across campus
#
# 3. Growth trends — how this department's SCH is changing relative to its college
#
# TERMINOLOGY
# -----------
# In cedar_students, each row is one student enrolled in one course section:
#   department      — the COURSE's home department (e.g., "HIST" for HIST 101)
#   major           — the STUDENT's declared major code (e.g., "PSYC")
#   student_college — the college the student is enrolled in (e.g., "AS")
#   level           — whether the course is "lower", "upper", or "grad"
#
# KEY DISTINCTION
# ---------------
# A student in HIST 101 has department="HIST" (where the course lives).
# That same student might have major="PSYC" (they're a Psychology student).
# These are two different things. The "outside major" charts ask:
# "Who is taking courses here — are they our students or someone else's?"
#
# TERM CODE FORMAT
# ----------------
# UNM uses 6-digit term codes: YYYYTT where TT = 10 (spring), 60 (summer),
# 80 (fall). So 202380 = Fall 2023, 202410 = Spring 2024.
#
# FILE STRUCTURE
# --------------
# 1. Data builders  — pure functions; return data frames; no plotting code;
#                     each can be called and tested independently
# 2. Plot builders  — pure functions; take a data frame in, return a plot out;
#                     no data transformation happens inside
# 3. Orchestrators  — coordinate the pipeline: call data builders, then plot
#                     builders, then package everything into $plots + $tables
# =============================================================================


# =============================================================================
# 1. DATA BUILDERS
# =============================================================================

#' Summarize credit hours by term, campus, college, department, subject, and level
#'
#' This is the foundational summary used by all department-level SCH plots.
#' It counts only credit hours earned through passing grades — we don't count
#' withdrawals, failures, or incompletes because those don't represent
#' completed academic work from the department's perspective.
#'
#' The result includes both individual level rows (lower/upper/grad) AND a
#' "total" row per group that sums across all levels — so downstream callers
#' can choose either view without re-aggregating.
#'
#' @param students cedar_students data frame
#' @return Long-format data frame with columns: term, campus, college,
#'   department, subject_code, level, total_hours.
#'   Level values: "lower", "upper", "grad", "total".
get_credit_hours <- function(students) {
  message("[credit-hours.R] get_credit_hours")

  # Fail loudly if the data doesn't have the columns we need — better to stop
  # here with a clear message than to produce silent wrong results downstream.
  required_cols <- c("final_grade", "term", "campus", "college",
                     "department", "level", "subject_code", "credits")
  missing_cols <- setdiff(required_cols, colnames(students))
  if (length(missing_cols) > 0) {
    stop("[credit-hours.R] Missing required columns: ",
         paste(missing_cols, collapse = ", "))
  }

  # Keep only students who earned a passing grade. The passing_grades vector
  # is defined in R/lists/grades.R and loaded globally by the app.
  passing <- students %>% filter(final_grade %in% passing_grades)

  # Count total credits earned, grouped by every dimension we care about.
  # This gives us one row per unique (term, campus, college, dept, level, subject).
  by_level <- passing %>%
    group_by(term, campus, college, department, level, subject_code) %>%
    summarize(total_hours = sum(credits), .groups = "keep")

  # Also compute a "total" row that adds lower + upper + grad together.
  # We add this as a separate row (level = "total") rather than filtering
  # it out, so callers can choose either the breakdown or the aggregate.
  totals <- passing %>%
    group_by(term, campus, college, department, subject_code) %>%
    summarize(level = "total", total_hours = sum(credits), .groups = "keep")

  # Stack the by-level rows and the total rows, then sort so levels appear
  # in a consistent order: lower → upper → grad → total.
  rbind(by_level, totals) %>%
    arrange(term, campus, college, department, subject_code,
            factor(level, levels = c("lower", "upper", "grad", "total")))
}


#' Filter and normalize student data for credit-hours-by-major analysis
#'
#' Before we analyze who is taking courses in a department, we need to narrow
#' the data to the right time window and remove students who didn't pass.
#'
#' Also fixes a Banner data inconsistency: the College of Education appears
#' under two different strings depending on the export vintage. We normalize
#' to one display name so grouping works correctly.
#'
#' @param students cedar_students data frame
#' @param term_start Integer term code for the beginning of the analysis window
#' @param term_end   Integer term code for the end of the analysis window
#' @return Filtered data frame, ready for major-level analysis
build_major_level_data <- function(students, term_start, term_end) {
  students %>%
    filter(
      as.integer(term) >= term_start,   # drop terms before the window
      as.integer(term) <= term_end,     # drop terms after the window
      final_grade %in% passing_grades   # drop non-passing enrollments
    ) %>%
    # Banner has used two different names for the same college in different
    # export generations. Normalize so charts don't show it as two separate groups.
    mutate(student_college = str_replace(
      student_college, "College of Educ & Human Sci", "College of Education"
    ))
}


#' Summarize SCH by major and split into home vs. outside
#'
#' For a given set of course enrollment rows (already filtered to a level like
#' "lower" or "upper"), this function totals the credit hours per major and
#' then divides them into two groups:
#'   - "Home" majors: students whose declared major belongs to this department
#'   - "Outside" majors: students from other departments who are taking these courses
#'
#' This is the foundation of the pie charts that show a department's service
#' function to the rest of the university.
#'
#' @param level_data Filtered student enrollment rows for one course level
#'   Required cols: major, major_name, credits
#' @param major_codes Character vector of major codes that belong to this
#'   department (e.g., c("BIOL", "FBIO", "CHBI") for Biology)
#' @return Named list with slots:
#'   major_summary — all majors with total hours
#'   home          — only the department's own majors
#'   outside       — all other majors
#'   home_hours, outside_hours, total_hours — scalar totals
build_major_summary <- function(level_data, major_codes) {
  # Normalize display name BEFORE grouping so one major code always maps to
  # one label. Without this, a code with some rows having major_name="Biology"
  # and others having major_name="" would produce two separate groups/slices.
  summary <- level_data %>%
    mutate(major_name = if_else(!is.na(major_name) & major_name != "", major_name, major_code)) %>%
    group_by(major_code, major_name) %>%
    summarize(total_hours = sum(credits, na.rm = TRUE), .groups = "drop") %>%
    arrange(desc(total_hours))  # biggest programs first

  # Split into home (our students) vs. outside (everyone else)
  home    <- summary %>% filter(major_code %in% major_codes)
  outside <- summary %>% filter(!(major_code %in% major_codes))

  list(
    major_summary   = summary,
    home            = home,
    outside         = outside,
    home_hours      = sum(home$total_hours,    na.rm = TRUE),
    outside_hours   = sum(outside$total_hours, na.rm = TRUE),
    total_hours     = sum(summary$total_hours, na.rm = TRUE)
  )
}


#' Group outside majors by display name and decide which get their own slice
#'
#' The raw outside-major data can have dozens of programs. If we gave every
#' small program its own slice, the pie chart would become unreadable. But a
#' hard "top N" cutoff can hide important groups — for example, Nursing students
#' might be the #10 largest group but still represent a meaningful story.
#'
#' Instead we use a percentage threshold: any program that accounts for at least
#' 3% of total outside SCH gets a named slice. The rest roll into "Other".
#' We cap the named groups at 12 to keep the legend legible.
#'
#' Each Banner program code gets its own slice. Display names are carried in
#' major_name for use in tables only — plots label by major_code so that
#' code variants (NURS, FNRS, FNAP) are visible separately rather than being
#' silently merged or split by name drift.
#'
#' The color map built here is shared with the time-series bar chart, so each
#' program code gets the same color in both views.
#'
#' @param outside_summary The "outside" slot from build_major_summary() —
#'   a data frame with major_code, major_name, and total_hours columns
#' @param pct_threshold Fraction of outside SCH required for a named slice
#'   (default 0.03 = 3%)
#' @param max_named Hard cap on the number of named slices (default 12)
#' @return Named list:
#'   outside_for_pie — complete ranking of all outside programs by code + name;
#'                     used as the full export table
#'   named_outside   — only programs that clear the threshold (capped at max_named)
#'   top_outside     — named_outside plus an "Other" row for everything else
#'   color_map       — named character vector mapping each major_code to a color
#'   outside_total   — scalar: total outside SCH
build_outside_pie_data <- function(outside_summary, pct_threshold = 0.03, max_named = 12L,
                                    recent_summary = NULL) {

  # Step 1: One row per major_code. major_name is carried for table display only.
  # build_major_summary already produces one row per code, so this is just a sort.
  outside_for_pie <- outside_summary %>%
    arrange(desc(total_hours))

  outside_total <- sum(outside_for_pie$total_hours, na.rm = TRUE)

  # Step 2: Return empty (but correctly shaped) results if there are no outside
  # majors at all. This prevents downstream code from failing on empty data.
  if (outside_total == 0 || nrow(outside_for_pie) == 0) {
    return(list(
      outside_for_pie = tibble(major_code = character(0), major_name = character(0), total_hours = numeric(0)),
      named_outside   = tibble(major_code = character(0), major_name = character(0), total_hours = numeric(0)),
      top_outside     = tibble(major_code = character(0), major_name = character(0), total_hours = numeric(0)),
      color_map       = build_color_map(character(0)),
      outside_total   = 0
    ))
  }

  # Step 3: Keep programs that clear the threshold, up to the cap.
  # A program is named if it clears the threshold in all-time SCH OR in the
  # recent-term SCH window. This prevents recently-grown programs (e.g., a new
  # pre-major code that only appears in the last 2 terms) from being swamped
  # by their earlier-term zeros and stuck in "Other" despite now being large.
  named_by_alltime <- outside_for_pie %>%
    filter(total_hours / outside_total >= pct_threshold) %>%
    pull(major_code)

  named_by_recent <- if (!is.null(recent_summary) && nrow(recent_summary) > 0) {
    recent_total <- sum(recent_summary$total_hours, na.rm = TRUE)
    if (recent_total > 0)
      recent_summary %>%
        filter(total_hours / recent_total >= pct_threshold) %>%
        pull(major_code)
    else character(0)
  } else character(0)

  named_outside <- outside_for_pie %>%
    filter(major_code %in% union(named_by_alltime, named_by_recent)) %>%
    slice_head(n = max_named)

  # Step 4: Compute how much is left over and add a single "Other" row.
  # If every named group accounts for 100% of outside SCH, no "Other" needed.
  other_hours <- outside_total - sum(named_outside$total_hours, na.rm = TRUE)
  top_outside <- if (other_hours > 0) {
    bind_rows(named_outside, tibble(major_code = "Other", major_name = "Other", total_hours = other_hours))
  } else {
    named_outside
  }

  # Step 5: Build the color map keyed on major_code (stable across name changes).
  color_map <- build_color_map(top_outside$major_code)

  list(
    outside_for_pie = outside_for_pie,
    named_outside   = named_outside,
    top_outside     = top_outside,
    color_map       = color_map,
    outside_total   = outside_total
  )
}


#' Build the term-by-term data for the outside-major bar chart
#'
#' The pie charts show averages across the whole analysis window. The time-
#' series bar chart shows the same grouping (same named programs, same "Other"
#' bucket) but laid out term by term so you can see trends over time.
#'
#' The named programs here must match exactly what build_outside_pie_data()
#' selected, so the two charts tell a consistent story: a program named in the
#' pie also appears as its own bar in the time series.
#'
#' @param level_data Filtered student enrollment rows for one course level
#'   Required cols: major, major_name, credits, term
#' @param major_codes Home department major codes — excluded from outside count
#' @param named_outside_codes The major_code values from build_outside_pie_data()
#'   $named_outside — these are the program codes that get their own bar color
#' @return Data frame: term (as a factor), major_group (chr), total_hours (dbl)
build_outside_time_data <- function(level_data, major_codes, named_outside_codes) {
  level_data %>%
    # Drop home-department students — we only want the outside majors here
    filter(!(major_code %in% major_codes)) %>%
    mutate(
      # Any code not in the named list becomes "Other" — keyed on major_code
      # so name drift never changes a program's group assignment
      major_group = if_else(major_code %in% named_outside_codes, major_code, "Other")
    ) %>%
    # Sum credits by term and group, giving one row per term × major_group
    group_by(term, major_group) %>%
    summarize(total_hours = sum(credits, na.rm = TRUE), .groups = "drop") %>%
    # Convert term to a factor so the x-axis labels appear in chronological order
    mutate(term = as.factor(term))
}


#' Build the wide-format SCH summary table (major × term)
#'
#' This is the export table that appears in the report alongside the charts.
#' It shows each major as a row and each term as a column, so a reader can
#' scan across a row to see how a program's SCH has changed over time.
#'
#' A "Total" row at the bottom sums every column, and missing values (a major
#' that didn't appear in a particular term) are shown as 0. Rows are sorted
#' by the most recent term so the most active programs appear first.
#'
#' @param filtered_students Filtered student rows (all levels combined)
#' @return Wide data frame: student_college, major, then one column per term
build_credit_hours_wide_table <- function(filtered_students) {
  # Start with a long-format summary: one row per (term, college, major_name).
  # Normalize the display name first so blank major_name falls back to the code.
  long <- filtered_students %>%
    mutate(major_name = if_else(!is.na(major_name) & major_name != "", major_name, major_code)) %>%
    group_by(term, student_college, major_code, major_name) %>%
    summarize(total_hours = sum(credits), .groups = "drop") %>%
    arrange(term, desc(total_hours))

  # Pivot so each term becomes its own column
  wide <- long %>%
    pivot_wider(names_from = term, values_from = total_hours)

  # If there are no term columns (only the ID columns), return as-is
  if (ncol(wide) <= 3) return(wide)

  term_cols <- names(wide)[4:ncol(wide)]

  # Build a totals row by summing each term column
  totals_row <- wide %>%
    ungroup() %>%
    summarise(
      student_college = "Total",
      major_code      = "Total",
      major_name      = "Total",
      across(all_of(term_cols), ~ sum(.x, na.rm = TRUE))
    )

  wide %>%
    ungroup() %>%
    bind_rows(totals_row) %>%
    # Replace NA (program didn't appear that term) with 0 for readability
    mutate(across(all_of(term_cols), ~ replace_na(as.numeric(.x), 0))) %>%
    # Sort by the most recent term so active programs float to the top
    arrange(desc(.data[[last(term_cols)]]))
}


#' Compute SCH growth and decline trends for outside majors
#'
#' This function asks: "Which outside programs are sending more or fewer
#' students to this department compared to the recent past?"
#'
#' We measure trends over three windows: 1-year, 2-year, and 4-year. Each
#' window compares the average SCH over the most recent N terms against the
#' same-length window immediately before that.
#'
#' Summer terms are excluded from all windows because summer enrollment
#' behaves very differently from the regular academic year — including summer
#' would distort the averages and make year-over-year comparisons misleading.
#'
#' We rank by absolute change (e.g., +200 SCH) rather than percentage change
#' (e.g., +20%) to avoid a tiny program with explosive percentage growth
#' appearing more important than a large program with modest but consequential
#' absolute growth.
#'
#' Window requirements (needs enough history in the data):
#'   1yr: needs ≥ 4 fall/spring terms in the range
#'   2yr: needs ≥ 6 fall/spring terms
#'   4yr: needs ≥ 10 fall/spring terms
#'
#' @param level_data Filtered student enrollment rows for one course level
#' @param major_codes Home department codes — only outside majors are analyzed
#' @param top_n How many top growing and declining programs to return (default 5)
#' @return list(growing, declining) — each a data frame with top_n rows,
#'   or NULL if there isn't enough history to compute any window
compute_major_sch_trends <- function(level_data, major_codes, top_n = 5L) {

  # Sum credits by outside major code and term — one row per major_code × term.
  # major_name is carried alongside for use in the returned tables.
  sch_by_term <- level_data %>%
    filter(!(major_code %in% major_codes)) %>%
    mutate(major_name = if_else(!is.na(major_name) & major_name != "", major_name, major_code)) %>%
    group_by(major_code, major_name, term) %>%
    summarize(sch = sum(credits, na.rm = TRUE), .groups = "drop")

  if (nrow(sch_by_term) == 0L) return(NULL)

  # Identify all terms in the data, then remove summer terms (TT=60).
  # UNM term code format: YYYYTT — the last two digits identify the semester.
  all_terms  <- sort(unique(sch_by_term$term))
  main_terms <- all_terms[all_terms %% 100L != 60L]  # keep spring (10) and fall (80)

  # For each major, delegate to compute_windowed_trend() (utils.R) which owns
  # the windowed comparison logic shared with other modules.
  all_trends <- sch_by_term %>%
    group_by(major_code, major_name) %>%
    group_modify(~ {
      tr <- compute_windowed_trend(
        series         = dplyr::rename(.x, value = sch),
        all_main_terms = main_terms
      )
      tibble(
        pct_1yr        = tr$pct_1yr,
        pct_2yr        = tr$pct_2yr,
        pct_4yr        = tr$pct_4yr,
        abs_change_1yr = tr$abs_change_1yr,
        # Current size: recent_avg from the trend, or fall back to all-term mean
        avg_sch        = if (!is.na(tr$recent_avg)) tr$recent_avg
                         else mean(.x$sch, na.rm = TRUE),
        is_emerging    = tr$is_emerging
      )
    }) %>%
    ungroup()

  # Emerging programs: surged from zero — not rankable by pct but worth surfacing.
  # Minimum floor of 30 avg SCH/term to avoid surfacing noise.
  emerging <- all_trends %>%
    filter(is_emerging, avg_sch >= 30) %>%
    arrange(desc(avg_sch)) %>%
    slice_head(n = top_n) %>%
    select(-is_emerging)

  # Established trends: drop programs with no computable pct_1yr
  trends <- all_trends %>%
    filter(!is.na(pct_1yr)) %>%
    select(-is_emerging)

  # Split into growing vs. declining and return the top N of each
  list(
    growing   = trends %>% filter(pct_1yr > 0L) %>% arrange(desc(abs_change_1yr)) %>% slice_head(n = top_n),
    declining = trends %>% filter(pct_1yr < 0L) %>% arrange(abs_change_1yr)       %>% slice_head(n = top_n),
    emerging  = emerging
  )
}


#' Build the department-vs-college indexed growth comparison data
#'
#' To understand whether a department's SCH growth is impressive or just
#' keeping pace, we compare it against its whole college. We index both series
#' to 100 at the first term — not because the starting value was 100, but so
#' the two lines start at the same point and divergence becomes visible.
#'
#' A department line above the college line means it's growing faster than
#' average for the college. Below means it's falling behind relative to peers.
#' The chart answers: "Is this department outpacing its college, or lagging?"
#'
#' @param credit_hours_data Output of get_credit_hours(), already filtered to
#'   the desired term range
#' @param dept_code Department code (e.g., "BIOL")
#' @param dept_college College code this department belongs to (e.g., "AS")
#' @return Long-format data frame: term (factor), series (chr), indexed_value (dbl)
#'   series values: "<dept_code> Department" and "<dept_college> College"
build_indexed_growth_data <- function(credit_hours_data, dept_code, dept_college) {

  # Total SCH for this department each term (ABQ and EA campuses only —
  # branch campuses run separate analyses)
  dept_totals <- credit_hours_data %>%
    filter(department == dept_code, campus %in% c("ABQ", "EA"), level == "total") %>%
    group_by(term) %>%
    summarise(dept_total = sum(total_hours), .groups = "drop") %>%
    arrange(term)

  # Total SCH for the entire college each term — all departments combined
  college_totals <- credit_hours_data %>%
    filter(college == dept_college, campus %in% c("ABQ", "EA"), level == "total") %>%
    group_by(term) %>%
    summarise(college_total = sum(total_hours), .groups = "drop") %>%
    arrange(term)

  # Join department and college totals side by side, one row per term.
  # all=TRUE keeps terms that appear in one but not the other.
  merged <- merge(dept_totals, college_totals, by = "term", all = TRUE) %>%
    arrange(term)
  merged[is.na(merged)] <- 0  # treat missing terms as zero SCH

  # Use the first term's values as the baseline. Guard against a zero starting
  # value (division by zero) by substituting 1.
  first_dept    <- if (merged$dept_total[1]    == 0) 1 else merged$dept_total[1]
  first_college <- if (merged$college_total[1] == 0) 1 else merged$college_total[1]

  # Divide every value by the baseline and multiply by 100. Now both series
  # start at 100 and the chart shows relative change from the starting point.
  # Then reshape from two columns to long format (one row per term per series)
  # so ggplot can easily draw two lines.
  merged %>%
    mutate(
      dept_indexed    = dept_total    / first_dept    * 100,
      college_indexed = college_total / first_college * 100,
      term            = as.factor(term)
    ) %>%
    pivot_longer(
      cols      = c(dept_indexed, college_indexed),
      names_to  = "series",
      values_to = "indexed_value"
    ) %>%
    # Replace the internal column names with readable labels for the legend.
    # The college label is built from dept_college so it's correct for any dept.
    mutate(series = ifelse(
      series == "dept_indexed",
      paste0(dept_code, " Department"),
      paste0(dept_college, " College")
    ))
}


#' Build college-wide credit hour data and department comparison frames
#'
#' Produces three related summaries used by the college-level plots:
#'
#' 1. All departments in the college, summed by term — for the stacked bar
#'    showing how the whole college's SCH is distributed
#'
#' 2. Just this department's rows — used as the comparison line
#'
#' 3. A year-over-year delta comparison — shows how many percentage points
#'    faster or slower the department grew compared to the college as a whole
#'    (positive = outpacing the college that year; negative = lagging)
#'
#' @param credit_hours_data Output of get_credit_hours(), filtered to term range
#' @param dept_college College code for this department
#' @param dept_code Department code
#' @return Named list: college_credit_hours, dept_credit_hours,
#'   diff_fr_college_hours
build_college_credit_hours <- function(credit_hours_data, dept_college, dept_code) {

  # Sum SCH across all departments in this college, by term
  college_credit_hours <- credit_hours_data %>%
    filter(college == dept_college, campus %in% c("ABQ", "EA"), level == "total") %>%
    group_by(term, department) %>%
    summarize(total_hours = sum(total_hours), .groups = "drop")

  # Add a term_type column (fall/spring/summer) and a college-wide total per term.
  # We need term_type so we can do year-over-year comparisons within each term
  # type (comparing this fall to last fall, not this fall to last spring).
  college_credit_hours <- add_term_type_col(college_credit_hours, "term") %>%
    distinct() %>%
    group_by(term) %>%
    mutate(college_total = sum(total_hours)) %>%
    ungroup()

  # Pull out just this department's rows from the college summary
  dept_credit_hours <- college_credit_hours %>% filter(department == dept_code)

  # Compute the year-over-year growth rate for the department and for the
  # college, then subtract to get diff_heavy: how many percentage points ahead
  # or behind the college the department is growing each year.
  # lag() looks one row back within each term_type group, giving us the
  # same term type from the prior year.
  diff_fr_college_hours <- dept_credit_hours %>%
    group_by(term_type) %>%
    arrange(term_type, term) %>%
    mutate(
      diff_d     = total_hours   / lag(total_hours,   n = 1) * 100,  # dept growth %
      diff_c     = college_total / lag(college_total, n = 1) * 100,  # college growth %
      diff_heavy = diff_d - diff_c  # positive = dept growing faster than college
    ) %>%
    ungroup()

  list(
    college_credit_hours   = college_credit_hours,
    dept_credit_hours      = dept_credit_hours,
    diff_fr_college_hours  = diff_fr_college_hours
  )
}


#' Build subject-level credit hour data for the department's own plots
#'
#' This prepares three differently-shaped views of the same data — all filtered
#' to just this department's courses on main campuses — for three different
#' charts that visualize the same information at different levels of detail.
#'
#' @param credit_hours_data Output of get_credit_hours(), filtered to term range
#' @param dept_code Department code
#' @return Named list with three data frames:
#'   by_subj_level — one row per (term, subject, level), level is NOT "total";
#'                   used for the faceted chart showing each subject broken down
#'                   by lower/upper/grad
#'   by_subj_total — one row per (term, subject), level IS "total";
#'                   used for the stacked chart and the data export table
#'   by_period     — one row per (term, level) with an added period_hours column
#'                   (the sum across all subjects for that level and term);
#'                   used for the by-level stacked bar
build_dept_subject_data <- function(credit_hours_data, dept_code) {
  dept_data <- credit_hours_data %>%
    filter(department == dept_code, campus %in% c("ABQ", "EA")) %>%
    arrange(term, college, department, subject_code, level) %>%
    # Convert term to a factor so charts display terms as categorical labels
    # rather than treating them as numbers
    mutate(term = as.factor(term))

  # Three views of the same base data, shaped differently for each chart
  by_subj_level <- dept_data %>% filter(level != "total")   # breakdown by level
  by_subj_total <- dept_data %>% filter(level == "total")   # aggregate only

  by_period <- dept_data %>%
    filter(level != "total") %>%
    group_by(term, campus, college, department, level) %>%
    # period_hours = total for this level across ALL subjects this term
    mutate(period_hours = sum(total_hours)) %>%
    ungroup() %>%
    arrange(term, college, department, level)

  list(
    by_subj_level = by_subj_level,
    by_subj_total = by_subj_total,
    by_period     = by_period
  )
}


# =============================================================================
# 2. PLOT BUILDERS
# =============================================================================
#
# Each function here takes a pre-built data frame (from a data builder above)
# and returns exactly one chart. No data filtering or aggregation happens here.
# =============================================================================

#' Donut chart: which outside programs are taking courses here?
#'
#' Shows the breakdown of outside-major SCH across all terms in the range.
#' Each named slice is a program that sent enough students to clear the
#' threshold; everything else is rolled into "Other".
#'
#' @param top_outside top_outside slot from build_outside_pie_data()
#' @param color_map color_map slot from build_outside_pie_data()
#' @param level_label Display label for the title (e.g., "Lower Division")
#' @return plotly donut chart, or NULL if there are no outside majors
plot_outside_majors_pie <- function(top_outside, color_map, level_label) {
  if (nrow(top_outside) == 0) return(NULL)

  # Look up each program's assigned color; fall back to gray for any not in the map
  colors <- color_map[as.character(top_outside$major_code)]
  colors[is.na(colors)] <- "#aaaaaa"

  # Order slices by total hours so the largest slice starts at the top
  top_outside <- top_outside %>%
    mutate(major_code = fct_reorder(major_code, total_hours))

  plot_ly(top_outside, labels = ~major_code, values = ~total_hours,
          marker = list(colors = unname(colors),
                        line   = list(color = "#fff", width = 1))) %>%
    add_pie(hole = 0.6) %>%  # hole = 0.6 makes this a donut rather than a full pie
    layout(title  = paste0("Outside Majors (", level_label, ")"),
           legend = list(x = 1.05, y = 0.5),
           xaxis  = list(showgrid = FALSE, zeroline = FALSE, showticklabels = FALSE),
           yaxis  = list(showgrid = FALSE, zeroline = FALSE, showticklabels = FALSE))
}


#' Pie chart: what share of SCH goes to the department's own students?
#'
#' A simple two-slice chart: "Department Majors" vs. "Outside Majors".
#' A service department (like English composition or core science) will show
#' a large outside slice; a specialized program will show a large home slice.
#'
#' @param home_hours,outside_hours,total_hours Scalar SCH totals from
#'   build_major_summary()
#' @param level_label Display label for the title
#' @return plotly pie chart, or NULL if total_hours is 0
plot_home_outside_pie <- function(home_hours, outside_hours, total_hours, level_label) {
  if (total_hours == 0) return(NULL)

  # Build a two-row table with the category names, raw hours, and percentages
  pct_data <- tibble(
    category = c("Department Majors", "Outside Majors"),
    hours    = c(home_hours, outside_hours),
    pct      = round(c(home_hours, outside_hours) / total_hours * 100, 1)
  )

  color_map <- build_color_map(pct_data$category)
  colors    <- unname(color_map[pct_data$category])
  colors[is.na(colors)] <- "#aaaaaa"

  # Include the percentage in the legend label so readers don't have to hover
  plot_ly(pct_data,
          labels = ~paste0(category, " (", pct, "%)"),
          values = ~hours,
          type   = "pie",
          marker = list(colors = colors,
                        line   = list(color = "#fff", width = 1))) %>%
    layout(title  = paste0("Majors vs Non-Majors (", level_label, ")"),
           legend = list(x = 1.05, y = 0.5),
           xaxis  = list(showgrid = FALSE, zeroline = FALSE, showticklabels = FALSE),
           yaxis  = list(showgrid = FALSE, zeroline = FALSE, showticklabels = FALSE))
}


#' Stacked bar: outside major credit hours by term
#'
#' Shows the same programs as the pie chart but over time, so you can see
#' whether outside-major enrollment is growing, shrinking, or shifting among
#' programs. Uses the same colors as the pie chart for direct visual comparison.
#'
#' @param time_data Output of build_outside_time_data()
#' @param color_map color_map slot from build_outside_pie_data()
#' @param level_label Display label for the title
#' @return plotly stacked bar chart, or NULL if time_data is empty
plot_outside_time_series <- function(time_data, color_map, level_label) {
  if (nrow(time_data) == 0) return(NULL)

  plot_ly(time_data,
          x      = ~term,
          y      = ~total_hours,
          color  = ~major_group,
          colors = color_map,
          type   = "bar") %>%
    layout(
      barmode = "stack",
      title   = paste0("Outside Majors — Credit Hours by Term (", level_label, ")"),
      xaxis   = list(title = "Term", tickangle = -45),
      yaxis   = list(title = "Credit Hours"),
      legend  = list(orientation = "h", y = -0.35)  # legend below the chart
    )
}


#' Line chart: department vs. college indexed SCH growth
#'
#' Both lines start at 100 (the first term in the analysis window) so their
#' trajectories can be directly compared regardless of their actual sizes.
#' If the department line is above the college line, the department is growing
#' faster than its college peers.
#'
#' @param indexed_data Output of build_indexed_growth_data()
#' @param dept_code Used to identify the department series by name
#' @return ggplot line + point chart
plot_indexed_growth <- function(indexed_data, dept_code) {
  dept_label    <- paste0(dept_code, " Department")
  college_label <- unique(indexed_data$series[indexed_data$series != dept_label])
  if (length(college_label) == 0) college_label <- "College"

  color_map <- c("#FF6B35", "#2E8B57")
  names(color_map) <- c(dept_label, college_label)

  plot_ly(indexed_data, x = ~term, y = ~indexed_value, color = ~series,
          colors        = color_map,
          type          = "scatter", mode = "lines+markers",
          hovertemplate = "%{x}<br>Index: %{y:.1f}<extra>%{fullData.name}</extra>") %>%
    layout(
      title  = list(text = paste0("Credit Hour Growth: ", dept_code, " vs ", college_label,
                                  "<br><sup>Both indexed to 100 at first term.</sup>"), x = 0),
      xaxis  = list(title = "Academic Period", tickangle = -45),
      yaxis  = list(title = "Indexed Credit Hours (First Term = 100)"),
      legend = list(orientation = "h", x = 0, y = -0.2),
      shapes = list(list(
        type = "line",
        x0 = 0, x1 = 1, xref = "paper",
        y0 = 100, y1 = 100, yref = "y",
        line = list(color = "gray", dash = "dash", width = 1)
      ))
    )
}


#' Stacked bar: all departments in the college, showing each department's share
#'
#' Provides context for the department's SCH within its college — is this a
#' large department, a medium one, or a small one relative to peers?
#'
#' @param college_credit_hours college_credit_hours slot from
#'   build_college_credit_hours()
#' @return ggplotly interactive bar chart
plot_college_credit_hours <- function(college_credit_hours) {
  plot_ly(college_credit_hours %>% mutate(term = as.character(term)),
          x = ~term, y = ~total_hours, color = ~department,
          type          = "bar",
          hovertemplate = "%{x}<br>%{y:,} hrs<extra>%{fullData.name}</extra>") %>%
    layout(barmode = "stack",
           xaxis   = list(title = "Academic Period", tickangle = -45),
           yaxis   = list(title = "Credit Hours"),
           legend  = list(orientation = "h", x = 0, y = -0.2))
}


#' Bar chart: how much faster or slower is the department growing vs. its college?
#'
#' Bars above zero mean the department grew faster than the college average that
#' year; bars below zero mean it grew slower. A consistently positive department
#' is gaining share; a consistently negative one is losing share.
#'
#' @param diff_fr_college_hours diff_fr_college_hours slot from
#'   build_college_credit_hours()
#' @return ggplot bar chart
plot_college_comp <- function(diff_fr_college_hours) {
  plot_ly(diff_fr_college_hours %>% mutate(term = as.character(term)),
          x = ~term, y = ~diff_heavy,
          type          = "bar",
          marker        = list(color = ~ifelse(diff_heavy >= 0, "#59a14f", "#e15759")),
          hovertemplate = "%{x}<br>Diff: %{y:+.1f}%<extra></extra>") %>%
    layout(xaxis = list(title = "Academic Year", tickangle = -45),
           yaxis = list(title = "% diff from College"))
}


#' Faceted bar chart: credit hours by subject code and course level
#'
#' Creates one panel per subject code (e.g., BIOL, BIOC, BIOM), with bars
#' stacked by level (lower/upper/grad) so you can see both the volume and the
#' mix for each subject area.
#'
#' @param by_subj_level by_subj_level slot from build_dept_subject_data()
#' @param palette RColorBrewer palette name for the level fill colors
#' @return ggplot with one facet panel per subject code
plot_chd_by_subj_faceted <- function(by_subj_level, palette) {
  subj_codes <- unique(by_subj_level$subject_code)
  sub_plots  <- lapply(seq_along(subj_codes), function(i) {
    sc <- subj_codes[[i]]
    plot_ly(by_subj_level %>% filter(subject_code == sc) %>% mutate(term = as.character(term)),
            x = ~term, y = ~total_hours, color = ~level, colors = palette,
            type          = "bar",
            showlegend    = (i == 1),
            legendgroup   = ~level,
            hovertemplate = "%{x}<br>%{y:,} hrs<extra>%{fullData.name}</extra>") %>%
      layout(barmode = "stack",
             annotations = list(list(text = sc, showarrow = FALSE,
                                     xref = "paper", yref = "paper",
                                     x = 0.5, y = 1.05, font = list(size = 11))),
             xaxis = list(tickangle = -75))
  })
  subplot(sub_plots, nrows = ceiling(length(subj_codes) / 3),
          shareX = FALSE, shareY = FALSE, titleX = TRUE, titleY = TRUE, margin = 0.08) %>%
    layout(legend = list(orientation = "h", x = 0, y = -0.1),
           yaxis  = list(title = "Credit Hours"))
}


#' Stacked bar: total credit hours by subject code across all levels
#'
#' A simpler view than the faceted chart — all subjects stacked in one bar
#' per term, useful for seeing which subject area dominates and how the mix
#' shifts over time.
#'
#' @param by_subj_total by_subj_total slot from build_dept_subject_data()
#' @return ggplot stacked bar chart
plot_chd_by_subj_stacked <- function(by_subj_total) {
  plot_ly(by_subj_total %>% mutate(term = as.character(term)),
          x = ~term, y = ~total_hours, color = ~subject_code,
          type          = "bar",
          hovertemplate = "%{x}<br>%{y:,} hrs<extra>%{fullData.name}</extra>") %>%
    layout(barmode = "stack",
           xaxis   = list(title = "Academic Period", tickangle = -75),
           yaxis   = list(title = "Credit Hours"),
           legend  = list(orientation = "h", x = 0, y = -0.2))
}


#' Stacked bar: total credit hours by course level (lower/upper/grad)
#'
#' Shows the balance between undergraduate and graduate instruction over time.
#' A shift in this chart might signal a change in the department's graduate
#' program size or a major curriculum redesign.
#'
#' @param by_period by_period slot from build_dept_subject_data()
#' @param subj_codes Subject codes shown in the chart title for reference
#' @param palette RColorBrewer palette name
#' @return ggplot stacked bar chart
plot_chd_by_level <- function(by_period, subj_codes, palette) {
  plot_ly(by_period %>% mutate(term = as.character(term)),
          x = ~term, y = ~total_hours, color = ~level, colors = palette,
          type          = "bar",
          hovertemplate = "%{x}<br>%{y:,} hrs<extra>%{fullData.name}</extra>") %>%
    layout(barmode = "stack",
           title   = list(text = paste0("Subject codes: ", paste(subj_codes, collapse = ", ")), x = 0),
           xaxis   = list(title = "Academic Period", tickangle = -75),
           yaxis   = list(title = "Credit Hours"),
           legend  = list(orientation = "h", x = 0, y = -0.2))
}


# =============================================================================
# 3. ORCHESTRATORS
# =============================================================================
#
# These are the functions called by Dept Trends support. Each one
# calls data builders to prepare the data, calls plot builders to create the
# charts, then packages everything into a list(plots=..., tables=...) that
# the active web profile can reference by name.
# =============================================================================

#' Credit Hours by Major
#'
#' The main function for the "who is taking our courses" analysis. Runs the
#' full pipeline three times — once for lower division, once for upper division,
#' and once for all undergrad combined — then assembles all plots and tables.
#'
#' @param students cedar_students data frame (pre-filtered to this department)
#' @param dept_code Department code (e.g., "BIOL")
#' @param term_start,term_end Integer term codes for the analysis window (inclusive)
#' @return list with:
#'   $plots:  sch_outside_pct_lower_plot, sch_dept_pct_lower_plot,
#'            sch_top_majors_lower_plot, sch_outside_pct_upper_plot,
#'            sch_dept_pct_upper_plot, sch_top_majors_upper_plot,
#'            sch_outside_pct_plot, sch_dept_pct_plot
#'   $tables: credit_hours_data_w, sch_major_trends_lower, sch_outside_full_lower,
#'            sch_major_trends_upper, sch_outside_full_upper
credit_hours_by_major <- function(students, dept_code, term_start, term_end) {

  # Verify the incoming data has everything we need before doing any work
  required_cols <- c("term", "final_grade", "credits", "major_code", "major_name",
                     "student_college", "level")
  missing_cols <- setdiff(required_cols, colnames(students))
  if (length(missing_cols) > 0) {
    stop("[credit-hours.R] Missing required columns in students: ",
         paste(missing_cols, collapse = ", "))
  }

  message("[credit-hours.R] credit_hours_by_major for dept: ", dept_code)

  # Derive home major codes from major_to_dept (loaded by catalog_lookups.R).
  # This replaces the explicit major_codes parameter: any major code that the
  # catalog maps to this dept is "home." If the dept has no catalog entries,
  # fall back to a direct code match (dept_code == major_code).
  major_codes <- if (exists("major_to_dept") && length(major_to_dept) > 0) {
    raw_codes <- names(major_to_dept)[!is.na(major_to_dept) & major_to_dept == dept_code]
    raw_codes <- as.character(raw_codes)
    unique(raw_codes[!is.na(raw_codes) & nzchar(raw_codes)])
  } else {
    dept_code
  }
  if (length(major_codes) == 0) major_codes <- dept_code

  # Filter to the term range, passing grades, and normalized college names
  all_data <- build_major_level_data(students, term_start, term_end)

  # The wide summary table goes in $tables regardless of level —
  # it covers all levels combined and is used for the export data view
  credit_hours_data_w <- build_credit_hours_wide_table(all_data)

  # Inner helper: run the full data → plots pipeline for one level slice.
  # Called three times below (lower, upper, all undergrad).
  make_level_outputs <- function(level_filter, level_label) {
    level_data <- all_data %>%
      filter(level %in% level_filter)

    if (nrow(level_data) == 0) {
      message("[credit-hours.R] No data for ", level_label)
      return(list(outside_plot = NULL, dept_plot = NULL, time_plot = NULL,
                  trends = NULL, full_outside_table = NULL))
    }

    # Step 1: Split students into home majors vs. outside majors
    split  <- build_major_summary(level_data, major_codes)

    # Step 2: Decide which outside programs get named slices vs. go into "Other".
    # Also pass a recent-term summary (last 4 non-summer terms = ~2 years) so that
    # programs that grew recently but have a diluted all-time average still get
    # their own slice rather than disappearing into "Other".
    recent_terms <- {
      all_t <- sort(unique(level_data$term))
      tail(all_t[all_t %% 100L != 60L], 4L)
    }
    recent_outside <- build_major_summary(
      level_data %>% filter(term %in% recent_terms), major_codes
    )$outside
    groups <- build_outside_pie_data(split$outside, recent_summary = recent_outside)

    # Step 3: Build the term-by-term view using the same named set as the pie
    time_data <- build_outside_time_data(
      level_data, major_codes,
      groups$named_outside %>% pull(major_code)
    )

    # Step 4: Compute trend windows for the growing/declining programs table
    trends <- compute_major_sch_trends(level_data, major_codes)

    message("[credit-hours.R] ", level_label,
            ": home=", split$home_hours, " outside=", split$outside_hours)

    # Step 5: Build the three charts for this level
    list(
      outside_plot       = plot_outside_majors_pie(groups$top_outside, groups$color_map, level_label),
      dept_plot          = plot_home_outside_pie(split$home_hours, split$outside_hours,
                                                  split$total_hours, level_label),
      time_plot          = plot_outside_time_series(time_data, groups$color_map, level_label),
      trends             = trends,
      full_outside_table = groups$outside_for_pie,  # complete ranking for the export table
      # raw data needed to rebuild plots on cache hit
      top_outside        = groups$top_outside,
      color_map          = groups$color_map,
      time_data          = time_data,
      home_hours         = split$home_hours,
      outside_hours      = split$outside_hours,
      total_hours        = split$total_hours
    )
  }

  # Run the pipeline for each level group
  lower  <- make_level_outputs("lower",             "Lower Division")
  upper  <- make_level_outputs("upper",             "Upper Division")
  all_ug <- make_level_outputs(c("lower", "upper"), "All Undergrad")

  # Package everything into the standard $plots + $tables return shape
  list(
    plots = list(
      sch_outside_pct_lower_plot = lower$outside_plot,
      sch_dept_pct_lower_plot    = lower$dept_plot,
      sch_top_majors_lower_plot  = lower$time_plot,
      sch_outside_pct_upper_plot = upper$outside_plot,
      sch_dept_pct_upper_plot    = upper$dept_plot,
      sch_top_majors_upper_plot  = upper$time_plot,
      sch_outside_pct_plot       = all_ug$outside_plot,
      sch_dept_pct_plot          = all_ug$dept_plot
    ),
    tables = list(
      credit_hours_data_w    = credit_hours_data_w,
      sch_major_trends_lower = lower$trends,
      sch_outside_full_lower = lower$full_outside_table,
      sch_major_trends_upper = upper$trends,
      sch_outside_full_upper = upper$full_outside_table,
      # raw data needed to rebuild plots on cache hit
      sch_top_outside_lower  = lower$top_outside,
      sch_color_map_lower    = lower$color_map,
      sch_time_data_lower    = lower$time_data,
      sch_split_lower        = c(home = lower$home_hours, outside = lower$outside_hours, total = lower$total_hours),
      sch_top_outside_upper  = upper$top_outside,
      sch_color_map_upper    = upper$color_map,
      sch_time_data_upper    = upper$time_data,
      sch_split_upper        = c(home = upper$home_hours, outside = upper$outside_hours, total = upper$total_hours),
      sch_top_outside_all_ug = all_ug$top_outside,
      sch_color_map_all_ug   = all_ug$color_map,
      sch_split_all_ug       = c(home = all_ug$home_hours, outside = all_ug$outside_hours, total = all_ug$total_hours)
    )
  )
}


#' Credit Hours by Faculty Category
#'
#' Shows how SCH production is distributed across faculty job categories —
#' tenure-track, lecturer, adjunct, etc. Requires the cedar_faculty table,
#' which is built from HR data and is not always available.
#'
#' @param data_objects List containing cedar_students and cedar_faculty
#' @param dept_code Department code
#' @param subj_codes Subject codes for plot titles
#' @param term_start,term_end Integer term codes (inclusive)
#' @param palette RColorBrewer palette name
#' @return list($plots): chd_by_fac_facet_plot (breakdown by level),
#'   chd_by_fac_plot (totals stacked by job category)
plot_chd_by_fac_faceted <- function(by_level, subj_codes, palette) {
  if (nrow(by_level) == 0) return("Insufficient data.")
  levels_present <- unique(by_level$level)
  sub_plots <- lapply(seq_along(levels_present), function(i) {
    lv <- levels_present[[i]]
    plot_ly(by_level %>% filter(level == lv),
            x = ~term, y = ~total_hours, color = ~job_category, colors = palette,
            type          = "bar",
            showlegend    = (i == 1),
            legendgroup   = ~job_category,
            hovertemplate = "%{x}<br>%{y:,} hrs<extra>%{fullData.name}</extra>") %>%
      layout(barmode = "group",
             annotations = list(list(text = lv, showarrow = FALSE,
                                     xref = "paper", yref = "paper",
                                     x = 0.5, y = 1.05, font = list(size = 11))),
             xaxis = list(tickangle = -45))
  })
  subplot(sub_plots, nrows = 1, shareX = FALSE, shareY = TRUE,
          titleX = TRUE, titleY = TRUE, margin = 0.06) %>%
    layout(title  = list(text = paste0("Subject codes: ", paste(subj_codes, collapse = ", ")), x = 0),
           yaxis  = list(title = "Credit Hours"),
           legend = list(orientation = "h", x = 0, y = -0.2))
}

plot_chd_by_fac_stacked <- function(by_total, subj_codes, palette) {
  plot_ly(by_total, x = ~term, y = ~total_hours, color = ~job_category, colors = palette,
          type          = "bar",
          hovertemplate = "%{x}<br>%{y:,} hrs<extra>%{fullData.name}</extra>") %>%
    layout(barmode = "stack",
           title   = list(text = paste0("Subject codes: ", paste(subj_codes, collapse = ", ")), x = 0),
           xaxis   = list(title = "Academic Period", tickangle = -45),
           yaxis   = list(title = "Credit Hours"),
           legend  = list(orientation = "h", x = 0, y = -0.2))
}


credit_hours_by_fac <- function(data_objects, dept_code, subj_codes, term_start, term_end, palette) {
  message("[credit-hours.R] credit_hours_by_fac for dept: ", dept_code)

  students    <- data_objects[["cedar_students"]]
  fac_by_term <- data_objects[["cedar_faculty"]]

  # cedar_faculty comes from HR data — it may genuinely not exist yet
  if (is.null(fac_by_term)) {
    stop("[credit-hours.R] cedar_faculty is NULL — run transform-hr-to-cedar.R to create it")
  }

  if (nrow(fac_by_term) == 0) {
    return(list(plots = list(
      chd_by_fac_facet_plot = "No faculty data available",
      chd_by_fac_plot       = "No faculty data available"
    )))
  }

  required_student_cols <- c("final_grade", "term", "department", "credits",
                              "campus", "college", "level", "instructor_id")
  missing <- setdiff(required_student_cols, colnames(students))
  if (length(missing) > 0) {
    stop("[credit-hours.R] Missing student columns: ", paste(missing, collapse = ", "))
  }

  required_faculty_cols <- c("term", "instructor_id", "department", "job_category")
  missing <- setdiff(required_faculty_cols, colnames(fac_by_term))
  if (length(missing) > 0) {
    stop("[credit-hours.R] Missing faculty columns: ", paste(missing, collapse = ", "))
  }

  # as_of_date appears in some faculty exports but causes problems in the merge
  if ("as_of_date" %in% colnames(fac_by_term)) {
    fac_by_term <- fac_by_term %>% select(-as_of_date)
  }

  # Keep only this department's courses within the analysis window
  filtered <- students %>%
    filter(
      final_grade %in% passing_grades,
      department  == dept_code,
      term        >= term_start & term <= term_end
    )

  # Join student enrollment rows to faculty job category by instructor + term.
  # all.x=TRUE is a left join: keeps all student rows even if the instructor
  # doesn't appear in the faculty table (e.g., a visiting instructor).
  merged <- merge(filtered, fac_by_term,
                  by    = c("term", "instructor_id", "department"),
                  all.x = TRUE)

  # Summarize by level for the faceted view, then collapse levels for the stacked view
  by_level <- merged %>%
    filter(campus %in% c("ABQ", "EA")) %>%
    group_by(term, college, department, level, job_category) %>%
    summarize(total_hours = sum(credits), .groups = "drop") %>%
    mutate(term = as.factor(term))

  by_total <- by_level %>%
    group_by(term, college, department, job_category) %>%
    summarize(total_hours = sum(total_hours), .groups = "drop")

  chd_by_fac_facet_plot <- plot_chd_by_fac_faceted(by_level, subj_codes, palette)
  chd_by_fac_plot       <- plot_chd_by_fac_stacked(by_total,  subj_codes, palette)

  list(
    plots = list(
      chd_by_fac_facet_plot = chd_by_fac_facet_plot,
      chd_by_fac_plot       = chd_by_fac_plot
    ),
    tables = list(
      chd_fac_by_level = by_level,
      chd_fac_by_total = by_total
    )
  )
}


#' Credit Hours for Dept Trends
#'
#' Produces the full set of department-level SCH plots: how the department
#' compares to its college over time, broken down by subject code and level.
#'
#' @param class_lists cedar_students data frame (full — not pre-filtered to dept)
#' @param dept_code Department code (e.g., "BIOL")
#' @param subj_codes Subject codes used in plot titles (informational only)
#' @param term_start,term_end Integer term codes for the analysis window (inclusive)
#' @param palette RColorBrewer palette name for bar chart colors
#' @return list with:
#'   $plots:  college_credit_hours_plot, college_credit_hours_comp_plot,
#'            college_dept_dual_plot, chd_by_year_facet_subj_plot,
#'            chd_by_year_subj_plot, chd_by_period_plot
#'   $tables: chd_by_period_table
get_credit_hours_for_dept_report <- function(class_lists, dept_code, subj_codes,
                                              term_start, term_end, palette) {
  message("[credit-hours.R] get_credit_hours_for_dept_report for dept: ", dept_code)

  # Build the full credit hour summary for all departments and filter to window
  credit_hours_data <- get_credit_hours(class_lists) %>%
    filter(term >= term_start & term <= term_end)

  # Determine which college this department belongs to by finding the most
  # common college code in the data — more robust than a lookup table
  dept_college <- credit_hours_data %>%
    ungroup() %>%
    filter(department == dept_code, !is.na(college), college != "") %>%
    count(college, sort = TRUE) %>%
    slice(1) %>%
    pull(college)
  if (length(dept_college) == 0) dept_college <- NA_character_
  message("[credit-hours.R] dept_college: ", dept_college)

  # Build all the data frames needed by the plots
  college_data   <- build_college_credit_hours(credit_hours_data, dept_college, dept_code)
  indexed_data   <- build_indexed_growth_data(credit_hours_data, dept_code, dept_college)
  dept_subj_data <- build_dept_subject_data(credit_hours_data, dept_code)

  # The period table pivots level breakdown wide — one column per level,
  # one row per term × subject — for the tabular export view
  chd_by_period_table <- dept_subj_data$by_subj_total %>%
    pivot_wider(names_from = level, values_from = total_hours) %>%
    ungroup() %>%
    select(term, department, 4:ncol(.))

  list(
    plots = list(
      college_credit_hours_plot      = plot_college_credit_hours(college_data$college_credit_hours),
      college_credit_hours_comp_plot = plot_college_comp(college_data$diff_fr_college_hours),
      college_dept_dual_plot         = plot_indexed_growth(indexed_data, dept_code),
      chd_by_year_facet_subj_plot    = plot_chd_by_subj_faceted(dept_subj_data$by_subj_level, palette),
      chd_by_year_subj_plot          = plot_chd_by_subj_stacked(dept_subj_data$by_subj_total),
      chd_by_period_plot             = plot_chd_by_level(dept_subj_data$by_period, subj_codes, palette)
    ),
    tables = list(
      chd_by_period_table = chd_by_period_table,
      # raw tables needed to rebuild plots on cache hit
      chd_college         = college_data$college_credit_hours,
      chd_diff_fr_college = college_data$diff_fr_college_hours,
      chd_indexed         = indexed_data,
      chd_by_subj_level   = dept_subj_data$by_subj_level,
      chd_by_subj_total   = dept_subj_data$by_subj_total,
      chd_by_period_data  = dept_subj_data$by_period
    )
  )
}
