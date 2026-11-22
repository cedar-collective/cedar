# summer-terms.R — What a set of students took in a summer
#
# The two things every summer section counts the same way: the band of
# credits a student attempted here that summer, and the courses a group took
# most. Read by get_summer_finishers() and get_summer_after_spring().
#
# Exported: SUMMER_CREDIT_BREAKS, SUMMER_CREDIT_BANDS, summer_credit_band(),
#           summer_course_list()

SUMMER_CREDIT_BREAKS <- c(1, 4, 7)
SUMMER_CREDIT_BANDS <- c("No course here", "1 to 3 credits", "4 to 6 credits", "7 credits or more")

#' The band of credits attempted here in a summer
#' @param credits Attempted credits; NA (no enrollment that summer) is none.
#' @return A factor over `SUMMER_CREDIT_BANDS`.
summer_credit_band <- function(credits) {
  credits <- dplyr::coalesce(as.numeric(credits), 0)
  factor(SUMMER_CREDIT_BANDS[findInterval(credits, SUMMER_CREDIT_BREAKS) + 1L], levels = SUMMER_CREDIT_BANDS)
}

#' The courses a group of students took most in their summers
#'
#' Graded attempts in each student's summer, by course and the campus that
#' taught it, over the latest `course_terms` summers with posted grades.
#'
#' @param who `student_id` and `summer_term`, one row a student and summer.
#' @param attempts `cedar_attempts`.
#' @param graded_edge `last_graded`: a later summer has no attempts yet.
#' @param course_terms Summers read, latest first.
#' @param min_n Students a listed course needs.
#' @return list(`courses` (`subject_course`, `campus`, `n_students`,
#'   `share_pct` of `n_students_read`), `terms` (the summers read),
#'   `n_students_read` (the rows of `who` in those summers)).
summer_course_list <- function(who, attempts, graded_edge, course_terms = 3L, min_n = 10L) {
  missing <- setdiff(c("student_id", "term", "subject_course", "campus"), names(attempts))
  if (length(missing) > 0L) stop("[summer-terms.R] attempts lacks ", paste(missing, collapse = ", "), call. = FALSE)
  if (anyDuplicated(who[c("student_id", "summer_term")]) > 0L) {
    stop("[summer-terms.R] summer_course_list: who holds a student and summer twice.", call. = FALSE)
  }
  read_terms <- sort(unique(who$summer_term[who$summer_term <= graded_edge]), decreasing = TRUE)
  read_terms <- sort(head(read_terms, as.integer(course_terms)))
  in_read <- who %>% filter(summer_term %in% read_terms)
  courses <- attempts %>%
    mutate(summer_term = as.integer(term)) %>%
    inner_join(in_read %>% select(student_id, summer_term), by = c("student_id", "summer_term"),
               relationship = "many-to-one") %>%
    group_by(subject_course, campus) %>%
    summarize(n_students = n_distinct(student_id), .groups = "drop") %>%
    filter(n_students >= as.integer(min_n)) %>%
    mutate(share_pct = 100 * n_students / nrow(in_read)) %>%
    arrange(desc(n_students), subject_course, campus)
  list(courses = courses, terms = read_terms, n_students_read = nrow(in_read))
}
