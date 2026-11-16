# Which courses hold the DFW grades, and how is each one moving?
#
# Over the last `n_window` terms of one term type, every course on every
# campus (a campus-course is the grain: a course taught on two campuses is two
# rows): its attempts, DFW grades and rate, and its share of all the DFW
# grades in scope, ranked by count, because the count is where the students
# are; a small course can have a high rate and few of them. Beside it, the
# course's whole history of that term type: the trend of its rate
# (compute_rate_trend(), every term with `min_term_n` attempts) and whether
# its terms swing around that line more than courses usually do.
#
# Swings are calibrated to the board's own noise. Every course's rate moves
# from term to term by more than binomial chance (a new instructor, a
# different cohort), so chance alone calls nearly every large course a
# swinger. The board measures the typical course's scatter beyond chance
# (`typical_extra_sd`: the median, over the courses with a trend, of the
# scatter's variance beyond chance), and a course `swings` when its scatter
# is beyond chance plus that typical amount. Every course with a trend is
# tested at once, so the bar is DFW_SWING_FAMILY_P shared across them
# (Bonferroni): on the whole board, about a 1-in-20 chance that even one
# course is called a swinger by luck. A course swings, then, when it swings
# more than this institution's courses do, by more than luck explains. On
# UNM's lower division (2026-11-15) the typical course moves about 4 points
# a term beyond chance, and 17 of 448 fall courses swing (7 of 413 spring);
# chance alone called 121.
#
# Exported functions:
#   get_dfw_course_board(attempts, opt)

DFW_SWING_FAMILY_P <- 0.05

#' The courses ranked by DFW grades, with their trends
#'
#' @param attempts The attempt measure table (`cedar_attempts`).
#' @param opt prepare_dfw_attempts()' options (`term_type` required, `level`,
#'   `campus`, `data_edges`), plus `n_window` (default 3 terms), `min_window_n`
#'   (default 50: a course is `listed` with this many attempts in the window),
#'   `min_term_n` (default 30) and `min_trend_terms` (default 4).
#' @return A list: `courses` (one row per campus-course with an attempt in
#'   the window, most DFW grades first: `rank`, `campus`, `college` (the code
#'   most of its window attempts carry), `subject_course`,
#'   summarize_attempt_outcomes()' columns, `dfw_share` and `cum_share` (of the window's DFW grades,
#'   0-1), `listed`, the trend's columns (compute_rate_trend()), `swing_p`
#'   and `swings`),
#'   `terms` (every term of the type for each of those courses:
#'   `n_attempts`, `n_dfw`, `dfw_pct`, `in_trend`, the series its trend is
#'   read from),
#'   `totals` (`n_courses`, `n_attempts`, `n_dfw`, `dfw_pct`,
#'   `courses_for_quarter`, `courses_for_half`: how many courses, from the
#'   top, hold a quarter and half of the DFW grades), `meta` (`window_terms`,
#'   `graded_edge`, `typical_extra_sd` (points a term), `n_swing_tests`,
#'   `swing_p_cut` and the options).
get_dfw_course_board <- function(attempts, opt = list()) {
  n_window <- opt$n_window %||% 3L
  min_window_n <- as.integer(opt$min_window_n %||% 50L)
  min_term_n <- as.integer(opt$min_term_n %||% 30L)
  min_trend_terms <- as.integer(opt$min_trend_terms %||% 4L)
  rows <- prepare_dfw_attempts(attempts, opt)
  window <- dfw_window_terms(rows, n_window)
  in_window <- rows %>% dplyr::filter(term %in% .env$window)
  key <- c("campus", "subject_course")

  college <- in_window %>%
    dplyr::count(campus, subject_course, college, name = ".n") %>%
    dplyr::arrange(dplyr::desc(.n), college) %>%
    dplyr::distinct(campus, subject_course, .keep_all = TRUE) %>%
    dplyr::select(-.n)

  course_terms <- summarize_attempt_outcomes(rows, c(key, "term")) %>%
    dplyr::mutate(in_trend = n_attempts >= min_term_n)
  trend <- course_terms %>%
    dplyr::filter(in_trend) %>%
    dplyr::transmute(campus, subject_course, term, k = n_dfw, n = n_attempts) %>%
    compute_rate_trend(key, min_terms = min_trend_terms)
  extra_var <- pmax(trend$resid_sd^2 - trend$chance_var, 0)
  typical_extra_var <- if (any(!is.na(extra_var))) stats::median(extra_var, na.rm = TRUE) else NA_real_
  trend <- trend %>%
    dplyr::mutate(
      swing_p = stats::pchisq((n_terms - 2L) * resid_sd^2 / (chance_var + .env$typical_extra_var),
                              df = n_terms - 2L, lower.tail = FALSE),
      swings = !is.na(swing_p) & swing_p < DFW_SWING_FAMILY_P / max(sum(!is.na(swing_p)), 1L)
    )
  n_swing_tests <- sum(!is.na(trend$swing_p))

  total_dfw <- sum(in_window$is_dfw_legacy)
  courses <- summarize_attempt_outcomes(in_window, key) %>%
    dplyr::left_join(college, by = key) %>%
    dplyr::arrange(dplyr::desc(n_dfw), dplyr::desc(n_attempts), campus, subject_course) %>%
    dplyr::mutate(
      rank = dplyr::row_number(),
      dfw_share = if (total_dfw > 0) n_dfw / total_dfw else NA_real_,
      cum_share = cumsum(dfw_share),
      listed = n_attempts >= min_window_n
    ) %>%
    dplyr::left_join(trend, by = key) %>%
    dplyr::mutate(swings = dplyr::coalesce(swings, FALSE)) %>%
    dplyr::relocate(rank, campus, college, subject_course)

  first_to <- function(share) {
    hit <- which(courses$cum_share >= share - 1e-9)
    if (length(hit)) hit[[1]] else NA_integer_
  }
  cedar_debug("[dfw-course-board.R] ", nrow(courses), " campus-courses, ", total_dfw, " DFW in ",
              paste(window, collapse = ", "))
  list(
    courses = courses,
    terms = course_terms %>%
      dplyr::semi_join(courses, by = key) %>%
      dplyr::select(campus, subject_course, term, n_attempts, n_dfw, dfw_pct, in_trend) %>%
      dplyr::arrange(campus, subject_course, term),
    totals = list(n_courses = nrow(courses), n_attempts = nrow(in_window), n_dfw = total_dfw,
                  dfw_pct = 100 * total_dfw / nrow(in_window),
                  courses_for_quarter = first_to(0.25), courses_for_half = first_to(0.5)),
    meta = list(term_type = opt$term_type, level = opt$level %||% "lower", campus = opt$campus,
                window_terms = sort(window), graded_edge = attr(rows, "graded_edge"),
                min_window_n = min_window_n, min_term_n = min_term_n, min_trend_terms = min_trend_terms,
                typical_extra_sd = sqrt(typical_extra_var), n_swing_tests = n_swing_tests,
                swing_p_cut = DFW_SWING_FAMILY_P / max(n_swing_tests, 1L))
  )
}
