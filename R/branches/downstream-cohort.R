# downstream-cohort.R: students who took course X, and what they did in course Y
#
# One definition behind every later-course number in Course Dynamics: the
# later-course picker (get_downstream_course_options()), the course-level
# outcomes (cones/downstream-outcomes.R) and the instructor balance check
# (cones/downstream-instructor-balance.R), so no two of them can count
# continuation differently.
#
#   Cohort      each student's first attempt at X (registered or late drop) on
#               a campus in scope, through the settled edge.
#   Window      Y counts only within `window_terms` regular terms after X. A
#               student whose window runs past the settled edge is
#               right-censored: too recent to have had the full chance, not a
#               non-continuer. Without a fixed window an early cohort had
#               years to reach Y and a recent one a single term (ISSUES I56).
#   Continued   any enrollment in Y (registered or late drop) inside the
#               window, read to the settled edge. Reading it only to the grade
#               edge counted everyone taking Y in the newest settled term as a
#               non-continuer (ISSUES I56).
#   Outcome     the first Y term in the window, as cedar_attempts classified
#               it. A term after the grade edge is not graded yet, never a
#               failure.
#   Excluded    for a single Y, a student who passed Y strictly before X was
#               never able to progress from X to Y. A same-term pass is
#               concurrent: counted separately, not excluded. In a set of
#               later courses, passing one member does not rule out the
#               others, so nobody is excluded.
#
# Two tables, by what is read (ADR-001 step 7). Who took X and Y, when, where
# and with whom is enrollment through the settled edge, which only the class
# list holds: cedar_attempts stops at the graded edge. What an attempt earned
# is read off cedar_attempts, classified once, so nothing here decides a grade.
#
# Campus: the cohort is scoped, and grouped by its readers, on the campus that
# delivered X. What a student did next is read on every campus: a student who
# took X at one campus and Y at another continued, as Retention counts a
# campus move as retained.
#
# Depends on: prepare_course_attempts() (branches/course-attempts.R)
#             add_attempt_grade_band() (branches/attempts.R)
#             cedar_longitudinal_edge() (branches/data-edges.R)
#             cedar_filter_campus() (lists/campuses.R)
#             advance_term() (branches/cedar-terms.R)

DOWNSTREAM_DEFAULT_WINDOW <- 3L

DOWNSTREAM_COHORT_COLUMNS <- c(
  "student_id", "campus", "term_x", "instructor_name", "x_outcome", "x_band",
  "window_end", "right_censored", "passed_y_before_x", "passed_y_same_term",
  "prior_pass_excluded", "eligible", "took_y", "term_y", "y_courses",
  "gap_terms", "y_outcome", "y_withdrew"
)

DOWNSTREAM_OPTION_COLUMNS <- c(
  "subject_course", "course_title", "department", "n_students", "n_eligible",
  "pct_of_x", "same_dept"
)

.downstream_class_list_cols <- c(
  "student_id", "term", "subject_course", "campus", "registration_status_code",
  "instructor_name"
)

# When a student's first X term holds rows on two campuses, the worst recorded
# outcome stands, as in the any-DFW rule for repeated rows elsewhere.
.downstream_band_precedence <- c("Withdrew", "C- to F", "Other nonpassing",
                                 "Other passing", "C", "B", "A", "Not graded")

#' How a page names the later course
#'
#' @param course_y The later course, or a set of them.
#' @return The course, or for a set "any of N later courses": a student counts
#'   at their first term with any member.
downstream_course_y_label <- function(course_y) {
  course_y <- unique(course_y)
  if (length(course_y) > 1L) paste0("any of ", length(course_y), " later courses") else course_y
}

.downstream_window <- function(opt) {
  window_terms <- as.integer(opt[["window_terms"]] %||% DOWNSTREAM_DEFAULT_WINDOW)
  if (length(window_terms) != 1L || is.na(window_terms) || window_terms < 1L) {
    stop("[downstream-cohort.R] opt$window_terms must be one whole number of regular terms, 1 or more.",
         call. = FALSE)
  }
  window_terms
}

# The two right edges: enrollment is followed to the settled edge, grades are
# read to the graded edge. Neither is derived here.
.downstream_edges <- function(opt) {
  edges <- opt[["data_edges"]]
  if (is.null(edges)) {
    stop("[downstream-cohort.R] opt$data_edges (cedar_data_edges() output) is required.",
         call. = FALSE)
  }
  edge <- list(
    observation_end = cedar_longitudinal_edge(edges, grade_dependent = FALSE),
    grade_end = cedar_longitudinal_edge(edges, grade_dependent = TRUE)
  )
  if (is.null(edge$observation_end) || is.null(edge$grade_end)) {
    stop("[downstream-cohort.R] A later-course analysis needs a settled and a graded edge; ",
         "opt$data_edges has no last_enrolled_complete or no last_graded.", call. = FALSE)
  }
  edge
}

.downstream_check_inputs <- function(students, course_x, caller) {
  missing <- setdiff(.downstream_class_list_cols, names(students))
  if (length(missing) > 0) {
    stop("[downstream-cohort.R] ", caller, ": the class list is missing columns: ",
         paste(missing, collapse = ", "), call. = FALSE)
  }
  if (length(course_x) != 1L || is.na(course_x) || !nzchar(course_x)) {
    stop("[downstream-cohort.R] ", caller, ": course_x must be one course.", call. = FALSE)
  }
}

# Every row of each student's first X term inside the campus scope: one per
# campus that taught them X that term (the class list's grain).
.downstream_first_x_rows <- function(students, course_x, campus, observation_end) {
  students %>%
    dplyr::filter(
      subject_course == course_x,
      registration_status_code %in% c(STATUS_REGISTERED, STATUS_DROP_LATE),
      term <= observation_end
    ) %>%
    cedar_filter_campus(campus, fn = "downstream-cohort.R") %>%
    dplyr::transmute(
      student_id, campus, term_x = as.integer(term),
      instructor_name = dplyr::na_if(trimws(as.character(instructor_name)), "")
    ) %>%
    dplyr::group_by(student_id) %>%
    dplyr::filter(term_x == min(term_x)) %>%
    dplyr::ungroup()
}

# The attempts of some courses to the grade edge, with each one's grade band.
# The edges must agree with the edge the table was built to
# (prepare_course_attempts() stops when they do not).
.downstream_attempts <- function(attempts, scope, opt, grade_end) {
  prepare_course_attempts(attempts, c(scope, list(data_edges = opt[["data_edges"]]))) %>%
    dplyr::filter(term <= grade_end) %>%
    add_attempt_grade_band() %>%
    dplyr::transmute(student_id, term = as.integer(term), campus, subject_course,
                     outcome, outcome_category, grade_band)
}

# The later-course enrollments of some students through the settled edge, one
# row per student, term and course.
.downstream_enrollments <- function(students, student_ids, observation_end) {
  students %>%
    dplyr::filter(
      student_id %in% student_ids,
      registration_status_code %in% c(STATUS_REGISTERED, STATUS_DROP_LATE),
      term <= observation_end
    )
}

#' Students who took course X, and what each did in course Y
#'
#' The single later-course cohort definition (see the file header).
#'
#' @param students cedar_registrations: who took X and Y, when and where.
#' @param attempts cedar_attempts: what each attempt earned.
#' @param course_x Character. The earlier course.
#' @param course_y Character vector. The later course, or a set of them; with
#'   more than one, each student counts at their first term with any member.
#' @param opt Named list: `data_edges` ([cedar_data_edges()] output; required),
#'   `campus` (campuses that delivered X; NULL for all) and `window_terms`
#'   (regular terms after X in which Y counts; default 3).
#' @return A list: `cohort`, `window_terms`, `observation_end` (the settled
#'   edge enrollment is followed to) and `grade_end` (the edge grades are read
#'   to). `cohort` has one row per student and DOWNSTREAM_COHORT_COLUMNS:
#'   the campus, term and instructor of their first X attempt, `x_outcome`
#'   ("pass" / "dfw" / NA) and `x_band` (GRADE_BAND_LEVELS), `window_end`,
#'   `right_censored`, `passed_y_before_x`, `passed_y_same_term`,
#'   `prior_pass_excluded`, `eligible`, `took_y`, `term_y`, `y_courses`,
#'   `gap_terms` (1..window_terms), `y_outcome` ("pass", "dfw", "not_graded",
#'   "no_outcome", or NA when Y was not taken) and `y_withdrew`.
build_downstream_cohort <- function(students, attempts, course_x, course_y, opt = list()) {
  .downstream_check_inputs(students, course_x, "build_downstream_cohort()")
  course_y <- unique(course_y[!is.na(course_y) & nzchar(course_y)])
  if (length(course_y) == 0L) {
    stop("[downstream-cohort.R] course_y must name at least one course.", call. = FALSE)
  }
  if (course_x %in% course_y) {
    stop("[downstream-cohort.R] course_y holds course_x (", course_x,
         "); a course is not its own later course.", call. = FALSE)
  }
  window_terms <- .downstream_window(opt)
  edge <- .downstream_edges(opt)
  graded <- .downstream_attempts(attempts, list(course = c(course_x, course_y)), opt, edge$grade_end)

  x_graded <- graded %>%
    dplyr::filter(subject_course == course_x) %>%
    dplyr::select(student_id, campus, term_x = term, x_outcome = outcome, x_band = grade_band)
  x <- .downstream_first_x_rows(students, course_x, opt[["campus"]], edge$observation_end) %>%
    dplyr::left_join(x_graded, by = c("student_id", "campus", "term_x")) %>%
    dplyr::mutate(
      x_band = dplyr::coalesce(x_band, "Not graded"),
      .rank = match(x_band, .downstream_band_precedence)
    ) %>%
    dplyr::arrange(student_id, .rank, campus) %>%
    dplyr::distinct(student_id, .keep_all = TRUE) %>%
    dplyr::select(-.rank) %>%
    dplyr::mutate(
      window_end = advance_term(term_x, window_terms),
      right_censored = is.na(window_end) | window_end > edge$observation_end
    )
  windows <- dplyr::select(x, student_id, term_x, window_end)

  y_graded <- dplyr::filter(graded, subject_course %in% course_y)

  # CAMPUS_ROLLUP: what a student did after X is read on every campus; the
  # cohort's campus is X's (see the file header).
  y_enrolled <- .downstream_enrollments(students, x$student_id, edge$observation_end) %>%
    dplyr::filter(subject_course %in% course_y) %>%
    dplyr::transmute(student_id, term = as.integer(term), subject_course) %>%
    dplyr::distinct(student_id, term, subject_course) %>%
    dplyr::inner_join(windows, by = "student_id")

  prior <- y_graded %>%
    dplyr::filter(outcome %in% "pass") %>%
    dplyr::inner_join(windows, by = "student_id") %>%
    dplyr::group_by(student_id) %>%
    dplyr::summarize(
      passed_y_before_x = any(term < term_x),
      passed_y_same_term = any(term == term_x),
      .groups = "drop"
    )

  first_y <- y_enrolled %>%
    dplyr::filter(term > term_x, !is.na(window_end), term <= window_end) %>%
    dplyr::group_by(student_id) %>%
    dplyr::filter(term == min(term)) %>%
    dplyr::summarize(
      term_x = dplyr::first(term_x),
      term_y = dplyr::first(term),
      y_courses = paste(sort(unique(subject_course)), collapse = ", "),
      .groups = "drop"
    )
  # How many regular terms after X the first Y fell: the first k whose window
  # holds it, so a summer enrollment belongs to the regular term after it.
  first_y$gap_terms <- NA_integer_
  for (k in rev(seq_len(window_terms))) {
    within_k <- first_y$term_y <= advance_term(first_y$term_x, k)
    first_y$gap_terms[within_k] <- k
  }

  # The first Y term's outcome: any nonpassing attempt that term makes it DFW,
  # as for a repeated row elsewhere. An attempt with no grade leaves it unknown.
  y_outcomes <- y_graded %>%
    dplyr::filter(!is.na(outcome)) %>%
    dplyr::inner_join(dplyr::select(first_y, student_id, term_y),
                      by = c("student_id", "term" = "term_y")) %>%
    dplyr::group_by(student_id) %>%
    dplyr::summarize(
      y_classified = dplyr::if_else(any(outcome == "dfw"), "dfw", "pass"),
      y_withdrew = any(outcome_category == "w_late_withdrawal"),
      .groups = "drop"
    )

  single_y <- length(course_y) == 1L
  cohort <- x %>%
    dplyr::left_join(prior, by = "student_id") %>%
    dplyr::left_join(dplyr::select(first_y, -term_x), by = "student_id") %>%
    dplyr::left_join(y_outcomes, by = "student_id") %>%
    dplyr::mutate(
      passed_y_before_x = dplyr::coalesce(passed_y_before_x, FALSE),
      passed_y_same_term = dplyr::coalesce(passed_y_same_term, FALSE),
      prior_pass_excluded = single_y & passed_y_before_x,
      eligible = !right_censored & !prior_pass_excluded,
      took_y = !is.na(term_y),
      y_outcome = dplyr::case_when(
        !took_y ~ NA_character_,
        term_y > edge$grade_end ~ "not_graded",
        is.na(y_classified) ~ "no_outcome",
        TRUE ~ y_classified
      ),
      y_withdrew = dplyr::coalesce(y_withdrew, FALSE)
    ) %>%
    dplyr::select(dplyr::all_of(DOWNSTREAM_COHORT_COLUMNS))

  cedar_debug("[downstream-cohort.R] ", course_x, " -> ", paste(course_y, collapse = ", "),
              ": ", nrow(cohort), " in X, ", sum(cohort$eligible), " with a full ",
              window_terms, "-term window, ", sum(cohort$eligible & cohort$took_y), " took Y")
  list(
    cohort = cohort,
    window_terms = window_terms,
    observation_end = edge$observation_end,
    grade_end = edge$grade_end
  )
}

#' Courses students took after a given course
#'
#' The later-course picker. Counts follow build_downstream_cohort(): students
#' whose first X attempt has a complete window, each later course counted once
#' per student inside that window and on every campus, its denominator net of
#' students who had already passed that course before X. The picker and the
#' analysis therefore show the same continuation share for a single course.
#'
#' Campus: the picker is one list across the campus scope, not a rate table
#' per campus ("CHEM 1225 at ABQ" and "CHEM 1225 at EA" as separate entries
#' would be unusable). The analysis that follows splits by campus.
#'
#' @param students cedar_registrations.
#' @param attempts cedar_attempts.
#' @param course_x Character. The earlier course.
#' @param opt Named list: `data_edges`, `campus` and `window_terms` as
#'   build_downstream_cohort(), and `min_n` (drop later courses reached by
#'   fewer students; default 15).
#' @return Tibble with DOWNSTREAM_OPTION_COLUMNS, same-department courses
#'   first, then by students: `n_students` who took the course in the window,
#'   `n_eligible` who could have, `pct_of_x` (0-100, unrounded). Zero rows
#'   when no later course reaches `min_n`.
get_downstream_course_options <- function(students, attempts, course_x, opt = list()) {
  .downstream_check_inputs(students, course_x, "get_downstream_course_options()")
  missing <- setdiff(c("course_title", "department"), names(students))
  if (length(missing) > 0) {
    stop("[downstream-cohort.R] get_downstream_course_options(): the class list is missing columns: ",
         paste(missing, collapse = ", "), call. = FALSE)
  }
  min_n <- as.integer(opt[["min_n"]] %||% 15L)
  window_terms <- .downstream_window(opt)
  edge <- .downstream_edges(opt)

  x_rows <- .downstream_first_x_rows(students, course_x, opt[["campus"]], edge$observation_end)
  took_x <- x_rows %>%
    dplyr::distinct(student_id, term_x) %>%
    dplyr::mutate(window_end = advance_term(term_x, window_terms)) %>%
    dplyr::filter(!is.na(window_end), window_end <= edge$observation_end)
  n_x <- nrow(took_x)

  later <- .downstream_enrollments(students, took_x$student_id, edge$observation_end) %>%
    dplyr::filter(subject_course != course_x) %>%
    dplyr::transmute(student_id, term = as.integer(term), subject_course, course_title, department) %>%
    dplyr::inner_join(took_x, by = "student_id")

  # CAMPUS_ROLLUP: a student's pass of a later course counts wherever it was
  # taken, as in build_downstream_cohort().
  prior_pairs <- .downstream_attempts(
    attempts, list(population_ids = took_x$student_id), opt, edge$grade_end
  ) %>%
    dplyr::filter(outcome %in% "pass", subject_course != course_x) %>%
    dplyr::inner_join(took_x, by = "student_id") %>%
    dplyr::filter(term < term_x) %>%
    dplyr::distinct(student_id, subject_course)

  # CAMPUS_ROLLUP: one count per later course across every campus that taught
  # it; the campus scope is X's and is already applied to took_x.
  continued <- later %>%
    dplyr::filter(term > term_x, term <= window_end) %>%
    dplyr::anti_join(prior_pairs, by = c("student_id", "subject_course")) %>%
    dplyr::distinct(student_id, subject_course) %>%
    dplyr::count(subject_course, name = "n_students") %>%
    dplyr::filter(n_students >= min_n)

  # CAMPUS_ROLLUP: a course's usual title and owning unit are labels, not
  # measures; the most common value among these students' rows.
  usual <- function(col) {
    later %>%
      dplyr::filter(subject_course %in% continued$subject_course,
                    !is.na(.data[[col]]), nzchar(.data[[col]])) %>%
      dplyr::count(subject_course, value = .data[[col]], name = "rows") %>%
      dplyr::group_by(subject_course) %>%
      dplyr::slice_max(rows, n = 1L, with_ties = FALSE) %>%
      dplyr::ungroup() %>%
      dplyr::select(subject_course, value)
  }
  dept_x <- students %>%
    dplyr::filter(subject_course == course_x, !is.na(department)) %>%
    dplyr::count(department, sort = TRUE) %>%
    dplyr::pull(department)
  dept_x <- if (length(dept_x) == 0) NA_character_ else dept_x[[1]]

  continued %>%
    # CAMPUS_ROLLUP: per later course, as `continued` above.
    dplyr::left_join(dplyr::count(prior_pairs, subject_course, name = "n_prior_pass"),
                     by = "subject_course") %>%
    dplyr::left_join(dplyr::rename(usual("course_title"), course_title = value), by = "subject_course") %>%
    dplyr::left_join(dplyr::rename(usual("department"), department = value), by = "subject_course") %>%
    dplyr::mutate(
      n_eligible = n_x - dplyr::coalesce(n_prior_pass, 0L),
      pct_of_x = 100 * n_students / n_eligible,
      same_dept = !is.na(department) & !is.na(dept_x) & department == dept_x
    ) %>%
    dplyr::arrange(dplyr::desc(same_dept), dplyr::desc(n_students), subject_course) %>%
    dplyr::select(dplyr::all_of(DOWNSTREAM_OPTION_COLUMNS))
}

# Null-coalescing operator - define only if not already loaded.
if (!exists("%||%")) {
  `%||%` <- function(a, b) if (!is.null(a)) a else b
}
