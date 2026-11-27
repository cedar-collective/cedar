# How far apart are a course's sections on its DFW rate, and is that changing?
#
# Within one course, campus and term, each section of at least
# `min_section_n` attempts is read against the course's rate that term (those
# sections pooled). A course-term with `min_sections` such sections is read:
# its `spread_var` is the variance of its sections' rates left after taking
# out what chance gives sections of their sizes (the method-of-moments
# estimate, squared points):
#
#   (chisq - (sections - 1)) * rate * (100 - rate) / (N - sum(n^2) / N)
#
# with chisq the chi-square of one rate across the sections, N the attempts
# and n each section's. Unlike the gap between the lowest and highest section,
# or the sections' mean distance from the course's rate, its expectation does
# not move with how many sections there are or how small they are. It is kept
# untruncated, negative when the sections sit closer than chance alone would
# put them, so an average over terms is not pushed up; `spread_pts` is its
# square root floored at 0, the reading in points: about how far a section's
# own rate sits from the course's. Its standard error is chance alone given
# those sections (a noncentral chi-square's,
# sqrt(2 * (df + 2 * max(chisq - df, 0))) on the chi-square's scale); what
# the terms scatter beyond that is compute_rate_trend()'s to guard. A
# course-term whose rate is 0 or 100% has no chance spread to be set against
# and is left out, counted in `meta`.
#
# Every term in scope is read, and nothing is said of one term alone. A
# course's average is its terms pooled, each by its weight (the formula's
# denominator); its direction is compute_rate_trend() over its terms'
# `spread_var` and `spread_se`: rising is spreading, falling consolidating.
# `overall` pools every course a term the same way, and every course and term
# into one average. The courses read change from term to term, so the overall
# series also moves with which courses had enough sections.
#
# A screen, not a verdict (data-anomalies.md): sections differ for reasons
# the attempts do not record (the time of day, delivery, which students
# chose it). The chi-square is approximate when a section's expected DFW
# count is small. No instructor is returned: a section is its CRN.
#
# Exported functions:
#   get_dfw_section_spread(attempts, opt)

# Course-terms' spreads pooled within each group: the mean of the variances,
# each term by its weight, with its standard error and its reading in points.
.dfw_pool_spread <- function(course_terms, group_cols) {
  course_terms %>%
    dplyr::group_by(dplyr::across(dplyr::all_of(group_cols))) %>%
    dplyr::summarize(
      n_course_terms = dplyr::n(),
      sections_per_term = mean(n_sections),
      lo_pct = mean(lo_pct),
      hi_pct = mean(hi_pct),
      n_attempts = sum(n_attempts),
      n_dfw = sum(n_dfw),
      .pooled_var = sum(spread_weight * spread_var) / sum(spread_weight),
      spread_se = sqrt(sum((spread_weight * spread_se)^2)) / sum(spread_weight),
      .groups = "drop"
    ) %>%
    dplyr::mutate(dfw_pct = 100 * n_dfw / n_attempts, spread_var = .pooled_var,
                  spread_pts = sqrt(pmax(spread_var, 0))) %>%
    dplyr::select(-.pooled_var) %>%
    dplyr::relocate(dfw_pct, .after = n_dfw) %>%
    dplyr::relocate(spread_var, .before = spread_se)
}

# The direction of a spread series, one line a group: compute_rate_trend()
# over the variances, with the fitted line's ends read back in points. Every
# series is a group, the one overall series too, so a scope with no term
# gives no row and no line is fitted to nothing.
.dfw_spread_trend <- function(spread_terms, group_cols, min_trend_terms) {
  spread_terms %>%
    dplyr::transmute(dplyr::across(dplyr::all_of(group_cols)), .series = 1L, term,
                     value = spread_var, se = spread_se) %>%
    compute_rate_trend(c(group_cols, ".series"), min_terms = min_trend_terms) %>%
    dplyr::transmute(dplyr::across(dplyr::all_of(group_cols)), n_terms, first_term, last_term,
                     first_spread_pts = sqrt(pmax(fit_first_pct, 0)),
                     last_spread_pts = sqrt(pmax(fit_last_pct, 0)),
                     slope, slope_se, direction)
}

#' How far apart a course's sections are, averaged over its terms
#'
#' @param attempts The attempt measure table (`cedar_attempts`).
#' @param opt prepare_dfw_attempts()' options (`term_type` required, `level`,
#'   `campus`, `from_term`, `to_term`, `data_edges`), plus `min_section_n`
#'   (default 10), `min_sections` (default 3) and `min_trend_terms` (default
#'   4: a spread read in fewer terms gets no direction).
#' @return A list, all of it over every term in scope: `spread_terms` (one row
#'   per course-term read: `campus`, `subject_course`, `term`, `n_sections`,
#'   `n_small_sections` (left out under `min_section_n`), `lo_pct`, `hi_pct`
#'   (its lowest and highest section), `chisq`, `n_attempts`, `n_dfw`,
#'   `dfw_pct`, and `spread_weight`, `spread_var`, `spread_se` (squared
#'   points), `spread_pts`), `spread_courses` (one row per campus-course:
#'   `terms_read`, `sections_per_term`, `lo_pct` and `hi_pct` (its lowest and
#'   highest section, averaged over its terms), `n_attempts`, `n_dfw`,
#'   `dfw_pct`, `spread_var`, `spread_se`, `spread_pts` (its terms pooled),
#'   and its direction: `first_term`, `last_term`, `first_spread_pts`,
#'   `last_spread_pts` (the fitted line's ends, NA without one), `slope`,
#'   `slope_se` (squared points a year), `direction` ("rising" is spreading,
#'   "falling" consolidating, "steady", "too_few_terms"); widest first),
#'   `overall` (`terms`: one row per term, every course pooled: `n_courses`,
#'   `n_attempts`, `n_dfw`, `dfw_pct` and the spread's columns; `trend`: its
#'   line, as a course's, with `n_terms`; `average`: every course and term
#'   pooled, one row: `n_courses`, `n_course_terms`, `sections_per_term`,
#'   `lo_pct`, `hi_pct`, `n_attempts`, `n_dfw`, `dfw_pct` and the spread's
#'   columns; none of the three has a row when no term has a spread); `meta`
#'   (with `n_without_spread`: course-terms of enough sections at a rate of 0
#'   or 100%).
get_dfw_section_spread <- function(attempts, opt = list()) {
  min_section_n <- as.integer(opt$min_section_n %||% 10L)
  min_sections <- as.integer(opt$min_sections %||% 3L)
  min_trend_terms <- as.integer(opt$min_trend_terms %||% 4L)
  rows <- prepare_dfw_attempts(attempts, opt)
  ct_key <- c("campus", "subject_course", "term")

  all_sections <- summarize_attempt_outcomes(rows, c(ct_key, "crn"))
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
      # What the sections' sizes leave to tell them apart: N - sum(n^2) / N.
      spread_weight = sum(n_attempts) - sum(n_attempts^2) / sum(n_attempts),
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
      # Squared points: the chi-square's excess over its degrees of freedom,
      # times a section's chance variance per unit of weight.
      .unit = dfw_pct * (100 - dfw_pct) / spread_weight,
      .has_spread = dfw_pct > 0 & dfw_pct < 100,
      spread_var = dplyr::if_else(.has_spread, (chisq - (n_sections - 1L)) * .unit, NA_real_),
      spread_se = dplyr::if_else(
        .has_spread, sqrt(2 * ((n_sections - 1L) + 2 * pmax(chisq - (n_sections - 1L), 0))) * .unit, NA_real_),
      spread_pts = sqrt(pmax(spread_var, 0))
    ) %>%
    dplyr::select(-.unit, -.has_spread) %>%
    dplyr::relocate(spread_weight, .before = spread_var) %>%
    dplyr::left_join(small, by = ct_key) %>%
    dplyr::mutate(n_small_sections = dplyr::coalesce(n_small_sections, 0L)) %>%
    dplyr::relocate(n_small_sections, .after = n_sections) %>%
    dplyr::arrange(campus, subject_course, term)

  # A course's terms pooled, and its line.
  spread_terms <- dplyr::filter(course_terms, !is.na(spread_var))
  spread_courses <- .dfw_pool_spread(spread_terms, c("campus", "subject_course")) %>%
    dplyr::rename(terms_read = n_course_terms) %>%
    dplyr::left_join(
      dplyr::select(.dfw_spread_trend(spread_terms, c("campus", "subject_course"), min_trend_terms), -n_terms),
      by = c("campus", "subject_course")
    ) %>%
    dplyr::arrange(dplyr::desc(spread_pts), dplyr::desc(n_attempts), campus, subject_course)
  overall_terms <- .dfw_pool_spread(spread_terms, "term") %>%
    dplyr::select(-sections_per_term, -lo_pct, -hi_pct) %>%
    dplyr::rename(n_courses = n_course_terms) %>%
    dplyr::arrange(term)
  # One group, so a scope with no course-term gives no row, as the line does.
  average <- spread_terms %>%
    dplyr::mutate(.all = 1L) %>%
    .dfw_pool_spread(".all") %>%
    dplyr::transmute(n_courses = nrow(spread_courses), dplyr::across(-.all))
  overall <- list(terms = overall_terms,
                  trend = .dfw_spread_trend(overall_terms, character(), min_trend_terms),
                  average = average)

  cedar_debug("[dfw-section-spread.R] ", nrow(spread_terms), " course-terms with a spread in ",
              nrow(overall_terms), " terms, over ", nrow(spread_courses), " campus-courses")
  list(
    spread_terms = spread_terms, spread_courses = spread_courses, overall = overall,
    meta = list(term_type = opt$term_type, level = opt$level %||% "lower", campus = opt$campus,
                graded_edge = attr(rows, "graded_edge"),
                min_section_n = min_section_n, min_sections = min_sections,
                min_trend_terms = min_trend_terms,
                # Course-terms of enough sections at a rate of 0 or 100%: no
                # spread to read.
                n_without_spread = sum(is.na(course_terms$spread_var)))
  )
}
