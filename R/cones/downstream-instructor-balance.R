# downstream-instructor-balance.R: were two X instructors' later-Y students alike?
#
# Course Dynamics > Later Course can break the students of course X down by
# their instructor in X (get_downstream_outcomes(by_instructor = TRUE)).
# Before reading a gap between two instructor rows as anything about the
# instructors, a reader needs to know whether those rows started out as
# similar students. This cone answers that one question: covariate balance
# between the students of the two largest instructor groups who went on to Y.
#
# Descriptive, not causal. Students choose sections by schedule, reputation
# and what they have already taken, and that shows up downstream as an
# instructor effect. Balance is pairwise, two named instructor groups, because
# pooling "everyone else" conflates instructors with different student mixes.
#
# The students compared are build_downstream_cohort()'s continuers
# (branches/downstream-cohort.R), the same students the instructor breakdown
# counts, so the two cannot disagree about who went on. An instructor group is
# one instructor on one campus, matching the breakdown's rows. Covariates are
# taken entering the X term: before the instructor, not after.
#
# Until 2026-11 this file was cones/course-instructor-effect.R and also built
# the outcome table by instructor; that table is get_downstream_outcomes()'s
# now, on the shared cohort (ISSUES I56).
#
# Depends on: build_downstream_cohort() (branches/downstream-cohort.R)
#             build_comparison() (branches/comparison.R)

#' Balance between the students of two X instructors who went on to Y
#'
#' @param students cedar_registrations.
#' @param attempts cedar_attempts.
#' @param programs cedar_programs.
#' @param applicants cedar_applicants, or NULL.
#' @param opt Named list:
#'   \describe{
#'     \item{course_x}{Character. The earlier course. Required.}
#'     \item{course_y}{Character vector. The later course or set. Required.}
#'     \item{data_edges}{Output of [cedar_data_edges()]. Required.}
#'     \item{campus}{Campuses that delivered X.}
#'     \item{window_terms}{Regular terms after X in which Y counts. Default 3.}
#'     \item{min_n}{Smallest instructor group compared. Default 15.}
#'     \item{reference_instructor}{Optional instructor name to compare first.}
#'   }
#' @param student_terms cedar_student_terms, for the rebuilt credit and GPA
#'   covariates.
#' @return Named list: `balance` (from build_comparison(), or NULL),
#'   `n_comparable` and `n_groups` (instructor groups with `min_n` continuers,
#'   and with any), `instructor_counts` (campus, instructor_name, n
#'   continuers), `reference_instructor`, `reference_campus`,
#'   `comparison_instructor`, `comparison_campus`, `n_treatment`, `n_control`,
#'   `min_n`, `course_x`, `course_y`, `course_y_label`, `window_terms`.
#'   `balance` is NULL when fewer than two groups reach `min_n`.
get_downstream_instructor_balance <- function(students, attempts, programs, applicants = NULL,
                                              opt = list(), student_terms = NULL) {
  course_x <- opt[["course_x"]]
  course_y <- opt[["course_y"]]
  if (is.null(course_x) || length(course_y) == 0) {
    stop("[downstream-instructor-balance.R] opt$course_x and opt$course_y are both required.")
  }
  min_n <- as.integer(opt[["min_n"]] %||% 15L)

  built <- build_downstream_cohort(students, attempts, course_x, course_y, opt)
  continuers <- built$cohort %>%
    dplyr::filter(eligible, took_y, !is.na(instructor_name))

  instructor_counts <- continuers %>%
    dplyr::count(campus, instructor_name, name = "n") %>%
    dplyr::arrange(dplyr::desc(n), campus, instructor_name)
  comparable <- dplyr::filter(instructor_counts, n >= min_n)

  result <- list(
    course_x              = course_x,
    course_y              = course_y,
    course_y_label        = downstream_course_y_label(course_y),
    window_terms          = built$window_terms,
    min_n                 = min_n,
    instructor_counts     = instructor_counts,
    n_comparable          = nrow(comparable),
    n_groups              = nrow(instructor_counts),
    balance               = NULL,
    reference_instructor  = NULL,
    reference_campus      = NULL,
    comparison_instructor = NULL,
    comparison_campus     = NULL,
    n_treatment           = 0L,
    n_control             = 0L
  )
  # Fewer than two groups to compare is an answer, not a failure: the
  # breakdown above it still stands.
  if (nrow(comparable) < 2L) return(result)

  # Reference: the named instructor if given, else the largest group. Pairwise
  # against the next largest group, never against everyone else pooled.
  reference <- opt[["reference_instructor"]]
  ref_row <- if (is.null(reference)) {
    dplyr::slice_head(comparable, n = 1L)
  } else {
    dplyr::slice_head(dplyr::filter(comparable, instructor_name == reference), n = 1L)
  }
  if (nrow(ref_row) == 0) {
    stop("[downstream-instructor-balance.R] reference_instructor '", reference,
         "' has fewer than ", min_n, " students who went on to ", result$course_y_label, ".")
  }
  cmp_row <- comparable %>%
    dplyr::filter(!(campus == ref_row$campus & instructor_name == ref_row$instructor_name)) %>%
    dplyr::slice_head(n = 1L)

  ref_students <- dplyr::filter(continuers, campus == ref_row$campus,
                                instructor_name == ref_row$instructor_name)
  cmp_students <- dplyr::filter(continuers, campus == cmp_row$campus,
                                instructor_name == cmp_row$instructor_name)

  comparison <- build_comparison(
    treatment_ids   = ref_students$student_id,
    pool_ids        = cmp_students$student_id,
    programs        = programs,
    applicants      = applicants,
    covariate_terms = dplyr::bind_rows(ref_students, cmp_students) %>%
      dplyr::transmute(student_id, covariate_term = term_x),
    student_terms   = student_terms
  )

  result$balance               <- comparison$balance
  result$reference_instructor  <- ref_row$instructor_name
  result$reference_campus      <- ref_row$campus
  result$comparison_instructor <- cmp_row$instructor_name
  result$comparison_campus     <- cmp_row$campus
  result$n_treatment           <- comparison$n_treatment
  result$n_control             <- comparison$n_control
  result
}

# Null-coalescing operator - define only if not already loaded.
if (!exists("%||%")) {
  `%||%` <- function(a, b) if (!is.null(a)) a else b
}
