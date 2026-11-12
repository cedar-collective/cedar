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

#' A course against similar non-takers, beside every other course and by instructor
#'
#' @param student_terms `cedar_student_terms`.
#' @param attempts `cedar_attempts`.
#' @param applicants `cedar_applicants`.
#' @param opt `course` (the focal course id; required), `classification`
#'   (required), `term`, `campus`, `min_n` (covered takers a course or an
#'   instructor needs; default 30), `min_cell_n`, `data_edges` (required).
#' @return A `course_similar_students` list: `meta`; `focal` (the course's
#'   one row, or NULL when it has fewer than `min_n` covered takers);
#'   `courses` (every course at `min_n`, the focal one among them, with
#'   `is_focal`); `benchmark` (one row per outcome: `n_courses`, `q1`,
#'   `median`, `q3` of the courses' gaps, `focal_gap`, `share_below`);
#'   `instructors` (the focal course's instructors at `min_n`) and
#'   `instructor_spread` (`n_instructors`, `sd_return_gap`, `mean_se`,
#'   `n_beyond_2se`; NULL under two instructors); `by_term` (the focal
#'   course's row per anchor term at `min_term_n` covered takers, default
#'   10) and `trend` (`course_similar_students_trend()` over it).
build_course_similar_students <- function(student_terms, attempts, applicants, opt = list()) {
  course <- opt$course
  if (is.null(course) || length(course) != 1L || is.na(course) || !nzchar(course)) {
    stop("[course-similar-students.R] opt$course (one focal course id) is required.", call. = FALSE)
  }
  cone_opt <- opt[intersect(names(opt), c("classification", "term", "campus", "min_n", "min_cell_n", "data_edges"))]
  courses <- get_course_similar_students(student_terms, attempts, applicants, cone_opt)
  min_n <- as.integer(opt$min_n %||% 30L)
  suppressed <- attr(courses, "suppressed")
  meta <- list(
    course = course,
    classification = opt$classification,
    term = opt$term, campus = opt$campus,
    min_n = min_n, min_cell_n = as.integer(opt$min_cell_n %||% 5L),
    edge = attr(courses, "edge"), graded_edge = attr(courses, "graded_edge"),
    n_population_student_terms = attr(courses, "n_population_student_terms"),
    focal_under_min_n = suppressed[suppressed$course == course, , drop = FALSE]
  )
  courses <- courses %>% mutate(is_focal = course == .env$course)
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

  term_opt <- cone_opt
  term_opt$min_n <- as.integer(opt$min_term_n %||% 10L)
  by_term <- get_course_similar_students(
    student_terms, attempts, applicants, c(term_opt, list(course = course, by_term = TRUE))
  )
  meta$min_term_n <- term_opt$min_n

  structure(list(meta = meta, focal = focal, courses = courses, benchmark = benchmark,
                 instructors = instructors, instructor_spread = spread,
                 by_term = by_term, trend = course_similar_students_trend(by_term)),
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
  like <- "non-takers of the same term, home campus, high-school GPA band and time status"
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
  if (!is.null(tr)) {
    sentences <- c(sentences, paste0(
      "Term by term, the return gap went from ", pts(tr$first_gap), " points in ", fmt_term(tr$first_term),
      " to ", pts(tr$last_gap), " in ", fmt_term(tr$last_term), " over ", tr$n_terms, " terms: ",
      switch(tr$direction,
             improving = "an upward trend",
             declining = "a downward trend",
             steady = "no trend beyond chance"),
      " (", pts(tr$slope), " points a term, where chance alone gives about ", sprintf("%.1f", 2 * tr$slope_se), ")."
    ))
  }
  sentences
}

#' Whether a course's return gap is rising, falling or steady across terms
#'
#' The slope of the per-term return gap on the term's position
#' (`compute_trend()`), judged against its own standard error from the
#' per-term errors: beyond two standard errors is a trend, inside is steady.
#' Summer terms are left out: a summer cohort is a different population.
#'
#' @param by_term `get_course_similar_students(by_term = TRUE)` rows of one course.
#' @return NULL under three regular terms with a return gap, else a list:
#'   `n_terms`, `first_term`, `first_gap`, `last_term`, `last_gap`, `slope`
#'   (points per term), `slope_se`, `direction` (`improving`, `declining`,
#'   `steady`).
course_similar_students_trend <- function(by_term) {
  rows <- by_term %>%
    filter(!is.na(return_gap), !is.na(return_gap_se), get_term_type(term) %in% c("fall", "spring")) %>%
    arrange(term)
  if (nrow(rows) < 3L) return(NULL)
  x <- seq_len(nrow(rows)) - mean(seq_len(nrow(rows)))
  slope <- unname(compute_trend(rows$return_gap)$slope)
  slope_se <- sqrt(sum(x^2 * rows$return_gap_se^2)) / sum(x^2)
  list(
    n_terms = nrow(rows),
    first_term = rows$term[1], first_gap = rows$return_gap[1],
    last_term = rows$term[nrow(rows)], last_gap = rows$return_gap[nrow(rows)],
    slope = slope, slope_se = slope_se,
    direction = if (slope > 2 * slope_se) "improving" else if (slope < -2 * slope_se) "declining" else "steady"
  )
}

#' The takers' return rate against the expected rate, term by term
#'
#' @param payload `build_course_similar_students()` output.
#' @return A plotly object, or NULL when no term has a return to show.
plot_course_similar_students_trend <- function(payload) {
  if (!inherits(payload, "course_similar_students")) {
    stop("[course-similar-students.R] payload must come from build_course_similar_students().", call. = FALSE)
  }
  rows <- payload$by_term %>% filter(!is.na(return_pct)) %>% arrange(term) %>%
    mutate(term_label = term_axis_factor(term))
  if (nrow(rows) == 0L) return(NULL)
  plotly::plot_ly(rows, x = ~term_label) %>%
    plotly::add_trace(
      y = ~return_expected_pct / 100, type = "scatter", mode = "lines+markers", name = "Expected from similar non-takers",
      line = list(color = unname(CEDAR_SEMANTIC_COLORS["reference"]), dash = "dot"),
      marker = list(color = unname(CEDAR_SEMANTIC_COLORS["reference"])),
      hovertemplate = "%{x}<br>Expected: %{y:.1%}<extra></extra>"
    ) %>%
    plotly::add_trace(
      y = ~return_pct / 100, type = "scatter", mode = "lines+markers", name = paste0("Took ", payload$meta$course),
      line = list(color = unname(CEDAR_SEMANTIC_COLORS["positive"])),
      marker = list(color = unname(CEDAR_SEMANTIC_COLORS["positive"])),
      customdata = ~return_n,
      hovertemplate = "%{x}<br>Returned: %{y:.1%} of %{customdata}<extra></extra>"
    ) %>%
    plotly::layout(
      xaxis = list(title = "", tickangle = -45),
      yaxis = list(title = "Returned the next regular term", tickformat = ".0%"),
      legend = list(orientation = "h", x = 0, y = -0.25)
    )
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
    paste0(meta$course, " against similar non-takers: ", paste(meta$classification, collapse = ", ")),
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
