#' Calculate Course-Level Enrollment Statistics
#'
#' Summarizes student enrollments for each course by term and term_type, counting
#' registration statuses (registered, dropped, waitlisted) and calculating averages.
#'
#' @param students Data frame of student-level course registration data.
#'   Required columns: campus, college, term, term_type, subject_course, student_id,
#'   registration_status_code
#' @param reg_status Optional character vector of registration status codes to filter by
#'   (e.g., c("RE", "DR")). If NULL (default), all status codes are summarized.
#'
#' @return Data frame with enrollment statistics per course per term. Key columns:
#' \describe{
#'   \item{registered}{Count of registered students (RE, RS codes) for THIS TERM}
#'   \item{registered_mean}{AVERAGE registered count across all terms OF SAME TERM_TYPE.
#'     E.g., if Fall 2023 had 45 and Fall 2024 had 55, registered_mean = 50.
#'     This is used as the denominator for calculating average percentages.}
#'   \item{dr_early, dr_late, dr_all}{Drop counts for this term}
#'   \item{dr_early_mean, dr_late_mean, dr_all_mean}{Average drops across term_type}
#' }
#'
#' @details
#' The "_mean" columns are critical for rollcall analysis. They represent the average
#' enrollment across all terms of the same type (e.g., all falls), providing a stable
#' baseline for calculating "typical" percentages.
#'
#' Calculation flow:
#' 1. Groups by campus, college, subject_course, term, term_type, registration_status_code
#' 2. Counts distinct students per group
#' 3. Regroups by term_type (removing term) to calculate means across terms
#' 4. NAs replaced with 0
#'
#' @examples
#' # Summarize all registration statuses:
#' calc_cl_enrls(students_df)
#' # Summarize only registered and dropped students:
#' calc_cl_enrls(students_df, reg_status = c("RE", "DR"))

calc_cl_enrls <- function(filtered_students, reg_status = NULL, by_part_term = FALSE) {

  # filtered_students <- load_students()
  #opt <- list()
  #opt[["course"]] <- "HIST 1105"
  #filtered_students <- filter_class_list(students,opt)
  # reg_status <- c("DR")
  # reg_status <- NULL

  # Optional part-of-term dimension. Off by default so existing callers (course
  # report, dept dashboard, forecasts, demographics) keep one row per course.
  # Regstats turns it on so a full-term section and its 8-week half-term
  # siblings are counted — and anomaly-compared — as the distinct entities they
  # are, rather than lumped into one course total. Requires part_term on the
  # input (present in cedar_students).
  if (isTRUE(by_part_term) && !"part_term" %in% names(filtered_students)) {
    stop("[enrl.R] calc_cl_enrls(by_part_term = TRUE) requires a part_term column in filtered_students")
  }
  pt_grp <- if (isTRUE(by_part_term)) "part_term" else character(0)

  reg_stats_summary <- tibble()

  # get distinct rows within courses; use subject_course to lump all sections topics courses together
  cedar_debug("[enrl.R] Getting distinct student within courses...")
  cl_enrls <- filtered_students %>%
    group_by(across(all_of(c("campus", "college", "term", "subject_course", pt_grp)))) %>%
    distinct(student_id, .keep_all = TRUE)

  # count students in each term by reg status code
  cedar_debug("[enrl.R] Counting students in each campus/college/course/term by reg status code...")
  cl_enrls <- cl_enrls %>%
    group_by(across(all_of(c("campus", "college", "subject_course", "registration_status_code", "term", "term_type", pt_grp)))) %>%
    summarize(count = n(), .groups="keep")

  # calc mean reg codes per course and term type
  cedar_debug("[enrl.R] Calculating mean counts across terms...")
  cl_enrls <- cl_enrls %>%
    group_by(across(all_of(c("campus", "college", "subject_course", "term_type", "registration_status_code", pt_grp)))) %>%
    mutate(mean = round(mean(count),digits=1))


  if (is.null(reg_status)) {
    cedar_debug("[enrl.R] reg_status is NULL; single-pass pivot across all registration codes...")

    # Single-pass: classify and sum all status buckets in one summarize() call.
    # Uses conditional sum() instead of 6 separate filter+merge passes.
    # Zero-count buckets return 0 (not NA) because sum(integer(0)) == 0L.
    reg_stats_summary <- cl_enrls %>%
      group_by(across(all_of(c("campus", "college", "subject_course", "term", "term_type", pt_grp)))) %>%
      summarize(
        registered = sum(count[registration_status_code %in% STATUS_REGISTERED]),
        dr_early   = sum(count[registration_status_code %in% STATUS_DROP_EARLY]),
        dr_late    = sum(count[registration_status_code %in% STATUS_DROP_LATE]),
        dr_all     = sum(count[registration_status_code %in% STATUS_DROP_ALL]),
        wl_all     = sum(count[registration_status_code %in% STATUS_WAITLIST]),
        cl_total   = sum(count[!registration_status_code %in% STATUS_WAITLIST]),
        .groups    = "keep"
      )

    # Compute cross-term means grouped by term_type (drop term from grouping)
    cedar_debug("[enrl.R] calculating means across term types...")
    reg_stats_summary <- reg_stats_summary %>%
      group_by(across(all_of(c("campus", "college", "subject_course", "term_type", pt_grp)))) %>%
      mutate(across(
        c(registered, dr_early, dr_late, dr_all, cl_total),
        ~ round(mean(.), digits = 2),
        .names = "{.col}_mean"
      ))
  } # end if reg_status is null

  # if given list of reg codes, filter for those
  else if (!is.null(reg_status)) {
    cedar_debug("[enrl.R] Filtering for status codes: ", reg_status)
    reg_stats_summary <- cl_enrls %>% filter(registration_status_code %in% reg_status)
  }

  cedar_debug("[enrl.R] calc_cl_enrls returning ", nrow(reg_stats_summary), " rows.")

  return (reg_stats_summary)
}

#' Add a census-point enrollment column
#'
#' Census enrollment is the headcount at the census snapshot: students still
#' registered at term end (\code{registered} — RE/RS/RR) PLUS those who dropped
#' after census (\code{dr_late} — DG/DW). Late drops were present at census but
#' left before term end, so adding them back recovers the census headcount; early
#' drops (DR) left before census and are excluded. This is the classlist analogue
#' of the census basis regstats uses for saturation fill (DESR enrolled + late
#' drops), so census enrollment lines up however it is measured.
#'
#' @param df A course-term enrollment table carrying \code{registered} and
#'   \code{dr_late} (e.g. a \code{\link{calc_cl_enrls}} result or
#'   \code{cedar_cl_enrls_base}).
#' @return \code{df} with a \code{census_enrl} column added.
#' @seealso \code{\link{calc_census_enrl_baselines}}
add_census_enrl <- function(df) {
  missing <- setdiff(c("registered", "dr_late"), names(df))
  if (length(missing) > 0)
    stop("[enrl.R] add_census_enrl() needs column(s): ", paste(missing, collapse = ", "))
  df %>% mutate(census_enrl = registered + dplyr::coalesce(dr_late, 0))
}

#' Historical census-enrollment baselines per course and term type
#'
#' Summarizes each course's census enrollment (see \code{\link{add_census_enrl}})
#' across its offerings into three things a "typical enrollment" readout needs:
#' \itemize{
#'   \item \code{census_hist} / \code{census_hist_terms} — the census series and
#'     its terms, ordered oldest→newest and including any target term so a
#'     sparkline can mark it in place;
#'   \item \code{census_mean} — the mean census enrollment over PRIOR terms
#'     (\code{target_terms} excluded so the viewed term can't inflate its own
#'     baseline), rounded to one decimal;
#'   \item \code{n_hist_terms} — the count of those prior terms.
#' }
#' Grouping is same-term-type by default so falls compare to falls; part of term is
#' added to the grouping automatically when the data carries it. Data finer than the
#' grouping (e.g. multiple part-of-term rows when \code{part_term} is not a key) is
#' summed per term first so the series lists one census figure per term.
#'
#' @param df Course-term enrollment rows (e.g. \code{cedar_cl_enrls_base} or a
#'   \code{\link{calc_cl_enrls}} result). Needs \code{registered}, \code{dr_late},
#'   \code{term}, and the grouping keys.
#' @param target_terms Term code(s) to exclude from the mean and count (the term(s)
#'   being viewed). \code{NULL} keeps every term.
#' @param keys Grouping columns; \code{part_term} is appended when present.
#' @return One row per group with \code{census_mean}, \code{n_hist_terms}, and the
#'   \code{census_hist} / \code{census_hist_terms} list-columns.
#' @seealso \code{\link{add_census_enrl}}
calc_census_enrl_baselines <- function(df, target_terms = NULL,
    keys = c("campus", "college", "subject_course", "term_type")) {
  df <- add_census_enrl(df)
  if ("part_term" %in% names(df)) keys <- unique(c(keys, "part_term"))
  keys <- intersect(keys, names(df))
  target <- if (length(target_terms) > 0) unique(target_terms) else df$term[0]

  df %>%
    # Collapse to one census figure per group×term first, so callers grouping at a
    # coarser grain than the data (e.g. no part_term) sum cleanly rather than
    # listing duplicate term entries in the series.
    group_by(across(all_of(c(keys, "term")))) %>%
    summarize(census_enrl = sum(census_enrl, na.rm = TRUE), .groups = "drop") %>%
    arrange(term) %>%
    group_by(across(all_of(keys))) %>%
    summarize(
      census_hist       = list(census_enrl),
      census_hist_terms = list(term),
      census_mean       = {
        h <- census_enrl[!term %in% target]
        if (length(h) == 0) NA_real_ else round(mean(h), 1)
      },
      n_hist_terms      = sum(!term %in% target),
      .groups = "drop"
    )
}

#' Compress AOP Course Pairs
#'
#' Compresses paired AOP (All Online Programs) course sections into single rows.
#' AOP courses typically consist of a MOPS (Modular Online Pair Section) and a
#' paired online section that are crosslisted. This function combines them into
#' a single row for cleaner reporting and analysis.
#'
#' @param courses Data frame of course sections. Must include columns:
#'   term, crosslist_code, delivery_method, crn, enrolled, total_enrl
#' @param opt Options list (currently unused but kept for consistency)
#'
#' @return Data frame with AOP pairs compressed. Non-AOP courses are unchanged.
#'   Compressed rows have:
#'   \itemize{
#'     \item \code{enrolled} = total_enrl (combined enrollment)
#'     \item \code{sect_enrl} = enrollment of kept section
#'     \item \code{pair_enrl} = enrollment of merged partner section
#'   }
#'
#' @details
#' The compression process:
#' \enumerate{
#'   \item Identifies MOPS delivery method courses (AOP sections)
#'   \item Filters for crosslisted AOP courses (crosslist_code != "0")
#'   \item Groups paired sections by term and crosslist_code
#'   \item Keeps first section (by delivery_method sort order)
#'   \item Combines enrollment: sets enrolled = total_enrl for kept row
#'   \item Adds sect_enrl and pair_enrl columns showing split
#'   \item Merges back with non-AOP courses
#' }
#'
#' AOP sections without a crosslisted partner are left as single sections.
#'
#' @examples
#' \dontrun{
#' # Compress AOP pairs in filtered course data
#' opt <- list(dept = "BIOL", term = "202510")
#' courses_filtered <- filter_DESRs(cedar_sections, opt)
#' courses_compressed <- compress_aop_pairs(courses_filtered, opt)
#' }
#'
#' @seealso \code{\link{get_enrl}} which calls this function when opt$aop = "compress"
compress_aop_pairs <- function(courses, opt) {
  cedar_debug("[enrl.R] Compressing AOP courses into single row...")

  # for clarity, combine aop and twin courses into single entry
  # test to see if we're filtering by dept
  courses <- courses %>% group_by(term, crosslist_code)

  # get just AOP courses
  courses_aop <- courses %>% filter(delivery_method == "MOPS")

  # AOP sections don't necessarily have a partner, so remove those without one
  # TODO: handle case of AOP course having partner, but not being crosslisted
  # might be able to check on course title
  courses_aop <- courses_aop %>% filter(crosslist_code != "0")

  # get pairs of aop and twin section
  aop_pairs <- courses_aop %>% filter(crosslist_code %in% courses_aop$crosslist_code) %>%
    distinct(crn, .keep_all = TRUE) %>%
    group_by(term, crosslist_code)

  # to collapse the aop and online section into one row, get each section's enrollment
  aop_pairs <- aop_pairs %>% mutate(sect_enrl = enrolled, pair_enrl = total_enrl - enrolled)

  # arrange by delivery_method, and take first row of group
  aop_single <- aop_pairs %>% arrange(delivery_method) %>% filter(row_number() == 1)

  # since compressing two sections into one, change enrolled to mimic total_enrl
  # otherwise, compressing effectively deletes the non-aop section enrollment
  aop_single <- aop_single %>% mutate(enrolled = total_enrl)

  # remove all pairs from orig course list
  courses <- courses %>% filter(!(crosslist_code %in% courses_aop$crosslist_code)) %>% distinct(crn, .keep_all = TRUE) %>%
    group_by(term, crosslist_code)

  # add all single rows
  courses <- rbind(courses,aop_single)

  return(courses)
} # end compress_aop_pairs
#' Summarize Courses by Grouping Columns
#'
#' Generic summary function that aggregates course section data by specified
#' grouping columns. Calculates section counts, enrollment statistics, and
#' availability metrics.
#'
#' @param courses Data frame of course sections. Must include columns used in
#'   grouping plus: enrolled, crosslist_code, available, waitlist_count
#' @param opt Options list containing:
#'   \itemize{
#'     \item \code{group_cols} - Character vector of column names to group by.
#'       If NULL, uses default: campus, college, term, term_type, subject,
#'       subject_course, course_title, level, gen_ed_area
#'   }
#'
#' @return Data frame summarized by group_cols with columns:
#'   \describe{
#'     \item{sections}{Total number of sections in group}
#'     \item{xl_sections}{Number of crosslisted sections (crosslist_code != "0")}
#'     \item{reg_sections}{Number of regular (non-crosslisted) sections}
#'     \item{avg_size}{Average enrollment per section (rounded to 1 decimal)}
#'     \item{total_enrl}{Crosslist-aware total: each crosslist group's combined
#'       enrollment counted once, plus own enrollment of non-crosslisted
#'       sections. For a cross-course crosslist this includes partner-course
#'       students, so it can exceed \code{enrolled}.}
#'     \item{enrolled}{Total enrollment across all sections (own students only)}
#'     \item{avail}{Total available seats across all sections}
#'     \item{waiting}{Total waitlist count across all sections}
#'   }
#'   Plus all columns specified in group_cols.
#'
#' @details
#' This function replaces many previous aggregation variants by providing a
#' flexible grouping mechanism. Group by course_title to differentiate topics
#' courses that share the same subject_course code.
#'
#' The function uses \code{group_by_at} with dynamic column selection, making
#' it adaptable to different analysis needs (e.g., department-level, course-level,
#' section-level summaries).
#'
#' @examples
#' \dontrun{
#' # Summarize by course across all terms
#' opt <- list(group_cols = c("subject_course", "course_title"))
#' summary <- summarize_courses(cedar_sections, opt)
#'
#' # Summarize by department and term (default grouping)
#' opt <- list(group_cols = NULL)  # Uses default
#' summary <- summarize_courses(cedar_sections, opt)
#' }
#'
#' Course-level total enrollment with each crosslist group counted once
#'
#' Every section row in a crosslist group carries the group's combined
#' enrollment in total_enrl (transform-to-cedar.R sets it to
#' pmax(ENROLLED, XL_TOTAL_ENROLLMENT)). Summing total_enrl over the rows of a
#' group therefore multiply-counts it — once per section. A same-course
#' internal group of 4 sections sharing a combined total of 96 sums to 384
#' (this is what made BIOL 2305 report ~4x its real enrollment).
#'
#' Within one aggregation cell, count each crosslist group's combined total
#' once (max over the group's identical values) and use each non-crosslisted
#' row's own enrollment. Cross-course groups keep their intended semantics:
#' each course's cell contains its own rows of the group, so each course sees
#' the combined total once.
#'
#' @param own Per-row own enrollment, used for rows with no crosslist group.
#' @param group_total Per-row crosslist-combined enrollment (total_enrl).
#' @param xl_key Crosslist group key (e.g. "term|campus|code"); NA for
#'   non-crosslisted rows.
sum_xl_dedup_total <- function(own, group_total, xl_key) {
  is_xl <- !is.na(xl_key)
  total <- sum(own[!is_xl], na.rm = TRUE)
  if (any(is_xl)) {
    group_totals <- tapply(group_total[is_xl], xl_key[is_xl], max, na.rm = TRUE)
    total <- total + sum(group_totals)
  }
  total
}

#' @seealso \code{\link{get_enrl}}, \code{\link{aggregate_courses}}
summarize_courses <- function(courses, opt) {

  # These columns are set by transform-to-cedar.R and preserved through
  # get_enrl()'s select step (crosslist_code gets a "0" placeholder there when
  # absent). If any is missing, the data was not sourced from cedar_sections.
  # Silently substituting (e.g. enrolled for total_enrl) would produce wrong
  # numbers for crosslisted courses with no trace.
  required_cols <- c("total_enrl", "enrolled", "term", "campus", "crosslist_code")
  missing_required <- setdiff(required_cols, names(courses))
  if (length(missing_required) > 0) {
    stop("[enrl.R] summarize_courses: missing required column(s): ",
         paste(missing_required, collapse = ", "),
         ". Data must come from cedar_sections (via get_enrl). ",
         "Columns present: ", paste(sort(names(courses)), collapse = ", "))
  }

  # Crosslist group key for total_enrl dedup: codes are unique within a term,
  # so scope the key by term (and campus for safety). NA marks non-crosslisted
  # rows, which contribute their own enrolled count instead.
  courses <- courses %>%
    ungroup() %>%
    mutate(.xl_key = dplyr::if_else(
      !is.na(crosslist_code) & crosslist_code != "0" & crosslist_code != "",
      paste(term, campus, crosslist_code, sep = "|"),
      NA_character_
    ))

  # set default group_cols
  # group by course_title to differentiate topics courses that use same subject_course
  if (is.null(opt[["group_cols"]])) {
    group_cols <- c("campus", "college", "term", "term_type", "subject", "subject_course", "course_title", "level", "gen_ed_area")
    cedar_debug("[enrl.R] group_cols is null; using default: ", paste(group_cols, collapse = ", "))
  }
  else {
    group_cols <- opt[["group_cols"]]
    group_cols <- convert_param_to_list(group_cols)
    group_cols <- as.character(group_cols)
    cedar_debug("[enrl.R] specified grouping by: ", paste(group_cols, collapse = ", "))
  }

  # Validate that all group_cols exist in the data
  missing_cols <- setdiff(group_cols, colnames(courses))
  if (length(missing_cols) > 0) {
    message("[enrl.R] WARNING: Missing columns in group_cols: ", paste(missing_cols, collapse = ", "))
    message("[enrl.R] Available columns: ", paste(colnames(courses), collapse = ", "))
    group_cols <- intersect(group_cols, colnames(courses))
    message("[enrl.R] Adjusted group_cols to: ", paste(group_cols, collapse = ", "))
  }

  if (length(group_cols) == 0) {
    stop("[enrl.R] ERROR: No valid group_cols after validation. Check column names in data.")
  }

  cedar_debug("[enrl.R] Starting data with ", nrow(courses), " rows...")
  cedar_debug("[enrl.R] summarizing enrollments by: ", paste(group_cols, collapse = ", "))

  summary <- courses %>% ungroup() %>% group_by_at(group_cols) %>%
    summarize(sections=n(),
      xl_sections=sum(crosslist_code != "0" & crosslist_code != "", na.rm=TRUE),
      reg_sections=sum(crosslist_code == "0" | crosslist_code == "" | is.na(crosslist_code)),
      avg_size=round(mean(enrolled, na.rm=TRUE),digits=1),
      # Each crosslist group's combined total counted once — see sum_xl_dedup_total().
      # Computed BEFORE enrolled is reassigned below: summarize() evaluates
      # sequentially, so after `enrolled=sum(...)` the name refers to the scalar.
      total_enrl=sum_xl_dedup_total(enrolled, total_enrl, .xl_key),
      enrolled=sum(enrolled, na.rm=TRUE),
      avail=sum(available, na.rm=TRUE),
      waiting=sum(waitlist_count, na.rm=TRUE),
      .groups="keep")

  cedar_debug("[enrl.R] Summarized to ", nrow(summary), " rows")
  return(summary)
}


#' Aggregate Courses (Wrapper)
#'
#' Wrapper function that validates group_cols parameter and calls summarize_courses().
#' This function ensures that aggregation is only attempted when grouping columns
#' are specified.
#'
#' @param courses Data frame of course sections
#' @param opt Options list. Must contain \code{group_cols} element with column names
#'
#' @return Data frame aggregated by group_cols (see \code{\link{summarize_courses}})
#'
#' @details
#' This is primarily a validation wrapper. It stops execution with an error if
#' group_cols is NULL, ensuring the caller provides explicit grouping instructions.
#'
#' @seealso \code{\link{summarize_courses}} for actual aggregation logic
aggregate_courses <- function(courses, opt) {

  if (!is.null(opt[["group_cols"]])) {
    summary <- summarize_courses(courses,opt)
  }
  else {
    cedar_debug("[enrl.R] ERROR: opt is: ", opt)
    stop("[enrl.R] opt$group_cols is null. Please specify group_cols for aggregation.")
  }

  return(summary)

} # end aggregate_courses



#' Get Enrollment Summary and Plots for Department Report
#'
#' Creates enrollment analysis and visualizations for department reports. Aggregates
#' enrollment data by course, generates top enrollment charts, and produces class size
#' distribution histograms.
#'
#' @param courses Data frame of course sections from cedar_sections table.
#' @param dept_code Character. Department code to analyze (e.g., "ENGL").
#' @param palette Character. ColorBrewer palette name for plots (e.g., "Set2", "Dark2").
#' @param term_start Integer. First term code to include (e.g., 201980). Fall/spring only —
#'   summers are excluded regardless.
#' @param term_end Integer. Last term code to include (e.g., 202480).
#'
#' @return List with structure:
#'   list(
#'     plots  = list(highest_total_enrl_plot, highest_mean_enrl_plot, highest_mean_histo_plot),
#'     tables = list()
#'   )
#'
#' @details
#' This function performs the following steps:
#' \enumerate{
#'   \item Strips summer terms from the sections data
#'   \item Builds opt list with department filter, term range, and default grouping columns
#'   \item Calls \code{get_enrl()} to filter and aggregate enrollment data
#'   \item Identifies top 10 courses by total and average enrollment
#'   \item Creates bar charts for highest enrollment courses
#'   \item Creates histogram of class size distribution by level
#'   \item Converts histogram to interactive plotly widget
#' }
#'
#' Default grouping columns are: subject, subject_course, course_title, level, gen_ed_area
#'
#' Note: AOP (All Online Programs) courses are compressed by default (opt$x = "compress").
#'
#' @examples
#' \dontrun{
#' result <- get_enrl_for_dept_report(cedar_sections, "ENGL", "Set2", 201980, 202480)
#' result$plots$highest_total_enrl_plot
#' }
#'
#' @seealso \code{\link{get_enrl}}, \code{\link{summarize_courses}}
get_enrl_for_dept_report <- function(courses, dept_code, palette, term_start, term_end) {

  # ── Derive a human-readable window label for axis titles ─────────────────────
  # Term codes are YYYYTT; extract the 4-digit year from each end of the window.
  start_yr <- as.integer(substr(as.character(term_start), 1, 4))
  end_yr   <- as.integer(substr(as.character(term_end),   1, 4))
  window_label <- if (start_yr == end_yr) as.character(start_yr) else paste0(start_yr, "–", end_yr)

  # ── Strip summers before any filtering ───────────────────────────────────────
  # Summer term codes end in 60 (e.g., 202060). Enrollment patterns in summer
  # are very different from fall/spring and would skew averages if included.
  courses <- filter_out_summer(courses, "term")

  myopt <- list()
  myopt$dept <- dept_code
  myopt$term <- paste0(term_start, "-", term_end)   # range filter: "201980-202480"
  myopt$group_cols <- c("subject", "subject_course", "course_title", "level", "gen_ed_area")
  myopt$x <- "compress"
  myopt$uel <- TRUE

  cedar_debug("[enrl.R] getting enrollment data via get_enrl (", window_label, ", no summers)...")
  summary_across_terms <- get_enrl(courses, myopt)  # filter, aggregate, etc

  # for inspection, rank by avg size across terms or total enrolled
  highest_total_enrl <- summary_across_terms  %>% ungroup() %>% arrange(desc(enrolled)) %>% slice_head(n=10)
  highest_mean_enrl <- summary_across_terms   %>% ungroup() %>% arrange(desc(avg_size))  %>% slice_head(n=10)

  highest_total_enrl_plot <- plot_ly(
    highest_total_enrl %>% arrange(enrolled) %>%
      mutate(course_title = factor(course_title, levels = unique(course_title))),
    x             = ~enrolled, y = ~course_title,
    type          = "bar", orientation = "h",
    marker        = list(color = "#4e79a7"),
    hovertemplate = "%{y}<br>Total enrollment: %{x}<extra></extra>"
  ) %>% layout(
    xaxis = list(title = paste0("Total Enrollment (", window_label, ")")),
    yaxis = list(title = "")
  )

  highest_mean_enrl_plot <- plot_ly(
    highest_mean_enrl %>% arrange(avg_size) %>%
      mutate(course_title = factor(course_title, levels = unique(course_title))),
    x             = ~avg_size, y = ~course_title,
    type          = "bar", orientation = "h",
    marker        = list(color = "#59a14f"),
    hovertemplate = "%{y}<br>Mean size: %{x:.1f}<extra></extra>"
  ) %>% layout(
    xaxis = list(title = paste0("Mean Section Size (", window_label, ")")),
    yaxis = list(title = "")
  )

  # histogram of avg class sizes
  highest_mean_enrl <- summary_across_terms %>% ungroup() %>% arrange(desc(avg_size))

  highest_mean_histo_plot <- plot_ly(
    highest_mean_enrl,
    x      = ~avg_size, color = ~level,
    colors = palette,
    type   = "histogram", nbinsx = 30,
    hovertemplate = "Avg size: %{x:.1f}<br>Count: %{y}<extra>%{fullData.name}</extra>"
  ) %>% layout(
    barmode = "stack",
    xaxis   = list(title = paste0("Avg section size (", window_label, ")")),
    yaxis   = list(title = "Number of courses"),
    legend  = list(orientation = "h", x = 0, y = -0.2)
  )


  list(
    plots = list(
      highest_total_enrl_plot = highest_total_enrl_plot,
      highest_mean_enrl_plot  = highest_mean_enrl_plot,
      highest_mean_histo_plot = highest_mean_histo_plot
    ),
    tables = list(
      enrl_summary = summary_across_terms  # full summary; rebuild derives top-10 slices and histogram
    )
  )
}


#' Create Enrollment Plot from Class List Data
#'
#' Generates an interactive enrollment visualization from student class list (CL)
#' registration statistics. Creates a faceted bar chart showing enrollment by
#' term and campus, with courses distinguished by color.
#'
#' @param reg_stats_summary Data frame of registration statistics aggregated from
#'   class list data. Expected columns include:
#'   \itemize{
#'     \item \code{term} - Term code
#'     \item \code{registered} - Number of registered students
#'     \item \code{subject_course} - Course identifier (e.g., "ENGL 1110")
#'     \item \code{campus} - Campus location
#'   }
#' @param opt Options list (currently unused but kept for consistency with other
#'   enrollment plotting functions)
#'
#' @return Named list containing one element:
#'   \itemize{
#'     \item \code{cl_enrl} - Interactive plotly bar chart (or NULL if no data)
#'   }
#'
#' @details
#' The function creates a bar chart with:
#' \itemize{
#'   \item X-axis: Term (angled 45 degrees)
#'   \item Y-axis: Student count
#'   \item Fill color: Course (subject_course)
#'   \item Facets: Campus (fixed scales)
#'   \item Interactive hover information via plotly
#'   \item Horizontal legend positioned at bottom
#' }
#'
#' If the input data frame is empty (0 rows), returns NULL for the plot.
#'
#' @examples
#' \dontrun{
#' # After calculating CL enrollment statistics
#' reg_stats <- calc_cl_enrls(students)
#' plots <- make_enrl_plot_from_cls(reg_stats, opt = list())
#' plots$cl_enrl  # Display the interactive plot
#' }
#'
#' @seealso \code{\link{make_enrl_plot}} for enrollment plots from section-level data
make_enrl_plot_from_cls <- function(reg_stats_summary, opt) {

  plots <- list()

  if (nrow(reg_stats_summary) > 0) {
    reg_stats_summary$term <- as.character(reg_stats_summary$term)
    campuses <- unique(reg_stats_summary$campus)

    make_campus_bar <- function(campus_data) {
      plot_ly(
        campus_data,
        x = ~term, y = ~registered,
        color = ~subject_course, type = "bar",
        hovertemplate = "%{x}<br>%{fullData.name}: %{y}<extra></extra>"
      ) %>%
        layout(
          barmode = "stack",
          xaxis   = list(tickangle = 45),
          annotations = list(list(
            text = campus_data$campus[1], showarrow = FALSE,
            xref = "paper", yref = "paper", x = 0.5, y = 1.05, xanchor = "center"
          ))
        )
    }

    if (length(campuses) == 1) {
      plots$cl_enrl <- make_campus_bar(reg_stats_summary) %>%
        layout(legend = list(orientation = "h", x = 0.3, y = -0.3))
    } else {
      panel_list <- lapply(campuses, function(c) {
        make_campus_bar(reg_stats_summary %>% filter(campus == c))
      })
      plots$cl_enrl <- subplot(panel_list, nrows = 1, shareY = TRUE, titleX = TRUE) %>%
        layout(legend = list(orientation = "h", x = 0.3, y = -0.3))
    }
  } else {
    plots$cl_enrl <- NULL
  }

  plots$cl_enrl

  return(plots)
}



#' Create Enrollment Plot from Aggregated Data
#'
#' Generates an interactive line chart showing enrollment trends over time from
#' pre-aggregated enrollment summary data. Creates faceted visualizations with
#' flexible grouping and optional faceting by any categorical field.
#'
#' @param summary Data frame of aggregated enrollment data (output from \code{get_enrl()}).
#'   Must include columns specified in \code{opt$group_cols}, plus \code{enrolled}.
#' @param opt Options list containing:
#'   \itemize{
#'     \item \code{group_cols} - Character vector of grouping columns. MUST include
#'       "term" and at least one other column (required)
#'     \item \code{facet_field} - Optional field to facet by (e.g., "campus", "level")
#'     \item \code{facet_scales} - Facet scale behavior: "fixed", "free", "free_x", "free_y"
#'       (default: "fixed")
#'     \item \code{facet_ncol} - Number of facet columns (default: NULL for auto)
#'   }
#'
#' @return Named list containing one element:
#'   \itemize{
#'     \item \code{enrl} - Interactive plotly line chart (or NULL if invalid data/opts)
#'   }
#'
#' @details
#' This function creates an enrollment trend visualization with the following features:
#' \itemize{
#'   \item Line chart with enrollment over time (term on x-axis)
#'   \item Lines colored/grouped by the first non-term column in group_cols
#'   \item Optional faceting by any categorical field (campus, level, etc.)
#'   \item Interactive plotly widget with hover details
#'   \item Horizontal legend at bottom
#'   \item 45-degree angled x-axis labels
#' }
#'
#' The function performs validation and will return NULL if:
#' \itemize{
#'   \item summary is missing or not a data frame
#'   \item group_cols is NULL
#'   \item group_cols doesn't include "term"
#'   \item group_cols has fewer than 2 elements
#'   \item summary data frame has 0 rows
#' }
#'
#' @examples
#' \dontrun{
#' # Basic enrollment trend by course
#' opt <- list(
#'   term = c("202310", "202320", "202410"),
#'   group_cols = c("term", "subject_course")
#' )
#' summary <- get_enrl(cedar_sections, opt)
#' plots <- make_enrl_plot(summary, opt)
#' plots$enrl
#'
#' # Faceted by campus with free y-axis scales
#' opt$facet_field <- "campus"
#' opt$facet_scales <- "free_y"
#' opt$facet_ncol <- 2
#' plots <- make_enrl_plot(summary, opt)
#' }
#'
#' @seealso \code{\link{get_enrl}}, \code{\link{make_enrl_plot_from_cls}}
make_enrl_plot <- function(summary, opt) {

  # create empty list of plots
  plots <- list()

  # Validate input
  if (missing(summary) || !is.data.frame(summary)) {
    cedar_debug("[enrl.R] Cannot create plot: Invalid summary data.")
    return(NULL)
  }

  cedar_debug("[enrl.R] Data shape: ", nrow(summary), " rows")
  cedar_debug("[enrl.R] Columns: ", paste(colnames(summary), collapse = ", "))

  # Validate group_cols
  group_cols <- opt$group_cols
  if (is.null(group_cols) || !("term" %in% group_cols) || length(group_cols) < 2) {
    cedar_debug("[enrl.R] Cannot create plot: opt$group_cols must include 'term' and at least one other column name.")
    return(NULL)
  }
  # The other grouping column (besides term)
  other_group <- setdiff(group_cols, "term")[1]
  cedar_debug("[enrl.R] Grouping by: ", other_group)

  # Facet settings from opt (optional)
  facet_field <- opt[["facet_field"]]

  # TODO make more dynamic with Shiny inputs
  facet_scales <- "fixed"
  facet_ncol <- NULL

  if (!is.null(facet_field)) {
    cedar_debug("[enrl.R] Faceting enrollment plot by field: ", facet_field)
  }
  if (!is.null(opt[["facet_scales"]])) facet_scales <- opt[["facet_scales"]]
  if (!is.null(opt[["facet_ncol"]])) facet_ncol <- as.integer(opt[["facet_ncol"]])

  cedar_debug("[enrl.R] Creating Enrollment plot...")
  if (nrow(summary) > 0) {
    # Convert term to factor for discrete x-axis
    summary$term <- factor(summary$term, levels = sort(unique(summary$term)), ordered = TRUE)

    plot <- ggplot(summary, aes(x = term, y = enrolled, group = .data[[other_group]], color = .data[[other_group]])) +
      geom_line(stat = "identity") +
      labs(title = "Enrollment by Group", x = "Term", y = "Student Count") +
      theme(axis.text.x = element_text(angle = 45, hjust = 1))

    # apply facet if requested and valid
    if (!is.null(facet_field) && facet_field %in% colnames(summary)) {
      if (is.null(facet_ncol)) {
        plot <- plot + facet_wrap(vars(.data[[facet_field]]), scales = facet_scales)
      } else {
        plot <- plot + facet_wrap(vars(.data[[facet_field]]), scales = facet_scales, ncol = facet_ncol)
      }
      cedar_debug("[enrl.R] Faceting enrollment plot by: ", facet_field, " (scales=", facet_scales, ", ncol=", facet_ncol, ")")
    }

    plots$enrl <- ggplotly(plot) %>% layout(legend = list(orientation = 'h', x = 0.3, y = -.3))
  } else {
    plots$enrl <- NULL
  }

return (plots)
}



#' Get Enrollment Data
#'
#' Main entry point for enrollment analysis. Filters course sections according to
#' specified criteria, handles missing columns gracefully, optionally compresses
#' AOP (All Online Programs) course pairs, and can aggregate data by specified
#' grouping columns.
#'
#' @param courses Data frame of course sections from cedar_sections table.
#'   Must include columns: campus, college, department, term, subject_course, etc.
#' @param opt List of filtering and processing options:
#'   \itemize{
#'     \item \code{dept} - Department code(s) to filter by
#'     \item \code{term} - Term code(s) to filter by
#'     \item \code{campus} - Campus code(s) to filter by
#'     \item \code{status} - Course status (default: "A" for active)
#'     \item \code{uel} - Use exclude list (default: TRUE)
#'     \item \code{aop} - AOP compression mode ("compress" to compress paired sections)
#'     \item \code{group_cols} - Vector of column names to group by for aggregation
#'   }
#'
#' @return Data frame of enrollment data. If \code{opt$group_cols} is specified,
#'   returns aggregated summary with columns: sections, xl_sections, reg_sections,
#'   avg_size, enrolled, avail, waiting. Otherwise returns section-level data
#'   with columns dynamically selected based on availability.
#'
#' @details
#' The function performs the following steps:
#' \enumerate{
#'   \item Validates options and sets defaults (status = "A", uel = TRUE)
#'   \item Filters courses using \code{filter_DESRs()} with provided options
#'   \item Dynamically selects columns that exist in the data
#'   \item Computes derived columns if source columns exist:
#'     \itemize{
#'       \item \code{available} = capacity - enrolled
#'       \item \code{total_enrl} = copy of enrolled (if crosslist data missing)
#'     }
#'   \item Optionally compresses AOP course pairs into single rows
#'   \item Removes duplicate rows and sorts consistently
#'   \item Optionally aggregates by \code{group_cols} using \code{summarize_courses()}
#' }
#'
#' Missing columns are handled gracefully - the function will compute derived
#' columns when possible or create placeholders to ensure downstream code works.
#'
#' @examples
#' \dontrun{
#' # Get section-level enrollment for a department
#' opt <- list(dept = "HIST", term = "202510", status = "A")
#' enrl_data <- get_enrl(cedar_sections, opt)
#'
#' # Get aggregated enrollment by course
#' opt <- list(
#'   dept = "HIST",
#'   group_cols = c("campus", "subject_course", "course_title", "term")
#' )
#' summary_data <- get_enrl(cedar_sections, opt)
#'
#' # Compress AOP course pairs
#' opt <- list(dept = "BIOL", aop = "compress")
#' compressed_data <- get_enrl(cedar_sections, opt)
#' }
#'
#' @seealso
#' \code{\link{filter_DESRs}} for filtering options,
#' \code{\link{summarize_courses}} for aggregation,
#' \code{\link{compress_aop_pairs}} for AOP compression
#'
#' @export
get_enrl <- function(courses, opt) {

# check for old aggregate flag until totally phased out
  agg_by <- opt$aggregate
  if (!is.null(agg_by)) {
    stop("[enrl.R] ERROR: old aggregate param detected: ", agg_by)
  }

  # default status to A for active courses
  if (is.null(opt$status)) {
    cedar_debug("[enrl.R] setting default status to A (active courses only.)")
    opt$status <- "A"
  }

  # default to use exclude list
  if (is.null(opt$uel)) {
    cedar_debug("[enrl.R] setting default to use exclude list (uel=TRUE).")
    opt$uel <- TRUE
  }

  # filter courses according to options
  cedar_debug("[enrl.R] filtering courses (via filter_DESRs) according to options...")
  courses <- filter_DESRs(courses, opt)

  # Combined courses (C-suffix like BIOL 2110C) have multiple CRNs per subject_course,
  # one per lab section. Three data patterns exist:
  #
  # Pattern A — non-crosslisted, XL_ENRL present (total_enrl > enrolled):
  #   Banner stores the course-level total in XL_ENRL on every lab CRN, so
  #   total_enrl (= pmax(ENROLLED, XL_ENRL)) is the course total (~89) while
  #   enrolled is just the per-lab count (~22). Without correction, the crosslist
  #   "home" filter does NOT collapse non-crosslisted C courses, so all lab rows
  #   survive and the correction sets every row to enrolled=89. Downstream
  #   summarize_courses() would then sum them: 4 × 89 = 356 (overcounting).
  #   Fix: correct enrolled → total_enrl, then dedup to one row per course.
  #
  # Pattern B — non-crosslisted, XL_ENRL absent (total_enrl == enrolled):
  #   Each lab row carries its own per-section count with no shared XL total.
  #   The natural sum across lab rows (22+22+23+22=89) is already correct.
  #   The correction is a no-op here, but a dedup would discard all but one
  #   lab section's count, causing severe undercounting (shows 22 instead of 89).
  #   Fix: do NOT dedup these courses.
  #
  # Pattern C — internal crosslist (crosslist_role == "internal"):
  #   Multiple internal crosslist groups (e.g., BIOL 300C groups "5Z" and "H";
  #   also non-combined courses like BIOL 2305 with several multi-CRN groups).
  #   The home filter keeps ALL internal rows, and sum(enrolled) within each group
  #   equals total_enrl for that group. The natural sum of enrolled is correct.
  #   Individual rows have total_enrl > enrolled (total_enrl is the group total, not
  #   the row's per-section count), which would falsely trigger the Pattern A tag.
  #   Fix (section level): exclude internal-crosslist rows from Pattern A detection.
  #   Fix (aggregation): summarize_courses() counts each crosslist group's
  #   total_enrl once per cell (sum_xl_dedup_total), so no normalization is
  #   needed here. A naive sum would overcount: 4 rows × group_total.
  #
  # Distinguishing A from B: among non-internal rows, check whether total_enrl > enrolled
  # on any row in the course group (before correction).
  if ("is_combined" %in% colnames(courses) &&
      !is.null(opt$crosslist) && opt$crosslist == "home" &&
      any(courses$is_combined, na.rm = TRUE)) {

    dedup_cols <- intersect(c("campus", "term", "subject_course"), colnames(courses))

    # Determine eligibility: combined rows that are NOT internal crosslists.
    # Internal crosslists (crosslist_role == "internal") are kept in full by the home
    # filter and their per-section enrolled values already sum to the correct total.
    has_role_col <- "crosslist_role" %in% colnames(courses)
    if (has_role_col) {
      courses <- courses %>%
        dplyr::mutate(
          .xl_eligible = is_combined & (is.na(crosslist_role) | crosslist_role != "internal")
        )
    } else {
      courses <- courses %>%
        dplyr::mutate(.xl_eligible = is_combined)
    }

    # Tag Pattern A rows: eligible combined rows where any group member has total_enrl > enrolled.
    # Must be computed BEFORE the correction (after which enrolled == total_enrl everywhere).
    courses <- courses %>%
      dplyr::group_by(dplyr::across(dplyr::all_of(dedup_cols))) %>%
      dplyr::mutate(
        .xl_combined = .xl_eligible & any(.xl_eligible & total_enrl > enrolled, na.rm = TRUE)
      ) %>%
      dplyr::ungroup()

    n_to_fix <- sum(courses$.xl_combined & courses$enrolled != courses$total_enrl, na.rm = TRUE)
    if (n_to_fix > 0) {
      message("[enrl.R] Correcting enrolled → total_enrl for ", n_to_fix,
              " combined-course rows (Pattern A: XL_ENRL present)")
    }

    # Apply correction only to Pattern A rows.
    courses <- courses %>%
      dplyr::mutate(enrolled = dplyr::if_else(.xl_combined, total_enrl, enrolled))

    # Dedup Pattern A combined courses to one row per (campus, term, subject_course).
    # Pattern B and C rows are untouched — their enrolled values sum correctly.
    n_before <- nrow(courses)
    courses <- courses %>%
      dplyr::group_by(dplyr::across(dplyr::all_of(dedup_cols))) %>%
      dplyr::filter(!.xl_combined | dplyr::row_number() == 1) %>%
      dplyr::ungroup()
    n_deduped <- n_before - nrow(courses)
    if (n_deduped > 0) {
      message("[enrl.R] Deduplicated ", n_deduped,
              " Pattern A combined-course lab rows (kept 1 per campus/term/course)")
    }

    courses <- courses %>% dplyr::select(-.xl_combined, -.xl_eligible)
  }

  # define standard columns to keep
  # Build list dynamically based on what exists in the data
  desired_cols <- c("campus", "college", "department", "term", "term_type", "crn", "subject", "subject_course", "section", "level", "course_title", "delivery_method", "instructor_name", "job_cat", "enrolled", "total_enrl", "crosslist_role", "crosslist_external", "crosslist_subject", "crosslist_code", "crosslist_partners", "is_split", "split_sections", "is_combined", "available", "waitlist_count", "gen_ed_area", "part_term")

  # Only keep columns that actually exist in the data
  select_cols <- desired_cols[desired_cols %in% colnames(courses)]

  # Compute missing derived columns if possible
  if (!"available" %in% colnames(courses) && all(c("capacity", "enrolled") %in% colnames(courses))) {
    cedar_debug("[enrl.R] Computing 'available' from capacity - enrolled...")
    courses <- courses %>% mutate(available = capacity - enrolled)
    select_cols <- c(select_cols, "available")
  }

  # If total_enrl doesn't exist, use enrolled as fallback
  if (!"total_enrl" %in% colnames(courses) && "enrolled" %in% colnames(courses)) {
    cedar_debug("[enrl.R] Computing 'total_enrl' as copy of enrolled (no crosslist data)...")
    courses <- courses %>% mutate(total_enrl = enrolled)
    select_cols <- c(select_cols, "total_enrl")
  }

  # If crosslist columns don't exist, create placeholder columns
  if (!"crosslist_code" %in% colnames(courses)) {
    cedar_debug("[enrl.R] Adding placeholder 'crosslist_code' column (no crosslist data)...")
    courses <- courses %>% mutate(crosslist_code = "0")
    select_cols <- c(select_cols, "crosslist_code")
  }

  if (!"crosslist_subject" %in% colnames(courses)) {
    cedar_debug("[enrl.R] Adding placeholder 'crosslist_subject' column (no crosslist data)...")
    courses <- courses %>% mutate(crosslist_subject = "")
    select_cols <- c(select_cols, "crosslist_subject")
  }

  cedar_debug("[enrl.R] selecting columns: ", paste(select_cols, collapse = ", "))

  ### AOP COMPRESSION
  if (!is.null(opt$aop) && opt$aop == "compress") {
    cedar_debug("[enrl.R] compressing AOP pairs...")
    courses <- compress_aop_pairs(courses,opt)
    select_cols <- c(select_cols, "sect_enrl","pair_enrl")
    courses <- courses %>% select(all_of(select_cols))
  }
  else {
    cedar_debug("[enrl.R] leaving AOP pairs alone...")
    courses <- courses %>% select(all_of(select_cols))
  }

  # courses get listed multiple times b/c of crosslisting (inc aop, but also in general)
  # also, a course can also be listed multiple times depending on the lecture/recitation model (b/c of XL_CRSE column)

  # remove dupes since we have final columns
  # Build arrange columns dynamically based on what exists
  # campus + college are the primary grouping; detail cols follow the crosslist sort
  group_arrange_cols <- c("campus", "college")
  detail_arrange_cols <- c("subject_course", "course_title", "term_type")
  if ("pt" %in% colnames(courses)) {
    detail_arrange_cols <- c(detail_arrange_cols, "pt")
  }
  detail_arrange_cols <- c(detail_arrange_cols, "delivery_method", "instructor_name")

  courses <- courses %>% distinct()

  if ("crosslist_role" %in% colnames(courses)) {
    # Partner crosslists sort to the bottom within each campus/college grouping
    courses <- courses %>%
      arrange(
        across(all_of(group_arrange_cols)),
        coalesce(crosslist_role == "partner", FALSE),
        across(all_of(detail_arrange_cols))
      )
  } else {
    courses <- courses %>%
      arrange(across(all_of(c(group_arrange_cols, detail_arrange_cols))))
  }

  # NOTE on aggregated total_enrl: section rows in a crosslist group each carry
  # the group's combined total, so summing them would multiply-count the group.
  # summarize_courses() handles this by counting each crosslist group's total
  # once per aggregation cell (sum_xl_dedup_total) — no per-row normalization is
  # needed here, and section-level callers (e.g. get_low_enrollment_courses)
  # still see the raw per-row group totals they depend on.

  # check if aggregating
  if(!is.null(opt$aggregate) || !is.null(opt$group_cols)) {
    courses <- aggregate_courses(courses, opt)
  } else {
    cedar_debug("[enrl.R] No aggregating!")
  }

  cedar_debug("[enrl.R] get_enrl returning ", nrow(courses), " rows.")
  return(courses)

} # end get_enrl function


###################################
# LOW ENROLLMENT DASHBOARD FUNCTIONS
###################################

#' Get courses below enrollment threshold
#'
#' Identifies courses with enrollment below a specified threshold, grouped by
#' campus, department, course title, and instructional method.
#'
#' @param courses Data frame of course sections (DESRs)
#' @param opt Options list with filtering parameters
#' @param threshold Numeric enrollment threshold (default 15)
#'
#' @return Data frame of low-enrollment courses with enrollment history
#' Count active sections and total enrollment per course
#'
#' Aggregates cedar_sections to one row per (term, subject_course, course_title,
#' campus), counting active home sections and summing total enrollment. Crosslist
#' partner rows and cancelled sections are excluded so each course is counted once.
#'
#' Designed to be reusable across any tab or report that needs "how many sections
#' is this course running and how many students are enrolled" — low-enrollment
#' alerts, dashboard summaries, comparison views, etc. Join the result back to a
#' course-level table on (term, subject_course, course_title, campus).
#'
#' @param sections Data frame of course sections (cedar_sections).
#'   Must include: status, crosslist_group, crosslist_primary, term,
#'   subject_course, course_title, campus, total_enrl.
#'
#' @return Data frame with columns:
#'   \itemize{
#'     \item \code{term} — term code
#'     \item \code{subject_course} — e.g. "HIST 1110"
#'     \item \code{course_title} — full course title (needed to distinguish topics courses)
#'     \item \code{campus} — campus code
#'     \item \code{n_sections} — count of active home sections
#'     \item \code{course_enrl} — sum of total_enrl across those sections
#'   }
#'
#' @examples
#' counts <- get_course_section_counts(cedar_sections)
#' low_enrl <- low_enrl %>%
#'   left_join(counts, by = c("term", "subject_course", "course_title", "campus")) %>%
#'   mutate(n_sections = coalesce(n_sections, 1L),
#'          course_enrl = coalesce(course_enrl, total_enrl))
get_course_section_counts <- function(sections) {
  sections %>%
    filter(status == "A") %>%
    filter(is.na(crosslist_group) | crosslist_role %in% c("home", "internal")) %>%
    # Rows in a crosslist group each carry the group's combined total_enrl, so
    # count each group once (multi-CRN internal groups like BIOL 2305 would
    # otherwise be multiply-counted). Non-crosslisted rows: total_enrl equals
    # the row's own enrollment.
    mutate(.xl_key = dplyr::if_else(
      !is.na(crosslist_group) & crosslist_group != "" & crosslist_group != "0",
      paste(term, campus, crosslist_group, sep = "|"),
      NA_character_
    )) %>%
    group_by(term, subject_course, course_title, campus) %>%
    summarize(
      n_sections  = n(),
      course_enrl = sum_xl_dedup_total(total_enrl, total_enrl, .xl_key),
      .groups = "drop"
    )
}


get_low_enrollment_courses <- function(courses, opt, threshold = 15, level_filter = NULL) {
  cedar_debug("[enrl.R] Getting low enrollment courses (threshold: ", threshold, ")...")

  # Apply level filter if specified (e.g., "lower", "upper", "split", "grad")
  if (!is.null(level_filter)) {
    cedar_debug("[enrl.R] Applying level filter: ", paste(level_filter, collapse = ", "))
    opt$level <- level_filter
  }

  opt$status <- "A"
  opt$uel <- TRUE

  # HOME leaves one row per all cross-dept xled sections in courses data
  # it's in the "home" dept and with total_enrl as sum of xlisted sections (OR XL_ENRL)
  # we want to filter out non-home xl'ed courses since enrollments tend to be quite small
  opt[["crosslist"]] <- "home"

  # filter courses
  # since we care about low enrolled sections--not aggregates--don't summarize (ie don't call get_enrl).
  filtered_courses <- filter_DESRs(courses, opt)

  # Filter per-section: each CRN is evaluated on its own enrolled count, not the
  # XL group total. total_enrl for split-level or crosslisted groups is the combined
  # enrollment across all partner sections, so using it here would hide individual
  # sections that are below threshold on their own.
  low_enrl <- filtered_courses %>%
    filter(enrolled <= threshold) %>%
    arrange(campus, department, course_title, enrolled)

  cedar_debug("[enrl.R] Found ", nrow(low_enrl), " low enrollment courses below threshold.")
  return(low_enrl)
}



#' Drop shell / placeholder sections
#'
#' Shell sections are active rows with zero enrollment and no instructor assigned —
#' scheduling placeholders left in the schedule build, not real offerings. They must
#' be removed before building enrollment history so a placeholder term is not counted
#' as a real zero-enrollment offering. Cancelled sections are intentionally kept:
#' they carry a meaningful "C" in the history string.
#'
#' @param sections Section rows; must include \code{status}, \code{total_enrl},
#'   \code{instructor_name}.
#' @return \code{sections} with shell rows removed.
#' @seealso \code{NO_INSTRUCTOR_NAMES} in \code{R/lists/status_codes.R}
drop_shell_sections <- function(sections) {
  sections %>%
    filter(!(status == "A" & total_enrl == 0 &
             (is.na(instructor_name) | instructor_name %in% NO_INSTRUCTOR_NAMES)))
}

#' Per-term active-enrollment series for a course (or course group)
#'
#' Collapses section rows to one row per group×term, recording whether the term had
#' any active section (\code{has_active}) and the active-only enrollment total
#' (\code{term_enrl} = sum of \code{total_enrl} over status "A" rows). Optionally
#' keeps only the most recent \code{n_terms} per group, returned oldest→newest.
#'
#' This is the shared history spine behind \code{\link{get_course_enrollment_history}}
#' (a single pre-filtered course, \code{keys = character(0)}) and
#' \code{\link{get_enrollment_concerns}} (many courses at once, keyed by
#' \code{subject_course}, \code{course_title}, \code{campus}).
#'
#' @param sections Section rows pre-filtered to the desired scope (campus, course,
#'   crosslist home, shell sections dropped). Must include \code{status},
#'   \code{total_enrl}, \code{term}, and every column named in \code{keys}.
#' @param keys Grouping columns identifying a course. Empty (default) groups by term
#'   only, for a single already-filtered course.
#' @param n_terms Keep only the most recent \code{n_terms} per group; \code{NULL}
#'   keeps every term.
#' @return One row per group×term with \code{has_active} and \code{term_enrl},
#'   ordered oldest→newest within each group.
summarize_term_enrl_series <- function(sections, keys = character(0), n_terms = NULL) {
  series <- sections %>%
    group_by(across(all_of(c(keys, "term")))) %>%
    summarize(
      has_active = any(status == "A"),
      term_enrl  = sum(total_enrl[status == "A"], na.rm = TRUE),
      .groups = "drop"
    )

  # Single course: no per-group keys, so slice/order over the whole series.
  if (length(keys) == 0) {
    if (!is.null(n_terms)) series <- series %>% arrange(desc(term)) %>% slice_head(n = n_terms)
    return(series %>% arrange(term))
  }

  # Course group: slice and order within each course.
  series <- series %>% group_by(across(all_of(keys)))
  if (!is.null(n_terms)) {
    series <- series %>% arrange(desc(term), .by_group = TRUE) %>% slice_head(n = n_terms)
  }
  series %>% arrange(term, .by_group = TRUE) %>% ungroup()
}

#' Format an enrollment history series as display text
#'
#' Renders a term-by-term series as \code{"Fa22: 12 → Sp23: C → Fa23: 10"}: the
#' active enrollment for each term, and "C" for terms with no active section.
#' Shared by \code{\link{get_enrollment_concerns}} and
#' \code{\link{format_enrollment_history}} so every history string reads the same.
#'
#' @param term Term codes (vector), ordered oldest→newest.
#' @param enrl Active enrollment per term (vector, parallel to \code{term}).
#' @param has_active Logical per term: did the term have an active section? \code{NULL}
#'   treats every term as active (no cancelled "C" markers).
#' @return A single string; \code{"No history"} when \code{term} is empty.
format_term_history <- function(term, enrl, has_active = NULL) {
  if (length(term) == 0) return("No history")
  if (is.null(has_active)) has_active <- rep(TRUE, length(term))
  labels <- ifelse(has_active,
                   paste0(abbr_term(term), ": ", enrl),
                   paste0(abbr_term(term), ": C"))
  paste(labels, collapse = " → ")
}

#' Get enrollment concerns for a future term
#'
#' Analyzes a future term's scheduled courses against historical enrollment
#' patterns from prior terms of the same type (fall/spring/summer). Returns
#' each scheduled course with its historical average enrollment, trend, and
#' history text for display in the concerns tab.
#'
#' @param courses Data frame of course sections (cedar_sections)
#' @param opt Options list with filters (term, course_campus, dept, etc.)
#' @param n_history_terms Number of prior same-type terms to average (default 4)
#'
#' @return Data frame with schedule + historical stats per course
get_enrollment_concerns <- function(courses, opt, n_history_terms = 4) {
  future_term <- opt$term
  cedar_debug("[enrl.R] Getting enrollment concerns for future term: ", future_term)

  # 1. Get scheduled courses for the future term
  opt$status <- "A"
  opt$uel <- TRUE
  opt[["crosslist"]] <- "home"
  scheduled <- filter_DESRs(courses, opt)

  if (nrow(scheduled) == 0) {
    cedar_debug("[enrl.R] No courses scheduled for future term.")
    return(NULL)
  }

  # 2. Aggregate to course-level per campus (one row per subject_course + course_title + campus).
  #    Include course_title to differentiate topics courses with same subject_course.
  #    Take the first value of descriptive columns; sum enrollment and count sections.
  scheduled_courses <- scheduled %>%
    group_by(subject_course, course_title, campus) %>%
    summarize(
      level = first(level),
      is_split = any(is_split),
      department = first(department),
      split_sections = if ("split_sections" %in% names(.)) first(na.omit(split_sections)) else NA_character_,
      n_sections = n(),
      current_enrl = sum(total_enrl, na.rm = TRUE),
      .groups = "drop"
    )

  cedar_debug("[enrl.R] Found ", nrow(scheduled_courses), " unique courses on future schedule.")

  # 3. Determine term type for historical matching
  term_type <- get_term_type(future_term)
  cedar_debug("[enrl.R] Matching against historical '", term_type, "' terms.")

  # 4. Pull historical data: same term_type, home sections, ALL statuses.
  #    Including cancelled sections lets the history show when a course was
  #    scheduled but later cancelled (displayed as "C" in history text).
  #    Shell sections (active, 0 enrollment, unstaffed) are dropped — they are
  #    placeholders left in the schedule build, not real offerings.
  hist_data <- courses %>%
    filter(
      is.na(crosslist_group) | crosslist_role %in% c("home", "internal"),
      term_type == !!term_type,
      term != as.integer(future_term)
    ) %>%
    drop_shell_sections()

  # 5+6. Aggregate to a course-level per-term enrollment series, keyed by
  #      subject_course + course_title + campus (course_title differentiates topics
  #      courses), keeping the most recent n_history_terms per course.
  hist_recent <- summarize_term_enrl_series(
    hist_data,
    keys    = c("subject_course", "course_title", "campus"),
    n_terms = n_history_terms
  )

  # 7. Compute averages (active terms only), trend, and history text.
  #    Cancelled terms appear in history_text as "C" but don't affect avg/trend.
  hist_stats <- hist_recent %>%
    group_by(subject_course, course_title, campus) %>%
    summarize(
      avg_enrl = {
        active_enrl <- term_enrl[has_active]
        if (length(active_enrl) > 0) round(mean(active_enrl, na.rm = TRUE), 1) else NA_real_
      },
      n_prior_terms = sum(has_active),
      n_cancelled = sum(!has_active),
      min_enrl = if (any(has_active)) min(term_enrl[has_active], na.rm = TRUE) else NA_real_,
      max_enrl = if (any(has_active)) max(term_enrl[has_active], na.rm = TRUE) else NA_real_,
      trend_slope = {
        active_enrl <- term_enrl[has_active]
        if (length(active_enrl) >= 2) {
          coef(lm(active_enrl ~ seq_along(active_enrl)))[2]
        } else {
          NA_real_
        }
      },
      history_text = format_term_history(term, term_enrl, has_active),
      .groups = "drop"
    )

  # 8. Compute trend direction label
  hist_stats <- hist_stats %>%
    mutate(
      trend = case_when(
        is.na(trend_slope)  ~ "—",
        trend_slope > 1     ~ "↑ up",
        trend_slope < -1    ~ "↓ down",
        TRUE                ~ "↔ stable"
      )
    )

  # 9. Join scheduled courses with historical stats
  result <- scheduled_courses %>%
    left_join(hist_stats, by = c("subject_course", "course_title", "campus")) %>%
    mutate(
      avg_enrl = coalesce(avg_enrl, NA_real_),
      n_prior_terms = coalesce(n_prior_terms, 0L),
      history_text = coalesce(history_text, "No prior history"),
      trend = coalesce(trend, "—")
    )

  cedar_debug("[enrl.R] Enrollment concerns ready: ", nrow(result), " courses (",
          sum(result$n_prior_terms > 0), " with history, ",
          sum(result$n_prior_terms == 0), " new).")
  return(result)
}


#' Get enrollment history for a specific course
#'
#' Retrieves the last N terms of enrollment data for a specific course offering.
#'
#' @param courses Data frame of course sections (DESRs)
#' @param campus Campus code
#' @param dept Department code
#' @param subj_crse Subject and course number (e.g., "HIST 1105")
#' @param crse_title Course title. For topics courses (Banner "T:" convention) the
#'   history is narrowed to this exact title so each rotating topic keeps its own
#'   trend; ignored for regular courses, whose titles get reworded across terms.
#' @param im Instructional method code
#' @param n_terms Number of historical terms to retrieve (default 3)
#'
#' @return Data frame with TERM and enrolled columns
get_course_enrollment_history <- function(courses, campus, dept, subj_crse, crse_title, im,
                                         n_terms = 4, exclude_term = NULL, max_term = NULL) {
  cedar_debug("[enrl.R] Getting enrollment history for: ", crse_title, " - ", subj_crse)

  # Filter for the specific course. Delivery method is intentionally excluded: it
  # changes across terms (ENH -> blank) without the course changing.
  #
  # course_title is handled by course type. For a topics course (Banner "T:" title
  # convention, the same rule that sets the is_topics column in transform-to-cedar.R)
  # a single subject_course such as HIST 300 is a rotating slot whose title names a
  # different topic each term, so matching on course number alone splices unrelated
  # topics into one history. Narrow those to the shown topic so the trend reflects
  # that topic — a one-off topic then correctly shows "no history" rather than
  # borrowing another topic's numbers. Regular courses keep course-number-only
  # matching: their titles get reworded over time (e.g. ENGL 1110) and title matching
  # would fragment a genuinely continuous history.
  #
  # Include all statuses so cancelled terms appear in history as "C"; drop shell
  # sections (active, 0 enrollment, unstaffed placeholders).
  course_history <- courses %>%
    filter(
      campus == !!campus,
      department == !!dept,
      subject_course == !!subj_crse
    ) %>%
    drop_shell_sections()

  if (isTRUE(grepl("^T:", trimws(crse_title)))) {
    course_history <- course_history %>% filter(course_title == !!crse_title)
  }

  # Exclude current term so history shows only prior terms
  if (!is.null(exclude_term)) {
    course_history <- course_history %>% filter(term != exclude_term)
  }
  # Cap at max_term to exclude future terms
  if (!is.null(max_term)) {
    course_history <- course_history %>% filter(term <= max_term)
  }

  # Deduplicate crosslisted rows: keep primary CRN per XL group + all non-XL rows,
  # then build the recent-terms enrollment series. term_enrl uses total_enrl, so
  # combined C-suffix courses report the correct course-level total rather than a
  # single lab section; renamed to `enrolled` for this function's public contract.
  course_history <- course_history %>%
    filter(is.na(crosslist_group) | crosslist_role %in% c("home", "internal")) %>%
    summarize_term_enrl_series(n_terms = n_terms) %>%
    rename(enrolled = term_enrl)

  cedar_debug("[enrl.R] Found ", nrow(course_history), " historical terms")
  return(course_history)
}


#' Create enrollment history string for display
#'
#' Thin adapter over \code{\link{format_term_history}} for a data frame produced by
#' \code{\link{get_course_enrollment_history}} (columns \code{term}, \code{enrolled},
#' and optionally \code{has_active}).
#'
#' @param history_data Data frame with \code{term} and \code{enrolled} columns, and
#'   optionally \code{has_active}.
#' @return Character string with the enrollment trend (e.g. "Fa22: 12 → Sp23: C").
format_enrollment_history <- function(history_data) {
  has_active <- if ("has_active" %in% names(history_data)) history_data$has_active else NULL
  format_term_history(history_data$term, history_data$enrolled, has_active)
}
