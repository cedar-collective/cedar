# entering-class-retention.R — How much of each entering class is still here?
#
# One question: of the students who first enrolled in a term, what share was
# enrolled one, two, three and more regular terms later?
#
# get_return_rates() (return-rates.R) reads every enrolled student-term and
# one step, the next regular term. This cone follows one group, an entering
# class, across several steps, so a class that holds its students through the
# first spring and loses them over the summer shows where it loses them. The
# two are siblings because their populations differ (every student-term
# against each student once, at entry); extending either would change the
# other's answer.
#
#   Entering class  the students whose first enrolled term at the level in
#                   scope is that term (cedar_student_terms' `enrolled`),
#                   scoped by their home campus that term. The first term the
#                   table holds is nobody's entering class: every continuing
#                   student's first row is there. It is left out and counted.
#   Still here      enrolled in the target term on any campus and at any
#                   level, or awarded a degree in or before it. Moving campus
#                   is not leaving; finishing is not leaving. A student away
#                   one term and back the next is not here in the first and
#                   here in the second.
#   Steps           regular terms: summer is not a step (advance_term()). For
#                   a fall class step 1 is the next spring and step 2 the
#                   next fall; `target_term` says which.
#   Edge            enrollment is read to the settled edge; a target term past
#                   it is unknown (NA), never zero.
#
# Who is in it: everyone new at the level, which includes transfer students
# and, at the undergraduate level, students taking college courses while in
# high school. `opt$classification` narrows the class to students holding one
# of the given classifications in their entering term.
#
# Depends on: .build_enrolled_lookup(), .build_graduated_lookup(),
#               .compute_retention() (branches/retention-context.R)
#             cedar_longitudinal_edge() (branches/data-edges.R)
#             advance_term() (branches/cedar-terms.R), get_term_type()

#' Each entering class's share still enrolled one to `n_terms` regular terms later
#'
#' @param student_terms `cedar_student_terms`.
#' @param degrees `cedar_degrees`, so a degree counts as still here; NULL
#'   reads enrollment alone.
#' @param opt `term_type` (the entering classes' term type; NULL keeps every
#'   regular term type), `student_level` (level codes; NULL keeps every
#'   level, each student entering once), `campus` (home campuses in the
#'   entering term; NULL keeps every campus), `classification` (entering-term
#'   classifications to keep; NULL keeps all), `n_terms` (steps followed;
#'   default 4), `min_n` (smallest entering class given a rate; default 30),
#'   `data_edges` (`cedar_data_edges()` output, required).
#' @return A tibble, one row per entering `term` and `step`: `target_term`,
#'   `n_entering`, `n_here` (NA past the edge), `here_pct` (NA past the edge
#'   or under `min_n`). Attributes: `edge`, `first_term` (the table's first
#'   term, left out), `n_first_term` (the students whose first row is there),
#'   `n_terms`, `min_n`.
get_entering_class_retention <- function(student_terms, degrees = NULL, opt = list()) {
  needed <- c("student_id", "term", "enrolled", "student_level", "student_campus",
              if (!is.null(opt$classification)) "student_classification")
  missing <- setdiff(needed, names(student_terms))
  if (length(missing) > 0L) {
    stop("[entering-class-retention.R] student_terms lacks ", paste(missing, collapse = ", "), call. = FALSE)
  }
  edge <- cedar_longitudinal_edge(opt$data_edges)
  if (is.null(edge)) {
    stop("[entering-class-retention.R] opt$data_edges has no settled enrollment edge.", call. = FALSE)
  }
  n_terms <- as.integer(opt$n_terms %||% 4L)
  if (is.na(n_terms) || n_terms < 1L) {
    stop("[entering-class-retention.R] opt$n_terms must be at least 1.", call. = FALSE)
  }
  min_n <- as.integer(opt$min_n %||% 30L)

  enrolled <- student_terms %>% filter(enrolled, term <= edge) %>% mutate(term = as.integer(term))
  if (nrow(enrolled) == 0L) {
    stop("[entering-class-retention.R] no enrolled student-term at or before the settled edge.", call. = FALSE)
  }
  first_term <- min(enrolled$term)

  # Each student's entering term at the level in scope: the first enrolled
  # term among that level's rows.
  at_level <- if (is.null(opt$student_level)) enrolled else enrolled %>% filter(student_level %in% opt$student_level)
  entering <- at_level %>%
    group_by(student_id) %>%
    slice_min(term, n = 1L, with_ties = FALSE) %>%
    ungroup()
  n_first_term <- sum(entering$term == first_term)
  entering <- entering %>% filter(term > first_term)
  if (!is.null(opt$term_type)) entering <- entering %>% filter(get_term_type(term) %in% opt$term_type)
  entering <- entering %>% filter(get_term_type(term) %in% c("fall", "spring", "summer"))
  if (!is.null(opt$campus)) entering <- entering %>% filter(student_campus %in% opt$campus)
  if (!is.null(opt$classification)) entering <- entering %>% filter(student_classification %in% opt$classification)
  cedar_debug("[entering-class-retention.R] ", nrow(entering), " entering students to ", fmt_term(edge))

  empty <- tibble::tibble(term = integer(), step = integer(), target_term = integer(), n_entering = integer(),
                          n_here = integer(), here_pct = numeric())
  result <- if (nrow(entering) == 0L) empty else {
    cohort <- entering %>% transmute(student_id, anchor_term = term)
    graduated <- .build_graduated_lookup(if (is.null(degrees)) NULL else degrees %>% filter(term <= edge))
    # The lookup is every level's enrollment: a student who moves level is here.
    followed <- .compute_retention(cohort, .build_enrolled_lookup(enrolled), n_terms, graduated)
    bind_rows(lapply(seq_len(n_terms), function(k) {
      followed %>%
        group_by(term = anchor_term) %>%
        summarize(n_entering = n(), n_here = sum(.data[[paste0("retained_", k)]]), .groups = "drop") %>%
        mutate(step = k, target_term = advance_term(term, k))
    })) %>%
      mutate(n_here = as.integer(n_here),
             here_pct = if_else(n_entering >= min_n, 100 * n_here / n_entering, NA_real_)) %>%
      select(term, step, target_term, n_entering, n_here, here_pct) %>%
      arrange(term, step)
  }
  attr(result, "edge") <- edge
  attr(result, "first_term") <- first_term
  attr(result, "n_first_term") <- n_first_term
  attr(result, "n_terms") <- n_terms
  attr(result, "min_n") <- min_n
  result
}
