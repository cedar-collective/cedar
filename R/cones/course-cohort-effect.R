# course-cohort-effect.R — A course's takers against its non-takers
#
# One question: among the students of one classification in a term, did the
# ones who took course X come back the next regular term, and pass what they
# took next, at different rates from the ones who never took it? The groups
# are passed X, DFW'd X, and never took X. Course Sequence (course-sequence-
# effect.R) needs a later course named and compares takers with everyone else
# who took that later course; Retention (course-retention.R) splits takers by
# outcome and never sees a non-taker. This cone is the comparison a dean asks
# for about a first-year seminar, and, run over every course of a college at
# once, the benchmark that says whether the seminar's gap is unusual
# (features/course-cohort-context.R).
#
# The population is cedar_student_terms: enrolled student-terms (CEDAR's one
# definition) in the classifications asked for, scoped by the student's home
# campus (`student_campus`) and grouped by it, because the question is about
# a population, not a course offering; a taker is a member with a classified
# attempt of X in that term on any campus (cedar_attempts, classified once).
# An early drop of X is not taking it and is in no group; a registered row
# with no posted grade is a taker whose outcome is unknown and is in no group
# either. Both stay in the population and are counted per course on the
# result (`left_out`). The population's own rates are reported too, so a
# group can be read against everyone.
#
# Two outcomes, each with its own edge. Return is the table's
# `returned_next_regular_term`, read only where `return_observable`; the
# next-term outcomes are the member's cedar_attempts in `next_regular_term`,
# read only when that term is at or before the graded edge, and the DFW share
# is dfw over classified attempts (an early drop next term is not an
# attempt). An anchor term past the settled enrollment edge is not a cohort.
# Rates are over the observable rows and NA when there are none; the counts
# are always there. A group nobody is in has no row.
#
# This is a descriptive contrast, never an effect. Students are placed into
# or choose a first-year course, and the three groups differ before the term
# starts. When programs (and applicants) are passed with one course,
# build_comparison() and compute_balance() (branches/comparison.R) report how
# the takers (passed or DFW'd) and the never-takers compare on what CEDAR
# can see, pooled over the anchor terms, each student at their first anchor.
#
# Depends on: cedar_longitudinal_edge() (branches/data-edges.R)
#             build_comparison(), compute_balance() (branches/comparison.R)

#' A course's takers against its non-takers, by return and next-term outcomes
#'
#' @param student_terms `cedar_student_terms`.
#' @param attempts `cedar_attempts`.
#' @param opt `course` (one or more course ids; required), `classification`
#'   (one or more `student_classification` values; required), `term` (anchor
#'   terms to keep; default every term to the settled edge), `campus` (home
#'   campuses to keep; NULL keeps every campus, each its own row), `min_n`
#'   (smallest group a row needs; default 10), `data_edges`
#'   (`cedar_data_edges()` output, required).
#' @param programs `cedar_programs`, for the balance table (one course only);
#'   NULL skips it.
#' @param applicants `cedar_applicants`, or NULL.
#' @return Named list. `rates`: one row per `course`, `term`, `student_campus`
#'   and `group` (`passed`, `dfw`, `none`) with `n_students`, `population`
#'   (the term and campus's members over every group, before suppression),
#'   `share_of_population`, `n_return_observable`, `n_returned`,
#'   `return_pct`, `next_term`, `next_outcomes_observable`,
#'   `n_with_next_attempts`, `next_attempts`, `next_dfw`, `next_dfw_pct`.
#'   `population`: the same measures per `term` and `student_campus` over
#'   every member. `left_out`: per `course`, `term` and `student_campus`,
#'   `n_early_drops` and `n_unclassified` (takers in no group). `balance`:
#'   `compute_balance()` output for takers against never-takers, or NULL.
#'   `courses`, `classification`, `edge` (settled), `graded_edge`,
#'   `n_population_student_terms`, `suppressed` (the rows under `min_n`:
#'   `course`, `term`, `student_campus`, `group`, `n_students`).
get_course_cohort_effect <- function(student_terms, attempts, opt = list(),
                                     programs = NULL, applicants = NULL) {
  courses <- unique(as.character(opt$course))
  if (length(courses) == 0L || any(is.na(courses)) || any(!nzchar(courses))) {
    stop("[course-cohort-effect.R] opt$course (one or more course ids) is required.", call. = FALSE)
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
  if (!is.null(programs) && length(courses) > 1L) {
    stop("[course-cohort-effect.R] the balance table is for one course; ", length(courses), " were asked for.",
         call. = FALSE)
  }

  # ── The population: every member, with its next-term outcomes ─────────────
  members <- student_terms %>%
    filter(enrolled, student_classification %in% classification, term <= edge)
  if (!is.null(opt$term)) members <- members %>% filter(term %in% as.integer(opt$term))
  if (!is.null(opt$campus)) members <- members %>% filter(student_campus %in% opt$campus)
  members <- members %>%
    select(student_id, term, student_campus, next_regular_term,
           returned_next_regular_term, return_observable)
  cedar_debug("[course-cohort-effect.R] ", nrow(members), " member student-terms to ", edge)

  next_outcomes <- members %>%
    select(student_id, term, next_regular_term) %>%
    inner_join(
      attempts %>% filter(!is.na(outcome)) %>% select(student_id, next_term = term, outcome),
      by = c("student_id", "next_regular_term" = "next_term")
    ) %>%
    group_by(student_id, term) %>%
    summarize(next_attempts = n(), next_dfw = sum(outcome == "dfw"), .groups = "drop")

  members <- members %>%
    left_join(next_outcomes, by = c("student_id", "term")) %>%
    mutate(
      # Observability is the term's: the next regular term either has posted
      # grades or has not, for every member of the anchor term.
      next_outcomes_observable = !is.na(next_regular_term) & next_regular_term <= graded_edge,
      next_attempts = if_else(next_outcomes_observable, coalesce(next_attempts, 0L), NA_integer_),
      next_dfw      = if_else(next_outcomes_observable, coalesce(next_dfw, 0L), NA_integer_)
    )

  sum_measures <- function(rows) {
    rows %>% summarize(
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
    )
  }
  rate_or_na <- function(num, den) if_else(!is.na(den) & den > 0L, num / den, NA_real_)
  add_rates <- function(rows) {
    rows %>% mutate(
      return_pct   = 100 * rate_or_na(n_returned, n_return_observable),
      next_dfw_pct = 100 * rate_or_na(next_dfw, next_attempts)
    )
  }

  population <- members %>%
    group_by(term, student_campus) %>%
    sum_measures() %>%
    add_rates() %>%
    rename(population = n_students)

  # ── The takers of each course, in four categories ─────────────────────────
  # CAMPUS_ROLLUP: a student took the course wherever it was taught; the
  # grain the result keeps is the student's home campus (student_campus).
  x <- attempts %>%
    filter(subject_course %in% courses) %>%
    group_by(student_id, term, course = subject_course) %>%
    summarize(
      group = case_when(
        any(outcome %in% "dfw") ~ "dfw",
        any(outcome %in% "pass") ~ "passed",
        all(outcome_category %in% "early_drop") ~ "early_drop",
        TRUE ~ "unclassified"
      ),
      .groups = "drop"
    )
  takers <- members %>% inner_join(x, by = c("student_id", "term"))

  by_category <- takers %>%
    group_by(course, term, student_campus, group) %>%
    sum_measures()

  left_out <- by_category %>%
    filter(group %in% c("early_drop", "unclassified")) %>%
    group_by(course, term, student_campus) %>%
    summarize(
      n_early_drops  = sum(n_students[group == "early_drop"]),
      n_unclassified = sum(n_students[group == "unclassified"]),
      .groups = "drop"
    )

  # ── Never took it: the population less every taker category ───────────────
  measure_cols <- c("n_students", "n_return_observable", "n_returned", "n_with_next_attempts",
                    "next_attempts", "next_dfw")
  taken_any <- by_category %>%
    group_by(course, term, student_campus) %>%
    summarize(across(all_of(measure_cols), ~ sum(.x)), .groups = "drop") %>%
    rename_with(~ paste0(.x, ".taken"), all_of(measure_cols))
  none <- tidyr::expand_grid(course = courses, population %>% select(term, student_campus)) %>%
    inner_join(population %>% rename(n_students = population), by = c("term", "student_campus")) %>%
    left_join(taken_any, by = c("course", "term", "student_campus"))
  for (col in measure_cols) {
    none[[col]] <- none[[col]] - coalesce(none[[paste0(col, ".taken")]], 0L)
  }
  none <- none %>%
    mutate(group = "none") %>%
    select(course, term, student_campus, group, all_of(measure_cols),
           next_term, next_outcomes_observable) %>%
    filter(n_students > 0L)

  rates <- bind_rows(by_category %>% filter(group %in% c("passed", "dfw")), none) %>%
    inner_join(population %>% select(term, student_campus, population), by = c("term", "student_campus")) %>%
    add_rates() %>%
    mutate(
      share_of_population = n_students / population,
      group = factor(group, levels = c("passed", "dfw", "none"))
    ) %>%
    arrange(match(course, courses), term, student_campus, group) %>%
    mutate(group = as.character(group)) %>%
    select(course, term, student_campus, group, n_students, population, share_of_population,
           n_return_observable, n_returned, return_pct,
           next_term, next_outcomes_observable, n_with_next_attempts,
           next_attempts, next_dfw, next_dfw_pct)

  suppressed <- rates %>% filter(n_students < min_n) %>%
    select(course, term, student_campus, group, n_students)
  rates <- rates %>% filter(n_students >= min_n)

  # ── The balance table, one course, takers against never-takers ────────────
  balance <- NULL
  if (!is.null(programs)) {
    first_anchor <- members %>%
      left_join(x %>% select(student_id, term, group), by = c("student_id", "term")) %>%
      mutate(group = coalesce(group, "none")) %>%
      arrange(student_id, term) %>%
      distinct(student_id, .keep_all = TRUE) %>%
      transmute(student_id, group, covariate_term = as.integer(term))
    taker_ids <- first_anchor$student_id[first_anchor$group %in% c("passed", "dfw")]
    never_ids <- first_anchor$student_id[first_anchor$group == "none"]
    if (length(taker_ids) == 0L || length(never_ids) == 0L) {
      stop("[course-cohort-effect.R] balance needs takers and never-takers; found ",
           length(taker_ids), " and ", length(never_ids), ".", call. = FALSE)
    }
    comparison <- build_comparison(
      treatment_ids = taker_ids, pool_ids = never_ids, programs = programs, applicants = applicants,
      covariate_terms = first_anchor %>% select(student_id, covariate_term),
      student_terms = student_terms
    )
    balance <- comparison$balance
  }

  cedar_debug("[course-cohort-effect.R] ", nrow(rates), " rows over ", length(courses), " courses (",
              nrow(suppressed), " under min_n ", min_n, ")")
  list(
    rates = rates,
    population = population %>%
      select(term, student_campus, population, n_return_observable, n_returned, return_pct,
             next_term, next_outcomes_observable, n_with_next_attempts, next_attempts, next_dfw,
             next_dfw_pct),
    left_out = left_out,
    balance = balance,
    courses = courses,
    classification = classification,
    edge = edge,
    graded_edge = graded_edge,
    n_population_student_terms = nrow(members),
    suppressed = suppressed
  )
}
