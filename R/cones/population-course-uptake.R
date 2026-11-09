# When does a population take a course, relative to entering its focal unit?
#
# One question: of the students in a population, how many have sat in each
# course (registered at the pull, or withdrew after census), and how long
# after entering the focal unit did they first take it. Entry is
# `population$first_unit_term`, the first term with a focal program record
# (declared or pre-major), so a course taken before entry is counted apart:
# it is preparation the student brought, not the unit's curriculum at work.
# Summer pins to the Spring before it, as relative-term numbering does, so a
# term after entry is a regular-term step.
#
# Observation stops at the settled enrollment edge (last_enrolled_complete),
# and each student's rows stop at `relevant_until`, the population ceiling.

#' Course uptake and timing for a population
#'
#' @param registrations `cedar_registrations`, keyed on the course.
#' @param population `build_population()` output, with `first_unit_term` and
#'   `relevant_until`.
#' @param opt `course` (the courses, required), `campus` (course campuses to
#'   keep; NULL keeps every campus, each its own row), `data_edges`
#'   (`cedar_data_edges()` output, required), `min_n` (smallest taker count a
#'   row needs; default 10).
#' @return One row per course and campus: `n_takers`, `n_population`, `share`
#'   (takers over the population), `n_before_entry`, `n_after_entry`,
#'   `median_terms_after_entry` and `p75_terms_after_entry` (regular terms
#'   after `first_unit_term`; 0 is the entry term; over the at-or-after rows).
#'   Attributes: `not_taken` (requested courses no one in the population sat
#'   in), `suppressed` (course × campus rows under `min_n`), `edge`,
#'   `n_without_entry` (population students with no `first_unit_term`, left
#'   out).
get_population_course_uptake <- function(registrations, population, opt = list()) {
  validate_population(population, "get_population_course_uptake")
  needed <- c("first_unit_term", "relevant_until")
  missing <- setdiff(needed, names(population))
  if (length(missing) > 0) {
    stop("[population-course-uptake.R] population lacks ", paste(missing, collapse = ", "),
         "; build it with build_population().", call. = FALSE)
  }
  courses <- unique(as.character(opt$course))
  if (length(courses) == 0L || all(is.na(courses))) {
    stop("[population-course-uptake.R] opt$course is required.", call. = FALSE)
  }
  edge <- cedar_longitudinal_edge(opt$data_edges)
  if (is.null(edge)) {
    stop("[population-course-uptake.R] opt$data_edges must carry last_enrolled_complete; ",
         "refusing to count uptake without a settled edge.", call. = FALSE)
  }
  min_n <- as.integer(opt$min_n %||% 10L)
  if (length(min_n) != 1L || is.na(min_n) || min_n < 1L) {
    stop("[population-course-uptake.R] opt$min_n must be a whole number of at least 1.", call. = FALSE)
  }
  cedar_require_campus(registrations, "population-course-uptake.R get_population_course_uptake")
  needed <- c("student_id", "term", "subject_course", "registration_status_code")
  missing <- setdiff(needed, names(registrations))
  if (length(missing) > 0) {
    stop("[population-course-uptake.R] registrations lack ", paste(missing, collapse = ", "), ".",
         call. = FALSE)
  }

  entry <- population %>%
    distinct(student_id, first_unit_term, relevant_until)
  n_without_entry <- sum(is.na(entry$first_unit_term))
  entry <- filter(entry, !is.na(first_unit_term))
  n_population <- n_distinct(entry$student_id)

  # A student sat in the course: registered at the pull, or withdrew after
  # census. An early drop or a waitlist row is not taking the course.
  rows <- registrations %>%
    filter(
      student_id %in% entry$student_id,
      subject_course %in% courses,
      registration_status_code %in% c(STATUS_REGISTERED, STATUS_DROP_LATE),
      as.integer(term) <= edge
    ) %>%
    cedar_filter_campus(opt$campus, fn = "get_population_course_uptake") %>%
    distinct(student_id, term, subject_course, campus) %>%
    inner_join(entry, by = "student_id") %>%
    filter(is.na(relevant_until) | as.integer(term) <= relevant_until)

  pin_regular <- function(term) {
    term <- as.integer(term)
    # Summer pins to the Spring before it, as assign_relative_terms() does.
    dplyr::if_else(term %% 100L == 60L, term - 50L, term)
  }
  first_takes <- rows %>%
    group_by(student_id, subject_course, campus) %>%
    summarize(
      first_term = min(as.integer(term)),
      first_unit_term = dplyr::first(first_unit_term),
      .groups = "drop"
    ) %>%
    mutate(terms_after_entry = term_diff(pin_regular(first_unit_term), pin_regular(first_term)))

  stat_or_na <- function(x, f) if (length(x) == 0L) NA_real_ else f(x)
  out <- first_takes %>%
    group_by(subject_course, campus) %>%
    summarize(
      n_takers = dplyr::n(),
      n_before_entry = sum(terms_after_entry < 0L),
      n_after_entry = sum(terms_after_entry >= 0L),
      median_terms_after_entry = stat_or_na(terms_after_entry[terms_after_entry >= 0L], stats::median),
      p75_terms_after_entry = stat_or_na(
        terms_after_entry[terms_after_entry >= 0L],
        function(x) stats::quantile(x, 0.75, names = FALSE)
      ),
      .groups = "drop"
    ) %>%
    mutate(
      n_population = n_population,
      share = dplyr::if_else(n_population > 0L, n_takers / n_population, NA_real_)
    ) %>%
    select(subject_course, campus, n_takers, n_population, share, n_before_entry,
           n_after_entry, median_terms_after_entry, p75_terms_after_entry) %>%
    arrange(subject_course, campus)

  suppressed <- out %>% filter(n_takers < min_n) %>% select(subject_course, campus, n_takers)
  out <- out %>% filter(n_takers >= min_n)
  attr(out, "not_taken") <- sort(setdiff(courses, unique(rows$subject_course)))
  attr(out, "suppressed") <- suppressed
  attr(out, "edge") <- as.integer(edge)
  attr(out, "n_without_entry") <- as.integer(n_without_entry)
  cedar_debug("[population-course-uptake.R] ", nrow(out), " course-campus rows shown, ",
              nrow(suppressed), " under min_n ", min_n, ", population ", n_population)
  out
}
