# Summer on the student pages
#
# Retention asks two summer questions, each of its own students (an entering
# class after its first spring; continuing students behind on credits), through
# get_summer_after_spring(); Graduation's is get_summer_finishers().
# The builders here name the students (entering_students()) and shape the
# cone's rows for the page.
#
# Exported functions:
#   build_first_year_summer()   an entering class's first spring, and the fall
#   build_pace_summer()         continuing students behind on credits each spring
#   summer_return_by_taking()   back-in-the-fall rates, took a summer course or not
#   summer_catch_up_by_term()   behind, took a summer course, caught up: by spring

# The years a first-time fall class is read at for the pace summer: the
# regular terms since entering at each spring, and its label.
SUMMER_PACE_YEARS <- c("1st year" = 1L, "2nd year" = 3L, "3rd year" = 5L, "4th year" = 7L)

#' Each entering class in the summer after its first spring
#'
#' The class's first spring is its 2nd semester for a fall class and its
#' entering term for a spring one. Read are the students enrolled that spring.
#'
#' @param student_terms,attempts,degrees,programs The loaded tables.
#' @param opt `data_edges` (required), `term_type`, `student_level`, `campus`,
#'   `entry`, `entry_time_status`, `min_n` (students a listed course needs).
#' @return get_summer_after_spring()'s list; `group` is the entering term.
build_first_year_summer <- function(student_terms, attempts, degrees, programs, opt = list()) {
  edge <- cedar_longitudinal_edge(opt$data_edges)
  if (is.null(edge)) stop("[summer-sections.R] opt$data_edges has no settled enrollment edge.", call. = FALSE)
  found <- entering_students(student_terms, programs, edge, list(
    entry = opt$entry %||% "first_time", student_level = opt$student_level, term_type = opt$term_type,
    campus = opt$campus, time_status = opt$entry_time_status))
  springs <- found$entering %>%
    transmute(student_id, group = as.character(term),
              term = if_else(get_term_type(term) == "spring", as.integer(term), advance_term(term, 1L))) %>%
    semi_join(found$enrolled, by = c("student_id", "term"))
  result <- get_summer_after_spring(springs, student_terms, attempts, degrees,
                                    list(data_edges = opt$data_edges, min_n = opt$min_n, course_terms = opt$course_terms))
  result$meta$n_entering <- nrow(found$entering)
  result$meta$entry <- opt$entry %||% "first_time"
  result
}

#' First-time fall classes each spring: behind on credits, and what summer did
#'
#' Each first-time fall class is read at the spring that ends each of its
#' first four years (`SUMMER_PACE_YEARS`), against the four-year pace
#' (`DEGREE_PACE_TERM_CREDITS`). Read are the students enrolled that spring.
#'
#' @param opt `data_edges` (required), `student_level`, `campus`, `min_n`.
#' @return get_summer_after_spring()'s list with the pace reading; `group` is
#'   the year label, and the courses are those of the students behind.
build_pace_summer <- function(student_terms, attempts, degrees, programs, opt = list()) {
  edge <- cedar_longitudinal_edge(opt$data_edges)
  if (is.null(edge)) stop("[summer-sections.R] opt$data_edges has no settled enrollment edge.", call. = FALSE)
  found <- entering_students(student_terms, programs, edge, list(
    entry = "first_time", student_level = opt$student_level, term_type = "fall", campus = opt$campus))
  springs <- bind_rows(lapply(seq_along(SUMMER_PACE_YEARS), function(i) {
    k <- SUMMER_PACE_YEARS[[i]]
    found$entering %>%
      transmute(student_id, group = names(SUMMER_PACE_YEARS)[[i]], term = advance_term(term, k),
                terms_completed = k + 1L)
  })) %>%
    semi_join(found$enrolled, by = c("student_id", "term"))
  result <- get_summer_after_spring(springs, student_terms, attempts, degrees, list(
    data_edges = opt$data_edges, min_n = opt$min_n, course_terms = opt$course_terms,
    pace_credits = DEGREE_PACE_TERM_CREDITS[["four_year"]], courses_for = "behind"))
  result$meta$years <- names(SUMMER_PACE_YEARS)
  result
}

#' Back in the fall, for students who took a summer course and those who did not
#'
#' @param result get_summer_after_spring() output.
#' @param min_n Students a rate needs.
#' @return One row per `group` and `term` with a settled fall: `n`, `n_took`,
#'   `took_pct` (the share taking a summer course), `back_took_pct`,
#'   `back_none_pct` (NA under `min_n` students).
summer_return_by_taking <- function(result, min_n = 30L) {
  rate <- function(back, n) if_else(n >= min_n, 100 * back / n, NA_real_)
  result$by_band %>%
    filter(n_readable > 0L) %>%
    mutate(took = band != SUMMER_CREDIT_BANDS[[1]]) %>%
    group_by(group, term) %>%
    summarize(n = sum(n_readable), n_took = sum(n_readable[took]),
              n_back_took = sum(n_back[took]), n_back_none = sum(n_back[!took]), .groups = "drop") %>%
    mutate(took_pct = 100 * n_took / n, back_took_pct = rate(n_back_took, n_took),
           back_none_pct = rate(n_back_none, n - n_took)) %>%
    arrange(group, term)
}

#' Students behind on credits each spring: no summer course, one and still behind, caught up
#'
#' @param result build_pace_summer() output.
#' @return One row per spring `term` with a readable total, every year
#'   together: `n_finished`, `n_known`, `n_unknown`, `n_behind`, `n_no_summer`, `n_still_behind`, `n_caught_up`.
summer_catch_up_by_term <- function(result) {
  if (is.null(result$pace)) stop("[summer-sections.R] the result has no pace reading.", call. = FALSE)
  result$pace %>%
    group_by(term) %>%
    summarize(across(c(n_finished, n_known, n_unknown, n_behind, n_behind_summer, n_caught_up), sum),
              .groups = "drop") %>%
    # A spring no running total can be read for (the table's first class) is not a row.
    filter(n_known > 0L) %>%
    transmute(term, n_finished, n_known, n_unknown, n_behind, n_no_summer = n_behind - n_behind_summer,
              n_still_behind = n_behind_summer - n_caught_up, n_caught_up) %>%
    arrange(term)
}

# ── Words ─────────────────────────────────────────────────────────────────────

#' The first-year summer in one sentence: how much more often summer students came back
#'
#' Every class the rates can be read for, not one: the smallest and largest
#' gap, and how the share taking a summer course moved.
#' @param rows summer_return_by_taking() output for one grouping (a row a class).
#' @return One sentence; character(0) when no class has both rates.
summer_return_sentence <- function(rows) {
  read <- rows %>% filter(!is.na(back_took_pct), !is.na(back_none_pct)) %>% arrange(term)
  if (nrow(read) == 0L) return(character(0))
  gap <- read$back_took_pct - read$back_none_pct
  classes <- if (nrow(read) == 1L) paste0("In the class read (", fmt_term(read$term[[1]]), " students),")
             else paste0("In each of the ", nrow(read), " classes read,")
  direction <- if (all(gap > 0)) "more often" else if (all(gap < 0)) "less often" else "sometimes more often, sometimes less,"
  size <- if (nrow(read) == 1L || round(min(abs(gap)), 1) == round(max(abs(gap)), 1)) sprintf("%.1f points", abs(gap[[1]]))
          else sprintf("%.1f to %.1f points", min(abs(gap)), max(abs(gap)))
  paste0(classes, " students who took a course here that summer were back in the fall ", direction,
         " than those who did not",
         if (all(gap > 0) || all(gap < 0)) paste0(", by ", size) else "",
         ". ", sprintf("%.1f%%", read$took_pct[[nrow(read)]]), " of the newest class took one",
         if (nrow(read) > 1L) paste0(", against ", sprintf("%.1f%%", read$took_pct[[1]]), " of the first") else "",
         ". Students who choose summer differ from those who do not, so this is what summer goes with, not what it causes.")
}

#' Summer and pace in one sentence: how many were behind, took a course, caught up
#'
#' The range over the springs read, never one spring.
#' @param rows summer_catch_up_by_term() output.
#' @param pace_credits The pace, in credits a regular term.
summer_catch_up_sentence <- function(rows, pace_credits) {
  read <- rows %>% filter(n_behind > 0L)
  if (nrow(read) == 0L) return(character(0))
  span <- function(x) if (round(min(x), 1) == round(max(x), 1)) sprintf("%.1f%%", x[[1]])
                      else sprintf("%.1f%% to %.1f%%", min(x), max(x))
  paste0(if (nrow(read) == 1L) paste0("After the spring read (", fmt_term(read$term[[1]]), "), ")
         else paste0("After each of the ", nrow(read), " springs read, "), span(100 * read$n_behind / read$n_known),
         " of these students had completed fewer than ", pace_credits, " credits here for each term so far. ",
         span(100 * (read$n_still_behind + read$n_caught_up) / read$n_behind),
         " of those behind took a course here that summer, and ", span(100 * read$n_caught_up / read$n_behind),
         " of those behind had caught up by the fall.")
}

# ── Plots ─────────────────────────────────────────────────────────────────────

#' Back in the fall, a line for summer students and one for the rest, a point a class
#'
#' @param rows summer_return_by_taking() output for one grouping.
#' @param label Names each class from its row: the default names the spring's students.
plot_summer_return <- function(rows, label = function(r) vapply(r$term, fmt_term, character(1))) {
  read <- rows %>% filter(!is.na(back_took_pct) | !is.na(back_none_pct)) %>% arrange(term)
  if (nrow(read) == 0L) stop("[summer-sections.R] no class to draw.", call. = FALSE)
  x <- label(read)
  series <- list(
    list(name = "Took a summer course", y = read$back_took_pct, n = read$n_took, back = read$n_back_took,
         colour = CEDAR_PALETTE[[1]]),
    list(name = "Did not", y = read$back_none_pct, n = read$n - read$n_took, back = read$n_back_none,
         colour = CEDAR_SEMANTIC_COLORS[["reference"]]))
  p <- plotly::plot_ly()
  for (s in series) {
    p <- plotly::add_trace(
      p, x = x, y = s$y, type = "scatter", mode = "lines+markers", name = s$name,
      line = list(color = s$colour, width = 3), marker = list(color = s$colour, size = 8),
      hovertext = paste0(x, "<br>", s$name, ": ", fmt_count(s$back), " of ", fmt_count(s$n), " back in the fall",
                         ifelse(is.na(s$y), "", sprintf(" (%.1f%%)", s$y)), "<br>",
                         sprintf("%.1f%%", read$took_pct), " of these students took a summer course"),
      hoverinfo = "text")
  }
  low <- min(c(read$back_took_pct, read$back_none_pct), na.rm = TRUE)
  plotly::layout(p,
    xaxis = list(title = "Students of", type = "category", categoryorder = "array", categoryarray = x),
    yaxis = list(title = "Back in the fall, or finished", ticksuffix = "%", range = c(max(0, low - 8), 100)),
    legend = list(orientation = "h", y = -0.2), margin = list(t = 20))
}

# The parts of the students behind, in drawing order: the column, the label.
SUMMER_CATCH_UP_PARTS <- c(n_no_summer = "No summer course", n_still_behind = "Summer course, still behind",
                           n_caught_up = "Summer course, caught up")

#' The students behind on credits each spring, in three parts
#' @param rows summer_catch_up_by_term() output.
plot_summer_catch_up <- function(rows) {
  read <- rows %>% filter(n_behind > 0L) %>% arrange(term)
  if (nrow(read) == 0L) stop("[summer-sections.R] no spring to draw.", call. = FALSE)
  x <- vapply(read$term, fmt_term, character(1))
  colours <- c(CEDAR_SEMANTIC_COLORS[["reference"]], CEDAR_PALETTE[[2]], CEDAR_PALETTE[[1]])
  p <- plotly::plot_ly()
  for (i in seq_along(SUMMER_CATCH_UP_PARTS)) {
    n <- read[[names(SUMMER_CATCH_UP_PARTS)[[i]]]]
    p <- plotly::add_trace(
      p, x = x, y = n, type = "bar", name = SUMMER_CATCH_UP_PARTS[[i]], marker = list(color = colours[[i]]),
      text = ifelse(n / read$n_behind >= 0.06, fmt_count(n), ""), textposition = "inside", textangle = 0,
      hovertext = paste0(x, "<br>", SUMMER_CATCH_UP_PARTS[[i]], ": ", fmt_count(n), " of ", fmt_count(read$n_behind),
                         " behind (", sprintf("%.1f%%", 100 * n / read$n_behind), ")<br>",
                         fmt_count(read$n_known), " students read that spring"),
      hoverinfo = "text")
  }
  plotly::layout(p, barmode = "stack",
    xaxis = list(title = "Behind after", type = "category", categoryorder = "array", categoryarray = x),
    yaxis = list(title = "Students behind on credits"),
    legend = list(orientation = "h", y = -0.2, traceorder = "normal"), margin = list(t = 20))
}
