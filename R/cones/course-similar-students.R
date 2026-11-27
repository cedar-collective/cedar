# course-similar-students.R — A course's takers against similar non-takers
#
# One question: did the students who took course X do better that term and
# the next than students like them who did not take it? "Like them" is a
# cell: the same anchor term, home campus, high-school GPA band and time
# status (full or part time); with `programs`, the same Pell eligibility and
# first-generation status that term too; with `opt$match_credits`, the same
# band of UNM credits already earned (none, 1 to 14, 15 or more, from the
# credit timeline, so a student with dual-credit or earlier terms is set
# beside others with them). A value not on record is its own cell, never
# dropped and never guessed. These are what the records hold for nearly
# every student; ACT is not among them (optional since 2020, on file for a
# small and falling share) and age is not (the admissions table holds age at
# the pull, a frozen field). Inside each cell the non-takers supply a rate;
# weighting those rates by the takers' own mix across cells gives the rate
# the takers would have had if they had done as their non-taking peers did
# (direct standardization). The gap is actual minus expected.
#
# The raw comparison with non-takers (course-cohort-effect.R) puts the raw groups side by
# side per term; this cone pools the terms and removes what the cells can
# see, so one course, or every course a population takes, or one course's
# instructors, can be read on one scale.
#
# Three outcomes, each with its own observability:
#   return           `returned_next_regular_term`, where `return_observable`.
#   other-course DFW the DFW share of the student's OTHER classified attempts
#                    in the anchor term (the course itself is left out of its
#                    own takers' rate and of nobody else's); anchor terms to
#                    the graded edge.
#   next-term GPA    the semester GPA of the next regular term, for students
#                    who returned and have one; next terms to the graded edge.
#                    It is conditional on returning, so it is read beside the
#                    return gap, never instead of it.
#
# Who the non-takers are: by default every member of the cell without a row
# in the course. With `comparison_courses` (Gen Ed, say), only members with a
# classified attempt in one of those courses that term: "students like them
# in Gen Ed courses", not "students like them". The takers are the same
# either way; a taker who also took a comparison course is a taker.
#
# A taker is a member with a classified attempt (pass or DFW) of the course
# in the anchor term, on any campus. A member whose only rows are an early
# drop or an ungraded registration is neither a taker nor a non-taker of
# that course. A cell with fewer than `min_cell_n` non-takers supplies no
# rate: its takers are left out of both sides and counted (`n_takers` less
# `n_covered`).
#
# Were the matched students alike? The cells cannot say: they are alike on
# what is in the cells by construction. So the same comparison is run on a
# measure taken before college that the cells do not hold and the course
# cannot have changed, the ACT composite where one is on file: the takers'
# average against what their non-taking peers averaged, cell by cell. A gap
# there is the students, not the course, and whatever made it is in every
# outcome gap too. `act_gap_smd` is that gap in the non-takers' standard
# deviations (classify_smd_balance() reads it).
#
# Descriptive, never an effect: the cells remove what they name and nothing
# else. Placement, advising, major and
# motivation are not in them, and a course students are placed into shows
# its placement here. At the instructor grain a section tied to a program or
# a learning community shows that program, not the teaching. Each gap's
# standard error is chance at the expected rates: binomial for return and
# for other-course DFW (attempts counted as independent), the non-takers'
# own spread of GPAs for next-term GPA. It ignores the error in the
# non-takers' rates and so is a floor.
#
# Depends on: cedar_longitudinal_edge() (branches/data-edges.R)
#             hs_gpa_band(), applicant_hs_gpa(), student_term_aid()
#               (branches/comparison.R)

# What decides who is compared with whom: every option and input the prepared
# rows depend on, resolved and checked. A row grain, one course or a threshold
# changes what is read off those rows, never the rows, and is not here.
.course_similar_scope <- function(opt, programs) {
  classification <- opt$classification
  if (is.null(classification) || length(classification) == 0L) {
    stop("[course-similar-students.R] opt$classification is required.", call. = FALSE)
  }
  edge <- cedar_longitudinal_edge(opt$data_edges)
  if (is.null(edge)) {
    stop("[course-similar-students.R] opt$data_edges has no settled enrollment edge (last_enrolled_complete).",
         call. = FALSE)
  }
  graded_edge <- opt$data_edges[["last_graded"]]
  if (is.null(graded_edge)) {
    stop("[course-similar-students.R] opt$data_edges has no graded edge (last_graded).", call. = FALSE)
  }
  comparison <- opt$comparison_courses
  if (!is.null(comparison)) {
    comparison <- unique(as.character(comparison))
    if (length(comparison) == 0L || anyNA(comparison)) {
      stop("[course-similar-students.R] opt$comparison_courses must name at least one course.", call. = FALSE)
    }
  }
  list(classification = classification, term = opt$term, campus = opt$campus,
       match_credits = isTRUE(opt$match_credits), comparison_courses = comparison,
       with_aid = !is.null(programs), edge = edge, graded_edge = as.integer(graded_edge))
}

#' The members, their cells and their courses, built once for several readings
#'
#' Everything `get_course_similar_students()` reads that does not depend on
#' which rows are asked for: the members with their outcomes, each member's
#' courses that term, and the non-takers' rates for every course in every
#' cell. Reading the comparison for every course, for every course term by
#' term and for one course's instructors is three readings of one of these;
#' a caller that wants more than one builds it once and passes it as
#' `prepared` (rebuilding it for each was 40 of the 50 seconds an Against
#' Non-Takers run took; ISSUES M68).
#'
#' @param student_terms,attempts,applicants,programs As
#'   `get_course_similar_students()` takes them.
#' @param opt `classification`, `term`, `campus`, `match_credits`,
#'   `comparison_courses` and `data_edges`, as there. `course`, `grain`,
#'   `by_term`, `min_n` and `min_cell_n` are not read.
#' @return A `course_similar_students_prepared` list: `scope` (the options it
#'   was built for), `cells` (the cell columns), `touched` (one row per
#'   member and course that term, with the member's cell and outcomes),
#'   `non_takers` (one row per course and cell: the non-takers' count and
#'   rates), `n_population_student_terms`, `n_comparison_student_terms`.
prepare_course_similar_students <- function(student_terms, attempts, applicants, opt = list(), programs = NULL) {
  scope <- .course_similar_scope(opt, programs)
  classification <- scope$classification
  edge <- scope$edge
  graded_edge <- scope$graded_edge
  comparison <- scope$comparison_courses
  if (is.null(applicants)) {
    stop("[course-similar-students.R] applicants (cedar_applicants) is required: the cells need the ",
         "high-school GPA band.", call. = FALSE)
  }
  needed_st <- c("student_id", "term", "enrolled", "student_classification", "student_campus", "time_status",
                 "sem_gpa", "next_regular_term", "returned_next_regular_term", "return_observable")
  missing_st <- setdiff(needed_st, names(student_terms))
  if (length(missing_st) > 0) {
    stop("[course-similar-students.R] student_terms lacks ", paste(missing_st, collapse = ", "), call. = FALSE)
  }
  needed_att <- c("student_id", "term", "subject_course", "outcome", "instructor_id", "instructor_name")
  missing_att <- setdiff(needed_att, names(attempts))
  if (length(missing_att) > 0) {
    stop("[course-similar-students.R] attempts lacks ", paste(missing_att, collapse = ", "), call. = FALSE)
  }
  cell_cols <- c("term", "student_campus", "hs_gpa_band", "time_status",
                 if (!is.null(programs)) c("pell", "first_gen"),
                 if (isTRUE(opt$match_credits)) "credits_band")
  if (isTRUE(opt$match_credits)) {
    missing_c <- setdiff(c("unm_credits_entering", "timeline_valid"), names(student_terms))
    if (length(missing_c) > 0) {
      stop("[course-similar-students.R] student_terms lacks ", paste(missing_c, collapse = ", "), call. = FALSE)
    }
  }

  # ── The population, one row per member, with its three outcomes ───────────
  members <- student_terms %>%
    filter(enrolled, student_classification %in% classification, term <= edge)
  if (!is.null(opt$term)) members <- members %>% filter(term %in% as.integer(opt$term))
  if (!is.null(opt$campus)) members <- members %>% filter(student_campus %in% opt$campus)
  next_gpas <- student_terms %>%
    filter(enrolled, term <= graded_edge, !is.na(sem_gpa)) %>%
    select(student_id, next_regular_term = term, next_gpa = sem_gpa)
  members <- members %>%
    select(student_id, term, student_campus, time_status, next_regular_term,
           returned_next_regular_term, return_observable,
           any_of(c("unm_credits_entering", "timeline_valid"))) %>%
    left_join(applicant_hs_gpa(applicants, with_act = TRUE), by = "student_id") %>%
    left_join(next_gpas, by = c("student_id", "next_regular_term")) %>%
    mutate(
      hs_gpa_band = hs_gpa_band(high_school_cum_gpa),
      time_status = coalesce(as.character(time_status), "not recorded"),
      ret_obs = as.integer(return_observable %in% TRUE),
      ret     = as.integer(return_observable %in% TRUE & returned_next_regular_term %in% TRUE),
      gpa_n   = as.integer(!is.na(next_gpa)),
      gpa_sum = coalesce(next_gpa, 0),
      gpa_sq  = coalesce(next_gpa^2, 0),
      act_n   = as.integer(!is.na(act_score)),
      act_sum = coalesce(act_score, 0),
      act_sq  = coalesce(act_score^2, 0)
    )
  if (!is.null(programs)) {
    members <- members %>%
      left_join(student_term_aid(programs), by = c("student_id", "term")) %>%
      mutate(pell = coalesce(pell, "not recorded"), first_gen = coalesce(first_gen, "not recorded"))
  }
  if (isTRUE(opt$match_credits)) {
    members <- members %>%
      mutate(credits_band = case_when(
        !(timeline_valid %in% TRUE) | is.na(unm_credits_entering) ~ "not recorded",
        unm_credits_entering <= 0 ~ "none",
        unm_credits_entering < 15 ~ "1 to 14",
        TRUE ~ "15 or more"))
  }
  cedar_debug("[course-similar-students.R] ", nrow(members), " member student-terms to ", edge)

  # One row per member and course, counted over the rows at once: which
  # member-course each attempt row belongs to, then how many of its rows are
  # classified and how many are DFW. A classified row sorts first, so the
  # first row's instructor is the classified attempt's.
  # CAMPUS_ROLLUP: a student took the course wherever it was taught; the grain
  # kept is the student's home campus (student_campus), which is in the cell.
  attempt_rows <- attempts %>%
    semi_join(members, by = c("student_id", "term")) %>%
    arrange(student_id, term, subject_course, is.na(outcome)) %>%
    group_by(student_id, term, course = subject_course)
  row_course <- group_indices(attempt_rows)
  touched <- group_keys(attempt_rows)
  first_row <- match(seq_len(nrow(touched)), row_course)
  touched <- touched %>%
    mutate(att = tabulate(row_course[!is.na(attempt_rows$outcome)], nrow(touched)),
           dfw = tabulate(row_course[attempt_rows$outcome %in% "dfw"], nrow(touched)),
           instructor_id = attempt_rows$instructor_id[first_row],
           instructor_name = attempt_rows$instructor_name[first_row])
  totals <- touched %>%
    filter(term <= graded_edge) %>%
    group_by(student_id, term) %>%
    summarize(tot_att = sum(att), tot_dfw = sum(dfw), .groups = "drop")
  members <- members %>%
    left_join(totals, by = c("student_id", "term")) %>%
    mutate(tot_att = if_else(term <= graded_edge, coalesce(tot_att, 0L), 0L),
           tot_dfw = if_else(term <= graded_edge, coalesce(tot_dfw, 0L), 0L))
  # Who may stand as a non-taker (see the header).
  members$in_comparison <- if (is.null(comparison)) TRUE else {
    holders <- touched %>% filter(course %in% comparison, att > 0L) %>% distinct(student_id, term)
    paste(members$student_id, members$term) %in% paste(holders$student_id, holders$term)
  }

  measures <- c("n", "ret_obs", "ret", "gpa_n", "gpa_sum", "gpa_sq", "tot_att", "tot_dfw",
                "act_n", "act_sum", "act_sq")
  cells <- members %>%
    filter(in_comparison) %>%
    group_by(across(all_of(cell_cols))) %>%
    summarize(n = n(), across(all_of(measures[-1]), sum), .groups = "drop") %>%
    rename_with(~ paste0(.x, ".cell"), all_of(measures))

  touched <- touched %>%
    inner_join(members %>% select(student_id, term, all_of(cell_cols[-1]), all_of(measures[-1]), in_comparison),
               by = c("student_id", "term")) %>%
    mutate(n = 1L, taker = att > 0L,
           # A taker's other courses: the term's attempts less this course's.
           other_att = if_else(term <= graded_edge, tot_att - att, 0L),
           other_dfw = if_else(term <= graded_edge, tot_dfw - dfw, 0L))

  # The non-takers of each course in each cell: the cell (its comparison
  # members) less those of them with a row in the course, and the rate they
  # supply. A cell where none of a course's holders is a comparison member
  # subtracts nothing.
  holder_sums <- touched %>%
    filter(in_comparison) %>%
    group_by(course, across(all_of(cell_cols))) %>%
    summarize(across(all_of(measures), sum), .groups = "drop")
  non_takers <- touched %>%
    distinct(course, across(all_of(cell_cols))) %>%
    left_join(holder_sums, by = c("course", cell_cols)) %>%
    mutate(across(all_of(measures), ~ coalesce(as.numeric(.x), 0))) %>%
    # A cell with no comparison member has no non-takers: its takers are
    # not covered, never dropped.
    left_join(cells, by = cell_cols) %>%
    mutate(across(ends_with(".cell"), ~ coalesce(as.numeric(.x), 0))) %>%
    transmute(
      course, across(all_of(cell_cols)),
      nt_n = n.cell - n,
      nt_return = if_else(ret_obs.cell - ret_obs > 0L, (ret.cell - ret) / (ret_obs.cell - ret_obs), NA_real_),
      nt_dfw    = if_else(tot_att.cell - tot_att > 0L, (tot_dfw.cell - tot_dfw) / (tot_att.cell - tot_att), NA_real_),
      nt_gpa    = if_else(gpa_n.cell - gpa_n > 0L, (gpa_sum.cell - gpa_sum) / (gpa_n.cell - gpa_n), NA_real_),
      nt_gpa_var = if_else(gpa_n.cell - gpa_n > 0L,
                           pmax((gpa_sq.cell - gpa_sq) / (gpa_n.cell - gpa_n) - nt_gpa^2, 0), NA_real_),
      nt_act    = if_else(act_n.cell - act_n > 0L, (act_sum.cell - act_sum) / (act_n.cell - act_n), NA_real_),
      nt_act_var = if_else(act_n.cell - act_n > 0L,
                           pmax((act_sq.cell - act_sq) / (act_n.cell - act_n) - nt_act^2, 0), NA_real_)
    )

  structure(
    list(scope = scope, cells = cell_cols, touched = touched, non_takers = non_takers,
         n_population_student_terms = nrow(members),
         n_comparison_student_terms = sum(members$in_comparison)),
    class = "course_similar_students_prepared"
  )
}

#' A course's takers against non-takers of the same term, campus, HS GPA band and time status
#'
#' @param student_terms `cedar_student_terms`.
#' @param attempts `cedar_attempts`.
#' @param applicants `cedar_applicants` (the high-school GPA band).
#' @param opt `classification` (one or more `student_classification` values;
#'   required), `course` (course ids; NULL reads every course with `min_n`
#'   takers), `term` (anchor terms; default every term to the settled edge),
#'   `campus` (home campuses; NULL keeps every campus, each its own cell),
#'   `grain` (`"course"`, the default, or `"instructor"`: a course's takers
#'   by the instructor of their attempt, against the course's non-takers),
#'   `by_term` (TRUE gives one row per anchor term as well, with `term`
#'   after the course: the same comparison term by term, for change over
#'   time; default FALSE pools the terms),
#'   `comparison_courses` (course ids: the non-takers are only members with
#'   a classified attempt in one of them that term; NULL, the default, every
#'   member without a row in the course),
#'   `min_n` (smallest covered taker count a row needs; default 30),
#'   `min_cell_n` (smallest non-taker count a cell needs; default 5),
#'   `match_credits` (TRUE adds the band of UNM credits already earned to
#'   the cells; default FALSE),
#'   `data_edges` (`cedar_data_edges()` output, required).
#' @param programs `cedar_programs`, optional: given, Pell eligibility and
#'   first-generation status that term are cells too.
#' @param prepared `prepare_course_similar_students()` output for the same
#'   classification, term, campus, match_credits, comparison_courses,
#'   data_edges and programs, optional: given, the members and their cells
#'   are not rebuilt. One built for other options stops.
#' @return A tibble, one row per `course` (and `instructor_id`,
#'   `instructor_name` at the instructor grain): `n_takers`, `n_covered`,
#'   `n_terms`; `return_n`, `return_pct`, `return_expected_pct`,
#'   `return_gap`, `return_gap_se`; `other_attempts`, `other_dfw_pct`,
#'   `other_dfw_expected_pct`, `other_dfw_gap`, `other_dfw_gap_se`;
#'   `next_gpa_n`, `next_gpa`, `next_gpa_expected`, `next_gpa_gap`,
#'   `next_gpa_gap_se`; `act_n`, `act`, `act_expected`, `act_gap`,
#'   `act_gap_se`, `act_gap_smd` (the alike check: takers with an ACT score
#'   in cells whose non-takers have one). Gaps are actual minus expected (a
#'   positive DFW gap is worse); an outcome with nothing observable is NA.
#'   Attributes: `edge`, `graded_edge`, `n_population_student_terms`,
#'   `cells` (the cell columns), `suppressed` (rows under `min_n`),
#'   `comparison_courses` (as given, NULL for every non-taker),
#'   `n_comparison_student_terms` (the members who may stand as non-takers:
#'   every member without comparison courses).
get_course_similar_students <- function(student_terms, attempts, applicants, opt = list(), programs = NULL,
                                        prepared = NULL) {
  grain <- opt$grain %||% "course"
  if (!grain %in% c("course", "instructor")) {
    stop("[course-similar-students.R] opt$grain must be \"course\" or \"instructor\", not ", grain, call. = FALSE)
  }
  min_n <- as.integer(opt$min_n %||% 30L)
  min_cell_n <- as.integer(opt$min_cell_n %||% 5L)
  scope <- .course_similar_scope(opt, programs)
  if (is.null(prepared)) {
    prepared <- prepare_course_similar_students(student_terms, attempts, applicants, opt, programs)
  } else if (!inherits(prepared, "course_similar_students_prepared") || !identical(prepared$scope, scope)) {
    stop("[course-similar-students.R] `prepared` was built for other options: build it with ",
         "prepare_course_similar_students() from the same classification, term, campus, match_credits, ",
         "comparison_courses, data_edges and programs.", call. = FALSE)
  }
  cell_cols <- prepared$cells
  non_takers <- prepared$non_takers
  touched <- prepared$touched
  if (!is.null(opt$course)) touched <- touched %>% filter(course %in% as.character(opt$course))

  row_cols <- c("course", if (grain == "instructor") c("instructor_id", "instructor_name"),
                if (isTRUE(opt$by_term)) "term")
  taker_cells <- touched %>%
    filter(taker) %>%
    group_by(across(all_of(union(row_cols, cell_cols)))) %>%
    summarize(n = n(), ret_obs = sum(ret_obs), ret = sum(ret), gpa_n = sum(gpa_n), gpa_sum = sum(gpa_sum),
              other_att = sum(other_att), other_dfw = sum(other_dfw),
              act_n = sum(act_n), act_sum = sum(act_sum), .groups = "drop") %>%
    inner_join(non_takers, by = c("course", cell_cols)) %>%
    mutate(covered = nt_n >= min_cell_n)

  # Each outcome is read over the covered cells where the non-takers have a
  # rate for it; the same cells on both sides of every gap.
  ratio <- function(num, den) if_else(den > 0, num / den, NA_real_)
  rows <- taker_cells %>%
    mutate(r_ok = covered & !is.na(nt_return), d_ok = covered & !is.na(nt_dfw), g_ok = covered & !is.na(nt_gpa),
           a_ok = covered & !is.na(nt_act)) %>%
    group_by(across(all_of(row_cols))) %>%
    summarize(
      n_takers = sum(n), n_covered = sum(n[covered]), n_terms = n_distinct(term[covered]),
      return_n = sum(ret_obs[r_ok]),
      .ret = sum(ret[r_ok]), .ret_exp = sum(ret_obs[r_ok] * nt_return[r_ok]),
      .ret_var = sum(ret_obs[r_ok] * nt_return[r_ok] * (1 - nt_return[r_ok])),
      other_attempts = sum(other_att[d_ok]),
      .dfw = sum(other_dfw[d_ok]), .dfw_exp = sum(other_att[d_ok] * nt_dfw[d_ok]),
      .dfw_var = sum(other_att[d_ok] * nt_dfw[d_ok] * (1 - nt_dfw[d_ok])),
      next_gpa_n = sum(gpa_n[g_ok]),
      .gpa = sum(gpa_sum[g_ok]), .gpa_exp = sum(gpa_n[g_ok] * nt_gpa[g_ok]),
      .gpa_var = sum(gpa_n[g_ok] * nt_gpa_var[g_ok]),
      .act_n = sum(act_n[a_ok]),
      .act = sum(act_sum[a_ok]), .act_exp = sum(act_n[a_ok] * nt_act[a_ok]),
      .act_var = sum(act_n[a_ok] * nt_act_var[a_ok]),
      .groups = "drop"
    ) %>%
    mutate(
      return_pct = 100 * ratio(.ret, return_n), return_expected_pct = 100 * ratio(.ret_exp, return_n),
      return_gap = return_pct - return_expected_pct, return_gap_se = 100 * ratio(sqrt(.ret_var), return_n),
      other_dfw_pct = 100 * ratio(.dfw, other_attempts),
      other_dfw_expected_pct = 100 * ratio(.dfw_exp, other_attempts),
      other_dfw_gap = other_dfw_pct - other_dfw_expected_pct,
      other_dfw_gap_se = 100 * ratio(sqrt(.dfw_var), other_attempts),
      next_gpa = ratio(.gpa, next_gpa_n), next_gpa_expected = ratio(.gpa_exp, next_gpa_n),
      next_gpa_gap = next_gpa - next_gpa_expected,
      next_gpa_gap_se = ratio(sqrt(.gpa_var), next_gpa_n),
      act_n = as.integer(.act_n),
      act = ratio(.act, act_n), act_expected = ratio(.act_exp, act_n),
      act_gap = act - act_expected, act_gap_se = ratio(sqrt(.act_var), act_n),
      # In the non-takers' standard deviations, pooled over the takers' cells.
      act_gap_smd = if_else(.act_var > 0, act_gap / sqrt(ratio(.act_var, act_n)), NA_real_)
    ) %>%
    select(all_of(row_cols), n_takers, n_covered, n_terms,
           return_n, return_pct, return_expected_pct, return_gap, return_gap_se,
           other_attempts, other_dfw_pct, other_dfw_expected_pct, other_dfw_gap, other_dfw_gap_se,
           next_gpa_n, next_gpa, next_gpa_expected, next_gpa_gap, next_gpa_gap_se,
           act_n, act, act_expected, act_gap, act_gap_se, act_gap_smd) %>%
    arrange(desc(return_gap), across(all_of(row_cols)))
  if (isTRUE(opt$by_term)) rows <- rows %>% arrange(across(all_of(row_cols)))

  suppressed <- rows %>% filter(n_covered < min_n) %>% select(all_of(row_cols), n_takers, n_covered)
  result <- rows %>% filter(n_covered >= min_n)
  attr(result, "edge") <- scope$edge
  attr(result, "graded_edge") <- scope$graded_edge
  attr(result, "n_population_student_terms") <- prepared$n_population_student_terms
  attr(result, "cells") <- cell_cols
  attr(result, "suppressed") <- suppressed
  attr(result, "comparison_courses") <- scope$comparison_courses
  attr(result, "n_comparison_student_terms") <- prepared$n_comparison_student_terms
  cedar_debug("[course-similar-students.R] ", nrow(result), " rows (", nrow(suppressed), " under min_n = ", min_n, ")")
  result
}
