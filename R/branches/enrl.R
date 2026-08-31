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
  # report, dept dashboard, waitlists, demographics) keep one row per course.
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
      )) %>%
      add_classlist_lifecycle_enrl()
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
#' Reconstructed census enrollment is still registered at extract time
#' (\code{registered} — RE/RS/RR) plus late drops (\code{dr_late} — DG/DW).
#' Early drops (DR/DD) are excluded. This uses class-list status counts only;
#' Regstats saturation separately combines DESR enrolled with class-list late
#' drops. Different extract dates can prevent those measures from agreeing.
#' Neither formula recovers a frozen census roster or actual peak occupancy.
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

#' Add the three interpretable class-list lifecycle counts
#'
#' Banner class-list extracts contain one final/current registration status per
#' student-course record, not frozen rosters from three dates. Consequently the
#' outer two columns are explicit proxies:
#' \itemize{
#'   \item \code{first_day_proxy}: everyone ever registered in the extract,
#'     calculated as still registered plus all early and late drops. It can
#'     include pre-term registration churn and is not a literal day-one roster.
#'   \item \code{census_enrl}: still registered plus late drops. Late drops were
#'     present at census; early drops were not.
#'   \item \code{last_day_or_current_enrl}: still registered at extract time.
#'     This is a last-day count for completed terms and a current count for an
#'     active term.
#' }
#'
#' @param df A course-term enrollment table carrying \code{registered},
#'   \code{dr_late}, and \code{dr_all}.
#' @return \code{df} with the three lifecycle columns added.
add_classlist_lifecycle_enrl <- function(df) {
  missing <- setdiff(c("registered", "dr_late", "dr_all"), names(df))
  if (length(missing) > 0) {
    stop(
      "[enrl.R] add_classlist_lifecycle_enrl() needs column(s): ",
      paste(missing, collapse = ", ")
    )
  }

  df %>%
    add_census_enrl() %>%
    mutate(
      first_day_proxy = registered + dplyr::coalesce(dr_all, 0),
      last_day_or_current_enrl = registered
    )
}

#' Calculate reusable census-capacity saturation metrics
#'
#' @param census_enrl Census-point enrollment counts.
#' @param capacity Scheduled seat capacity at the same course-term grain.
#' @param constrained_threshold Fill rate at which enrollment is plausibly
#'   censored by the seat ceiling.
#' @param max_plausible_fill Fill rates above this value indicate unreliable
#'   capacity rather than a defensible ceiling.
#' @return A tibble with census fill, remaining census seats, and capacity
#'   quality/constraint flags.
capacity_saturation_metrics <- function(census_enrl, capacity,
                                        constrained_threshold = 0.90,
                                        max_plausible_fill = 1.25) {
  census_enrl <- as.numeric(census_enrl)
  capacity <- as.numeric(capacity)
  census_fill <- dplyr::if_else(
    is.finite(capacity) & capacity > 0,
    census_enrl / capacity,
    NA_real_
  )
  capacity_usable <- is.finite(census_fill) &
    census_fill <= as.numeric(max_plausible_fill)

  tibble::tibble(
    census_fill = census_fill,
    census_available_seats = dplyr::if_else(
      is.finite(capacity) & capacity > 0 & is.finite(census_enrl),
      pmax(0, capacity - census_enrl),
      NA_real_
    ),
    capacity_usable = capacity_usable,
    capacity_anomaly = is.finite(census_fill) & !capacity_usable,
    capacity_constrained = capacity_usable &
      census_fill >= as.numeric(constrained_threshold)
  )
}

#' Historical census-enrollment baselines per course and term type
#'
#' Summarizes each course's census enrollment (see \code{\link{add_census_enrl}})
#' across its offerings into three things a "typical enrollment" readout needs:
#' \itemize{
#'   \item \code{census_hist} / \code{census_hist_terms} — the census series and
#'     its terms, ordered oldest→newest and including any target term so a
#'     sparkline can mark it in place;
#'   \item \code{census_mean} — mean comparison enrollment;
#'   \item \code{n_hist_terms} — number of comparison terms.
#' }
#' Grouping is same-term-type by default so falls compare to falls; part of term is
#' added to the grouping automatically when the data carries it. Data finer than the
#' grouping (e.g. multiple part-of-term rows when \code{part_term} is not a key) is
#' summed per term first so the series lists one census figure per term.
#'
#' @param df Course-term enrollment rows (e.g. \code{cedar_cl_enrls_base} or a
#'   \code{\link{calc_cl_enrls}} result). Needs \code{registered}, \code{dr_late},
#'   \code{term}, and the grouping keys.
#' @param target_terms With \code{prior_only = TRUE}, select the terms to report
#'   (NULL reports every term). Otherwise, exclude these terms from the all-history
#'   reference mean/count; this legacy mode can include terms later than the target.
#' @param keys Grouping columns; \code{part_term} is appended when present.
#' @param prior_only When TRUE, give each term its own strictly earlier comparison
#'   mean, population SD, and count. The full series remains available for context.
#' @return One row per group (or group/term in prior-only mode) with
#'   \code{census_mean}, \code{n_hist_terms}, and the \code{census_hist} /
#'   \code{census_hist_terms} list-columns. Prior-only mode also returns
#'   \code{census_sd}; fewer than two prior observations gives NA SD. The legacy
#'   reference mean is rounded to one decimal; prior-only statistics retain precision.
#' @seealso \code{\link{add_census_enrl}}
calc_census_enrl_baselines <- function(df, target_terms = NULL,
    keys = c("campus", "college", "subject_course", "term_type"), prior_only = FALSE) {
  df <- add_census_enrl(df)
  if ("part_term" %in% names(df)) keys <- unique(c(keys, "part_term"))
  keys <- intersect(keys, names(df))
  target <- if (length(target_terms) > 0) unique(target_terms) else df$term[0]

  series <- df %>%
    # Collapse to one census figure per group×term first, so callers grouping at a
    # coarser grain than the data (e.g. no part_term) sum cleanly rather than
    # listing duplicate term entries in the series.
    group_by(across(all_of(c(keys, "term")))) %>%
    summarize(census_enrl = sum(census_enrl, na.rm = TRUE), .groups = "drop") %>%
    arrange(term)

  if (isTRUE(prior_only)) {
    history <- series %>% group_by(across(all_of(keys))) %>%
      summarize(census_hist = list(census_enrl), census_hist_terms = list(term),
                .groups = "drop")
    result <- add_prior_history_stats(series, "census_enrl", keys, "term") %>%
      select(all_of(c(keys, "term")), census_mean = census_enrl_hist_mean,
             census_sd = census_enrl_hist_sd, n_hist_terms = census_enrl_hist_n) %>%
      left_join(history, by = keys, relationship = "many-to-one")
    if (length(target_terms) > 0) result <- result %>% filter(term %in% target_terms)
    return(result)
  }

  series %>%
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
#' opt <- list(dept_code = "BIOL", term = "202510")
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
#' # Summarize by course across all terms. Campus is part of the key — see the
#' # CEDAR-wide campus policy in AGENTS.md; a course taught in Albuquerque and at
#' # a branch is two offerings, not one.
#' opt <- list(group_cols = c("campus", "subject_course", "course_title"))
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


enforce_course_campus_grouping <- function(group_cols) {
  if (is.null(group_cols) || length(group_cols) == 0) return(group_cols)

  group_cols <- as.character(convert_param_to_list(group_cols))
  if ("subject_course" %in% group_cols && !"campus" %in% group_cols) {
    group_cols <- c(group_cols, "campus")
  }

  unique(group_cols)
}


.enrollment_crosslist_col <- function(data, lower, display) {
  name <- if (lower %in% names(data)) lower else if (display %in% names(data)) display else NULL
  if (is.null(name)) return(NULL)
  data[[name]]
}


#' Filter Enrollment DESR rows for a crosslist subtab
#'
#' Accepts either the lowercase columns returned by aggregated get_enrl() calls
#' or the display aliases used by section-level results.
#'
#' @param data Enrollment DESR rows.
#' @param view One of home, split, xl-home, away, or all.
#' @return Rows belonging to the requested crosslist view.
filter_enrollment_crosslist_view <- function(data, view = "home") {
  if (is.null(data) || nrow(data) == 0) return(data)

  view <- as.character(view %||% "home")[[1]]
  allowed <- c("home", "split", "xl-home", "away", "all")
  if (!view %in% allowed) {
    stop("[filter_enrollment_crosslist_view] unknown view: ", view)
  }
  if (view == "all") return(data)

  role <- .enrollment_crosslist_col(data, "crosslist_role", "XlistRole")
  external <- .enrollment_crosslist_col(data, "crosslist_external", "XlistExternal")
  primary <- .enrollment_crosslist_col(data, "crosslist_primary", "XlistPrimary")
  is_split <- .enrollment_crosslist_col(data, "is_split", "IsSplit")

  needed <- switch(
    view,
    home = c(role = !is.null(role)),
    split = c(is_split = !is.null(is_split), crosslist_primary = !is.null(primary)),
    `xl-home` = c(crosslist_role = !is.null(role), crosslist_external = !is.null(external)),
    away = c(crosslist_role = !is.null(role), crosslist_external = !is.null(external))
  )
  if (!all(needed)) {
    stop(
      "[filter_enrollment_crosslist_view] ", view,
      " view is missing classification column(s): ",
      paste(names(needed)[!needed], collapse = ", "),
      ". Preserve crosslist fields through aggregation."
    )
  }

  keep <- switch(
    view,
    home = is.na(role) | role %in% c("home", "internal"),
    split = dplyr::coalesce(as.logical(is_split), FALSE) &
      dplyr::coalesce(as.logical(primary), FALSE),
    `xl-home` = role == "home" & dplyr::coalesce(as.logical(external), FALSE),
    away = role == "partner" & dplyr::coalesce(as.logical(external), FALSE)
  )

  data[!is.na(keep) & keep, , drop = FALSE]
}


strip_enrollment_crosslist_metadata <- function(data) {
  if (is.null(data)) return(data)
  data %>% select(-any_of(c(
    "crosslist_role", "crosslist_external", "crosslist_primary", "is_split",
    "XlistRole", "XlistExternal", "XlistPrimary", "IsSplit"
  )))
}



#' Get Enrollment Summary and Plots for Dept Trends
#'
#' Creates enrollment analysis and visualizations for Dept Trends. Aggregates
#' enrollment data by course, generates top enrollment charts, and produces class size
#' distribution histograms.
#'
#' @param courses Data frame of course sections from cedar_sections table.
#' @param dept_code Character. Department code to analyze (e.g., "ENGL").
#' @param palette Character. Brewer palette name or explicit color vector. Use
#'   NULL to inherit the shared CEDAR palette.
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
#' result <- get_enrl_for_dept_report(cedar_sections, "ENGL", NULL, 201980, 202480)
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
  myopt$dept_code <- dept_code
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
    marker        = list(color = unname(CEDAR_COLORS["blue"])),
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
    marker        = list(color = unname(CEDAR_COLORS["green"])),
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
    colors = cedar_plotly_palette(highest_mean_enrl$level, palette, label_order = CEDAR_LEVEL_ORDER),
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




# Topics courses have titles prefixed with "T:"; keep this shared because
# Enrollment trends and dashboard snapshot cards both need the same test.
is_topics_course <- function(course_title) {
  grepl("^T:", trimws(course_title))
}


# Stop loudly if course history was built without campus keys.
.assert_history_has_campus <- function(course_history, caller) {
  required <- c("subject_course", "course_title", "term", "campus")
  missing <- setdiff(required, names(course_history))
  if (length(missing) > 0) {
    stop("[", caller, "] course_history is missing required column(s): ",
         paste(missing, collapse = ", "),
         ". Build it with campus in group_cols; campuses are never merged.")
  }
}


prepare_enrollment_trend_history <- function(course_history) {
  if (is.null(course_history) || nrow(course_history) == 0) return(course_history)
  .assert_history_has_campus(course_history, "prepare_enrollment_trend_history")

  topics_slots <- course_history %>%
    ungroup() %>%
    mutate(.is_topics_course = if ("is_topics" %in% names(.)) coalesce(is_topics, FALSE) else FALSE) %>%
    group_by(subject_course, campus) %>%
    summarize(
      .topics_slot = any(.is_topics_course | is_topics_course(course_title), na.rm = TRUE),
      .groups = "drop"
    )

  history <- course_history %>%
    ungroup() %>%
    mutate(
      .trend_enrolled = if ("total_enrl" %in% names(.)) total_enrl else enrolled
    ) %>%
    left_join(topics_slots, by = c("subject_course", "campus")) %>%
    mutate(
      .course_title_key = if_else(
        coalesce(.topics_slot, FALSE),
        course_title,
        "__regular_course__"
      )
    )

  titles <- history %>%
    filter(!is.na(course_title), nzchar(course_title)) %>%
    arrange(term) %>%
    group_by(subject_course, campus, .course_title_key) %>%
    summarize(course_title = last(course_title), .groups = "drop")

  collapsed <- history %>%
    group_by(subject_course, campus, term, .course_title_key) %>%
    summarize(enrolled = sum(.trend_enrolled, na.rm = TRUE), .groups = "drop") %>%
    left_join(titles, by = c("subject_course", "campus", ".course_title_key"))

  if ("total_enrl" %in% names(history)) {
    totals <- history %>%
      group_by(subject_course, campus, term, .course_title_key) %>%
      summarize(total_enrl = sum(total_enrl, na.rm = TRUE), .groups = "drop")
    collapsed <- collapsed %>%
      left_join(totals, by = c("subject_course", "campus", "term", ".course_title_key"))
  }

  collapsed %>%
    select(subject_course, course_title, campus, term, enrolled, any_of("total_enrl"))
}


resolve_enrollment_trend_term_scope <- function(term_values, current_term = NULL) {
  values <- as.character(term_values %||% character(0))
  values <- values[nzchar(values)]
  exact_terms <- values[grepl("^\\d{6}$", values)]
  term_types <- setdiff(values, exact_terms)

  exact_ints <- suppressWarnings(as.integer(exact_terms))
  exact_ints <- exact_ints[!is.na(exact_ints)]
  selected_max <- if (length(exact_ints) > 0) max(exact_ints) else NULL

  current_int <- suppressWarnings(as.integer(current_term))
  if (length(current_int) == 0 || is.na(current_int)) current_int <- NULL

  max_term <- selected_max
  if (!is.null(current_int)) {
    max_term <- if (is.null(max_term)) current_int else min(max_term, current_int)
  }

  list(
    term_types = if (length(term_types) > 0) term_types else NULL,
    max_term = max_term,
    exact_terms = exact_terms,
    description = if (length(term_types) > 0) {
      paste0("Term type filter retained: ", paste(term_types, collapse = ", "), ".")
    } else {
      "All term types included."
    },
    exact_note = if (length(exact_terms) > 0 && !is.null(max_term)) {
      paste0(" Trend history runs through ", abbr_term(max_term), ".")
    } else if (!is.null(max_term)) {
      paste0(" Trend history capped at ", abbr_term(max_term), ".")
    } else {
      ""
    }
  )
}


filter_enrollment_trend_scope <- function(course_history, term_scope) {
  if (is.null(course_history) || nrow(course_history) == 0) return(course_history)
  if (!is.null(term_scope$max_term) && "term" %in% names(course_history)) {
    course_history <- course_history %>% filter(term <= term_scope$max_term)
  }
  if (!is.null(term_scope$term_types) && "term_type" %in% names(course_history)) {
    course_history <- course_history %>% filter(term_type %in% term_scope$term_types)
  }
  course_history
}


#' Prepare campus-aware enrollment-by-level trend series
#'
#' Collapses enrollment to one point per term, campus, and course level. Campus
#' is a required series key so multi-campus selections cannot be connected into
#' or summarized as a single line.
#'
#' @param level_data Enrollment summary with term, level, campus, and enrolled.
#' @return A data frame ready for the Trend Explorer level chart, or NULL.
prepare_enrollment_level_trend_series <- function(level_data) {
  if (is.null(level_data) || nrow(level_data) == 0) return(NULL)

  required <- c("term", "level", "campus", "enrolled")
  missing <- setdiff(required, names(level_data))
  if (length(missing) > 0) {
    stop("[prepare_enrollment_level_trend_series] missing required column(s): ",
         paste(missing, collapse = ", "))
  }

  plot_data <- level_data %>%
    ungroup() %>%
    filter(!is.na(level), nzchar(as.character(level))) %>%
    mutate(
      campus = if_else(
        is.na(campus) | !nzchar(as.character(campus)),
        "Unknown",
        as.character(campus)
      ),
      term_label = term_code_to_axis_label(term),
      level_label = case_when(
        level == "lower" ~ "Lower Div",
        level == "upper" ~ "Upper Div",
        level == "grad"  ~ "Graduate",
        TRUE             ~ as.character(level)
      )
    ) %>%
    group_by(term, term_label, campus, level, level_label) %>%
    summarize(enrolled = sum(enrolled, na.rm = TRUE), .groups = "drop")

  if (nrow(plot_data) == 0) return(NULL)

  term_order <- plot_data %>%
    distinct(term, term_label) %>%
    arrange(term) %>%
    pull(term_label) %>%
    unique()

  plot_data %>%
    mutate(term_label = factor(term_label, levels = term_order)) %>%
    arrange(campus, level, term)
}


#' Build the Trend Explorer campus-by-level enrollment chart
#'
#' Campus controls line color and level creates separate traces within each
#' campus, making both dimensions visible without joining campuses together.
#'
#' @param level_data Enrollment summary accepted by
#'   `prepare_enrollment_level_trend_series()`.
#' @return A Plotly object, or NULL when there is no usable data.
build_enrollment_level_trend_plot <- function(level_data) {
  plot_data <- prepare_enrollment_level_trend_series(level_data)
  if (is.null(plot_data) || nrow(plot_data) == 0) return(NULL)

  plotly::plot_ly(
    plot_data,
    x = ~term_label,
    y = ~enrolled,
    color = ~campus,
    split = ~level_label,
    colors = cedar_plotly_palette(plot_data$campus),
    type = "scatter",
    mode = "lines+markers",
    hovertemplate = "%{y:,} enrolled<extra>%{fullData.name}</extra>"
  ) %>%
    plotly::layout(
      xaxis = list(title = "", tickangle = -45),
      yaxis = list(title = "Students Enrolled"),
      legend = list(
        title = list(text = "Campus / level"),
        orientation = "h",
        x = 0,
        y = -0.3,
        font = list(size = 10)
      ),
      margin = list(b = 105),
      paper_bgcolor = "rgba(0,0,0,0)",
      plot_bgcolor = "rgba(0,0,0,0)"
    )
}


get_enrollment_momentum <- function(course_history, n_terms = 6, threshold = 1) {
  cedar_debug("[enrl.R] get_enrollment_momentum")

  if (is.null(course_history) || nrow(course_history) == 0) {
    return(list(growing = NULL, investigate = NULL))
  }
  .assert_history_has_campus(course_history, "get_enrollment_momentum")

  course_history <- prepare_enrollment_trend_history(course_history)

  course_trends <- course_history %>%
    group_by(subject_course, course_title, campus) %>%
    arrange(term) %>%
    slice_tail(n = n_terms) %>%
    summarize(
      n_terms = n(),
      avg_enrl = round(mean(enrolled, na.rm = TRUE), 1),
      avg_enrl_early = round(mean(utils::head(enrolled, max(1, floor(n() / 2))),
                                  na.rm = TRUE), 1),
      avg_enrl_recent = round(mean(utils::tail(enrolled, max(1, ceiling(n() / 2))),
                                   na.rm = TRUE), 1),
      trend_slope = compute_trend(enrolled)$slope,
      .groups = "drop"
    ) %>%
    filter(!is.na(trend_slope), n_terms >= 2) %>%
    mutate(
      change_abs = as.integer(round(avg_enrl_recent - avg_enrl_early)),
      change_pct = if_else(
        avg_enrl_early > 0,
        as.integer(round((avg_enrl_recent - avg_enrl_early) / avg_enrl_early * 100)),
        NA_integer_
      ),
      direction = case_when(
        trend_slope > threshold ~ "growing",
        trend_slope < -threshold ~ "investigate",
        TRUE ~ "stable"
      )
    )

  list(
    growing = course_trends %>%
      filter(direction == "growing") %>%
      arrange(desc(change_pct)),
    investigate = course_trends %>%
      filter(direction == "investigate") %>%
      arrange(change_pct)
  )
}


select_enrollment_trend_plot_data <- function(courses, history, n = 5) {
  if (is.null(courses) || nrow(courses) == 0 || is.null(history) || nrow(history) == 0) {
    return(NULL)
  }
  top_keys <- head(courses, n) %>%
    select(subject_course, course_title, campus)

  history %>%
    semi_join(top_keys, by = c("subject_course", "course_title", "campus"))
}


prepare_enrollment_trend_plot_series <- function(courses, history, n = 5) {
  plot_data <- select_enrollment_trend_plot_data(courses, history, n)
  if (is.null(plot_data) || nrow(plot_data) == 0) return(NULL)

  multi_campus <- n_distinct(plot_data$campus) > 1
  plot_data <- plot_data %>%
    mutate(
      term_label = term_code_to_axis_label(term),
      series_key = paste(subject_course, course_title, campus, sep = "\r"),
      series_label = if (multi_campus) {
        paste0(subject_course, " (", campus, "): ", course_title)
      } else {
        paste0(subject_course, ": ", course_title)
      }
    ) %>%
    arrange(term)

  term_order <- plot_data %>%
    distinct(term, term_label) %>%
    arrange(term) %>%
    pull(term_label) %>%
    unique()

  plot_data %>%
    group_by(series_key, series_label, subject_course, course_title, campus, term, term_label) %>%
    summarize(enrolled = sum(enrolled, na.rm = TRUE), .groups = "drop") %>%
    mutate(
      term_label = factor(term_label, levels = term_order),
      trace_name = series_label
    ) %>%
    arrange(series_key, term)
}

#' Compare current-term enrollment to recent same-season averages
#'
#' For each course offered in `current_term`, computes the historical average
#' enrollment across recent prior terms of the same term type and returns above-
#' and below-average rows. Campuses are never merged: ABQ history compares only
#' with ABQ, EA only with EA, and so on.
#'
#' @param course_history Per-campus course enrollment history, one row per
#'   subject_course x course_title x campus x term. Must include `campus`.
#' @param current_term Integer term code.
#' @param n_years Recent years to include in the same-season baseline.
#' @param min_prior_terms Minimum prior same-season offerings required.
#' @return Named list with `above` and `below` data frames.
get_current_enrl_vs_avg <- function(course_history, current_term, n_years = 3,
                                    min_prior_terms = 2) {
  cedar_debug("[enrl.R] get_current_enrl_vs_avg for term ", current_term)

  if (is.null(course_history) || nrow(course_history) == 0) {
    return(list(above = NULL, below = NULL))
  }
  .assert_history_has_campus(course_history, "get_current_enrl_vs_avg")

  current <- course_history %>% filter(term == current_term)
  if (nrow(current) == 0) {
    cedar_debug("[enrl.R] No courses found for current term ", current_term)
    return(list(above = NULL, below = NULL))
  }

  current_season <- current_term %% 100
  window_start <- current_term - (as.integer(n_years) * 100L)

  hist_avg <- course_history %>%
    filter(
      term < current_term,
      term >= window_start,
      term %% 100 == current_season
    ) %>%
    group_by(subject_course, course_title, campus) %>%
    summarize(
      hist_avg_enrl = round(mean(total_enrl, na.rm = TRUE), 1),
      n_hist        = n(),
      hist_terms    = paste(vapply(term, abbr_term, character(1)), collapse = ", "),
      .groups       = "drop"
    ) %>%
    filter(n_hist >= min_prior_terms)

  comparison <- current %>%
    inner_join(hist_avg, by = c("subject_course", "course_title", "campus")) %>%
    mutate(
      diff = as.integer(round(total_enrl - hist_avg_enrl)),
      pct_diff = if_else(
        hist_avg_enrl > 0,
        as.integer(round(diff / hist_avg_enrl * 100)),
        NA_integer_
      ),
      hist_window_label = paste0(n_years, "yr avg")
    ) %>%
    filter(diff != 0)

  list(
    above = comparison %>% filter(diff > 0) %>% arrange(desc(pct_diff)),
    below = comparison %>% filter(diff < 0) %>% arrange(pct_diff)
  )
}

get_course_enrollment_trajectory_signals <- function(course_history, current_term = NULL,
                                                     min_terms = 4L,
                                                     baseline_terms = 2L,
                                                     recent_terms = 2L,
                                                     top_n = 10L) {
  if (is.null(course_history) || nrow(course_history) == 0) {
    return(list(increase = NULL, decrease = NULL, repeated_topics = NULL))
  }
  .assert_history_has_campus(course_history, "get_course_enrollment_trajectory_signals")

  max_term <- suppressWarnings(as.integer(current_term))
  if (length(max_term) == 0 || is.na(max_term)) max_term <- max(course_history$term, na.rm = TRUE)

  history <- prepare_enrollment_trend_history(course_history) %>%
    dplyr::filter(term <= max_term)
  history$.enrl <- if ("total_enrl" %in% names(history)) {
    dplyr::coalesce(as.numeric(history$total_enrl), as.numeric(history$enrolled), 0)
  } else {
    dplyr::coalesce(as.numeric(history$enrolled), 0)
  }
  history$is_topics <- is_topics_course(history$course_title)

  if (nrow(history) == 0) {
    return(list(increase = NULL, decrease = NULL, repeated_topics = NULL))
  }

  recent_history <- compact_enrl_history_str(history, current_term = max_term, max_terms = 5)
  baseline_terms <- max(1L, as.integer(baseline_terms))
  recent_terms <- max(1L, as.integer(recent_terms))
  min_terms <- max(2L, as.integer(min_terms))
  top_n <- max(1L, as.integer(top_n))
  round_half_away <- function(x) as.integer(sign(x) * floor(abs(x) + 0.5))

  trajectories <- history %>%
    dplyr::arrange(term) %>%
    dplyr::group_by(subject_course, course_title, campus) %>%
    dplyr::summarize(
      n_terms = dplyr::n_distinct(term),
      first_term = min(term, na.rm = TRUE),
      last_term = max(term, na.rm = TRUE),
      baseline_avg_enrl = round(mean(utils::head(.enrl, baseline_terms), na.rm = TRUE), 1),
      recent_avg_enrl = round(mean(utils::tail(.enrl, recent_terms), na.rm = TRUE), 1),
      avg_enrl = round(mean(.enrl, na.rm = TRUE), 1),
      max_enrl = max(.enrl, na.rm = TRUE),
      is_topics = any(is_topics, na.rm = TRUE),
      .groups = "drop"
    ) %>%
    dplyr::filter(n_terms >= min_terms) %>%
    dplyr::mutate(
      change_abs = round_half_away(recent_avg_enrl - baseline_avg_enrl),
      change_pct = dplyr::if_else(
        baseline_avg_enrl > 0,
        round_half_away(change_abs / baseline_avg_enrl * 100),
        NA_integer_
      ),
      first_term_label = vapply(first_term, abbr_term, character(1)),
      last_term_label = vapply(last_term, abbr_term, character(1)),
      topics_flag = dplyr::if_else(is_topics, "T", "")
    ) %>%
    dplyr::left_join(recent_history, by = c("subject_course", "course_title", "campus"))

  if (nrow(trajectories) == 0) {
    return(list(increase = NULL, decrease = NULL, repeated_topics = NULL))
  }

  changed_trajectories <- trajectories %>% dplyr::filter(change_abs != 0)

  list(
    increase = changed_trajectories %>%
      dplyr::filter(change_abs > 0) %>%
      dplyr::arrange(dplyr::desc(change_abs), dplyr::desc(change_pct), subject_course) %>%
      dplyr::slice_head(n = top_n),
    decrease = changed_trajectories %>%
      dplyr::filter(change_abs < 0) %>%
      dplyr::arrange(change_abs, change_pct, subject_course) %>%
      dplyr::slice_head(n = top_n),
    repeated_topics = trajectories %>%
      dplyr::filter(is_topics) %>%
      dplyr::arrange(dplyr::desc(n_terms), dplyr::desc(abs(change_abs)), subject_course) %>%
      dplyr::slice_head(n = top_n)
  )
}

compact_enrl_history_str <- function(course_history, current_term, max_terms = 3) {
  if (is.null(course_history) || nrow(course_history) == 0) {
    return(tibble::tibble(
      subject_course = character(),
      course_title = character(),
      campus = character(),
      enrl_history = character()
    ))
  }
  .assert_history_has_campus(course_history, "compact_enrl_history_str")
  enrl_col <- if ("total_enrl" %in% names(course_history)) "total_enrl" else "enrolled"

  course_history %>%
    filter(term <= current_term) %>%
    arrange(desc(term)) %>%
    group_by(subject_course, course_title, campus) %>%
    slice_head(n = max_terms) %>%
    arrange(term, .by_group = TRUE) %>%
    summarize(
      enrl_history = format_term_history(term, .data[[enrl_col]]),
      .groups = "drop"
    )
}

section_metric <- function(df, preferred, fallback = NULL) {
  if (preferred %in% names(df)) {
    as.numeric(df[[preferred]])
  } else if (!is.null(fallback) && fallback %in% names(df)) {
    as.numeric(df[[fallback]])
  } else {
    rep(0, nrow(df))
  }
}

keep_home_sections_compat <- function(sections) {
  if (all(c("crosslist_group", "crosslist_role") %in% names(sections))) {
    keep_home_sections(sections)
  } else if ("crosslist_primary" %in% names(sections)) {
    filter(sections, is.na(crosslist_primary) | crosslist_primary)
  } else {
    sections
  }
}

get_current_course_enrollment_snapshot <- function(sections, dept_code, current_term,
                                                   campus = NULL) {
  if (is.null(sections) || nrow(sections) == 0) return(NULL)

  campus_filter <- if (is.null(campus)) character(0) else as.character(campus)
  campus_filter <- campus_filter[nzchar(campus_filter)]

  current_sections <- sections %>%
    filter(
      department == dept_code,
      term == current_term,
      status == "A"
    )
  if (length(campus_filter) > 0) {
    current_sections <- current_sections %>% filter(campus %in% campus_filter)
  }
  current_sections <- keep_home_sections_compat(current_sections)
  if (nrow(current_sections) == 0) return(NULL)

  current_sections %>%
    mutate(
      .enrl = coalesce(section_metric(., "total_enrl", "enrolled"), 0),
      .capacity = coalesce(section_metric(., "capacity"), 0),
      .waiting = coalesce(section_metric(., "waitlist_count"), 0)
    ) %>%
    group_by(subject_course, course_title, campus) %>%
    summarize(
      n_sections = n(),
      enrolled = sum(.enrl, na.rm = TRUE),
      capacity = sum(.capacity, na.rm = TRUE),
      waiting = sum(.waiting, na.rm = TRUE),
      fill_rate = if_else(capacity > 0, enrolled / capacity, NA_real_),
      .groups = "drop"
    ) %>%
    mutate(fill_pct = if_else(!is.na(fill_rate), round(100 * fill_rate, 0), NA_real_))
}

build_high_waitlist_review <- function(sections, course_history, dept_code, current_term,
                                       campus = NULL, max_history_terms = 3) {
  current_course <- get_current_course_enrollment_snapshot(
    sections, dept_code, current_term, campus = campus
  )
  if (is.null(current_course) || nrow(current_course) == 0) return(NULL)

  history <- compact_enrl_history_str(course_history, current_term, max_terms = max_history_terms)

  high_waitlist <- current_course %>%
    filter(waiting > 0) %>%
    left_join(history, by = c("subject_course", "course_title", "campus")) %>%
    arrange(desc(waiting), desc(enrolled), subject_course)

  if (nrow(high_waitlist) == 0) NULL else high_waitlist
}

get_dept_enrollment_trend_signals <- function(sections, dept_code,
                                              term_start = NULL, term_end = NULL,
                                              current_term = NULL, campus = NULL,
                                              thresholds = NULL,
                                              min_terms = 3L,
                                              persistent_share = 0.70) {
  if (is.null(sections) || nrow(sections) == 0 || is.null(dept_code) || !nzchar(dept_code)) {
    return(list(
      tables = list(
        perennial_low = NULL,
        often_waitlisted = NULL,
        current_above_avg = NULL,
        current_below_avg = NULL,
        largest_enrl_increase = NULL,
        largest_enrl_decrease = NULL,
        repeated_topics_history = NULL
      ),
      current_enrl_vs_avg = list(above = NULL, below = NULL)
    ))
  }

  thresholds <- normalize_low_enrollment_thresholds(thresholds)
  opt <- list(
    dept_code = dept_code,
    status = "A",
    crosslist = "home",
    uel = TRUE,
    group_cols = c("subject_course", "course_title", "campus", "term", "level", "is_split")
  )
  if (!is.null(term_start) && !is.null(term_end)) {
    opt$term <- paste0(term_start, "-", term_end)
  }
  campus_filter <- if (is.null(campus)) character(0) else as.character(campus)
  campus_filter <- campus_filter[nzchar(campus_filter)]
  if (length(campus_filter) > 0) opt$course_campus <- campus_filter

  history <- get_enrl(sections, opt) %>%
    ungroup() %>%
    filter(enrolled > 0)

  if (nrow(history) == 0) {
    return(list(
      tables = list(
        perennial_low = NULL,
        often_waitlisted = NULL,
        current_above_avg = NULL,
        current_below_avg = NULL,
        largest_enrl_increase = NULL,
        largest_enrl_decrease = NULL,
        repeated_topics_history = NULL
      ),
      current_enrl_vs_avg = list(above = NULL, below = NULL)
    ))
  }

  if (!"is_split" %in% names(history)) history$is_split <- FALSE
  if (!"level" %in% names(history)) history$level <- NA_character_
  if (!"waiting" %in% names(history)) history$waiting <- 0
  if (!"total_enrl" %in% names(history)) history$total_enrl <- history$enrolled

  history <- history %>%
    mutate(.threshold = low_enrollment_threshold_for_row(level, is_split, thresholds))

  recent_history <- compact_enrl_history_str(
    history,
    current_term = current_term %||% max(history$term, na.rm = TRUE),
    max_terms = 4
  )

  perennial_low <- history %>%
    group_by(subject_course, course_title, campus, level, is_split) %>%
    summarize(
      n_terms = n_distinct(term),
      low_terms = sum(enrolled <= .threshold, na.rm = TRUE),
      pct_low = round(low_terms / n_terms * 100, 0),
      avg_enrl = round(mean(enrolled, na.rm = TRUE), 1),
      min_enrl = min(enrolled, na.rm = TRUE),
      threshold = max(.threshold, na.rm = TRUE),
      .groups = "drop"
    ) %>%
    filter(n_terms >= min_terms, pct_low >= persistent_share * 100) %>%
    left_join(recent_history, by = c("subject_course", "course_title", "campus")) %>%
    arrange(desc(pct_low), avg_enrl, subject_course)

  often_waitlisted <- history %>%
    group_by(subject_course, course_title, campus) %>%
    summarize(
      n_terms = n_distinct(term),
      waitlist_terms = sum(waiting > 0, na.rm = TRUE),
      pct_waitlisted = round(waitlist_terms / n_terms * 100, 0),
      avg_waiting = round(mean(waiting, na.rm = TRUE), 1),
      max_waiting = max(waiting, na.rm = TRUE),
      .groups = "drop"
    ) %>%
    filter(n_terms >= min_terms, pct_waitlisted >= persistent_share * 100) %>%
    left_join(recent_history, by = c("subject_course", "course_title", "campus")) %>%
    arrange(desc(pct_waitlisted), desc(max_waiting), subject_course)

  current_signals <- if (!is.null(current_term) && current_term %in% history$term) {
    get_current_enrl_vs_avg(history, current_term)
  } else {
    list(above = NULL, below = NULL)
  }
  trajectory_signals <- get_course_enrollment_trajectory_signals(
    history,
    current_term = current_term %||% max(history$term, na.rm = TRUE),
    min_terms = min_terms,
    top_n = 10L
  )

  list(
    tables = list(
      perennial_low = if (nrow(perennial_low) > 0) perennial_low else NULL,
      often_waitlisted = if (nrow(often_waitlisted) > 0) often_waitlisted else NULL,
      current_above_avg = current_signals$above,
      current_below_avg = current_signals$below,
      largest_enrl_increase = trajectory_signals$increase,
      largest_enrl_decrease = trajectory_signals$decrease,
      repeated_topics_history = trajectory_signals$repeated_topics
    ),
    current_enrl_vs_avg = current_signals
  )
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
#'     \item \code{dept_code} - Department code(s) to filter by
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
#' opt <- list(dept_code = "HIST", term = "202510", status = "A")
#' enrl_data <- get_enrl(cedar_sections, opt)
#'
#' # Get aggregated enrollment by course
#' opt <- list(
#'   dept_code = "HIST",
#'   group_cols = c("campus", "subject_course", "course_title", "term")
#' )
#' summary_data <- get_enrl(cedar_sections, opt)
#'
#' # Compress AOP course pairs
#' opt <- list(dept_code = "BIOL", aop = "compress")
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
  desired_cols <- c("campus", "college", "department", "term", "term_type", "crn", "subject", "subject_course", "section", "level", "course_title", "is_topics", "delivery_method", "instructor_name", "job_cat", "enrolled", "total_enrl", "crosslist_role", "crosslist_external", "crosslist_primary", "crosslist_subject", "crosslist_code", "crosslist_partners", "is_split", "split_sections", "is_combined", "available", "waitlist_count", "gen_ed_area", "part_term")

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


#' Add the standard average section-size measure
#'
#' Department and course dashboards use the same definition: crosslist-aware
#' total enrollment divided by the number of active home sections.
#'
#' @param history Enrollment history returned by `get_enrl()` with `sections`
#'   and `total_enrl` columns.
#' @return `history` with `avg_section_size` added.
add_avg_section_size <- function(history) {
  required <- c("sections", "total_enrl")
  missing <- setdiff(required, names(history))
  if (length(missing) > 0) {
    stop("[enrl.R] add_avg_section_size: missing column(s): ",
         paste(missing, collapse = ", "))
  }

  history %>%
    dplyr::mutate(
      avg_section_size = dplyr::if_else(
        sections > 0,
        round(total_enrl / sections, 1),
        NA_real_
      )
    )
}


#' Build reusable section history for one course
#'
#' Uses the canonical DESR enrollment path (`get_enrl()`) and keeps campuses as
#' separate rows. This is the course-level counterpart to the section history
#' used by the department dashboard.
#'
#' @param sections `cedar_sections`.
#' @param opt Standard CEDAR filter options including `course`.
#' @return One row per campus, term, and course with total enrollment, active
#'   section count, and average section size.
get_course_section_history <- function(sections, opt) {
  if (is.null(opt[["course"]]) || length(opt[["course"]]) == 0) {
    stop("[enrl.R] get_course_section_history requires opt$course")
  }

  history_opt <- opt
  history_opt[["term"]] <- NULL
  history_opt[["status"]] <- "A"
  history_opt[["uel"]] <- TRUE
  history_opt[["crosslist"]] <- "home"
  history_opt[["group_cols"]] <- c(
    "campus", "term", "term_type", "subject_course"
  )

  get_enrl(sections, history_opt) %>%
    dplyr::ungroup() %>%
    dplyr::mutate(
      term = suppressWarnings(as.integer(as.character(term))),
      term_type = vapply(term, get_term_type, character(1))
    ) %>%
    add_avg_section_size() %>%
    dplyr::arrange(campus, term)
}


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
    keep_home_sections() %>%
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

  # Filter on the crosslist-aware enrollment total. For standalone sections this
  # matches enrolled; for split-level, crosslisted, and combined sections it
  # reflects the students attached to the full course group.
  low_enrl <- filtered_courses %>%
    mutate(.alert_enrl = coalesce(total_enrl, enrolled)) %>%
    filter(.alert_enrl <= threshold) %>%
    arrange(campus, department, course_title, enrolled)

  cedar_debug("[enrl.R] Found ", nrow(low_enrl), " low enrollment courses below threshold.")
  return(low_enrl)
}


default_low_enrollment_thresholds <- function() {
  c(lower = 12, upper = 12, split = 10, grad = 5)
}

normalize_low_enrollment_thresholds <- function(thresholds = NULL) {
  defaults <- default_low_enrollment_thresholds()
  if (is.null(thresholds)) return(defaults)
  thresholds <- unlist(thresholds, use.names = TRUE)
  if (is.null(names(thresholds)) || any(names(thresholds) == "")) {
    stop("[enrl.R] low enrollment thresholds must be named: lower, upper, split, grad")
  }
  out <- defaults
  shared <- intersect(names(out), names(thresholds))
  out[shared] <- as.numeric(thresholds[shared])
  out
}

low_enrollment_threshold_for_row <- function(level, is_split, thresholds = NULL) {
  thresholds <- normalize_low_enrollment_thresholds(thresholds)
  level <- as.character(level)
  is_split <- dplyr::coalesce(as.logical(is_split), FALSE)
  dplyr::case_when(
    is_split ~ thresholds[["split"]],
    level == "grad" ~ thresholds[["grad"]],
    level == "upper" ~ thresholds[["upper"]],
    TRUE ~ thresholds[["lower"]]
  )
}

low_enrollment_severity <- function(enrolled, threshold, include_buffer = TRUE) {
  dplyr::case_when(
    enrolled < threshold * 0.5  ~ "critical",
    enrolled < threshold * 0.75 ~ "warning",
    enrolled <= threshold       ~ "watch",
    include_buffer              ~ "buffer",
    TRUE                        ~ "buffer"
  )
}

# Shared low-enrollment band filter used by the Enrollment tab's subtabs and
# any dashboard/report surface that needs to mirror those level/split rules.
filter_low_enrollment_level <- function(data, level_val, threshold,
                                        is_split_filter = FALSE,
                                        mode = c("alerts", "concerns")) {
  mode <- match.arg(mode)
  if (is.null(data) || nrow(data) == 0) return(data)

  if (!"is_split" %in% names(data)) data$is_split <- FALSE
  if (!"level" %in% names(data)) data$level <- NA_character_
  if (!".alert_enrl" %in% names(data)) data$.alert_enrl <- data$enrolled

  if (mode == "concerns") {
    if (isTRUE(is_split_filter)) {
      data %>%
        filter(coalesce(is_split, FALSE),
               n_prior_terms == 0 | avg_enrl < threshold + 5)
    } else {
      data %>%
        filter(level == level_val, !coalesce(is_split, FALSE),
               n_prior_terms == 0 | avg_enrl < threshold + 5)
    }
  } else {
    fetch_limit <- ceiling(threshold * 1.25)
    if (isTRUE(is_split_filter)) {
      data %>% filter(coalesce(is_split, FALSE), .alert_enrl <= fetch_limit)
    } else {
      data %>% filter(level == level_val, !coalesce(is_split, FALSE), .alert_enrl <= fetch_limit)
    }
  }
}

# Combine the four Enrollment low-enrollment bands into one review dataset while
# preserving each row's level-specific threshold. This is the common path for
# summaries, downloads, and dashboard sections.
collect_low_enrollment_threshold_rows <- function(data, thresholds = NULL,
                                                  mode = c("alerts", "concerns")) {
  mode <- match.arg(mode)
  thresholds <- normalize_low_enrollment_thresholds(thresholds)
  if (is.null(data) || nrow(data) == 0) return(data)

  bind_rows(
    filter_low_enrollment_level(data, "lower", thresholds[["lower"]], mode = mode) %>%
      mutate(.threshold = thresholds[["lower"]]),
    filter_low_enrollment_level(data, "upper", thresholds[["upper"]], mode = mode) %>%
      mutate(.threshold = thresholds[["upper"]]),
    filter_low_enrollment_level(data, NA, thresholds[["split"]],
                                is_split_filter = TRUE, mode = mode) %>%
      mutate(.threshold = thresholds[["split"]]),
    filter_low_enrollment_level(data, "grad", thresholds[["grad"]], mode = mode) %>%
      mutate(.threshold = thresholds[["grad"]])
  )
}

is_perennial_low_enrollment <- function(history_data, threshold,
                                        min_prior_terms = 3L,
                                        perennial_threshold = 0.70) {
  if (is.null(history_data) || nrow(history_data) == 0) return(FALSE)
  active <- if ("has_active" %in% names(history_data)) history_data$has_active else rep(TRUE, nrow(history_data))
  vals <- history_data$enrolled[active]
  vals <- vals[!is.na(vals)]
  if (length(vals) < min_prior_terms) return(FALSE)
  mean(vals <= threshold) >= perennial_threshold
}

#' Build low-enrollment alert rows for shared tab/dashboard use
#'
#' Wraps `get_low_enrollment_courses()` with the level/split thresholds, course
#' section context, severity coding, and optional prior-history labels used by
#' the Enrollment tab. Callers can keep the tab's 25% buffer rows or request
#' strict threshold-only output for compact dashboard cards.
#' @param min_enrl Minimum section enrollment to include. Defaults to 1 so
#'   active zero-enrollment schedule artifacts stay out of alert tables; pass
#'   0 to inspect them explicitly.
build_low_enrollment_alerts <- function(courses, opt, thresholds = NULL,
                                        include_buffer = TRUE,
                                        min_enrl = 1L,
                                        add_history = TRUE,
                                        history_limit = 500L,
                                        max_term = NULL,
                                        n_history_terms = 4L,
                                        add_perennial = FALSE,
                                        min_prior_terms = 3L,
                                        perennial_threshold = 0.70) {
  thresholds <- normalize_low_enrollment_thresholds(thresholds)
  fetch_multiplier <- if (isTRUE(include_buffer)) 1.25 else 1
  max_threshold <- ceiling(max(thresholds, na.rm = TRUE) * fetch_multiplier)

  all_low <- get_low_enrollment_courses(courses, opt, threshold = max_threshold)
  if (is.null(all_low) || nrow(all_low) == 0) return(NULL)

  if (!"is_split" %in% names(all_low)) all_low$is_split <- FALSE
  if (!"level" %in% names(all_low)) all_low$level <- NA_character_
  if (!"delivery_method" %in% names(all_low)) all_low$delivery_method <- NA_character_

  all_low <- all_low %>%
    mutate(
      .threshold = low_enrollment_threshold_for_row(level, is_split, thresholds),
      .fetch_limit = ceiling(.threshold * fetch_multiplier),
      .alert_enrl = coalesce(.alert_enrl, total_enrl, enrolled)
    ) %>%
    filter(.alert_enrl <= .fetch_limit)

  if (!is.null(min_enrl) && !is.na(min_enrl) && min_enrl > 0) {
    all_low <- all_low %>% filter(enrolled >= as.integer(min_enrl))
  }

  if (nrow(all_low) == 0) return(NULL)

  section_counts <- get_course_section_counts(courses)
  all_low <- all_low %>%
    left_join(section_counts, by = c("term", "subject_course", "course_title", "campus")) %>%
    mutate(
      n_sections  = coalesce(n_sections, 1L),
      course_enrl = coalesce(course_enrl, total_enrl),
      .alert_enrl = coalesce(.alert_enrl, course_enrl, total_enrl, enrolled),
      severity    = low_enrollment_severity(.alert_enrl, .threshold, include_buffer)
    )

  current_term <- max(all_low$term, na.rm = TRUE)
  if (is.null(max_term)) max_term <- current_term

  if (isTRUE(add_history) && nrow(all_low) <= history_limit) {
    cedar_debug("[enrl.R] Adding enrollment history for ", nrow(all_low), " low-enrollment rows...")
    all_low <- all_low %>%
      rowwise() %>%
      mutate(
        history = list(get_course_enrollment_history(
          courses, campus, department, subject_course, course_title, delivery_method,
          n_terms = n_history_terms, exclude_term = current_term, max_term = max_term
        )),
        history_text = format_enrollment_history(history),
        perennial_low = if (isTRUE(add_perennial)) {
          is_perennial_low_enrollment(history, .threshold, min_prior_terms, perennial_threshold)
        } else {
          FALSE
        }
      ) %>%
      ungroup()
  } else {
    all_low$history_text <- NA_character_
    all_low$perennial_low <- FALSE
  }

  all_low
}

# Strict or buffered dashboard-ready low-enrollment review rows. This is a thin
# contract wrapper around build_low_enrollment_alerts(): it keeps the shared
# section/history/perennial calculations and standardizes display columns used
# outside the Enrollment tab.
build_low_enrollment_review <- function(courses, opt, thresholds = NULL,
                                        include_buffer = FALSE,
                                        min_enrl = 1L,
                                        add_history = TRUE,
                                        history_limit = 500L,
                                        max_term = NULL,
                                        n_history_terms = 4L,
                                        add_perennial = FALSE,
                                        min_prior_terms = 3L,
                                        perennial_threshold = 0.70) {
  review <- build_low_enrollment_alerts(
    courses, opt,
    thresholds = thresholds,
    include_buffer = include_buffer,
    min_enrl = min_enrl,
    add_history = add_history,
    history_limit = history_limit,
    max_term = max_term,
    n_history_terms = n_history_terms,
    add_perennial = add_perennial,
    min_prior_terms = min_prior_terms,
    perennial_threshold = perennial_threshold
  )

  if (is.null(review) || nrow(review) == 0) return(NULL)
  if (!"section" %in% names(review)) review$section <- NA_character_

  review %>%
    mutate(
      enrl_history = coalesce(history_text, ""),
      perennial_low = coalesce(perennial_low, FALSE),
      severity_rank = match(severity, c("critical", "warning", "watch", "buffer"))
    ) %>%
    arrange(severity_rank, .alert_enrl, enrolled, subject_course, section) %>%
    select(-severity_rank)
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
#' Renders a term-by-term series as \code{"12, C, 10 (Fa22, Sp23, Fa23)"}:
#' the active enrollment values first for easy scanning, and "C" for terms with
#' no active section.
#' Shared by \code{\link{get_enrollment_concerns}} and
#' \code{\link{format_enrollment_history}} so every history string reads the same.
#' Call this helper instead of building \code{"term: value"} strings inline.
#'
#' @param term Term codes (vector), ordered oldest→newest.
#' @param enrl Active enrollment per term (vector, parallel to \code{term}).
#' @param has_active Logical per term: did the term have an active section? \code{NULL}
#'   treats every term as active (no cancelled "C" markers).
#' @return A single string; \code{"No history"} when \code{term} is empty.
format_term_history <- function(term, enrl, has_active = NULL) {
  if (length(term) == 0) return("No history")
  if (is.null(has_active)) has_active <- rep(TRUE, length(term))
  values <- ifelse(has_active, as.character(enrl), "C")
  terms <- vapply(term, abbr_term, character(1))
  paste0(paste(values, collapse = ", "), " (", paste(terms, collapse = ", "), ")")
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
    keep_home_sections() %>%
    filter(
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
      trend_slope = compute_trend(term_enrl[has_active])$slope,
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

  is_topic_title <- isTRUE(any(grepl("^T:", trimws(course_history$course_title))))
  if ("is_topics" %in% names(course_history)) {
    is_topic_title <- is_topic_title || isTRUE(any(course_history$is_topics %in% TRUE, na.rm = TRUE))
  }

  if (is_topic_title) {
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
    keep_home_sections() %>%
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
#' @return Character string with the enrollment trend (e.g. "12, C (Fa22, Sp23)").
format_enrollment_history <- function(history_data) {
  has_active <- if ("has_active" %in% names(history_data)) history_data$has_active else NULL
  format_term_history(history_data$term, history_data$enrolled, has_active)
}
