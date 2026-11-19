# Do a course's sections agree on its DFW rate?
#
# Within one course, campus and term, each section of at least
# `min_section_n` attempts is read against the course's rate that term (its
# tested sections pooled). A course-term with `min_sections` such sections is
# tested: the sections are `uneven` when their rates spread more than chance
# allows at `alpha` (a chi-square test of one rate across the sections).
# Each section is placed against the band chance gives a section its size
# (95%, the normal approximation to the binomial): above, within or below.
# Over the window, a course is counted by how many of its tested terms were
# uneven: one that is uneven term after term is a matter of how the course is
# run, not of one term's draw.
#
# A screen, not a verdict (data-anomalies.md): sections differ for reasons
# the attempts do not record (the time of day, delivery, which students
# chose it). The chi-square is approximate when a section's expected DFW
# count is small. No instructor is returned: a section is its CRN.
#
# Exported functions:
#   get_dfw_section_spread(attempts, opt)

#' Whether a course's sections agree, term by term
#'
#' @param attempts The attempt measure table (`cedar_attempts`).
#' @param opt prepare_dfw_attempts()' options (`term_type` required, `level`,
#'   `campus`, `data_edges`), plus `n_window` (default 3 terms),
#'   `min_section_n` (default 10), `min_sections` (default 3) and `alpha`
#'   (default 0.01).
#' @return A list: `sections` (one row per tested section: `campus`,
#'   `subject_course`, `term`, `crn`, summarize_attempt_outcomes()' columns, `band_lo`,
#'   `band_hi` (0-100) and `position`), `course_terms` (one row per tested
#'   course-term: `n_sections`, `n_small_sections` (left out under
#'   `min_section_n`), `n_attempts`, `n_dfw`, `dfw_pct`, `lo_pct`, `hi_pct`,
#'   `chisq`, `p_value`, `uneven`), `courses` (one row per campus-course with
#'   a tested term: `terms_tested`, `terms_uneven`, `n_attempts`, `n_dfw`,
#'   `sections_above`, `sections_below`; most uneven terms first), `meta`.
get_dfw_section_spread <- function(attempts, opt = list()) {
  n_window <- opt$n_window %||% 3L
  min_section_n <- as.integer(opt$min_section_n %||% 10L)
  min_sections <- as.integer(opt$min_sections %||% 3L)
  alpha <- opt$alpha %||% 0.01
  rows <- prepare_dfw_attempts(attempts, opt)
  window <- dfw_window_terms(rows, n_window)
  ct_key <- c("campus", "subject_course", "term")

  all_sections <- summarize_attempt_outcomes(dplyr::filter(rows, term %in% .env$window), c(ct_key, "crn"))
  small <- all_sections %>%
    dplyr::filter(n_attempts < min_section_n) %>%
    dplyr::count(campus, subject_course, term, name = "n_small_sections")
  sized <- all_sections %>%
    dplyr::filter(n_attempts >= min_section_n) %>%
    dplyr::group_by(dplyr::across(dplyr::all_of(ct_key))) %>%
    dplyr::filter(dplyr::n() >= min_sections) %>%
    dplyr::mutate(.p = sum(n_dfw) / sum(n_attempts)) %>%
    dplyr::ungroup()

  course_terms <- sized %>%
    dplyr::group_by(dplyr::across(dplyr::all_of(ct_key))) %>%
    dplyr::summarize(
      # Before the counts are summed: each section against the pooled rate.
      # Zero when every section has one rate, and when the rate is 0 or 100%.
      chisq = if (dplyr::first(.p) %in% c(0, 1)) 0 else
        sum((n_dfw - n_attempts * .p)^2 / (n_attempts * .p * (1 - .p))),
      n_sections = dplyr::n(),
      # A scope with no course-term of enough sections summarizes no group;
      # dplyr still evaluates once on the empty frame.
      lo_pct = if (dplyr::n() > 0L) min(dfw_pct) else NA_real_,
      hi_pct = if (dplyr::n() > 0L) max(dfw_pct) else NA_real_,
      n_attempts = sum(n_attempts),
      n_dfw = sum(n_dfw),
      .groups = "drop"
    ) %>%
    dplyr::relocate(chisq, .after = hi_pct) %>%
    dplyr::mutate(
      dfw_pct = 100 * n_dfw / n_attempts,
      p_value = stats::pchisq(chisq, df = n_sections - 1L, lower.tail = FALSE),
      uneven = p_value < alpha
    ) %>%
    dplyr::left_join(small, by = ct_key) %>%
    dplyr::mutate(n_small_sections = dplyr::coalesce(n_small_sections, 0L)) %>%
    dplyr::relocate(n_small_sections, .after = n_sections) %>%
    dplyr::arrange(campus, subject_course, term)

  sections <- sized %>%
    dplyr::mutate(
      .half = 1.96 * sqrt(.p * (1 - .p) / n_attempts),
      band_lo = 100 * pmax(.p - .half, 0),
      band_hi = 100 * pmin(.p + .half, 1),
      position = dplyr::case_when(dfw_pct > band_hi ~ "above", dfw_pct < band_lo ~ "below", TRUE ~ "within")
    ) %>%
    dplyr::select(-.p, -.half) %>%
    dplyr::arrange(campus, subject_course, term, dplyr::desc(dfw_pct), crn)

  courses <- course_terms %>%
    dplyr::group_by(campus, subject_course) %>%
    dplyr::summarize(terms_tested = dplyr::n(), terms_uneven = sum(uneven),
                     n_attempts = sum(n_attempts), n_dfw = sum(n_dfw), .groups = "drop") %>%
    dplyr::left_join(
      sections %>%
        dplyr::group_by(campus, subject_course) %>%
        dplyr::summarize(sections_above = sum(position == "above"), sections_below = sum(position == "below"),
                         .groups = "drop"),
      by = c("campus", "subject_course")
    ) %>%
    dplyr::arrange(dplyr::desc(terms_uneven), dplyr::desc(n_dfw), campus, subject_course)

  cedar_debug("[dfw-section-spread.R] ", nrow(course_terms), " course-terms tested, ",
              sum(course_terms$uneven), " uneven")
  list(
    sections = sections, course_terms = course_terms, courses = courses,
    meta = list(term_type = opt$term_type, level = opt$level %||% "lower", campus = opt$campus,
                window_terms = sort(window), graded_edge = attr(rows, "graded_edge"),
                min_section_n = min_section_n, min_sections = min_sections, alpha = alpha)
  )
}
