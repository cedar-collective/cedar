#' Roadblocks: First-Outcome Stop-Out Comparisons
#'
#' For each course and delivery campus, compare next-regular-term stop-out
#' after DFW versus pass, separately for a selected population and other students.
#' Each student contributes their first eligible observed outcome to exactly one
#' group. Scope, population-window filtering, and both right edges precede this
#' selection. This is not necessarily the student's first lifetime attempt.
#'
#' Agreeing first-term outcomes collapse to one observation; conflicting
#' first-term outcomes exclude that student/course/campus comparison. Later
#' repeats remain evidence of return but do not change the selected outcome.
#' Counts, rates, DFW context, and tests all use these same observations.
#'
#' Return means registered or late-drop enrollment anywhere at UNM in the next
#' fall or spring. A degree in the outcome term also prevents a stop-out flag.
#' Nonreturn is an observed absence, not proof of permanent departure.
#'
#' The chi-squared test (Yates correction) compares DFW versus pass WITHIN each
#' population; it does not test whether the population and baseline gaps differ.
#' Tests require at least five students in each outcome group and both return
#' states. Small expected cells can still make the approximation unreliable.
#' P-values are unadjusted across courses; neither a gap nor the ranking score
#' establishes that a course caused a student to leave.
#'
#' @param students Full `cedar_students` enrollment history. If course outcomes
#'   are term-windowed, supply the full-history `cedar_next_term` separately:
#'   otherwise filtering away return terms silently creates false stop-outs.
#' @param population Output of [build_population()], with `student_id` and
#'   `population_label`. Callers apply population membership windows to outcome
#'   rows before this function; the return lookup must remain unwindowed.
#' @param degrees Optional degree records; a degree in the outcome term counts
#'   as completion rather than stop-out.
#' @param opt List of options:
#'   `term`, `campus`, `level`, and `subject_code` restrict course outcomes;
#'   `min_n` (default 15) is the minimum selected population students per
#'   course/campus; `min_dfw_n` (default 5) is the minimum selected DFW students;
#'   `graded_through` caps outcomes; `observation_end_term` requires the next
#'   regular term to be observable. Reporting thresholds do not guarantee
#'   statistical validity. Standalone callers must supply appropriate edges.
#' @param cedar_grades Optional preclassified outcomes with the current saved
#'   outcome-policy version, already respecting the caller's population window.
#' @param cedar_next_term Optional full-history next-term return lookup.
#' @return List containing `by_course` (one row per campus/course),
#'   `population_size`, eligible anchor `term_range`, and `observation_info`
#'   (coverage counts before size thresholds). Course rows contain `pop_` and
#'   `baseline_` columns: `n_dfw`, `n_pass`, `n_graded`, `dfw_rate`,
#'   `dfw_stopout_rate`, `pass_stopout_rate`, `stopout_gap`, and `p_value`.
#'   Statistics retain full precision; round only for display.
#' @seealso [build_population()], [prepare_roadblock_results()]
#' @export
get_stopout <- function(students, population, degrees = NULL, opt = list(),
                        cedar_grades = NULL, cedar_next_term = NULL) {

  message("[stopout.R] Starting stop-out analysis...")

  validate_population(population, "get_stopout")

  min_n       <- opt$min_n     %||% 15L  # reporting threshold, not a test-validity guarantee
  min_dfw_n   <- opt$min_dfw_n %||% 5L   # suppress rates where fewer than 5 students had DFW
  population_ids  <- unique(population$student_id)

  # Classify grades into pass / DFW.
  # If cedar_grades is provided (pre-computed at transform time, already windowed
  # for relevant_until by the caller), validate its policy before applying filters.
  # Otherwise fall back to classifying from the raw students table — correct but
  # expensive on large datasets.
  if (!is.null(cedar_grades) && nrow(cedar_grades) > 0) {
    validate_cedar_grades_policy(cedar_grades)
    message("[stopout.R] Using pre-computed cedar_grades...")
    graded <- cedar_grades
    if (!is.null(opt$term)   && length(opt$term)   > 0) graded <- filter(graded, term   %in% opt$term)
    if (!is.null(opt$campus) && length(opt$campus) > 0) graded <- filter(graded, campus %in% opt$campus)
    if (!is.null(opt$level)  && length(opt$level)  > 0) graded <- filter(graded, level  %in% opt$level)
    graded <- .filter_stopout_subject(graded, opt$subject_code)
  } else {
    message("[stopout.R] Classifying grades from raw students (cedar_grades not available)...")
    filtered_students <- students
    if (!is.null(opt$term)   && length(opt$term)   > 0) filtered_students <- filter(filtered_students, term   %in% opt$term)
    if (!is.null(opt$campus) && length(opt$campus) > 0) filtered_students <- filter(filtered_students, campus %in% opt$campus)
    if (!is.null(opt$level)  && length(opt$level)  > 0) filtered_students <- filter(filtered_students, level  %in% opt$level)
    filtered_students <- .filter_stopout_subject(filtered_students, opt$subject_code)
    graded <- classify_outcomes(filtered_students)
  }

  if (nrow(graded) == 0) {
    message("[stopout.R] No graded records found after filtering.")
    return(list(by_course = data.frame(), population_size = length(population_ids)))
  }
  cedar_require_campus(graded, "get_stopout")

  graded_through <- opt$graded_through
  if (!is.null(graded_through)) {
    graded <- dplyr::filter(graded, term <= .env$graded_through)
  }

  observation_end <- opt$observation_end_term
  if (!is.null(observation_end) && nrow(graded) > 0L) {
    graded <- graded %>%
      add_next_term_col("term", summer = FALSE) %>%
      filter(!is.na(next_term), next_term <= .env$observation_end) %>%
      select(-next_term)
  }

  if (nrow(graded) == 0) {
    message("[stopout.R] No outcomes have a complete next-term observation window.")
    return(list(by_course = data.frame(), population_size = length(population_ids),
                term_range = c(NA_integer_, NA_integer_)))
  }

  # Select only AFTER scope and observation eligibility. Preserve the eligible
  # anchor range for the scope note; first observations need not reach its tail.
  observations <- select_stopout_observations(graded)
  term_range <- observations$term_range
  observation_info <- observations$info
  graded <- observations$data %>%
    mutate(in_pop = student_id %in% population_ids)

  # Determine which courses have enough cohort students to be worth analyzing
  pop_course_counts <- graded %>%
    filter(in_pop) %>%
    group_by(campus, subject_course) %>%
    summarize(pop_graded = n_distinct(student_id), .groups = "drop") %>%
    filter(pop_graded >= min_n)

  if (nrow(pop_course_counts) == 0) {
    message("[stopout.R] No courses met the minimum cohort size threshold (", min_n, ").")
    return(list(by_course = data.frame(), population_size = length(population_ids),
                term_range = term_range, observation_info = observation_info))
  }

  course_keys <- pop_course_counts %>% select(campus, subject_course)
  message("[stopout.R] Analyzing ", nrow(course_keys),
          " campus-course groups...")

  # Build next-term lookup only for students who appear in the analyzed courses
  # (cohort + baseline). Scoping to courses_to_analyze rather than all of graded
  # avoids building the lookup for students in unrelated courses that won't be used.
  # We still draw from the full enrollment history so a student who stopped enrolling
  # can be detected even if their next term falls outside opt$term.
  students_in_graded <- graded %>%
    semi_join(course_keys, by = c("campus", "subject_course")) %>%
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
    semi_join(course_keys, by = c("campus", "subject_course")) %>%
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

  message("[stopout.R] Computing stop-out rates per campus and course...")
  results <- purrr::map2_dfr(
    course_keys$campus,
    course_keys$subject_course,
    function(course_campus, course) {
      course_data <- graded_so %>%
        filter(campus == .env$course_campus, subject_course == .env$course)

      pop_row <- compute_stopout_for_group(
        course_data %>% filter(in_pop), prefix = "pop"
      )
      baseline_row <- compute_stopout_for_group(
        course_data %>% filter(!in_pop), prefix = "baseline"
      )

      bind_cols(
        tibble(campus = course_campus, subject_course = course),
        pop_row,
        baseline_row
      )
    }
  )

  results <- results %>%
    arrange(desc(pop_dfw_stopout_rate))

  # Drop courses where the cohort had too few DFW students to be meaningful
  n_before_dfw_filter <- nrow(results)
  results <- results %>%
    filter(is.na(pop_n_dfw) | pop_n_dfw >= min_dfw_n)
  message("[stopout.R] min_dfw_n filter (>=", min_dfw_n, "): kept ",
          nrow(results), " of ", n_before_dfw_filter, " courses.")

  message("[stopout.R] Done. Returning results for ",
          nrow(results), " campus-course groups.")

  list(
    by_course   = results,
    population_size = length(population_ids),
    term_range  = term_range,
    observation_info = observation_info
  )
}


#' Prepare Roadblock Ranking Metrics
#'
#' Uses the first-observation context already in the input and computes the population's excess stop-out
#' gap over the same-course baseline. A missing baseline stays missing: treating
#' it as zero would turn "not estimable" into an apparently adverse comparison.
#'
#' @param stopout_by_course Course rows returned in `get_stopout()$by_course`.
#' @return Input rows with `excess_gap` and `impact_score`, ordered by descending
#'   estimable impact. Impact is a descriptive ranking score, not a causal estimate.
prepare_roadblock_results <- function(stopout_by_course) {
  result <- stopout_by_course
  if (is.null(result) || nrow(result) == 0L) return(result)

  result %>%
    dplyr::mutate(
      excess_gap = dplyr::if_else(
        !is.na(pop_stopout_gap) & !is.na(baseline_stopout_gap),
        pop_stopout_gap - baseline_stopout_gap,
        NA_real_
      ),
      impact_score = dplyr::if_else(
        !is.na(excess_gap),
        pmax(excess_gap, 0) * pop_n_dfw,
        NA_real_
      )
    ) %>%
    dplyr::arrange(dplyr::desc(impact_score))
}


#' Get DFW Rates by Course for a Population
#'
#' For each course taken by population students, computes the DFW rate among
#' population students and the baseline (all other students in the same
#' courses). A student with ANY eligible DFW counts in the numerator, even if
#' they also passed. This standalone ever-DFW measure is not the Roadblocks
#' first-outcome context. Sorted by population DFW rate descending.
#'
#' Shares `classify_outcomes()` with `get_stopout()`. Does not require a
#' next-term lookup. Callers must cap input at the grade edge; it does not
#' require the complete follow-up window used by Roadblocks.
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
#' @return Data frame with one row per campus and course, columns:
#'   `campus`, `subject_course`, `pop_n_graded`, `pop_n_dfw`, `pop_dfw_rate`,
#'   `baseline_n_graded`, `baseline_n_dfw`, `baseline_dfw_rate`.
#'
#' @keywords internal
get_dfw_rates <- function(students, population, opt = list(), cedar_grades = NULL) {
  min_n     <- opt$min_n     %||% 10L  # minimum course enrollment to report DFW rates
  min_dfw_n <- opt$min_dfw_n %||% 5L   # suppress rates where fewer than 5 students had DFW
  population_ids <- unique(population$student_id)

  if (!is.null(cedar_grades) && nrow(cedar_grades) > 0) {
    validate_cedar_grades_policy(cedar_grades)
    graded <- cedar_grades
    if (!is.null(opt$level)  && length(opt$level)  > 0) graded <- dplyr::filter(graded, level  %in% opt$level)
    if (!is.null(opt$campus) && length(opt$campus) > 0) graded <- dplyr::filter(graded, campus %in% opt$campus)
    graded <- .filter_stopout_subject(graded, opt$subject_code)
  } else {
    filtered <- students
    if (!is.null(opt$level)  && length(opt$level)  > 0) filtered <- filtered %>% dplyr::filter(level  %in% opt$level)
    if (!is.null(opt$campus) && length(opt$campus) > 0) filtered <- filtered %>% dplyr::filter(campus %in% opt$campus)
    filtered <- .filter_stopout_subject(filtered, opt$subject_code)
    graded <- classify_outcomes(filtered)
  }

  graded <- graded %>%
    dplyr::mutate(in_pop = student_id %in% population_ids)
  cedar_require_campus(graded, "get_dfw_rates")

  # Courses with enough population students to be meaningful
  pop_counts <- graded %>%
    dplyr::filter(in_pop) %>%
    dplyr::group_by(campus, subject_course) %>%
    dplyr::summarize(n_graded = dplyr::n_distinct(student_id), .groups = "drop") %>%
    dplyr::filter(n_graded >= min_n)

  if (nrow(pop_counts) == 0) return(data.frame())
  course_keys <- pop_counts %>% dplyr::select(campus, subject_course)

  summarize_dfw <- function(df, prefix) {
    df %>%
      dplyr::semi_join(course_keys, by = c("campus", "subject_course")) %>%
      dplyr::group_by(campus, subject_course) %>%
      dplyr::summarize(
        n_graded = dplyr::n_distinct(student_id),
        n_dfw    = dplyr::n_distinct(student_id[outcome == "dfw"]),
        .groups  = "drop"
      ) %>%
      dplyr::mutate(dfw_rate = round(n_dfw / n_graded, 3)) %>%
      dplyr::rename_with(
        ~ paste0(prefix, "_", .),
        -dplyr::all_of(c("campus", "subject_course"))
      )
  }

  pop_summary      <- summarize_dfw(dplyr::filter(graded, in_pop),  "pop")
  baseline_summary <- summarize_dfw(dplyr::filter(graded, !in_pop), "baseline")

  pop_summary %>%
    dplyr::left_join(baseline_summary, by = c("campus", "subject_course")) %>%
    dplyr::filter(is.na(pop_n_dfw) | pop_n_dfw >= min_dfw_n) %>%
    dplyr::arrange(dplyr::desc(pop_dfw_rate))
}


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

# Restrict to courses whose subject prefix is in `subject_code`.
#
# cedar_grades does not retain subject_code, so derive the prefix from
# subject_course ("HIST 1150"). NULL or empty means every subject.
.filter_stopout_subject <- function(df, subject_code = NULL) {
  if (is.null(subject_code) || length(subject_code) == 0) return(df)
  if (!"subject_course" %in% names(df)) return(df)
  dplyr::filter(df, sub(" .*", "", subject_course) %in% subject_code)
}


#' Select First Eligible Roadblocks Observations
#'
#' Input must already respect the course scope, population window, grade edge,
#' and complete follow-up edge. Keep one outcome per student/course/campus at
#' the first eligible term. Agreeing records in that term collapse to one;
#' conflicting pass/DFW records exclude the entire comparison, without advancing
#' to a later term. Later enrollment remains in the separate full-history return
#' lookup. Coverage counts refer to scoped outcome records before size thresholds.
#'
#' @param graded Classified, eligible outcome records.
#' @return List with `data` (selected observations), `term_range` (eligible
#'   anchors before selection), and `info` (coverage counts and a display-ready
#'   note). Counts include population and other students across the scoped input;
#'   they are student-course-campus observations, not unique people across courses.
#' @keywords internal
select_stopout_observations <- function(graded) {
  valid <- graded %>%
    dplyr::filter(!is.na(student_id), nzchar(trimws(student_id)),
                  !is.na(term), !is.na(subject_course), nzchar(trimws(subject_course)),
                  outcome %in% c("pass", "dfw")) %>%
    dplyr::select(student_id, campus, subject_course, term, outcome)
  keys <- c("student_id", "campus", "subject_course")
  # Sort once and join the earliest keys back to retain ALL first-term outcomes.
  # Per-student grouped R callbacks are prohibitively slow on the full history.
  first_terms <- valid %>%
    dplyr::arrange(term) %>%
    dplyr::distinct(student_id, campus, subject_course, .keep_all = TRUE) %>%
    dplyr::select(-outcome)
  first_records <- dplyr::semi_join(valid, first_terms, by = c(keys, "term"))
  first_outcomes <- dplyr::distinct(first_records)
  # Only pass/DFW remain: a repeated key here means conflicting first outcomes.
  ambiguous <- first_outcomes[duplicated(first_outcomes[keys]), keys, drop = FALSE]
  unambiguous <- dplyr::anti_join(first_records, ambiguous, by = keys)
  selected <- dplyr::distinct(unambiguous)
  info <- list(
    n_selected = nrow(selected),
    n_ambiguous = nrow(ambiguous),
    n_invalid = nrow(graded) - nrow(valid),
    n_later = nrow(valid) - nrow(first_records),
    n_duplicates = nrow(unambiguous) - nrow(selected)
  )
  info$note <- sprintf(paste0(
    "Across scoped population and other students, before size thresholds: %s first eligible student-course-campus observations; ",
    "%s later outcome records omitted, %s agreeing first-term records collapsed, ",
    "%s comparisons excluded for conflicting first-term outcomes, and %s invalid records excluded."),
    format(info$n_selected, big.mark = ","), format(info$n_later, big.mark = ","),
    format(info$n_duplicates, big.mark = ","), format(info$n_ambiguous, big.mark = ","),
    format(info$n_invalid, big.mark = ","))
  list(data = selected, info = info,
       term_range = if (nrow(valid) > 0L) range(valid$term) else c(NA_integer_, NA_integer_))
}

#' Classify Student Enrollment Records as Pass or DFW
#'
#' Takes enrollment records and labels each as `"pass"` or `"dfw"` using the
#' canonical CEDAR classification (`classify_enrollment_outcomes()` in
#' trunk/utils.R — see the "CEDAR-wide DFW policy" note in AGENTS.md).
#' A+ through C and CR pass. Every other recorded non-audit grade, including
#' incomplete and no-credit outcomes, is DFW/nonpassing. AUD is excluded
#' regardless of registration status. Blank/NA grades are excluded unless
#' the record is a late drop.
#'
#' Late drops (`STATUS_DROP_LATE`) are DFW. Early drops
#' (`STATUS_DROP_EARLY`) are excluded entirely: a drop before the deadline
#' posts no grade and is not an academic outcome.
#'
#' @param students Data frame. The `cedar_students` table.
#'
#' @return Data frame with columns: `student_id`, `term`, `campus`, `subject_course`,
#'   `outcome` (`"pass"` or `"dfw"`).
#'
#' @keywords internal
classify_outcomes <- function(students) {

  students %>%
    select(student_id, term, campus, subject_course, final_grade, registration_status_code) %>%
    distinct() %>%
    classify_enrollment_outcomes() %>%
    select(student_id, term, campus, subject_course, outcome)
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

  # Census participation is evidence of return. Waitlists and early drops are
  # not enrollment; late drops were enrolled at census and therefore do count.
  if ("registration_status_code" %in% names(students)) {
    students <- students %>%
      filter(registration_status_code %in% c(STATUS_REGISTERED, STATUS_DROP_LATE))
  }
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
#' Given one selected observation per student in a single population and
#' course/campus, computes DFW context and stop-out rates on that same set,
#' plus a within-group chi-squared test. Repeated or incomplete observations
#' are rejected rather than silently reweighting the denominators.
#'
#' @param course_group Data frame. First eligible observations selected by
#'   `get_stopout()` for one group in one course/campus. Must have columns:
#'   `student_id`, `term`, `outcome`, and `stopped_out` (pre-joined by caller).
#' @param prefix Character. Column name prefix for the returned values
#'   (`"cohort"` or `"baseline"`).
#'
#' @return Single-row tibble with columns:
#'   `{prefix}_n_dfw`, `{prefix}_n_pass`, `{prefix}_n_graded`, `{prefix}_dfw_rate`,
#'   `{prefix}_dfw_stopout_rate`, `{prefix}_pass_stopout_rate`,
#'   `{prefix}_stopout_gap`, `{prefix}_p_value`
#'
#' @keywords internal
compute_stopout_for_group <- function(course_group, prefix) {

  empty_row <- tibble(
    n_graded          = NA_integer_,
    dfw_rate          = NA_real_,
    n_dfw             = NA_integer_,
    n_pass            = NA_integer_,
    dfw_stopout_rate  = NA_real_,
    pass_stopout_rate = NA_real_,
    stopout_gap       = NA_real_,
    p_value           = NA_real_
  )
  names(empty_row) <- paste0(prefix, "_", names(empty_row))

  if (nrow(course_group) == 0) return(empty_row)

  if (anyNA(course_group$student_id) || anyDuplicated(course_group$student_id)) {
    stop("Roadblocks requires one observation per student within each course/campus group.")
  }
  if (anyNA(course_group$stopped_out) ||
      !all(course_group$outcome %in% c("pass", "dfw"))) {
    stop("Roadblocks requires complete stop-out flags and classifiable outcomes.")
  }

  # stopped_out is pre-joined by get_stopout() before the per-course loop
  analysis <- course_group

  dfw_data  <- analysis %>% filter(outcome == "dfw")
  pass_data <- analysis %>% filter(outcome == "pass")

  n_dfw  <- nrow(dfw_data)
  n_pass <- nrow(pass_data)

  dfw_stopout  <- if (n_dfw > 0)  mean(dfw_data$stopped_out,  na.rm = TRUE) else NA_real_
  pass_stopout <- if (n_pass > 0) mean(pass_data$stopped_out, na.rm = TRUE) else NA_real_

  stopout_gap <- if (!is.na(dfw_stopout) && !is.na(pass_stopout)) {
    dfw_stopout - pass_stopout
  } else NA_real_

  # Chi-squared test: can we detect a difference in stop-out rates?
  p_value <- NA_real_
  if (n_dfw >= 5 && n_pass >= 5) {
    contingency <- table(analysis$outcome, analysis$stopped_out)
    if (all(dim(contingency) == c(2, 2))) {
      # tryCatch is intentional (exempt from the no-fallback rule): chisq.test
      # errors on degenerate tables (e.g. a zero-margin row/column), and NA is
      # the mathematically correct p-value for an untestable contingency table.
      p_value <- tryCatch(
        suppressWarnings(chisq.test(contingency)$p.value),
        error = function(e) NA_real_
      )
    }
  }

  result <- tibble(
    n_graded          = n_dfw + n_pass,
    dfw_rate          = n_dfw / (n_dfw + n_pass),
    n_dfw             = n_dfw,
    n_pass            = n_pass,
    dfw_stopout_rate  = dfw_stopout,
    pass_stopout_rate = pass_stopout,
    stopout_gap       = stopout_gap,
    p_value           = p_value
  )
  names(result) <- paste0(prefix, "_", names(result))
  result
}


# Null-coalescing operator - define only if not already loaded.
if (!exists("%||%")) {
  `%||%` <- function(a, b) if (!is.null(a)) a else b
}
