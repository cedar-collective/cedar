# summer-after-spring.R — What did a spring's students do in the summer, and where were they in the fall?
#
# One question, asked of any set of spring students the caller names (an
# entering class in its first spring; continuing students each spring): how
# many took courses here in the summer after, in which courses, and by the
# fall how many were back and how many who were behind on credits had caught
# up.
#
#   Who           the caller's rows: a student and a spring they were enrolled
#                 in, with the group the page shows them under.
#   Summer        credits attempted here in the summer after that spring
#                 (cedar_student_terms), in summer_credit_band()'s bands.
#   Back          enrolled the fall after, at this university on any campus
#                 and at any level, or awarded a degree in that spring or by
#                 the fall (degrees_to_date(): past the degree edge, an
#                 application to graduate, counted from the term after it): a
#                 student who finished is not one who left. Read only where
#                 that fall is settled.
#   Behind        with `opt$pace_credits` and the rows' `terms_completed`, and
#                 leaving out the students awarded a degree that spring:
#                 fewer credits completed here through the spring than the
#                 pace asks for that many regular terms. Caught up: the
#                 summer's completed credits bring the total to it. Credits
#                 brought from elsewhere are not counted, as on the pace
#                 chart. Read only where the summer's grades are posted and
#                 the running total is whole (`timeline_valid`).
#   Courses       summer_course_list() over the students who took a summer
#                 course (`opt$courses_for = "behind"`: only those behind).
#   Not a claim   that summer caused anything: students who choose summer
#                 differ from those who do not.
#
# A sibling of get_summer_finishers(), not an extension: that one asks who
# finished and what they took last; this one follows students who go on.
#
# Depends on: summer_credit_band(), summer_course_list() (branches/summer-terms.R)
#             degrees_to_date() (branches/retention-context.R)
#             advance_term() (branches/cedar-terms.R), get_term_type()
#             cedar_longitudinal_edge() (branches/data-edges.R)

#' A spring's students in the summer after, and in the fall
#'
#' @param spring_students `student_id`, `term` (a spring the student was
#'   enrolled in), `group` (the label they are shown under) and, for the pace
#'   reading, `terms_completed` (regular terms since entering, that spring
#'   included). One row a student and term.
#' @param student_terms `cedar_student_terms`.
#' @param attempts `cedar_attempts`.
#' @param degrees `cedar_degrees`.
#' @param opt `data_edges` (required: settled, graded and degree edges),
#'   `pace_credits` (credits a regular term; NULL leaves the pace reading
#'   out), `courses_for` (`"takers"`, the default, or `"behind"`),
#'   `course_terms` (summers the course list reads; default 3), `min_n`
#'   (students a listed course needs; default 10).
#' @return list(`by_band` (one row per `group`, `term` and summer credit
#'   `band`: `n`, `n_readable` whose fall is settled, `n_back`), `pace` (NULL
#'   without `pace_credits`; one row per `group` and `term` whose summer is
#'   graded: `n_finished` (awarded a degree that spring, left out),
#'   `n_known`, `n_unknown`, `n_behind`, `n_behind_summer`, `n_caught_up`),
#'   `courses`, `meta`).
get_summer_after_spring <- function(spring_students, student_terms, attempts, degrees, opt = list()) {
  pace_credits <- opt$pace_credits
  need <- list(
    spring_students = c("student_id", "term", "group", if (!is.null(pace_credits)) "terms_completed"),
    student_terms = c("student_id", "term", "enrolled", "attempted_unm_credits", "completed_unm_credits",
                      if (!is.null(pace_credits)) c("cumulative_completed_unm_credits", "timeline_valid")))
  have <- list(spring_students = spring_students, student_terms = student_terms)
  for (name in names(need)) {
    missing <- setdiff(need[[name]], names(have[[name]]))
    if (length(missing) > 0L) stop("[summer-after-spring.R] ", name, " lacks ", paste(missing, collapse = ", "), call. = FALSE)
  }
  edge <- cedar_longitudinal_edge(opt$data_edges)
  graded_edge <- opt$data_edges[["last_graded"]]
  degree_edge <- opt$data_edges[["last_degree"]]
  if (is.null(edge) || is.null(graded_edge) || is.null(degree_edge)) {
    stop("[summer-after-spring.R] opt$data_edges needs the settled, graded and degree edges.", call. = FALSE)
  }
  courses_for <- opt$courses_for %||% "takers"
  if (!courses_for %in% c("takers", "behind") || (courses_for == "behind" && is.null(pace_credits))) {
    stop("[summer-after-spring.R] opt$courses_for is \"takers\" or, with opt$pace_credits, \"behind\".", call. = FALSE)
  }
  who <- spring_students %>% mutate(term = as.integer(term))
  if (anyDuplicated(who[c("student_id", "term")]) > 0L) {
    stop("[summer-after-spring.R] spring_students holds a student and term twice.", call. = FALSE)
  }
  if (any(get_term_type(who$term) != "spring")) {
    stop("[summer-after-spring.R] every spring_students term must be a spring.", call. = FALSE)
  }

  enrolled <- student_terms %>% filter(enrolled) %>% mutate(term = as.integer(term))
  summers <- enrolled %>%
    transmute(student_id, summer_term = term, summer_attempted = as.numeric(attempted_unm_credits),
              summer_completed = as.numeric(completed_unm_credits))
  here <- enrolled %>% transmute(student_id, fall = term, in_fall = TRUE)
  # An application is for a term the student may still be enrolled in: it
  # counts from the term after, as the entering classes count it.
  finished <- degrees_to_date(degrees, degree_edge) %>%
    mutate(degree_term = if_else(basis == "applied", advance_term(degree_term, 1L, summer = TRUE), degree_term)) %>%
    select(student_id, degree_term)
  placed <- who %>%
    mutate(summer_term = advance_term(term, 1L, summer = TRUE), fall = advance_term(term, 1L)) %>%
    left_join(summers, by = c("student_id", "summer_term"), relationship = "many-to-one") %>%
    left_join(here, by = c("student_id", "fall"), relationship = "many-to-one")
  with_degree <- placed %>%
    select(student_id, term, fall) %>%
    inner_join(finished, by = "student_id", relationship = "many-to-many") %>%
    filter(degree_term >= term, degree_term <= fall) %>%
    group_by(student_id, term) %>%
    summarize(degree = TRUE, finished_spring = any(degree_term == term), .groups = "drop")
  placed <- placed %>%
    left_join(with_degree, by = c("student_id", "term"), relationship = "one-to-one") %>%
    mutate(band = summer_credit_band(summer_attempted), took = !is.na(summer_attempted) & summer_attempted > 0,
           readable = fall <= edge, back = readable & (in_fall %in% TRUE | degree %in% TRUE))
  cedar_debug("[summer-after-spring.R] ", nrow(placed), " spring students; ", sum(placed$took), " took a summer course")

  by_band <- placed %>%
    group_by(group, term, band) %>%
    summarize(n = n(), n_readable = sum(readable), n_back = sum(back), .groups = "drop") %>%
    arrange(group, term, band)

  pace <- NULL
  behind_ids <- NULL
  if (!is.null(pace_credits)) {
    through <- student_terms %>%
      transmute(student_id, term = as.integer(term), valid = timeline_valid %in% TRUE,
                through_spring = as.numeric(cumulative_completed_unm_credits))
    paced <- placed %>%
      # The summer's grades are what catching up is read from.
      filter(summer_term <= graded_edge) %>%
      left_join(through, by = c("student_id", "term"), relationship = "many-to-one") %>%
      mutate(finished = finished_spring %in% TRUE,
             known = !finished & valid %in% TRUE & !is.na(through_spring),
             threshold = as.numeric(pace_credits) * terms_completed,
             behind = known & through_spring < threshold,
             caught_up = behind & through_spring + dplyr::coalesce(summer_completed, 0) >= threshold)
    pace <- paced %>%
      group_by(group, term) %>%
      summarize(n_finished = sum(finished), n_known = sum(known), n_unknown = sum(!known & !finished),
                n_behind = sum(behind),
                n_behind_summer = sum(behind & took), n_caught_up = sum(caught_up), .groups = "drop") %>%
      arrange(group, term)
    behind_ids <- paced %>% filter(behind) %>% select(student_id, term)
  }

  listed_who <- placed %>% filter(took)
  if (courses_for == "behind") listed_who <- listed_who %>% semi_join(behind_ids, by = c("student_id", "term"))
  listed <- summer_course_list(listed_who %>% select(student_id, summer_term), attempts, graded_edge,
                               opt$course_terms %||% 3L, opt$min_n %||% 10L)

  list(by_band = by_band, pace = pace, courses = listed$courses,
       meta = list(edge = edge, graded_edge = graded_edge, degree_edge = degree_edge, pace_credits = pace_credits,
                   courses_for = courses_for, n_students = nrow(placed), n_took = sum(placed$took),
                   course_terms = listed$terms, n_course_students = listed$n_students_read,
                   min_n = as.integer(opt$min_n %||% 10L)))
}
