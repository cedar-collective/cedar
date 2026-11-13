# downstream-outcomes.R: what students do in a later course
#
# Of the students who took course X, how many took course Y within a set
# number of regular terms, when, and how did they do in it, read by the grade
# they earned in X and by the term they took X?
#
# The cohort, window, edges and exclusions are build_downstream_cohort()'s
# (branches/downstream-cohort.R), shared with the later-course picker and the
# instructor balance check, so none of them can count continuation
# differently. This cone only summarizes that cohort.
#
# Campus policy (AGENTS.md): every table is grouped by the campus that
# delivered X. A breakdown (grade in X, term of X, X instructor) groups
# further, never instead.
#
# Small cells: a rate whose denominator is below opt$min_n is NA; its counts
# stay. Headline rows are summarized from the cohort directly, never by
# summing guarded breakdown rows.
#
# Grade in X matters most: past students who earned a C in an introductory
# course passed its sequel far less often than those who earned an A. The
# instructor breakdown therefore reports each instructor's X grade mix beside
# their students' later results, and the later results again within each grade
# band: an instructor who passes fewer students sends a stronger group on.
#
# Depends on: build_downstream_cohort() (branches/downstream-cohort.R)
#             add_acad_year(), get_term_type() (trunk/utils.R)
#             GRADE_BAND_LEVELS (lists/grade_bands.R)

# Counts and rates for one grouping of the cohort. Rates are percentages,
# unrounded; display adapters round.
.downstream_rates <- function(cohort, group_cols, min_n) {
  cohort %>%
    dplyr::group_by(dplyr::across(dplyr::all_of(group_cols))) %>%
    dplyr::summarize(
      n_in_x               = dplyr::n(),
      n_right_censored     = sum(right_censored),
      n_passed_y_before_x  = sum(passed_y_before_x),
      # Prior passers removed from the denominator, counted only among those
      # not already removed as too recent, so the removals add up to it.
      n_prior_excluded     = sum(!right_censored & prior_pass_excluded),
      n_passed_y_same_term = sum(passed_y_same_term),
      n_eligible           = sum(eligible),
      n_x_pass             = sum(eligible & x_outcome %in% "pass"),
      n_x_a_or_b           = sum(eligible & x_band %in% c("A", "B")),
      n_took_y             = sum(eligible & took_y),
      n_pass               = sum(eligible & y_outcome %in% "pass"),
      n_dfw                = sum(eligible & y_outcome %in% "dfw"),
      n_withdrew           = sum(eligible & y_outcome %in% "dfw" & y_withdrew),
      n_not_graded         = sum(eligible & y_outcome %in% "not_graded"),
      n_no_outcome         = sum(eligible & y_outcome %in% "no_outcome"),
      first_term_x         = if (any(eligible)) min(term_x[eligible]) else NA_integer_,
      last_term_x          = if (any(eligible)) max(term_x[eligible]) else NA_integer_,
      .groups = "drop"
    ) %>%
    dplyr::mutate(
      n_graded     = n_pass + n_dfw,
      pct_took_y   = dplyr::if_else(n_eligible >= min_n, 100 * n_took_y / n_eligible, NA_real_),
      pct_x_pass   = dplyr::if_else(n_eligible >= min_n, 100 * n_x_pass / n_eligible, NA_real_),
      pct_x_a_or_b = dplyr::if_else(n_eligible >= min_n, 100 * n_x_a_or_b / n_eligible, NA_real_),
      pct_pass     = dplyr::if_else(n_graded >= min_n, 100 * n_pass / n_graded, NA_real_),
      pct_dfw      = dplyr::if_else(n_graded >= min_n, 100 * n_dfw / n_graded, NA_real_)
    )
}

# When continuers took Y: per campus and regular term after X, the count, its
# share of continuers and the running share of everyone who could have.
.downstream_timing <- function(cohort, summary, window_terms, min_n) {
  cohort %>%
    dplyr::filter(eligible, took_y) %>%
    dplyr::count(campus, gap_terms, name = "n") %>%
    tidyr::complete(campus, gap_terms = seq_len(window_terms), fill = list(n = 0L)) %>%
    dplyr::inner_join(dplyr::select(summary, campus, n_eligible, n_took_y), by = "campus") %>%
    dplyr::group_by(campus) %>%
    dplyr::arrange(gap_terms, .by_group = TRUE) %>%
    dplyr::mutate(
      pct_of_continuers = dplyr::if_else(n_took_y >= min_n, 100 * n / n_took_y, NA_real_),
      cum_pct_of_eligible = dplyr::if_else(n_eligible >= min_n,
                                           100 * cumsum(n) / n_eligible, NA_real_)
    ) %>%
    dplyr::ungroup()
}

#' Outcomes in a later course for the students of an earlier one
#'
#' @param students cedar_registrations.
#' @param attempts cedar_attempts.
#' @param opt Named list:
#'   \describe{
#'     \item{course_x}{Character. The earlier course. Required.}
#'     \item{course_y}{Character vector. The later course, or a set of them
#'       (each student counts at their first term with any). Required.}
#'     \item{data_edges}{Output of [cedar_data_edges()]. Required.}
#'     \item{campus}{Campuses that delivered X. NULL includes every campus.}
#'     \item{window_terms}{Regular terms after X in which Y counts. Default 3.}
#'     \item{by_instructor}{TRUE adds the breakdown by the instructor of each
#'       student's first X attempt. Default FALSE.}
#'     \item{min_n}{Smallest denominator a rate is shown for. Default 10.}
#'   }
#' @return Named list. Tables, each with the counts and rates of
#'   `.downstream_rates()`: `summary` (one row per campus), `by_grade`
#'   (campus x grade band in X), `by_term` (campus x term of X, with
#'   `term_type`, oldest first), `instructors` and `instructors_by_grade`
#'   (campus x instructor, and x grade band; NULL unless `by_instructor`).
#'   Also `timing` (campus x regular terms after X), `order_by_year` (campus
#'   x academic year: Y passed before or alongside X), `main_term_type` (the
#'   term type of X holding the most eligible students), and the scope:
#'   `course_x`, `course_y`, `course_y_label`, `rollup`, `by_instructor`,
#'   `min_n`, `window_terms`, `observation_end`, `grade_end`.
get_downstream_outcomes <- function(students, attempts, opt = list()) {
  course_x <- opt[["course_x"]]
  course_y <- opt[["course_y"]]
  if (length(course_x) != 1L || !nzchar(course_x) || length(course_y) == 0L) {
    stop("[downstream-outcomes.R] opt$course_x (one course) and opt$course_y are required.")
  }
  by_instructor <- isTRUE(opt[["by_instructor"]])
  min_n <- as.integer(opt[["min_n"]] %||% 10L)

  built <- build_downstream_cohort(students, attempts, course_x, course_y, opt)
  cohort <- built$cohort
  if (nrow(cohort) == 0) {
    stop("[downstream-outcomes.R] No students took ", course_x,
         " in the selected campuses through ", fmt_term(built$observation_end), ".")
  }
  if (!any(cohort$eligible)) {
    stop("[downstream-outcomes.R] No student who took ", course_x, " has had ",
         built$window_terms, " regular terms to take a later course yet. ",
         "Shorten the follow-up window.")
  }

  cohort <- cohort %>%
    add_acad_year(term_x) %>%
    dplyr::mutate(
      x_band = factor(x_band, levels = GRADE_BAND_LEVELS),
      instructor = dplyr::coalesce(instructor_name, "Instructor not recorded")
    )

  summary <- .downstream_rates(cohort, "campus", min_n)
  by_grade <- .downstream_rates(cohort, c("campus", "x_band"), min_n) %>%
    dplyr::mutate(x_band = as.character(x_band))
  by_term <- .downstream_rates(cohort, c("campus", "term_x"), min_n) %>%
    dplyr::mutate(term_type = get_term_type(term_x), .after = term_x) %>%
    dplyr::arrange(campus, term_x)
  # The term type most of the students who could have continued took X in:
  # the one a per-term reading starts from.
  type_sizes <- by_term %>%
    dplyr::group_by(term_type) %>%
    dplyr::summarize(n = sum(n_eligible), .groups = "drop") %>%
    dplyr::arrange(dplyr::desc(n), match(term_type, c("fall", "spring", "summer")))

  instructors <- NULL
  instructors_by_grade <- NULL
  if (by_instructor) {
    instructors <- .downstream_rates(cohort, c("campus", "instructor"), min_n)
    instructors_by_grade <- .downstream_rates(cohort, c("campus", "instructor", "x_band"), min_n) %>%
      dplyr::mutate(x_band = as.character(x_band))
  }

  order_by_year <- cohort %>%
    dplyr::group_by(campus, acad_year) %>%
    dplyr::summarize(
      students_taking_x = dplyr::n(),
      # Before the two sums below replace the flags they read.
      passed_y_before_or_same = sum(passed_y_before_x | passed_y_same_term),
      passed_y_before_x = sum(passed_y_before_x),
      passed_y_same_term = sum(passed_y_same_term),
      .groups = "drop"
    ) %>%
    dplyr::mutate(pct_before_or_same = 100 * passed_y_before_or_same / students_taking_x) %>%
    dplyr::arrange(campus, acad_year)

  list(
    course_x             = course_x,
    course_y             = course_y,
    course_y_label       = downstream_course_y_label(course_y),
    rollup               = length(course_y) > 1L,
    by_instructor        = by_instructor,
    min_n                = min_n,
    window_terms         = built$window_terms,
    observation_end      = built$observation_end,
    grade_end            = built$grade_end,
    summary              = summary,
    by_grade             = by_grade,
    by_term              = by_term,
    main_term_type       = type_sizes$term_type[[1]],
    timing               = .downstream_timing(cohort, summary, built$window_terms, min_n),
    instructors          = instructors,
    instructors_by_grade = instructors_by_grade,
    order_by_year        = order_by_year
  )
}

# Null-coalescing operator - define only if not already loaded.
if (!exists("%||%")) {
  `%||%` <- function(a, b) if (!is.null(a)) a else b
}
