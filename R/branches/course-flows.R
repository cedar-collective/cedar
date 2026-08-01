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
      target_course = subject_course
    )

  if (nrow(target) == 0L) {
    return(tibble::tibble(
      campus = character(), college = character(), subject_course = character(),
      student_classification = character(), term_type = character(),
      enrl_from_target = numeric(), in_crse = character()
    ))
  }

  concurrent <- target %>%
    dplyr::inner_join(
      enrollments,
      by = c("campus", "student_id", "target_term" = "term"),
      relationship = "many-to-many"
    ) %>%
    dplyr::filter(subject_course != target_course)

  if (nrow(concurrent) == 0L) {
    return(tibble::tibble(
      campus = character(), college = character(), subject_course = character(),
      student_classification = character(), term_type = character(),
      enrl_from_target = numeric(), in_crse = character()
    ))
  }

  concurrent %>%
    dplyr::group_by(
      campus, college, target_course, target_term, subject_course,
      student_classification, term_type
    ) %>%
    dplyr::summarise(enrolled = dplyr::n_distinct(student_id), .groups = "drop") %>%
    dplyr::group_by(
      campus, college, target_course, subject_course,
      student_classification, term_type
    ) %>%
    dplyr::summarise(enrl_from_target = mean(enrolled), .groups = "drop") %>%
    dplyr::rename(in_crse = target_course) %>%
    dplyr::arrange(dplyr::desc(enrl_from_target))
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

  scoped <- students %>%
    dplyr::filter(registration_status_code %in% STATUS_REGISTERED,
                  !is.na(subject_course), nzchar(subject_course)) %>%
    cedar_filter_campus(campus, fn = "course-flows.R get_downstream_course_options")

  took_x <- scoped %>%
    dplyr::filter(subject_course == course_x) %>%
    dplyr::group_by(student_id) %>%
    dplyr::summarize(term_x = min(term, na.rm = TRUE), .groups = "drop")

  n_x <- nrow(took_x)
  if (n_x == 0) return(empty_downstream_options())

  dept_x <- scoped %>%
    dplyr::filter(subject_course == course_x, !is.na(department)) %>%
    dplyr::slice(1) %>%
    dplyr::pull(department)
  dept_x <- if (length(dept_x) == 0) NA_character_ else dept_x[[1]]

  titles <- scoped %>%
    dplyr::filter(!is.na(course_title), nzchar(course_title)) %>%
    dplyr::count(subject_course, course_title) %>%
    dplyr::group_by(subject_course) %>%
    dplyr::slice_max(n, n = 1, with_ties = FALSE) %>%
    dplyr::ungroup() %>%
    dplyr::select(subject_course, course_title)

  depts <- scoped %>%
    dplyr::filter(!is.na(department)) %>%
    dplyr::distinct(subject_course, department) %>%
    dplyr::group_by(subject_course) %>%
    dplyr::slice(1) %>%
    dplyr::ungroup()

  scoped %>%
    dplyr::inner_join(took_x, by = "student_id", relationship = "many-to-many") %>%
    dplyr::filter(term > term_x, subject_course != course_x) %>%
    # One row per student per follow-on course: a student who repeats a course
    # should not count twice toward how many students continue into it.
    dplyr::distinct(student_id, subject_course) %>%
    dplyr::count(subject_course, name = "n_students") %>%
    dplyr::filter(n_students >= min_n) %>%
    dplyr::left_join(titles, by = "subject_course") %>%
    dplyr::left_join(depts,  by = "subject_course") %>%
    dplyr::mutate(
      pct_of_x  = round(100 * n_students / n_x, 1),
      same_dept = !is.na(department) & !is.na(dept_x) & department == dept_x
    ) %>%
    dplyr::arrange(dplyr::desc(same_dept), dplyr::desc(n_students)) %>%
    dplyr::select(subject_course, course_title, department,
                  n_students, pct_of_x, same_dept)
}
