# Shared course-flow computations.
#
# Public API for course sequencing / neighboring-course analyses:
# - get_next_course_pairs(): campus-scoped source -> next-term destination
#   pairs, counted from the class list; what build_course_flows() runs
# - build_course_flows(): every next-term pair, bounded at the longitudinal
#   edge and stamped: cedar_course_flows, built by the transform (ADR-001
#   step 6), what every next-term reader reads
# - get_course_destinations(): the courses taken the term after a course,
#   read off cedar_course_flows (ADR-001 step 7 group 4)
# - get_course_feeders(): the courses taken the term before a course, the
#   same pairs read from the destination's side
# - get_concurrent_courses(): courses taken in the same term, counted from the
#   class list: a same-term pair is not a flow and no measure table holds it
#
# Course sequencing always joins and groups by campus. This prevents students at
# different campuses from being treated as part of the same source/destination
# flow and keeps downstream caches honest about scope.

course_flow_required_cols <- c(
  "student_id", "term", "subject_course", "campus", "college", "term_type",
  "registration_status_code"
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
    stop("[course-flows.R] Missing required cedar_registrations columns: ",
         paste(missing_cols, collapse = ", "), call. = FALSE)
  }

  campus_scope <- opt[["course_campus"]] %||% opt[["campus"]] %||% NULL

  students %>%
    dplyr::ungroup() %>%
    dplyr::filter(registration_status_code %in% STATUS_REGISTERED) %>%
    {
      if (!is.null(campus_scope) && length(campus_scope) > 0) {
        dplyr::filter(., campus %in% .env$campus_scope)
      } else {
        .
      }
    } %>%
    dplyr::distinct(
      campus, college, student_id, term, subject_course, term_type
    )
}

get_next_course_pairs <- function(students, opt = list(), source_courses = NULL) {
  incl_summer <- opt[["summer"]] %||% FALSE
  source_courses <- source_courses %||% opt[["course"]] %||% opt[["courses"]] %||% NULL

  enrollments <- prepare_course_flow_enrollments(students, opt)
  # opt$through_term: no term after it, as source or destination (the
  # longitudinal edge, build_course_flows()).
  if (!is.null(opt[["through_term"]])) {
    enrollments <- dplyr::filter(enrollments, term <= .env$opt[["through_term"]])
  }

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

# ── cedar_course_flows: every next-term pair, counted once (ADR-001 step 4) ──

# Bump when the pairs counted or the stamps change; a saved copy built under
# another version is rebuilt at start.
COURSE_FLOWS_BUILD_VERSION <- 1L

#' Count every course's next-term destinations, to the longitudinal edge
#'
#' get_next_course_pairs() over the whole keyed class list, regular terms
#' only, after dropping every term past `cedar_longitudinal_edge(edges)`. A
#' pair is a follow-up: its destination term must be complete for
#' enrollment, or the newest source term's pairs count a registration still
#' in progress and read as a fall in flow (right-edge policy). Source terms
#' whose next regular term is past the edge contribute no pair.
#'
#' @param students `cedar_registrations` keyed on the course (attach_course_ids()).
#' @param edges `cedar_report_edges()$edges`; needs `last_enrolled_complete`.
#' @return get_next_course_pairs()'s columns, stamped with `code_renames`,
#'   `enrolled_edge` and `course_flows_build_version`.
build_course_flows <- function(students, edges) {
  edge <- cedar_longitudinal_edge(edges, grade_dependent = FALSE)
  if (is.null(edge)) {
    stop("[course-flows.R] build_course_flows(): edges carry no last_enrolled_complete; ",
         "course flows are a follow-up and need it.", call. = FALSE)
  }
  # The edge is applied inside, to the distinct enrollments: filtering the
  # whole class list first copies every row of it even when nothing is past
  # the edge, at start-up's memory peak.
  flows <- get_next_course_pairs(students, opt = list(summer = FALSE, through_term = edge))
  cedar_debug("[course-flows.R] build_course_flows(): ", nrow(flows),
              " next-term pairs through ", edge, ".")
  attr(flows, "code_renames") <- course_code_renames(students)
  attr(flows, "enrolled_edge") <- as.integer(edge)
  attr(flows, "course_flows_build_version") <- COURSE_FLOWS_BUILD_VERSION
  flows
}

#' Is a course-flow table this build's, for this class list and edge?
#'
#' @param flows A saved or held cedar_course_flows, or NULL.
#' @param students The keyed class list it should have been counted over.
#' @param edges The edges it should be bounded at.
#' @return TRUE when the build version, columns, enrollment edge and the class
#'   list's course-code renames all match.
course_flows_is_current <- function(flows, students, edges) {
  if (!is.data.frame(flows)) return(FALSE)
  if (!identical(attr(flows, "course_flows_build_version", exact = TRUE),
                 COURSE_FLOWS_BUILD_VERSION)) return(FALSE)
  if (!identical(names(flows), names(empty_next_course_pairs()))) return(FALSE)
  edge <- cedar_longitudinal_edge(edges, grade_dependent = FALSE)
  if (is.null(edge) || !identical(attr(flows, "enrolled_edge", exact = TRUE), as.integer(edge))) {
    return(FALSE)
  }
  renames <- attr(flows, "code_renames", exact = TRUE)
  !is.null(renames) && identical(as.character(renames), course_code_renames(students))
}

#' Is this cedar_course_flows as build_course_flows() counts it?
#'
#' The table is required, never recomputed: an absent one is a start-up
#' failure to report, not a reason to count the class list again.
#'
#' @param course_flows The table to check.
#' @param caller The function name for the message.
#' @return `course_flows`, invisibly; an error otherwise.
require_course_flows <- function(course_flows, caller) {
  needed <- names(empty_next_course_pairs())
  if (!is.data.frame(course_flows) || length(setdiff(needed, names(course_flows))) > 0L ||
      is.null(attr(course_flows, "enrolled_edge", exact = TRUE))) {
    stop("[course-flows.R] ", caller, "(): course_flows must be cedar_course_flows as ",
         "build_course_flows() counts it and the loader holds it.", call. = FALSE)
  }
  invisible(course_flows)
}

# The pairs of some courses, scoped the way the class-list readers scoped
# their enrollments: a campus in opt$course_campus (or opt$campus) keeps the
# pairs on that campus (every pair is one campus, the student's on both
# terms). The table is counted without summer as a step (Spring → Fall), so a
# request for summer pairs is refused rather than answered with other pairs.
.scope_course_flows <- function(course_flows, opt, caller) {
  require_course_flows(course_flows, caller)
  if (isTRUE(opt[["summer"]])) {
    stop("[course-flows.R] ", caller, "(): cedar_course_flows counts next regular terms ",
         "(summer = FALSE); opt$summer = TRUE is not an option it answers.", call. = FALSE)
  }
  campus_scope <- opt[["course_campus"]] %||% opt[["campus"]] %||% NULL
  if (!is.null(campus_scope) && length(campus_scope) > 0) {
    course_flows <- dplyr::filter(course_flows, campus %in% .env$campus_scope)
  }
  course_flows
}

#' Courses taken the term after a course
#'
#' @param course_flows `cedar_course_flows` (build_course_flows()).
#' @param opt `course` (or `courses`): the source course(s), required;
#'   `course_campus` / `campus`: keep pairs on these campuses.
#' @return One row per campus, destination course and the pair's term types:
#'   `campus`, `college` (the destination's), `subject_course` (the
#'   destination), `source_term_type`, `dest_term_type`, `from_crse`,
#'   `total_students`, `num_terms`, `min_contrib`, `max_contrib`,
#'   `avg_contrib` (students per destination term).
get_course_destinations <- function(course_flows, opt = list()) {
  courses <- opt[["course"]] %||% opt[["courses"]]
  if (is.null(courses) || length(courses) == 0) {
    stop("[course-flows.R] opt$course is required.", call. = FALSE)
  }

  pairs <- .scope_course_flows(course_flows, opt, "get_course_destinations") %>%
    dplyr::filter(source_course %in% .env$courses)
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

#' Courses taken the term before a course
#'
#' The same next-term pairs as get_course_destinations(), read from the
#' destination's side: a feeder of Y in term T is a course taken in the
#' regular term before T by a student registered in Y at T. Pairs stop at the
#' table's edge, so a term still registering has no feeders yet.
#'
#' @param course_flows `cedar_course_flows` (build_course_flows()).
#' @param opt `course` (or `courses`): the target course(s), required;
#'   `course_campus` / `campus`: keep pairs on these campuses.
#' @return One row per campus, feeder course and the pair's term types:
#'   `campus`, `college` (the feeder's), `subject_course` (the feeder),
#'   `source_term_type`, `target_term_type`, `to_crse`, `total_students`,
#'   `num_terms`, `min_contrib`, `max_contrib`, `avg_contrib` (students per
#'   target term).
get_course_feeders <- function(course_flows, opt = list()) {
  courses <- opt[["course"]] %||% opt[["courses"]]
  if (is.null(courses) || length(courses) == 0) {
    stop("[course-flows.R] opt$course is required.", call. = FALSE)
  }

  pairs <- .scope_course_flows(course_flows, opt, "get_course_feeders") %>%
    dplyr::filter(dest_course %in% .env$courses)
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
      source_term_type, target_term_type = dest_term_type, to_crse = dest_course
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

# Same-term co-enrollment is counted from the class list per request: it is
# not a flow, and no measure table holds the same-term pairs (every pair of a
# student-term's courses is several times the class list).
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
      term_type = character(),
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
      term_type = character(),
      enrl_from_target = numeric(), in_crse = character(),
      coenrolled_student_terms = integer(),
      target_student_terms = integer(), target_terms = integer()
    ))
  }

  concurrent %>%
    dplyr::group_by(
      campus, college, target_course, subject_course, term_type
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
#' Collapses the term-type detail returned by
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
