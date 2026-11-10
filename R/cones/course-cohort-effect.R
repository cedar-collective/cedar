# course-cohort-effect.R — A course's takers against its non-takers
#
# One question: among the students of one classification in a term, did the
# ones who took course X come back the next regular term, and pass what they
# took next, at different rates from the ones who never took it? The groups
# are passed X, DFW'd X, and never took X. Course Sequence (course-sequence-
# effect.R) needs a later course named and compares takers with everyone else
# who took that later course; Retention (course-retention.R) splits takers by
# outcome and never sees a non-taker. This cone is the comparison a dean asks
# for about a first-year seminar.
#
# The population is cedar_student_terms: enrolled student-terms (CEDAR's one
# definition) in the classifications asked for, scoped by the student's home
# campus (`student_campus`) and grouped by it, because the question is about
# a population, not a course offering; a taker is a member with a classified
# attempt of X in that term on any campus (cedar_attempts, classified once).
# An early drop of X is not taking it and is left out of every group; a
# registered row with no posted grade is a taker whose outcome is unknown and
# is left out too. Both are counted on the result.
#
# Two outcomes, each with its own edge. Return is the table's
# `returned_next_regular_term`, read only where `return_observable`; the
# next-term outcomes are the member's cedar_attempts in `next_regular_term`,
# read only when that term is at or before the graded edge, and the DFW share
# is dfw over classified attempts (an early drop next term is not an
# attempt). An anchor term past the settled enrollment edge is not a cohort.
# Rates are over the observable rows and NA when there are none; the counts
# are always there.
#
# This is a descriptive contrast, never an effect. Students are placed into
# or choose a first-year course, and the three groups differ before the term
# starts. When programs (and applicants) are passed, build_comparison() and
# compute_balance() (branches/comparison.R) report how the takers (passed or
# DFW'd) and the never-takers compare on what CEDAR can see, pooled over the
# anchor terms, each student at their first anchor.
#
# Depends on: cedar_longitudinal_edge() (branches/data-edges.R)
#             build_comparison(), compute_balance() (branches/comparison.R)

#' A course's takers against its non-takers, by return and next-term outcomes
#'
#' @param student_terms `cedar_student_terms`.
#' @param attempts `cedar_attempts`.
#' @param opt `course` (the course id; required), `classification` (one or
#'   more `student_classification` values; required), `term` (anchor terms
#'   to keep; default every term to the settled edge), `campus` (home
#'   campuses to keep; NULL keeps every campus, each its own row), `min_n`
#'   (smallest group a row needs; default 10), `data_edges`
#'   (`cedar_data_edges()` output, required).
#' @param programs `cedar_programs`, for the balance table; NULL skips it.
#' @param applicants `cedar_applicants`, or NULL.
#' @return Named list. `rates`: one row per `term`, `student_campus` and
#'   `group` (`passed`, `dfw`, `none`) with `n_students`, `population` (the
#'   term and campus's members over every group, before suppression),
#'   `share_of_population`, `n_return_observable`, `n_returned`,
#'   `return_pct`, `next_term`, `next_outcomes_observable`,
#'   `n_with_next_attempts`, `next_attempts`, `next_dfw`, `next_dfw_pct`.
#'   `balance`: `compute_balance()` output for takers against never-takers,
#'   or NULL. `course`, `classification`, `edge` (settled), `graded_edge`,
#'   `n_population_student_terms`, `n_early_drops`, `n_unclassified_takers`,
#'   `suppressed` (the rows under `min_n`: `term`, `student_campus`, `group`,
#'   `n_students`).
get_course_cohort_effect <- function(student_terms, attempts, opt = list(),
                                     programs = NULL, applicants = NULL) {
  course <- opt$course
  if (is.null(course) || length(course) != 1L || is.na(course) || !nzchar(course)) {
    stop("[course-cohort-effect.R] opt$course (one course id) is required.", call. = FALSE)
  }
  classification <- opt$classification
  if (is.null(classification) || length(classification) == 0L) {
    stop("[course-cohort-effect.R] opt$classification is required.", call. = FALSE)
  }
  needed_st <- c("student_id", "term", "enrolled", "student_classification", "student_campus",
                 "next_regular_term", "returned_next_regular_term", "return_observable")
  missing_st <- setdiff(needed_st, names(student_terms))
  if (length(missing_st) > 0) {
    stop("[course-cohort-effect.R] student_terms lacks ", paste(missing_st, collapse = ", "),
         call. = FALSE)
  }
  needed_att <- c("student_id", "term", "subject_course", "outcome", "outcome_category")
  missing_att <- setdiff(needed_att, names(attempts))
  if (length(missing_att) > 0) {
    stop("[course-cohort-effect.R] attempts lacks ", paste(missing_att, collapse = ", "), call. = FALSE)
  }
  min_n <- as.integer(opt$min_n %||% 10L)
  edge <- cedar_longitudinal_edge(opt$data_edges)
  if (is.null(edge)) {
    stop("[course-cohort-effect.R] opt$data_edges has no settled enrollment edge (last_enrolled_complete).",
         call. = FALSE)
  }
  graded_edge <- opt$data_edges[["last_graded"]]
  if (is.null(graded_edge)) {
    stop("[course-cohort-effect.R] opt$data_edges has no graded edge (last_graded).", call. = FALSE)
  }
  graded_edge <- as.integer(graded_edge)

  members <- student_terms %>%
    filter(enrolled, student_classification %in% classification, term <= edge)
  if (!is.null(opt$term)) members <- members %>% filter(term %in% as.integer(opt$term))
  if (!is.null(opt$campus)) members <- members %>% filter(student_campus %in% opt$campus)
  members <- members %>%
    select(student_id, term, student_campus, next_regular_term,
           returned_next_regular_term, return_observable)
  cedar_debug("[course-cohort-effect.R] ", nrow(members), " member student-terms to ", edge)

  x <- attempts %>%
    filter(subject_course == course) %>%
    group_by(student_id, term) %>%
    summarize(
      x_outcome = case_when(
        any(outcome %in% "dfw") ~ "dfw",
        any(outcome %in% "pass") ~ "passed",
        all(outcome_category %in% "early_drop") ~ "early_drop",
        TRUE ~ "unclassified"
      ),
      .groups = "drop"
    )

  members <- members %>%
    left_join(x, by = c("student_id", "term")) %>%
    mutate(group = if_else(is.na(x_outcome), "none", x_outcome))
  n_early <- sum(members$group == "early_drop")
  n_unclassified <- sum(members$group == "unclassified")
  n_members <- nrow(members)
  # The population is every member, the left-out rows included, so a group's
  # share says how much of the classification it is.
  population <- members %>%
    group_by(term, student_campus) %>%
    summarize(population = n(), .groups = "drop")
  members <- members %>% filter(group %in% c("passed", "dfw", "none"))

  # The next term's classified attempts, per member, read only when that term
  # has posted grades.
  next_outcomes <- members %>%
    select(student_id, term, next_regular_term) %>%
    inner_join(
      attempts %>% filter(!is.na(outcome)) %>% select(student_id, next_term = term, outcome),
      by = c("student_id", "next_regular_term" = "next_term")
    ) %>%
    group_by(student_id, term) %>%
    summarize(next_attempts = n(), next_dfw = sum(outcome == "dfw"), .groups = "drop")

  scored <- members %>%
    left_join(next_outcomes, by = c("student_id", "term")) %>%
    mutate(
      next_outcomes_observable = !is.na(next_regular_term) & next_regular_term <= graded_edge,
      next_attempts = if_else(next_outcomes_observable, coalesce(next_attempts, 0L), NA_integer_),
      next_dfw      = if_else(next_outcomes_observable, coalesce(next_dfw, 0L), NA_integer_)
    )

  rate_or_na <- function(num, den) if_else(den > 0L, num / den, NA_real_)
  rates <- scored %>%
    group_by(term, student_campus, group) %>%
    summarize(
      n_students = n(),
      n_return_observable = sum(return_observable),
      n_returned = sum(returned_next_regular_term[return_observable]),
      next_term = {
        nt <- unique(next_regular_term)
        if (length(nt) == 1L) nt else NA_integer_
      },
      next_outcomes_observable = all(next_outcomes_observable),
      n_with_next_attempts = sum(next_attempts > 0L, na.rm = TRUE),
      next_attempts = if (all(next_outcomes_observable)) sum(next_attempts) else NA_integer_,
      next_dfw      = if (all(next_outcomes_observable)) sum(next_dfw) else NA_integer_,
      .groups = "drop"
    ) %>%
    inner_join(population, by = c("term", "student_campus")) %>%
    mutate(
      share_of_population = n_students / population,
      return_pct   = 100 * rate_or_na(n_returned, n_return_observable),
      next_dfw_pct = 100 * rate_or_na(next_dfw, next_attempts),
      group = factor(group, levels = c("passed", "dfw", "none"))
    ) %>%
    arrange(term, student_campus, group) %>%
    mutate(group = as.character(group)) %>%
    select(term, student_campus, group, n_students, population, share_of_population,
           n_return_observable, n_returned, return_pct,
           next_term, next_outcomes_observable, n_with_next_attempts,
           next_attempts, next_dfw, next_dfw_pct)

  suppressed <- rates %>% filter(n_students < min_n) %>% select(term, student_campus, group, n_students)
  rates <- rates %>% filter(n_students >= min_n)

  balance <- NULL
  if (!is.null(programs)) {
    first_anchor <- scored %>%
      arrange(student_id, term) %>%
      distinct(student_id, .keep_all = TRUE) %>%
      transmute(student_id, group, covariate_term = as.integer(term))
    takers <- first_anchor$student_id[first_anchor$group %in% c("passed", "dfw")]
    never  <- first_anchor$student_id[first_anchor$group == "none"]
    if (length(takers) == 0L || length(never) == 0L) {
      stop("[course-cohort-effect.R] balance needs takers and never-takers; found ",
           length(takers), " and ", length(never), ".", call. = FALSE)
    }
    comparison <- build_comparison(
      treatment_ids = takers, pool_ids = never, programs = programs, applicants = applicants,
      covariate_terms = first_anchor %>% select(student_id, covariate_term),
      student_terms = student_terms
    )
    balance <- comparison$balance
  }

  cedar_debug("[course-cohort-effect.R] ", nrow(rates), " rows (", nrow(suppressed), " under min_n ", min_n, ")")
  list(
    rates = rates,
    balance = balance,
    course = course,
    classification = classification,
    edge = edge,
    graded_edge = graded_edge,
    n_population_student_terms = n_members,
    n_early_drops = n_early,
    n_unclassified_takers = n_unclassified,
    suppressed = suppressed
  )
}
