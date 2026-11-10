# major-course-units.R — Which units teach the courses a major's students take?
#
# One question: in each term, the students whose primary major belongs to a
# unit sat in courses taught by which units, and how much of their
# course-taking was outside their own unit. The inverse question (which majors
# fill a unit's seats) is Dept Trends' student-credit-hour breakdown in
# R/branches/credit-hours.R; this cone looks out from the major, not in at
# the course.
#
# A member is a student-term on cedar_student_terms whose primary major's
# unit (`primary_dept_code`, attached at load from programs.csv) is the one
# asked for, and which the table calls enrolled: CEDAR's one definition. A
# pre-major student-term is a member unless opt$include_pre_majors is FALSE.
# The courses are the member's registration rows that term, registered at
# the pull or withdrawn late (a seat held past census); an early drop or a
# waitlist row is not course-taking. The teaching unit is the registration
# row's `department`, the subject's unit from subjects.csv, with NA for a
# subject no mapping row has decided: such rows are kept as a row of their
# own, never dropped and never given a unit.
#
# A row is a term, teaching campus, college and unit, because a course
# metric is grouped by campus (campus-policy.md): a student taking courses on
# two campuses in one term is in both campus rows. Shares are within the
# term and campus over every member registration there, computed before any
# small cell is suppressed, so a page's headline does not move with its
# display grain.
#
# Terms stop at the settled enrollment edge (last_enrolled_complete). With
# opt$include_in_progress, terms up to last_enrolled are added and marked
# `in_progress`, the right-edge policy's labelled current registration.
#
# This is a filter and a join over two tables (ADR-001): the cone counts
# nothing a table already holds.
#
# Depends on: STATUS_REGISTERED, STATUS_DROP_LATE (lists/status_codes.R)
#             cedar_longitudinal_edge() (branches/data-edges.R)
#             cedar_filter_campus() (lists/campuses.R)

#' Which units teach the courses a major's students take
#'
#' @param student_terms `cedar_student_terms`, with its units attached
#'   (`primary_dept_code`).
#' @param registrations `cedar_registrations`, with its units attached
#'   (`department`, `college`).
#' @param opt `dept_code` (the major's unit; required), `program_code` (one
#'   or more program codes to narrow the members to; default every program
#'   of the unit), `include_pre_majors` (default TRUE), `term` (terms to
#'   keep; default every term to the edge), `campus` (teaching campuses to
#'   keep; NULL keeps every campus, each its own row), `min_n` (the smallest
#'   distinct-student count a unit row needs; default 10),
#'   `include_in_progress` (default FALSE), `data_edges`
#'   (`cedar_data_edges()` output, required).
#' @return One row per `term`, `campus`, `college` and `dept_code` (the
#'   teaching unit; NA for a subject with no mapping row), with
#'   `is_own_unit`, `in_progress`, `n_registrations` (distinct student ×
#'   course), `n_students` (distinct students), `term_registrations` and
#'   `term_students` (the same over every unit in that term and campus) and
#'   `share_of_registrations` (`n_registrations / term_registrations`).
#'   Attributes: `edge` (the settled term the rows stop at), `latest_term`
#'   (the last term included), `n_member_student_terms`, `n_members`
#'   (distinct students), `n_unmapped` (member registrations whose subject
#'   has no unit), `suppressed` (the unit rows under `min_n`, as a tibble of
#'   `term`, `campus`, `dept_code`, `n_students`).
get_major_course_units <- function(student_terms, registrations, opt = list()) {
  dept_code <- opt$dept_code
  if (is.null(dept_code) || length(dept_code) != 1L || is.na(dept_code) || !nzchar(dept_code)) {
    stop("[major-course-units.R] opt$dept_code (one unit code) is required.", call. = FALSE)
  }
  needed_st <- c("student_id", "term", "enrolled", "primary_major_code", "primary_dept_code", "is_pre_major")
  missing_st <- setdiff(needed_st, names(student_terms))
  if (length(missing_st) > 0) {
    stop("[major-course-units.R] student_terms lacks ", paste(missing_st, collapse = ", "),
         "; attach its units with attach_default_units().", call. = FALSE)
  }
  needed_reg <- c("student_id", "term", "subject_course", "campus", "college", "department",
                  "registration_status_code")
  missing_reg <- setdiff(needed_reg, names(registrations))
  if (length(missing_reg) > 0) {
    stop("[major-course-units.R] registrations lacks ", paste(missing_reg, collapse = ", "),
         "; attach its units with attach_default_units().", call. = FALSE)
  }

  include_pre_majors  <- isTRUE(opt$include_pre_majors %||% TRUE)
  include_in_progress <- isTRUE(opt$include_in_progress %||% FALSE)
  min_n <- as.integer(opt$min_n %||% 10L)

  edge <- cedar_longitudinal_edge(opt$data_edges)
  if (is.null(edge)) {
    stop("[major-course-units.R] opt$data_edges has no settled enrollment edge (last_enrolled_complete).",
         call. = FALSE)
  }
  latest <- edge
  if (include_in_progress) {
    # `[[`, not `$`: on a list, `$last_enrolled` partial-matches `last_enrolled_complete`.
    latest <- opt$data_edges[["last_enrolled"]]
    if (is.null(latest)) {
      stop("[major-course-units.R] opt$data_edges has no last_enrolled edge for include_in_progress.",
           call. = FALSE)
    }
    latest <- max(as.integer(latest), edge)
  }

  members <- student_terms %>%
    filter(enrolled, !is.na(primary_dept_code), primary_dept_code == dept_code, term <= latest)
  if (!include_pre_majors) members <- members %>% filter(!is_pre_major %in% TRUE)
  if (!is.null(opt$program_code)) members <- members %>% filter(primary_major_code %in% opt$program_code)
  if (!is.null(opt$term)) members <- members %>% filter(term %in% as.integer(opt$term))
  members <- members %>% distinct(student_id, term)
  cedar_debug("[major-course-units.R] ", nrow(members), " member student-terms of ", dept_code,
              " to ", latest)

  taken <- registrations %>%
    filter(registration_status_code %in% c(STATUS_REGISTERED, STATUS_DROP_LATE)) %>%
    select(student_id, term, subject_course, campus, college, department) %>%
    inner_join(members, by = c("student_id", "term"))
  taken <- cedar_filter_campus(taken, opt$campus, "get_major_course_units")

  totals <- taken %>%
    group_by(term, campus) %>%
    summarize(
      term_registrations = n_distinct(student_id, subject_course),
      term_students      = n_distinct(student_id),
      .groups = "drop"
    )

  by_unit <- taken %>%
    group_by(term, campus, college, dept_code = department) %>%
    summarize(
      n_registrations = n_distinct(student_id, subject_course),
      n_students      = n_distinct(student_id),
      .groups = "drop"
    ) %>%
    inner_join(totals, by = c("term", "campus")) %>%
    mutate(
      is_own_unit = !is.na(dept_code) & dept_code == .env$dept_code,
      in_progress = term > edge,
      share_of_registrations = n_registrations / term_registrations
    ) %>%
    select(term, campus, college, dept_code, is_own_unit, in_progress,
           n_registrations, n_students, term_registrations, term_students,
           share_of_registrations) %>%
    arrange(term, campus, desc(n_registrations), dept_code)

  suppressed <- by_unit %>%
    filter(n_students < min_n) %>%
    select(term, campus, dept_code, n_students)
  result <- by_unit %>% filter(n_students >= min_n)

  attr(result, "edge")        <- edge
  attr(result, "latest_term") <- latest
  attr(result, "n_member_student_terms") <- nrow(members)
  attr(result, "n_members")   <- n_distinct(members$student_id)
  attr(result, "n_unmapped")  <- sum(is.na(taken$department))
  attr(result, "suppressed")  <- suppressed
  cedar_debug("[major-course-units.R] ", nrow(result), " unit rows (", nrow(suppressed),
              " under min_n ", min_n, ")")
  result
}
