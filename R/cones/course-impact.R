# course-impact.R — Course Impact Analysis
#
# Observational comparisons of student outcomes between a "treatment" group
# (took a course, had a specific instructor, followed a course sequence) and a
# comparable control group. All analyses call build_comparison() (branches/comparison.R)
# for covariate joining and balance reporting.
#
# Three question types:
#
#   1. RETENTION — get_course_retention()
#      Did students who took course X persist longer than comparable students
#      who didn't? Primary use case: FYEX 1110, college-success courses.
#      Treatment: enrolled in X. Control: eligible pool, never took X.
#      Outcome: enrolled at +1, +2, +3 semesters from entry term.
#
#   2. SEQUENCE — get_course_sequence_effect()
#      Do students who took course X before course Y earn better grades in Y?
#      Treatment: passed X before enrolling in Y. Control: took Y without prior X.
#      Outcome: pass/DFW rate in Y.
#
#   3. INSTRUCTOR — get_instructor_effect()
#      Did instructor A's students in course X outperform instructor B's when
#      they later took course Y?
#      Treatment: had instructor A in X, then took Y. Control: had instructor B.
#      Outcome: pass/DFW rate in Y.
#
# Interactive covariate filters (opt$filters) narrow the comparison pool after
# group assignment so users can see how the result changes under different
# comparability assumptions — without rebuilding groups from scratch.
#
# Depends on: build_comparison(), compute_balance() (branches/comparison.R)
#             STATUS_REGISTERED (lists/status_codes.R)
#             GRADES_DFW, GRADES_PASS (lists/grades.R)

`%||%` <- function(a, b) if (!is.null(a)) a else b


# ── Internal helpers ──────────────────────────────────────────────────────────

# Advance a term code by n_semesters, skipping summer.
# Term codes: YYYYSS where SS = 10 (Spring), 60 (Summer), 80 (Fall).
#   Fall(80)   + 1 → Spring next year: +30
#   Spring(10) + 1 → Fall same year:   +70
.advance_n_terms <- function(term_codes, n) {
  result <- as.integer(term_codes)
  for (i in seq_len(n)) {
    season <- result %% 100L
    result <- if_else(season == 80L, result + 30L, result + 70L)
  }
  result
}

# Apply a named list of covariate equality filters to a groups tibble.
# Students with NA in the filtered column are excluded.
# Example: filters = list(first_gen = TRUE, pell_eligible = TRUE)
.apply_covariate_filters <- function(groups, filters) {
  for (col in names(filters)) {
    val <- filters[[col]]
    if (!col %in% names(groups)) {
      message("[course-impact.R] Filter column '", col, "' not in groups — skipping.")
      next
    }
    groups <- filter(groups, !is.na(.data[[col]]) & .data[[col]] == val)
  }
  groups
}

# Compute retention rates (with 95% Wilson-style CI) for a labeled groups tibble.
# Returns a tibble: group, terms_out, n, n_enrolled, rate, ci_low, ci_high.
.compute_retention <- function(groups, students, n_terms) {
  all_ids <- unique(groups$student_id)

  entry_lookup <- students %>%
    filter(student_id %in% all_ids) %>%
    group_by(student_id) %>%
    summarize(entry_term = min(term), .groups = "drop")

  enrolled_terms <- students %>%
    filter(student_id %in% all_ids) %>%
    select(student_id, term) %>%
    distinct()

  purrr::map_dfr(seq_len(n_terms), function(offset) {
    targets <- entry_lookup %>%
      mutate(target_term = .advance_n_terms(entry_term, offset))

    enrolled_flag <- targets %>%
      left_join(
        enrolled_terms %>%
          rename(target_term = term) %>%
          mutate(enrolled = TRUE),
        by = c("student_id", "target_term")
      ) %>%
      mutate(enrolled = replace_na(enrolled, FALSE)) %>%
      select(student_id, enrolled)

    groups %>%
      select(student_id, group) %>%
      left_join(enrolled_flag, by = "student_id") %>%
      group_by(group) %>%
      summarize(
        terms_out  = offset,
        n          = n(),
        n_enrolled = sum(enrolled, na.rm = TRUE),
        rate       = round(n_enrolled / n, 3),
        .groups    = "drop"
      ) %>%
      mutate(
        # Wald CI — adequate for n > 30; clip to [0,1]
        ci_low  = pmax(0, round(rate - 1.96 * sqrt(rate * (1 - rate) / n), 3)),
        ci_high = pmin(1, round(rate + 1.96 * sqrt(rate * (1 - rate) / n), 3))
      )
  })
}

# Summarize group covariates into a compact profile table.
# inst_gpa and overall_credits_earned are drawn from each student's covariate_term
# (the term they took course X for treatment, course Y for control) rather than
# their entry term, so these reflect academic standing at the point of comparison.
.group_profile <- function(groups) {
  groups %>%
    group_by(group) %>%
    summarize(
      n                    = n(),
      pct_first_gen        = round(100 * mean(first_gen,     na.rm = TRUE), 1),
      pct_pell             = round(100 * mean(pell_eligible, na.rm = TRUE), 1),
      mean_hs_gpa          = if ("high_school_cum_gpa"    %in% names(.))
                               round(mean(high_school_cum_gpa,    na.rm = TRUE), 2) else NA_real_,
      mean_act             = if ("unm_act_combined_score" %in% names(.))
                               round(mean(unm_act_combined_score, na.rm = TRUE), 1) else NA_real_,
      mean_inst_gpa        = round(mean(inst_gpa,              na.rm = TRUE), 2),
      mean_credits_earned  = if ("overall_credits_earned" %in% names(.))
                               round(mean(overall_credits_earned, na.rm = TRUE), 1) else NA_real_,
      .groups = "drop"
    )
}


# ── 1. Course Retention ───────────────────────────────────────────────────────

#' Course Retention Comparison
#'
#' Compares multi-term persistence between students who took a target course
#' (treatment) and comparable students who didn't (control). Primary use case
#' is college-success or intervention courses like FYEX 1110.
#'
#' The eligible control pool is scoped to students entering in the same terms
#' as treatment students and matching opt$eligible_populations. Interactive
#' covariate filters (opt$filters) can narrow both groups further so users can
#' test whether the retention gap holds within specific subgroups.
#'
#' @param students cedar_students data frame.
#' @param programs cedar_programs data frame.
#' @param applicants cedar_applicants data frame, or NULL.
#' @param opt Named list of options:
#'   \describe{
#'     \item{course}{Character vector. Subject_course value(s) defining treatment
#'       (e.g., "FYEX 1110"). Required.}
#'     \item{eligible_populations}{Character vector of student_population values
#'       that define who could have taken the course. Default: first-time freshman
#'       populations.}
#'     \item{campus}{Character vector. Restrict to these campus codes. Optional.}
#'     \item{n_terms}{Integer. Semesters of retention to track (default 3).}
#'     \item{min_n}{Integer. Minimum students per group (default 15).}
#'     \item{filters}{Named list of covariate equality filters applied after group
#'       assignment, e.g., list(first_gen = TRUE). Optional.}
#'   }
#'
#' @return Named list:
#'   \describe{
#'     \item{course}{Treatment course(s).}
#'     \item{retention}{Tibble: group, terms_out, n, n_enrolled, rate, ci_low, ci_high.}
#'     \item{group_profile}{Compact covariate summary for each group.}
#'     \item{balance}{From compute_balance(): smd_table + categorical distributions.}
#'     \item{n_treatment, n_control}{Group sizes after any filters.}
#'     \item{groups}{Full labeled tibble — pass back to Shiny for dynamic filtering.}
#'   }
get_course_retention <- function(students, programs, applicants = NULL, opt = list()) {

  course <- opt$course
  if (is.null(course) || length(course) == 0)
    stop("[course-impact.R] opt$course is required.")

  n_terms  <- as.integer(opt$n_terms %||% 3L)
  min_n    <- as.integer(opt$min_n   %||% 15L)
  campus   <- opt$campus

  eligible_populations <- opt$eligible_populations

  message("[course-impact.R] get_course_retention: ", paste(course, collapse = ", "))

  # ── Treatment: registered students in the target course ─────────────────────
  treated_records <- students %>%
    filter(
      subject_course %in% course,
      registration_status_code %in% STATUS_REGISTERED
    )
  if (!is.null(campus)) treated_records <- filter(treated_records, campus %in% .env$campus)

  if (nrow(treated_records) == 0)
    stop("[course-impact.R] No registered students found for course: ",
         paste(course, collapse = ", "))

  treatment_ids <- unique(treated_records$student_id)
  message("[course-impact.R]   Treatment: ", length(treatment_ids),
          " students enrolled in the course.")

  # ── Credits earned at treatment time ────────────────────────────────────────
  # For each treatment student, find their overall_credits_earned in the term
  # they took the course. Use this to define the credit band for control matching.
  # overall_credits_earned lives in cedar_programs (per-student per-term snapshot).
  treatment_credits <- programs %>%
    filter(student_id %in% treatment_ids) %>%
    inner_join(
      treated_records %>% select(student_id, term),
      by = c("student_id", "term")
    ) %>%
    group_by(student_id) %>%
    arrange(term) %>%
    slice(1) %>%
    ungroup() %>%
    select(student_id, overall_credits_earned) %>%
    filter(!is.na(overall_credits_earned))

  credits_range <- range(treatment_credits$overall_credits_earned)
  credits_width <- diff(credits_range)
  message("[course-impact.R]   Treatment credits at course time: ",
          round(credits_range[1], 0), "–", round(credits_range[2], 0),
          " (", nrow(treatment_credits), " of ", length(treatment_ids), " with credit data)")

  # ── Control pool: matched on credits ────────────────────────────────────────
  # Find all students (excluding treatment) whose overall_credits_earned in any
  # term falls within the treatment credit range. Using the full range rather than
  # individual matching keeps the pool large enough for balance assessment while
  # excluding students at very different academic stages.
  # Pad by 10% of range on each side to avoid hard-edge exclusions near the boundary.
  credits_pad  <- max(3, round(credits_width * 0.10))
  credits_lo   <- max(0, credits_range[1] - credits_pad)
  credits_hi   <- credits_range[2] + credits_pad

  message("[course-impact.R]   Credit match window: ", round(credits_lo, 0),
          "–", round(credits_hi, 0), " (pad ±", credits_pad, ")")

  pool_ids <- programs %>%
    filter(
      !student_id %in% treatment_ids,
      !is.na(overall_credits_earned),
      overall_credits_earned >= credits_lo,
      overall_credits_earned <= credits_hi
    ) %>%
    pull(student_id) %>%
    unique()

  # Optionally restrict to specified populations (e.g. first-time freshmen).
  if (!is.null(eligible_populations)) {
    pool_ids <- programs %>%
      filter(
        student_id %in% pool_ids,
        student_population %in% eligible_populations
      ) %>%
      pull(student_id) %>%
      unique()
  }

  if (!is.null(campus)) {
    pool_ids <- programs %>%
      filter(student_id %in% pool_ids, student_campus %in% campus) %>%
      pull(student_id) %>%
      unique()
  }

  message("[course-impact.R]   Eligible control pool: ", length(pool_ids),
          " students (credit-matched)")

  if (length(pool_ids) < min_n)
    stop("[course-impact.R] Control pool too small (", length(pool_ids),
         " students, min_n = ", min_n, "). ",
         "Check opt$eligible_populations and opt$campus.")

  # ── Build comparison groups with covariates + balance ───────────────────────
  comparison <- build_comparison(
    treatment_ids = treatment_ids,
    pool_ids      = pool_ids,
    programs      = programs,
    applicants    = applicants,
    students      = students
  )
  groups <- comparison$groups

  # ── Apply interactive covariate filters (optional) ──────────────────────────
  filters <- opt$filters %||% list()
  if (length(filters) > 0) {
    groups <- .apply_covariate_filters(groups, filters)
    n_t <- sum(groups$group == "treatment")
    n_c <- sum(groups$group == "control")
    message("[course-impact.R]   After filters: treatment = ", n_t, ", control = ", n_c)
    if (n_t < min_n || n_c < min_n)
      stop("[course-impact.R] Filtered groups too small (min_n = ", min_n, "). ",
           "Relax opt$filters or lower opt$min_n.")
    comparison$balance     <- compute_balance(groups)
    comparison$n_treatment <- n_t
    comparison$n_control   <- n_c
  }

  # ── Multi-term retention ─────────────────────────────────────────────────────
  retention <- .compute_retention(groups, students, n_terms)

  message("[course-impact.R]   Retention tracked over ", n_terms, " terms. Done.")

  list(
    course        = course,
    retention     = retention,
    group_profile = .group_profile(groups),
    balance       = comparison$balance,
    n_treatment   = comparison$n_treatment,
    n_control     = comparison$n_control,
    groups        = groups
  )
}


# ── 2. Course Sequence Effect ─────────────────────────────────────────────────

#' Course Sequence Effect
#'
#' Compares grades in course Y between students who passed course X before
#' taking Y (treatment) and students who took Y without prior X (control).
#' Surfaces whether completing X meaningfully prepares students for Y.
#'
#' @param students cedar_students data frame.
#' @param programs cedar_programs data frame.
#' @param applicants cedar_applicants data frame, or NULL.
#' @param opt Named list:
#'   \describe{
#'     \item{course_x}{Character. The preparatory course. Required.}
#'     \item{course_y}{Character. The outcome course. Required.}
#'     \item{campus}{Character vector. Optional campus filter.}
#'     \item{min_n}{Integer. Minimum students per group (default 15).}
#'     \item{filters}{Named list of covariate equality filters. Optional.}
#'   }
#'
#' @return Named list:
#'   \describe{
#'     \item{course_x, course_y}{Course identifiers.}
#'     \item{outcomes}{Tibble: group, outcome (pass/dfw), n, pct.}
#'     \item{group_profile}{Compact covariate summary per group.}
#'     \item{balance}{From compute_balance().}
#'     \item{n_treatment, n_control}{Group sizes.}
#'   }
get_course_sequence_effect <- function(students, programs, applicants = NULL,
                                       opt = list()) {
  course_x <- opt$course_x
  course_y <- opt$course_y
  if (is.null(course_x) || is.null(course_y))
    stop("[course-impact.R] opt$course_x and opt$course_y are both required.")

  min_n  <- as.integer(opt$min_n %||% 15L)
  campus <- opt$campus

  message("[course-impact.R] get_course_sequence_effect: ", course_x, " → ", course_y)

  # Students who took Y (registered, with a gradeable outcome)
  took_y <- students %>%
    filter(
      subject_course %in% course_y,
      registration_status_code %in% STATUS_REGISTERED
    )
  if (!is.null(campus)) took_y <- filter(took_y, campus %in% .env$campus)
  took_y <- took_y %>%
    distinct(student_id, term, .keep_all = TRUE) %>%
    select(student_id, term_y = term, grade_y = final_grade)

  if (nrow(took_y) == 0)
    stop("[course-impact.R] No students found for course_y: ", course_y)

  # When did each student first pass X?
  passed_x <- students %>%
    filter(
      subject_course %in% course_x,
      registration_status_code %in% STATUS_REGISTERED,
      final_grade %in% GRADES_PASS
    ) %>%
    group_by(student_id) %>%
    summarize(term_x = min(term), .groups = "drop")

  # Label treatment (passed X strictly before taking Y) vs. control (took Y, no prior X)
  sequence_data <- took_y %>%
    left_join(passed_x, by = "student_id") %>%
    mutate(
      group = if_else(!is.na(term_x) & term_x < term_y, "treatment", "control")
    )

  treatment_ids <- filter(sequence_data, group == "treatment") %>% pull(student_id) %>% unique()
  pool_ids      <- filter(sequence_data, group == "control")   %>% pull(student_id) %>% unique()

  # Summarize the term range and gap distribution for transparency
  treatment_terms <- sequence_data %>%
    filter(group == "treatment") %>%
    mutate(terms_gap = term_y - term_x)

  term_range_x <- range(filter(students, student_id %in% treatment_ids,
                                subject_course %in% course_x)$term)
  term_range_y <- range(took_y$term_y)

  message("[course-impact.R]   Took ", course_x, " before ", course_y, ": ",
          length(treatment_ids), " students")
  message("[course-impact.R]   ", course_x, " offered: ", term_range_x[1], "–", term_range_x[2])
  message("[course-impact.R]   ", course_y, " offered: ", term_range_y[1], "–", term_range_y[2])
  message("[course-impact.R]   Took ", course_y, " without prior ", course_x, ": ",
          length(pool_ids), " students")
  message("[course-impact.R]   Note: treatment requires passing (not just taking) ", course_x)

  if (length(treatment_ids) < min_n || length(pool_ids) < min_n)
    stop("[course-impact.R] Groups too small (min_n = ", min_n, "). ",
         "Try a different course pair or lower min_n.")

  # Build per-student covariate terms: treatment uses the term they took X,
  # control uses the term they took Y. This gives a meaningful GPA/credits
  # snapshot at the moment of comparison, not at their entry term years earlier.
  covariate_terms <- bind_rows(
    sequence_data %>%
      filter(group == "treatment") %>%
      transmute(student_id, covariate_term = as.integer(term_x)),
    sequence_data %>%
      filter(group == "control") %>%
      transmute(student_id, covariate_term = as.integer(term_y))
  ) %>%
    distinct(student_id, .keep_all = TRUE)

  comparison <- build_comparison(
    treatment_ids   = treatment_ids,
    pool_ids        = pool_ids,
    programs        = programs,
    applicants      = applicants,
    students        = students,
    covariate_terms = covariate_terms
  )
  groups <- comparison$groups

  # ── GPA band filter ──────────────────────────────────────────────────────────
  # HS GPA is often imbalanced in sequence analyses because stronger students
  # self-select into completing prerequisites. Restricting both groups to a
  # common GPA window makes the comparison more defensible.
  # opt$hs_gpa_min / opt$hs_gpa_max are optional; NULL means no restriction.
  hs_gpa_min <- opt$hs_gpa_min
  hs_gpa_max <- opt$hs_gpa_max
  if (!is.null(hs_gpa_min) || !is.null(hs_gpa_max)) {
    if (!"high_school_cum_gpa" %in% names(groups)) {
      message("[course-impact.R]   GPA band requested but high_school_cum_gpa not available ",
              "(cedar_applicants may not be loaded) — skipping GPA filter.")
    } else {
      before <- nrow(groups)
      if (!is.null(hs_gpa_min))
        groups <- filter(groups, is.na(high_school_cum_gpa) | high_school_cum_gpa >= hs_gpa_min)
      if (!is.null(hs_gpa_max))
        groups <- filter(groups, is.na(high_school_cum_gpa) | high_school_cum_gpa <= hs_gpa_max)
      message("[course-impact.R]   GPA band [", hs_gpa_min %||% "-∞", ", ",
              hs_gpa_max %||% "+∞", "]: ", before, " → ", nrow(groups), " students")
    }
  }

  filters <- opt$filters %||% list()
  if (length(filters) > 0)
    groups <- .apply_covariate_filters(groups, filters)

  n_t <- sum(groups$group == "treatment")
  n_c <- sum(groups$group == "control")
  if (n_t < min_n || n_c < min_n)
    stop("[course-impact.R] Groups too small after filtering (treatment=", n_t,
         ", control=", n_c, ", min_n=", min_n, ").")

  if (!is.null(hs_gpa_min) || !is.null(hs_gpa_max) || length(filters) > 0) {
    comparison$balance     <- compute_balance(groups)
    comparison$n_treatment <- n_t
    comparison$n_control   <- n_c
  }

  # Grade outcomes in Y by group.
  # sequence_data already carries the group label — use it directly, restricted
  # to students that survived build_comparison() (those with program records).
  outcomes <- sequence_data %>%
    filter(student_id %in% groups$student_id) %>%
    mutate(
      outcome = case_when(
        grade_y %in% GRADES_PASS ~ "pass",
        grade_y %in% GRADES_DFW  ~ "dfw",
        TRUE                      ~ NA_character_
      )
    ) %>%
    filter(!is.na(outcome)) %>%
    group_by(group, outcome) %>%
    summarize(n = n(), .groups = "drop") %>%
    group_by(group) %>%
    mutate(pct = round(100 * n / sum(n), 1)) %>%
    ungroup()

  # Count how many treatment students were dropped by build_comparison()
  # (students without program records don't make it into groups)
  n_dropped_by_programs <- length(treatment_ids) - comparison$n_treatment

  message("[course-impact.R]   Sequence effect computed. Done.")

  list(
    course_x                = course_x,
    course_y                = course_y,
    outcomes                = outcomes,
    group_profile           = .group_profile(groups),
    balance                 = comparison$balance,
    n_treatment             = comparison$n_treatment,
    n_control               = comparison$n_control,
    n_took_x_before_y       = length(treatment_ids),
    n_took_y_without_x      = length(pool_ids),
    n_dropped_by_programs   = n_dropped_by_programs,
    term_range_x            = term_range_x,
    term_range_y            = term_range_y
  )
}


# ── 3. Downstream Success by Instructor ───────────────────────────────────────

#' Downstream Success by Instructor
#'
#' Among students who took course X and later took course Y, compares grade
#' outcomes in Y between students taught by different instructors in X.
#' Surfaces descriptive differences in downstream outcomes by upstream instructor.
#'
#' The balance table reveals whether instructor sections self-selected different
#' kinds of students — the most common confounder in multi-section courses.
#'
#' @param students cedar_students data frame.
#' @param programs cedar_programs data frame.
#' @param applicants cedar_applicants data frame, or NULL.
#' @param opt Named list:
#'   \describe{
#'     \item{course_x}{Character. The upstream course. Required.}
#'     \item{course_y}{Character. The downstream outcome course. Required.}
#'     \item{campus}{Character vector. Optional campus filter.}
#'     \item{min_n}{Integer. Minimum students per instructor who later took Y
#'       (default 15). Instructors below this threshold are excluded.}
#'   }
#'
#' @return Named list:
#'   \describe{
#'     \item{course_x, course_y}{Course identifiers.}
#'     \item{outcomes}{Tibble: instructor_name, outcome, n, total, pct.}
#'     \item{instructor_counts}{Tibble: instructor_name, n (students who took Y).}
#'     \item{balance}{Balance between the two most-common instructors' student pools.}
#'     \item{n_treatment, n_control}{Sizes for the reference instructor comparison.}
#'   }
get_instructor_effect <- function(students, programs, applicants = NULL,
                                   opt = list()) {
  course_x <- opt$course_x
  course_y <- opt$course_y
  if (is.null(course_x) || is.null(course_y))
    stop("[course-impact.R] opt$course_x and opt$course_y are both required.")

  min_n  <- as.integer(opt$min_n %||% 15L)
  campus <- opt$campus

  message("[course-impact.R] get_instructor_effect: ", course_x, " → ", course_y)

  # Students who took Y — include late drops (DG/DW) so they count as DFW outcomes
  took_y <- students %>%
    filter(
      subject_course %in% course_y,
      registration_status_code %in% c(STATUS_REGISTERED, STATUS_DROP_LATE)
    )
  if (!is.null(campus)) took_y <- filter(took_y, campus %in% .env$campus)
  took_y <- took_y %>%
    distinct(student_id, term, .keep_all = TRUE) %>%
    select(student_id, term_y = term, grade_y = final_grade,
           status_y = registration_status_code)

  if (nrow(took_y) == 0)
    stop("[course-impact.R] No students found for course_y: ", course_y)

  # First instructor each student had in X
  x_instructor <- students %>%
    filter(
      subject_course %in% course_x,
      registration_status_code %in% STATUS_REGISTERED,
      !is.na(instructor_name), nzchar(instructor_name)
    )
  if (!is.null(campus)) x_instructor <- filter(x_instructor, campus %in% .env$campus)
  x_instructor <- x_instructor %>%
    group_by(student_id) %>%
    arrange(term) %>%
    slice(1) %>%
    ungroup() %>%
    select(student_id, instructor_name, term_x = term)

  # Students who took X before Y, with their instructor
  instructor_data <- took_y %>%
    inner_join(x_instructor, by = "student_id") %>%
    filter(term_x < term_y)

  if (nrow(instructor_data) == 0)
    stop("[course-impact.R] No students found who took ", course_x,
         " before ", course_y, ".")

  # Total enrollment in X per instructor (all students, not just those who took Y).
  # This gives context for how many students each instructor has taught overall,
  # vs. n_took_y which is only the subset who later enrolled in the downstream course.
  total_enrl_in_x <- students %>%
    filter(
      subject_course %in% course_x,
      registration_status_code %in% STATUS_REGISTERED,
      !is.na(instructor_name), nzchar(instructor_name)
    ) %>%
    { if (!is.null(campus)) filter(., campus %in% .env$campus) else . } %>%
    count(instructor_name, name = "n_total_in_x")

  term_range_x <- range(x_instructor$term_x)
  term_range_y <- range(took_y$term_y)

  # Keep only instructors with enough downstream students
  instructor_counts <- instructor_data %>%
    count(instructor_name, sort = TRUE) %>%
    rename(n_took_y = n) %>%
    filter(n_took_y >= min_n)

  if (nrow(instructor_counts) < 2) {
    n_inst_any <- dplyr::n_distinct(instructor_data$instructor_name)
    stop("Fewer than 2 instructors have ≥ ", min_n,
         " students who later took ", course_y, ". ",
         n_inst_any, " instructor(s) had any such students at all. ",
         "Lower 'Min students per instructor' (currently ", min_n, ") to see results.")
  }

  instructor_data <- filter(instructor_data,
                             instructor_name %in% instructor_counts$instructor_name)

  # Grade outcomes in Y by instructor — wide format (one row per instructor).
  # Three mutually exclusive outcomes (sum to n_took_y):
  #   dropped = late drop (DG/DW registration status)
  #   failed  = registered to end but grade was not a pass (D, F, W, I, NR, NC, etc.)
  #   pass    = C- or better, CR, P, S
  # pct_dfw = (n_dropped + n_failed) / n_took_y
  outcomes_long <- instructor_data %>%
    mutate(
      outcome = case_when(
        status_y %in% STATUS_DROP_LATE ~ "dropped",
        grade_y %in% GRADES_PASS       ~ "pass",
        TRUE                           ~ "failed"
      )
    ) %>%
    group_by(instructor_name, outcome) %>%
    summarize(n = n(), .groups = "drop") %>%
    group_by(instructor_name) %>%
    mutate(pct = round(100 * n / sum(n), 1)) %>%
    ungroup()

  outcomes_wide <- outcomes_long %>%
    tidyr::pivot_wider(
      id_cols     = "instructor_name",
      names_from  = "outcome",
      values_from = c("n", "pct"),
      values_fill = 0
    )
  for (.col in c("n_pass", "pct_pass", "n_failed", "pct_failed", "n_dropped", "pct_dropped")) {
    if (!.col %in% names(outcomes_wide)) outcomes_wide[[.col]] <- 0
  }

  outcomes <- outcomes_wide %>%
    left_join(instructor_counts, by = "instructor_name") %>%
    left_join(total_enrl_in_x,   by = "instructor_name") %>%
    mutate(
      pct_took_y = round(100 * n_took_y / n_total_in_x, 1),
      pct_dfw    = round(100 * (n_failed + n_dropped) / n_took_y, 1)
    ) %>%
    dplyr::select(
      instructor_name,
      n_total_in_x,
      n_took_y,
      pct_took_y,
      n_pass, pct_pass,
      n_failed, pct_failed,
      n_dropped, pct_dropped,
      pct_dfw
    ) %>%
    arrange(desc(n_took_y))

  message("[course-impact.R]   Instructors with enough students: ",
          nrow(instructor_counts))

  # Balance: reference instructor vs. second-most-common instructor.
  # Pairwise comparison is more interpretable than one vs. everyone —
  # "everyone else" conflates multiple instructors with different student mixes.
  ref_instructor <- opt$reference_instructor %||% instructor_counts$instructor_name[1]
  cmp_instructor <- instructor_counts$instructor_name[
    instructor_counts$instructor_name != ref_instructor
  ][1]
  treatment_ids  <- filter(instructor_data, instructor_name == ref_instructor)$student_id
  pool_ids       <- filter(instructor_data, instructor_name == cmp_instructor)$student_id

  message("[course-impact.R]   Balance: ", ref_instructor, " vs. ", cmp_instructor,
          " (", length(treatment_ids), " vs. ", length(pool_ids), " students)")
  if (nrow(instructor_counts) > 2) {
    message("[course-impact.R]   Note: ", nrow(instructor_counts) - 2,
            " additional instructor(s) excluded from balance check.")
  }

  comparison <- build_comparison(
    treatment_ids = treatment_ids,
    pool_ids      = pool_ids,
    programs      = programs,
    applicants    = applicants,
    students      = students
  )

  message("[course-impact.R]   Instructor effect computed. Done.")

  list(
    course_x              = course_x,
    course_y              = course_y,
    outcomes              = outcomes,
    instructor_counts     = instructor_counts,
    balance               = comparison$balance,
    n_treatment           = comparison$n_treatment,
    n_control             = comparison$n_control,
    reference_instructor  = ref_instructor,
    comparison_instructor = cmp_instructor,
    term_range_x          = term_range_x,
    term_range_y          = term_range_y
  )
}
