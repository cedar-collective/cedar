# Shared course-flow computations.
#
# Public API for course sequencing / neighboring-course analyses:
# - get_next_course_pairs(): campus-scoped source -> next-term destination pairs
# - get_course_destinations(): summarized courses taken after a target course
# - get_course_feeders(): summarized courses taken before a target course
# - get_concurrent_courses(): summarized courses taken in the same term
# - get_course_flow_neighbors(): named list combining destinations/feeders/concurrent
#
# Course sequencing always joins and groups by campus. This prevents students at
# different campuses from being treated as part of the same source/destination
# flow and keeps downstream caches honest about scope.

course_flow_required_cols <- c(
  "student_id", "term", "subject_course", "campus", "college", "term_type",
  "student_classification"
)

empty_next_course_pairs <- function() {
  tibble::tibble(
    campus = character(),
    source_course = character(),
    source_college = character(),
    term = integer(),
    source_term_type = character(),
    dest_course = character(),
    dest_college = character(),
    next_term = integer(),
    dest_term_type = character(),
    n_students = integer()
  )
}

prepare_course_flow_enrollments <- function(students, opt = list()) {
  missing_cols <- setdiff(course_flow_required_cols, names(students))
  if (length(missing_cols) > 0) {
    stop("[course-flows.R] Missing required cedar_students columns: ",
         paste(missing_cols, collapse = ", "), call. = FALSE)
  }

  campus_scope <- opt[["course_campus"]] %||% opt[["campus"]] %||% NULL

  students %>%
    dplyr::ungroup() %>%
    {
      if ("registration_status_code" %in% names(.)) {
        dplyr::filter(., registration_status_code %in% STATUS_REGISTERED)
      } else {
        .
      }
    } %>%
    {
      if (!is.null(campus_scope) && length(campus_scope) > 0) {
        dplyr::filter(., campus %in% .env$campus_scope)
      } else {
        .
      }
    } %>%
    dplyr::distinct(
      campus, college, student_id, term, subject_course, term_type,
      student_classification
    )
}

get_next_course_pairs <- function(students, opt = list(), source_courses = NULL) {
  incl_summer <- opt[["summer"]] %||% FALSE
  source_courses <- source_courses %||% opt[["course"]] %||% opt[["courses"]] %||% NULL

  enrollments <- prepare_course_flow_enrollments(students, opt)

  src <- enrollments %>%
    {
      if (!is.null(source_courses) && length(source_courses) > 0) {
        dplyr::filter(., subject_course %in% .env$source_courses)
      } else {
        .
      }
    } %>%
    dplyr::transmute(
      campus,
      student_id,
      term,
      source_course = subject_course,
      source_college = college,
      source_term_type = term_type
    )

  if (nrow(src) == 0L) return(empty_next_course_pairs())

  src <- add_next_term_col(src, "term", summer = incl_summer)

  dest <- enrollments %>%
    dplyr::transmute(
      campus,
      student_id,
      dest_term = term,
      dest_course = subject_course,
      dest_college = college,
      dest_term_type = term_type
    )

  src %>%
    dplyr::filter(!is.na(next_term)) %>%
    dplyr::inner_join(
      dest,
      by = c("campus", "student_id", "next_term" = "dest_term"),
      relationship = "many-to-many"
    ) %>%
    dplyr::count(
      campus, source_course, source_college, term, source_term_type,
      dest_course, dest_college, next_term, dest_term_type,
      name = "n_students"
    ) %>%
    dplyr::arrange(campus, source_course, term, dplyr::desc(n_students))
}

get_previous_course_pairs <- function(students, opt = list(), target_courses = NULL) {
  incl_summer <- opt[["summer"]] %||% FALSE
  target_courses <- target_courses %||% opt[["course"]] %||% opt[["courses"]] %||% NULL

  if (is.null(target_courses) || length(target_courses) == 0) {
    stop("[course-flows.R] target course is required for previous-course pairs.",
         call. = FALSE)
  }

  enrollments <- prepare_course_flow_enrollments(students, opt)

  target <- enrollments %>%
    dplyr::filter(subject_course %in% .env$target_courses) %>%
    dplyr::transmute(
      campus,
      student_id,
      target_term = term,
      target_course = subject_course,
      target_college = college,
      target_term_type = term_type
    )

  if (nrow(target) == 0L) {
    return(tibble::tibble(
      campus = character(), source_course = character(),
      source_college = character(), source_term = integer(),
      source_term_type = character(), target_course = character(),
      target_college = character(), target_term = integer(),
      target_term_type = character(), n_students = integer()
    ))
  }

  target <- add_prev_term_col(target, "target_term", summer = incl_summer)

  src <- enrollments %>%
    dplyr::transmute(
      campus,
      student_id,
      source_term = term,
      source_course = subject_course,
      source_college = college,
      source_term_type = term_type
    )

  target %>%
    dplyr::filter(!is.na(prev_term)) %>%
    dplyr::inner_join(
      src,
      by = c("campus", "student_id", "prev_term" = "source_term"),
      relationship = "many-to-many"
    ) %>%
    dplyr::mutate(source_term = prev_term) %>%
    dplyr::count(
      campus, source_course, source_college, source_term,
      source_term_type, target_course, target_college, target_term,
      target_term_type,
      name = "n_students"
    ) %>%
    dplyr::arrange(campus, target_course, target_term, dplyr::desc(n_students))
}

get_course_destinations <- function(students, opt = list()) {
  courses <- opt[["course"]] %||% opt[["courses"]]
  if (is.null(courses) || length(courses) == 0) {
    stop("[course-flows.R] opt$course is required.", call. = FALSE)
  }

  pairs <- get_next_course_pairs(students, opt, source_courses = courses)
  if (nrow(pairs) == 0L) {
    return(tibble::tibble(
      campus = character(), college = character(), subject_course = character(),
      source_term_type = character(), dest_term_type = character(),
      from_crse = character(), total_students = integer(), num_terms = integer(),
      min_contrib = integer(), max_contrib = integer(), avg_contrib = numeric()
    ))
  }

  pairs %>%
    dplyr::group_by(
      campus, college = dest_college, subject_course = dest_course,
      source_term_type, dest_term_type, from_crse = source_course
    ) %>%
    dplyr::summarise(
      total_students = sum(n_students),
      num_terms = dplyr::n_distinct(next_term),
      min_contrib = min(n_students),
      max_contrib = max(n_students),
      .groups = "drop"
    ) %>%
    dplyr::mutate(avg_contrib = total_students / num_terms) %>%
    dplyr::arrange(dplyr::desc(avg_contrib))
}

get_course_feeders <- function(students, opt = list()) {
  courses <- opt[["course"]] %||% opt[["courses"]]
  if (is.null(courses) || length(courses) == 0) {
    stop("[course-flows.R] opt$course is required.", call. = FALSE)
  }

  pairs <- get_previous_course_pairs(students, opt, target_courses = courses)
  if (nrow(pairs) == 0L) {
    return(tibble::tibble(
      campus = character(), college = character(), subject_course = character(),
      source_term_type = character(), target_term_type = character(),
      to_crse = character(), total_students = integer(), num_terms = integer(),
      min_contrib = integer(), max_contrib = integer(), avg_contrib = numeric()
    ))
  }

  pairs %>%
    dplyr::group_by(
      campus, college = source_college, subject_course = source_course,
      source_term_type, target_term_type, to_crse = target_course
    ) %>%
    dplyr::summarise(
      total_students = sum(n_students),
      num_terms = dplyr::n_distinct(target_term),
      min_contrib = min(n_students),
      max_contrib = max(n_students),
      .groups = "drop"
    ) %>%
    dplyr::mutate(avg_contrib = total_students / num_terms) %>%
    dplyr::arrange(dplyr::desc(avg_contrib))
}

get_concurrent_courses <- function(students, opt = list()) {
  courses <- opt[["course"]] %||% opt[["courses"]]
  if (is.null(courses) || length(courses) == 0) {
    stop("[course-flows.R] opt$course is required.", call. = FALSE)
  }

  enrollments <- prepare_course_flow_enrollments(students, opt)

  target <- enrollments %>%
    dplyr::filter(subject_course %in% .env$courses) %>%
    dplyr::transmute(
      campus,
      student_id,
      target_term = term,
      target_course = subject_course,
      target_term_type = term_type
    )

  if (nrow(target) == 0L) {
    return(tibble::tibble(
      campus = character(), college = character(), subject_course = character(),
      student_classification = character(), term_type = character(),
      enrl_from_target = numeric(), in_crse = character(),
      coenrolled_student_terms = integer(),
      target_student_terms = integer(), target_terms = integer()
    ))
  }

  target_scope <- target %>%
    dplyr::group_by(campus, target_course) %>%
    dplyr::summarise(
      target_student_terms = dplyr::n(),
      target_terms = dplyr::n_distinct(target_term),
      .groups = "drop"
    )

  concurrent <- target %>%
    dplyr::inner_join(
      enrollments,
      by = c("campus", "student_id", "target_term" = "term"),
      relationship = "many-to-many"
    ) %>%
    dplyr::mutate(term_type = target_term_type) %>%
    dplyr::filter(subject_course != target_course)

  if (nrow(concurrent) == 0L) {
    return(tibble::tibble(
      campus = character(), college = character(), subject_course = character(),
      student_classification = character(), term_type = character(),
      enrl_from_target = numeric(), in_crse = character(),
      coenrolled_student_terms = integer(),
      target_student_terms = integer(), target_terms = integer()
    ))
  }

  concurrent %>%
    dplyr::group_by(
      campus, college, target_course, subject_course,
      student_classification, term_type
    ) %>%
    dplyr::summarise(
      coenrolled_student_terms = dplyr::n(),
      .groups = "drop"
    ) %>%
    dplyr::left_join(
      target_scope,
      by = c("campus", "target_course")
    ) %>%
    dplyr::mutate(
      enrl_from_target = coenrolled_student_terms / target_terms
    ) %>%
    dplyr::rename(in_crse = target_course) %>%
    dplyr::arrange(dplyr::desc(enrl_from_target))
}

#' Summarize courses taken alongside a selected course
#'
#' Collapses the classification and term-type detail returned by
#' `get_concurrent_courses()` into one campus-course row. Counts use
#' student-term enrollments, so a student who takes the selected course in two
#' terms contributes twice. The denominator includes every registered
#' selected-course student-term in the campus scope, including students who did
#' not take a given companion course.
#'
#' @param concurrent Output from `get_concurrent_courses()`.
#' @param top_n Optional maximum number of campus-course rows to retain.
#' @return A campus-grained tibble ordered by share of selected-course
#'   student-term enrollments.
summarize_concurrent_courses <- function(concurrent, top_n = NULL) {
  if (is.null(concurrent) || nrow(concurrent) == 0L) {
    return(tibble::tibble(
      campus = character(), college = character(), subject_course = character(),
      selected_course = character(), coenrolled_student_terms = integer(),
      target_student_terms = integer(), target_terms = integer(),
      avg_students_per_target_term = numeric(),
      pct_selected_student_terms = numeric()
    ))
  }

  required <- c(
    "campus", "college", "subject_course", "in_crse",
    "coenrolled_student_terms", "target_student_terms", "target_terms"
  )
  missing_cols <- setdiff(required, names(concurrent))
  if (length(missing_cols) > 0L) {
    stop("[course-flows.R] Concurrent summary is missing columns: ",
         paste(missing_cols, collapse = ", "), call. = FALSE)
  }

  out <- concurrent %>%
    dplyr::group_by(campus, college, subject_course, selected_course = in_crse) %>%
    dplyr::summarise(
      coenrolled_student_terms = sum(coenrolled_student_terms),
      target_student_terms = max(target_student_terms),
      target_terms = max(target_terms),
      .groups = "drop"
    ) %>%
    dplyr::mutate(
      avg_students_per_target_term = dplyr::if_else(
        target_terms > 0,
        coenrolled_student_terms / target_terms,
        NA_real_
      ),
      pct_selected_student_terms = dplyr::if_else(
        target_student_terms > 0,
        100 * coenrolled_student_terms / target_student_terms,
        NA_real_
      )
    ) %>%
    dplyr::arrange(
      dplyr::desc(pct_selected_student_terms),
      campus,
      subject_course
    )

  if (!is.null(top_n) && length(top_n) > 0L && !is.na(top_n[[1]])) {
    out <- dplyr::slice_head(out, n = max(0L, as.integer(top_n[[1]])))
  }

  out
}

get_course_flow_neighbors <- function(students, opt = list()) {
  courses <- convert_param_to_list(opt[["course"]])
  if (is.null(courses) || length(courses) == 0) {
    stop("Required params: -c (course)\nFor example: -c 'ENGL 1120'",
         call. = FALSE)
  }

  destinations <- list()
  feeders <- list()
  concurrent <- list()

  for (course in courses) {
    course_opt <- opt
    course_opt[["course"]] <- course
    destinations[[course]] <- get_course_destinations(students, course_opt)
    feeders[[course]] <- get_course_feeders(students, course_opt)
    concurrent[[course]] <- get_concurrent_courses(students, course_opt)
  }

  list(
    destinations = dplyr::bind_rows(destinations),
    feeders = dplyr::bind_rows(feeders),
    concurrent = dplyr::bind_rows(concurrent)
  )
}


# ── Downstream course options for a single course ────────────────────────────
#
# Answers "what do students actually take after course X, and how many?" — the
# list a Sequence Effect / Downstream Success user needs in order to pick a
# meaningful downstream course.
#
# Unlike get_next_course_pairs(), this is NOT limited to the immediately
# following term: the impact analyses count any later term, so this must match
# or the picker would advertise counts the analysis does not reproduce.
#
# Campus: scoped, not grouped. This produces a list of courses to choose from,
# not a published rate table, and a dropdown offering "CHEM 1225 · ABQ" and
# "CHEM 1225 · EA" as separate entries would be unusable. The counts are
# therefore aggregates *within the campus scope the caller passes*, and the
# analysis that follows is scoped identically — so the numbers agree. This is a
# deliberate exception under the campus policy in AGENTS.md; pass the same
# opt$campus you will pass to the analysis.

empty_downstream_options <- function() {
  tibble::tibble(
    subject_course  = character(),
    course_title    = character(),
    department      = character(),
    n_students      = integer(),
    pct_of_x        = numeric(),
    same_dept       = logical()
  )
}

.downstream_edges <- function(students, opt) {
  edges <- opt[["data_edges"]] %||% cedar_data_edges(students)
  list(
    observation_end = cedar_longitudinal_edge(edges, grade_dependent = FALSE),
    grade_end = cedar_longitudinal_edge(edges, grade_dependent = TRUE)
  )
}

.downstream_scoped_students <- function(students, campus) {
  students %>%
    dplyr::filter(!is.na(subject_course), nzchar(subject_course)) %>%
    cedar_filter_campus(campus, fn = "course-flows.R downstream audit")
}

.downstream_x_cohort <- function(scoped, course_x, observation_end) {
  scoped %>%
    dplyr::filter(
      subject_course == course_x,
      registration_status_code %in% STATUS_REGISTERED,
      term <= observation_end
    ) %>%
    dplyr::group_by(student_id) %>%
    dplyr::summarize(term_x = min(term, na.rm = TRUE), .groups = "drop") %>%
    add_next_term_col(term_x, summer = FALSE) %>%
    dplyr::rename(first_followup_term = next_term)
}

#' Course-level eligibility and order audit for a downstream pair
#'
#' Counts every student once, independent of instructor attribution. The year
#' table keys a student to the calendar year of their first X attempt and shows
#' whether they had already passed Y strictly earlier or in that same term.
#'
#' @param students cedar_students.
#' @param course_x Character. Upstream course.
#' @param course_y Character vector. Selected downstream course(s).
#' @param opt Named list with `campus` and `data_edges`.
#' @return List with one-row `summary` and `order_by_year` tibbles.
get_downstream_pair_audit <- function(students, course_x, course_y, opt = list()) {
  if (is.null(course_x) || !nzchar(course_x[1]) || length(course_y) == 0) {
    return(list(summary = tibble::tibble(), order_by_year = tibble::tibble()))
  }
  edge <- .downstream_edges(students, opt)
  if (is.null(edge$observation_end) || is.null(edge$grade_end)) {
    return(list(summary = tibble::tibble(), order_by_year = tibble::tibble()))
  }

  scoped <- .downstream_scoped_students(students, opt[["campus"]])
  took_x <- .downstream_x_cohort(scoped, course_x, edge$observation_end)
  if (nrow(took_x) == 0) {
    return(list(summary = tibble::tibble(), order_by_year = tibble::tibble()))
  }

  took_y <- scoped %>%
    dplyr::filter(
      subject_course %in% course_y,
      registration_status_code %in% c(STATUS_REGISTERED, STATUS_DROP_LATE),
      term <= edge$grade_end
    ) %>%
    dplyr::distinct(student_id, term, subject_course, .keep_all = TRUE)

  pass_flags <- took_y %>%
    dplyr::filter(final_grade %in% GRADES_PASS) %>%
    dplyr::inner_join(dplyr::select(took_x, student_id, term_x), by = "student_id") %>%
    dplyr::group_by(student_id) %>%
    dplyr::summarize(
      passed_y_before_x = any(term < term_x),
      passed_y_same_term = any(term == term_x),
      .groups = "drop"
    )

  cohort <- took_x %>%
    dplyr::left_join(pass_flags, by = "student_id") %>%
    dplyr::mutate(
      passed_y_before_x = dplyr::coalesce(passed_y_before_x, FALSE),
      passed_y_same_term = dplyr::coalesce(passed_y_same_term, FALSE),
      right_censored = is.na(first_followup_term) |
        first_followup_term > edge$observation_end,
      prior_pass_excluded = length(course_y) == 1L & passed_y_before_x,
      eligible_for_y = !right_censored & !prior_pass_excluded
    )

  later_ids <- took_y %>%
    dplyr::inner_join(
      dplyr::select(cohort, student_id, term_x, eligible_for_y),
      by = "student_id"
    ) %>%
    dplyr::filter(eligible_for_y, term > term_x) %>%
    dplyr::distinct(student_id)

  summary <- cohort %>%
    dplyr::summarize(
      n_total_in_x = dplyr::n(),
      n_right_censored = sum(right_censored),
      n_passed_y_before_x = sum(passed_y_before_x),
      n_passed_y_same_term = sum(passed_y_same_term),
      n_eligible_for_y = sum(eligible_for_y),
      n_took_y = nrow(later_ids),
      pct_took_y = ifelse(n_eligible_for_y > 0,
                          round(100 * n_took_y / n_eligible_for_y, 1), NA_real_)
    )

  order_by_year <- cohort %>%
    dplyr::mutate(
      year = term_x %/% 100L,
      passed_y_before_or_same_flag = passed_y_before_x | passed_y_same_term
    ) %>%
    dplyr::group_by(year) %>%
    dplyr::summarize(
      students_taking_x = dplyr::n(),
      passed_y_before_x = sum(passed_y_before_x),
      passed_y_same_term = sum(passed_y_same_term),
      passed_y_before_or_same = sum(passed_y_before_or_same_flag),
      pct_before_or_same = round(100 * passed_y_before_or_same / students_taking_x, 1),
      .groups = "drop"
    ) %>%
    dplyr::arrange(dplyr::desc(year))

  list(summary = summary, order_by_year = order_by_year)
}

#' Courses students took after a given course
#'
#' @param students cedar_students.
#' @param course_x Character. The upstream course.
#' @param opt Named list:
#'   \describe{
#'     \item{campus}{Character vector of course-delivery campus codes. Pass the
#'       same value the analysis will use so the counts agree.}
#'     \item{min_n}{Integer. Drop follow-on courses below this many students.
#'       Default 15, matching the impact analyses' default.}
#'     \item{data_edges}{Optional output of [cedar_data_edges()]. Follow-on
#'       enrollment is capped at the longitudinal grade edge (the earlier of
#'       `last_enrolled_complete` and `last_graded`), and recent X cohorts
#'       without a subsequent regular term by that edge are excluded from the
#'       picker denominator. Derived from `students` when omitted.}
#'   }
#' @return Tibble ordered by same-department first, then share of X's students:
#'   subject_course, course_title, department, n_students, pct_of_x, same_dept.
#'
#' No term-gap column: term codes are YYYYSS, so differencing them does not
#' yield a number of semesters, and a plausible-looking wrong gap is worse than
#' no gap at all. Add it via term_diff() if it is ever needed.
get_downstream_course_options <- function(students, course_x, opt = list()) {
  if (is.null(course_x) || !nzchar(course_x[1])) return(empty_downstream_options())
  min_n  <- as.integer(opt[["min_n"]] %||% 15L)
  campus <- opt[["campus"]]
  edge <- .downstream_edges(students, opt)
  if (is.null(edge$observation_end) || is.null(edge$grade_end)) {
    return(empty_downstream_options())
  }

  scoped <- .downstream_scoped_students(students, campus)
  took_x <- .downstream_x_cohort(scoped, course_x, edge$observation_end) %>%
    dplyr::filter(!is.na(first_followup_term),
                  first_followup_term <= edge$observation_end)

  n_x <- nrow(took_x)
  if (n_x == 0) return(empty_downstream_options())

  dept_x <- scoped %>%
    dplyr::filter(subject_course == course_x, !is.na(department)) %>%
    dplyr::slice(1) %>%
    dplyr::pull(department)
  dept_x <- if (length(dept_x) == 0) NA_character_ else dept_x[[1]]

  # CAMPUS_ROLLUP: these are course-picker labels and institution-wide student
  # trajectories inside the selected campus scope, not delivery-rate rows.
  titles <- scoped %>%
    dplyr::filter(!is.na(course_title), nzchar(course_title)) %>%
    dplyr::count(subject_course, course_title) %>%
    dplyr::group_by(subject_course) %>%
    dplyr::slice_max(n, n = 1, with_ties = FALSE) %>%
    dplyr::ungroup() %>%
    dplyr::select(subject_course, course_title)

  depts <- scoped %>%
    dplyr::filter(!is.na(department)) %>%
    # CAMPUS_ROLLUP: course-picker ownership metadata is campus-neutral.
    dplyr::distinct(subject_course, department) %>%
    dplyr::group_by(subject_course) %>%
    dplyr::slice(1) %>%
    dplyr::ungroup()

  y_rows <- scoped %>%
    dplyr::filter(
      subject_course != course_x,
      registration_status_code %in% c(STATUS_REGISTERED, STATUS_DROP_LATE),
      term <= edge$grade_end
    ) %>%
    dplyr::inner_join(took_x, by = "student_id", relationship = "many-to-many") %>%
    dplyr::filter(subject_course != course_x)

  prior_pairs <- y_rows %>%
    dplyr::filter(final_grade %in% GRADES_PASS, term < term_x) %>%
    dplyr::distinct(student_id, subject_course)

  eligible_by_course <- prior_pairs %>%
    dplyr::count(subject_course, name = "n_prior_pass")

  y_rows %>%
    dplyr::filter(term > term_x) %>%
    dplyr::anti_join(prior_pairs, by = c("student_id", "subject_course")) %>%
    # CAMPUS_ROLLUP: the follow-on picker describes student trajectories within
    # the selected scope, not campus delivery performance.
    # One row per student per follow-on course: a student who repeats a course
    # should not count twice toward how many students continue into it.
    dplyr::distinct(student_id, subject_course) %>%
    dplyr::count(subject_course, name = "n_students") %>%
    dplyr::filter(n_students >= min_n) %>%
    dplyr::left_join(eligible_by_course, by = "subject_course") %>%
    dplyr::left_join(titles, by = "subject_course") %>%
    dplyr::left_join(depts,  by = "subject_course") %>%
    dplyr::mutate(
      n_prior_pass = dplyr::coalesce(n_prior_pass, 0L),
      n_eligible = n_x - n_prior_pass,
      pct_of_x  = round(100 * n_students / n_eligible, 1),
      same_dept = !is.na(department) & !is.na(dept_x) & department == dept_x
    ) %>%
    dplyr::filter(n_eligible > 0) %>%
    dplyr::arrange(dplyr::desc(same_dept), dplyr::desc(n_students)) %>%
    dplyr::select(subject_course, course_title, department,
                  n_students, pct_of_x, same_dept)
}
