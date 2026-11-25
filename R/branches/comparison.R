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
# Use cases (cones/course-sequence-effect.R, cones/downstream-instructor-balance.R):
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
#' @param students cedar_registrations data frame, used to determine each student's
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
                              applicants = NULL,
                              covariate_terms = NULL, student_terms = NULL) {
  message("[comparison.R] Building comparison groups...")
  message("[comparison.R]   Treatment: ", length(treatment_ids), " students")
  message("[comparison.R]   Control pool: ", length(pool_ids), " students")

  if (length(treatment_ids) == 0) stop("[comparison.R] treatment_ids is empty.")
  if (length(pool_ids) == 0)      stop("[comparison.R] pool_ids is empty.")

  all_ids <- union(treatment_ids, pool_ids)

  # Entry term: the student's first enrolled term on cedar_student_terms, or
  # the first programs term without the table. Used where covariate_terms
  # doesn't cover a student.
  if (!is.null(student_terms) && nrow(student_terms) > 0) {
    entry_terms <- student_terms %>%
      filter(student_id %in% all_ids, enrolled) %>%
      group_by(student_id) %>%
      summarize(covariate_term = as.integer(min(term, na.rm = TRUE)), .groups = "drop")
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
    # Each student's latest such record: one sort and the first row a student
    # has, where a slice per student took a tenth of a large comparison.
    arrange(desc(term)) %>%
    distinct(student_id, .keep_all = TRUE) %>%
    arrange(student_id) %>%
    select(
      student_id, covariate_term,
      student_population, student_classification, student_level, student_campus,
      first_gen, pell_eligible, ipeds_race, gender, time_status,
      residency, academic_standing,
      # Kept DESCRIPTIVE, never as a matching covariate — see the note below and
      # the continuous_cols list in compute_balance().
      current_unm_gpa = inst_gpa
    )
  # A table of its own, built from its columns: the declarations table's
  # stamps (its schema version) describe that table and are not carried on.
  prog_covs <- tibble::tibble(!!!prog_covs)

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
  groups <- .attach_position_covariates(groups, programs, student_terms)

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
#' @param students cedar_registrations, or NULL.
#' @param programs cedar_programs, for the transfer block.
#' @param student_terms cedar_student_terms, or NULL.
#' @return `groups` with the three columns added.
#' @keywords internal
.attach_position_covariates <- function(groups, programs, student_terms) {

  ids <- unique(groups$student_id)

  if (is.null(student_terms) || nrow(student_terms) == 0) {
    message("[comparison.R]   No student_terms table — cumulative GPA and credit covariates ",
            "unavailable. Pass student_terms = cedar_student_terms.")
    groups$cum_gpa_entering       <- NA_real_
    groups$unm_credits_entering   <- NA_real_
    groups$total_credits_entering <- NA_real_
  } else {
    # --- Cumulative GPA entering the covariate term (the table's grade points) ---
    gpa_tl <- build_gpa_timeline(student_terms, opt = list(student_ids = ids))
    groups <- groups %>%
      attach_gpa_position(gpa_tl, term_col = "covariate_term") %>%
      mutate(
        cum_gpa_entering = if_else(timeline_valid, gpa_entering, NA_real_)
      ) %>%
      select(-gpa_entering, -timeline_valid)

    # --- Credit position entering the covariate term ---
    credit_tl <- build_credit_timeline(
      student_terms, programs = programs, opt = list(student_ids = ids))
    groups <- groups %>%
      left_join(
        credit_tl %>%
          filter(timeline_valid) %>%
          select(student_id, covariate_term = term,
                 unm_credits_entering, total_credits_entering),
        by = c("student_id", "covariate_term"))
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

# ── High-school GPA bands ─────────────────────────────────────────────────────
# The one banding every like-with-like comparison uses (Course Sequence, the
# similar-students course effect). A missing GPA is its own band, never
# dropped: who has no GPA on file is not random.
CEDAR_HS_GPA_BREAKS <- c(2.75, 3.25, 3.75)
CEDAR_HS_GPA_BANDS  <- c("2.75 or lower", "2.76 to 3.25", "3.26 to 3.75", "above 3.75", "not on file")

#' The high-school GPA band of each value
#'
#' @param gpa Numeric high-school GPAs; NA is "not on file".
#' @return A factor over `CEDAR_HS_GPA_BANDS`.
hs_gpa_band <- function(gpa) {
  band <- CEDAR_HS_GPA_BANDS[findInterval(gpa, CEDAR_HS_GPA_BREAKS, left.open = TRUE) + 1L]
  factor(if_else(is.na(gpa), "not on file", band), levels = CEDAR_HS_GPA_BANDS)
}

# ── Entering-GPA bands ────────────────────────────────────────────────────────
# A continuing student's GPA entering a term (build_gpa_timeline()'s
# gpa_entering), for comparisons within like students. No "not on file" band:
# a first-term student has no entering GPA, and a reader leaves them out or
# reads them apart.
CEDAR_ENTERING_GPA_BREAKS <- c(2.5, 3.0, 3.5)
CEDAR_ENTERING_GPA_BANDS  <- c("below 2.5", "2.5 to 2.99", "3.0 to 3.49", "3.5 or higher")

#' The entering-GPA band of each value
#'
#' @param gpa Numeric entering GPAs; NA stops (a band is for a known GPA).
#' @return A factor over `CEDAR_ENTERING_GPA_BANDS`.
entering_gpa_band <- function(gpa) {
  if (anyNA(gpa)) stop("[comparison.R] entering_gpa_band(): a missing GPA has no band.", call. = FALSE)
  factor(CEDAR_ENTERING_GPA_BANDS[findInterval(gpa, CEDAR_ENTERING_GPA_BREAKS) + 1L],
         levels = CEDAR_ENTERING_GPA_BANDS)
}

#' One high-school GPA per student, off the applicants table
#'
#' The first row per student, as build_comparison() reads it, with the same
#' cleaning: a value above 5.5 or at or below zero is an unscaled or empty
#' record and is not a GPA.
#'
#' With `with_act`, the student's ACT composite as `act_score` too (1 to 36;
#' anything else is not a score). An applicants table with no ACT column gives
#' every student NA: an installation without test scores has none to read.
#'
#' @param applicants `cedar_applicants`.
#' @param with_act TRUE adds `act_score`. Default FALSE.
#' @return A tibble of `student_id` and `high_school_cum_gpa`, one row each.
applicant_hs_gpa <- function(applicants, with_act = FALSE) {
  missing <- setdiff(c("student_id", "high_school_cum_gpa"), names(applicants))
  if (length(missing) > 0) {
    stop("[comparison.R] applicant_hs_gpa: applicants lacks ", paste(missing, collapse = ", "), call. = FALSE)
  }
  first_rows <- applicants %>% distinct(student_id, .keep_all = TRUE)
  out <- first_rows %>%
    transmute(student_id,
              high_school_cum_gpa = if_else(high_school_cum_gpa > 5.5 | high_school_cum_gpa <= 0,
                                            NA_real_, as.numeric(high_school_cum_gpa)))
  if (isTRUE(with_act)) {
    act <- if ("unm_act_combined_score" %in% names(first_rows)) as.numeric(first_rows$unm_act_combined_score) else NA_real_
    out$act_score <- if_else(!is.na(act) & act >= 1 & act <= 36, act, NA_real_)
  }
  out
}

#' Each student-term's Pell eligibility and first-generation status, as cell labels
#'
#' The declarations table carries both on every row of a student's term. A
#' student-term is "yes" when any of its rows says so, "no" when one says no
#' and none says yes, and absent from the result when no row records it.
#'
#' @param programs `cedar_programs`.
#' @return A tibble of `student_id`, `term`, `pell` and `first_gen`
#'   (`"yes"`, `"no"` or NA), one row per student-term.
student_term_aid <- function(programs) {
  missing <- setdiff(c("student_id", "term", "pell_eligible", "first_gen"), names(programs))
  if (length(missing) > 0) {
    stop("[comparison.R] student_term_aid: programs lacks ", paste(missing, collapse = ", "), call. = FALSE)
  }
  # Counted over the whole table at once: which student-term each row belongs
  # to, then whether any of its rows says yes and whether any says no. Asking
  # each student-term in turn (a summarize() over half a million groups) took
  # 20 of the 50 seconds an Against Non-Takers run spent (ISSUES M68).
  by_term <- tibble::tibble(student_id = programs$student_id, term = as.integer(programs$term)) %>%
    group_by(student_id, term)
  student_terms <- group_keys(by_term)
  row_term <- group_indices(by_term)
  said <- function(x) {
    x <- as.logical(x)
    any_row <- function(rows) tabulate(row_term[rows], nrow(student_terms)) > 0L
    if_else(any_row(which(x)), "yes", if_else(any_row(which(!x)), "no", NA_character_))
  }
  student_terms %>% mutate(pell = said(programs$pell_eligible), first_gen = said(programs$first_gen))
}
