# course-sequence-effect.R — Course Sequence Effect
#
# Do students who took course X before course Y earn better grades in Y?
#
#   Treatment: passed X strictly before their first classifiable Y attempt.
#   Control:   took Y with no prior in-scope X pass.
#   Outcome:   pass/DFW in that one selected Y attempt.
#
# An observational comparison, never a causal estimate. Students self-select
# into completing prerequisites, so build_comparison() (branches/comparison.R)
# joins the covariates and compute_balance() reports how comparable the two
# groups actually are. The optional HS GPA band and the interactive covariate
# filters (opt$filters) narrow the pool *after* group assignment, so a user can
# watch the result move under different comparability assumptions without
# rebuilding the groups from scratch.
#
# Split from the former cones/course-impact.R on 2026-09-07. The instructor
# question that shared that file now lives in cones/course-instructor-effect.R;
# the two shared no code, only a filename.
#
#   (A RETENTION analysis, get_course_retention(), was removed 2026-08-01: it had
#   no callers, and its private .compute_retention() was shadowed at load time by
#   a same-named function in cones/course-retention.R. Course Dynamics > Retention
#   is served by get_retention_trend() in that file.)
#
# Depends on: build_comparison(), compute_balance(), hs_gpa_band() (branches/comparison.R)
#             prepare_course_attempts() (branches/course-attempts.R): both
#               courses' outcomes come off cedar_attempts (ADR-001 step 7)
#             cedar_longitudinal_edge() (branches/data-edges.R)

# ── Internal helpers ──────────────────────────────────────────────────────────

# NOTE: a private .advance_n_terms() lived here until 2026-08-01. It duplicated
# add_next_term_col() (R/trunk/utils.R) and got the summer case wrong
# (202460 + 70 = 202530, a code with no season). It went unnoticed because its
# only caller was the removed retention analysis. The canonical helper handles
# Summer -> Fall correctly and is what the live retention path uses.

# Apply a named list of covariate equality filters to a groups tibble.
# Students with NA in the filtered column are excluded.
# Example: filters = list(first_gen = TRUE, pell_eligible = TRUE)
.apply_covariate_filters <- function(groups, filters) {
  for (col in names(filters)) {
    val <- filters[[col]]
    if (!col %in% names(groups)) {
      message("[course-sequence-effect.R] Filter column '", col, "' not in groups — skipping.")
      next
    }
    groups <- filter(groups, !is.na(.data[[col]]) & .data[[col]] == val)
  }
  groups
}


# Summarize group covariates into a compact profile table.
#
# The academic-position figures are RECONSTRUCTED at each student's covariate_term
# (the term they took course X for treatment, course Y for control), not read off
# cedar_programs. The cumulative fields there are stamped at the data pull, so
# they describe where a student ended up rather than where they stood at the
# point of comparison — see .attach_position_covariates() in branches/comparison.R
# and the field reliability contract in AGENTS.md.
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
      mean_cum_gpa         = if ("cum_gpa_entering" %in% names(.))
                               round(mean(cum_gpa_entering, na.rm = TRUE), 2) else NA_real_,
      # Descriptive companion: where the two groups ended up overall. Much better
      # covered than the reconstruction, and NOT a matching covariate — it is
      # measured after the outcome. See comparison.R.
      mean_current_gpa     = if ("current_unm_gpa" %in% names(.))
                               round(mean(current_unm_gpa, na.rm = TRUE), 2) else NA_real_,
      mean_credits_earned  = if ("total_credits_entering" %in% names(.))
                               round(mean(total_credits_entering, na.rm = TRUE), 1) else NA_real_,
      .groups = "drop"
    )
}




# The two groups' Y outcomes inside each high-school GPA band, and the DFW
# rate the treatment group would have had at the control group's band rates
# (direct standardization to the treatment group's mix). A band whose control
# group is under `min_band_n` supplies no rate: its treatment students are
# left out of both sides of the standardized comparison and counted.
.sequence_band_comparison <- function(groups, y_outcomes, min_band_n) {
  rows <- groups %>%
    transmute(student_id, group, band = hs_gpa_band(high_school_cum_gpa)) %>%
    inner_join(y_outcomes, by = "student_id")
  by_band <- rows %>%
    group_by(band, group) %>%
    summarize(n = n(), n_dfw = sum(y_outcome == "dfw"), .groups = "drop") %>%
    mutate(dfw_pct = 100 * n_dfw / n) %>%
    arrange(band, desc(group))
  wide <- by_band %>%
    select(band, group, n, n_dfw) %>%
    tidyr::pivot_wider(names_from = group, values_from = c(n, n_dfw), values_fill = 0L)
  for (col in c("n_treatment", "n_control", "n_dfw_treatment", "n_dfw_control")) {
    if (!col %in% names(wide)) wide[[col]] <- 0L
  }
  usable <- wide %>% filter(n_treatment > 0L, n_control >= min_band_n)
  n_covered <- sum(usable$n_treatment)
  standardized <- list(
    n_treatment_covered  = n_covered,
    n_treatment_left_out = sum(wide$n_treatment) - n_covered,
    bands_used           = as.character(usable$band),
    min_band_n           = min_band_n,
    actual_dfw_pct       = if (n_covered > 0L) 100 * sum(usable$n_dfw_treatment) / n_covered else NA_real_,
    expected_dfw_pct     = if (n_covered > 0L) {
      100 * sum(usable$n_treatment * usable$n_dfw_control / usable$n_control) / n_covered
    } else NA_real_
  )
  list(by_band = by_band, standardized = standardized)
}

# ── Course Sequence Effect ────────────────────────────────────────────────────

#' Course Sequence Effect
#'
#' Compares grades in course Y between students who passed course X before
#' their first observed, classifiable Y attempt (treatment) and students whose
#' first such Y attempt occurred without a prior in-scope X pass (control).
#' Surfaces whether completing X meaningfully prepares students for Y.
#'
#' @param students cedar_registrations data frame: the comparison's covariates.
#' @param attempts The attempt measure table (`cedar_attempts`): both courses'
#'   outcomes, classified once (ADR-001 step 7).
#' @param programs cedar_programs data frame.
#' @param applicants cedar_applicants data frame, or NULL.
#' @param data_edges Optional output of [cedar_data_edges()]. Y outcomes stop at
#'   the longitudinal grade edge: the earlier of `last_enrolled_complete` and
#'   `last_graded`.
#' @param opt Named list:
#'   \describe{
#'     \item{course_x}{Character. The preparatory course. Required.}
#'     \item{course_y}{Character. The outcome course, or several codes read as
#'       one course (a course and its modular or stretch forms): a student's
#'       outcome is their earliest attempt of any of them. Required.}
#'     \item{campus}{Character vector. Optional campus filter.}
#'     \item{min_n}{Integer. Minimum students per group (default 15).}
#'     \item{filters}{Named list of covariate equality filters. Optional.}
#'     \item{hs_gpa_min, hs_gpa_max, act_min, act_max}{Optional windows on
#'       high-school GPA and ACT composite; a student with no value is left
#'       out while a window on it is active, and counted.}
#'     \item{min_band_n}{Smallest control group a high-school GPA band needs
#'       to supply a rate to the standardized comparison (default 10).}
#'   }
#'
#' @return Named list:
#'   \describe{
#'     \item{course_x, course_y}{Course identifiers.}
#'     \item{outcomes}{Tibble: group, outcome (pass/dfw), n, pct.}
#'     \item{group_profile}{Compact covariate summary per group.}
#'     \item{balance}{From compute_balance().}
#'     \item{n_treatment, n_control}{Group sizes.}
#'     \item{control_split}{The control group by what they did in X before Y:
#'       `prior_x` (`attempted_not_passed`: a classified X attempt strictly
#'       before Y, none passed; `no_prior_attempt`), `n`, `n_dfw`, `dfw_pct`.}
#'     \item{by_year}{Per calendar year of the Y attempt and group: `n`,
#'       `n_dfw`, `dfw_pct` (NA under `min_n`).}
#'     \item{by_hs_gpa_band}{Per high-school GPA band and group: `n`, `n_dfw`,
#'       `dfw_pct`; NULL without an applicants table.}
#'     \item{standardized}{The treatment group's actual DFW rate against the
#'       rate expected at the control group's rate in each band
#'       (`actual_dfw_pct`, `expected_dfw_pct`, `n_treatment_covered`,
#'       `n_treatment_left_out`, `bands_used`, `min_band_n`); NULL without an
#'       applicants table.}
#'     \item{n_missing_hs_gpa_excluded, n_missing_act_excluded}{Students left
#'       out by an active window for having no value.}
#'   }
get_course_sequence_effect <- function(students, attempts, programs, applicants = NULL,
                                       opt = list(), student_terms = NULL,
                                       data_edges = NULL) {
  course_x <- opt$course_x
  course_y <- opt$course_y
  if (is.null(course_x) || is.null(course_y))
    stop("[course-sequence-effect.R] opt$course_x and opt$course_y are both required.")

  min_n  <- as.integer(opt$min_n %||% 15L)
  campus <- opt$campus
  data_edges <- data_edges %||% opt$data_edges %||% cedar_data_edges(students)
  analysis_end_term <- cedar_longitudinal_edge(data_edges, grade_dependent = TRUE)
  if (is.null(analysis_end_term)) {
    stop("[course-sequence-effect.R] No complete term with sufficiently complete grades is available.")
  }

  y_label <- paste(course_y, collapse = " or ")
  min_band_n <- as.integer(opt$min_band_n %||% 10L)
  message("[course-sequence-effect.R] get_course_sequence_effect: ", course_x, " → ", y_label)

  # Apply the delivery-campus scope once, before deriving either side of the
  # sequence. Otherwise an excluded-campus X pass can relabel an in-scope Y
  # student as treatment. Both sides are read off cedar_attempts: `outcome` is
  # the stored pass / dfw, NA for an early drop or an ungraded registration,
  # which is what "classifiable" means here.
  scoped <- prepare_course_attempts(attempts, list(course = c(course_x, course_y),
                                                   course_campus = campus)) %>%
    filter(term <= analysis_end_term, !is.na(outcome))

  # Select one Y outcome per student: the earliest in-scope term with a
  # classifiable outcome. Attempts on several campuses in that term collapse
  # to one outcome, with any DFW taking precedence over a pass.
  took_y <- scoped %>%
    filter(subject_course %in% course_y) %>%
    group_by(student_id, term) %>%
    summarize(
      y_outcome = if_else(any(outcome == "dfw"), "dfw", "pass"),
      .groups = "drop"
    ) %>%
    arrange(student_id, term) %>%
    group_by(student_id) %>%
    slice_head(n = 1L) %>%
    ungroup() %>%
    rename(term_y = term)

  if (nrow(took_y) == 0)
    stop("[course-sequence-effect.R] No students found for course_y: ", y_label)

  # When did each student first pass X inside the same campus and grade edge?
  passed_x <- scoped %>%
    filter(subject_course %in% course_x, outcome == "pass") %>%
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

  if (length(treatment_ids) < min_n || length(pool_ids) < min_n)
    stop("[course-sequence-effect.R] Groups too small (min_n = ", min_n, "). ",
         "Try a different course pair or lower min_n.")

  # Summarize the term range and gap distribution for transparency
  term_range_x <- range(
    passed_x$term_x[passed_x$student_id %in% treatment_ids], na.rm = TRUE
  )
  term_range_y <- range(took_y$term_y)

  message("[course-sequence-effect.R]   Took ", course_x, " before ", y_label, ": ",
          length(treatment_ids), " students")
  message("[course-sequence-effect.R]   ", course_x, " offered: ", term_range_x[1], "–", term_range_x[2])
  message("[course-sequence-effect.R]   ", y_label, " offered: ", term_range_y[1], "–", term_range_y[2])
  message("[course-sequence-effect.R]   Took ", y_label, " without prior ", course_x, ": ",
          length(pool_ids), " students")
  message("[course-sequence-effect.R]   Note: treatment requires passing (not just taking) ", course_x)

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
    covariate_terms = covariate_terms,
    student_terms   = student_terms
  )
  groups <- comparison$groups
  n_dropped_by_programs <- length(treatment_ids) - comparison$n_treatment
  n_missing_hs_gpa_excluded <- 0L

  # ── GPA band filter ──────────────────────────────────────────────────────────
  # HS GPA is often imbalanced in sequence analyses because stronger students
  # self-select into completing prerequisites. Restricting both groups to a
  # common GPA window makes the comparison more defensible.
  # opt$hs_gpa_min / opt$hs_gpa_max are optional; NULL means no restriction.
  hs_gpa_min <- opt$hs_gpa_min
  hs_gpa_max <- opt$hs_gpa_max
  if (!is.null(hs_gpa_min) || !is.null(hs_gpa_max)) {
    if (!"high_school_cum_gpa" %in% names(groups)) {
      message("[course-sequence-effect.R]   GPA band requested but high_school_cum_gpa not available ",
              "(cedar_applicants may not be loaded) — skipping GPA filter.")
    } else {
      before <- nrow(groups)
      n_missing_hs_gpa_excluded <- sum(is.na(groups$high_school_cum_gpa))
      groups <- filter(groups, !is.na(high_school_cum_gpa))
      if (!is.null(hs_gpa_min))
        groups <- filter(groups, high_school_cum_gpa >= hs_gpa_min)
      if (!is.null(hs_gpa_max))
        groups <- filter(groups, high_school_cum_gpa <= hs_gpa_max)
      message("[course-sequence-effect.R]   GPA band [", hs_gpa_min %||% "-∞", ", ",
              hs_gpa_max %||% "+∞", "]: ", before, " → ", nrow(groups),
              " students; ", n_missing_hs_gpa_excluded, " missing GPA excluded")
    }
  }

  # ── ACT band filter ──────────────────────────────────────────────────────────
  # The placement measure, beside the GPA window. ACT is on file for a
  # minority of students at a test-optional institution, so the count left
  # out for having none is reported and is often most of the pool.
  act_min <- opt$act_min
  act_max <- opt$act_max
  n_missing_act_excluded <- 0L
  if (!is.null(act_min) || !is.null(act_max)) {
    if (!"unm_act_combined_score" %in% names(groups)) {
      stop("[course-sequence-effect.R] An ACT window needs the applicants table's ",
           "unm_act_combined_score, which the comparison does not carry.")
    }
    n_missing_act_excluded <- sum(is.na(groups$unm_act_combined_score))
    groups <- filter(groups, !is.na(unm_act_combined_score))
    if (!is.null(act_min)) groups <- filter(groups, unm_act_combined_score >= act_min)
    if (!is.null(act_max)) groups <- filter(groups, unm_act_combined_score <= act_max)
  }

  filters <- opt$filters %||% list()
  if (length(filters) > 0)
    groups <- .apply_covariate_filters(groups, filters)

  n_t <- sum(groups$group == "treatment")
  n_c <- sum(groups$group == "control")
  if (n_t < min_n || n_c < min_n)
    stop("[course-sequence-effect.R] Groups too small after filtering (treatment=", n_t,
         ", control=", n_c, ", min_n=", min_n, ").")

  if (!is.null(hs_gpa_min) || !is.null(hs_gpa_max) || !is.null(act_min) || !is.null(act_max) ||
      length(filters) > 0) {
    comparison$balance     <- compute_balance(groups)
    comparison$n_treatment <- n_t
    comparison$n_control   <- n_c
  }

  # Grade outcomes in the single selected Y attempt, restricted to students
  # that survived covariate construction and optional filters.
  outcomes <- sequence_data %>%
    filter(student_id %in% groups$student_id) %>%
    transmute(student_id, group, outcome = y_outcome) %>%
    group_by(group, outcome) %>%
    summarize(n = n_distinct(student_id), .groups = "drop") %>%
    group_by(group) %>%
    mutate(pct = round(100 * n / sum(n), 1)) %>%
    ungroup()

  # The control group is two different kinds of student: those who tried X
  # before Y and did not pass it, and those who never sat X before Y (placed
  # past it, transferred it in, or skipped it). Strictly earlier only: an X
  # attempt in Y's own term is not "before".
  tried_x <- scoped %>%
    filter(subject_course %in% course_x) %>%
    inner_join(took_y %>% select(student_id, term_y), by = "student_id") %>%
    filter(term < term_y) %>%
    distinct(student_id)
  final <- sequence_data %>% filter(student_id %in% groups$student_id)
  control_split <- final %>%
    filter(group == "control") %>%
    mutate(prior_x = if_else(student_id %in% tried_x$student_id, "attempted_not_passed", "no_prior_attempt")) %>%
    group_by(prior_x) %>%
    summarize(n = n(), n_dfw = sum(y_outcome == "dfw"), .groups = "drop") %>%
    mutate(dfw_pct = 100 * n_dfw / n)

  bands <- if ("high_school_cum_gpa" %in% names(groups)) {
    .sequence_band_comparison(groups, final %>% select(student_id, y_outcome), min_band_n)
  } else list(by_band = NULL, standardized = NULL)

  # The same two rates by the calendar year of the Y attempt, for change over
  # time. A group under min_n in a year keeps its count and has no rate.
  by_year <- final %>%
    mutate(year = as.integer(term_y %/% 100L)) %>%
    group_by(year, group) %>%
    summarize(n = n(), n_dfw = sum(y_outcome == "dfw"), .groups = "drop") %>%
    mutate(dfw_pct = if_else(n >= min_n, 100 * n_dfw / n, NA_real_)) %>%
    arrange(year, desc(group))

  message("[course-sequence-effect.R]   Sequence effect computed. Done.")

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
    n_missing_hs_gpa_excluded = n_missing_hs_gpa_excluded,
    n_missing_act_excluded  = n_missing_act_excluded,
    control_split           = control_split,
    by_year                 = by_year,
    n_min_year              = min_n,
    by_hs_gpa_band          = bands$by_band,
    standardized            = bands$standardized,
    y_attempt_rule          = "earliest classifiable in-scope Y attempt per student",
    term_range_x            = term_range_x,
    term_range_y            = term_range_y,
    analysis_end_term       = analysis_end_term,
    edge_note               = cedar_longitudinal_edge_note(
      data_edges, grade_dependent = TRUE
    )
  )
}

# Null-coalescing operator - define only if not already loaded.
if (!exists("%||%")) {
  `%||%` <- function(a, b) if (!is.null(a)) a else b
}
