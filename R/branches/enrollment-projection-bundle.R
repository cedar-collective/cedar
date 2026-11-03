# The saved bundle contract: provenance, construction, validation, and
# reading and writing a bundle file.

validate_enrollment_projection_model_provenance <- function(
    provenance, model_version, schema_version) {
  provenance_required <- c(
    "model_version", "schema_version", "git_commit",
    "relevant_worktree_dirty", "source_hashes", "source_snapshot"
  )
  if (!is.list(provenance)) {
    stop("[enrollment-projection-bundle.R] Projection model_provenance must be a list.",
         call. = FALSE)
  }
  provenance_missing <- setdiff(provenance_required, names(provenance))
  if (length(provenance_missing) > 0L) {
    stop(
      "[enrollment-projection-bundle.R] Projection model_provenance is missing: ",
      paste(provenance_missing, collapse = ", "),
      call. = FALSE
    )
  }
  if (!identical(as.character(provenance$model_version),
                 as.character(model_version)) ||
      !identical(as.integer(provenance$schema_version),
                 as.integer(schema_version))) {
    stop(
      "[enrollment-projection-bundle.R] Model provenance versions do not match the bundle.",
      call. = FALSE
    )
  }
  git_commit_valid <- is.character(provenance$git_commit) &&
    length(provenance$git_commit) == 1L &&
    (is.na(provenance$git_commit) ||
       grepl("^[0-9a-f]{40}$", provenance$git_commit))
  dirty_valid <- is.logical(provenance$relevant_worktree_dirty) &&
    length(provenance$relevant_worktree_dirty) == 1L
  hashes <- provenance$source_hashes
  snapshot <- provenance$source_snapshot
  source_names_valid <- is.character(hashes) && is.character(snapshot) &&
    length(hashes) > 0L && length(snapshot) > 0L &&
    !is.null(names(hashes)) && !is.null(names(snapshot)) &&
    identical(names(hashes), names(snapshot)) &&
    all(!is.na(names(hashes)) & nzchar(names(hashes))) &&
    all(!is.na(hashes) & grepl("^[0-9a-f]{64}$", hashes)) &&
    all(!is.na(snapshot))
  if (!git_commit_valid || !dirty_valid || !source_names_valid) {
    stop("[enrollment-projection-bundle.R] Projection model provenance is invalid.",
         call. = FALSE)
  }
  calculated_hashes <- vapply(
    snapshot,
    digest::digest,
    character(1),
    algo = "sha256",
    serialize = FALSE,
    USE.NAMES = TRUE
  )
  if (!identical(unname(calculated_hashes), unname(hashes))) {
    stop(
      "[enrollment-projection-bundle.R] Saved model source does not match its hashes.",
      call. = FALSE
    )
  }
  invisible(TRUE)
}


new_enrollment_projection_bundle <- function(analysis, target_term, as_of_term,
                                             scope_courses, scope_campuses,
                                             scope_market_id,
                                             model_provenance,
                                             model_config =
                                               enrollment_projection_model_config(),
                                             source_fingerprint = list(),
                                             target_schedule_as_of = as.Date(NA),
                                             built_at = Sys.time()) {
  bundle <- list(
    schema_version = CEDAR_ENROLLMENT_PROJECTION_SCHEMA_VERSION,
    model_version = CEDAR_ENROLLMENT_PROJECTION_MODEL_VERSION,
    built_at = as.POSIXct(built_at, tz = "UTC"),
    target_term = as.integer(target_term),
    as_of_term = as.integer(as_of_term),
    scope_courses = sort(unique(as.character(scope_courses))),
    scope_campuses = sort(unique(as.character(scope_campuses))),
    scope_market_id = as.character(scope_market_id),
    model_config = model_config,
    model_provenance = model_provenance,
    source_fingerprint = source_fingerprint,
    # When the target term's (draft) schedule was pulled; NA when the data
    # holds no schedule for the target term yet.
    target_schedule_as_of = as.Date(target_schedule_as_of),
    pressure_screen = analysis$pressure_screen,
    projections = analysis$projections,
    delivery_components = analysis$delivery_components,
    candidates = analysis$candidates,
    backtests = analysis$backtests,
    method_performance = analysis$method_performance,
    recent_history = analysis$recent_history,
    recent_campus_history = analysis$recent_campus_history,
    cohort_composition = analysis$cohort_composition
  )
  validate_enrollment_projection_bundle(bundle)
  bundle
}


validate_enrollment_projection_bundle <- function(bundle) {
  required <- c(
    "schema_version", "model_version", "built_at", "target_term", "as_of_term",
    "scope_courses", "scope_campuses", "scope_market_id", "model_config",
    "model_provenance", "source_fingerprint", "target_schedule_as_of",
    "pressure_screen", "projections",
    "delivery_components", "candidates", "backtests", "method_performance",
    "recent_history", "recent_campus_history", "cohort_composition"
  )
  missing <- setdiff(required, names(bundle))
  if (length(missing) > 0) {
    stop("[enrollment-projection-bundle.R] Projection bundle is missing: ",
         paste(missing, collapse = ", "), call. = FALSE)
  }
  if (!inherits(bundle$target_schedule_as_of, "Date") ||
      length(bundle$target_schedule_as_of) != 1L) {
    stop("[enrollment-projection-bundle.R] target_schedule_as_of must be one Date ",
         "(NA when no target schedule is loaded).", call. = FALSE)
  }
  if (!identical(as.integer(bundle$schema_version),
                 CEDAR_ENROLLMENT_PROJECTION_SCHEMA_VERSION)) {
    stop("[enrollment-projection-bundle.R] Unsupported projection bundle schema version.",
         call. = FALSE)
  }
  if (!identical(as.character(bundle$model_version),
                 CEDAR_ENROLLMENT_PROJECTION_MODEL_VERSION)) {
    stop("[enrollment-projection-bundle.R] Unsupported projection model version.",
         call. = FALSE)
  }
  validate_enrollment_projection_model_provenance(
    bundle$model_provenance,
    model_version = bundle$model_version,
    schema_version = bundle$schema_version
  )
  if (!is.list(bundle$model_config)) {
    stop("[enrollment-projection-bundle.R] Projection model_config must be a list.",
         call. = FALSE)
  }
  config_required <- names(enrollment_projection_model_config())
  config_missing <- setdiff(config_required, names(bundle$model_config))
  if (length(config_missing) > 0) {
    stop(
      "[enrollment-projection-bundle.R] Projection model_config is missing: ",
      paste(config_missing, collapse = ", "),
      call. = FALSE
    )
  }
  enrollment_projection_model_config(bundle$model_config)
  if (length(bundle$target_term) != 1L || is.na(bundle$target_term) ||
      length(bundle$as_of_term) != 1L || is.na(bundle$as_of_term) ||
      as.integer(bundle$as_of_term) >= as.integer(bundle$target_term)) {
    stop("[enrollment-projection-bundle.R] Bundle cutoff must precede its target term.",
         call. = FALSE)
  }
  if (length(bundle$scope_courses) == 0L ||
      any(is.na(bundle$scope_courses) | !nzchar(bundle$scope_courses)) ||
      length(bundle$scope_campuses) == 0L ||
      any(is.na(bundle$scope_campuses) | !nzchar(bundle$scope_campuses)) ||
      length(bundle$scope_market_id) != 1L || is.na(bundle$scope_market_id) ||
      !nzchar(bundle$scope_market_id)) {
    stop("[enrollment-projection-bundle.R] Bundle course, campus, and market scopes are required.",
         call. = FALSE)
  }

  scoped_tables <- c(
    "pressure_screen", "projections", "delivery_components", "candidates",
    "backtests", "method_performance", "recent_history", "recent_campus_history"
  )
  for (table_name in scoped_tables) {
    data <- bundle[[table_name]]
    if ("subject_course" %in% names(data) &&
        any(!data$subject_course %in% bundle$scope_courses)) {
      stop("[enrollment-projection-bundle.R] ", table_name,
           " contains a course outside the saved scope.", call. = FALSE)
    }
    if ("campus" %in% names(data) &&
        any(!data$campus %in% bundle$scope_campuses)) {
      stop("[enrollment-projection-bundle.R] ", table_name,
           " contains a campus outside the saved scope.", call. = FALSE)
    }
    if ("market_id" %in% names(data) &&
        any(data$market_id != bundle$scope_market_id)) {
      stop("[enrollment-projection-bundle.R] ", table_name,
           " contains a market outside the saved scope.", call. = FALSE)
    }
  }

  projection_require_columns(
    bundle$pressure_screen,
    c(
      "market_id", "subject_course", "target_term", "scheduled_capacity",
      "target_classlist_total_to_date", "target_registered_now",
      "target_early_drops_to_date", "target_late_drops_to_date",
      "target_other_status_to_date",
      "target_registration_observed", "target_available_seats",
      "target_classlist_fill", "target_active_fill", "target_capacity_reached",
      "recent_high_fill_terms", "recent_capacity_terms", "is_forced",
      "pressure_capacity_shortfall", "pressure_chronic_fill",
      "pressure_growth", "included", "inclusion_reason"
    ),
    "validate_enrollment_projection_bundle() pressure_screen"
  )
  projection_require_columns(
    bundle$projections,
    c("market_id", "college", "department", "subject_course", "target_term",
      "projected_classlist_total", "method_id",
      "stability", "stability_reason", "history_terms", "history_cv",
      "depth", "depth_reason", "accuracy", "accuracy_reason",
      "why_uncertain", "recommendation",
      "target_term_label", "backtest_terms", "backtest_term_range",
      "selection_wape", "selection_n_backtests", "selection_basis",
      "selection_pct_error_sd", "selection_common_n",
      "selection_default_wape", "selection_challenger_wape",
      "selection_reason", "capacity_constrained_history",
      "observed_baseline", "capacity_data_quality",
      "target_schedule_available", "raw_projected_classlist_total",
      "first_day_retention_rate", "first_day_retention_n_terms",
      "first_day_retention_terms", "projected_first_day_equivalent",
      "weighted_bias", "direction_consistency", "signed_error_history",
      "capacity_censored_wape", "n_capacity_censored_misses",
      "capacity_explained_error_share", "capacity_miss_assessment",
      "target_classlist_total_to_date", "target_registered_now",
      "target_early_drops_to_date", "target_late_drops_to_date",
      "target_other_status_to_date",
      "target_registration_observed", "target_available_seats",
      "target_classlist_fill", "target_active_fill", "target_capacity_reached",
      "projected_over_capacity",
      "capacity_limit_signal", "capacity_limit_status",
      "capacity_limit_note", "recommended_sections",
      "adjusted_projection", "adjusted_applicable", "adjusted_reason",
      "adjusted_saturated_prior", "adjusted_prior_first_day_fill",
      "adjusted_prior_first_day_basis", "adjusted_floor_uplift",
      "adjusted_floor_basis", "adjusted_delta_repeat", "adjusted_delta_sequence",
      "adjusted_sequence_courses", "adjusted_sequence_change",
      "adjusted_delta_feeder", "adjusted_regime_alarm", "adjusted_delta_basis",
      "expansion_pairs", "expansion_fill_rate", "expansion_note",
      "floor_note", "regime_note", "reference_section_size",
      "pressure_judged_terms", "pressure_full_terms", "pressure_bump_applied",
      "pressure_bump", "pressure_bump_note", "plan_feeder_adjustment",
      "plan_feeder_note", "planned_registrations", "plan_feeder_sections",
      "pressure_bump_sections", "seat_consistency", "seat_consistency_reason",
      "seat_consistency_terms", "seat_consistency_moves"),
    "validate_enrollment_projection_bundle() projections"
  )
  projection_require_columns(
    bundle$recent_history,
    c(
      "market_id", "subject_course", "term_type",
      "projection_target_term", "history_term", "history_term_label",
      "recency_rank", "actual_classlist_total", "actual_first_day",
      "actual_census", "actual_final_enrollment", "capacity_usable",
      "scheduled_sections", "scheduled_capacity", "method_id",
      "prior_classlist_total", "prior_scheduled_capacity",
      "classlist_change", "capacity_change",
      "method_label", "aftcast_method_id", "aftcast_method_label",
      "aftcast_applicable", "aftcast_reason",
      "aftcast_classlist_total", "aftcast_error",
      "aftcast_pct_error", "first_day_fill", "first_day_capacity_gap",
      "capacity_reached",
      "aftcast_capacity_censored", "aftcast_censored_error",
      "aftcast_censored_pct_error", "potential_miss_explanation",
      "source_term", "source_term_label", "prior_source_term",
      "prior_source_term_label", "university_students",
      "prior_university_students", "university_student_change",
      "university_incoming_first_sem",
      "prior_university_incoming_first_sem", "university_incoming_change",
      "market_students", "prior_market_students", "market_student_change",
      "source_outcomes_complete", "source_graded_students",
      "source_dfw_students", "source_dfw_rate",
      "prior_source_dfw_students", "prior_source_dfw_rate",
      "source_dfw_student_change", "source_dfw_rate_change",
      "source_dfw_next_term_repeaters", "source_dfw_repeater_share",
      "movement_context"
    ),
    "validate_enrollment_projection_bundle() recent_history"
  )
  projection_require_columns(
    bundle$candidates,
    c("market_id", "college", "subject_course", "target_term", "method_id",
      "method_role", "projected_classlist_total", "applicable", "selected",
      "first_day_retention_rate", "first_day_retention_n_terms",
      "first_day_retention_terms", "projected_first_day_equivalent",
      "target_term_label", "n_backtests", "backtest_terms",
      "backtest_term_range", "wape", "first_day_equivalent_wape",
      "capacity_censored_wape",
      "uncensored_wape", "raw_projected_classlist_total", "weighted_bias",
      "pct_error_sd", "uncensored_pct_error_sd", "direction_consistency",
      "signed_error_history",
      "n_capacity_censored_misses",
      "capacity_explained_wape", "capacity_explained_error_share",
      "capacity_censored_terms", "capacity_miss_assessment",
      "spine", "spine_term", "saturated_prior", "prior_first_day_fill",
      "waitlisted_prior", "floor_uplift", "floor_basis", "preceding_term",
      "waitlisted_preceding",
      "preceding_term_enrollment", "preceding_term_change", "regime_alarm",
      "delta_repeat", "repeat_rate", "delta_sequence", "sequence_courses",
      "sequence_change", "delta_feeder", "feeder_rate",
      "feeder_courses", "feeder_change", "delta_basis", "projection_formula"),
    "validate_enrollment_projection_bundle() candidates"
  )
  projection_require_columns(
    bundle$delivery_components,
    c("market_id", "campus", "college", "subject_course", "part_term",
      "target_term", "scheduled_sections", "scheduled_capacity",
      "capacity_share"),
    "validate_enrollment_projection_bundle() delivery_components"
  )
  projection_require_columns(
    bundle$method_performance,
    c(
      "market_id", "college", "subject_course", "term_type", "method_id",
      "method_label", "wape", "weighted_bias", "pct_error_sd",
      "uncensored_pct_error_sd",
      "direction_consistency", "signed_error_history",
      "capacity_censored_wape", "first_day_equivalent_wape",
      "n_capacity_censored_misses", "capacity_explained_wape",
      "capacity_explained_error_share", "capacity_censored_terms",
      "capacity_miss_assessment"
    ),
    "validate_enrollment_projection_bundle() method_performance"
  )
  if (nrow(bundle$backtests) > 0) {
    projection_require_columns(
      bundle$backtests,
      c(
        "method_role", "raw_projected_classlist_total",
        "actual_classlist_total", "actual_first_day", "actual_census",
        "actual_final_enrollment",
        "projected_first_day_equivalent", "capacity_fill",
        "capacity_gap", "capacity_reached", "policy_selected",
        "capacity_censored_classlist_projection",
        "capacity_censored_error", "capacity_censored_abs_error",
        "capacity_censored_miss", "capacity_explained_classlist_error",
        "capacity_explained_share", "fold_seat_change", "fold_prior_near_full"
      ),
      "validate_enrollment_projection_bundle() backtests"
    )
  }
  # Each reader-facing axis has its own vocabulary and is checked separately.
  # They are allowed to disagree -- a Stable course with Thin depth and Unrated
  # accuracy is a real and common state -- so a shared check would have to
  # accept every value on every axis and would catch nothing.
  axis_values <- list(
    stability = c("Stable", "Moderate", "Volatile", "Unrated"),
    depth     = c("Deep", "Moderate", "Thin", "None"),
    accuracy  = c("High", "Moderate", "Low", "Unrated"),
    seat_consistency = c("High", "Moderate", "Low", "Unrated")
  )
  for (axis in names(axis_values)) {
    invalid <- setdiff(unique(bundle$projections[[axis]]), axis_values[[axis]])
    if (length(invalid) > 0L) {
      stop(
        "[enrollment-projection-bundle.R] Projection ", axis,
        " contains unsupported values: ",
        paste(invalid, collapse = ", "),
        call. = FALSE
      )
    }
  }

  projection_keys <- c("market_id", "subject_course", "target_term")
  duplicate_projections <- bundle$projections %>%
    dplyr::count(dplyr::across(dplyr::all_of(projection_keys))) %>%
    dplyr::filter(n > 1)
  if (nrow(duplicate_projections) > 0) {
    stop("[enrollment-projection-bundle.R] Projection bundle has duplicate published rows.",
         call. = FALSE)
  }
  duplicate_candidates <- bundle$candidates %>%
    dplyr::count(
      dplyr::across(dplyr::all_of(c(projection_keys, "method_id")))
    ) %>%
    dplyr::filter(n > 1)
  if (nrow(duplicate_candidates) > 0) {
    stop("[enrollment-projection-bundle.R] Projection bundle has duplicate candidates.",
         call. = FALSE)
  }
  validate_spine_rows(
    bundle$candidates, "validate_enrollment_projection_bundle() candidates"
  )
  validate_pressure_bump_rows(
    bundle$projections, bundle$model_config$plan_feeder_seasons,
    "validate_enrollment_projection_bundle() projections"
  )
  if (nrow(bundle$backtests) > 0) {
    validate_spine_rows(
      bundle$backtests, "validate_enrollment_projection_bundle() backtests"
    )
    validate_projection_capacity_rows(
      bundle$backtests,
      "validate_enrollment_projection_bundle() backtests"
    )
  }
  component_keys <- c(
    "market_id", "campus", "college", "subject_course", "part_term",
    "target_term"
  )
  duplicate_components <- bundle$delivery_components %>%
    dplyr::count(dplyr::across(dplyr::all_of(component_keys))) %>%
    dplyr::filter(n > 1)
  if (nrow(duplicate_components) > 0) {
    stop("[enrollment-projection-bundle.R] Projection bundle has duplicate delivery components.",
         call. = FALSE)
  }

  target_term <- as.integer(bundle$target_term)
  projection_targets_match <- all(
    !is.na(bundle$projections$target_term) &
      as.integer(bundle$projections$target_term) == target_term
  )
  candidate_targets_match <- all(
    !is.na(bundle$candidates$target_term) &
      as.integer(bundle$candidates$target_term) == target_term
  )
  component_targets_match <- all(
    !is.na(bundle$delivery_components$target_term) &
      as.integer(bundle$delivery_components$target_term) == target_term
  )
  if (!projection_targets_match || !candidate_targets_match ||
      !component_targets_match) {
    stop("[enrollment-projection-bundle.R] Saved rows do not match the bundle target term.",
         call. = FALSE)
  }
  recent_targets_match <- all(
    !is.na(bundle$recent_history$projection_target_term) &
      as.integer(bundle$recent_history$projection_target_term) == target_term &
      as.integer(bundle$recent_history$history_term) < target_term
  )
  if (!recent_targets_match) {
    stop("[enrollment-projection-bundle.R] Recent history has invalid target terms.",
         call. = FALSE)
  }
  if (nrow(bundle$recent_history) > 0L) {
    recent_starts <- projection_course_history_starts(
      bundle$recent_history$subject_course, bundle$model_config
    )
    if (any(bundle$recent_history$history_term < recent_starts)) {
      stop("[enrollment-projection-bundle.R] Recent history precedes its model window.",
           call. = FALSE)
    }
    recent_duplicates <- bundle$recent_history %>%
      dplyr::count(
        market_id, subject_course, projection_target_term, history_term
      ) %>%
      dplyr::filter(n > 1L)
    if (nrow(recent_duplicates) > 0L) {
      stop("[enrollment-projection-bundle.R] Recent history contains duplicate terms.",
           call. = FALSE)
    }
  }
  # Every campus row belongs to a pooled recent-history term, once.
  projection_require_columns(
    bundle$recent_campus_history,
    names(empty_projection_recent_campus_history()),
    "validate_enrollment_projection_bundle() recent_campus_history"
  )
  campus_terms <- bundle$recent_campus_history %>%
    dplyr::anti_join(
      bundle$recent_history,
      by = c("market_id", "subject_course", "projection_target_term",
             "history_term")
    )
  campus_duplicates <- bundle$recent_campus_history %>%
    dplyr::count(
      market_id, subject_course, projection_target_term, history_term, campus
    ) %>%
    dplyr::filter(n > 1L)
  if (nrow(campus_terms) > 0L || nrow(campus_duplicates) > 0L) {
    stop("[enrollment-projection-bundle.R] Campus history must hold each recent ",
         "history term's campuses once.", call. = FALSE)
  }
  if (nrow(bundle$backtests) > 0L) {
    backtest_starts <- projection_course_history_starts(
      bundle$backtests$subject_course, bundle$model_config
    )
    if (any(bundle$backtests$target_term < backtest_starts)) {
      stop("[enrollment-projection-bundle.R] Aftcasts precede their model window.",
           call. = FALSE)
    }
  }

  # CAMPUS_ROLLUP: reconcile the named market total back to every saved campus
  # and part-term component so the rollup cannot silently lose a delivery.
  component_totals <- bundle$delivery_components %>%
    dplyr::group_by(market_id, subject_course, target_term) %>%
    dplyr::summarise(
      component_sections = sum(scheduled_sections, na.rm = TRUE),
      component_capacity = sum(scheduled_capacity, na.rm = TRUE),
      .groups = "drop"
    )
  capacity_audit <- bundle$pressure_screen %>%
    dplyr::select(
      market_id, subject_course, target_term,
      scheduled_sections, scheduled_capacity
    ) %>%
    dplyr::left_join(
      component_totals,
      by = c("market_id", "subject_course", "target_term")
    ) %>%
    dplyr::mutate(
      component_sections = dplyr::coalesce(component_sections, 0),
      component_capacity = dplyr::coalesce(component_capacity, 0)
    ) %>%
    dplyr::filter(
      scheduled_sections != component_sections |
        abs(scheduled_capacity - component_capacity) > 1e-8
    )
  if (nrow(capacity_audit) > 0) {
    stop("[enrollment-projection-bundle.R] Delivery components do not reconcile to market capacity.",
         call. = FALSE)
  }

  expected_selected <- bundle$projections %>%
    dplyr::filter(method_id != "none") %>%
    dplyr::select(dplyr::all_of(projection_keys), method_id)
  actual_selected <- bundle$candidates %>%
    dplyr::filter(!is.na(selected), selected) %>%
    dplyr::select(dplyr::all_of(projection_keys), method_id)
  missing_selected <- dplyr::anti_join(
    expected_selected, actual_selected,
    by = c(projection_keys, "method_id")
  )
  unexpected_selected <- dplyr::anti_join(
    actual_selected, expected_selected,
    by = c(projection_keys, "method_id")
  )
  if (nrow(missing_selected) > 0 || nrow(unexpected_selected) > 0) {
    stop("[enrollment-projection-bundle.R] Published methods and selected candidates disagree.",
         call. = FALSE)
  }
  numeric_audit <- bundle$projections %>%
    dplyr::filter(method_id != "none") %>%
    dplyr::select(
      dplyr::all_of(projection_keys), method_id,
      published_projection = projected_classlist_total,
      published_raw = raw_projected_classlist_total
    ) %>%
    dplyr::inner_join(
      bundle$candidates %>%
        dplyr::filter(!is.na(selected), selected) %>%
        dplyr::select(
          dplyr::all_of(projection_keys), method_id,
          candidate_raw = raw_projected_classlist_total
        ),
      by = c(projection_keys, "method_id")
    ) %>%
    dplyr::mutate(
      rounded_matches =
        (is.na(published_projection) & is.na(candidate_raw)) |
        dplyr::near(published_projection, round(candidate_raw), tol = 1e-8),
      raw_matches =
        (is.na(published_raw) & is.na(candidate_raw)) |
        dplyr::near(published_raw, candidate_raw, tol = 1e-8)
    ) %>%
    dplyr::filter(
      !dplyr::coalesce(rounded_matches, FALSE) |
        !dplyr::coalesce(raw_matches, FALSE)
    )
  if (nrow(numeric_audit) > 0L) {
    stop(
      "[enrollment-projection-bundle.R] Published projection values and selected candidates disagree.",
      call. = FALSE
    )
  }
  invisible(TRUE)
}


write_enrollment_projection_bundle <- function(bundle, path) {
  validate_enrollment_projection_bundle(bundle)
  dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
  tmp_path <- paste0(path, ".tmp")
  if (grepl("\\.qs$", path, ignore.case = TRUE)) {
    qs2::qs_save(bundle, tmp_path)
  } else if (grepl("\\.Rds$", path, ignore.case = TRUE)) {
    saveRDS(bundle, tmp_path)
  } else {
    stop("[enrollment-projection-bundle.R] Bundle path must end in .qs or .Rds.",
         call. = FALSE)
  }
  if (!file.rename(tmp_path, path)) {
    stop("[enrollment-projection-bundle.R] Could not atomically publish bundle: ", path,
         call. = FALSE)
  }
  invisible(path)
}


read_enrollment_projection_bundle <- function(path) {
  if (!file.exists(path)) {
    stop("[enrollment-projection-bundle.R] Projection bundle not found: ", path,
         call. = FALSE)
  }
  bundle <- if (grepl("\\.qs$", path, ignore.case = TRUE)) {
    qs2::qs_read(path)
  } else if (grepl("\\.Rds$", path, ignore.case = TRUE)) {
    readRDS(path)
  } else {
    stop("[enrollment-projection-bundle.R] Bundle path must end in .qs or .Rds.",
         call. = FALSE)
  }
  validate_enrollment_projection_bundle(bundle)
  bundle
}
