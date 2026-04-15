# comparison.R — Comparison Group Builder
#
# Builds labeled treatment/control student groups for observational studies.
# Handles covariate joining from cedar_programs and (optionally) cedar_applicants,
# and computes a balance table with standardized mean differences (SMDs).
#
# The *caller* (cone) is responsible for defining who is in the treatment group
# and who is eligible for the control pool. This branch handles joining,
# labeling, and balance reporting only.
#
# Use cases (all in cones/course-impact.R):
#   - Retention:   took course X vs. eligible pool who didn't
#   - Sequence:    took X before Y vs. took Y without prior X
#   - Instructor:  had instructor A in X vs. instructor B, then took Y
#
# Depends on: nothing in cedar domain — pure data joining + statistics.

`%||%` <- function(a, b) if (!is.null(a)) a else b


# ── build_comparison ──────────────────────────────────────────────────────────

#' Build a labeled treatment/control tibble with covariates and balance stats
#'
#' Joins covariates from cedar_programs at each student's reference term and
#' optionally cedar_applicants. Returns labeled groups and a balance table
#' with standardized mean differences so the caller can assess comparability.
#'
#' By default, covariates are pulled at the student's entry term (first term
#' in the system). Callers can pass \code{covariate_terms} to use a specific
#' term per student instead — e.g., the term they took course X — which gives
#' a more meaningful snapshot of GPA and credits at the point of comparison.
#'
#' @param treatment_ids Character vector of student IDs in the treatment group.
#' @param pool_ids Character vector of eligible control student IDs.
#'   Must already exclude treatment_ids and any ineligible students.
#' @param programs cedar_programs data frame.
#' @param applicants cedar_applicants data frame, or NULL to skip admissions covariates.
#' @param students cedar_students data frame, used to determine each student's
#'   entry term (first term with any enrollment). If NULL, entry term is derived
#'   from programs instead.
#' @param covariate_terms Optional named integer vector or two-column tibble
#'   (student_id, covariate_term) giving the term at which to pull program
#'   covariates for each student. Overrides the entry-term default for any
#'   student present in this argument; students not listed fall back to entry term.
#'
#' @return Named list:
#'   \describe{
#'     \item{groups}{Tibble: student_id, group ("treatment"/"control"),
#'       entry_term, and all available covariates.}
#'     \item{balance}{Named list from compute_balance(): smd_table and categorical.}
#'     \item{n_treatment}{Integer. Students in treatment group.}
#'     \item{n_control}{Integer. Students in control group.}
#'   }
build_comparison <- function(treatment_ids, pool_ids, programs,
                              applicants = NULL, students = NULL,
                              covariate_terms = NULL) {
  message("[comparison.R] Building comparison groups...")
  message("[comparison.R]   Treatment: ", length(treatment_ids), " students")
  message("[comparison.R]   Control pool: ", length(pool_ids), " students")

  if (length(treatment_ids) == 0) stop("[comparison.R] treatment_ids is empty.")
  if (length(pool_ids) == 0)      stop("[comparison.R] pool_ids is empty.")

  all_ids <- union(treatment_ids, pool_ids)

  # Entry term: first term in cedar_students (most reliable) or cedar_programs fallback.
  # Used as fallback when covariate_terms doesn't cover a student.
  if (!is.null(students) && nrow(students) > 0) {
    entry_terms <- students %>%
      filter(student_id %in% all_ids) %>%
      group_by(student_id) %>%
      summarize(covariate_term = min(term, na.rm = TRUE), .groups = "drop")
  } else {
    entry_terms <- programs %>%
      filter(student_id %in% all_ids) %>%
      group_by(student_id) %>%
      summarize(covariate_term = min(term, na.rm = TRUE), .groups = "drop")
  }

  # Override with caller-supplied covariate_terms where provided.
  # covariate_terms should be a tibble with columns (student_id, covariate_term).
  if (!is.null(covariate_terms)) {
    if (is.numeric(covariate_terms)) {
      # Named vector form: names are student_ids, values are terms
      covariate_terms <- tibble(
        student_id     = names(covariate_terms),
        covariate_term = as.integer(covariate_terms)
      )
    }
    entry_terms <- entry_terms %>%
      rows_update(covariate_terms, by = "student_id", unmatched = "ignore")
    message("[comparison.R]   Covariate terms: using caller-supplied terms for ",
            nrow(covariate_terms), " students (GPA/credits at course time, not entry term)")
  } else {
    message("[comparison.R]   Covariate terms: using entry term for all students")
  }

  # Covariates from cedar_programs at the reference term per student.
  # For each student, find the program record closest to (but not exceeding) their
  # covariate_term — handles cases where the exact term has no program record.
  prog_covs <- programs %>%
    filter(student_id %in% all_ids) %>%
    inner_join(entry_terms, by = "student_id") %>%
    filter(term <= covariate_term) %>%
    group_by(student_id) %>%
    arrange(desc(term)) %>%
    slice(1) %>%
    ungroup() %>%
    select(
      student_id, covariate_term,
      student_population, student_classification, student_level, student_campus,
      first_gen, pell_eligible, ipeds_race, gender, time_status,
      residency, inst_gpa, academic_standing,
      any_of(c("overall_credits_earned", "inst_credits_attempted"))
    )

  groups <- prog_covs %>%
    mutate(group = if_else(student_id %in% treatment_ids, "treatment", "control"))

  # Optionally join cedar_applicants covariates.
  # high_school_cum_gpa values > 5.5 are data artifacts (unscaled/weighted GPA) — capped.
  if (!is.null(applicants) && nrow(applicants) > 0) {
    message("[comparison.R]   Joining cedar_applicants covariates...")
    appl_covs <- applicants %>%
      filter(student_id %in% all_ids) %>%
      group_by(student_id) %>%
      slice(1) %>%
      ungroup() %>%
      select(student_id, any_of(c(
        "admissions_population", "high_school_cum_gpa", "unm_act_combined_score",
        "transfer_gpa", "high_school_self_reported_gpa", "current_age", "state_admit"
      ))) %>%
      mutate(across(
        any_of("high_school_cum_gpa"),
        ~ if_else(.x > 5.5 | .x <= 0, NA_real_, .x)
      ))

    groups <- left_join(groups, appl_covs, by = "student_id")
  }

  n_treatment <- sum(groups$group == "treatment")
  n_control   <- sum(groups$group == "control")
  message("[comparison.R]   Matched — treatment: ", n_treatment,
          "  control: ", n_control)

  balance <- compute_balance(groups)

  flagged_covs <- balance$smd_table %>%
    filter(flagged) %>%
    pull(covariate)
  if (length(flagged_covs) > 0) {
    message("[comparison.R]   WARNING: poor covariate balance (|SMD| > 0.25) on: ",
            paste(flagged_covs, collapse = ", "),
            ". Groups may not be comparable on these dimensions.")
  }

  list(
    groups      = groups,
    balance     = balance,
    n_treatment = n_treatment,
    n_control   = n_control
  )
}


# ── compute_balance ───────────────────────────────────────────────────────────

#' Compute covariate balance between treatment and control groups
#'
#' For binary and continuous covariates, computes group means/proportions and
#' standardized mean differences (SMDs). |SMD| < 0.1 indicates good balance;
#' |SMD| > 0.25 is flagged as potentially problematic.
#'
#' SMD formulas:
#'   Binary:     (p_t - p_c) / sqrt(p_bar * (1 - p_bar))
#'   Continuous: (mu_t - mu_c) / sqrt((var_t + var_c) / 2)
#'
#' Categorical covariates (ipeds_race, time_status, etc.) are returned as
#' frequency distributions rather than SMDs — proportions don't reduce to
#' a single meaningful scalar.
#'
#' @param groups Tibble from build_comparison() with a "group" column.
#' @return Named list:
#'   \describe{
#'     \item{smd_table}{Tibble sorted by |SMD| descending: covariate, type,
#'       n_treatment, n_control, value_treatment, value_control, unit, smd, flagged.}
#'     \item{categorical}{Named list of frequency tibbles for categorical covariates.}
#'   }
compute_balance <- function(groups) {
  treatment <- filter(groups, group == "treatment")
  control   <- filter(groups, group == "control")

  binary_cols <- intersect(
    c("first_gen", "pell_eligible"),
    names(groups)
  )
  continuous_cols <- intersect(
    c("inst_gpa", "high_school_cum_gpa", "unm_act_combined_score",
      "transfer_gpa", "current_age", "overall_credits_earned"),
    names(groups)
  )
  categorical_cols <- intersect(
    c("ipeds_race", "gender", "time_status", "residency",
      "admissions_population", "student_population", "student_classification"),
    names(groups)
  )

  smd_rows <- list()

  for (col in binary_cols) {
    p_t   <- mean(treatment[[col]], na.rm = TRUE)
    p_c   <- mean(control[[col]],   na.rm = TRUE)
    p_bar <- (p_t + p_c) / 2
    denom <- sqrt(p_bar * (1 - p_bar))
    smd   <- if (!is.na(denom) && denom > 0) (p_t - p_c) / denom else NA_real_
    smd_rows[[col]] <- tibble(
      covariate       = col,
      type            = "binary",
      n_treatment     = sum(!is.na(treatment[[col]])),
      n_control       = sum(!is.na(control[[col]])),
      value_treatment = round(p_t * 100, 1),
      value_control   = round(p_c * 100, 1),
      unit            = "%",
      smd             = round(smd, 3),
      flagged         = !is.na(smd) && abs(smd) > 0.25
    )
  }

  for (col in continuous_cols) {
    mu_t  <- mean(treatment[[col]], na.rm = TRUE)
    mu_c  <- mean(control[[col]],   na.rm = TRUE)
    var_t <- var(treatment[[col]],  na.rm = TRUE)
    var_c <- var(control[[col]],    na.rm = TRUE)
    denom <- sqrt((coalesce(var_t, 0) + coalesce(var_c, 0)) / 2)
    smd   <- if (!is.na(denom) && denom > 0) (mu_t - mu_c) / denom else NA_real_
    smd_rows[[col]] <- tibble(
      covariate       = col,
      type            = "continuous",
      n_treatment     = sum(!is.na(treatment[[col]])),
      n_control       = sum(!is.na(control[[col]])),
      value_treatment = round(mu_t, 2),
      value_control   = round(mu_c, 2),
      unit            = "mean",
      smd             = round(smd, 3),
      flagged         = !is.na(smd) && abs(smd) > 0.25
    )
  }

  smd_table <- bind_rows(smd_rows) %>%
    arrange(desc(abs(smd)))

  categorical_dist <- lapply(categorical_cols, function(col) {
    bind_rows(
      treatment %>%
        count(value = .data[[col]]) %>%
        mutate(group = "treatment", pct = round(100 * n / sum(n), 1)),
      control %>%
        count(value = .data[[col]]) %>%
        mutate(group = "control",   pct = round(100 * n / sum(n), 1))
    )
  })
  names(categorical_dist) <- categorical_cols

  list(smd_table = smd_table, categorical = categorical_dist)
}
