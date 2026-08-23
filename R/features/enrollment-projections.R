# App- and script-facing enrollment projection orchestration.
#
# The same builder is used by the persistent R lab, the standalone publisher,
# and future CEDAR tabs. UI code should consume its saved bundle, not reproduce
# any calculation here.

projection_table_fingerprint <- function(data) {
  if (is.null(data)) return(list(status = "missing"))
  # Term extrema describe the saved source only; they never bound an analysis.
  terms <- if ("term" %in% names(data)) {
    suppressWarnings(as.integer(as.character(data$term)))
  } else {
    integer(0)
  }
  terms <- terms[!is.na(terms)]
  as_of <- if ("as_of_date" %in% names(data)) {
    values <- as.Date(data$as_of_date)
    values <- values[!is.na(values)]
    if (length(values) == 0) NA_character_ else as.character(max(values))
  } else {
    NA_character_
  }
  term_counts <- if (length(terms) == 0) integer(0) else sort(table(terms))

  list(
    rows = nrow(data),
    columns = ncol(data),
    first_term = if (length(terms) == 0) NA_integer_ else min(terms, na.rm = TRUE),
    last_term = if (length(terms) == 0) NA_integer_ else max(terms, na.rm = TRUE),
    as_of_date = as_of,
    signature = substr(
      digest::digest(list(dim(data), names(data), term_counts, as_of)), 1, 16
    )
  )
}


enrollment_projection_model_source_files <- function() {
  c(
    "R/lists/enrollment_projection_groups.R",
    "R/lists/status_codes.R",
    "R/lists/campuses.R",
    "R/lists/gen_ed_courses.R",
    "R/trunk/utils.R",
    "R/branches/enrl.R",
    "R/branches/enrollment-projections.R",
    "R/cones/enrollment-projections.R",
    "R/features/enrollment-projections.R",
    "scripts/build-enrollment-projections.R"
  )
}


find_enrollment_projection_repo_root <- function(path = getwd()) {
  root <- normalizePath(path, mustWork = TRUE)
  while (!file.exists(file.path(root, "global.R")) && dirname(root) != root) {
    root <- dirname(root)
  }
  if (!file.exists(file.path(root, "global.R"))) {
    stop(
      "[enrollment-projections.R] Could not find the CEDAR repository root.",
      call. = FALSE
    )
  }
  root
}


capture_enrollment_projection_git <- function(root, args) {
  output <- tryCatch(
    suppressWarnings(system2(
      "git", c("-C", shQuote(root), args), stdout = TRUE, stderr = TRUE
    )),
    error = function(error) structure(character(0), status = 1L)
  )
  status <- attr(output, "status")
  if (!is.null(status) && status != 0L) return(NULL)
  output
}


enrollment_projection_model_provenance <- function(base_dir = getwd()) {
  root <- find_enrollment_projection_repo_root(base_dir)
  source_files <- enrollment_projection_model_source_files()
  source_paths <- file.path(root, source_files)
  missing <- source_files[!file.exists(source_paths)]
  if (length(missing) > 0L) {
    stop(
      "[enrollment-projections.R] Model source is missing: ",
      paste(missing, collapse = ", "),
      call. = FALSE
    )
  }

  source_snapshot <- stats::setNames(vapply(source_paths, function(path) {
    paste(readLines(path, warn = FALSE, encoding = "UTF-8"), collapse = "\n")
  }, character(1)), source_files)
  source_hashes <- vapply(
    source_snapshot,
    digest::digest,
    character(1),
    algo = "sha256",
    serialize = FALSE,
    USE.NAMES = TRUE
  )
  commit <- capture_enrollment_projection_git(root, c("rev-parse", "HEAD"))
  worktree <- capture_enrollment_projection_git(
    root, c("status", "--porcelain", "--", source_files)
  )

  list(
    model_version = CEDAR_ENROLLMENT_PROJECTION_MODEL_VERSION,
    schema_version = CEDAR_ENROLLMENT_PROJECTION_SCHEMA_VERSION,
    git_commit = if (length(commit) == 1L && grepl("^[0-9a-f]{40}$", commit)) {
      commit
    } else {
      NA_character_
    },
    relevant_worktree_dirty = if (is.null(worktree)) NA else length(worktree) > 0L,
    source_hashes = source_hashes,
    source_snapshot = source_snapshot
  )
}


enrollment_projection_model_source <- function(bundle, path = NULL) {
  if (is.character(bundle) && length(bundle) == 1L && file.exists(bundle)) {
    bundle <- if (grepl("\\.qs$", bundle, ignore.case = TRUE)) {
      qs2::qs_read(bundle)
    } else if (grepl("\\.Rds$", bundle, ignore.case = TRUE)) {
      readRDS(bundle)
    } else {
      stop(
        "[enrollment-projections.R] Bundle path must end in .qs or .Rds.",
        call. = FALSE
      )
    }
  }
  if (!is.list(bundle) ||
      !all(c("model_version", "schema_version", "model_provenance") %in%
             names(bundle))) {
    stop(
      "[enrollment-projections.R] A projection bundle or bundle path is required.",
      call. = FALSE
    )
  }
  validate_enrollment_projection_model_provenance(
    bundle$model_provenance,
    model_version = bundle$model_version,
    schema_version = bundle$schema_version
  )
  provenance <- bundle$model_provenance
  if (is.null(path)) {
    return(tibble::tibble(
      path = names(provenance$source_hashes),
      sha256 = unname(provenance$source_hashes)
    ))
  }
  path <- as.character(path)
  if (length(path) != 1L || is.na(path) ||
      !path %in% names(provenance$source_snapshot)) {
    stop(
      "[enrollment-projections.R] Unknown saved model source path: ",
      paste(path, collapse = ", "),
      call. = FALSE
    )
  }
  unname(provenance$source_snapshot[[path]])
}


build_enrollment_projection_bundle <- function(cl_enrls, sections, students,
                                               target_term, as_of_term,
                                               scope_courses,
                                               scope_campuses,
                                               scope_market_id,
                                               force_courses = NULL,
                                               opt = list(),
                                               built_at = Sys.time()) {
  if (is.null(target_term) || length(target_term) != 1 || is.na(target_term)) {
    stop("[enrollment-projections.R] One explicit target_term is required.",
         call. = FALSE)
  }
  if (is.null(as_of_term) || length(as_of_term) != 1 || is.na(as_of_term)) {
    stop("[enrollment-projections.R] One explicit as_of_term is required.",
         call. = FALSE)
  }
  if (is.null(scope_courses) || length(scope_courses) == 0) {
    stop("[enrollment-projections.R] scope_courses is required.", call. = FALSE)
  }
  if (is.null(scope_campuses) || length(scope_campuses) == 0) {
    stop("[enrollment-projections.R] scope_campuses is required.", call. = FALSE)
  }
  if (is.null(scope_market_id) || length(scope_market_id) != 1L ||
      is.na(scope_market_id) || !nzchar(scope_market_id)) {
    stop("[enrollment-projections.R] scope_market_id is required.", call. = FALSE)
  }
  target_term <- as.integer(target_term)
  as_of_term <- as.integer(as_of_term)
  if (as_of_term >= target_term) {
    stop("[enrollment-projections.R] as_of_term must precede target_term.",
         call. = FALSE)
  }
  opt <- enrollment_projection_model_config(opt)

  inputs <- prepare_enrollment_projection_inputs(
    cl_enrls = cl_enrls,
    sections = sections,
    students = students,
    target_courses = scope_courses,
    target_campuses = scope_campuses,
    target_market_id = scope_market_id,
    enrollment_through_term = as_of_term,
    section_through_term = target_term,
    history_start_term = opt$history_start_term,
    course_history_start_terms = opt$course_history_start_terms
  )
  analysis <- get_course_enrollment_projections(
    inputs,
    target_term = target_term,
    scope_courses = scope_courses,
    force_courses = force_courses,
    opt = opt
  )

  new_enrollment_projection_bundle(
    analysis,
    target_term = target_term,
    as_of_term = as_of_term,
    scope_courses = scope_courses,
    scope_campuses = scope_campuses,
    scope_market_id = scope_market_id,
    model_provenance = enrollment_projection_model_provenance(),
    model_config = opt,
    source_fingerprint = list(
      classlist_enrollments = projection_table_fingerprint(cl_enrls),
      sections = projection_table_fingerprint(sections),
      students = projection_table_fingerprint(students)
    ),
    built_at = built_at
  )
}


find_latest_enrollment_projection_bundle <- function(
    output_dir = file.path(getwd(), "output", "projections")) {
  if (!dir.exists(output_dir)) return(NULL)
  paths <- list.files(
    output_dir,
    pattern = "^enrollment-projections-[0-9]{6}-latest\\.(qs|Rds)$",
    full.names = TRUE
  )
  if (length(paths) == 0L) return(NULL)
  target_terms <- suppressWarnings(as.integer(sub(
    "^enrollment-projections-([0-9]{6})-latest\\.(qs|Rds)$",
    "\\1", basename(paths)
  )))
  paths[[order(target_terms, file.info(paths)$mtime, decreasing = TRUE)[[1]]]]
}


load_latest_enrollment_projection_bundle <- function(
    output_dir = file.path(getwd(), "output", "projections")) {
  path <- find_latest_enrollment_projection_bundle(output_dir)
  if (is.null(path)) return(NULL)
  bundle <- read_enrollment_projection_bundle(path)
  attr(bundle, "bundle_path") <- normalizePath(path, mustWork = TRUE)
  bundle
}


enrollment_projection_group_choices <- function() {
  c(
    "All saved projections" = "all_saved",
    "Always monitored" = "always_monitored",
    "General Education" = "general_education"
  )
}


enrollment_projection_group_courses <- function(bundle, group_id) {
  switch(
    as.character(group_id %||% "all_saved"),
    all_saved = bundle$scope_courses,
    always_monitored = intersect(
      bundle$scope_courses,
      CEDAR_ENROLLMENT_PROJECTION_ALWAYS_MONITORED_COURSES
    ),
    general_education = intersect(
      bundle$scope_courses,
      unlist(gen_ed_all, use.names = FALSE)
    ),
    stop(
      "[enrollment-projections.R] Unknown projection display group: ",
      group_id, call. = FALSE
    )
  )
}


projection_confidence_explanation <- function(confidence, n_backtests, wape,
                                              coverage_rate = NA_real_,
                                              term_type = NA_character_,
                                              selection_basis = "All-term WAPE",
                                              pct_error_sd = NA_real_,
                                              capacity_constrained = FALSE,
                                              selection_uses_uncensored = FALSE,
                                              n_capacity_reached = NA_integer_,
                                              n_capacity_unreached = NA_integer_,
                                              method_role = NA_character_,
                                              methods_disagree = FALSE) {
  size <- max(
    length(confidence), length(n_backtests), length(wape),
    length(coverage_rate), length(term_type), length(selection_basis),
    length(pct_error_sd),
    length(capacity_constrained), length(selection_uses_uncensored),
    length(n_capacity_reached), length(n_capacity_unreached),
    length(method_role), length(methods_disagree)
  )
  confidence <- rep_len(as.character(confidence), size)
  n_backtests <- rep_len(as.integer(n_backtests), size)
  wape <- rep_len(as.numeric(wape), size)
  coverage_rate <- rep_len(as.numeric(coverage_rate), size)
  term_type <- rep_len(as.character(term_type), size)
  selection_basis <- rep_len(as.character(selection_basis), size)
  pct_error_sd <- rep_len(as.numeric(pct_error_sd), size)
  capacity_constrained <- rep_len(as.logical(capacity_constrained), size)
  selection_uses_uncensored <- rep_len(
    as.logical(selection_uses_uncensored), size
  )
  n_capacity_reached <- rep_len(as.integer(n_capacity_reached), size)
  n_capacity_unreached <- rep_len(as.integer(n_capacity_unreached), size)
  method_role <- rep_len(as.character(method_role), size)
  methods_disagree <- rep_len(as.logical(methods_disagree), size)

  vapply(seq_len(size), function(i) {
    level <- confidence[[i]]
    n <- dplyr::coalesce(n_backtests[[i]], 0L)
    error <- wape[[i]]
    coverage <- coverage_rate[[i]]
    variation <- pct_error_sd[[i]]
    basis <- selection_basis[[i]]
    basis_suffix <- if (identical(basis, "Unconstrained-term WAPE")) {
      "WAPE (unconstrained terms)"
    } else {
      "WAPE (all terms)"
    }
    season <- switch(
      term_type[[i]], spring = "Spring", summer = "Summer", fall = "Fall",
      "same-term-type"
    )
    evidence <- if (n > 0L && is.finite(error)) {
      paste0(
        n, " comparable ", season, " aftcast", if (n == 1L) "" else "s",
        " at ", scales::percent(error, accuracy = 0.1), " ",
        basis_suffix,
        if (is.finite(variation)) paste0(
          ", with ", scales::percent(variation, accuracy = 0.1),
          " term-to-term error variation"
        ) else "",
        ". "
      )
    } else if (n > 0L) {
      paste0(n, " comparable ", season, " aftcast", if (n == 1L) "" else "s", ". ")
    } else {
      paste0("No comparable ", season, " aftcasts. ")
    }

    rating_reason <- if (identical(level, "High")) {
      paste(
        "High requires at least 4 aftcasts, WAPE no greater than 10%,",
        "and error variation no greater than 10%."
      )
    } else if (identical(level, "Medium")) {
      paste(
        "Medium clears the 3-aftcast, 15% WAPE and 15% variation rule;",
        "High requires 4 aftcasts with both measures no greater than 10%."
      )
    } else if (identical(level, "Low")) {
      reason <- if (n < 3L) {
        "Accuracy may be strong, but Medium requires 3 aftcasts and High requires 4."
      } else if (is.finite(error) && error > 0.15) {
        "The error clears the 20% Low ceiling but exceeds the 15% Medium ceiling."
      } else if (is.finite(variation) && variation > 0.15) {
        "Error variation clears the 20% Low ceiling but exceeds the 15% Medium ceiling."
      } else {
        "It meets the Low rule but not the stronger evidence rules above it."
      }
      reason
    } else {
      if (n < 2L) {
        "At least 2 comparable aftcasts are required for any confidence rating."
      } else if (!is.finite(error)) {
        "There is no measurable historical WAPE."
      } else if (error > 0.20) {
        paste0(
          "WAPE exceeds the 20% ceiling for a Low rating by ",
          scales::percent(error - 0.20, accuracy = 0.1), "."
        )
      } else if (!is.finite(variation)) {
        "Term-to-term error consistency cannot be measured."
      } else if (variation > 0.20) {
        paste0(
          "Term-to-term error variation is ",
          scales::percent(variation, accuracy = 0.1),
          ", above the 20% ceiling for a Low rating."
        )
      } else {
        "The selected method does not clear the minimum confidence rule."
      }
    }

    caveats <- character(0)
    if (isTRUE(capacity_constrained[[i]])) {
      reached <- dplyr::coalesce(n_capacity_reached[[i]], 0L)
      unreached <- dplyr::coalesce(n_capacity_unreached[[i]], 0L)
      caveats <- c(caveats, if (isTRUE(selection_uses_uncensored[[i]])) {
        paste0(
          "Capacity caveat: ", reached,
          " capacity-reached term(s) are excluded from this accuracy basis; ",
          unreached, " unconstrained term(s) determine it."
        )
      } else {
        paste0(
          "Capacity caveat: ", reached, " of ", reached + unreached,
          " capacity-observed aftcast term(s) reached the registration ceiling. ",
          "The rating describes fit to observed enrollment, not proof of ",
          "unconstrained demand."
        )
      })
    }
    if (identical(method_role[[i]], "anchored_upstream")) {
      coverage_text <- if (is.finite(coverage)) paste0(
        " with ", scales::percent(coverage, accuracy = 0.1),
        " source coverage"
      ) else ""
      caveats <- c(caveats, paste0(
        "Upstream caveat: the selected method applies an observed upstream ",
        "population change", coverage_text,
        "; this is an observational planning relationship, not a causal estimate."
      ))
    }
    if (isTRUE(methods_disagree[[i]])) {
      caveats <- c(caveats, paste(
        "Method caveat: candidate projections differ materially, so method",
        "choice remains important."
      ))
    }
    paste(c(trimws(evidence), rating_reason, caveats), collapse = " ")
  }, character(1))
}


projection_confidence_brief <- function(n_backtests, pct_error_sd,
                                        capacity_constrained = FALSE,
                                        methods_disagree = FALSE,
                                        method_role = NA_character_,
                                        coverage_rate = NA_real_) {
  size <- max(
    length(n_backtests), length(pct_error_sd),
    length(capacity_constrained), length(methods_disagree),
    length(method_role), length(coverage_rate)
  )
  n_backtests <- rep_len(as.integer(n_backtests), size)
  pct_error_sd <- rep_len(as.numeric(pct_error_sd), size)
  capacity_constrained <- rep_len(as.logical(capacity_constrained), size)
  methods_disagree <- rep_len(as.logical(methods_disagree), size)
  method_role <- rep_len(as.character(method_role), size)
  coverage_rate <- rep_len(as.numeric(coverage_rate), size)

  vapply(seq_len(size), function(i) {
    n <- dplyr::coalesce(n_backtests[[i]], 0L)
    variation <- pct_error_sd[[i]]
    volume <- if (n == 0L) "No comparable terms" else paste(n, "terms")
    stability <- dplyr::case_when(
      !is.finite(variation) ~ "consistency unavailable",
      variation <= 0.10 ~ "consistent errors",
      variation <= 0.20 ~ "moderate variation",
      TRUE ~ "variable errors"
    )
    qualifier <- dplyr::case_when(
      isTRUE(capacity_constrained[[i]]) ~ "capacity-limited",
      isTRUE(methods_disagree[[i]]) ~ "methods differ",
      identical(method_role[[i]], "anchored_upstream") &&
        is.finite(coverage_rate[[i]]) && coverage_rate[[i]] < 0.60 ~
        "limited upstream coverage",
      TRUE ~ NA_character_
    )
    paste(c(volume, stability, qualifier)[
      !is.na(c(volume, stability, qualifier))
    ], collapse = " · ")
  }, character(1))
}


build_enrollment_projection_view <- function(bundle, opt = list()) {
  validate_enrollment_projection_bundle(bundle)
  group_id <- as.character(opt$group_id %||% "all_saved")[[1]]
  group_courses <- enrollment_projection_group_courses(bundle, group_id)
  departments <- as.character(opt$departments %||% character(0))
  departments <- departments[!is.na(departments) & nzchar(departments)]
  courses <- as.character(opt$courses %||% character(0))
  courses <- courses[!is.na(courses) & nzchar(courses)]
  confidence <- as.character(opt$confidence %||% character(0))
  confidence <- confidence[!is.na(confidence) & nzchar(confidence)]
  min_calibration_validation <- as.integer(
    bundle$model_config$calibration_min_validation_terms %||% 2L
  )

  projections <- bundle$projections %>%
    dplyr::filter(subject_course %in% .env$group_courses)
  if (!"coverage_rate" %in% names(projections)) {
    projections$coverage_rate <- rep(NA_real_, nrow(projections))
  }
  if (!"selection_pct_error_sd" %in% names(projections)) {
    projections$selection_pct_error_sd <- rep(NA_real_, nrow(projections))
  }
  if (!"n_capacity_reached" %in% names(projections)) {
    projections$n_capacity_reached <- rep(NA_integer_, nrow(projections))
  }
  if (!"method_role" %in% names(projections)) {
    projections$method_role <- rep(NA_character_, nrow(projections))
  }
  if (!"methods_disagree" %in% names(projections)) {
    projections$methods_disagree <- rep(FALSE, nrow(projections))
  }
  if (length(departments) > 0L) {
    projections <- dplyr::filter(
      projections, department %in% .env$departments
    )
  }
  if (length(courses) > 0L) {
    projections <- dplyr::filter(
      projections, subject_course %in% .env$courses
    )
  }
  if (length(confidence) > 0L) {
    projections <- dplyr::filter(
      projections, confidence %in% .env$confidence
    )
  }
  projections <- projections %>%
    dplyr::arrange(department, subject_course) %>%
    dplyr::mutate(
      bias_correction = projection_preview_bias_correction(
        applied = dplyr::coalesce(calibration_applied, FALSE),
        factor = calibration_factor,
        adjustment = calibration_adjustment,
        candidate = dplyr::coalesce(calibration_candidate, FALSE),
        n_validation = n_calibrated_backtests,
        reason = calibration_reason,
        n_backtests = n_backtests,
        min_validation = .env$min_calibration_validation
      ),
      aftcast_accuracy = dplyr::case_when(
        dplyr::coalesce(selection_n_backtests, 0L) == 0L ~ "No aftcasts",
        TRUE ~ paste0(
          selection_n_backtests, " at ",
          projection_preview_percent(selection_wape), " ",
          dplyr::if_else(
            selection_uses_uncensored, "uncensored WAPE", "all-term WAPE"
          )
        )
      ),
      confidence_explanation = projection_confidence_explanation(
        confidence, selection_n_backtests, selection_wape, coverage_rate,
        term_type, selection_basis, selection_pct_error_sd,
        capacity_constrained_history, selection_uses_uncensored,
        n_capacity_reached, n_capacity_unreached, method_role,
        methods_disagree
      ),
      confidence_brief = projection_confidence_brief(
        selection_n_backtests, selection_pct_error_sd,
        capacity_constrained_history, methods_disagree, method_role,
        coverage_rate
      )
    )
  selected_keys <- projections %>%
    dplyr::select(market_id, subject_course, term_type, target_term)
  history <- bundle$recent_history %>%
    dplyr::semi_join(
      selected_keys,
      by = c(
        "market_id", "subject_course",
        "projection_target_term" = "target_term"
      )
    ) %>%
    dplyr::arrange(subject_course, recency_rank)
  candidates <- bundle$candidates %>%
    dplyr::semi_join(
      selected_keys,
      by = c("market_id", "subject_course", "target_term")
    ) %>%
    dplyr::arrange(subject_course, method_role, method_id)
  method_history <- if (nrow(bundle$backtests) == 0L) {
    bundle$backtests
  } else {
    bundle$backtests %>%
      dplyr::semi_join(
        selected_keys,
        by = c("market_id", "subject_course", "term_type")
      ) %>%
      dplyr::arrange(subject_course, target_term, method_id)
  }

  table <- projections %>%
    dplyr::transmute(
      course = subject_course,
      department,
      projected_demand = projected_classlist_total,
      expected_census = projected_census_equivalent,
      method = method_label,
      aftcast_accuracy,
      confidence,
      confidence_reason,
      confidence_brief,
      confidence_explanation,
      bias_correction,
      coupling = coupling_status,
      coupling_reason,
      demand_signal,
      recommendation,
      why_uncertain
    )

  list(
    meta = list(
      target_term = bundle$target_term,
      target_term_label = fmt_term(bundle$target_term),
      as_of_term = bundle$as_of_term,
      as_of_term_label = fmt_term(bundle$as_of_term),
      history_start_term = bundle$model_config$history_start_term,
      history_start_term_label = fmt_term(bundle$model_config$history_start_term),
      built_at = bundle$built_at,
      model_version = bundle$model_version,
      model_provenance = bundle$model_provenance,
      market_id = bundle$scope_market_id,
      campuses = bundle$scope_campuses,
      group_id = group_id,
      n_rows = nrow(projections),
      bundle_path = attr(bundle, "bundle_path") %||% NA_character_
    ),
    projections = projections,
    table = table,
    history = history,
    candidates = candidates,
    method_history = method_history
  )
}


enrollment_projection_filter_choices <- function(bundle, opt = list()) {
  scoped <- build_enrollment_projection_view(
    bundle,
    utils::modifyList(opt, list(courses = character(0), confidence = character(0)))
  )$projections
  list(
    groups = enrollment_projection_group_choices(),
    departments = sort(unique(stats::na.omit(scoped$department))),
    courses = sort(unique(stats::na.omit(scoped$subject_course))),
    confidence = c("High", "Medium", "Low", "None")
  )
}


enrollment_projection_course_detail <- function(view, subject_course) {
  course <- as.character(subject_course %||% character(0))
  if (length(course) != 1L || is.na(course) || !nzchar(course)) return(NULL)
  current <- view$projections %>%
    dplyr::filter(subject_course == .env$course) %>%
    dplyr::slice_head(n = 1)
  if (nrow(current) == 0L) return(NULL)
  list(
    current = current,
    history = view$history %>%
      dplyr::filter(subject_course == .env$course) %>%
      dplyr::arrange(recency_rank),
    candidates = view$candidates %>%
      dplyr::filter(subject_course == .env$course),
    method_history = if (nrow(view$method_history) == 0L) {
      view$method_history
    } else {
      view$method_history %>%
        dplyr::filter(subject_course == .env$course) %>%
        dplyr::arrange(target_term, method_id)
    }
  )
}


build_enrollment_projection_method_history_plot <- function(
    method_history, selected_method_id = NULL) {
  required <- c(
    "subject_course", "term_type", "method_id", "method_label", "target_term",
    "applicable", "raw_projected_classlist_total", "actual_classlist_total",
    "actual_census", "actual_final_enrollment"
  )
  missing <- setdiff(required, names(method_history))
  if (length(missing) > 0L) {
    stop(
      "[enrollment-projections.R] Historical-method plot needs column(s): ",
      paste(missing, collapse = ", "), call. = FALSE
    )
  }
  if (nrow(method_history) == 0L) return(NULL)

  term_types <- unique(stats::na.omit(as.character(method_history$term_type)))
  if (length(term_types) != 1L) {
    stop(
      "[enrollment-projections.R] Historical-method plot must contain one term type.",
      call. = FALSE
    )
  }
  term_order <- method_history %>%
    dplyr::distinct(target_term) %>%
    dplyr::arrange(target_term) %>%
    dplyr::pull(target_term)
  term_labels <- stats::setNames(
    vapply(term_order, fmt_term, character(1)), as.character(term_order)
  )
  actuals <- method_history %>%
    dplyr::distinct(
      target_term, actual_classlist_total, actual_census,
      actual_final_enrollment
    ) %>%
    dplyr::arrange(target_term)
  methods <- method_history %>%
    dplyr::filter(
      applicable, is.finite(raw_projected_classlist_total),
      method_id %in% names(CEDAR_ENROLLMENT_PROJECTION_METHODS)
    ) %>%
    dplyr::arrange(target_term, method_id)

  plot <- plotly::plot_ly()
  actual_specs <- list(
    list(
      label = "First day / ever registered (model target)",
      column = "actual_classlist_total", color = unname(CEDAR_COLORS["green_dark"]),
      width = 4L, symbol = "circle"
    ),
    list(
      label = "Census", column = "actual_census",
      color = unname(CEDAR_COLORS["blue"]), width = 3L, symbol = "diamond"
    ),
    list(
      label = "Final / last day", column = "actual_final_enrollment",
      color = unname(CEDAR_COLORS["neutral"]), width = 3L, symbol = "square"
    )
  )
  for (spec in actual_specs) {
    values <- actuals[[spec$column]]
    plot <- plotly::add_trace(
      plot,
      x = unname(term_labels[as.character(actuals$target_term)]),
      y = values,
      type = "scatter", mode = "lines+markers", name = spec$label,
      legendgroup = "actual",
      line = list(color = spec$color, width = spec$width),
      marker = list(color = spec$color, size = 8, symbol = spec$symbol),
      text = paste0(
        spec$label, "<br>",
        unname(term_labels[as.character(actuals$target_term)]),
        "<br>Enrollment: ", round(values)
      ),
      hovertemplate = "%{text}<extra></extra>"
    )
  }

  method_ids <- intersect(
    names(CEDAR_ENROLLMENT_PROJECTION_METHODS), unique(methods$method_id)
  )
  method_colors <- cedar_plotly_palette(
    method_ids, label_order = names(CEDAR_ENROLLMENT_PROJECTION_METHODS)
  )
  selected_method_id <- as.character(selected_method_id %||% NA_character_)[[1]]
  for (method in method_ids) {
    values <- methods %>% dplyr::filter(method_id == .env$method)
    selected <- identical(method, selected_method_id)
    label <- unique(values$method_label)[[1]]
    plot <- plotly::add_trace(
      plot,
      x = unname(term_labels[as.character(values$target_term)]),
      y = values$raw_projected_classlist_total,
      type = "scatter", mode = "lines+markers",
      name = paste0(label, if (selected) " (selected)" else ""),
      legendgroup = "methods",
      line = list(
        color = unname(method_colors[[method]]),
        width = if (selected) 3L else 1.5,
        dash = if (selected) "dash" else "dot"
      ),
      marker = list(
        color = unname(method_colors[[method]]),
        size = if (selected) 7 else 5
      ),
      opacity = if (selected) 1 else 0.78,
      text = paste0(
        label, if (selected) " (selected)" else "", "<br>",
        unname(term_labels[as.character(values$target_term)]),
        "<br>Raw aftcast: ", round(values$raw_projected_classlist_total)
      ),
      hovertemplate = "%{text}<extra></extra>"
    )
  }

  season <- switch(
    term_types[[1]], spring = "Spring", summer = "Summer", fall = "Fall",
    term_types[[1]]
  )
  plot %>%
    plotly::layout(
      xaxis = list(
        title = "",
        categoryorder = "array",
        categoryarray = unname(term_labels),
        tickangle = -30
      ),
      yaxis = list(title = "Students", rangemode = "tozero"),
      legend = list(orientation = "h", x = 0, y = -0.28),
      margin = list(t = 20, r = 20, b = 125, l = 65),
      hovermode = "x unified",
      annotations = list(list(
        text = paste0(season, " terms only"),
        showarrow = FALSE, xref = "paper", yref = "paper",
        x = 1, y = 1.06, xanchor = "right",
        font = list(size = 12, color = unname(CEDAR_COLORS["text"]))
      ))
    ) %>%
    plotly::config(displaylogo = FALSE)
}


projection_preview_integer <- function(x) {
  ifelse(
    is.finite(x),
    format(round(x), big.mark = ",", scientific = FALSE, trim = TRUE),
    "--"
  )
}


projection_preview_percent <- function(x, signed = FALSE) {
  output <- rep("--", length(x))
  keep <- is.finite(x)
  format_string <- if (isTRUE(signed)) "%+.1f%%" else "%.1f%%"
  output[keep] <- sprintf(format_string, 100 * x[keep])
  output
}


projection_preview_bias_correction <- function(
  applied, factor, adjustment, candidate, n_validation, reason, n_backtests,
  min_validation = 2L
) {
  vapply(seq_along(applied), function(i) {
    if (isTRUE(applied[[i]])) {
      rounded_adjustment <- as.integer(round(adjustment[[i]]))
      student_label <- if (abs(rounded_adjustment) == 1L) "student" else "students"
      return(paste0(
        "Applied x", format(round(factor[[i]], 3), nsmall = 3),
        " (", sprintf("%+d", rounded_adjustment), " ", student_label, ")"
      ))
    }

    validation_n <- n_validation[[i]]
    if (isTRUE(candidate[[i]]) && is.finite(validation_n) &&
        validation_n < min_validation) {
      return(paste0(
        "Pending validation: ", validation_n, "/", min_validation, " trials"
      ))
    }

    row_reason <- reason[[i]]
    if (!is.na(row_reason) && nzchar(row_reason)) {
      row_reason <- paste0(
        tolower(substr(row_reason, 1L, 1L)), substr(row_reason, 2L, nchar(row_reason))
      )
      return(paste0("Not applied: ", row_reason))
    }
    if (!is.finite(n_backtests[[i]]) || n_backtests[[i]] == 0L) {
      return("Not assessed: no eligible aftcasts")
    }
    "Not applied: no validated correction"
  }, character(1))
}


projection_preview_markdown_table <- function(data, right_align = character()) {
  if (nrow(data) == 0L) return(character(0))
  cells <- lapply(data, function(x) {
    value <- as.character(x)
    value[is.na(value) | !nzchar(value)] <- "--"
    gsub("|", "\\|", value, fixed = TRUE)
  })
  headers <- names(data)
  widths <- vapply(seq_along(headers), function(i) {
    max(nchar(c(headers[[i]], cells[[i]])), na.rm = TRUE)
  }, integer(1))
  row_line <- function(values) {
    padded <- vapply(seq_along(values), function(i) {
      if (headers[[i]] %in% right_align) {
        sprintf(paste0("%", widths[[i]], "s"), values[[i]])
      } else {
        sprintf(paste0("%-", widths[[i]], "s"), values[[i]])
      }
    }, character(1))
    paste0("| ", paste(padded, collapse = " | "), " |")
  }
  separator <- vapply(seq_along(headers), function(i) {
    width <- max(3L, widths[[i]])
    if (headers[[i]] %in% right_align) {
      paste0(paste(rep("-", width - 1L), collapse = ""), ":")
    } else {
      paste(rep("-", width), collapse = "")
    }
  }, character(1))
  rows <- if (nrow(data) == 0L) character(0) else
    vapply(seq_len(nrow(data)), function(i) {
      row_line(vapply(cells, `[[`, character(1), i))
    }, character(1))
  c(row_line(headers), row_line(separator), rows)
}


format_enrollment_projection_preview <- function(bundle, courses = NULL) {
  validate_enrollment_projection_bundle(bundle)
  min_calibration_validation <- as.integer(
    bundle$model_config$calibration_min_validation_terms %||% 2L
  )
  selected_courses <- if (is.null(courses)) {
    bundle$projections$subject_course
  } else {
    unique(as.character(courses))
  }
  projections <- bundle$projections %>%
    dplyr::filter(subject_course %in% .env$selected_courses) %>%
    dplyr::arrange(subject_course)
  history <- bundle$recent_history %>%
    dplyr::filter(subject_course %in% .env$selected_courses) %>%
    dplyr::arrange(subject_course, recency_rank)

  current_table <- projections %>%
    dplyr::transmute(
      Course = subject_course,
      Target = target_term_label,
      `Class-list demand` = projection_preview_integer(projected_classlist_total),
      `Expected census` = projection_preview_integer(projected_census_equivalent),
      Method = method_label,
      Aftcasts = projection_preview_integer(n_backtests),
      `Accuracy terms` = backtest_term_range,
      `Raw WAPE` = projection_preview_percent(wape),
      `Capacity audit` = dplyr::case_when(
        dplyr::coalesce(n_backtests, 0L) == 0L ~ "--",
        dplyr::coalesce(n_capacity_censored_misses, 0L) == 0L ~
          "No bounded errors",
        n_capacity_censored_misses == n_backtests ~ paste0(
          "Capacity-bounded (", n_capacity_censored_misses, "/",
          n_backtests, ")"
        ),
        TRUE ~ paste0(
          n_capacity_censored_misses, "/", n_backtests,
          " capacity-bounded; minimum ",
          projection_preview_percent(capacity_censored_wape)
        )
      ),
      `Uncensored WAPE` = projection_preview_percent(uncensored_wape),
      Bias = projection_preview_percent(weighted_bias, signed = TRUE),
      Confidence = confidence,
      `Why uncertain` = dplyr::if_else(
        confidence == "None", why_uncertain, "--"
      ),
      Coupling = coupling_status,
      `Bias correction` = projection_preview_bias_correction(
        applied = dplyr::coalesce(calibration_applied, FALSE),
        factor = calibration_factor,
        adjustment = calibration_adjustment,
        candidate = dplyr::coalesce(calibration_candidate, FALSE),
        n_validation = n_calibrated_backtests,
        reason = calibration_reason,
        n_backtests = n_backtests,
        min_validation = .env$min_calibration_validation
      ),
      Recommendation = recommendation
    )
  history_table <- history %>%
    dplyr::transmute(
      Course = subject_course,
      Term = history_term_label,
      Aftcast = projection_preview_integer(aftcast_classlist_total),
      `Raw error` = projection_preview_percent(aftcast_pct_error, signed = TRUE),
      `Error assessment` = dplyr::case_when(
        !aftcast_applicable | !is.finite(aftcast_classlist_total) ~ "--",
        dplyr::coalesce(aftcast_capacity_censored, FALSE) ~
          "Capacity-bounded",
        TRUE ~ "Observed"
      ),
      `First day / ever registered` =
        projection_preview_integer(actual_classlist_total),
      Census = projection_preview_integer(actual_census),
      `Final / last day` = projection_preview_integer(actual_final_enrollment),
      Sections = projection_preview_integer(scheduled_sections),
      Capacity = projection_preview_integer(scheduled_capacity),
      `Registration fill` = projection_preview_percent(registration_fill),
      `Capacity status` = dplyr::case_when(
        !capacity_usable ~ "No capacity",
        capacity_reached ~ "Reached",
        TRUE ~ "Not reached"
      ),
      `Potential explanation` = potential_miss_explanation
    )

  overrides <- bundle$model_config$course_history_start_terms
  override_note <- if (length(overrides) == 0L) {
    "None"
  } else {
    paste(
      paste0(names(overrides), " from ",
             vapply(overrides, fmt_term, character(1))),
      collapse = "; "
    )
  }
  context <- paste0(
    "Target: ", fmt_term(bundle$target_term),
    " | Data through: ", fmt_term(bundle$as_of_term),
    " | Market: ", bundle$scope_market_id,
    " | Model: ", bundle$model_version,
    " | General history: ", fmt_term(bundle$model_config$history_start_term),
    " | Overrides: ", override_note
  )
  current_lines <- projection_preview_markdown_table(
    current_table,
    right_align = c(
      "Class-list demand", "Expected census", "Aftcasts", "Raw WAPE",
      "Uncensored WAPE", "Bias"
    )
  )
  history_lines <- projection_preview_markdown_table(
    history_table,
    right_align = c(
      "First day / ever registered", "Census", "Final / last day",
      "Sections", "Capacity", "Registration fill",
      "Aftcast", "Raw error"
    )
  )

  c(
    "# Enrollment Projection Preview",
    context,
    "",
    "## Current projections",
    if (length(current_lines) == 0L) "_No matching projection rows._" else
      current_lines,
    "",
    "## Recent same-season evidence",
    if (length(history_lines) == 0L) "_No comparable history rows._" else
      history_lines,
    "",
    paste(
      "Historical predictions are leakage-safe aftcasts of the current selected",
      "method; they are not claims about a forecast published at that time."
    ),
    paste(
      "Capacity-bounded means overprojection cannot be measured because",
      "registration reached capacity; it is not a claim of zero error."
    )
  )
}


print_enrollment_projection_preview <- function(bundle, courses = NULL) {
  output <- format_enrollment_projection_preview(bundle, courses = courses)
  cat(output, sep = "\n")
  invisible(output)
}
