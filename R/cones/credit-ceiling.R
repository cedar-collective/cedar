# credit-ceiling.R — Where are students when they pass the attempted-credit ceiling?
#
# One question: of the students whose attempted credits pass the ceiling (160,
# a general standard for aid) with no degree yet, where did those credits come
# from, and what happens in the terms after?
#
#   Attempted     the student's running attempted credits, credit brought from
#                 elsewhere included: build_credit_timeline()'s
#                 `total_credits_after`, the one sanctioned per-term position
#                 (field-reliability.md). On the attempted basis throughout.
#   Passing       the first enrolled term that ends at or past the ceiling,
#                 having begun under it. Level and home campus are that
#                 term's. A student already past it in their first term on
#                 record did not pass it where it can be seen
#                 (`n_already_past`), and one whose record began before the
#                 class lists has no readable total (`n_not_readable`,
#                 `timeline_valid`): both are counted, neither is placed.
#   No degree     a student awarded a degree before the passing term is
#                 working on another and is left out (`n_prior_degree`).
#   Where from    three parts of the total at the passing term: brought from
#                 elsewhere, completed here, attempted here and not completed
#                 (failed, withdrawn, incomplete or repeated without credit).
#   What next     at the passing term and each regular term after it: awarded
#                 a degree by then, enrolled, or not enrolled. A step is
#                 counted only for students whose target term is settled and
#                 within the degree edge, so the denominators shrink with the
#                 step and each row says its own.
#   Edges         passing terms run to the grade-dependent longitudinal edge:
#                 the completed part needs the term's grades.
#   Not a claim   that anyone lost aid: the data holds no aid record
#                 (R/lists/aid_progress.R).
#
# Depends on: build_credit_timeline() (branches/credit-timeline.R)
#             cedar_longitudinal_edge() (branches/data-edges.R)
#             advance_term() (branches/cedar-terms.R), EXIT_CREDIT_CEILING

#' Students passing the attempted-credit ceiling without a degree
#'
#' @param student_terms `cedar_student_terms`.
#' @param programs `cedar_programs`, for the credit brought from elsewhere.
#' @param degrees `cedar_degrees`.
#' @param opt `data_edges` (required: settled, graded and degree edges),
#'   `student_level`, `campus` (of the passing term; NULL keeps all),
#'   `credit_ceiling` (default `EXIT_CREDIT_CEILING`), `n_terms` (regular
#'   terms followed after passing; default 4).
#' @return list(`students` one row per student who passed: `student_id`,
#'   `term`, `primary_major_code`, `student_campus`, `total`, `elsewhere`,
#'   `completed_here`, `not_completed_here`; `by_term` (`term`, `n`);
#'   `outcomes` one row per step 0..`n_terms`: `step`, `n_observed`,
#'   `n_degree`, `n_enrolled`, `n_gone`; `meta`).
get_credit_ceiling_crossings <- function(student_terms, programs, degrees, opt = list()) {
  needed <- c("student_id", "term", "enrolled", "student_level", "student_campus", "primary_major_code",
              "cumulative_completed_unm_credits")
  missing <- setdiff(needed, names(student_terms))
  if (length(missing) > 0L) {
    stop("[credit-ceiling.R] student_terms lacks ", paste(missing, collapse = ", "), call. = FALSE)
  }
  if (!all(c("student_id", "term") %in% names(degrees))) {
    stop("[credit-ceiling.R] degrees lacks student_id or term.", call. = FALSE)
  }
  edge <- cedar_longitudinal_edge(opt$data_edges, grade_dependent = TRUE)
  settled <- cedar_longitudinal_edge(opt$data_edges)
  degree_edge <- opt$data_edges[["last_degree"]]
  if (is.null(edge) || is.null(degree_edge)) {
    stop("[credit-ceiling.R] opt$data_edges needs settled, graded and degree edges.", call. = FALSE)
  }
  ceiling <- as.numeric(opt$credit_ceiling %||% EXIT_CREDIT_CEILING)
  n_terms <- as.integer(opt$n_terms %||% 4L)

  enrolled <- student_terms %>% filter(enrolled, term <= settled) %>% mutate(term = as.integer(term))
  timeline <- build_credit_timeline(enrolled, programs) %>% mutate(term = as.integer(term))
  # Each student's first enrolled term at or past the ceiling.
  first_past <- enrolled %>%
    select(all_of(needed)) %>%
    inner_join(timeline, by = c("student_id", "term"), relationship = "one-to-one") %>%
    filter(total_credits_after >= ceiling) %>%
    arrange(student_id, term) %>%
    distinct(student_id, .keep_all = TRUE) %>%
    filter(term <= edge)
  if (!is.null(opt$student_level)) first_past <- first_past %>% filter(student_level %in% opt$student_level)
  if (!is.null(opt$campus)) first_past <- first_past %>% filter(student_campus %in% opt$campus)

  awarded <- degrees %>% transmute(student_id, degree_term = as.integer(term)) %>% filter(degree_term <= degree_edge)
  prior <- first_past %>%
    inner_join(awarded, by = "student_id", relationship = "many-to-many") %>%
    filter(degree_term < term) %>%
    distinct(student_id)
  candidates <- first_past %>% anti_join(prior, by = "student_id")
  readable <- candidates %>% filter(timeline_valid)
  passed <- readable %>% filter(total_credits_entering < ceiling)
  cedar_debug("[credit-ceiling.R] ", nrow(passed), " passed ", ceiling, "; ", nrow(candidates) - nrow(readable),
              " not readable; ", nrow(readable) - nrow(passed), " already past")

  students <- passed %>%
    transmute(student_id, term, primary_major_code, student_campus, total = total_credits_after,
              elsewhere = transfer_credits,
              completed_here = as.numeric(cumulative_completed_unm_credits),
              not_completed_here = unm_credits_after - as.numeric(cumulative_completed_unm_credits))

  here <- enrolled %>% distinct(student_id, target_term = term) %>% mutate(here = TRUE)
  first_degree <- awarded %>% group_by(student_id) %>% summarize(degree_term = min(degree_term), .groups = "drop")
  outcomes <- bind_rows(lapply(0:n_terms, function(k) {
    students %>%
      transmute(student_id, step = k, target_term = if (k == 0L) term else advance_term(term, k)) %>%
      filter(target_term <= settled, target_term <= degree_edge)
  })) %>%
    left_join(here, by = c("student_id", "target_term"), relationship = "many-to-one") %>%
    left_join(first_degree, by = "student_id", relationship = "many-to-one") %>%
    mutate(degree = !is.na(degree_term) & degree_term <= target_term, here = here %in% TRUE & !degree) %>%
    group_by(step) %>%
    summarize(n_observed = n(), n_degree = sum(degree), n_enrolled = sum(here),
              n_gone = sum(!degree & !here), .groups = "drop")
  outcomes <- tibble::tibble(step = 0:n_terms) %>%
    left_join(outcomes, by = "step", relationship = "one-to-one") %>%
    mutate(across(c(n_observed, n_degree, n_enrolled, n_gone), ~ dplyr::coalesce(.x, 0L)))

  list(
    students = students,
    by_term = students %>% count(term, name = "n") %>% arrange(term),
    outcomes = outcomes,
    meta = list(ceiling = ceiling, edge = edge, settled_edge = settled, degree_edge = degree_edge,
                n_passed = nrow(students), n_prior_degree = nrow(prior),
                n_not_readable = nrow(candidates) - nrow(readable),
                n_already_past = nrow(readable) - nrow(passed), n_terms = n_terms)
  )
}
