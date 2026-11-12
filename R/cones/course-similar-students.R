# course-similar-students.R — A course's takers against similar non-takers
#
# One question: did the students who took course X do better that term and
# the next than students like them who did not take it? "Like them" is a
# cell: the same anchor term, home campus, high-school GPA band and time
# status (full or part time). Inside each cell the non-takers supply a rate;
# weighting those rates by the takers' own mix across cells gives the rate
# the takers would have had if they had done as their non-taking peers did
# (direct standardization). The gap is actual minus expected.
#
# Takers vs Non-Takers (course-cohort-effect.R) puts the raw groups side by
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
# A taker is a member with a classified attempt (pass or DFW) of the course
# in the anchor term, on any campus. A member whose only rows are an early
# drop or an ungraded registration is neither a taker nor a non-taker of
# that course. A cell with fewer than `min_cell_n` non-takers supplies no
# rate: its takers are left out of both sides and counted (`n_takers` less
# `n_covered`).
#
# Descriptive, never an effect: the cells remove term, campus, high-school
# GPA and time status and nothing else. Placement, advising, major and
# motivation are not in them, and a course students are placed into shows
# its placement here. At the instructor grain a section tied to a program or
# a learning community shows that program, not the teaching. The return
# gap's standard error is the binomial error at the expected rates; it
# ignores the error in the non-takers' rates and so is a floor.
#
# Depends on: cedar_longitudinal_edge() (branches/data-edges.R)
#             hs_gpa_band(), applicant_hs_gpa() (branches/comparison.R)

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
#'   `min_n` (smallest covered taker count a row needs; default 30),
#'   `min_cell_n` (smallest non-taker count a cell needs; default 5),
#'   `data_edges` (`cedar_data_edges()` output, required).
#' @return A tibble, one row per `course` (and `instructor_id`,
#'   `instructor_name` at the instructor grain): `n_takers`, `n_covered`,
#'   `n_terms`; `return_n`, `return_pct`, `return_expected_pct`,
#'   `return_gap`, `return_gap_se`; `other_attempts`, `other_dfw_pct`,
#'   `other_dfw_expected_pct`, `other_dfw_gap`; `next_gpa_n`, `next_gpa`,
#'   `next_gpa_expected`, `next_gpa_gap`. Gaps are actual minus expected (a
#'   positive DFW gap is worse); an outcome with nothing observable is NA.
#'   Attributes: `edge`, `graded_edge`, `n_population_student_terms`,
#'   `cells` (the cell columns), `suppressed` (rows under `min_n`).
get_course_similar_students <- function(student_terms, attempts, applicants, opt = list()) {
  classification <- opt$classification
  if (is.null(classification) || length(classification) == 0L) {
    stop("[course-similar-students.R] opt$classification is required.", call. = FALSE)
  }
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
  grain <- opt$grain %||% "course"
  if (!grain %in% c("course", "instructor")) {
    stop("[course-similar-students.R] opt$grain must be \"course\" or \"instructor\", not ", grain, call. = FALSE)
  }
  min_n <- as.integer(opt$min_n %||% 30L)
  min_cell_n <- as.integer(opt$min_cell_n %||% 5L)
  edge <- cedar_longitudinal_edge(opt$data_edges)
  if (is.null(edge)) {
    stop("[course-similar-students.R] opt$data_edges has no settled enrollment edge (last_enrolled_complete).",
         call. = FALSE)
  }
  graded_edge <- opt$data_edges[["last_graded"]]
  if (is.null(graded_edge)) {
    stop("[course-similar-students.R] opt$data_edges has no graded edge (last_graded).", call. = FALSE)
  }
  graded_edge <- as.integer(graded_edge)
  cell_cols <- c("term", "student_campus", "hs_gpa_band", "time_status")

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
           returned_next_regular_term, return_observable) %>%
    left_join(applicant_hs_gpa(applicants), by = "student_id") %>%
    left_join(next_gpas, by = c("student_id", "next_regular_term")) %>%
    mutate(
      hs_gpa_band = hs_gpa_band(high_school_cum_gpa),
      time_status = coalesce(as.character(time_status), "not recorded"),
      ret_obs = as.integer(return_observable %in% TRUE),
      ret     = as.integer(return_observable %in% TRUE & returned_next_regular_term %in% TRUE),
      gpa_n   = as.integer(!is.na(next_gpa)),
      gpa_sum = coalesce(next_gpa, 0)
    )
  cedar_debug("[course-similar-students.R] ", nrow(members), " member student-terms to ", edge)

  # CAMPUS_ROLLUP: a student took the course wherever it was taught; the grain
  # kept is the student's home campus (student_campus), which is in the cell.
  touched <- attempts %>%
    semi_join(members, by = c("student_id", "term")) %>%
    arrange(student_id, term, subject_course, is.na(outcome)) %>%
    group_by(student_id, term, course = subject_course) %>%
    summarize(att = sum(!is.na(outcome)), dfw = sum(outcome %in% "dfw"),
              instructor_id = first(instructor_id), instructor_name = first(instructor_name),
              .groups = "drop")
  totals <- touched %>%
    filter(term <= graded_edge) %>%
    group_by(student_id, term) %>%
    summarize(tot_att = sum(att), tot_dfw = sum(dfw), .groups = "drop")
  members <- members %>%
    left_join(totals, by = c("student_id", "term")) %>%
    mutate(tot_att = if_else(term <= graded_edge, coalesce(tot_att, 0L), 0L),
           tot_dfw = if_else(term <= graded_edge, coalesce(tot_dfw, 0L), 0L))

  measures <- c("n", "ret_obs", "ret", "gpa_n", "gpa_sum", "tot_att", "tot_dfw")
  cells <- members %>%
    group_by(across(all_of(cell_cols))) %>%
    summarize(n = n(), across(all_of(measures[-1]), sum), .groups = "drop") %>%
    rename_with(~ paste0(.x, ".cell"), all_of(measures))

  if (!is.null(opt$course)) touched <- touched %>% filter(course %in% as.character(opt$course))
  touched <- touched %>%
    inner_join(members %>% select(student_id, term, all_of(cell_cols[-1]), all_of(measures[-1])),
               by = c("student_id", "term")) %>%
    mutate(n = 1L, taker = att > 0L,
           # A taker's other courses: the term's attempts less this course's.
           other_att = if_else(term <= graded_edge, tot_att - att, 0L),
           other_dfw = if_else(term <= graded_edge, tot_dfw - dfw, 0L))

  # The non-takers of each course in each cell: the cell less everyone with a
  # row in the course, and the rate they supply.
  non_takers <- touched %>%
    group_by(course, across(all_of(cell_cols))) %>%
    summarize(across(all_of(measures), sum), .groups = "drop") %>%
    inner_join(cells, by = cell_cols) %>%
    transmute(
      course, across(all_of(cell_cols)),
      nt_n = n.cell - n,
      nt_return = if_else(ret_obs.cell - ret_obs > 0L, (ret.cell - ret) / (ret_obs.cell - ret_obs), NA_real_),
      nt_dfw    = if_else(tot_att.cell - tot_att > 0L, (tot_dfw.cell - tot_dfw) / (tot_att.cell - tot_att), NA_real_),
      nt_gpa    = if_else(gpa_n.cell - gpa_n > 0L, (gpa_sum.cell - gpa_sum) / (gpa_n.cell - gpa_n), NA_real_)
    )

  row_cols <- c("course", if (grain == "instructor") c("instructor_id", "instructor_name"),
                if (isTRUE(opt$by_term)) "term")
  taker_cells <- touched %>%
    filter(taker) %>%
    group_by(across(all_of(union(row_cols, cell_cols)))) %>%
    summarize(n = n(), ret_obs = sum(ret_obs), ret = sum(ret), gpa_n = sum(gpa_n), gpa_sum = sum(gpa_sum),
              other_att = sum(other_att), other_dfw = sum(other_dfw), .groups = "drop") %>%
    inner_join(non_takers, by = c("course", cell_cols)) %>%
    mutate(covered = nt_n >= min_cell_n)

  # Each outcome is read over the covered cells where the non-takers have a
  # rate for it; the same cells on both sides of every gap.
  ratio <- function(num, den) if_else(den > 0, num / den, NA_real_)
  rows <- taker_cells %>%
    mutate(r_ok = covered & !is.na(nt_return), d_ok = covered & !is.na(nt_dfw), g_ok = covered & !is.na(nt_gpa)) %>%
    group_by(across(all_of(row_cols))) %>%
    summarize(
      n_takers = sum(n), n_covered = sum(n[covered]), n_terms = n_distinct(term[covered]),
      return_n = sum(ret_obs[r_ok]),
      .ret = sum(ret[r_ok]), .ret_exp = sum(ret_obs[r_ok] * nt_return[r_ok]),
      .ret_var = sum(ret_obs[r_ok] * nt_return[r_ok] * (1 - nt_return[r_ok])),
      other_attempts = sum(other_att[d_ok]),
      .dfw = sum(other_dfw[d_ok]), .dfw_exp = sum(other_att[d_ok] * nt_dfw[d_ok]),
      next_gpa_n = sum(gpa_n[g_ok]),
      .gpa = sum(gpa_sum[g_ok]), .gpa_exp = sum(gpa_n[g_ok] * nt_gpa[g_ok]),
      .groups = "drop"
    ) %>%
    mutate(
      return_pct = 100 * ratio(.ret, return_n), return_expected_pct = 100 * ratio(.ret_exp, return_n),
      return_gap = return_pct - return_expected_pct, return_gap_se = 100 * ratio(sqrt(.ret_var), return_n),
      other_dfw_pct = 100 * ratio(.dfw, other_attempts),
      other_dfw_expected_pct = 100 * ratio(.dfw_exp, other_attempts),
      other_dfw_gap = other_dfw_pct - other_dfw_expected_pct,
      next_gpa = ratio(.gpa, next_gpa_n), next_gpa_expected = ratio(.gpa_exp, next_gpa_n),
      next_gpa_gap = next_gpa - next_gpa_expected
    ) %>%
    select(all_of(row_cols), n_takers, n_covered, n_terms,
           return_n, return_pct, return_expected_pct, return_gap, return_gap_se,
           other_attempts, other_dfw_pct, other_dfw_expected_pct, other_dfw_gap,
           next_gpa_n, next_gpa, next_gpa_expected, next_gpa_gap) %>%
    arrange(desc(return_gap), across(all_of(row_cols)))
  if (isTRUE(opt$by_term)) rows <- rows %>% arrange(across(all_of(row_cols)))

  suppressed <- rows %>% filter(n_covered < min_n) %>% select(all_of(row_cols), n_takers, n_covered)
  result <- rows %>% filter(n_covered >= min_n)
  attr(result, "edge") <- edge
  attr(result, "graded_edge") <- graded_edge
  attr(result, "n_population_student_terms") <- nrow(members)
  attr(result, "cells") <- cell_cols
  attr(result, "suppressed") <- suppressed
  cedar_debug("[course-similar-students.R] ", nrow(result), " rows (", nrow(suppressed), " under min_n = ", min_n, ")")
  result
}
