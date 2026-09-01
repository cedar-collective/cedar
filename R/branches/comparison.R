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
                              covariate_terms = NULL, term_credits = NULL) {
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
      residency, academic_standing,
      # Kept DESCRIPTIVE, never as a matching covariate — see the note below and
      # the continuous_cols list in compute_balance().
      current_unm_gpa = inst_gpa
    )

  groups <- prog_covs %>%
    mutate(group = if_else(student_id %in% treatment_ids, "treatment", "control"))

  # WHY `current_unm_gpa` IS DESCRIPTIVE AND NOT A COVARIATE
  #
  # It is Banner's Institution GPA, stamped at the data pull — the student's UNM
  # cumulative GPA *today*, not at the covariate term. It is a perfectly good
  # answer to "how strong is this student overall", and it is the better of the
  # two on coverage: it is populated for 166,859 students against 41,016 for the
  # reconstruction (25%), because the reconstruction loses left-truncated
  # students, first graded terms, and any UNM coursework predating the window.
  # So it earns a place in the group profile.
  #
  # What it cannot do is certify balance. It is measured after the treatment AND
  # after the outcome, so balancing on it partially balances on the outcome and
  # biases the estimated effect toward zero. That is structural, not a precision
  # problem: measured against the reconstruction it sits a median 0.142 away, but
  # the gap is worst at a student's FIRST term (0.220; 44.8% differ by >0.25),
  # which is exactly where sequencing questions are asked, and the signed error
  # grows from +0.005 to +0.081 across a career because the frozen value keeps
  # folding in later work.
  #
  # Hence: shown in the profile, excluded from continuous_cols.

  # Academic-position covariates are reconstructed, not read off cedar_programs.
  #
  # `inst_gpa`, `overall_credits_earned` and `inst_credits_attempted` are stamped
  # as of the data pull onto every historical row, so the "closest record at or
  # before covariate_term" logic above returns the same number whichever term it
  # lands on. Matching on them means matching on where each student ENDED UP,
  # which for any outcome measured after the covariate term is partly the outcome
  # itself — and the balance table would then certify balance on a variable never
  # measured at the point of comparison. Measured: `inst_gpa` is identical across
  # every term of a student's own history for 67.8% of students with 5+ terms.
  # See the field reliability contract in AGENTS.md.
  groups <- .attach_position_covariates(groups, students, programs, term_credits)

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
    filter(balance_band == "substantial") %>%
    pull(covariate)
  if (length(flagged_covs) > 0) {
    message("[comparison.R]   WARNING: substantial observed covariate differences (|SMD| > 0.25) on: ",
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


# ── .attach_position_covariates ───────────────────────────────────────────────

#' Reconstructed academic-position covariates at the covariate term
#'
#' Replaces the three banned cumulative fields with values rebuilt from the
#' per-term series, joined at each student's own `covariate_term`:
#'
#'   `cum_gpa_entering`       from [build_gpa_timeline()]     (was `inst_gpa`)
#'   `unm_credits_entering`   from [build_credit_timeline()]  (was `inst_credits_attempted`)
#'   `total_credits_entering` from [build_credit_timeline()]  (was `overall_credits_earned`)
#'
#' All three are *entering* values — the student's record walking into the term
#' where the comparison happens. An "after" value would include the term's own
#' coursework, which in a course-effect study is the outcome being measured.
#'
#' Any input that is unavailable yields NA columns rather than a fallback to the
#' frozen field: an absent covariate weakens a match visibly, a wrong one does
#' not. Left-truncated students get NA for the same reason — their running totals
#' start mid-career.
#'
#' @param groups Tibble with `student_id` and `covariate_term`.
#' @param students cedar_students, or NULL.
#' @param programs cedar_programs, for the transfer block.
#' @param term_credits cedar_student_term_credits, or NULL.
#' @return `groups` with the three columns added.
#' @keywords internal
.attach_position_covariates <- function(groups, students, programs, term_credits) {

  ids <- unique(groups$student_id)

  # --- Cumulative GPA entering the covariate term ---
  if (!is.null(students) && nrow(students) > 0) {
    gpa_tl <- build_gpa_timeline(students, opt = list(student_ids = ids))
    groups <- groups %>%
      attach_gpa_position(gpa_tl, term_col = "covariate_term") %>%
      mutate(
        cum_gpa_entering = if_else(timeline_valid, gpa_entering, NA_real_)
      ) %>%
      select(-gpa_entering, -timeline_valid)
  } else {
    message("[comparison.R]   No students table — cumulative GPA covariate unavailable.")
    groups$cum_gpa_entering <- NA_real_
  }

  # --- Credit position entering the covariate term ---
  if (!is.null(term_credits) && nrow(term_credits) > 0) {
    credit_tl <- build_credit_timeline(
      term_credits, programs = programs, opt = list(student_ids = ids))
    groups <- groups %>%
      left_join(
        credit_tl %>%
          filter(timeline_valid) %>%
          select(student_id, covariate_term = term,
                 unm_credits_entering, total_credits_entering),
        by = c("student_id", "covariate_term"))
  } else {
    message("[comparison.R]   No term_credits table — credit covariates unavailable. ",
            "Pass term_credits = cedar_student_term_credits.")
    groups$unm_credits_entering   <- NA_real_
    groups$total_credits_entering <- NA_real_
  }

  n_gpa <- sum(!is.na(groups$cum_gpa_entering))
  message("[comparison.R]   Position covariates: cumulative GPA for ", n_gpa,
          " of ", nrow(groups), " students; credits for ",
          sum(!is.na(groups$total_credits_entering)), ".")

  groups
}


# ── compute_balance ───────────────────────────────────────────────────────────

# Classify an absolute standardized mean difference for display and audit.
# Exact 0.10 and 0.25 values stay in the review band; only values above 0.25
# retain the legacy `flagged` warning.
classify_smd_balance <- function(smd) {
  dplyr::case_when(
    is.na(smd) ~ "unavailable",
    abs(smd) < 0.10 ~ "small",
    abs(smd) <= 0.25 ~ "review",
    TRUE ~ "substantial"
  )
}


summarize_smd_balance <- function(balance_band) {
  observed <- balance_band[balance_band != "unavailable"]
  if (length(observed) == 0L) return("unavailable")
  if (any(observed == "substantial")) return("substantial")
  if (any(observed == "review")) return("review")
  "small"
}


#' Compute covariate balance between treatment and control groups
#'
#' For binary and continuous covariates, computes group means/proportions and
#' standardized mean differences (SMDs). Absolute SMDs below 0.10 are classified
#' as small observed differences, values from 0.10 through 0.25 require review,
#' and values above 0.25 are classified as substantial observed differences.
#' These descriptive bands do not establish comparability or remove confounding.
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
#'       n_treatment, n_control, value_treatment, value_control, unit, smd,
#'       balance_band, flagged. SMD retains full precision; display layers round it.}
#'     \item{categorical}{Named list of frequency tibbles for categorical covariates.}
#'     \item{overall_balance}{The most serious observed SMD band, or unavailable
#'       when no SMD can be estimated.}
#'   }
compute_balance <- function(groups) {
  treatment <- filter(groups, group == "treatment")
  control   <- filter(groups, group == "control")

  binary_cols <- intersect(
    c("first_gen", "pell_eligible"),
    names(groups)
  )
  continuous_cols <- intersect(
    # cum_gpa_entering / *_credits_entering are reconstructed at the covariate
    # term (see .attach_position_covariates). `current_unm_gpa` is deliberately
    # absent and must not be added: it is measured at the data pull, after the
    # treatment and after the outcome, so balancing on it certifies a
    # comparability that was never measured and shrinks the effect toward zero.
    # It is shown in the group profile instead.
    c("cum_gpa_entering", "high_school_cum_gpa", "unm_act_combined_score",
      "transfer_gpa", "current_age",
      "unm_credits_entering", "total_credits_entering"),
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
    balance_band <- classify_smd_balance(smd)
    smd_rows[[col]] <- tibble(
      covariate       = col,
      type            = "binary",
      n_treatment     = sum(!is.na(treatment[[col]])),
      n_control       = sum(!is.na(control[[col]])),
      value_treatment = round(p_t * 100, 1),
      value_control   = round(p_c * 100, 1),
      unit            = "%",
      smd             = smd,
      balance_band    = balance_band,
      flagged         = balance_band == "substantial"
    )
  }

  for (col in continuous_cols) {
    mu_t  <- mean(treatment[[col]], na.rm = TRUE)
    mu_c  <- mean(control[[col]],   na.rm = TRUE)
    var_t <- var(treatment[[col]],  na.rm = TRUE)
    var_c <- var(control[[col]],    na.rm = TRUE)
    denom <- sqrt((coalesce(var_t, 0) + coalesce(var_c, 0)) / 2)
    smd   <- if (!is.na(denom) && denom > 0) (mu_t - mu_c) / denom else NA_real_
    balance_band <- classify_smd_balance(smd)
    smd_rows[[col]] <- tibble(
      covariate       = col,
      type            = "continuous",
      n_treatment     = sum(!is.na(treatment[[col]])),
      n_control       = sum(!is.na(control[[col]])),
      value_treatment = round(mu_t, 2),
      value_control   = round(mu_c, 2),
      unit            = "mean",
      smd             = smd,
      balance_band    = balance_band,
      flagged         = balance_band == "substantial"
    )
  }

  # A groups tibble can legitimately carry no SMD-able covariate (all of its
  # columns categorical). bind_rows(list()) then returns a 0x0 tibble with no
  # `smd` column and arrange() errors on it, so build the empty shape
  # explicitly. This is a real empty result, not a fallback masking a failure.
  smd_table <- if (length(smd_rows) == 0) {
    tibble(
      covariate = character(), type = character(),
      n_treatment = integer(), n_control = integer(),
      value_treatment = numeric(), value_control = numeric(),
      unit = character(), smd = numeric(), balance_band = character(),
      flagged = logical()
    )
  } else {
    bind_rows(smd_rows) %>% arrange(desc(abs(smd)))
  }

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

  list(
    smd_table = smd_table,
    categorical = categorical_dist,
    overall_balance = summarize_smd_balance(smd_table$balance_band)
  )
}


# Null-coalescing operator - define only if not already loaded.
if (!exists("%||%")) {
  `%||%` <- function(a, b) if (!is.null(a)) a else b
}
