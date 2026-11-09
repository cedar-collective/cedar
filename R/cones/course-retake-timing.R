# After a DFW, when do students take the course again?
#
# One question: of the attempts in a course that ended in DFW (a D, F, W or
# other non-passing outcome under the default policy, read off
# cedar_attempts), how many were followed by the student sitting in the
# course again, and when: the next regular term, a summer, later within the
# year, or not within a year. It is the measure behind "would a second-half
# or summer section shorten the path": a retake the next regular term costs a
# semester, a summer retake costs none, and a DFW with no retake within a
# year is a student the sequence has lost for now.
#
# The year is the opportunity window (an A→B analysis needs one): an attempt
# whose year ends after the settled enrollment edge is not judged, and the
# count of those is returned beside the result, never folded into "no
# retake". The retake may be on any campus; it is counted under the campus
# of the attempt it follows.

#' Retake timing after a DFW
#'
#' @param attempts The attempt measure table (`cedar_attempts`).
#' @param registrations `cedar_registrations`, keyed on the course, for the
#'   later registrations (any status date; terms past the graded edge count,
#'   a retake needs no grade).
#' @param opt `course` (required), `course_campus` (or `campus`),
#'   `population_ids` (optional), `data_edges` (`cedar_data_edges()` output,
#'   required: the opportunity edge is `last_enrolled_complete`, and the
#'   graded edge must agree with the table's), `min_n` (smallest DFW count a
#'   row needs; default 10).
#' @return One row per course and campus of the DFW attempt: `n_dfw` (judged
#'   attempts), `n_next_regular`, `n_summer`, `n_within_year_other`,
#'   `n_none_within_year`, and `n_unobservable` (attempts too recent to judge).
#'   Attribute `suppressed`: course × campus rows under `min_n`.
get_course_retake_timing <- function(attempts, registrations, opt = list()) {
  opt <- normalize_course_attempt_opt(opt)
  courses <- unique(as.character(opt$course))
  if (length(courses) == 0L || all(is.na(courses))) {
    stop("[course-retake-timing.R] opt$course is required.", call. = FALSE)
  }
  edge <- cedar_longitudinal_edge(opt$data_edges)
  if (is.null(edge)) {
    stop("[course-retake-timing.R] opt$data_edges must carry last_enrolled_complete; ",
         "a retake window needs a settled edge.", call. = FALSE)
  }
  min_n <- as.integer(opt$min_n %||% 10L)
  if (length(min_n) != 1L || is.na(min_n) || min_n < 1L) {
    stop("[course-retake-timing.R] opt$min_n must be a whole number of at least 1.", call. = FALSE)
  }
  needed <- c("student_id", "term", "subject_course", "registration_status_code")
  missing <- setdiff(needed, names(registrations))
  if (length(missing) > 0) {
    stop("[course-retake-timing.R] registrations lack ", paste(missing, collapse = ", "), ".",
         call. = FALSE)
  }

  # The attempts in scope, classified once by the transform; the DFW ones are
  # the anchors. prepare_course_attempts() applies the course, campus and
  # population scope and checks the graded edge.
  scoped <- prepare_course_attempts(attempts, opt)
  if (!"outcome" %in% names(scoped)) {
    stop("[course-retake-timing.R] attempts lack the outcome column build_attempts() writes.",
         call. = FALSE)
  }
  anchors <- scoped %>%
    filter(outcome %in% "dfw") %>%
    distinct(student_id, subject_course, campus, term) %>%
    mutate(
      term = as.integer(term),
      window_end = term + 100L,
      observable = window_end <= edge
    )
  empty <- tibble::tibble(
    subject_course = character(), campus = character(), n_dfw = integer(),
    n_next_regular = integer(), n_summer = integer(), n_within_year_other = integer(),
    n_none_within_year = integer(), n_unobservable = integer()
  )
  if (nrow(anchors) == 0L) {
    attr(empty, "suppressed") <- empty[, c("subject_course", "campus", "n_dfw")]
    return(empty)
  }

  unobservable <- anchors %>%
    filter(!observable) %>%
    count(subject_course, campus, name = "n_unobservable")
  judged <- anchors %>% filter(observable)

  # Sitting in the course again: registered at the pull, or withdrew after
  # census, in a later term up to the edge.
  later <- registrations %>%
    filter(
      student_id %in% judged$student_id,
      subject_course %in% courses,
      registration_status_code %in% c(STATUS_REGISTERED, STATUS_DROP_LATE),
      as.integer(term) <= edge
    ) %>%
    # CAMPUS_ROLLUP: a retake on any campus is a retake; it is counted under
    # the campus of the DFW attempt it follows, which keys the result.
    distinct(student_id, subject_course, retake_term = as.integer(term))

  first_retake <- judged %>%
    left_join(later, by = c("student_id", "subject_course"), relationship = "many-to-many") %>%
    mutate(retake_term = dplyr::if_else(!is.na(retake_term) & retake_term > term,
                                        retake_term, NA_integer_)) %>%
    group_by(student_id, subject_course, campus, term, window_end) %>%
    summarize(
      first_retake = if (all(is.na(retake_term))) NA_integer_ else min(retake_term, na.rm = TRUE),
      .groups = "drop"
    ) %>%
    mutate(
      season = term %% 100L,
      next_regular = dplyr::case_when(
        season == 80L ~ term + 30L,   # Fall -> Spring
        season == 10L ~ term + 70L,   # Spring -> Fall
        season == 60L ~ term + 20L    # Summer -> Fall
      ),
      when = dplyr::case_when(
        is.na(first_retake) | first_retake > window_end ~ "none_within_year",
        first_retake == next_regular ~ "next_regular",
        first_retake %% 100L == 60L ~ "summer",
        TRUE ~ "within_year_other"
      )
    )

  out <- first_retake %>%
    group_by(subject_course, campus) %>%
    summarize(
      n_dfw = dplyr::n(),
      n_next_regular = sum(when == "next_regular"),
      n_summer = sum(when == "summer"),
      n_within_year_other = sum(when == "within_year_other"),
      n_none_within_year = sum(when == "none_within_year"),
      .groups = "drop"
    ) %>%
    full_join(unobservable, by = c("subject_course", "campus")) %>%
    mutate(
      across(c(n_dfw, n_next_regular, n_summer, n_within_year_other, n_none_within_year,
               n_unobservable), ~ as.integer(dplyr::coalesce(.x, 0L)))
    ) %>%
    arrange(subject_course, campus)

  suppressed <- out %>% filter(n_dfw < min_n) %>% select(subject_course, campus, n_dfw)
  out <- out %>% filter(n_dfw >= min_n)
  attr(out, "suppressed") <- suppressed
  cedar_debug("[course-retake-timing.R] ", nrow(out), " course-campus rows, ",
              sum(out$n_dfw), " DFW attempts judged, ", sum(anchors$observable == FALSE),
              " too recent")
  out
}
