#' Stop-Out Analysis: Where Students Leave the Pipeline
#'
#' @description
#' Identifies courses where students in a defined cohort stop enrolling after
#' a poor outcome (DFW grade), and compares that stop-out rate to the baseline
#' behavior of all other students in the same courses.
#'
#' A "stop-out" is when a student does not appear in any course enrollment the
#' following term. The core question is: after failing or withdrawing from a
#' course, do cohort students leave at a higher rate than students in general?
#' If yes, that course is an offramp — a point where the pipeline loses people
#' disproportionately.
#'
#' @section How the comparison works:
#' For each course, two groups of students are analyzed:
#' - **Cohort students** who took the course (from `build_population()`)
#' - **Baseline students** — everyone else who took the course
#'
#' Within each group, stop-out rates are compared between students who got a
#' DFW grade and those who passed. A course is a significant offramp when the
#' DFW stop-out rate is markedly higher than the pass stop-out rate, AND the
#' gap is larger for the cohort than for the baseline.
#'
#' Statistical significance is assessed with a chi-squared test comparing
#' DFW stop-out vs. pass stop-out within each group. Results include the
#' p-value and effect size (stop-out rate difference) so you can prioritize
#' courses where the pattern is both significant and large.
#'
#' @section RStudio Exploration:
#'
#' ```r
#' library(qs2); library(dplyr)
#'
#' cedar_programs <- qs_read("data/cedar_programs.qs")
#' cedar_students <- qs_read("data/cedar_students.qs")
#'
#' # Build cohort, then find where they stop out
#' cohort <- build_population(cedar_programs, opt = list(type = "health"))
#' result <- get_stopout(cedar_students, cohort, opt = list())
#'
#' # View top offramps — courses with highest DFW stop-out gap
#' result$by_course
#'
#' # Filter to statistically significant courses (p < 0.05 in cohort)
#' result$by_course %>% filter(cohort_p_value < 0.05)
#'
#' # Restrict to a specific term
#' result <- get_stopout(cedar_students, cohort, opt = list(term = 202510))
#'
#' # Set minimum student threshold (default 15)
#' result <- get_stopout(cedar_students, cohort, opt = list(min_n = 10))
#' ```
#'
#' @name stopout


#' Get Stop-Out Analysis for a Cohort
#'
#' For each course taken by cohort students, computes how often a DFW grade
#' leads to not enrolling the following term — and compares that rate to
#' baseline students in the same course.
#'
#' @param students Data frame. The `cedar_students` table. Should cover
#'   multiple terms so next-term enrollment can be checked.
#' @param cohort Data frame. Output of `build_population()`. Must have columns
#'   `student_id` and `population_label`.
#' @param opt List of options:
#'   \describe{
#'     \item{`term`}{Integer or character vector. Restrict which course-terms
#'       to analyze. Optional; defaults to all terms.}
#'     \item{`campus`}{Character vector. Restrict to these campus codes. Optional.}
#'     \item{`min_n`}{Integer. Minimum number of cohort students with a graded
#'       record in a course for it to appear in results. Default: `15`.}
#'   }
#'
#' @return Named list:
#'   \describe{
#'     \item{`by_course`}{Data frame, one row per course, sorted by
#'       `cohort_dfw_stopout_rate` descending. Columns:
#'       \itemize{
#'         \item `subject_course` — course identifier
#'         \item `cohort_n_dfw`, `cohort_n_pass` — cohort student counts by outcome
#'         \item `cohort_dfw_stopout_rate` — proportion of DFW cohort students
#'           who did not return the next term
#'         \item `cohort_pass_stopout_rate` — same for passing cohort students
#'         \item `cohort_stopout_gap` — difference (DFW rate minus pass rate);
#'           higher = greater penalty for failing
#'         \item `cohort_p_value` — chi-squared p-value comparing DFW vs pass
#'           stop-out within the cohort
#'         \item `baseline_n_dfw`, `baseline_n_pass` — same counts for non-cohort
#'           students
#'         \item `baseline_dfw_stopout_rate`, `baseline_pass_stopout_rate`,
#'           `baseline_stopout_gap`, `baseline_p_value` — same metrics for baseline
#'       }}
#'     \item{`population_size`}{Integer. Number of unique student IDs in the cohort.}
#'   }
#'
#' @examples
#' \dontrun{
#' cedar_programs <- qs_read("data/cedar_programs.qs")
#' cedar_students <- qs_read("data/cedar_students.qs")
#'
#' cohort <- build_population(cedar_programs, opt = list(type = "health"))
#' result <- get_stopout(cedar_students, cohort, opt = list())
#' result$by_course
#'
#' # Top courses where cohort students stop out after DFW significantly more
#' # than baseline students do
#' result$by_course %>%
#'   filter(cohort_p_value < 0.05) %>%
#'   arrange(desc(cohort_stopout_gap - baseline_stopout_gap))
#' }
#'
#' @seealso [build_population()], [compute_stopout_by_course()]
#' @export
get_stopout <- function(students, population, degrees = NULL, opt = list(),
                        cedar_grades = NULL, cedar_next_term = NULL) {

  message("[stopout.R] Starting stop-out analysis...")

  validate_population(population, "get_stopout")

  min_n       <- opt$min_n     %||% 15L  # chi-square needs ~15 per group to be reliable
  min_dfw_n   <- opt$min_dfw_n %||% 5L   # suppress rates where fewer than 5 students had DFW
  population_ids  <- unique(population$student_id)

  # Classify grades into pass / DFW.
  # If cedar_grades is provided (pre-computed at transform time, already windowed
  # for relevant_until by the caller), apply only the opt filters and use directly.
  # Otherwise fall back to classifying from the raw students table — correct but
  # expensive on large datasets.
  if (!is.null(cedar_grades) && nrow(cedar_grades) > 0) {
    message("[stopout.R] Using pre-computed cedar_grades...")
    graded <- cedar_grades
    if (!is.null(opt$term)   && length(opt$term)   > 0) graded <- filter(graded, term   %in% opt$term)
    if (!is.null(opt$campus) && length(opt$campus) > 0) graded <- filter(graded, campus %in% opt$campus)
    if (!is.null(opt$level)  && length(opt$level)  > 0) graded <- filter(graded, level  %in% opt$level)
  } else {
    message("[stopout.R] Classifying grades from raw students (cedar_grades not available)...")
    filtered_students <- students
    if (!is.null(opt$term)   && length(opt$term)   > 0) filtered_students <- filter(filtered_students, term   %in% opt$term)
    if (!is.null(opt$campus) && length(opt$campus) > 0) filtered_students <- filter(filtered_students, campus %in% opt$campus)
    if (!is.null(opt$level)  && length(opt$level)  > 0) filtered_students <- filter(filtered_students, level  %in% opt$level)
    graded <- classify_outcomes(filtered_students)
  }

  if (nrow(graded) == 0) {
    message("[stopout.R] No graded records found after filtering.")
    return(list(by_course = data.frame(), population_size = length(population_ids)))
  }

  # Label cohort vs baseline
  graded <- graded %>%
    mutate(in_pop = student_id %in% population_ids)

  # Determine which courses have enough cohort students to be worth analyzing
  pop_course_counts <- graded %>%
    filter(in_pop) %>%
    group_by(subject_course) %>%
    summarize(pop_graded = n_distinct(student_id), .groups = "drop") %>%
    filter(pop_graded >= min_n)

  if (nrow(pop_course_counts) == 0) {
    message("[stopout.R] No courses met the minimum cohort size threshold (", min_n, ").")
    return(list(by_course = data.frame(), population_size = length(population_ids)))
  }

  courses_to_analyze <- pop_course_counts$subject_course
  message("[stopout.R] Analyzing ", length(courses_to_analyze), " courses...")

  # Build next-term lookup only for students who appear in the analyzed courses
  # (cohort + baseline). Scoping to courses_to_analyze rather than all of graded
  # avoids building the lookup for students in unrelated courses that won't be used.
  # We still draw from the full enrollment history so a student who stopped enrolling
  # can be detected even if their next term falls outside opt$term.
  students_in_graded <- graded %>%
    filter(subject_course %in% courses_to_analyze) %>%
    pull(student_id) %>%
    unique()
  message("[stopout.R] Building next-term lookup for ",
          format(length(students_in_graded), big.mark = ","), " students (in analyzed courses)...")
  if (!is.null(cedar_next_term) && nrow(cedar_next_term) > 0) {
    # Pre-computed at transform time — just filter to relevant students.
    next_term_lookup <- cedar_next_term %>%
      filter(student_id %in% students_in_graded)
    message("[stopout.R] Used pre-computed cedar_next_term.")
  } else {
    next_term_lookup <- build_next_term_lookup(
      students %>% filter(student_id %in% students_in_graded)
    )
  }

  # Pre-join stop-out status onto graded ONCE — eliminates a full join per course
  message("[stopout.R] Joining stop-out status...")
  graded_so <- graded %>%
    filter(subject_course %in% courses_to_analyze) %>%
    left_join(next_term_lookup, by = c("student_id", "term")) %>%
    mutate(stopped_out = !returned_next_term | is.na(returned_next_term))

  # Graduate correction: students who earned a degree in term T did not "stop out" —
  # they completed. Mark them as stopped_out = FALSE for their graduation term.
  if (!is.null(degrees) && nrow(degrees) > 0) {
    grad_terms <- degrees %>%
      dplyr::select(student_id, term) %>%
      dplyr::distinct() %>%
      dplyr::mutate(graduated = TRUE)
    n_before <- sum(graded_so$stopped_out, na.rm = TRUE)
    graded_so <- graded_so %>%
      dplyr::left_join(grad_terms, by = c("student_id", "term")) %>%
      dplyr::mutate(stopped_out = dplyr::if_else(!is.na(graduated), FALSE, stopped_out)) %>%
      dplyr::select(-graduated)
    n_corrected <- n_before - sum(graded_so$stopped_out, na.rm = TRUE)
    message("[stopout.R] Graduate correction: ", n_corrected,
            " stop-out records cleared for students who graduated that term.")
  }

  # Pre-split by course — O(1) lookup in the loop instead of O(n) filter
  graded_split <- split(graded_so, graded_so$subject_course)

  message("[stopout.R] Computing stop-out rates per course...")
  results <- purrr::map_dfr(courses_to_analyze, function(course) {
    course_data <- graded_split[[course]]

    pop_row   <- compute_stopout_for_group(course_data %>% filter(in_pop),
                                              prefix = "pop")
    baseline_row <- compute_stopout_for_group(course_data %>% filter(!in_pop),
                                              prefix = "baseline")

    bind_cols(tibble(subject_course = course), pop_row, baseline_row)
  })

  results <- results %>%
    arrange(desc(pop_dfw_stopout_rate))

  # Drop courses where the cohort had too few DFW students to be meaningful
  n_before_dfw_filter <- nrow(results)
  results <- results %>%
    filter(is.na(pop_n_dfw) | pop_n_dfw >= min_dfw_n)
  message("[stopout.R] min_dfw_n filter (>=", min_dfw_n, "): kept ",
          nrow(results), " of ", n_before_dfw_filter, " courses.")

  term_range <- if (nrow(graded) > 0) range(graded$term) else c(NA_integer_, NA_integer_)

  message("[stopout.R] Done. Returning results for ",
          nrow(results), " courses.")

  list(
    by_course   = results,
    population_size = length(population_ids),
    term_range  = term_range
  )
}


#' Get DFW Rates by Course for a Population
#'
#' For each course taken by population students, computes the DFW rate among
#' population students and the baseline (all other students in the same
#' courses). Sorted by population DFW rate descending.
#'
#' Shares `classify_outcomes()` with `get_stopout()`. Does not require a
#' next-term lookup, so it is faster and has no edge-case around the most
#' recent term.
#'
#' @param students Data frame. The `cedar_students` table.
#' @param population Data frame. Output of `build_population()`. Must have
#'   `student_id`.
#' @param opt List of options:
#'   \describe{
#'     \item{`level`}{Character vector. Course levels to include. Optional.}
#'     \item{`campus`}{Character vector. Campus codes to include. Optional.}
#'     \item{`min_n`}{Integer. Min population students graded in a course.
#'       Default: `10`.}
#'     \item{`min_dfw_n`}{Integer. Min population DFW students. Default: `5`.}
#'   }
#'
#' @return Data frame with one row per course, columns:
#'   `subject_course`, `pop_n_graded`, `pop_n_dfw`, `pop_dfw_rate`,
#'   `baseline_n_graded`, `baseline_n_dfw`, `baseline_dfw_rate`.
#'
#' @keywords internal
get_dfw_rates <- function(students, population, opt = list(), cedar_grades = NULL) {
  min_n     <- opt$min_n     %||% 10L  # minimum course enrollment to report DFW rates
  min_dfw_n <- opt$min_dfw_n %||% 5L   # suppress rates where fewer than 5 students had DFW
  population_ids <- unique(population$student_id)

  if (!is.null(cedar_grades) && nrow(cedar_grades) > 0) {
    graded <- cedar_grades
    if (!is.null(opt$level)  && length(opt$level)  > 0) graded <- dplyr::filter(graded, level  %in% opt$level)
    if (!is.null(opt$campus) && length(opt$campus) > 0) graded <- dplyr::filter(graded, campus %in% opt$campus)
  } else {
    filtered <- students
    if (!is.null(opt$level)  && length(opt$level)  > 0) filtered <- filtered %>% dplyr::filter(level  %in% opt$level)
    if (!is.null(opt$campus) && length(opt$campus) > 0) filtered <- filtered %>% dplyr::filter(campus %in% opt$campus)
    graded <- classify_outcomes(filtered)
  }

  graded <- graded %>%
    dplyr::mutate(in_pop = student_id %in% population_ids)

  # Courses with enough population students to be meaningful
  pop_counts <- graded %>%
    dplyr::filter(in_pop) %>%
    dplyr::group_by(subject_course) %>%
    dplyr::summarize(n_graded = dplyr::n_distinct(student_id), .groups = "drop") %>%
    dplyr::filter(n_graded >= min_n)

  if (nrow(pop_counts) == 0) return(data.frame())
  courses <- pop_counts$subject_course

  summarize_dfw <- function(df, prefix) {
    df %>%
      dplyr::filter(subject_course %in% courses) %>%
      dplyr::group_by(subject_course) %>%
      dplyr::summarize(
        n_graded = dplyr::n_distinct(student_id),
        n_dfw    = dplyr::n_distinct(student_id[outcome == "dfw"]),
        .groups  = "drop"
      ) %>%
      dplyr::mutate(dfw_rate = round(n_dfw / n_graded, 3)) %>%
      dplyr::rename_with(~ paste0(prefix, "_", .), -subject_course)
  }

  pop_summary      <- summarize_dfw(dplyr::filter(graded, in_pop),  "pop")
  baseline_summary <- summarize_dfw(dplyr::filter(graded, !in_pop), "baseline")

  pop_summary %>%
    dplyr::left_join(baseline_summary, by = "subject_course") %>%
    dplyr::filter(is.na(pop_n_dfw) | pop_n_dfw >= min_dfw_n) %>%
    dplyr::arrange(dplyr::desc(pop_dfw_rate))
}


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

#' Classify Student Enrollment Records as Pass or DFW
#'
#' Takes graded enrollment records and labels each as `"pass"`, `"dfw"`, or
#' `"ungraded"`. Ungraded records (incomplete, audit, no record) are dropped
#' from the result — they provide no signal for stop-out analysis.
#'
#' Considers only registered students (registration_status_code RE, RS, RR).
#' Early drops (DR) are treated as DFW — a student who dropped before the
#' deadline is still a non-completion.
#'
#' @param students Data frame. The `cedar_students` table.
#'
#' @return Data frame with columns: `student_id`, `term`, `subject_course`,
#'   `outcome` (`"pass"` or `"dfw"`).
#'
#' @keywords internal
classify_outcomes <- function(students) {

  students %>%
    filter(
      registration_status_code %in% c(STATUS_REGISTERED, STATUS_DROP_EARLY)
    ) %>%
    select(student_id, term, subject_course, final_grade, registration_status_code) %>%
    distinct() %>%
    mutate(
      outcome = case_when(
        registration_status_code %in% STATUS_DROP_EARLY ~ "dfw",
        final_grade %in% GRADES_DFW                    ~ "dfw",
        final_grade %in% GRADES_PASS                   ~ "pass",
        TRUE                                            ~ NA_character_
      )
    ) %>%
    filter(!is.na(outcome)) %>%
    select(student_id, term, subject_course, outcome)
}


#' Build a Next-Term Enrollment Lookup
#'
#' For each student-term pair present in the data, determines the next
#' regular academic term and whether the student enrolled in it. Uses
#' `add_next_term_col()` from `utils.R`.
#'
#' Summer terms are excluded from the "next term" mapping — a student who
#' doesn't enroll in summer is not considered a stop-out.
#'
#' @param students Data frame. The full `cedar_students` table (not pre-filtered
#'   by term — we need the full enrollment history to check the next term).
#'
#' @return Data frame with columns: `student_id`, `term`, `returned_next_term`
#'   (logical: `TRUE` if the student had any enrollment the following term).
#'
#' @keywords internal
build_next_term_lookup <- function(students) {

  # All terms in which each student appears (any registration status)
  student_terms <- students %>%
    select(student_id, term) %>%
    distinct()

  # Map each term to the next regular term (no summer)
  with_next <- student_terms %>%
    add_next_term_col("term", summer = FALSE)

  # Which student-next_term pairs actually have enrollment?
  enrolled_terms <- student_terms %>%
    rename(next_term = term) %>%
    mutate(returned = TRUE)

  with_next %>%
    left_join(enrolled_terms, by = c("student_id", "next_term")) %>%
    mutate(returned_next_term = !is.na(returned)) %>%
    select(student_id, term, returned_next_term)
}


#' Compute Stop-Out Rates for One Group in One Course
#'
#' Given the graded records for a single group (cohort or baseline) in a
#' single course, computes stop-out rates for DFW and passing students,
#' and runs a chi-squared test to assess whether the difference is significant.
#'
#' @param course_group Data frame. Rows from `classify_outcomes()` for one
#'   group (cohort or baseline) in one course. Must have columns:
#'   `student_id`, `term`, `outcome`, and `stopped_out` (pre-joined by caller).
#' @param prefix Character. Column name prefix for the returned values
#'   (`"cohort"` or `"baseline"`).
#'
#' @return Single-row tibble with columns:
#'   `{prefix}_n_dfw`, `{prefix}_n_pass`,
#'   `{prefix}_dfw_stopout_rate`, `{prefix}_pass_stopout_rate`,
#'   `{prefix}_stopout_gap`, `{prefix}_p_value`
#'
#' @keywords internal
compute_stopout_for_group <- function(course_group, prefix) {

  empty_row <- tibble(
    n_dfw             = NA_integer_,
    n_pass            = NA_integer_,
    dfw_stopout_rate  = NA_real_,
    pass_stopout_rate = NA_real_,
    stopout_gap       = NA_real_,
    p_value           = NA_real_
  )
  names(empty_row) <- paste0(prefix, "_", names(empty_row))

  if (nrow(course_group) == 0) return(empty_row)

  # stopped_out is pre-joined by get_stopout() before the per-course loop
  analysis <- course_group

  dfw_data  <- analysis %>% filter(outcome == "dfw")
  pass_data <- analysis %>% filter(outcome == "pass")

  n_dfw  <- n_distinct(dfw_data$student_id)
  n_pass <- n_distinct(pass_data$student_id)

  dfw_stopout  <- if (n_dfw > 0)  mean(dfw_data$stopped_out,  na.rm = TRUE) else NA_real_
  pass_stopout <- if (n_pass > 0) mean(pass_data$stopped_out, na.rm = TRUE) else NA_real_

  stopout_gap <- if (!is.na(dfw_stopout) && !is.na(pass_stopout)) {
    round(dfw_stopout - pass_stopout, 3)
  } else NA_real_

  # Chi-squared test: can we detect a difference in stop-out rates?
  p_value <- NA_real_
  if (n_dfw >= 5 && n_pass >= 5) {
    contingency <- table(analysis$outcome, analysis$stopped_out)
    if (all(dim(contingency) == c(2, 2))) {
      p_value <- tryCatch(
        suppressWarnings(chisq.test(contingency)$p.value),
        error = function(e) NA_real_
      )
    }
  }

  result <- tibble(
    n_dfw             = n_dfw,
    n_pass            = n_pass,
    dfw_stopout_rate  = round(dfw_stopout,  3),
    pass_stopout_rate = round(pass_stopout, 3),
    stopout_gap       = stopout_gap,
    p_value           = round(p_value, 4)
  )
  names(result) <- paste0(prefix, "_", names(result))
  result
}


# Null-coalescing operator — define only if not already loaded
if (!exists("%||%")) {
  `%||%` <- function(a, b) if (!is.null(a)) a else b
}
