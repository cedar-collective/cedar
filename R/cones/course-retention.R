# Cones: Course Retention
#
# Two analyses for measuring how well courses retain students at UNM:
#
#   get_retention_comparison()  — cross-course matrix for a single anchor term:
#       rows = courses, cols = T+1 to T+N semesters
#       cell = % of students registered in that course who are still enrolled
#       anywhere at UNM N semesters later
#
#   get_retention_trend()       — single-course trend across terms:
#       rows = starting terms (terms when students took that course),
#       cols = T+1 to T+N semesters
#       optionally split by instructor
#
# Retention definition: a student is retained at T+N if they are:
#   (a) registered anywhere at UNM in the target term, OR
#   (b) recorded as having graduated at or after the anchor term.
# Graduates are not counted as stop-outs — they successfully completed.
#
# Cells where the target term is beyond the available data are returned as
# NA, not 0%. A 0% would be misleading for recent terms where students
# could not yet have met the criterion.
#
# Depends on:
#   lists/status_codes.R  — STATUS_REGISTERED
#   trunk/utils.R         — add_next_term_col
#
# Exported functions:
#   get_retention_comparison(students, opt, degrees = NULL)
#   get_retention_trend(students, opt, degrees = NULL)


# =============================================================================
# Internal helpers
# =============================================================================

# Advance a vector of term codes by exactly n_steps semesters (skipping summer
# by default). Each element is advanced independently.
.advance_term_n <- function(term_codes, n_steps, summer = FALSE) {
  result <- as.integer(term_codes)
  for (i in seq_len(n_steps)) {
    tmp    <- data.frame(term = result)
    result <- add_next_term_col(tmp, "term", summer = summer)$next_term
  }
  result
}

# Pre-build the "is registered at term T" lookup.
# Returns a tibble with (student_id, term) for all registered rows.
.build_registered_lookup <- function(students) {
  students %>%
    filter(registration_status_code %in% STATUS_REGISTERED) %>%
    distinct(student_id, term)
}

# Pre-build the graduated lookup.
# Returns a tibble with (student_id, grad_term), or NULL if degrees unavailable.
.build_graduated_lookup <- function(degrees) {
  if (is.null(degrees) || nrow(degrees) == 0) return(NULL)
  degrees %>%
    distinct(student_id, grad_term = term)
}

# Given a cohort tibble with columns (student_id, anchor_term), compute
# whether each student is retained at T+1 .. T+n_terms.
#
# A student is retained at T+N if:
#   - registered anywhere at UNM in the target term, OR
#   - has a graduation record at or after their anchor term.
#
# Cells whose target term is beyond max(registered_lookup$term) are set to NA
# rather than FALSE — the data simply does not exist yet.
#
# Returns cohort with additional logical/NA columns retained_1 .. retained_n.
.compute_retention <- function(cohort, registered_lookup, n_terms,
                                graduated_lookup = NULL) {
  result         <- cohort
  unique_anchors <- unique(cohort$anchor_term)
  max_data_term  <- max(registered_lookup$term, na.rm = TRUE)

  # Students who graduated at or after their anchor term are retained at every
  # T+N offset — they successfully completed their degree.
  grad_retained_pairs <- if (!is.null(graduated_lookup) && nrow(graduated_lookup) > 0) {
    cohort %>%
      inner_join(graduated_lookup, by = "student_id") %>%
      filter(grad_term >= anchor_term) %>%
      distinct(student_id, anchor_term)
  } else {
    NULL
  }

  for (n in seq_len(n_terms)) {
    col_name <- paste0("retained_", n)

    # Map each anchor term to its T+N target
    term_map <- data.frame(
      anchor_term = unique_anchors,
      target_term = .advance_term_n(unique_anchors, n_steps = n)
    )

    # Anchor terms whose target is beyond available data — return NA, not 0%
    future_anchors <- term_map %>%
      filter(target_term > max_data_term) %>%
      pull(anchor_term)

    # Students registered at the target term
    retained_enrolled <- term_map %>%
      inner_join(
        registered_lookup %>% rename(target_term = term),
        by = "target_term"
      ) %>%
      select(student_id, anchor_term) %>%
      mutate(!!col_name := TRUE)

    # Union with graduates (retained regardless of target-term registration)
    if (!is.null(grad_retained_pairs)) {
      retained_enrolled <- bind_rows(
        retained_enrolled,
        grad_retained_pairs %>% mutate(!!col_name := TRUE)
      ) %>%
        distinct(student_id, anchor_term, .keep_all = TRUE)
    }

    result <- result %>%
      left_join(retained_enrolled, by = c("student_id", "anchor_term")) %>%
      mutate(!!col_name := if_else(
        anchor_term %in% future_anchors,
        NA,                          # target term not in data — leave blank
        !is.na(!!sym(col_name))      # FALSE = not retained; TRUE = retained
      ))
  }

  result
}

# Safe mean that returns NA_real_ when all inputs are NA (e.g. future terms)
# rather than NaN or 0.
.safe_mean <- function(x) {
  x <- x[!is.na(x)]
  if (length(x) == 0L) NA_real_ else mean(x)
}

compare_retention_to_benchmarks <- function(course_result, dept_result = NULL,
                                             college_result = NULL,
                                             n_terms = NULL) {
  if (is.null(course_result) || nrow(course_result) == 0) return(tibble::tibble())
  ret_cols <- grep("^ret_\\d+$", names(course_result), value = TRUE)
  if (length(ret_cols) == 0) return(tibble::tibble())
  if (!is.null(n_terms)) ret_cols <- intersect(ret_cols, paste0("ret_", seq_len(n_terms)))

  course_long <- course_result %>%
    select(term, term_label, n_course = n, all_of(ret_cols)) %>%
    tidyr::pivot_longer(
      cols = all_of(ret_cols),
      names_to = "horizon",
      values_to = "course_retention"
    ) %>%
    mutate(horizon_n = as.integer(gsub("^ret_", "", horizon)))

  benchmark_long <- function(df, label) {
    if (is.null(df) || nrow(df) == 0) return(NULL)
    cols <- intersect(ret_cols, names(df))
    if (length(cols) == 0) return(NULL)
    df %>%
      select(term, n_benchmark = n, all_of(cols)) %>%
      tidyr::pivot_longer(
        cols = all_of(cols),
        names_to = "horizon",
        values_to = "benchmark_retention"
      ) %>%
      mutate(
        benchmark = label,
        horizon_n = as.integer(gsub("^ret_", "", horizon))
      )
  }

  benchmarks <- bind_rows(
    benchmark_long(dept_result, "Department"),
    benchmark_long(college_result, "College")
  )
  if (is.null(benchmarks) || nrow(benchmarks) == 0) return(tibble::tibble())

  course_long %>%
    inner_join(benchmarks, by = c("term", "horizon", "horizon_n")) %>%
    mutate(
      diff_pct = round((course_retention - benchmark_retention) * 100, 1),
      row_label = paste0(benchmark, " +", horizon_n),
      course_retention_pct = round(course_retention * 100, 1),
      benchmark_retention_pct = round(benchmark_retention * 100, 1)
    ) %>%
    filter(!is.na(diff_pct)) %>%
    arrange(term, benchmark, horizon_n)
}

summarize_instructor_retention_rows <- function(retention_result, top_n = 10L) {
  if (is.null(retention_result) || nrow(retention_result) == 0 ||
      !"instructor_id" %in% names(retention_result)) {
    return(list(top = NULL, bottom = NULL))
  }
  ret_cols <- grep("^ret_\\d+$", names(retention_result), value = TRUE)
  if (length(ret_cols) == 0) return(list(top = NULL, bottom = NULL))

  scores <- as.matrix(retention_result[, ret_cols, drop = FALSE])
  row_score <- apply(scores, 1, function(x) {
    x <- x[!is.na(x)]
    if (length(x) == 0L) NA_real_ else mean(x)
  })

  ranked <- retention_result %>%
    mutate(avg_retention = row_score) %>%
    filter(!is.na(avg_retention)) %>%
    arrange(desc(avg_retention), desc(n))

  if (nrow(ranked) == 0) return(list(top = NULL, bottom = NULL))

  top_n <- max(1L, as.integer(top_n))
  list(
    top = ranked %>% slice_head(n = top_n),
    bottom = ranked %>% arrange(avg_retention, desc(n)) %>% slice_head(n = top_n)
  )
}


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
#'   }
#' @param degrees  cedar_degrees data frame. Used to avoid counting graduates
#'   as stop-outs. Optional; pass NULL to skip the correction.
#'
#' @return Wide tibble: one row per course, columns subject_course, n,
#'   ret_1 .. ret_n (numeric 0–1 or NA).
#'
get_retention_comparison <- function(students, opt = list(), degrees = NULL) {
  anchor_term <- as.integer(opt[["term"]])
  if (is.na(anchor_term) || length(anchor_term) != 1) {
    stop("[course-retention.R] get_retention_comparison: opt$term must be a single term code.")
  }

  n_terms <- as.integer(opt[["n_terms"]] %||% 5L)
  min_n   <- as.integer(opt[["min_n"]]   %||% 10L)

  message("[course-retention.R] Comparison: anchor=", anchor_term,
          " n_terms=", n_terms, " min_n=", min_n)

  anchor <- students %>%
    filter(
      term == anchor_term,
      registration_status_code %in% STATUS_REGISTERED
    )

  if (length(opt[["course"]]) > 0) {
    anchor <- anchor %>% filter(subject_course %in% opt[["course"]])
  }

  anchor <- anchor %>%
    distinct(student_id, subject_course) %>%
    mutate(anchor_term = anchor_term)

  if (nrow(anchor) == 0) {
    message("[course-retention.R] No registered students found for anchor term ", anchor_term)
    return(data.frame())
  }

  registered_lookup <- .build_registered_lookup(students)
  graduated_lookup  <- .build_graduated_lookup(degrees)

  cohort_with_ret <- .compute_retention(anchor, registered_lookup, n_terms, graduated_lookup)

  ret_cols <- paste0("retained_", seq_len(n_terms))

  result <- cohort_with_ret %>%
    group_by(subject_course) %>%
    summarise(
      n = n(),
      across(all_of(ret_cols), .safe_mean, .names = "rate_{.col}"),
      .groups = "drop"
    ) %>%
    filter(n >= min_n) %>%
    arrange(subject_course)

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
#'   }
#' @param degrees  cedar_degrees data frame. Used to avoid counting graduates
#'   as stop-outs. Optional; pass NULL to skip the correction.
#'
#' @return Wide tibble: one row per term (or term × instructor), columns
#'   term_label, n, ret_1 .. ret_n (numeric 0–1 or NA).
#'
get_retention_trend <- function(students, opt = list(), degrees = NULL) {
  course <- opt[["course"]] %||% ""
  if (!nzchar(course)) {
    stop("[course-retention.R] get_retention_trend: opt$course must be a non-empty course code.")
  }

  n_terms       <- as.integer(opt[["n_terms"]] %||% 5L)
  min_n         <- as.integer(opt[["min_n"]]   %||% 10L)
  by_instructor <- isTRUE(opt[["by_instructor"]])

  message("[course-retention.R] Trend: course='", course,
          "' n_terms=", n_terms, " by_instructor=", by_instructor)

  cohort <- students %>%
    filter(
      subject_course == course,
      registration_status_code %in% STATUS_REGISTERED
    )

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

  keep_cols <- c("student_id", "term", if (by_instructor) c("instructor_id", "instructor_name"))

  cohort <- cohort %>%
    distinct(across(all_of(keep_cols))) %>%
    rename(anchor_term = term)

  if (nrow(cohort) == 0) {
    message("[course-retention.R] No registered students found for course '", course, "'")
    return(data.frame())
  }

  registered_lookup <- .build_registered_lookup(students)
  graduated_lookup  <- .build_graduated_lookup(degrees)

  cohort_with_ret <- .compute_retention(cohort, registered_lookup, n_terms, graduated_lookup)

  group_vars <- c("anchor_term", if (by_instructor) c("instructor_id", "instructor_name"))
  ret_cols   <- paste0("retained_", seq_len(n_terms))

  result <- cohort_with_ret %>%
    group_by(across(all_of(group_vars))) %>%
    summarise(
      n = n(),
      across(all_of(ret_cols), .safe_mean, .names = "rate_{.col}"),
      .groups = "drop"
    ) %>%
    filter(n >= min_n) %>%
    arrange(desc(anchor_term))

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
#'   }
#' @param degrees  cedar_degrees data frame. Graduates are not counted as
#'   stop-outs. Optional; pass NULL to skip.
#'
#' @return Wide tibble: one row per anchor term, columns term, term_label, n,
#'   ret_1 .. ret_n (numeric 0–1 or NA).
#'
get_dept_retention_trend <- function(students, opt = list(), degrees = NULL) {
  dept_val    <- opt[["dept"]]
  college_val <- opt[["college"]]

  if (is.null(dept_val) && is.null(college_val)) {
    stop("[course-retention.R] get_dept_retention_trend: opt$dept or opt$college is required.")
  }

  n_terms   <- as.integer(opt[["n_terms"]] %||% 5L)
  min_n     <- as.integer(opt[["min_n"]]   %||% 10L)
  terms     <- opt[["terms"]]
  level_val <- opt[["level"]]
  # Ignore "unknown" — it means the course number pattern didn't match, so
  # filtering on it would silently exclude valid courses.
  if (!is.null(level_val) && (is.na(level_val) || level_val == "unknown")) level_val <- NULL

  label <- if (!is.null(dept_val)) paste0("dept=", dept_val) else paste0("college=", college_val)
  if (!is.null(level_val)) label <- paste0(label, " level=", level_val)
  message("[course-retention.R] Benchmark: ", label, " n_terms=", n_terms)

  # Filter by dept or college, then optionally by course level, then deduplicate
  # to one row per student per term so that students enrolled in multiple courses
  # in the same dept/level are not over-counted in the cohort.
  cohort <- students %>%
    filter(registration_status_code %in% STATUS_REGISTERED)

  if (!is.null(dept_val)) {
    cohort <- cohort %>% filter(department == .env$dept_val)
  } else {
    cohort <- cohort %>% filter(college == .env$college_val)
  }

  if (!is.null(level_val)) {
    cohort <- cohort %>% filter(level == .env$level_val)
  }

  cohort <- cohort %>%
    distinct(student_id, term) %>%
    rename(anchor_term = term)

  # Restrict to specific anchor terms if requested (e.g. to match a course trend)
  if (!is.null(terms) && length(terms) > 0) {
    cohort <- cohort %>% filter(anchor_term %in% as.integer(terms))
  }

  if (nrow(cohort) == 0) {
    message("[course-retention.R] No registered students found for ", label)
    return(data.frame())
  }

  registered_lookup <- .build_registered_lookup(students)
  graduated_lookup  <- .build_graduated_lookup(degrees)

  cohort_with_ret <- .compute_retention(cohort, registered_lookup, n_terms, graduated_lookup)

  ret_cols <- paste0("retained_", seq_len(n_terms))

  result <- cohort_with_ret %>%
    group_by(anchor_term) %>%
    summarise(
      n = n(),
      across(all_of(ret_cols), .safe_mean, .names = "rate_{.col}"),
      .groups = "drop"
    ) %>%
    filter(n >= min_n) %>%
    arrange(desc(anchor_term))

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
