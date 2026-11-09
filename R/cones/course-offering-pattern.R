# In which seasons and parts of term is a course offered, and how full is it
# on the first day?
#
# One question, read off cedar_course_terms' schedule side: over the last
# few years, in how many Falls, Springs and Summers was a course offered on a
# campus, in which parts of term (full term, a half, a session), with how many
# seats, and how full it was when classes began. A season's denominator is
# the terms the table covers in the window, so "1 of 3 Summers" means two
# covered Summers without the course, never a Summer the data lacks. The
# first-day fill is the table's reconstruction (first_day_enrl over seats),
# and is known only where every section of the course-term is matched to the
# class list and every capacity is known; anything else is unknown, never a
# partial fill.

#' Offering pattern by season and part of term
#'
#' @param course_terms The course-term measure table (`cedar_course_terms`).
#' @param opt `course` (required), `campus` or `course_campus` (campuses to
#'   keep; each its own row), `data_edges` (`cedar_data_edges()` output,
#'   required: the window ends at `last_enrolled_complete`), `n_years`
#'   (academic years in the window; default 3).
#' @return One row per course, campus, season (`term_type`) and `part_term`:
#'   `n_terms_offered`, `n_terms_in_window` (covered terms of that season),
#'   `last_offered`, `median_sections`, `median_seats`, `n_terms_fill_known`,
#'   `median_first_day_fill` (a proportion), `n_terms_full`
#'   (`CEDAR_FULL_FILL` or more), `n_terms_near_full` (`CEDAR_NEAR_FULL_FILL`
#'   or more). Attribute `window`: the first and last term covered.
get_course_offering_pattern <- function(course_terms, opt = list()) {
  require_course_terms_build(course_terms, "get_course_offering_pattern")
  courses <- unique(as.character(opt$course))
  if (length(courses) == 0L || all(is.na(courses))) {
    stop("[course-offering-pattern.R] opt$course is required.", call. = FALSE)
  }
  edge <- cedar_longitudinal_edge(opt$data_edges)
  if (is.null(edge)) {
    stop("[course-offering-pattern.R] opt$data_edges must carry last_enrolled_complete.",
         call. = FALSE)
  }
  n_years <- as.integer(opt$n_years %||% 3L)
  if (length(n_years) != 1L || is.na(n_years) || n_years < 1L) {
    stop("[course-offering-pattern.R] opt$n_years must be a whole number of at least 1.",
         call. = FALSE)
  }
  campus <- opt$course_campus %||% opt$campus
  window_start <- edge - 100L * n_years   # exclusive: the same season n_years earlier

  covered <- course_terms %>%
    distinct(term, term_type) %>%
    mutate(term = as.integer(term)) %>%
    filter(term <= edge, term > window_start)
  in_window <- covered %>% count(term_type, name = "n_terms_in_window")

  scope <- list(course = courses)
  if (!is.null(campus) && length(campus) > 0) scope$course_campus <- campus
  offered <- filter_course_terms(course_terms, scope) %>%
    ungroup() %>%
    mutate(term = as.integer(term)) %>%
    filter(term <= edge, term > window_start, !is.na(sections))

  # One course-term-campus-part across its colleges (rarely more than one):
  # a fill is known only when every section is matched and every seat known.
  per_term <- offered %>%
    group_by(subject_course, campus, term, term_type, part_term) %>%
    summarize(
      sections = sum(sections),
      # The table's seats count a section whose capacity is unknown as its
      # headcount; a course-term with one such section has unknown seats.
      seats = if (all(seats_known %in% TRUE)) sum(seats) else NA_real_,
      seats_known = all(seats_known %in% TRUE),
      matched = all(sections_matched == sections),
      first_day = sum(first_day_enrl),
      first_day_known = all(is.finite(first_day_enrl)),
      .groups = "drop"
    ) %>%
    mutate(
      first_day_fill = dplyr::if_else(
        seats_known & matched & first_day_known & is.finite(seats) & seats > 0,
        first_day / seats, NA_real_
      )
    )

  median_or_na <- function(x) if (all(is.na(x))) NA_real_ else stats::median(x, na.rm = TRUE)
  out <- per_term %>%
    group_by(subject_course, campus, term_type, part_term) %>%
    summarize(
      n_terms_offered = dplyr::n_distinct(term),
      last_offered = max(term),
      median_sections = stats::median(sections),
      median_seats = median_or_na(seats),
      n_terms_fill_known = sum(!is.na(first_day_fill)),
      median_first_day_fill = median_or_na(first_day_fill),
      n_terms_full = sum(first_day_fill >= CEDAR_FULL_FILL, na.rm = TRUE),
      n_terms_near_full = sum(first_day_fill >= CEDAR_NEAR_FULL_FILL, na.rm = TRUE),
      .groups = "drop"
    ) %>%
    left_join(in_window, by = "term_type") %>%
    mutate(n_terms_in_window = as.integer(dplyr::coalesce(n_terms_in_window, 0L))) %>%
    select(subject_course, campus, term_type, part_term, n_terms_offered, n_terms_in_window,
           last_offered, median_sections, median_seats, n_terms_fill_known,
           median_first_day_fill, n_terms_full, n_terms_near_full) %>%
    arrange(subject_course, campus, term_type, part_term)
  attr(out, "window") <- c(
    first = if (nrow(covered)) min(covered$term) else NA_integer_,
    last = if (nrow(covered)) max(covered$term) else NA_integer_
  )
  attr(out, "covered") <- in_window
  out
}
