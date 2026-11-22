# summer-finishers.R — What did students who finished right after a term still need?
#
# One question: of the students enrolled in a term who were awarded a degree
# before the next regular term (in practice: spring students who finish in the
# summer), how many credits did each take in that last stretch, and in which
# courses?
#
#   Who           between_term_finishers() (branches/retention-context.R): the
#                 same students the return rate leaves out as finished. Scoped
#                 by level and home campus in the anchor term.
#   Credits       the finishing term's attempted credits here
#                 (cedar_student_terms). A student with no enrollment that term
#                 took nothing here: the degree was posted then (an incomplete
#                 made up, a course finished elsewhere, paperwork).
#   Courses       graded attempts in the finishing term (cedar_attempts), by
#                 course and the campus that taught it, over the latest
#                 `course_terms` finishing terms with posted grades. A course
#                 under `min_n` students is not listed.
#   Not a claim   that the summer courses were required: the data holds what
#                 a student took, not their audit.
#
# Depends on: between_term_finishers(), get_term_type() (trunk/utils.R)

SUMMER_FINISHER_CREDIT_BREAKS <- c(1, 4, 7)
SUMMER_FINISHER_BANDS <- c("No course here", "1 to 3 credits", "4 to 6 credits", "7 credits or more")

#' Students who finished before the next regular term, by what they took
#'
#' @param student_terms `cedar_student_terms`.
#' @param degrees `cedar_degrees`.
#' @param attempts `cedar_attempts`.
#' @param opt `data_edges` (required: `last_enrolled_complete`, `last_degree`,
#'   `last_graded`), `term_type` (anchor term types; NULL keeps all),
#'   `student_level`, `campus` (home campuses), `course_terms` (finishing
#'   terms the course list reads; default 3), `min_n` (students a listed
#'   course needs; default 10).
#' @return list(`by_term` one row per anchor term and credit band: `term`,
#'   `finish_term`, `basis`, `band`, `n`; `courses` one row per course and
#'   campus: `subject_course`, `campus`, `n_students`, `share_pct` of the
#'   finishers in those terms; `meta`).
get_summer_finishers <- function(student_terms, degrees, attempts, opt = list()) {
  need <- list(student_terms = c("student_id", "term", "enrolled", "student_level", "student_campus",
                                 "attempted_unm_credits"),
               attempts = c("student_id", "term", "subject_course", "campus"))
  have <- list(student_terms = student_terms, attempts = attempts)
  for (name in names(need)) {
    missing <- setdiff(need[[name]], names(have[[name]]))
    if (length(missing) > 0L) stop("[summer-finishers.R] ", name, " lacks ", paste(missing, collapse = ", "), call. = FALSE)
  }
  edge <- cedar_longitudinal_edge(opt$data_edges)
  graded_edge <- opt$data_edges[["last_graded"]]
  if (is.null(edge) || is.null(graded_edge)) {
    stop("[summer-finishers.R] opt$data_edges needs the settled enrollment edge and the graded edge.", call. = FALSE)
  }
  course_terms <- as.integer(opt$course_terms %||% 3L)
  min_n <- as.integer(opt$min_n %||% 10L)

  anchors <- student_terms %>% filter(enrolled, term <= edge)
  if (!is.null(opt$term_type)) anchors <- anchors %>% filter(get_term_type(term) %in% opt$term_type)
  if (!is.null(opt$student_level)) anchors <- anchors %>% filter(student_level %in% opt$student_level)
  if (!is.null(opt$campus)) anchors <- anchors %>% filter(student_campus %in% opt$campus)
  finishers <- between_term_finishers(anchors %>% select(student_id, term), degrees, opt$data_edges[["last_degree"]])
  cedar_debug("[summer-finishers.R] ", nrow(finishers), " finished between terms")

  took <- student_terms %>%
    filter(enrolled) %>%
    transmute(student_id, finish_term = as.integer(term), credits = as.numeric(attempted_unm_credits))
  placed <- finishers %>%
    left_join(took, by = c("student_id", "finish_term"), relationship = "many-to-one") %>%
    mutate(credits = dplyr::coalesce(credits, 0),
           band = factor(SUMMER_FINISHER_BANDS[findInterval(credits, SUMMER_FINISHER_CREDIT_BREAKS) + 1L],
                         levels = SUMMER_FINISHER_BANDS))
  by_term <- placed %>% count(term, finish_term, basis, band, name = "n", .drop = FALSE) %>% filter(n > 0L)

  read_terms <- sort(unique(placed$finish_term[placed$finish_term <= graded_edge]), decreasing = TRUE)
  read_terms <- sort(head(read_terms, course_terms))
  in_read <- placed %>% filter(finish_term %in% read_terms)
  courses <- attempts %>%
    mutate(finish_term = as.integer(term)) %>%
    inner_join(in_read %>% select(student_id, finish_term), by = c("student_id", "finish_term"),
               relationship = "many-to-one") %>%
    group_by(subject_course, campus) %>%
    summarize(n_students = n_distinct(student_id), .groups = "drop") %>%
    filter(n_students >= min_n) %>%
    mutate(share_pct = 100 * n_students / nrow(in_read)) %>%
    arrange(desc(n_students), subject_course, campus)

  list(by_term = by_term, courses = courses,
       meta = list(term_type = opt$term_type, student_level = opt$student_level, campus = opt$campus,
                   edge = edge, graded_edge = graded_edge, degree_edge = opt$data_edges[["last_degree"]],
                   n_finishers = nrow(placed), course_terms = read_terms, n_course_finishers = nrow(in_read),
                   min_n = min_n))
}

# ── Plotting ─────────────────────────────────────────────────────────────────

#' Students who finished before the next regular term: one stacked bar a term
#'
#' Each bar is the students of one term who finished in the stretch after it,
#' split by the credits they took here in that stretch. A term whose degrees
#' are not posted yet shows applications, and says so on its label.
#' @param result get_summer_finishers() output.
plot_summer_finishers <- function(result) {
  b <- result$by_term
  if (nrow(b) == 0L) stop("[summer-finishers.R] no finisher to draw.", call. = FALSE)
  terms <- b %>% distinct(term, finish_term, basis) %>% arrange(term)
  labels <- stats::setNames(
    paste0(vapply(terms$finish_term, fmt_term, character(1)), ifelse(terms$basis == "applied", "<br>(applied)", "")),
    terms$term)
  colours <- stats::setNames(
    # Amounts, not good and bad: the reference grey for none, then the palette.
    c(CEDAR_SEMANTIC_COLORS[["reference"]], unname(unlist(CEDAR_PALETTE[1:3]))), SUMMER_FINISHER_BANDS)
  totals <- b %>% group_by(term) %>% summarize(total = sum(n), .groups = "drop")
  fig <- plotly::plot_ly()
  for (band in SUMMER_FINISHER_BANDS) {
    rows <- terms %>% select(term) %>%
      left_join(b[b$band == band, c("term", "n")], by = "term", relationship = "one-to-one") %>%
      left_join(totals, by = "term", relationship = "one-to-one") %>%
      mutate(n = dplyr::coalesce(n, 0L))
    fig <- plotly::add_trace(
      fig, x = unname(labels[as.character(rows$term)]), y = rows$n, type = "bar", name = band,
      marker = list(color = colours[[band]]),
      text = ifelse(rows$n / rows$total >= 0.06, format(rows$n, big.mark = ",", trim = TRUE), ""),
      textposition = "inside", textangle = 0,
      hovertext = paste0(vapply(rows$term, fmt_term, character(1)), " students finishing in ",
                         gsub("<br>", " ", unname(labels[as.character(rows$term)])), "<br>", band, ": ",
                         format(rows$n, big.mark = ",", trim = TRUE), " of ",
                         format(rows$total, big.mark = ",", trim = TRUE),
                         " (", sprintf("%.1f%%", 100 * rows$n / rows$total), ")"),
      hoverinfo = "text")
  }
  plotly::layout(fig, barmode = "stack",
    xaxis = list(title = "Degree awarded in", type = "category", categoryorder = "array",
                 categoryarray = unname(labels)),
    yaxis = list(title = "Students"),
    legend = list(orientation = "h", y = -0.3, traceorder = "normal"), margin = list(t = 20))
}
