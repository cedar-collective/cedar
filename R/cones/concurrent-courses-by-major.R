# concurrent-courses-by-major.R — What else do a course's students take that
# term, by their major?
#
# One question: of the student-terms in one course, grouped by the student's
# primary major that term, which other courses were they registered in that
# same term on the same campus, and what share of the group took each? A
# course's students differ by major (pre-nursing students take BIOL 2210
# beside CHEM 1215, engineering students MATH 1512), and a pooled list is
# led by the courses everyone takes; one list per major says what a semester
# with this course looks like for each kind of student.
#
# A student-term is a student registered in the course at the pull on a
# campus in one term (prepare_course_flow_enrollments(), the same rows
# get_concurrent_courses() reads: registered statuses only). A student who
# took the course in two terms is two student-terms. The other courses are
# that student's registered rows the same term on the same campus; a course
# on another campus that term is not counted, because every course figure is
# read by campus (campus-policy.md).
#
# The major is cedar_student_terms' primary major for the student-term,
# named through name_program_codes(), so a pre-major is its own group
# ("Nursing (pre-major)" beside "Nursing"). The opt$n_majors largest groups
# with at least opt$min_n student-terms get a list each; every other
# student-term is in "All other majors", whose shares are over its own
# student-terms. Ties go to the name first in alphabetical order.
#
# The window is one term type at a time (opt$term_type): the course's last
# opt$n_terms terms of that type on each campus, up to the settled enrollment
# edge (last_enrolled_complete). Registration still moving is not a semester's
# course-taking. Each campus's terms are on the result.
#
# The course's own lab (its code with an L suffix, a standalone lab:
# AGENTS.md, Course suffixes) is taken by most of the course's students
# whatever their major, so it would lead every list and push out a course
# that tells the groups apart. It is read once per campus, as a share of all
# the course's student-terms, and left out of the lists.
#
# Same-term pairs are counted from the class list: no measure table holds
# them (AGENTS.md: a same-term pair is not a flow).
#
# Depends on: prepare_course_flow_enrollments() (branches/course-flows.R)
#             attach_student_term(), name_program_codes() (branches/student-terms.R)
#             fmt_term() (trunk/utils.R)

CONCURRENT_OTHER_MAJORS <- "All other majors"

#' What else a course's students take that term, by their major
#'
#' @param registrations `cedar_registrations` as loaded (`subject_course` is
#'   the course id).
#' @param student_terms `cedar_student_terms`, read for `primary_major_code`
#'   and `is_pre_major`.
#' @param dims `cedar_dims`, to name the majors.
#' @param opt `course` (one course id; required), `term_type` (`"fall"`,
#'   `"spring"` or `"summer"`; required), `campus` (campuses to keep; NULL
#'   keeps every campus, each read apart), `n_terms` (the course's last terms
#'   of that type on each campus; default 3), `n_majors` (default 5),
#'   `n_courses` (courses listed per group; default 5), `min_n` (the fewest
#'   student-terms a major needs for a list of its own; default 20),
#'   `min_course_n` (the fewest student-terms a listed course needs; default
#'   5), `data_edges` (`cedar_data_edges()` output; required).
#' @return A list: `lab` (one row per campus where at least
#'   `min_course_n` of the course's student-terms took its own lab:
#'   `lab_course`, `n_student_terms`, `course_student_terms`, `pct`);
#'   `groups` (one row per campus and group: `group`,
#'   `group_rank`, the "All other majors" group last, `n_student_terms`,
#'   `n_students`, `n_majors`); `courses` (one row per campus, group and
#'   listed course: `subject_course`, `n_student_terms` taking it,
#'   `pct` of the group's student-terms, `course_rank`); `meta` (`course`,
#'   `term_type`, `terms`: one row per campus with its terms, `edge`, and the
#'   options used).
get_concurrent_courses_by_major <- function(registrations, student_terms, dims, opt = list()) {
  course <- opt[["course"]]
  if (is.null(course) || length(course) != 1 || is.na(course) || !nzchar(course)) {
    stop("[concurrent-courses-by-major.R] opt$course must be one course id", call. = FALSE)
  }
  term_type <- opt[["term_type"]]
  if (is.null(term_type) || length(term_type) != 1 || !term_type %in% c("fall", "spring", "summer")) {
    stop("[concurrent-courses-by-major.R] opt$term_type must be one of fall, spring, summer", call. = FALSE)
  }
  edge <- opt[["data_edges"]][["last_enrolled_complete"]]
  if (is.null(edge)) {
    stop("[concurrent-courses-by-major.R] opt$data_edges must name last_enrolled_complete", call. = FALSE)
  }
  edge <- as.integer(edge)
  st_cols <- c("student_id", "term", "primary_major_code", "is_pre_major")
  if (is.null(student_terms) || !all(st_cols %in% names(student_terms))) {
    stop("[concurrent-courses-by-major.R] student_terms needs ", paste(st_cols, collapse = ", "),
         call. = FALSE)
  }
  concurrent_major_int_opt <- function(name, default) {
    v <- suppressWarnings(as.integer(opt[[name]] %||% default))
    if (length(v) != 1 || is.na(v) || v < 1L) {
      stop("[concurrent-courses-by-major.R] opt$", name, " must be a positive whole number", call. = FALSE)
    }
    v
  }
  n_terms      <- concurrent_major_int_opt("n_terms", 3L)
  n_majors     <- concurrent_major_int_opt("n_majors", 5L)
  n_courses    <- concurrent_major_int_opt("n_courses", 5L)
  min_n        <- concurrent_major_int_opt("min_n", 20L)
  min_course_n <- concurrent_major_int_opt("min_course_n", 5L)

  enrollments <- prepare_course_flow_enrollments(registrations, list(campus = opt[["campus"]])) %>%
    dplyr::mutate(term = as.integer(term)) %>%
    dplyr::filter(term_type == .env$term_type, term <= .env$edge)

  # The course's last n_terms terms of the type on each campus.
  window <- enrollments %>%
    dplyr::filter(subject_course == .env$course) %>%
    dplyr::distinct(campus, term) %>%
    dplyr::group_by(campus) %>%
    dplyr::slice_max(term, n = n_terms, with_ties = FALSE) %>%
    dplyr::ungroup()

  members <- enrollments %>%
    dplyr::filter(subject_course == .env$course) %>%
    dplyr::semi_join(window, by = c("campus", "term")) %>%
    dplyr::distinct(campus, student_id, term)
  members <- attach_student_term(members, dplyr::mutate(student_terms, term = as.integer(term)),
                                 c("primary_major_code", "is_pre_major"))
  unmatched <- !(paste(members$student_id, members$term) %in%
                   paste(student_terms$student_id, student_terms$term))
  if (any(unmatched)) {
    stop("[concurrent-courses-by-major.R] ", sum(unmatched), " student-terms in ", course,
         " have no row on cedar_student_terms; the tables were not built from the same class lists.",
         call. = FALSE)
  }
  labels <- name_program_codes(members$primary_major_code, dims, is_pre_major = members$is_pre_major)
  members <- members %>%
    dplyr::mutate(major = dplyr::if_else(is.na(primary_major_code) | !nzchar(primary_major_code),
                                         "No major recorded", unname(labels[primary_major_code])))

  # The groups: the largest majors with min_n student-terms, then the rest.
  by_major <- members %>%
    dplyr::count(campus, major, name = "n_student_terms") %>%
    dplyr::arrange(campus, dplyr::desc(n_student_terms), major) %>%
    dplyr::group_by(campus) %>%
    dplyr::mutate(.rank = cumsum(n_student_terms >= min_n),
                  shown = n_student_terms >= min_n & .rank <= n_majors) %>%
    dplyr::ungroup()
  members <- members %>%
    dplyr::left_join(dplyr::select(by_major, campus, major, shown, .rank), by = c("campus", "major")) %>%
    dplyr::mutate(group = dplyr::if_else(shown, major, CONCURRENT_OTHER_MAJORS),
                  group_rank = dplyr::if_else(shown, .rank, n_majors + 1L))

  groups <- members %>%
    dplyr::group_by(campus, group, group_rank) %>%
    dplyr::summarise(n_student_terms = dplyr::n(), n_students = dplyr::n_distinct(student_id),
                     n_majors = dplyr::n_distinct(major), .groups = "drop") %>%
    dplyr::arrange(campus, group_rank)

  # Each member's other registered courses that term on that campus.
  taken <- members %>%
    dplyr::select(campus, student_id, term, group, group_rank) %>%
    dplyr::inner_join(dplyr::select(enrollments, campus, student_id, term, subject_course),
                      by = c("campus", "student_id", "term"), relationship = "one-to-many") %>%
    dplyr::filter(subject_course != .env$course) %>%
    dplyr::distinct(campus, student_id, term, group, group_rank, subject_course)

  # The course's own lab, once per campus, and out of the lists.
  lab_course <- paste0(course, "L")
  lab <- taken %>%
    dplyr::filter(subject_course == .env$lab_course) %>%
    dplyr::count(campus, name = "n_student_terms") %>%
    dplyr::left_join(dplyr::count(members, campus, name = "course_student_terms"), by = "campus") %>%
    dplyr::mutate(lab_course = .env$lab_course, pct = 100 * n_student_terms / course_student_terms) %>%
    dplyr::filter(n_student_terms >= min_course_n) %>%
    dplyr::select(campus, lab_course, n_student_terms, course_student_terms, pct)
  taken <- dplyr::filter(taken, subject_course != .env$lab_course)

  courses <- taken %>%
    dplyr::count(campus, group, group_rank, subject_course, name = "n_student_terms") %>%
    dplyr::left_join(dplyr::select(groups, campus, group, group_terms = n_student_terms),
                     by = c("campus", "group")) %>%
    dplyr::mutate(pct = 100 * n_student_terms / group_terms) %>%
    dplyr::filter(n_student_terms >= min_course_n) %>%
    dplyr::arrange(campus, group_rank, dplyr::desc(n_student_terms), subject_course) %>%
    dplyr::group_by(campus, group) %>%
    dplyr::mutate(course_rank = dplyr::row_number()) %>%
    dplyr::filter(course_rank <= n_courses) %>%
    dplyr::ungroup() %>%
    dplyr::select(campus, group, group_rank, subject_course, n_student_terms, pct, course_rank)

  terms <- window %>%
    dplyr::arrange(campus, term) %>%
    dplyr::group_by(campus) %>%
    dplyr::summarise(terms = list(term), .groups = "drop")

  cedar_debug("[concurrent-courses-by-major.R] ", course, " ", term_type, ": ", nrow(members),
              " student-terms in ", nrow(groups), " campus groups; ", nrow(courses), " courses listed")

  list(
    lab = lab,
    groups = groups,
    courses = courses,
    meta = list(course = course, term_type = term_type, terms = terms, edge = edge,
                n_terms = n_terms, n_majors = n_majors, n_courses = n_courses,
                min_n = min_n, min_course_n = min_course_n)
  )
}

# ── Text preview ───────────────────────────────────────────────────────────────

#' The by-major lists as text
#'
#' @param payload get_concurrent_courses_by_major() output.
#' @return A character vector of lines.
format_concurrent_courses_by_major <- function(payload) {
  if (!all(c("lab", "groups", "courses", "meta") %in% names(payload))) {
    stop("[concurrent-courses-by-major.R] payload must come from get_concurrent_courses_by_major()",
         call. = FALSE)
  }
  m <- payload$meta
  whole <- function(x) format(as.integer(x), big.mark = ",", trim = TRUE)
  out <- sprintf("Courses taken alongside %s, %s terms, through %s (the settled edge)",
                 m$course, m$term_type, fmt_term(m$edge))
  if (nrow(payload$groups) == 0) {
    return(c(out, sprintf("No student registered in %s in a %s term up to the edge.", m$course, m$term_type)))
  }
  for (cp in unique(payload$groups$campus)) {
    g <- payload$groups[payload$groups$campus == cp, ]
    terms <- m$terms$terms[[match(cp, m$terms$campus)]]
    out <- c(out, "", sprintf("%s: %s student-terms in %s (%s)", cp, whole(sum(g$n_student_terms)), m$course,
                              paste(vapply(terms, fmt_term, character(1)), collapse = ", ")))
    lab <- payload$lab[payload$lab$campus == cp, ]
    if (nrow(lab) == 1) {
      out <- c(out, sprintf("  Its lab, %s: %.1f%% (%s), every major together; not in the lists below",
                            lab$lab_course, lab$pct, whole(lab$n_student_terms)))
    }
    for (i in seq_len(nrow(g))) {
      size <- sprintf("%s student-terms, %s students", whole(g$n_student_terms[i]), whole(g$n_students[i]))
      if (g$group[i] == CONCURRENT_OTHER_MAJORS) {
        size <- paste0(size, sprintf(", %s majors", whole(g$n_majors[i])))
      }
      cs <- payload$courses[payload$courses$campus == cp & payload$courses$group == g$group[i], ]
      listed <- if (nrow(cs) == 0) "no other course with enough students" else
        paste(sprintf("%s %.1f%% (%s)", cs$subject_course, cs$pct, whole(cs$n_student_terms)), collapse = ", ")
      out <- c(out, sprintf("  %s (%s): %s", g$group[i], size, listed))
    }
  }
  out
}
