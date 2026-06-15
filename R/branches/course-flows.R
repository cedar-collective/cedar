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
