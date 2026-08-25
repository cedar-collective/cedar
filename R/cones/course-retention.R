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
# Campus policy (see AGENTS.md): the *cohort* is campus-scoped — a student who
# took a course at Gallup is not in the Albuquerque cohort — but the retention
# *outcome* is deliberately UNM-wide, because a student who transfers between
# campuses has been retained, not lost. opt$campus restricts the cohort; results
# are always grouped by campus.
#
# Retention definition: a student is retained at T+N if they are:
#   (a) registered anywhere at UNM in the target term, OR
#   (b) recorded as having graduated between the anchor and target terms.
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
#   summarize_retention_by_term_type(retention_result, by_instructor = FALSE)


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

# Every entry point in this file groups by campus, so a students frame without
# a campus column cannot produce a correct result. Failing here is deliberate:
# quietly dropping campus from the grouping is precisely the silent-wrongness
# this policy exists to prevent (see AGENTS.md). Callers with a genuinely
# campus-free frame should add the column before calling.
.require_campus <- function(df, fn) {
  cedar_require_campus(df, paste0("course-retention.R ", fn))
}

# Restrict a students frame to the requested campuses.
#
# Per the CEDAR-wide campus policy in AGENTS.md, a course cohort is always
# campus-scoped: a student taking ENGL 1120 at Gallup is not in the same cohort
# as one taking it in Albuquerque. NULL means every campus, which callers should
# only pass when they intend a UNM-wide aggregate.
.filter_campus <- function(df, campus = NULL) {
  cedar_filter_campus(df, campus, fn = "course-retention.R")
}

.retention_observation_edge <- function(opt) {
  explicit <- opt[["observation_end_term"]]
  if (!is.null(explicit) && length(explicit) > 0) return(as.integer(explicit[[1]]))
  cedar_longitudinal_edge(opt[["data_edges"]], grade_dependent = FALSE)
}

.scope_retention_history <- function(df, observation_end) {
  if (is.null(df) || is.null(observation_end) || !"term" %in% names(df)) return(df)
  dplyr::filter(df, term <= .env$observation_end)
}

# Pre-build the "is registered at term T" lookup.
# Returns a tibble with (student_id, term) for all registered rows.
#
# DELIBERATELY UNM-WIDE, and the one place in this file that is. Retention asks
# whether a student was still enrolled *anywhere at UNM*, so a student who takes
# a course at Gallup and later enrols in Albuquerque is retained, not a stop-out.
# Narrowing this lookup to the cohort's campus would silently redefine retention
# as "stayed on the same campus" and count every transfer as attrition.
# The cohort is campus-scoped (see .filter_campus); the outcome is not.
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
#   - has a graduation record at or after their anchor term and no later than
#     the target term being measured.
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

  # Keep the graduation term until each horizon is evaluated. Dropping it here
  # would let a future degree retroactively mark every earlier horizon retained.
  grad_retained_pairs <- if (!is.null(graduated_lookup) && nrow(graduated_lookup) > 0) {
    cohort %>%
      inner_join(graduated_lookup, by = "student_id") %>%
      filter(grad_term >= anchor_term) %>%
      distinct(student_id, anchor_term, grad_term)
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
    # Many-to-many is expected and harmless: several anchor terms can share a
    # target term, and every student registered in that target matches each of
    # them. The resulting (student_id, anchor_term) pairs are still distinct, so
    # the left_join below cannot duplicate a cohort row. Declared explicitly so
    # the warning does not read as a real fan-out.
    retained_enrolled <- term_map %>%
      inner_join(
        registered_lookup %>% rename(target_term = term),
        by = "target_term",
        relationship = "many-to-many"
      ) %>%
      select(student_id, anchor_term) %>%
      mutate(!!col_name := TRUE)

    # Union with students who had graduated by this target term. A degree earned
    # later remains a success, but cannot change the earlier historical state.
    if (!is.null(grad_retained_pairs)) {
      retained_enrolled <- bind_rows(
        retained_enrolled,
        grad_retained_pairs %>%
          inner_join(term_map, by = "anchor_term") %>%
          filter(grad_term <= target_term) %>%
          select(student_id, anchor_term) %>%
          mutate(!!col_name := TRUE)
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

#' Summarize term-level retention rates across like term types
#'
#' Converts the term rows returned by `get_retention_trend()` into stable
#' Fall/Spring/Summer summaries. Rates are weighted by the starting cohort size,
#' so a 100-student term contributes more than a 10-student term. Each horizon
#' uses only terms for which that future term is observable; `eligible_N`
#' records the corresponding denominator.
#'
#' Campus is always part of the grouping key. When `by_instructor` is TRUE,
#' instructor identity is preserved as well.
#'
#' @param retention_result Result from `get_retention_trend()` or
#'   `get_dept_retention_trend()`.
#' @param by_instructor Logical; aggregate separately by instructor.
#' @param min_n Integer; minimum pooled cohort size for a summary row and for
#'   each displayed horizon. Small individual terms may contribute to a pooled
#'   row as long as the pooled denominator meets this threshold.
#'
#' @return One row per campus and term type, optionally per instructor, with
#'   `terms`, `n`, `ret_1 ... ret_N`, and `eligible_1 ... eligible_N`.
summarize_retention_by_term_type <- function(retention_result,
                                              by_instructor = FALSE,
                                              min_n = 1L) {
  if (is.null(retention_result) || nrow(retention_result) == 0) {
    return(tibble::tibble())
  }

  required <- c("campus", "term", "n")
  missing_cols <- setdiff(required, names(retention_result))
  if (length(missing_cols) > 0) {
    stop(
      "[course-retention.R] summarize_retention_by_term_type: missing required columns: ",
      paste(missing_cols, collapse = ", ")
    )
  }

  ret_cols <- grep("^ret_\\d+$", names(retention_result), value = TRUE)
  if (length(ret_cols) == 0) return(tibble::tibble())
  min_n <- max(1L, as.integer(min_n))

  instructor_cols <- character()
  if (isTRUE(by_instructor)) {
    if (!"instructor_id" %in% names(retention_result)) {
      stop(
        "[course-retention.R] summarize_retention_by_term_type: ",
        "instructor_id is required when by_instructor = TRUE."
      )
    }
    instructor_cols <- "instructor_key"
  }

  data <- retention_result %>%
    mutate(
      term_type = get_term_type(term),
      term_type_label = dplyr::recode(
        term_type,
        fall = "Fall",
        spring = "Spring",
        summer = "Summer",
        .default = NA_character_
      ),
      cohort_n = as.numeric(n)
    ) %>%
    filter(!is.na(term_type))

  if (isTRUE(by_instructor)) {
    if (!"instructor_name" %in% names(data)) {
      data$instructor_name <- NA_character_
    }
    data <- data %>%
      mutate(
        instructor_id = trimws(as.character(instructor_id)),
        instructor_name = trimws(as.character(instructor_name)),
        instructor_key = case_when(
          !is.na(instructor_id) & nzchar(instructor_id) ~ paste0("id:", instructor_id),
          !is.na(instructor_name) & nzchar(instructor_name) ~
            paste0("name:", tolower(instructor_name)),
          TRUE ~ "unknown"
        )
      )
  }

  group_cols <- c("campus", "term_type", "term_type_label", instructor_cols)
  summary <- data %>%
    group_by(across(all_of(group_cols))) %>%
    summarize(
      terms = n_distinct(term),
      n = sum(cohort_n, na.rm = TRUE),
      .groups = "drop"
    )

  # Instructor names can vary across terms (middle initials, capitalization,
  # trailing spaces). Aggregate on the stable ID and use the latest available
  # display name rather than fragmenting one person's history by label text.
  if (isTRUE(by_instructor)) {
    instructor_labels <- data %>%
      arrange(desc(term)) %>%
      group_by(across(all_of(group_cols))) %>%
      summarize(
        instructor_id = dplyr::first(instructor_id),
        instructor_name = dplyr::first(instructor_name),
        .groups = "drop"
      )
    summary <- summary %>%
      left_join(instructor_labels, by = group_cols)
  }

  # Build each horizon independently because recent anchor terms may be
  # observable at +1 but not +2 (and so on). This keeps both the weighted rate
  # and its denominator honest for every column.
  for (ret_col in ret_cols) {
    horizon <- sub("^ret_", "", ret_col)
    eligible_col <- paste0("eligible_", horizon)
    horizon_summary <- data %>%
      filter(!is.na(.data[[ret_col]]), !is.na(cohort_n), cohort_n > 0) %>%
      group_by(across(all_of(group_cols))) %>%
      summarize(
        !!ret_col := stats::weighted.mean(.data[[ret_col]], cohort_n),
        !!eligible_col := sum(cohort_n),
        .groups = "drop"
      )
    summary <- summary %>%
      left_join(horizon_summary, by = group_cols)
  }

  for (ret_col in ret_cols) {
    eligible_col <- paste0("eligible_", sub("^ret_", "", ret_col))
    summary <- summary %>%
      mutate(
        !!ret_col := if_else(
          !is.na(.data[[eligible_col]]) & .data[[eligible_col]] >= min_n,
          .data[[ret_col]],
          NA_real_
        )
      )
  }

  summary %>%
    filter(n >= min_n) %>%
    mutate(
      .term_type_order = match(term_type, c("fall", "spring", "summer")),
      n = as.integer(n),
      across(starts_with("eligible_"), as.integer)
    ) %>%
    arrange(campus, .term_type_order, across(any_of("instructor_name"))) %>%
    select(-.term_type_order, -any_of("instructor_key"))
}

compare_retention_to_benchmarks <- function(course_result, dept_result = NULL,
                                             college_result = NULL,
                                             n_terms = NULL) {
  if (is.null(course_result) || nrow(course_result) == 0) return(tibble::tibble())
  ret_cols <- grep("^ret_\\d+$", names(course_result), value = TRUE)
  if (length(ret_cols) == 0) return(tibble::tibble())
  if (!is.null(n_terms)) ret_cols <- intersect(ret_cols, paste0("ret_", seq_len(n_terms)))

  # Campus joins the key whenever both sides carry it. Without it a course row
  # for one campus matches the benchmark row for every campus in the same term,
  # fanning out and comparing a course against the wrong cohort.
  join_keys <- c("term", "horizon", "horizon_n")
  use_campus <- "campus" %in% names(course_result) &&
    all(vapply(list(dept_result, college_result), function(d) {
      is.null(d) || nrow(d) == 0 || "campus" %in% names(d)
    }, logical(1)))
  if (use_campus) join_keys <- c("campus", join_keys)

  course_long <- course_result %>%
    select(any_of("campus"), term, term_label, n_course = n, all_of(ret_cols)) %>%
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
      select(any_of("campus"), term, n_benchmark = n, all_of(cols)) %>%
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

  compared <- course_long %>%
    inner_join(benchmarks, by = join_keys) %>%
    mutate(
      diff_pct = round((course_retention - benchmark_retention) * 100, 1),
      row_label = paste0(benchmark, " +", horizon_n),
      course_retention_pct = round(course_retention * 100, 1),
      benchmark_retention_pct = round(benchmark_retention * 100, 1)
    ) %>%
    filter(!is.na(diff_pct))

  if (use_campus) {
    compared %>% arrange(campus, term, benchmark, horizon_n)
  } else {
    compared %>% arrange(term, benchmark, horizon_n)
  }
}

summarize_instructor_retention_rows <- function(retention_result, top_n = 10L,
                                                min_n = 1L) {
  if (is.null(retention_result) || nrow(retention_result) == 0 ||
      !"instructor_id" %in% names(retention_result)) {
    return(list(top = NULL, bottom = NULL))
  }
  # The review list is intentionally based on stable instructor-by-term-type
  # summaries, not isolated semesters. Already-aggregated input is accepted so
  # callers can reuse a prepared table.
  if (!all(c("term_type", "terms") %in% names(retention_result))) {
    retention_result <- summarize_retention_by_term_type(
      retention_result,
      by_instructor = TRUE,
      min_n = min_n
    )
  }

  ret_cols <- grep("^ret_\\d+$", names(retention_result), value = TRUE)
  if (length(ret_cols) == 0) return(list(top = NULL, bottom = NULL))

  row_score <- vapply(seq_len(nrow(retention_result)), function(i) {
    rates <- as.numeric(unlist(retention_result[i, ret_cols], use.names = FALSE))
    eligible_cols <- paste0("eligible_", sub("^ret_", "", ret_cols))
    if (all(eligible_cols %in% names(retention_result))) {
      weights <- as.numeric(unlist(
        retention_result[i, eligible_cols],
        use.names = FALSE
      ))
      keep <- !is.na(rates) & !is.na(weights) & weights > 0
      if (!any(keep)) return(NA_real_)
      return(stats::weighted.mean(rates[keep], weights[keep]))
    }
    rates <- rates[!is.na(rates)]
    if (length(rates) == 0L) NA_real_ else mean(rates)
  }, numeric(1))

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
#'     \item{`campus`}{Character vector of campus codes. Restricts the cohort.
#'       NULL includes every campus — pass NULL only for a deliberate UNM-wide
#'       aggregate. Results are grouped by campus either way.}
#'     \item{`data_edges`}{Output of [cedar_data_edges()]. Longitudinal cohorts
#'       and return lookups stop at `last_enrolled_complete`.}
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
  observation_end <- .retention_observation_edge(opt)
  students <- .scope_retention_history(students, observation_end)
  degrees  <- .scope_retention_history(degrees, observation_end)

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

  registered_lookup <- .build_registered_lookup(students)
  graduated_lookup  <- .build_graduated_lookup(degrees)

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
#'
#' @return Wide tibble: one row per campus × term (or campus × term ×
#'   instructor), columns campus, term_label, n, ret_1 .. ret_n (numeric 0–1
#'   or NA).
#'
get_retention_trend <- function(students, opt = list(), degrees = NULL) {
  course <- opt[["course"]] %||% ""
  if (!nzchar(course)) {
    stop("[course-retention.R] get_retention_trend: opt$course must be a non-empty course code.")
  }

  n_terms       <- as.integer(opt[["n_terms"]] %||% 5L)
  min_n         <- as.integer(opt[["min_n"]]   %||% 10L)
  by_instructor <- isTRUE(opt[["by_instructor"]])
  observation_end <- .retention_observation_edge(opt)
  students <- .scope_retention_history(students, observation_end)
  degrees  <- .scope_retention_history(degrees, observation_end)

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

  registered_lookup <- .build_registered_lookup(students)
  graduated_lookup  <- .build_graduated_lookup(degrees)

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
#'
#' @return Wide tibble: one row per campus × anchor term, columns campus, term,
#'   term_label, n, ret_1 .. ret_n (numeric 0–1 or NA).
#'
get_dept_retention_trend <- function(students, opt = list(), degrees = NULL) {
  dept_val    <- opt[["dept_code"]]
  college_val <- opt[["college"]]

  if (is.null(dept_val) && is.null(college_val)) {
    stop("[course-retention.R] get_dept_retention_trend: opt$dept_code or opt$college is required.")
  }

  n_terms   <- as.integer(opt[["n_terms"]] %||% 5L)
  min_n     <- as.integer(opt[["min_n"]]   %||% 10L)
  observation_end <- .retention_observation_edge(opt)
  students <- .scope_retention_history(students, observation_end)
  degrees  <- .scope_retention_history(degrees, observation_end)
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

  registered_lookup <- .build_registered_lookup(students)
  graduated_lookup  <- .build_graduated_lookup(degrees)

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
