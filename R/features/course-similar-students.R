# course-similar-students.R — a course against similar non-takers, in context
#
# Assembles get_course_similar_students() (cones/course-similar-students.R)
# into the payload behind "do students who take this course do better than
# students like them who do not, and is that unusual?": the focal course's
# row, the same row for every course the population takes (the benchmark:
# taking almost any course goes with returning, so a gap is read against the
# other courses' gaps, never against zero), and the focal course's
# instructors against the course's non-takers.
#
# The payload is typed; format_course_similar_students() is the one text
# rendering (the text-first preview), and the page and tests read the payload.
#
# Depends on: get_course_similar_students() (cones/course-similar-students.R)

#' Who a course's takers are compared with
#'
#' The named comparisons the page offers: every similar student who did not
#' take the course, or only those who took a Gen Ed course that term (the
#' institution's gen_ed_courses.csv) -- for a course outside Gen Ed, "did its
#' students do better than students like them in Gen Ed courses?".
#'
#' @return Named character vector, comparison id to the words the page uses
#'   for the compared students.
course_similar_comparisons <- function() {
  c(all = "similar students who did not take it",
    gen_ed = "similar students who took a Gen Ed course that term and not this one")
}


#' A course against similar non-takers, beside every other course and by instructor
#'
#' @param student_terms `cedar_student_terms`.
#' @param attempts `cedar_attempts`.
#' @param applicants `cedar_applicants`.
#' @param opt `course` (the focal course id; required), `classification`
#'   (required), `term`, `campus`, `comparison` (who the non-takers are, one
#'   of course_similar_comparisons(): "all", the default, or "gen_ed"), `min_n`
#'   (covered takers a course or an instructor needs; default 30),
#'   `min_cell_n`, `data_edges` (required).
#' @return A `course_similar_students` list: `meta`; `focal` (the course's
#'   one row, or NULL when it has fewer than `min_n` covered takers);
#'   `courses` (every course at `min_n`, the focal one among them, with
#'   `is_focal`); `benchmark` (one row per outcome: `n_courses`, `q1`,
#'   `median`, `q3` of the courses' gaps, `focal_gap`, `share_below`);
#'   `instructors` (the focal course's instructors at `min_n`) and
#'   `instructor_spread` (`n_instructors`, `sd_return_gap`, `mean_se`,
#'   `n_beyond_2se`; NULL under two instructors); `courses_by_term` (every
#'   course's row per anchor term at `min_term_n` covered takers, default
#'   10) and `by_term` (the focal course's); `trends`
#'   (`course_similar_students_trend()` over every course, in
#'   `meta$trend_term_type`, the regular term type with the most covered
#'   takers) and `trend` (the focal course's rows). `courses` carries its
#'   return-gap trend: `return_trend`, `return_trend_slope`,
#'   `return_trend_chance` (two standard errors) and `return_gap_series` (the
#'   gaps in term order, a list column).
build_course_similar_students <- function(student_terms, attempts, applicants, opt = list()) {
  course <- opt$course
  if (is.null(course) || length(course) != 1L || is.na(course) || !nzchar(course)) {
    stop("[course-similar-students.R] opt$course (one focal course id) is required.", call. = FALSE)
  }
  comparison <- opt$comparison %||% "all"
  if (length(comparison) != 1L || !comparison %in% names(course_similar_comparisons())) {
    stop("[course-similar-students.R] opt$comparison must be one of ",
         paste(names(course_similar_comparisons()), collapse = ", "), call. = FALSE)
  }
  cone_opt <- opt[intersect(names(opt), c("classification", "term", "campus", "min_n", "min_cell_n", "data_edges"))]
  if (comparison == "gen_ed") {
    # The Gen Ed list names registrar codes; the loaded attempts key on the
    # course id, their subject_course (a renamed Gen Ed course is one course).
    if (!"listed_code" %in% names(attempts)) {
      stop("[course-similar-students.R] attempts lacks listed_code, which the Gen Ed comparison ",
           "resolves its codes through.", call. = FALSE)
    }
    # CAMPUS_ROLLUP: a code-to-course lookup, not a count; a code names one
    # course on every campus.
    keyed <- dplyr::distinct(dplyr::transmute(attempts, course_id = subject_course, listed_code))
    cone_opt$comparison_courses <- course_ids_of(unlist(gen_ed_all, use.names = FALSE), keyed,
                                                 caller = "build_course_similar_students")
  }
  courses <- get_course_similar_students(student_terms, attempts, applicants, cone_opt)
  min_n <- as.integer(opt$min_n %||% 30L)
  suppressed <- attr(courses, "suppressed")
  meta <- list(
    course = course,
    classification = opt$classification,
    term = opt$term, campus = opt$campus,
    comparison = comparison,
    comparison_courses = attr(courses, "comparison_courses"),
    n_comparison_student_terms = attr(courses, "n_comparison_student_terms"),
    min_n = min_n, min_cell_n = as.integer(opt$min_cell_n %||% 5L),
    edge = attr(courses, "edge"), graded_edge = attr(courses, "graded_edge"),
    n_population_student_terms = attr(courses, "n_population_student_terms"),
    focal_under_min_n = suppressed[suppressed$course == course, , drop = FALSE]
  )
  # Every course term by term, so each course's gaps read as a series and a
  # trend, fitted within one regular term type.
  term_opt <- cone_opt
  term_opt$min_n <- as.integer(opt$min_term_n %||% 10L)
  courses_by_term <- get_course_similar_students(
    student_terms, attempts, applicants, c(term_opt, list(by_term = TRUE))
  )
  meta$min_term_n <- term_opt$min_n
  regular <- courses_by_term %>%
    mutate(term_type = get_term_type(term)) %>%
    filter(term_type %in% c("fall", "spring"))
  covered_by_type <- tapply(regular$n_covered, regular$term_type, sum)
  meta$trend_term_type <- if (length(covered_by_type)) names(covered_by_type)[which.max(covered_by_type)] else NA_character_
  trends <- course_similar_students_trend(courses_by_term, meta$trend_term_type)
  series <- regular %>%
    filter(term_type == meta$trend_term_type, !is.na(return_gap)) %>%
    arrange(course, term) %>%
    group_by(course) %>%
    summarize(return_gap_series = list(return_gap), .groups = "drop")
  courses <- courses %>%
    mutate(is_focal = course == .env$course) %>%
    left_join(trends %>% filter(outcome == "return") %>%
                transmute(course, return_trend = direction, return_trend_slope = slope,
                          return_trend_chance = 2 * slope_se),
              by = "course") %>%
    left_join(series, by = "course")
  focal <- courses %>% filter(is_focal)
  if (nrow(focal) == 0L) focal <- NULL

  others <- courses %>% filter(!is_focal)
  bench_row <- function(outcome, col) {
    gaps <- others[[col]][!is.na(others[[col]])]
    focal_gap <- if (is.null(focal)) NA_real_ else focal[[col]]
    tibble::tibble(
      outcome = outcome, n_courses = length(gaps),
      q1 = if (length(gaps)) unname(stats::quantile(gaps, 0.25)) else NA_real_,
      median = if (length(gaps)) stats::median(gaps) else NA_real_,
      q3 = if (length(gaps)) unname(stats::quantile(gaps, 0.75)) else NA_real_,
      focal_gap = focal_gap,
      share_below = if (length(gaps) && !is.na(focal_gap)) mean(gaps < focal_gap) else NA_real_
    )
  }
  benchmark <- bind_rows(
    bench_row("return", "return_gap"),
    bench_row("other_dfw", "other_dfw_gap"),
    bench_row("next_gpa", "next_gpa_gap")
  )

  instructors <- get_course_similar_students(
    student_terms, attempts, applicants,
    c(cone_opt, list(course = course, grain = "instructor"))
  ) %>% filter(!is.na(instructor_id))
  spread <- NULL
  measured <- instructors %>% filter(!is.na(return_gap), !is.na(return_gap_se), return_gap_se > 0)
  if (nrow(measured) >= 2L) {
    spread <- list(
      n_instructors = nrow(measured),
      sd_return_gap = stats::sd(measured$return_gap),
      mean_se = mean(measured$return_gap_se),
      n_beyond_2se = sum(abs(measured$return_gap - mean(measured$return_gap)) > 2 * measured$return_gap_se)
    )
  }

  structure(list(meta = meta, focal = focal, courses = courses, benchmark = benchmark,
                 instructors = instructors, instructor_spread = spread,
                 courses_by_term = courses_by_term,
                 by_term = courses_by_term %>% filter(course == .env$course),
                 trends = trends, trend = trends %>% filter(course == .env$course)),
            class = "course_similar_students")
}

#' The similar-students result as sentences
#'
#' @param payload `build_course_similar_students()` output.
#' @return Character vector: the return gap with its counts and chance band;
#'   the other-course DFW and next-term GPA gaps; where the return gap sits
#'   among the other courses; and, with two or more instructors, how far the
#'   instructors' gaps spread beyond chance.
course_similar_students_headline <- function(payload) {
  if (!inherits(payload, "course_similar_students")) {
    stop("[course-similar-students.R] payload must come from build_course_similar_students().", call. = FALSE)
  }
  meta <- payload$meta
  f <- payload$focal
  fmt_n <- function(n) format(as.integer(n), big.mark = ",", trim = TRUE)
  pct <- function(p) sprintf("%.1f%%", p)
  pts <- function(p) sprintf("%+.1f", p)
  if (is.null(f)) {
    under <- meta$focal_under_min_n
    return(paste0(
      meta$course, " has ", if (nrow(under) == 0L) "no" else fmt_n(under$n_covered),
      " takers in this population with comparable non-takers, under the ", meta$min_n,
      " this comparison needs."
    ))
  }
  like <- if (identical(meta$comparison, "gen_ed")) {
    "students of the same term, home campus, high-school GPA band and time status who took a Gen Ed course and not this one"
  } else "non-takers of the same term, home campus, high-school GPA band and time status"
  sentences <- if (is.na(f$return_gap)) {
    paste0("No return is observable yet for the ", fmt_n(f$n_covered), " students who took ", meta$course, ".")
  } else {
    paste0(
      "Of ", fmt_n(f$return_n), " students who took ", meta$course, ", ", pct(f$return_pct),
      " returned the next regular term, against ", pct(f$return_expected_pct), " expected from ", like,
      ": a gap of ", pts(f$return_gap), " points, where chance alone moves it about ",
      sprintf("%.1f", 2 * f$return_gap_se), "."
    )
  }
  second <- c(
    if (!is.na(f$other_dfw_gap)) paste0(
      "in their other courses that term they did not pass ", pct(f$other_dfw_pct), " of attempts against ",
      pct(f$other_dfw_expected_pct), " expected (", pts(f$other_dfw_gap), " points)"),
    if (!is.na(f$next_gpa_gap)) paste0(
      "those who returned earned a next-term GPA of ", sprintf("%.2f", f$next_gpa), " against ",
      sprintf("%.2f", f$next_gpa_expected), " expected")
  )
  if (length(second) > 0) {
    second <- paste0(paste(second, collapse = "; "), ".")
    sentences <- c(sentences, paste0(toupper(substr(second, 1, 1)), substring(second, 2)))
  }
  if (identical(meta$comparison, "gen_ed")) {
    sentences <- c(sentences, paste0(
      "The compared students come from the ", fmt_n(meta$n_comparison_student_terms), " of ",
      fmt_n(meta$n_population_student_terms), " student-terms in this population with a Gen Ed course that term (",
      sprintf("%.0f%%", 100 * meta$n_comparison_student_terms / meta$n_population_student_terms), ")."
    ))
  }
  b <- payload$benchmark[payload$benchmark$outcome == "return", , drop = FALSE]
  if (b$n_courses > 0L && !is.na(b$share_below)) {
    sentences <- c(sentences, paste0(
      "Taking almost any course goes with returning: across the ", fmt_n(b$n_courses),
      " other courses these students took, the median return gap is ", pts(b$median), " points, and ",
      meta$course, "'s is larger than ", sprintf("%.0f%%", 100 * b$share_below), " of them."
    ))
  }
  s <- payload$instructor_spread
  if (!is.null(s)) {
    sentences <- c(sentences, paste0(
      "Its ", s$n_instructors, " instructors with ", meta$min_n, " or more takers differ by ",
      sprintf("%.1f", s$sd_return_gap), " points in return gap (standard deviation) where chance alone gives about ",
      sprintf("%.1f", s$mean_se), "; ", s$n_beyond_2se,
      " sit more than two standard errors from the instructors' average."
    ))
  }
  tr <- payload$trend
  if (!is.null(tr) && any(tr$direction != "too_few_terms")) {
    verdict <- c(rising = "rising", falling = "falling", steady = "no trend beyond chance")
    say <- function(outcome, label, unit, digits) {
      r <- tr[tr$outcome == outcome & tr$direction != "too_few_terms", , drop = FALSE]
      if (nrow(r) == 0L) return(NULL)
      signed <- function(x) sprintf(paste0("%+.", digits, "f"), x)
      paste0(label, " went from ", signed(r$first_gap), unit, " in ", fmt_term(r$first_term), " to ",
             signed(r$last_gap), " in ", fmt_term(r$last_term), " over ", r$n_terms, " terms: ",
             verdict[[r$direction]], " (", signed(r$slope), " a year; a trend needs more than ±",
             sprintf(paste0("%.", digits, "f"), 2 * r$slope_se), ").")
    }
    type <- tools::toTitleCase(tr$term_type[1])
    parts <- c(say("return", paste0(type, " to ", tolower(type), ", the return gap"), " points", 1),
               say("other_dfw", "The other-course DFW gap", " points", 1),
               say("next_gpa", "The next-term GPA gap", "", 2))
    sentences <- c(sentences, parts)
  }
  sentences
}

# The three gaps a trend is read for, each beside its standard error column.
SIMILAR_GAP_COLS <- c(return = "return_gap", other_dfw = "other_dfw_gap", next_gpa = "next_gpa_gap")

#' Whether each course's gaps are rising, falling or steady across terms
#'
#' compute_rate_trend() over each course's per-term gaps, given with their
#' standard errors: the slope a year within one regular term type, beyond two
#' standard errors (the larger of chance and the terms' own scatter) a trend.
#' A term whose gap has no standard error above zero (an expected rate of 0
#' or 100%) carries no chance error and is left out of the line.
#'
#' @param by_term `get_course_similar_students(by_term = TRUE)` rows.
#' @param term_type The one term type the lines are fitted in (`"fall"`).
#' @return One row per course and outcome (`return`, `other_dfw`,
#'   `next_gpa`): `term_type`, `n_terms`, `first_term`, `first_gap`,
#'   `last_term`, `last_gap`, `slope` (gap units a year), `slope_se`,
#'   `direction` (`rising`, `falling`, `steady`, `too_few_terms`), and the
#'   fitted line's ends, `fit_first` and `fit_last`. No rows for an NA
#'   term type.
course_similar_students_trend <- function(by_term, term_type) {
  missing <- setdiff(c("course", "term", SIMILAR_GAP_COLS, paste0(SIMILAR_GAP_COLS, "_se")), names(by_term))
  if (length(missing)) {
    stop("[course-similar-students.R] by_term lacks ", paste(missing, collapse = ", "), call. = FALSE)
  }
  if (length(term_type) != 1L) stop("[course-similar-students.R] term_type must be one term type.", call. = FALSE)
  long <- bind_rows(lapply(names(SIMILAR_GAP_COLS), function(outcome) {
    col <- SIMILAR_GAP_COLS[[outcome]]
    tibble::tibble(course = by_term$course, term = by_term$term, outcome = outcome,
                   value = by_term[[col]], se = by_term[[paste0(col, "_se")]])
  })) %>%
    filter(!is.na(term_type), get_term_type(term) == term_type, !is.na(value), !is.na(se), se > 0)
  mids <- long %>%
    group_by(course, outcome) %>%
    summarize(.mid_value = mean(value), .mid_year = mean(term %/% 100L), .groups = "drop")
  compute_rate_trend(long, c("course", "outcome"), min_terms = 3L) %>%
    left_join(mids, by = c("course", "outcome")) %>%
    transmute(course, outcome, term_type = .env$term_type, n_terms, first_term, first_gap = first_pct,
              last_term, last_gap = last_pct, slope, slope_se, direction,
              fit_first = .mid_value + slope * (first_term %/% 100L - .mid_year),
              fit_last = .mid_value + slope * (last_term %/% 100L - .mid_year))
}

#' The focal course's three gaps term by term, with chance and the trend
#'
#' One panel a gap: each term's gap with the band chance alone gives (two
#' standard errors), zero marked, and the fitted line across the trend's
#' term type when there is one.
#'
#' @param payload `build_course_similar_students()` output.
#' @return A plotly subplot, or NULL with no terms.
plot_course_similar_students_trend <- function(payload) {
  if (!inherits(payload, "course_similar_students")) {
    stop("[course-similar-students.R] payload must come from build_course_similar_students().", call. = FALSE)
  }
  rows <- payload$by_term %>% arrange(term)
  if (nrow(rows) == 0L) return(NULL)
  rows$term_label <- term_axis_factor(rows$term)
  levels_x <- levels(rows$term_label)
  panels <- list(
    list(outcome = "return", title = "Return gap (points)", digits = 1),
    list(outcome = "other_dfw", title = "Other-course DFW gap (points)", digits = 1),
    list(outcome = "next_gpa", title = "Next-term GPA gap", digits = 2)
  )
  plots <- lapply(panels, function(pn) {
    col <- SIMILAR_GAP_COLS[[pn$outcome]]
    d <- rows[!is.na(rows[[col]]), , drop = FALSE]
    d$gap <- d[[col]]
    d$chance <- 2 * d[[paste0(col, "_se")]]
    fmt <- paste0("%{y:+.", pn$digits, "f}")
    p <- plotly::plot_ly(d, x = ~term_label) %>%
      plotly::add_trace(
        y = ~gap, type = "scatter", mode = "markers", showlegend = FALSE,
        marker = list(color = unname(CEDAR_SEMANTIC_COLORS["neutral"]), size = 8),
        error_y = list(type = "data", array = ~chance, color = unname(CEDAR_SEMANTIC_COLORS["reference"]),
                       thickness = 1.5, width = 0),
        customdata = ~chance,
        hovertemplate = paste0("%{x}<br>Gap: ", fmt, "<br>Chance alone: ±%{customdata:.", pn$digits,
                               "f}<extra></extra>")
      )
    tr <- payload$trend[payload$trend$outcome == pn$outcome & payload$trend$direction != "too_few_terms", , drop = FALSE]
    if (nrow(tr) == 1L) {
      ends <- tibble::tibble(term_label = factor(term_code_to_axis_label(c(tr$first_term, tr$last_term)), levels = levels_x),
                             fit = c(tr$fit_first, tr$fit_last))
      p <- p %>% plotly::add_trace(
        data = ends, x = ~term_label, y = ~fit, type = "scatter", mode = "lines", showlegend = FALSE,
        line = list(color = unname(CEDAR_SEMANTIC_COLORS["caution"]), dash = "dash"),
        hovertemplate = paste0("Trend: ", sprintf(paste0("%+.", pn$digits, "f"), tr$slope), " a year (",
                               c(rising = "rising", falling = "falling", steady = "no trend beyond chance")[[tr$direction]],
                               ")<extra></extra>"))
    }
    p %>% plotly::layout(yaxis = list(title = pn$title, zeroline = TRUE,
                                      zerolinecolor = unname(CEDAR_SEMANTIC_COLORS["reference"])))
  })
  plotly::subplot(plots, nrows = 3, shareX = TRUE, titleY = TRUE, margin = 0.04) %>%
    plotly::layout(xaxis = list(title = "", tickangle = -45, categoryorder = "array", categoryarray = levels_x))
}

#' The similar-students payload as plain text (the text-first preview)
#'
#' @param payload `build_course_similar_students()` output.
#' @return Character vector of lines.
format_course_similar_students <- function(payload) {
  if (!inherits(payload, "course_similar_students")) {
    stop("[course-similar-students.R] payload must come from build_course_similar_students().", call. = FALSE)
  }
  meta <- payload$meta
  num <- function(x, digits = 1) ifelse(is.na(x), "—", formatC(x, format = "f", digits = digits))
  course_line <- function(r, label) {
    sprintf("  %-28s n %5d  return %s vs %s (%s)  other DFW %s vs %s (%s)  next GPA %s vs %s",
            label, r$n_covered, num(r$return_pct), num(r$return_expected_pct), num(r$return_gap),
            num(r$other_dfw_pct), num(r$other_dfw_expected_pct), num(r$other_dfw_gap),
            num(r$next_gpa, 2), num(r$next_gpa_expected, 2))
  }
  rows_of <- function(tbl, labels) vapply(seq_len(nrow(tbl)), function(i) course_line(tbl[i, ], labels[i]), character(1))
  lines <- c(
    paste0(meta$course, " against ", course_similar_comparisons()[[meta$comparison]], ": ",
           paste(meta$classification, collapse = ", ")),
    paste0("Population: ", format(meta$n_population_student_terms, big.mark = ","), " student-terms; ",
           "cells of term, home campus, high-school GPA band and time status with at least ", meta$min_cell_n,
           " non-takers; rows with at least ", meta$min_n, " covered takers."),
    "", course_similar_students_headline(payload), "",
    paste0("Every course (", nrow(payload$courses), "), by return gap:"),
    rows_of(payload$courses, paste0(payload$courses$course, ifelse(payload$courses$is_focal, " *", "")))
  )
  if (nrow(payload$by_term) > 0L) {
    lines <- c(lines, "", paste0(meta$course, " term by term:"),
               rows_of(payload$by_term, fmt_term(payload$by_term$term)))
  }
  if (nrow(payload$instructors) > 0L) {
    lines <- c(lines, "", paste0(meta$course, " by instructor, against the course's non-takers:"),
               rows_of(payload$instructors, payload$instructors$instructor_name))
  }
  lines
}
