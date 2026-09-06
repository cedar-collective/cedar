# course-retention.R — Descriptive retention questions
#
# Three questions, each returning a wide tibble of retention rates:
#
#   get_retention_comparison()  — cross-course matrix for a single anchor term:
#       rows = courses, cols = T+1 to T+N semesters
#   get_retention_trend()       — one course's trend across terms, optionally
#       split by instructor
#   get_dept_retention_trend()  — the same trend at department grain
#
# The shared computation these consume — context, lookups, and the retained_1 ..
# retained_n flags — lives in R/branches/retention-context.R. Reshaping their
# output lives in R/cones/retention-summaries.R.
#
# Campus policy (see AGENTS.md): the *cohort* is campus-scoped — a student who
# took a course at Gallup is not in the Albuquerque cohort — but the retention
# *outcome* is deliberately UNM-wide, because a student who transfers between
# campuses has been retained, not lost. opt$campus restricts the cohort; results
# are always grouped by campus.
#
# Depends on: build_retention_context(), .compute_retention(), .safe_mean()
#             (branches/retention-context.R)

# =============================================================================
# get_retention_comparison
# =============================================================================
#
#' @title Cross-course retention comparison for a single anchor term
#'
#' @description For each course offered in the anchor term, computes the
#'   percentage of students who remain enrolled at UNM (any course) at T+1
#'   through T+n_terms semesters later. Graduates are counted as retained.
#'   Cells where the target term is beyond available data are NA.
#'
#' @param students  cedar_students data frame.
#' @param opt       Named list of options:
#'   \describe{
#'     \item{`term`}{Integer. Anchor term code (required).}
#'     \item{`course`}{Character vector. Restrict to these course codes. Optional.}
#'     \item{`n_terms`}{Integer. How many semesters forward to track. Default: 5.}
#'     \item{`min_n`}{Integer. Suppress rows with fewer students. Default: 10.}
#'     \item{`campus`}{Character vector of campus codes. Restricts the cohort.
#'       NULL includes every campus — pass NULL only for a deliberate UNM-wide
#'       aggregate. Results are grouped by campus either way.}
#'     \item{`data_edges`}{Output of [cedar_data_edges()]. Longitudinal cohorts
#'       and return lookups stop at `last_enrolled_complete`.}
#'   }
#' @param degrees  cedar_degrees data frame. Used to avoid counting graduates
#'   as stop-outs. Optional; pass NULL to skip the correction.
#' @param context Optional value from [build_retention_context()]. Reuse one
#'   context when computing several retention views from the same data and edge.
#'
#' @return Wide tibble: one row per course, columns subject_course, n,
#'   ret_1 .. ret_n (numeric 0–1 or NA).
#'
get_retention_comparison <- function(students, opt = list(), degrees = NULL,
                                     context = NULL) {
  anchor_term <- as.integer(opt[["term"]])
  if (is.na(anchor_term) || length(anchor_term) != 1) {
    stop("[course-retention.R] get_retention_comparison: opt$term must be a single term code.")
  }

  n_terms <- as.integer(opt[["n_terms"]] %||% 5L)
  min_n   <- as.integer(opt[["min_n"]]   %||% 10L)
  context <- .resolve_retention_context(students, degrees, opt, context)
  students <- context$students

  .require_campus(students, "get_retention_comparison")

  message("[course-retention.R] Comparison: anchor=", anchor_term,
          " n_terms=", n_terms, " min_n=", min_n)

  anchor <- students %>%
    filter(
      term == anchor_term,
      registration_status_code %in% STATUS_REGISTERED
    ) %>%
    .filter_campus(opt[["campus"]])

  if (length(opt[["course"]]) > 0) {
    anchor <- anchor %>% filter(subject_course %in% opt[["course"]])
  }

  anchor <- anchor %>%
    distinct(student_id, campus, subject_course) %>%
    mutate(anchor_term = anchor_term)

  if (nrow(anchor) == 0) {
    message("[course-retention.R] No registered students found for anchor term ", anchor_term)
    return(data.frame())
  }

  registered_lookup <- context$registered_lookup
  graduated_lookup  <- context$graduated_lookup

  cohort_with_ret <- .compute_retention(anchor, registered_lookup, n_terms, graduated_lookup)

  ret_cols <- paste0("retained_", seq_len(n_terms))

  result <- cohort_with_ret %>%
    group_by(campus, subject_course) %>%
    summarise(
      n = n(),
      across(all_of(ret_cols), .safe_mean, .names = "rate_{.col}"),
      .groups = "drop"
    ) %>%
    filter(n >= min_n) %>%
    arrange(campus, subject_course)

  for (n in seq_len(n_terms)) {
    old_col <- paste0("rate_retained_", n)
    new_col <- paste0("ret_", n)
    if (old_col %in% names(result)) result <- result %>% rename(!!new_col := !!old_col)
  }

  message("[course-retention.R] Comparison: ", nrow(result), " courses returned.")
  result
}


# =============================================================================
# get_retention_trend
# =============================================================================
#
#' @title Single-course retention trend across starting terms
#'
#' @description For a single course, computes T+1 .. T+n_terms retention for
#'   each term the course was offered. Optionally splits by instructor.
#'   Graduates are counted as retained. Cells where the target term is beyond
#'   available data are NA rather than 0%.
#'
#' @param students  cedar_students data frame.
#' @param opt       Named list of options:
#'   \describe{
#'     \item{`course`}{Character. Single course code (required).}
#'     \item{`by_instructor`}{Logical. Split by instructor. Default: FALSE.}
#'     \item{`n_terms`}{Integer. Semesters forward to track. Default: 5.}
#'     \item{`min_n`}{Integer. Suppress rows with fewer students. Default: 10.}
#'     \item{`campus`}{Character vector of campus codes. Restricts the cohort.
#'       NULL includes every campus — pass NULL only for a deliberate UNM-wide
#'       aggregate. Results are grouped by campus either way.}
#'     \item{`data_edges`}{Output of [cedar_data_edges()]. Longitudinal cohorts
#'       and return lookups stop at `last_enrolled_complete`.}
#'   }
#' @param degrees  cedar_degrees data frame. Used to avoid counting graduates
#'   as stop-outs. Optional; pass NULL to skip the correction.
#' @param context Optional value from [build_retention_context()]. Reuse one
#'   context when computing several retention views from the same data and edge.
#'
#' @return Wide tibble: one row per campus × term (or campus × term ×
#'   instructor), columns campus, term_label, n, ret_1 .. ret_n (numeric 0–1
#'   or NA).
#'
get_retention_trend <- function(students, opt = list(), degrees = NULL,
                                context = NULL) {
  course <- opt[["course"]] %||% ""
  if (!nzchar(course)) {
    stop("[course-retention.R] get_retention_trend: opt$course must be a non-empty course code.")
  }

  n_terms       <- as.integer(opt[["n_terms"]] %||% 5L)
  min_n         <- as.integer(opt[["min_n"]]   %||% 10L)
  by_instructor <- isTRUE(opt[["by_instructor"]])
  context <- .resolve_retention_context(students, degrees, opt, context)
  students <- context$students

  .require_campus(students, "get_retention_trend")

  message("[course-retention.R] Trend: course='", course,
          "' n_terms=", n_terms, " by_instructor=", by_instructor)

  cohort <- students %>%
    filter(
      subject_course == course,
      registration_status_code %in% STATUS_REGISTERED
    ) %>%
    .filter_campus(opt[["campus"]])

  if (by_instructor) {
    if (!"instructor_id" %in% names(cohort)) {
      stop("[course-retention.R] get_retention_trend: by_instructor=TRUE requires instructor_id.")
    }
    if (!"instructor_name" %in% names(cohort)) {
      cohort$instructor_name <- NA_character_
    }
    cohort <- cohort %>%
      mutate(
        instructor_name = if_else(
          !is.na(instructor_name) & nzchar(trimws(instructor_name)) & instructor_name != "NA, NA",
          instructor_name,
          instructor_id
        )
      )
  }

  keep_cols <- c("student_id", "campus", "term",
                 if (by_instructor) c("instructor_id", "instructor_name"))

  cohort <- cohort %>%
    distinct(across(all_of(keep_cols))) %>%
    rename(anchor_term = term)

  if (nrow(cohort) == 0) {
    message("[course-retention.R] No registered students found for course '", course, "'")
    return(data.frame())
  }

  registered_lookup <- context$registered_lookup
  graduated_lookup  <- context$graduated_lookup

  cohort_with_ret <- .compute_retention(cohort, registered_lookup, n_terms, graduated_lookup)

  group_vars <- c("campus", "anchor_term",
                  if (by_instructor) c("instructor_id", "instructor_name"))
  ret_cols   <- paste0("retained_", seq_len(n_terms))

  result <- cohort_with_ret %>%
    group_by(across(all_of(group_vars))) %>%
    summarise(
      n = n(),
      across(all_of(ret_cols), .safe_mean, .names = "rate_{.col}"),
      .groups = "drop"
    ) %>%
    filter(n >= min_n) %>%
    arrange(campus, desc(anchor_term))

  result <- result %>%
    rename(term = anchor_term) %>%
    mutate(term_label = term_code_to_axis_label(term))

  for (n in seq_len(n_terms)) {
    old_col <- paste0("rate_retained_", n)
    new_col <- paste0("ret_", n)
    if (old_col %in% names(result)) result <- result %>% rename(!!new_col := !!old_col)
  }

  message("[course-retention.R] Trend: ", nrow(result), " term rows returned.")
  result
}


# =============================================================================
# get_dept_retention_trend
# =============================================================================
#
#' @title Department- or college-level retention trend across terms
#'
#' @description For all students registered in any course within a given
#'   department (or college), computes T+1 .. T+n_terms retention for each
#'   anchor term. Intended as a benchmark alongside get_retention_trend() for
#'   a specific course — lets you see whether a course's pattern is distinctive
#'   or mirrors the broader department/college trend.
#'
#'   Students are deduplicated per term before computing retention, so a student
#'   enrolled in three courses in the same department counts once per term, not
#'   three times.
#'
#' @param students  cedar_students data frame.
#' @param opt       Named list of options:
#'   \describe{
#'     \item{`dept`}{Character. Department code (e.g. "HIST"). Use dept OR college.}
#'     \item{`college`}{Character. College code (e.g. "AS"). Use dept OR college.}
#'     \item{`level`}{Character. Restrict to courses at this level: "lower", "upper",
#'       or "grad". Pass the level of the target course so the benchmark cohort
#'       contains only students in comparable courses. Optional.}
#'     \item{`terms`}{Integer vector. Restrict to these anchor terms. Optional —
#'       pass the anchor terms from get_retention_trend() to align rows.}
#'     \item{`n_terms`}{Integer. Semesters forward to track. Default: 5.}
#'     \item{`min_n`}{Integer. Suppress rows with fewer students. Default: 10.}
#'     \item{`campus`}{Character vector of campus codes. Pass the same value
#'       used for the course trend so the benchmark is drawn from the same
#'       campuses; otherwise the comparison is against a different institution.}
#'     \item{`data_edges`}{Output of [cedar_data_edges()]. Longitudinal cohorts
#'       and return lookups stop at `last_enrolled_complete`.}
#'   }
#' @param degrees  cedar_degrees data frame. Graduates are not counted as
#'   stop-outs. Optional; pass NULL to skip.
#' @param context Optional value from [build_retention_context()]. Reuse one
#'   context when computing several retention views from the same data and edge.
#'
#' @return Wide tibble: one row per campus × anchor term, columns campus, term,
#'   term_label, n, ret_1 .. ret_n (numeric 0–1 or NA).
#'
get_dept_retention_trend <- function(students, opt = list(), degrees = NULL,
                                     context = NULL) {
  dept_val    <- opt[["dept_code"]]
  college_val <- opt[["college"]]

  if (is.null(dept_val) && is.null(college_val)) {
    stop("[course-retention.R] get_dept_retention_trend: opt$dept_code or opt$college is required.")
  }

  n_terms   <- as.integer(opt[["n_terms"]] %||% 5L)
  min_n     <- as.integer(opt[["min_n"]]   %||% 10L)
  context <- .resolve_retention_context(students, degrees, opt, context)
  students <- context$students
  terms     <- opt[["terms"]]
  level_val <- opt[["level"]]
  # Ignore "unknown" — it means the course number pattern didn't match, so
  # filtering on it would silently exclude valid courses.
  if (!is.null(level_val) && (is.na(level_val) || level_val == "unknown")) level_val <- NULL

  .require_campus(students, "get_dept_retention_trend")

  label <- if (!is.null(dept_val)) paste0("dept=", dept_val) else paste0("college=", college_val)
  if (!is.null(level_val)) label <- paste0(label, " level=", level_val)
  message("[course-retention.R] Benchmark: ", label, " n_terms=", n_terms)

  # Filter by dept or college, then optionally by course level, then deduplicate
  # to one row per student per term so that students enrolled in multiple courses
  # in the same dept/level are not over-counted in the cohort.
  cohort <- students %>%
    filter(registration_status_code %in% STATUS_REGISTERED) %>%
    .filter_campus(opt[["campus"]])

  if (!is.null(dept_val)) {
    cohort <- cohort %>% filter(department == .env$dept_val)
  } else {
    cohort <- cohort %>% filter(college == .env$college_val)
  }

  if (!is.null(level_val)) {
    cohort <- cohort %>% filter(level == .env$level_val)
  }

  # Campus joins the dedup key so the benchmark is per campus, matching the
  # course trend it is compared against. A student taking this department's
  # courses on two campuses in one term belongs to both campus cohorts.
  cohort <- cohort %>%
    distinct(student_id, campus, term) %>%
    rename(anchor_term = term)

  # Restrict to specific anchor terms if requested (e.g. to match a course trend)
  if (!is.null(terms) && length(terms) > 0) {
    cohort <- cohort %>% filter(anchor_term %in% as.integer(terms))
  }

  if (nrow(cohort) == 0) {
    message("[course-retention.R] No registered students found for ", label)
    return(data.frame())
  }

  registered_lookup <- context$registered_lookup
  graduated_lookup  <- context$graduated_lookup

  cohort_with_ret <- .compute_retention(cohort, registered_lookup, n_terms, graduated_lookup)

  ret_cols <- paste0("retained_", seq_len(n_terms))

  result <- cohort_with_ret %>%
    group_by(campus, anchor_term) %>%
    summarise(
      n = n(),
      across(all_of(ret_cols), .safe_mean, .names = "rate_{.col}"),
      .groups = "drop"
    ) %>%
    filter(n >= min_n) %>%
    arrange(campus, desc(anchor_term))

  result <- result %>%
    rename(term = anchor_term) %>%
    mutate(term_label = term_code_to_axis_label(term))

  for (n in seq_len(n_terms)) {
    old_col <- paste0("rate_retained_", n)
    new_col <- paste0("ret_", n)
    if (old_col %in% names(result)) result <- result %>% rename(!!new_col := !!old_col)
  }

  message("[course-retention.R] Benchmark: ", nrow(result), " term rows returned.")
  result
}
