# later-course.R: Course Dynamics > Downstream > Later Course
#
# Of the students who took the analysed course (X), how many took a later
# course (Y) within a set number of regular terms, when, and how did they do
# in it? The page reads that by the term students took X, by the grade they
# earned in X and, behind the instructor gate, by their instructor in X.
#
# This file assembles the page's payload from two cones and holds everything
# the page shows that is not layout:
#
#   build_later_course()            the payload (get_downstream_outcomes())
#   later_course_balance()          adds the instructor balance check
#                                   (get_downstream_instructor_balance())
#   later_course_headline()         per campus: the two rates and the counts
#                                   they come from, step by step
#   later_course_term_table()       the per-term series
#   later_course_trend()            is each series rising, falling or steady
#   later_course_trend_sentences()  the verdicts in words
#   plot_later_course_trend()       the series as a chart
#   later_course_band_table()       by grade in X
#   later_course_timing_table()     when continuers took Y
#   later_course_instructor_table() by instructor in X (gated on the page)
#   later_course_order_table()      Y passed before or alongside X, by year
#   later_course_scope_note()       which edges bound the page
#   format_later_course()           the payload as text (text-first preview)
#
# The payload is typed and unrounded; the module rounds once, in its column
# definitions. format_later_course() is the one text rendering of it.
#
# Depends on: get_downstream_outcomes() (cones/downstream-outcomes.R)
#             get_downstream_instructor_balance() (cones/downstream-instructor-balance.R)
#             GRADE_LETTER_BANDS, GRADE_BAND_LEVELS (lists/grade_bands.R)
#             fmt_term(), term_axis_factor(), CEDAR_SEMANTIC_COLORS (trunk/utils.R)

# A trend is read from at least this many terms of one type with a rate.
LATER_COURSE_MIN_TREND_TERMS <- 3L

LATER_COURSE_TERM_TYPES <- c("fall", "spring", "summer")

.later_course_check <- function(payload) {
  if (!inherits(payload, "later_course")) {
    stop("[later-course.R] payload must come from build_later_course().", call. = FALSE)
  }
  invisible(payload)
}

.later_course_check_cols <- function(d, required, what) {
  missing <- setdiff(required, names(d))
  if (length(missing) > 0L) {
    stop("[later-course.R] ", what, " is missing columns: ",
         paste(missing, collapse = ", "), call. = FALSE)
  }
  invisible(d)
}

.later_course_window_label <- function(window_terms) {
  paste0(window_terms, " regular term", if (window_terms == 1L) "" else "s")
}

.later_course_n <- function(x) format(as.integer(x), big.mark = ",", scientific = FALSE, trim = TRUE)

.later_course_pct <- function(x) {
  ifelse(is.na(x), "—", paste0(formatC(x, format = "f", digits = 1), "%"))
}

#' The Later Course payload
#'
#' @param students cedar_registrations.
#' @param attempts cedar_attempts.
#' @param opt Named list: `course_x` (the analysed course), `course_y` (the
#'   later course, or a set), `data_edges` (required), `campus` (campuses that
#'   delivered X; NULL for all), `window_terms` (default 3), `min_n` (smallest
#'   denominator a rate is shown for; default 10).
#' @return The output of [get_downstream_outcomes()] with the instructor
#'   breakdown always on it (the page shows it only behind the instructor
#'   gate), `campus` (the scope asked for) and `balance` (NULL until
#'   [later_course_balance()] adds it), classed `later_course`.
build_later_course <- function(students, attempts, opt = list()) {
  cone_opt <- opt[intersect(names(opt), c("course_x", "course_y", "data_edges", "campus",
                                          "window_terms", "min_n"))]
  outcomes <- get_downstream_outcomes(students, attempts, c(cone_opt, list(by_instructor = TRUE)))
  structure(
    c(outcomes, list(campus = opt[["campus"]], balance = NULL)),
    class = c("later_course", "list")
  )
}

#' Add the instructor balance check to a Later Course payload
#'
#' Whether the two largest instructor groups among the students who went on to
#' Y started alike. It changes no rate on the payload.
#'
#' @param payload [build_later_course()] output.
#' @param students,attempts,programs,applicants,student_terms CEDAR tables;
#'   `applicants` may be NULL.
#' @param opt Named list: `data_edges` (required) and `balance_min_n`
#'   (smallest instructor group compared; default 15).
#' @return The payload with `balance` set to
#'   [get_downstream_instructor_balance()]'s output.
later_course_balance <- function(payload, students, attempts, programs, applicants,
                                 student_terms, opt = list()) {
  .later_course_check(payload)
  if (is.null(programs)) stop("[later-course.R] programs is required for the balance check.", call. = FALSE)
  payload$balance <- get_downstream_instructor_balance(
    students, attempts, programs, applicants,
    opt = list(course_x = payload$course_x, course_y = payload$course_y,
               campus = payload$campus, window_terms = payload$window_terms,
               data_edges = opt[["data_edges"]],
               min_n = as.integer(opt[["balance_min_n"]] %||% 15L)),
    student_terms = student_terms
  )
  payload
}

#' Which edges bound the page, in one sentence
#'
#' @param payload [build_later_course()] output.
later_course_scope_note <- function(payload) {
  .later_course_check(payload)
  paste0(
    "Enrollment in ", payload$course_x, " and in ", payload$course_y_label, " is followed through ",
    fmt_term(payload$observation_end), ", the most recent term whose registration has settled; grades are read through ",
    fmt_term(payload$grade_end), ". A student counts only when ",
    .later_course_window_label(payload$window_terms), " after ", payload$course_x,
    " had passed by ", fmt_term(payload$observation_end), "."
  )
}

#' The headline and its arithmetic, one entry per campus that taught X
#'
#' @param payload [build_later_course()] output.
#' @return A list of lists: `campus`, the headline counts and rates, and
#'   `steps`, a tibble (`n`, `label`, `role`) of labelled counts from everyone
#'   who took X down to the pass rate in Y, in the order the page explains
#'   them. `role` is total, removed, denominator, count, outcome, detail or
#'   unknown.
later_course_headline <- function(payload) {
  .later_course_check(payload)
  s <- payload$summary
  .later_course_check_cols(s, c(
    "campus", "n_in_x", "n_right_censored", "n_passed_y_before_x", "n_prior_excluded",
    "n_passed_y_same_term", "n_eligible", "n_took_y", "n_pass", "n_dfw", "n_withdrew",
    "n_not_graded", "n_no_outcome", "n_graded", "pct_took_y", "pct_pass",
    "first_term_x", "last_term_x"
  ), "The later-course summary")
  x <- payload$course_x
  y <- payload$course_y_label
  window <- .later_course_window_label(payload$window_terms)
  single <- !isTRUE(payload$rollup)
  lapply(seq_len(nrow(s)), function(i) {
    r <- s[i, ]
    steps <- tibble::tibble(
      n = c(
        r$n_in_x, r$n_right_censored, if (single) r$n_prior_excluded,
        r$n_eligible, r$n_took_y, r$n_pass, r$n_dfw, r$n_withdrew,
        r$n_not_graded, r$n_no_outcome
      ),
      label = c(
        paste0("took ", x, " through ", fmt_term(payload$observation_end),
               ", counted at their first attempt"),
        paste0("too recent to have had ", window, " to take ", y),
        if (single) paste0("had already passed ", y, " before ", x),
        if (is.na(r$first_term_x)) paste0("could have taken ", y, " within ", window) else
          paste0("could have taken ", y, " within ", window, " (took ", x, " ",
                 fmt_term(r$first_term_x), " to ", fmt_term(r$last_term_x), ")"),
        paste0("took ", y, " within ", window),
        if (single) "passed it" else "passed what they took",
        "DFW, including withdrawals",
        "of them withdrew (late drop or W)",
        paste0("took it after ", fmt_term(payload$grade_end), ", not yet graded"),
        "no recorded outcome (blank or audit)"
      ),
      role = c(
        "total", "removed", if (single) "removed", "denominator", "count",
        "outcome", "outcome", "detail", "unknown", "unknown"
      )
    )
    list(
      campus = r$campus,
      n_in_x = r$n_in_x,
      n_eligible = r$n_eligible,
      n_took_y = r$n_took_y,
      pct_took_y = r$pct_took_y,
      n_graded = r$n_graded,
      n_pass = r$n_pass,
      pct_pass = r$pct_pass,
      n_passed_y_before_x = r$n_passed_y_before_x,
      n_passed_y_same_term = r$n_passed_y_same_term,
      steps = steps
    )
  })
}

#' The term types of X a per-term reading can choose from
#'
#' @param payload [build_later_course()] output.
#' @return Character vector in fall, spring, summer order.
later_course_term_types <- function(payload) {
  .later_course_check(payload)
  intersect(LATER_COURSE_TERM_TYPES, unique(payload$by_term$term_type))
}

.later_course_term_types_arg <- function(payload, term_types) {
  offered <- later_course_term_types(payload)
  if (is.null(term_types)) return(offered)
  unknown <- setdiff(term_types, LATER_COURSE_TERM_TYPES)
  if (length(unknown) > 0L) {
    stop("[later-course.R] Unknown term type: ", paste(unknown, collapse = ", "), call. = FALSE)
  }
  intersect(offered, term_types)
}

#' The per-term series: X's students by the term they took X
#'
#' @param payload [build_later_course()] output.
#' @param term_types Term types of X to keep ("fall", "spring", "summer");
#'   NULL keeps all.
#' @return One row per campus and term of X, oldest first: `campus`, `term_x`,
#'   `term_type`, `n_in_x`, `n_eligible`, `n_took_y`, `pct_took_y`,
#'   `n_graded`, `n_pass`, `pct_pass`, `n_not_graded`. A term whose students
#'   are all too recent keeps its row with no eligible students and no rate.
later_course_term_table <- function(payload, term_types = NULL) {
  .later_course_check(payload)
  .later_course_check_cols(payload$by_term, c(
    "campus", "term_x", "term_type", "n_in_x", "n_eligible", "n_took_y", "pct_took_y",
    "n_graded", "n_pass", "pct_pass", "n_not_graded"
  ), "The later-course per-term table")
  payload$by_term %>%
    dplyr::filter(term_type %in% .later_course_term_types_arg(payload, term_types)) %>%
    dplyr::arrange(campus, term_x) %>%
    dplyr::select(campus, term_x, term_type, n_in_x, n_eligible, n_took_y, pct_took_y,
                  n_graded, n_pass, pct_pass, n_not_graded)
}

# The two rates the page follows over time, long: one row per campus, term of
# X and measure, with the rate's numerator and denominator.
.later_course_series <- function(payload, term_types) {
  rows <- later_course_term_table(payload, term_types)
  dplyr::bind_rows(
    dplyr::transmute(rows, campus, term_type, term_x, measure = "took_y",
                     k = n_took_y, n = n_eligible, pct = pct_took_y),
    dplyr::transmute(rows, campus, term_type, term_x, measure = "pass",
                     k = n_pass, n = n_graded, pct = pct_pass)
  )
}

#' Whether each per-term rate is rising, falling or steady
#'
#' For each campus, term type and measure (the share who took Y, and the pass
#' rate in Y among those graded): the slope of the rate on the year students
#' took X, judged against its standard error. Two things can move a slope
#' without the rate having a direction, and the error is the larger of the
#' two: chance (each term's binomial error if the rate were the pooled rate
#' every term), and the terms' own scatter around the fitted line (a dip and
#' recovery in a large course is far outside binomial chance and is still not
#' a trend). Beyond two standard errors is a trend; inside is steady. Term
#' types are never mixed: a Fall cohort and a Spring one are different
#' students.
#'
#' @param payload [build_later_course()] output.
#' @param term_types Term types of X to read; NULL reads all.
#' @return One row per campus, term type and measure with at least one term
#'   holding a rate: `campus`, `term_type`, `measure` ("took_y" / "pass"),
#'   `n_terms`, `first_term`, `first_pct`, `last_term`, `last_pct`,
#'   `pooled_pct`, `slope` (points a year), `se_chance`, `se_scatter`,
#'   `slope_se` (the larger of the two) and `direction` ("rising", "falling",
#'   "steady", or "too_few_terms" under LATER_COURSE_MIN_TREND_TERMS, where
#'   the slope and its errors are NA).
later_course_trend <- function(payload, term_types = NULL) {
  .later_course_series(payload, term_types) %>%
    dplyr::filter(!is.na(pct)) %>%
    dplyr::mutate(
      year = term_x %/% 100L,
      measure = factor(measure, levels = c("took_y", "pass")),
      term_type = factor(term_type, levels = LATER_COURSE_TERM_TYPES)
    ) %>%
    dplyr::group_by(campus, term_type, measure) %>%
    dplyr::arrange(term_x, .by_group = TRUE) %>%
    dplyr::summarize(
      n_terms = dplyr::n(),
      first_term = dplyr::first(term_x),
      first_pct = dplyr::first(pct),
      last_term = dplyr::last(term_x),
      last_pct = dplyr::last(pct),
      pooled_pct = 100 * sum(k) / sum(n),
      .sxx = sum((year - mean(year))^2),
      .sxy = sum((year - mean(year)) * pct),
      .syy = sum((pct - mean(pct))^2),
      # Each term's variance at the pooled rate, in squared points.
      .svar = sum((year - mean(year))^2 * pooled_pct * (100 - pooled_pct) / n),
      .groups = "drop"
    ) %>%
    dplyr::mutate(
      enough = n_terms >= LATER_COURSE_MIN_TREND_TERMS,
      slope = dplyr::if_else(enough, .sxy / .sxx, NA_real_),
      se_chance = dplyr::if_else(enough, sqrt(.svar) / .sxx, NA_real_),
      # What is left around the line, per term beyond the two the line uses.
      se_scatter = dplyr::if_else(
        enough, sqrt(pmax(.syy - .sxy^2 / .sxx, 0) / pmax(n_terms - 2L, 1L) / .sxx), NA_real_),
      slope_se = pmax(se_chance, se_scatter),
      direction = dplyr::case_when(
        !enough ~ "too_few_terms",
        slope > 2 * slope_se ~ "rising",
        slope < -2 * slope_se ~ "falling",
        TRUE ~ "steady"
      ),
      measure = as.character(measure),
      term_type = as.character(term_type)
    ) %>%
    dplyr::select(campus, term_type, measure, n_terms, first_term, first_pct, last_term,
                  last_pct, pooled_pct, slope, se_chance, se_scatter, slope_se, direction)
}

#' The trend verdicts in words
#'
#' The first and last terms' rates are stated as they are; the verdict is the
#' fitted line's across every term, so the sentence says so: the two can
#' point different ways.
#'
#' @param payload [build_later_course()] output.
#' @param term_types Term types of X to read; NULL reads all.
#' @return Character vector, one sentence per campus, term type and measure.
#'   Zero-length when no term holds a rate.
later_course_trend_sentences <- function(payload, term_types = NULL) {
  trend <- later_course_trend(payload, term_types)
  if (nrow(trend) == 0L) return(character(0))
  y <- payload$course_y_label
  window <- .later_course_window_label(payload$window_terms)
  what <- c(
    took_y = paste0("the share taking ", y, " within ", window),
    pass = if (isTRUE(payload$rollup)) "the pass rate among those graded in what they took" else
      paste0("the pass rate in ", y, " among those graded")
  )
  verdict <- c(rising = "an upward trend", falling = "a downward trend",
               steady = "no trend beyond that")
  vapply(seq_len(nrow(trend)), function(i) {
    t <- trend[i, ]
    lead <- paste0(t$campus, ", ", tools::toTitleCase(t$term_type), " terms of ", payload$course_x, ": ",
                   what[[t$measure]])
    if (t$direction == "too_few_terms") {
      return(paste0(lead, " has a rate in ", t$n_terms, " term", if (t$n_terms == 1L) "" else "s",
                    "; a trend is read from ", LATER_COURSE_MIN_TREND_TERMS, " or more."))
    }
    paste0(
      lead, " was ", .later_course_pct(t$first_pct), " for ", fmt_term(t$first_term), " and ",
      .later_course_pct(t$last_pct), " for ", fmt_term(t$last_term), ". Across the ", t$n_terms,
      " terms the fitted line moves ", sprintf("%+.1f", t$slope),
      " points a year, where chance and the terms' own scatter give about ",
      sprintf("%.1f", 2 * t$slope_se), ": ", verdict[[t$direction]], "."
    )
  }, character(1))
}

#' The two rates by the term students took X
#'
#' One line per campus, measure and term type: the share who took Y within
#' the window, and the pass rate in Y among those graded. A line never joins
#' a Fall term to a Spring one: with several term types drawn each has its own
#' line, named for it. Measures differ by colour, campuses by line style, term
#' types by marker.
#'
#' @param payload [build_later_course()] output.
#' @param term_types Term types of X to draw; NULL draws all.
#' @return A plotly object, or NULL when no term has a rate to show.
plot_later_course_trend <- function(payload, term_types = NULL) {
  series <- .later_course_series(payload, term_types) %>% dplyr::filter(!is.na(pct))
  if (nrow(series) == 0L) return(NULL)
  series <- series %>%
    dplyr::arrange(term_x) %>%
    dplyr::mutate(term_label = term_axis_factor(term_x))
  campuses <- sort(unique(series$campus))
  dashes <- rep_len(c("solid", "dot", "dash", "dashdot"), length(campuses))
  types <- intersect(LATER_COURSE_TERM_TYPES, unique(series$term_type))
  symbols <- c(fall = "circle", spring = "square", summer = "diamond")
  measures <- list(
    took_y = list(
      name = paste0("Took ", payload$course_y_label),
      color = unname(CEDAR_SEMANTIC_COLORS["neutral"]),
      hover = "%{x}<br>Took it: %{y:.1%} of %{customdata}<extra>%{fullData.name}</extra>"
    ),
    pass = list(
      name = if (isTRUE(payload$rollup)) "Passed what they took" else "Passed it",
      color = unname(CEDAR_SEMANTIC_COLORS["positive"]),
      hover = "%{x}<br>Passed: %{y:.1%} of %{customdata} graded<extra>%{fullData.name}</extra>"
    )
  )
  p <- plotly::plot_ly()
  for (m in names(measures)) {
    for (i in seq_along(campuses)) {
      for (type in types) {
        rows <- series[series$measure == m & series$campus == campuses[[i]] &
                         series$term_type == type, , drop = FALSE]
        if (nrow(rows) == 0L) next
        p <- plotly::add_trace(
          p, data = rows, x = ~term_label, y = ~pct / 100, customdata = ~n,
          type = "scatter", mode = "lines+markers",
          name = paste(c(measures[[m]]$name,
                         if (length(campuses) > 1L) campuses[[i]],
                         if (length(types) > 1L) tools::toTitleCase(type)), collapse = ", "),
          line = list(color = measures[[m]]$color, dash = dashes[[i]]),
          marker = list(color = measures[[m]]$color, symbol = symbols[[type]]),
          hovertemplate = measures[[m]]$hover
        )
      }
    }
  }
  plotly::layout(
    p,
    xaxis = list(title = paste0("Term of ", payload$course_x), tickangle = -45,
                 categoryorder = "array", categoryarray = levels(series$term_label)),
    yaxis = list(title = "", tickformat = ".0%", range = c(0, 1.05)),
    legend = list(orientation = "h", x = 0, y = -0.3)
  )
}

#' Results in Y by the grade students earned in X
#'
#' @param payload [build_later_course()] output.
#' @return One row per campus and grade band with anyone eligible, bands in
#'   GRADE_BAND_LEVELS order.
later_course_band_table <- function(payload) {
  .later_course_check(payload)
  .later_course_check_cols(payload$by_grade, c(
    "campus", "x_band", "n_eligible", "n_took_y", "pct_took_y", "n_graded", "n_pass", "pct_pass"
  ), "The later-course grade-band table")
  payload$by_grade %>%
    dplyr::filter(n_eligible > 0) %>%
    dplyr::arrange(campus, match(x_band, GRADE_BAND_LEVELS)) %>%
    dplyr::select(campus, x_band, n_eligible, n_took_y, pct_took_y, n_graded, n_pass, pct_pass)
}

#' When continuers took Y, by regular terms after X
#'
#' @param payload [build_later_course()] output.
#' @return One row per campus and step, labelled in words.
later_course_timing_table <- function(payload) {
  .later_course_check(payload)
  .later_course_check_cols(payload$timing, c(
    "campus", "gap_terms", "n", "pct_of_continuers", "cum_pct_of_eligible"
  ), "The later-course timing table")
  payload$timing %>%
    dplyr::arrange(campus, gap_terms) %>%
    dplyr::mutate(when = dplyr::if_else(
      gap_terms == 1L, "The next regular term", paste0(gap_terms, " regular terms later")
    )) %>%
    dplyr::select(campus, when, n, pct_of_continuers, cum_pct_of_eligible)
}

#' The breakdown by instructor in X
#'
#' Each instructor's X results sit beside their students' Y results, and the
#' pass rate in Y is repeated for students with the same letter grade in X, so
#' an instructor who sent a stronger set of students on is not mistaken for
#' one who prepared them better.
#'
#' @param payload [build_later_course()] output.
#' @return One row per campus and instructor with anyone eligible, largest
#'   first. `pass_<band>` / `graded_<band>` hold the pass rate in Y and its
#'   denominator for each letter band of GRADE_LETTER_BANDS.
later_course_instructor_table <- function(payload) {
  .later_course_check(payload)
  if (is.null(payload$instructors) || is.null(payload$instructors_by_grade)) {
    stop("[later-course.R] This payload has no instructor breakdown.", call. = FALSE)
  }
  .later_course_check_cols(payload$instructors, c(
    "campus", "instructor", "n_eligible", "pct_x_pass", "pct_x_a_or_b", "n_took_y",
    "pct_took_y", "n_graded", "n_pass", "pct_pass", "n_dfw", "pct_dfw"
  ), "The later-course instructor breakdown")
  bands <- names(GRADE_LETTER_BANDS)
  by_band <- payload$instructors_by_grade %>%
    dplyr::filter(x_band %in% bands) %>%
    dplyr::mutate(x_band = factor(x_band, levels = bands)) %>%
    dplyr::select(campus, instructor, x_band, n_graded, pct_pass) %>%
    tidyr::pivot_wider(names_from = x_band, values_from = c(pct_pass, n_graded),
                       names_glue = "{.value}_{x_band}", names_expand = TRUE)
  names(by_band) <- sub("^pct_pass_", "pass_", names(by_band))
  names(by_band) <- sub("^n_graded_", "graded_", names(by_band))
  # An instructor whose students are all too recent has nothing to show; the
  # headline's arithmetic already counts them.
  payload$instructors %>%
    dplyr::filter(n_eligible > 0) %>%
    dplyr::select(campus, instructor, n_eligible, pct_x_pass, pct_x_a_or_b,
                  n_took_y, pct_took_y, n_graded, n_pass, pct_pass, n_dfw, pct_dfw) %>%
    dplyr::left_join(by_band, by = c("campus", "instructor")) %>%
    dplyr::mutate(dplyr::across(dplyr::starts_with("graded_"), ~ dplyr::coalesce(.x, 0L))) %>%
    dplyr::arrange(campus, dplyr::desc(n_eligible), instructor)
}

#' Students who had passed Y before or alongside X, by academic year
#'
#' @param payload [build_later_course()] output.
#' @return One row per campus and academic year of the first X attempt:
#'   `campus`, `acad_year`, `students_taking_x`, `passed_y_before_x`,
#'   `passed_y_same_term`, `passed_y_before_or_same` (their union) and
#'   `pct_before_or_same`.
later_course_order_table <- function(payload) {
  .later_course_check(payload)
  cols <- c("campus", "acad_year", "students_taking_x", "passed_y_before_x",
            "passed_y_same_term", "passed_y_before_or_same", "pct_before_or_same")
  .later_course_check_cols(payload$order_by_year, cols, "The later-course order check")
  payload$order_by_year[, cols]
}

#' The Later Course payload as plain text (the text-first preview)
#'
#' @param payload [build_later_course()] output.
#' @param instructors TRUE adds the instructor breakdown, which names
#'   instructors beside student outcomes. Default FALSE.
#' @return Character vector of lines.
format_later_course <- function(payload, instructors = FALSE) {
  .later_course_check(payload)
  x <- payload$course_x
  y <- payload$course_y_label
  n <- .later_course_n
  pct <- .later_course_pct
  rate <- function(k, d, p) paste0(pct(p), " (", n(k), " of ", n(d), ")")
  lines <- c(
    paste0(x, " -> ", y, ", within ", .later_course_window_label(payload$window_terms)),
    if (isTRUE(payload$rollup)) paste0("Later courses: ", paste(payload$course_y, collapse = ", ")),
    later_course_scope_note(payload),
    paste0("A rate is shown for ", payload$min_n, " or more students.")
  )
  for (h in later_course_headline(payload)) {
    lines <- c(
      lines, "", paste0(x, " taught on ", h$campus),
      sprintf("  %7s  %s", n(h$steps$n), h$steps$label),
      paste0("  Took ", y, ": ", rate(h$n_took_y, h$n_eligible, h$pct_took_y),
             "; passed, of those graded: ", rate(h$n_pass, h$n_graded, h$pct_pass))
    )
  }
  terms <- later_course_term_table(payload)
  lines <- c(
    lines, "", paste0("By term of ", x, ":"),
    sprintf("  %-4s %-12s in X %5s  could %5s  took %-22s  passed %-22s  not graded %s",
            terms$campus, fmt_term(terms$term_x), n(terms$n_in_x), n(terms$n_eligible),
            rate(terms$n_took_y, terms$n_eligible, terms$pct_took_y),
            rate(terms$n_pass, terms$n_graded, terms$pct_pass), n(terms$n_not_graded)),
    paste0("  ", later_course_trend_sentences(payload))
  )
  bands <- later_course_band_table(payload)
  lines <- c(
    lines, "", paste0("By grade in ", x, ":"),
    sprintf("  %-4s %-17s could %5s  took %-22s  passed %s",
            bands$campus, bands$x_band, n(bands$n_eligible),
            rate(bands$n_took_y, bands$n_eligible, bands$pct_took_y),
            rate(bands$n_pass, bands$n_graded, bands$pct_pass))
  )
  timing <- later_course_timing_table(payload)
  lines <- c(
    lines, "", paste0("When they took ", y, ":"),
    sprintf("  %-4s %-24s %5s  %s of continuers, %s of all who could by then",
            timing$campus, timing$when, n(timing$n), pct(timing$pct_of_continuers),
            pct(timing$cum_pct_of_eligible))
  )
  order <- later_course_order_table(payload)
  lines <- c(
    lines, "", paste0("Passed ", y, " before or with ", x, ", by academic year:"),
    sprintf("  %-4s %-9s took X %5s  before %4s  same term %4s  either %4s",
            order$campus, order$acad_year, n(order$students_taking_x), n(order$passed_y_before_x),
            n(order$passed_y_same_term), n(order$passed_y_before_or_same))
  )
  if (isTRUE(instructors)) {
    inst <- later_course_instructor_table(payload)
    lines <- c(
      lines, "", paste0("By instructor in ", x, ":"),
      sprintf("  %-4s %-26s could %5s  passed X %6s  A or B %6s  took %-22s  passed %s",
              inst$campus, inst$instructor, n(inst$n_eligible), pct(inst$pct_x_pass),
              pct(inst$pct_x_a_or_b), rate(inst$n_took_y, inst$n_eligible, inst$pct_took_y),
              rate(inst$n_pass, inst$n_graded, inst$pct_pass))
    )
  }
  lines
}

# Null-coalescing operator - define only if not already loaded.
if (!exists("%||%")) {
  `%||%` <- function(a, b) if (!is.null(a)) a else b
}
