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

  content_signature <- digest::digest(data, algo = "sha256", serialize = TRUE)
  list(
    rows = nrow(data),
    columns = ncol(data),
    first_term = if (length(terms) == 0) NA_integer_ else min(terms, na.rm = TRUE),
    last_term = if (length(terms) == 0) NA_integer_ else max(terms, na.rm = TRUE),
    as_of_date = as_of,
    signature = substr(content_signature, 1, 16),
    content_sha256 = content_signature
  )
}


enrollment_projection_model_source_files <- function() {
  c(
    "R/lists/enrollment_projection_groups.R",
    "R/lists/seat_fill.R",
    "R/lists/grades.R",
    "R/lists/status_codes.R",
    "R/lists/campuses.R",
    "R/lists/gen_ed_courses.R",
    "R/trunk/utils.R",
    "R/branches/enrl.R",
    "R/branches/data-edges.R",
    "R/branches/enrollment-projections.R",
    "R/cones/enrollment-projections.R",
    "R/features/enrollment-projection-refresh.R",
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
    error = function(error) {
      # No git on this machine: provenance records NA and the page says so,
      # but the build log should say why rather than nothing.
      message("[enrollment-projections.R] git unavailable: ",
              conditionMessage(error))
      structure(character(0), status = 1L)
    }
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
                                               built_at = Sys.time(),
                                               reuse_if_current = FALSE,
                                               existing_bundle = NULL) {
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
  # Spring and Fall only. Summer is refused deliberately, not for lack of
  # plumbing: it has a different scheduling and demand regime, and the history
  # window holds too few comparable Summer terms to aftcast against.
  if (!get_term_type(target_term) %in% c("spring", "fall")) {
    stop(
      "[enrollment-projections.R] Published projection bundles support Spring and Fall ",
      "targets only; Summer has a different demand regime and no comparable evidence base.",
      call. = FALSE
    )
  }
  if (as_of_term >= target_term) {
    stop("[enrollment-projections.R] as_of_term must precede target_term.",
         call. = FALSE)
  }
  edges <- cedar_data_edges(students)
  settled_through_term <- edges$last_enrolled_complete
  if (is.null(settled_through_term) || length(settled_through_term) == 0L ||
      is.na(settled_through_term[[1]])) {
    stop(
      "[enrollment-projections.R] Cannot determine a settled enrollment edge; projection builds fail closed.",
      call. = FALSE
    )
  }
  settled_through_term <- as.integer(settled_through_term[[1]])
  if (as_of_term > settled_through_term) {
    stop(
      "[enrollment-projections.R] as_of_term ", as_of_term,
      " is not settled; last_enrolled_complete is ", settled_through_term, ".",
      call. = FALSE
    )
  }
  opt <- enrollment_projection_model_config(opt)
  graded_through_term <- edges$last_graded

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
    course_history_start_terms = opt$course_history_start_terms,
    graded_through_term = graded_through_term,
    intersession_parts_of_term = opt$intersession_parts_of_term
  )
  provenance <- enrollment_projection_model_provenance()
  refresh_signature <- enrollment_projection_refresh_signature(
    inputs, opt, force_courses, provenance
  )
  if (isTRUE(reuse_if_current)) {
    reason <- enrollment_projection_rebuild_reason(existing_bundle, refresh_signature)
    if (is.null(reason)) {
      message("[projections] Saved projections are current; skipping model fitting.")
      attr(existing_bundle, "projection_reused") <- TRUE
      return(existing_bundle)
    }
    message("[projections] Rebuilding: ", reason, ".")
  }
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
    model_provenance = provenance,
    model_config = opt,
    source_fingerprint = list(
      refresh = refresh_signature,
      classlist_enrollments = projection_table_fingerprint(cl_enrls),
      sections = projection_table_fingerprint(sections),
      students = projection_table_fingerprint(students)
    ),
    target_schedule_as_of = projection_target_schedule_as_of(sections, target_term),
    built_at = built_at
  )
}


# When the target term's schedule -- a draft until registration settles -- was
# pulled, from its DESR rows' as_of_date. NA when the data has no section for
# the target term yet.
projection_target_schedule_as_of <- function(sections, target_term) {
  if (!"as_of_date" %in% names(sections)) {
    stop("[enrollment-projections.R] sections needs as_of_date to date the ",
         "target schedule.", call. = FALSE)
  }
  dates <- as.Date(sections$as_of_date[sections$term == as.integer(target_term)])
  if (length(dates) == 0L || all(is.na(dates))) return(as.Date(NA))
  max(dates, na.rm = TRUE)
}


# Saved bundles, one row per published target term.
#
# CEDAR publishes one bundle PER SEASON, not one bundle overall: a Fall 2027 and
# a Spring 2027 projection are both current, and neither supersedes the other.
# Discovery is therefore season-aware everywhere. Choosing the single highest
# target term -- correct while Spring was the only season -- would make the first
# published Fall bundle silently hide Spring from every reader.
#
# Returns a zero-row tibble when nothing is saved; an absent bundle is a
# documented empty state for readers, not an error.
find_enrollment_projection_bundles <- function(
    output_dir = file.path(getwd(), "output", "projections")) {
  empty <- tibble::tibble(
    path = character(0), target_term = integer(0),
    term_type = character(0), modified = Sys.time()[0]
  )
  if (!dir.exists(output_dir)) return(empty)
  paths <- list.files(
    output_dir,
    pattern = "^enrollment-projections-[0-9]{6}-latest\\.(qs|Rds)$",
    full.names = TRUE
  )
  if (length(paths) == 0L) return(empty)
  target_terms <- suppressWarnings(as.integer(sub(
    "^enrollment-projections-([0-9]{6})-latest\\.(qs|Rds)$",
    "\\1", basename(paths)
  )))
  found <- tibble::tibble(
    path = paths,
    target_term = target_terms,
    term_type = get_term_type(target_terms),
    modified = file.info(paths)$mtime
  )
  # One target term can hold both a .qs and an .Rds; the newer file wins.
  found %>%
    dplyr::arrange(dplyr::desc(.data$target_term), dplyr::desc(.data$modified)) %>%
    dplyr::distinct(.data$target_term, .keep_all = TRUE)
}


.enrollment_projection_season <- function(term_type) {
  if (length(term_type) != 1L || is.na(term_type) ||
      !term_type %in% c("spring", "fall")) {
    stop(
      "[enrollment-projections.R] A published season is required: ",
      "\"spring\" or \"fall\".",
      call. = FALSE
    )
  }
  term_type
}


# The newest published bundle OF A NAMED SEASON.
#
# term_type has no default on purpose. A caller that does not name its season
# would keep working today and silently switch seasons the day the other one
# publishes a later target term -- the exact failure this function exists to
# prevent.
find_latest_enrollment_projection_bundle <- function(
    output_dir = file.path(getwd(), "output", "projections"), term_type = NULL) {
  term_type <- .enrollment_projection_season(term_type)
  saved <- find_enrollment_projection_bundles(output_dir)
  saved <- saved[saved$term_type == term_type, , drop = FALSE]
  if (nrow(saved) == 0L) return(NULL)
  saved$path[[1]]
}


find_enrollment_projection_bundle <- function(
    output_dir = file.path(getwd(), "output", "projections"), target_term) {
  target_term <- suppressWarnings(as.integer(target_term))
  if (length(target_term) != 1L || is.na(target_term)) {
    stop("[enrollment-projections.R] One target_term is required.", call. = FALSE)
  }
  saved <- find_enrollment_projection_bundles(output_dir)
  saved <- saved[saved$target_term == target_term, , drop = FALSE]
  if (nrow(saved) == 0L) return(NULL)
  saved$path[[1]]
}


read_enrollment_projection_bundle_at <- function(path) {
  if (is.null(path)) return(NULL)
  bundle <- read_enrollment_projection_bundle(path)
  attr(bundle, "bundle_path") <- normalizePath(path, mustWork = TRUE)
  bundle
}


load_latest_enrollment_projection_bundle <- function(
    output_dir = file.path(getwd(), "output", "projections"), term_type = NULL) {
  read_enrollment_projection_bundle_at(
    find_latest_enrollment_projection_bundle(output_dir, term_type = term_type)
  )
}


load_enrollment_projection_bundle <- function(
    output_dir = file.path(getwd(), "output", "projections"), target_term) {
  read_enrollment_projection_bundle_at(
    find_enrollment_projection_bundle(output_dir, target_term = target_term)
  )
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


# Reader-facing prose for the three projection axes.
#
# One explanation covers all three because they are only useful together: a
# reader needs to know that a course is Volatile AND Deep (we have watched it
# closely and it genuinely jumps around) rather than Volatile AND Thin (we have
# barely seen it). The old single-paragraph confidence explanation could not
# express that, because it had one label to explain.
projection_axis_explanation <- function(stability, depth, accuracy,
                                        n_backtests, wape,
                                        history_terms = NA_integer_,
                                        history_cv = NA_real_,
                                        history_median_yoy = NA_real_,
                                        term_type = NA_character_,
                                        pct_error_sd = NA_real_,
                                        capacity_constrained = FALSE,
                                        n_capacity_reached = NA_integer_,
                                        n_capacity_unreached = NA_integer_,
                                        method_role = NA_character_,
                                        methods_disagree = FALSE) {
  size <- max(
    length(stability), length(depth), length(accuracy),
    length(n_backtests), length(wape), length(history_terms),
    length(history_cv), length(history_median_yoy),
    length(term_type),
    length(pct_error_sd), length(capacity_constrained),
    length(n_capacity_reached),
    length(n_capacity_unreached), length(method_role), length(methods_disagree)
  )
  stability <- rep_len(as.character(stability), size)
  depth <- rep_len(as.character(depth), size)
  accuracy <- rep_len(as.character(accuracy), size)
  n_backtests <- rep_len(as.integer(n_backtests), size)
  wape <- rep_len(as.numeric(wape), size)
  history_terms <- rep_len(as.integer(history_terms), size)
  history_cv <- rep_len(as.numeric(history_cv), size)
  history_median_yoy <- rep_len(as.numeric(history_median_yoy), size)
  term_type <- rep_len(as.character(term_type), size)
  pct_error_sd <- rep_len(as.numeric(pct_error_sd), size)
  capacity_constrained <- rep_len(as.logical(capacity_constrained), size)
  n_capacity_reached <- rep_len(as.integer(n_capacity_reached), size)
  n_capacity_unreached <- rep_len(as.integer(n_capacity_unreached), size)
  method_role <- rep_len(as.character(method_role), size)
  methods_disagree <- rep_len(as.logical(methods_disagree), size)

  vapply(seq_len(size), function(i) {
    n <- dplyr::coalesce(n_backtests[[i]], 0L)
    error <- wape[[i]]
    variation <- pct_error_sd[[i]]
    season <- switch(
      term_type[[i]], spring = "Spring", summer = "Summer", fall = "Fall",
      "same-term-type"
    )
    basis_suffix <- "WAPE"

    stability_text <- switch(
      stability[[i]],
      Stable = paste0(
        "Stability: this course's own ", season,
        " enrollment has moved only ",
        scales::percent(history_cv[[i]], accuracy = 0.1),
        " across ", history_terms[[i]], " comparable terms, so its history ",
        "alone supports a forecast."
      ),
      Moderate = paste0(
        "Stability: ", season, " enrollment varies ",
        scales::percent(history_cv[[i]], accuracy = 0.1),
        " across ", history_terms[[i]], " comparable terms — enough movement ",
        "to matter for planning, not enough to make the course unpredictable."
      ),
      Volatile = paste0(
        "Stability: ", season, " enrollment swings ",
        scales::percent(history_cv[[i]], accuracy = 0.1),
        " across ", history_terms[[i]], " comparable terms, typically ",
        scales::percent(history_median_yoy[[i]], accuracy = 0.1),
        " term to term. No method forecasts a course like this reliably; ",
        "the swing itself is the thing worth investigating."
      ),
      paste0(
        "Stability: ", history_terms[[i]], " comparable ", season,
        " term(s) observed, too few to judge whether this course behaves ",
        "predictably."
      )
    )

    depth_text <- switch(
      depth[[i]],
      Deep = paste0(
        "Depth: ", n, " comparable ", season,
        " aftcasts stand behind the selection rule."
      ),
      Moderate = paste0(
        "Depth: ", n, " comparable ", season,
        " aftcasts — enough to measure accuracy, not enough to be sure it holds."
      ),
      Thin = paste0(
        "Depth: only ", n, " comparable ", season,
        " aftcast", if (n == 1L) "" else "s",
        ", so any accuracy figure rests on very little evidence."
      ),
      "Depth: no comparable aftcast for the selection rule."
    )

    # The accuracy figure is the realised error of the selection rule replayed
    # at each past term with only earlier evidence, so it is an out-of-sample
    # record rather than the fit of the winner on the terms that chose it.
    accuracy_text <- switch(
      accuracy[[i]],
      High = paste0(
        "Reliability: rolling-selection aftcasts landed within ",
        scales::percent(error, accuracy = 0.1), " ", basis_suffix,
        if (is.finite(variation)) paste0(
          ", varying ", scales::percent(variation, accuracy = 0.1),
          " term to term"
        ) else "", "."
      ),
      Moderate = paste0(
        "Reliability: rolling-selection aftcasts averaged ",
        scales::percent(error, accuracy = 0.1), " ", basis_suffix,
        " — usable for planning, not for a precise seat count."
      ),
      Low = paste0(
        "Reliability: rolling-selection aftcasts averaged ",
        scales::percent(error, accuracy = 0.1), " ", basis_suffix,
        ". Treat this projection as a rough scale, not a number to schedule to."
      ),
      "Reliability: not enough comparable aftcasts to measure how close past forecasts were."
    )

    caveats <- character(0)
    if (isTRUE(capacity_constrained[[i]])) {
      reached <- dplyr::coalesce(n_capacity_reached[[i]], 0L)
      unreached <- dplyr::coalesce(n_capacity_unreached[[i]], 0L)
      caveats <- c(caveats, paste0(
        "Capacity caveat: first-day enrollment reached the scheduled seats in ",
        reached, " of ", reached + unreached,
        " capacity-observed aftcast term(s). ",
        "Accuracy describes fit to observed enrollment, not proof of ",
        "unconstrained demand."
      ))
    }
    if (isTRUE(methods_disagree[[i]])) {
      caveats <- c(caveats, paste(
        "Method caveat: candidate projections differ materially, so method",
        "choice remains important."
      ))
    }
    paste(c(stability_text, depth_text, accuracy_text, caveats), collapse = " ")
  }, character(1))
}


# Compact one-line summary for a table cell: the three axes in reading order.
projection_axis_brief <- function(stability, depth, accuracy,
                                  capacity_constrained = FALSE,
                                  methods_disagree = FALSE,
                                  regime_alarm = FALSE) {
  size <- max(
    length(stability), length(depth), length(accuracy),
    length(capacity_constrained), length(methods_disagree),
    length(regime_alarm)
  )
  stability <- rep_len(as.character(stability), size)
  depth <- rep_len(as.character(depth), size)
  accuracy <- rep_len(as.character(accuracy), size)
  capacity_constrained <- rep_len(as.logical(capacity_constrained), size)
  methods_disagree <- rep_len(as.logical(methods_disagree), size)
  regime_alarm <- rep_len(as.logical(regime_alarm), size)

  vapply(seq_len(size), function(i) {
    qualifier <- dplyr::case_when(
      isTRUE(regime_alarm[[i]]) ~ "regime check",
      isTRUE(capacity_constrained[[i]]) ~ "capacity-limited",
      isTRUE(methods_disagree[[i]]) ~ "methods differ",
      TRUE ~ NA_character_
    )
    parts <- c(
      paste0(stability[[i]], " history"),
      paste0(depth[[i]], " evidence"),
      paste0(accuracy[[i]], " reliability"),
      qualifier
    )
    paste(parts[!is.na(parts)], collapse = " \u00b7 ")
  }, character(1))
}


# What reliability and seat consistency say together, in one sentence. Most
# past error followed schedule changes, so a miss is only the forecast's when
# the seats held steady.
projection_reliability_reading <- function(reliability, seat_consistency) {
  reliability <- as.character(reliability)
  seat_consistency <- dplyr::coalesce(as.character(seat_consistency), "Unrated")
  dplyr::case_when(
    reliability == "Unrated" ~
      "Too few past forecasts to say how reliable this course's projection is.",
    reliability == "High" ~
      "Past forecasts landed close, so the projection can be planned to.",
    reliability == "Low" & seat_consistency == "High" ~ paste(
      "Past forecasts missed by more than 20% even though the seats held",
      "steady, so the forecast itself missed: look at this course before",
      "planning to it."
    ),
    reliability == "Low" & seat_consistency %in% c("Moderate", "Low") ~ paste(
      "Past forecasts missed by more than 20%, in terms when the seats kept",
      "moving: the misses follow the schedule more than demand, so the",
      "projection holds if the seats do."
    ),
    reliability == "Moderate" & seat_consistency == "High" ~ paste(
      "Past forecasts were 10 to 20% off with steady seats: usable for",
      "planning, not for a precise seat count."
    ),
    reliability == "Moderate" & seat_consistency %in% c("Moderate", "Low") ~ paste(
      "Past forecasts were 10 to 20% off, and some of that followed seat",
      "changes."
    ),
    TRUE ~ paste(
      "The seats behind past forecasts cannot be compared, so a miss cannot",
      "be told apart from a schedule change."
    )
  )
}


# Plain-language flags for the summary table. Each one names a reason an
# administrator should look at the row; none changes a number. Full and near
# full are the two seat-fill levels (R/lists/seat_fill.R), read live.
projection_flags <- function(projections) {
  projection_require_columns(
    projections,
    c("adjusted_saturated_prior", "adjusted_prior_first_day_fill",
      "adjusted_prior_first_day_basis", "adjusted_waitlisted_prior",
      "adjusted_regime_alarm", "adjusted_preceding_term_change", "stability",
      "accuracy", "seat_consistency", "methods_disagree", "campus_fill_flag"),
    "projection_flags()"
  )
  vapply(seq_len(nrow(projections)), function(i) {
    row <- projections[i, , drop = FALSE]
    saturated <- row$adjusted_saturated_prior[[1]]
    flags <- c(
      if (isTRUE(saturated)) {
        if (isTRUE(row$adjusted_prior_first_day_fill >= CEDAR_FULL_FILL)) {
          "Full last term"
        } else {
          "Near full last term"
        }
      },
      if (isTRUE(saturated) && isTRUE(row$adjusted_waitlisted_prior > 0)) {
        paste(row$adjusted_waitlisted_prior, "waiting")
      },
      # Unknown is said with its cause, never left blank (ISSUES.md I28).
      if (is.na(saturated)) {
        switch(
          dplyr::coalesce(row$adjusted_prior_first_day_basis[[1]], ""),
          undated = "Last term's fill unknown: no status dates",
          sessions_pending = "Last term's fill unknown: a session had not begun",
          no_capacity = "Last term's fill unknown: no seat count",
          NULL
        )
      },
      if (!is.na(row$campus_fill_flag)) row$campus_fill_flag,
      if (isTRUE(row$adjusted_regime_alarm)) paste0(
        "Fall enrollment ",
        sprintf("%+.0f%%", 100 * row$adjusted_preceding_term_change)
      ),
      if (identical(row$stability, "Volatile")) "Hard to predict",
      # A miss with steady seats is the forecast's; a miss as seats moved is
      # mostly the schedule's.
      if (identical(row$accuracy, "Low")) {
        switch(
          dplyr::coalesce(row$seat_consistency, "Unrated"),
          High = "Off 20%+ with steady seats",
          Moderate = , Low = "Off 20%+ as seats moved",
          "Past forecasts off by 20%+"
        )
      },
      if (isTRUE(row$methods_disagree)) "Candidates disagree"
    )
    if (length(flags) == 0L) "" else paste(flags, collapse = " | ")
  }, character(1))
}


# One flag per projection where, in the latest recent term, a delivery campus
# was full on the first day while another had room. The forecast pools the
# campuses as one market; this keeps a full online campus from hiding behind
# open seats elsewhere (ISSUES.md M36). Only complete first days with usable
# seats are compared; NA where no campus pair qualifies.
projection_campus_fill_flags <- function(projections, campus_history) {
  projection_require_columns(
    projections, c("market_id", "subject_course", "target_term"),
    "projection_campus_fill_flags()"
  )
  projection_require_columns(
    campus_history,
    c("market_id", "subject_course", "projection_target_term", "recency_rank",
      "campus", "first_day_basis", "first_day_fill"),
    "projection_campus_fill_flags() campus history"
  )
  # CAMPUS_ROLLUP: one flag per pooled market row, naming each campus.
  flags <- campus_history %>%
    dplyr::filter(
      recency_rank == 1L, first_day_basis == "complete",
      is.finite(first_day_fill)
    ) %>%
    dplyr::group_by(market_id, subject_course, projection_target_term) %>%
    dplyr::summarise(
      full = paste(sort(campus[first_day_fill >= CEDAR_FULL_FILL]), collapse = " and "),
      room = paste(sort(campus[first_day_fill < CEDAR_NEAR_FULL_FILL]), collapse = " and "),
      .groups = "drop"
    ) %>%
    dplyr::filter(nzchar(full), nzchar(room)) %>%
    dplyr::transmute(
      market_id, subject_course, target_term = projection_target_term,
      campus_fill_flag = paste0(full, " full last term, ", room, " had room")
    )
  projections %>%
    dplyr::select(market_id, subject_course, target_term) %>%
    dplyr::left_join(
      flags, by = c("market_id", "subject_course", "target_term"),
      relationship = "many-to-one"
    ) %>%
    dplyr::pull(campus_fill_flag)
}


# One sentence an administrator can act on, built from the published fields.
# The tables beneath it are supporting evidence, not the first thing a reader
# meets.
projection_summary_sentence <- function(projections) {
  vapply(seq_len(nrow(projections)), function(i) {
    row <- projections[i, , drop = FALSE]
    if (!is.finite(row$projected_classlist_total)) {
      return("Not enough comparable history to project this course.")
    }
    count <- function(x) format(round(x), big.mark = ",")
    bumped <- isTRUE(row$pressure_bump > 0)
    fed <- isTRUE(row$plan_feeder_adjustment != 0)
    raised <- bumped || fed
    first_day <- if (is.finite(row$projected_first_day_equivalent)) {
      paste0(
        " (about ", count(row$projected_first_day_equivalent),
        if (raised) paste0(" of the projected ", count(row$projected_classlist_total)) else "",
        " in seats on the first day)"
      )
    } else ""
    # The projection, then what the plan adds to it: the feeder adjustment
    # (either way) and the pressure bump.
    parts <- paste0(
      count(row$projected_classlist_total), " projected",
      if (fed) {
        paste0(", ", sprintf("%+.0f", row$plan_feeder_adjustment),
               " for the change in its feeder courses")
      } else "",
      if (bumped) {
        paste0(if (fed) "," else "", " plus a pressure bump of ",
               count(row$pressure_bump))
      } else ""
    )
    plan <- if (!is.na(row$recommended_sections)) {
      paste0(
        if (isTRUE(row$adjusted_saturated_prior)) "Plan at least " else "Plan ",
        row$recommended_sections, " section",
        if (row$recommended_sections == 1L) "" else "s", " for ",
        count(row$planned_registrations), " registrations",
        if (raised) paste0(": ", parts) else "",
        first_day, "."
      )
    } else {
      paste0(
        "Expect about ", count(row$planned_registrations), " registrations",
        if (raised) paste0(" (", parts, ")") else "",
        "; no section size is available to convert that to sections."
      )
    }
    change <- if (is.finite(row$observed_baseline) && row$observed_baseline > 0) {
      delta <- row$projected_classlist_total / row$observed_baseline - 1
      if (abs(delta) < 0.005) {
        " That is last year's level."
      } else {
        paste0(" That is ", sprintf("%+.0f%%", 100 * delta),
               " on last ", switch(row$term_type, spring = "Spring",
                                   fall = "Fall", "comparable term"), ".")
      }
    } else ""
    full <- if (isTRUE(row$adjusted_saturated_prior)) {
      paste0(
        " Last ", switch(row$term_type, spring = "Spring", fall = "Fall", "term"),
        " filled ", scales::percent(row$adjusted_prior_first_day_fill, accuracy = 0.1),
        " of its seats on the first day",
        if (isTRUE(row$adjusted_waitlisted_prior > 0)) {
          paste0(" with ", row$adjusted_waitlisted_prior, " students waiting")
        } else "",
        ", so this is a floor."
      )
    } else ""
    # A course full last term with no bump says why, so a reader does not
    # take the missing bump for an oversight.
    no_bump <- if (isTRUE(row$adjusted_saturated_prior) &&
                   isFALSE(row$pressure_bump_applied)) {
      paste0(" ", row$pressure_bump_note, ".")
    } else ""
    fall <- if (isTRUE(row$adjusted_regime_alarm)) {
      paste0(
        " Enrollment in ", fmt_term(row$adjusted_preceding_term), " moved ",
        sprintf("%+.0f%%", 100 * row$adjusted_preceding_term_change),
        " from the year before; review before scheduling to this number."
      )
    } else ""
    # The course's own figure, rounded as its plan steps round it: the band
    # ("10 to 20% off") read beside the step's 10.0% as though they disagreed.
    trust <- if (identical(row$accuracy, "Unrated") || !is.finite(row$wape)) {
      " Too few past forecasts to say how reliable this is."
    } else {
      paste0(
        " Past forecasts for this course missed by ",
        scales::percent(row$wape, accuracy = 0.1), " on average",
        if (identical(row$accuracy, "Low")) "; treat it as a rough scale" else "",
        "."
      )
    }
    paste0(plan, change, full, no_bump, fall, trust)
  }, character(1))
}


# How one course's plan was built, step by step from last year's class list to
# the sections: every number on the course's detail, each with where it came
# from, so a reader can check the plan without opening the evidence. Display
# only, from saved fields: the projection's own audit trail (spine, floor,
# deltas), the plan's two additions, and the section size. Returns one row per
# step: `label`, `amount`, `kind` ("start", "add", "total" or "sections") and
# `detail`. A course with no projection has no steps.
projection_plan_steps <- function(row) {
  projection_require_columns(
    row,
    c("term_type", "method_id", "spine", "spine_term", "floor_uplift",
      "delta_repeat", "delta_sequence", "delta_feeder",
      "adjusted_sequence_courses", "adjusted_preceding_term",
      "projected_classlist_total", "accuracy", "wape", "n_backtests",
      "backtest_term_range", "plan_feeder_adjustment", "plan_feeder_note",
      "pressure_bump", "pressure_bump_note", "planned_registrations",
      "reference_section_size", "recommended_sections",
      "scheduled_sections", "target_schedule_available"),
    "projection_plan_steps()"
  )
  if (nrow(row) != 1L) {
    stop("[enrollment-projections.R] projection_plan_steps() takes one row.",
         call. = FALSE)
  }
  empty <- tibble::tibble(
    label = character(), amount = numeric(), kind = character(),
    detail = character()
  )
  if (!is.finite(row$projected_classlist_total) || !is.finite(row$spine)) {
    return(empty)
  }
  count <- function(x) format(round(x), big.mark = ",")
  signed <- function(x) {
    paste0(if (round(x) > 0) "+" else if (round(x) < 0) "\u2212" else "",
           count(abs(x)))
  }
  season <- switch(row$term_type, spring = "Spring", fall = "Fall", "term")
  step <- function(label, amount, kind, detail = NA_character_) {
    tibble::tibble(label = label, amount = as.numeric(amount), kind = kind,
                   detail = detail)
  }
  # The plan notes open with "Feeder adjustment -68: " / "Pressure bump +109: ",
  # which the step's label and amount already say.
  reason <- function(note) {
    text <- sub("^[^:]*[+-][0-9,]+: ", "", note)
    paste0(toupper(substr(text, 1, 1)), substring(text, 2))
  }

  adjusted <- identical(row$method_id, "spine_adjusted")
  floor_uplift <- if (adjusted) dplyr::coalesce(row$floor_uplift, 0) else 0
  steps <- list(step(
    paste0("Registered in ", fmt_term(row$spine_term)), row$spine, "start",
    paste0("Everyone on last ", season, "'s class lists, including students ",
           "who later dropped")
  ))
  if (floor_uplift != 0) {
    steps <- c(steps, list(step(
      "Students still waiting", floor_uplift, "add",
      paste0("Waitlisted last ", season, " without a seat in any section, ",
             "because the course was near full")
    )))
  }
  # The projection is the rounded sum, so the change is whatever takes the
  # whole-number start to it; its parts are rounded separately and say so
  # when they no longer add up to it.
  # Parts that cancel still show, so the adjusted method's work is visible.
  change <- row$projected_classlist_total - row$spine - floor_uplift
  parts <- c(
    dplyr::coalesce(row$delta_repeat, 0),
    dplyr::coalesce(row$delta_sequence, 0),
    dplyr::coalesce(row$delta_feeder, 0)
  )
  if (adjusted && any(round(parts) != 0)) {
    names <- c(
      "students retaking this course",
      paste0(dplyr::coalesce(row$adjusted_sequence_courses, "the listed predecessor"),
             ", taken just before"),
      "other feeder courses"
    )
    shown <- round(parts) != 0
    detail <- paste0(
      paste0(names[shown], " ", vapply(parts[shown], signed, character(1)),
             collapse = "; "),
      if (sum(round(parts)) != round(change)) " (each rounded)" else ""
    )
    steps <- c(steps, list(step(
      paste0("Enrollment change in ", fmt_term(row$adjusted_preceding_term)),
      change, "add", detail
    )))
  }
  record <- if (identical(row$accuracy, "Unrated") || !is.finite(row$wape)) {
    "Too few past forecasts to say how close this one will be"
  } else {
    paste0(
      "Past forecasts for this course missed by ",
      scales::percent(row$wape, accuracy = 0.1), " on average (",
      row$n_backtests, " term", if (row$n_backtests == 1L) "" else "s",
      if (!is.na(row$backtest_term_range)) paste0(", ", row$backtest_term_range) else "",
      ")"
    )
  }
  steps <- c(steps, list(step(
    "Forecast registrations", row$projected_classlist_total, "total", record
  )))
  if (isTRUE(row$plan_feeder_adjustment != 0)) {
    steps <- c(steps, list(step(
      "Feeder adjustment", row$plan_feeder_adjustment, "add",
      reason(row$plan_feeder_note)
    )))
  }
  if (isTRUE(row$pressure_bump > 0)) {
    steps <- c(steps, list(step(
      "Pressure bump", row$pressure_bump, "add", reason(row$pressure_bump_note)
    )))
  }
  if (isTRUE(row$plan_feeder_adjustment != 0) || isTRUE(row$pressure_bump > 0)) {
    steps <- c(steps, list(step(
      "Planned registrations", row$planned_registrations, "total",
      "What the sections are sized for"
    )))
  }
  if (!is.na(row$recommended_sections)) {
    from_draft <- isTRUE(row$target_schedule_available) &&
      isTRUE(row$scheduled_sections > 0)
    steps <- c(steps, list(step(
      "Sections", row$recommended_sections, "sections",
      paste0(
        count(row$planned_registrations), " registrations at ",
        format(round(row$reference_section_size, 1), nsmall = 1),
        " per section (",
        if (from_draft) "the draft schedule's average" else "recent average",
        "), rounded up",
        if (from_draft) {
          paste0("; the draft schedule has ", row$scheduled_sections,
                 " section", if (row$scheduled_sections == 1L) "" else "s")
        } else ""
      )
    )))
  }
  dplyr::bind_rows(steps)
}


# What the pressure bump adds across the rows shown, and one sentence saying
# so, so the page states how much it raised the plan. Rows without a
# projection carry a zero bump and no sections, and are left out of the
# section total.
projection_pressure_bump_summary <- function(projections, share) {
  if (!is.numeric(share) || length(share) != 1L || !is.finite(share)) {
    stop("[enrollment-projections.R] The bundle's model_config has no ",
         "pressure_bump_share.", call. = FALSE)
  }
  applied <- projections$pressure_bump_applied %in% TRUE
  registrations <- sum(projections$pressure_bump[applied])
  projected <- sum(projections$projected_classlist_total[applied])
  sections <- sum(projections$pressure_bump_sections[applied], na.rm = TRUE)
  n_courses <- sum(applied)
  sentence <- if (n_courses == 0L) {
    paste(
      "No course shown gets a pressure bump: none was near full on the first",
      "day in every recent same-season term with a first-day count."
    )
  } else {
    paste0(
      "The pressure bump adds ", format(round(registrations), big.mark = ","),
      " registrations (", scales::percent(registrations / projected, accuracy = 0.1),
      " of those courses' projections) and ", format(sections, big.mark = ","),
      " section", if (sections == 1L) "" else "s", " across ", n_courses,
      " of the ", nrow(projections), " courses shown. They were near full on ",
      "the first day in every recent same-season term with a first-day count, ",
      "so their registrations were capped by their seats. The bump is ",
      scales::percent(share, accuracy = 1), ", or the students left waiting if ",
      "that is more, and it will be measured from waitlists as they accumulate."
    )
  }
  list(
    n_courses = as.integer(n_courses),
    registrations = as.numeric(registrations),
    sections = as.integer(sections),
    sentence = sentence
  )
}


# What the plan's feeder adjustment moves across the rows shown, and one
# sentence saying so: how many plans it raised and lowered and by how much,
# or why it moved none. `line` and `seasons` are the bundle's
# plan_feeder_change and plan_feeder_seasons.
projection_plan_feeder_summary <- function(projections, line, seasons) {
  if (!is.numeric(line) || length(line) != 1L || !is.finite(line)) {
    stop("[enrollment-projections.R] The bundle's model_config has no ",
         "plan_feeder_change.", call. = FALSE)
  }
  seasons_rule <- projection_plan_feeder_seasons_rule(seasons)
  projection_require_columns(
    projections,
    c("term_type", "projected_classlist_total", "method_id",
      "plan_feeder_adjustment", "adjusted_preceding_term",
      "adjusted_feeder_check"),
    "projection_plan_feeder_summary()"
  )
  projected <- is.finite(projections$projected_classlist_total)
  out_of_season <- projected & !projections$term_type %in% seasons
  adjustment <- projections$plan_feeder_adjustment
  up <- projected & adjustment > 0
  down <- projected & adjustment < 0
  in_projection <- projected & projections$method_id == "spine_adjusted"
  unobserved <- projected & projections$adjusted_feeder_check %in% "term_not_observed"
  preceding <- stats::na.omit(projections$adjusted_preceding_term)
  preceding_label <- if (length(preceding) > 0L) fmt_term(preceding[[1]]) else
    "the term just finished"
  count <- function(x) format(round(x), big.mark = ",")
  whose <- function(n, noun) {
    if (n == 1L) paste0("1 course's ", noun) else paste0(n, " courses' ", noun, "s")
  }
  rule <- paste0(
    "A course's listed predecessor, taken the term before, always counts; its ",
    "other feeder courses count when they moved ",
    scales::percent(line, accuracy = 1), " or more."
  )
  included <- if (sum(in_projection) > 0L) {
    paste0(
      " ", whose(sum(in_projection), "published projection"),
      if (sum(in_projection) == 1L) " already includes" else " already include",
      " those changes."
    )
  } else ""
  sentence <- if (sum(projected) > 0L && all(out_of_season[projected])) {
    paste0("No plan has a feeder adjustment: ", seasons_rule, ".")
  } else if (sum(projected) > 0L && all(unobserved[projected])) {
    paste0(
      "No plan has a feeder adjustment: ", preceding_label, " is not observed ",
      "yet, so its feeder courses cannot be read. They count once it settles."
    )
  } else if (sum(up) + sum(down) == 0L) {
    paste0(
      "No plan shown has a feeder adjustment: where the forecast is last ",
      "year's number, feeder courses moved less than ",
      scales::percent(line, accuracy = 1), " in ", preceding_label,
      " and no listed predecessor changed it.", included
    )
  } else {
    paste0(
      "Feeder courses in ", preceding_label, " ",
      paste(c(
        if (sum(up) > 0L) paste0("raise ", whose(sum(up), "plan"), " by ",
                                 count(sum(adjustment[up])), " registrations"),
        if (sum(down) > 0L) paste0("lower ", whose(sum(down), "plan"), " by ",
                                   count(-sum(adjustment[down])))
      ), collapse = " and "),
      ". ", rule, included
    )
  }
  list(
    n_raised = as.integer(sum(up)),
    n_lowered = as.integer(sum(down)),
    registrations = as.numeric(sum(adjustment[up | down])),
    sentence = sentence
  )
}


# Where past forecast error came from, as a table and one sentence, from the
# bundle's saved aftcasts.
projection_error_sources_summary <- function(backtests, model_config) {
  sources <- summarize_projection_error_sources(backtests, model_config)
  n_folds <- sum(sources$folds)
  share <- function(id) {
    value <- sources$share_of_error[sources$source == id]
    if (length(value) == 1L && is.finite(value)) scales::percent(value, accuracy = 1) else "none"
  }
  room_wape <- sources$wape[sources$source == "seats_held_room"]
  sentence <- if (n_folds == 0L) {
    "No past forecasts are saved for this target, so where error comes from cannot be shown."
  } else {
    paste0(
      "Across ", format(n_folds, big.mark = ","), " past forecasts, ",
      share("seats_changed"), " of the error came from terms whose seats ",
      "changed, ", share("data_missing"), " from terms with seat or first-day ",
      "data missing, ", share("seats_held_full"), " from near-full courses ",
      "whose seats held, and ", share("seats_held_room"), " from courses with ",
      "room whose seats held", if (length(room_wape) == 1L && is.finite(room_wape)) {
        paste0(" (", scales::percent(room_wape, accuracy = 0.1), " off on average)")
      } else "",
      ". Only that last group tests the forecast of demand itself; the rest ",
      "is the schedule, the data, or demand a full course could not show."
    )
  }
  list(table = sources, n_folds = as.integer(n_folds), sentence = sentence)
}


# How often the range held on past forecasts, by whether their seats held,
# as a table and one sentence, from the bundle's saved aftcasts (ISSUES.md
# M35). The range assumes steady seats and the page says so.
projection_range_coverage_summary <- function(backtests, model_config) {
  coverage <- summarize_projection_range_coverage(backtests, model_config)
  change <- scales::percent(
    as.numeric(projection_option(model_config, "seat_consistency_change")), accuracy = 1
  )
  steady <- coverage[coverage$seats == "steady", , drop = FALSE]
  moved <- coverage[coverage$seats == "moved", , drop = FALSE]
  above <- sum(coverage$actual_above)
  below <- sum(coverage$actual_below)
  held <- function(row) paste0(
    format(row$covered, big.mark = ","), " of ", format(row$folds, big.mark = ",")
  )
  sentence <- if (steady$folds + moved$folds == 0L) {
    paste(
      "The range assumes seats like last year's. No past forecast has an",
      "earlier one to build a range from, so how often it held cannot be shown",
      "yet."
    )
  } else {
    paste0(
      "The range assumes seats like last year's. Rebuilt for each past ",
      "forecast from the course's earlier ones only, it held ", held(steady),
      " times when seats stayed within ", change, " of the year before, and ",
      held(moved), " when they moved",
      if (above + below > 0L) paste0(
        ". Of its ", format(above + below, big.mark = ","),
        if (above + below == 1L) " miss, " else " misses, ",
        format(max(above, below), big.mark = ","), " had registrations ",
        if (above >= below) "above" else "below", " it"
      ) else "",
      "."
    )
  }
  list(table = coverage, sentence = sentence)
}


# Beside a row's range: when the draft schedule moves the seats from last
# year's same term by the seat-consistency change or more, the range, which
# assumes steady seats, says so (ISSUES.md M35). NA otherwise, including when
# no draft is in the data.
projection_range_seat_notes <- function(projections, recent_history, model_config) {
  change <- as.numeric(projection_option(model_config, "seat_consistency_change"))
  projection_require_columns(
    projections,
    c("market_id", "subject_course", "target_term", "target_schedule_available",
      "scheduled_capacity"),
    "projection_range_seat_notes()"
  )
  projection_require_columns(
    recent_history,
    c("market_id", "subject_course", "projection_target_term", "recency_rank",
      "scheduled_capacity", "history_term_label"),
    "projection_range_seat_notes() history"
  )
  last <- recent_history %>%
    dplyr::filter(recency_rank == 1L) %>%
    dplyr::transmute(
      market_id, subject_course, target_term = projection_target_term,
      last_capacity = scheduled_capacity, last_label = history_term_label
    )
  projections %>%
    dplyr::select(
      market_id, subject_course, target_term, target_schedule_available,
      scheduled_capacity
    ) %>%
    dplyr::left_join(
      last, by = c("market_id", "subject_course", "target_term"),
      relationship = "many-to-one"
    ) %>%
    dplyr::mutate(
      seat_change = dplyr::if_else(
        target_schedule_available %in% TRUE & is.finite(last_capacity) &
          last_capacity > 0 & is.finite(scheduled_capacity),
        scheduled_capacity / last_capacity - 1, NA_real_
      ),
      note = dplyr::if_else(
        is.finite(seat_change) & abs(seat_change) >= change,
        sprintf(
          "Draft seats %+.0f%% on %s: the range assumes steady seats",
          100 * seat_change, last_label
        ),
        NA_character_
      )
    ) %>%
    dplyr::pull(note)
}


# The published plan beside the target term's schedule as it stands -- a
# draft until registration settles -- course by course. Arithmetic over saved
# rows: the bundle captured the schedule when it was built, and a changed
# draft rebuilds the bundle on the next refresh. Planned registrations carry
# the deliberate margin, the feeder adjustment and any pressure bump, so the
# comparison separates a
# draft short of the students expected on day one from one short only of the
# margin.
build_enrollment_projection_draft_comparison <- function(view) {
  projections <- view$projections
  projection_require_columns(
    projections,
    c("subject_course", "department", "market_id", "projected_classlist_total",
      "planned_registrations", "pressure_bump", "plan_feeder_adjustment",
      "projected_first_day_equivalent",
      "recommended_sections", "additional_sections", "reference_section_size",
      "scheduled_sections", "scheduled_capacity", "target_schedule_available",
      "target_registration_observed", "target_registered_now", "accuracy",
      "seat_consistency"),
    "build_enrollment_projection_draft_comparison()"
  )
  as_of <- view$meta$target_schedule_as_of
  count <- function(x) format(round(x), big.mark = ",", trim = TRUE)
  sections_note <- function(n) dplyr::if_else(
    dplyr::coalesce(n, 0L) > 0L,
    paste0(" (", n, " section", dplyr::if_else(n == 1L, "", "s"), ")"),
    ""
  )
  # CAMPUS_ROLLUP: the draft is shown per course across the pooled market, with
  # each campus's sections listed beside it from the saved delivery components.
  campus_sections <- view$delivery_components %>%
    dplyr::group_by(market_id, subject_course, campus) %>%
    dplyr::summarise(sections = sum(scheduled_sections), .groups = "drop") %>%
    dplyr::arrange(subject_course, campus) %>%
    dplyr::group_by(market_id, subject_course) %>%
    dplyr::summarise(
      campus_sections = paste(campus, sections, collapse = " \u00b7 "),
      .groups = "drop"
    )

  table <- projections %>%
    dplyr::filter(is.finite(projected_classlist_total)) %>%
    dplyr::left_join(campus_sections, by = c("market_id", "subject_course")) %>%
    dplyr::transmute(
      course = subject_course,
      department,
      in_draft = target_schedule_available %in% TRUE,
      draft_sections = dplyr::if_else(in_draft, as.integer(scheduled_sections), NA_integer_),
      draft_seats = dplyr::if_else(in_draft, as.numeric(scheduled_capacity), NA_real_),
      campus_sections,
      expected_first_day = projected_first_day_equivalent,
      planned_registrations,
      pressure_bump,
      plan_feeder_adjustment,
      plan_sections = recommended_sections,
      # Negative where the draft is short of the plan.
      draft_vs_plan = dplyr::if_else(in_draft, scheduled_capacity - planned_registrations, NA_real_),
      sections_to_add = dplyr::if_else(in_draft, additional_sections, NA_integer_),
      # Each shortfall carries its own sections, at the plan's section size:
      # "short by 10; the plan needs 2 more sections" read as 2 sections for 10
      # students, when the 2 were for the larger gap to the plan.
      day_one_sections = projection_sections_for_demand(
        expected_first_day - draft_seats, reference_section_size
      ),
      spare_line = pmax(10, dplyr::coalesce(reference_section_size, 0)),
      registered_now = dplyr::if_else(
        target_registration_observed %in% TRUE, as.numeric(target_registered_now), NA_real_
      ),
      reliability = accuracy,
      seat_consistency,
      status = dplyr::case_when(
        !in_draft ~ "not_in_draft",
        is.finite(expected_first_day) & draft_seats < expected_first_day ~ "short_day_one",
        draft_vs_plan < 0 ~ "short_plan",
        draft_vs_plan > spare_line ~ "spare",
        TRUE ~ "covers"
      ),
      verdict = dplyr::case_when(
        status == "not_in_draft" ~ "Not in the draft schedule",
        status == "short_day_one" ~ paste0(
          "Short of day-one seats by ", count(expected_first_day - draft_seats),
          sections_note(day_one_sections),
          # A falling feeder can put the plan below the first day.
          dplyr::if_else(
            draft_vs_plan < 0,
            paste0("; ", count(-draft_vs_plan), " short of the plan",
                   sections_note(sections_to_add)),
            ""
          )
        ),
        status == "short_plan" ~ paste0(
          "Covers day one; ", count(-draft_vs_plan), " short of the plan",
          sections_note(sections_to_add)
        ),
        status == "spare" ~ paste0(count(draft_vs_plan), " seats beyond the plan"),
        TRUE ~ dplyr::if_else(
          draft_vs_plan > 0, paste0("Covers the plan, ", count(draft_vs_plan), " to spare"),
          "Covers the plan"
        )
      )
    ) %>%
    dplyr::select(
      course, department, verdict, draft_sections, draft_seats,
      expected_first_day, planned_registrations, plan_sections, draft_vs_plan,
      registered_now, reliability, seat_consistency,
      in_draft, campus_sections, pressure_bump, plan_feeder_adjustment,
      sections_to_add, status
    ) %>%
    dplyr::arrange(
      factor(status, levels = c("short_day_one", "short_plan", "not_in_draft", "covers", "spare")),
      draft_vs_plan
    )

  in_draft <- table$in_draft
  n <- function(id) sum(table$status == id)
  gap_sum <- function(id, x) sum(x[table$status == id], na.rm = TRUE)
  available <- any(in_draft)
  sentence <- if (!available) {
    paste0(
      "No schedule for ", view$meta$target_term_label, " is in the data yet. ",
      "It appears here after a refresh pulls the target term's DESR from ",
      "MyReports, and the bundle rebuilds with it."
    )
  } else {
    paste0(
      "The draft schedule", if (!is.na(as_of)) paste0(
        " (pulled ", format(as_of, "%B "), as.integer(format(as_of, "%d")),
        format(as_of, ", %Y"), ")"
      ) else "",
      " has ", count(sum(table$draft_seats, na.rm = TRUE)), " seats in ",
      sum(in_draft), " of the ", nrow(table), " courses shown, against ",
      count(sum(table$planned_registrations[in_draft])), " planned registrations. ",
      n("short_day_one"), " course", if (n("short_day_one") == 1L) " is" else "s are",
      " short of the students expected on day one",
      if (n("short_day_one") > 0L) paste0(
        " (by ", count(gap_sum("short_day_one", table$expected_first_day - table$draft_seats)), " seats)"
      ) else "", "; ", n("short_plan"), " cover day one but not the plan; ",
      n("covers"), " cover the plan; ", n("spare"),
      " have more than a section to spare",
      if (n("not_in_draft") > 0L) paste0(
        ". ", n("not_in_draft"), " monitored course",
        if (n("not_in_draft") == 1L) " is" else "s are", " not in the draft"
      ) else "",
      "."
    )
  }
  list(
    available = available,
    as_of = as_of,
    table = table,
    counts = table %>% dplyr::count(status),
    sentence = sentence
  )
}


# The latest `n_terms` same-season terms in the view, oldest first, and for
# each course its first-day enrollment and scheduled sections in each: the
# at-a-glance history the summary table shows. First-day enrollment is NA where
# the class lists carry no status dates or a session had not begun when they
# were pulled, and both are NA in a term the course
# was not offered; a reader-facing surface shows either as an em dash, never as
# zero or as another lifecycle count.
build_enrollment_projection_history_summary <- function(
    projections, history, n_terms = 4L) {
  n_terms <- as.integer(n_terms)
  if (length(n_terms) != 1L || is.na(n_terms) || n_terms < 1L) {
    stop(
      "[enrollment-projections.R] Summary history terms must be positive.",
      call. = FALSE
    )
  }
  required <- c(
    "subject_course", "history_term", "history_term_label",
    "actual_first_day", "scheduled_sections"
  )
  missing <- setdiff(required, names(history))
  if (length(missing) > 0L) {
    stop(
      "[enrollment-projections.R] Summary history needs column(s): ",
      paste(missing, collapse = ", "), call. = FALSE
    )
  }

  # CAMPUS_ROLLUP: subject_course is unique inside the bundle's explicitly named
  # pooled planning market (currently ABQ + EA); campus components were already
  # reconciled into that market before publication and must stay combined here.
  courses <- unique(as.character(projections$subject_course))
  terms <- history %>%
    dplyr::distinct(term = history_term, term_label = history_term_label) %>%
    dplyr::arrange(dplyr::desc(term)) %>%
    dplyr::slice_head(n = n_terms) %>%
    dplyr::arrange(term) %>%
    dplyr::mutate(abbr = vapply(term, abbr_term, character(1)))

  slot <- function(course, column) {
    rows <- history[history$subject_course == course, , drop = FALSE]
    as.numeric(rows[[column]][match(terms$term, rows$history_term)])
  }
  first_day <- lapply(courses, slot, column = "actual_first_day")
  sections <- lapply(courses, slot, column = "scheduled_sections")
  text <- vapply(seq_along(courses), function(i) {
    if (nrow(terms) == 0L) return(NA_character_)
    paste(paste0(
      terms$abbr, " ",
      ifelse(is.finite(first_day[[i]]),
             format(round(first_day[[i]]), big.mark = ",", trim = TRUE),
             "\u2014"),
      " first day / ",
      ifelse(is.finite(sections[[i]]), sections[[i]], "\u2014"),
      " sections"
    ), collapse = "; ")
  }, character(1))

  list(
    data = tibble::tibble(
      course = courses,
      recent_first_day = first_day,
      recent_sections = sections,
      recent_terms = text
    ),
    columns = terms
  )
}


build_enrollment_projection_method_guide <- function(
    method_ids = names(CEDAR_ENROLLMENT_PROJECTION_METHODS)) {
  method_ids <- unique(as.character(method_ids))
  unknown <- setdiff(method_ids, names(CEDAR_ENROLLMENT_PROJECTION_METHODS))
  if (length(unknown) > 0L) {
    stop(
      "[enrollment-projections.R] Unknown projection methods in guide: ",
      paste(unknown, collapse = ", "),
      call. = FALSE
    )
  }

  guide <- CEDAR_ENROLLMENT_PROJECTION_METHOD_GUIDE
  guide <- guide[guide$method_id %in% method_ids, , drop = FALSE]
  guide$method_label <- unname(
    CEDAR_ENROLLMENT_PROJECTION_METHODS[guide$method_id]
  )
  guide <- guide[order(match(guide$method_id, method_ids)), , drop = FALSE]

  families <- lapply(
    seq_len(nrow(CEDAR_ENROLLMENT_PROJECTION_METHOD_FAMILIES)),
    function(i) {
      family <- CEDAR_ENROLLMENT_PROJECTION_METHOD_FAMILIES[i, , drop = FALSE]
      methods <- guide[guide$family_id == family$family_id[[1]], , drop = FALSE]
      if (nrow(methods) == 0L) return(NULL)
      list(
        id = family$family_id[[1]],
        label = family$family_label[[1]],
        description = family$description[[1]],
        selection_note = family$selection_note[[1]],
        methods = tibble::as_tibble(methods)
      )
    }
  )
  families <- Filter(Negate(is.null), families)

  family_count <- function(id) sum(guide$family_id == id)
  n_candidates <- nrow(guide)
  n_ideas <- length(unique(guide$concept_id))
  repeated_ideas <- sum(table(guide$concept_id) > 1L)

  list(
    n_candidates = n_candidates,
    n_ideas = n_ideas,
    summary = sprintf(
      paste0(
        "%d candidates: %d historical baselines, %d diagnostic upstream ",
        "indicators, and %d selectable anchored blend%s."
      ),
      n_candidates,
      family_count("observed_enrollment"),
      family_count("structural_demand"),
      family_count("anchored_upstream"),
      if (family_count("anchored_upstream") == 1L) "" else "s"
    ),
    overview = sprintf(
      paste0(
        "The %d labels represent %d underlying ideas. %d signals ",
        "appear twice: once raw and once as a 50/50 blend with ",
        "prior same-season enrollment."
      ),
      n_candidates, n_ideas, repeated_ideas
    ),
    selection_process = paste(
      "Prior same-season is the default for every course. Another candidate",
      "replaces it only after beating it by a margin on earlier aftcast terms",
      "the two share, and the rule is replayed at every past term with only",
      "the evidence available then, so the accuracy shown is what that rule",
      "would actually have delivered. Raw upstream indicators never win",
      "directly, and the anchored candidate must clear aftcast, coverage, and",
      "error gates before it can challenge."
    ),
    families = families
  )
}


build_enrollment_projection_view <- function(bundle, opt = list()) {
  validate_enrollment_projection_bundle(bundle)
  group_id <- as.character(opt$group_id %||% "all_saved")[[1]]
  group_courses <- enrollment_projection_group_courses(bundle, group_id)
  departments <- as.character(opt$departments %||% character(0))
  departments <- departments[!is.na(departments) & nzchar(departments)]
  courses <- as.character(opt$courses %||% character(0))
  courses <- courses[!is.na(courses) & nzchar(courses)]
  stability <- as.character(opt$stability %||% character(0))
  stability <- stability[!is.na(stability) & nzchar(stability)]
  depth <- as.character(opt$depth %||% character(0))
  depth <- depth[!is.na(depth) & nzchar(depth)]
  accuracy <- as.character(opt$accuracy %||% character(0))
  accuracy <- accuracy[!is.na(accuracy) & nzchar(accuracy)]
  attention_only <- isTRUE(opt$attention_only)
  projections <- bundle$projections %>%
    dplyr::filter(subject_course %in% .env$group_courses)
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
  if (length(stability) > 0L) {
    projections <- dplyr::filter(projections, stability %in% .env$stability)
  }
  if (length(depth) > 0L) {
    projections <- dplyr::filter(projections, depth %in% .env$depth)
  }
  if (length(accuracy) > 0L) {
    projections <- dplyr::filter(projections, accuracy %in% .env$accuracy)
  }
  projections <- projections %>%
    dplyr::mutate(
      # Rows a chair should actually look at; the rest can be planned at last
      # term's level.
      campus_fill_flag = projection_campus_fill_flags(
        dplyr::pick(dplyr::everything()), bundle$recent_campus_history
      ),
      attention = adjusted_saturated_prior %in% TRUE |
        adjusted_regime_alarm %in% TRUE | accuracy == "Low" |
        !is.na(campus_fill_flag)
    )
  if (attention_only) {
    projections <- dplyr::filter(projections, attention)
  }
  projections <- projections %>%
    dplyr::arrange(department, subject_course) %>%
    dplyr::mutate(
      # Why this method is live: the default, or the challenger evidence that
      # displaced it. The accuracy figures themselves live on the axes.
      selection_evidence = dplyr::case_when(
        method_id == "none" ~ "No applicable method",
        is.finite(selection_common_n) ~ paste0(
          "Beat prior same-season on ", selection_common_n,
          " earlier shared aftcasts (",
          projection_preview_percent(selection_challenger_wape), " vs ",
          projection_preview_percent(selection_default_wape), ")"
        ),
        TRUE ~ "Default; no challenger beat it on earlier aftcasts"
      ),
      axis_explanation = projection_axis_explanation(
        stability, depth, accuracy, n_backtests, wape,
        history_terms = history_terms,
        history_cv = history_cv,
        history_median_yoy = history_median_yoy_change,
        term_type, selection_pct_error_sd,
        capacity_constrained_history,
        n_capacity_reached, n_capacity_unreached, method_role,
        methods_disagree
      ),
      axis_brief = projection_axis_brief(
        stability, depth, accuracy,
        capacity_constrained = capacity_constrained_history,
        methods_disagree = methods_disagree,
        regime_alarm = dplyr::coalesce(adjusted_regime_alarm, FALSE)
      ),
      regime_alarm = dplyr::coalesce(adjusted_regime_alarm, FALSE),
      reliability_reading = projection_reliability_reading(
        accuracy, seat_consistency
      ),
      flags = projection_flags(dplyr::pick(dplyr::everything())),
      summary_sentence = projection_summary_sentence(
        dplyr::pick(dplyr::everything())
      ),
      # The range is in registrations, the unit sections are sized from.
      demand_range = dplyr::if_else(
        is.finite(projection_low) & is.finite(projection_high),
        paste0(
          format(round(projection_low), big.mark = ",", trim = TRUE),
          " to ",
          format(round(projection_high), big.mark = ",", trim = TRUE)
        ),
        NA_character_
      ),
      range_note = dplyr::if_else(
        is.na(demand_range), NA_character_,
        projection_range_seat_notes(
          dplyr::pick(dplyr::everything()), bundle$recent_history,
          bundle$model_config
        )
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
  history_summary <- build_enrollment_projection_history_summary(
    projections, history, n_terms = 4L
  )
  method_guide <- build_enrollment_projection_method_guide(
    bundle$model_config$projection_methods %||%
      names(CEDAR_ENROLLMENT_PROJECTION_METHODS)
  )

  table <- projections %>%
    dplyr::transmute(
      course = subject_course,
      department,
      planning_sections = recommended_sections,
      pressure_bump,
      pressure_bump_sections,
      pressure_bump_note,
      plan_feeder_adjustment,
      plan_feeder_sections,
      plan_feeder_note,
      expected_first_day = projected_first_day_equivalent,
      demand_range,
      range_note,
      flags,
      attention,
      projected_demand = projected_classlist_total,
      method = method_label,
      selection_evidence,
      summary_sentence,
      stability,
      stability_reason,
      history_terms,
      history_cv,
      history_median_yoy_change,
      depth,
      depth_reason,
      accuracy,
      accuracy_reason,
      seat_consistency,
      seat_consistency_reason,
      reliability_reading,
      axis_brief,
      axis_explanation,
      regime_alarm,
      why_uncertain
    ) %>%
    dplyr::left_join(history_summary$data, by = "course") %>%
    dplyr::select(
      # The decision first: sections to plan, how much of them the feeder
      # adjustment and the pressure bump added, the registrations they are
      # sized from with their range, first-day seats, the recent first days
      # and sections, and plain-language flags. The evidence axes follow; the
      # method and its evidence are for the course detail.
      course, department, planning_sections, pressure_bump,
      pressure_bump_sections, pressure_bump_note, plan_feeder_adjustment,
      plan_feeder_sections, plan_feeder_note, projected_demand,
      demand_range, range_note, expected_first_day,
      recent_first_day, recent_sections, recent_terms, flags,
      stability, stability_reason, depth, depth_reason,
      # Reliability (accuracy) sits beside seat consistency so the two read
      # together: low reliability with steady seats is the forecast's miss.
      accuracy, accuracy_reason, seat_consistency, seat_consistency_reason,
      reliability_reading,
      method, selection_evidence,
      summary_sentence, attention,
      axis_brief, axis_explanation, regime_alarm, why_uncertain
    )

  list(
    meta = list(
      target_term = bundle$target_term,
      target_term_label = fmt_term(bundle$target_term),
      season_label = switch(
        get_term_type(bundle$target_term),
        spring = "Spring", summer = "Summer", fall = "Fall"
      ),
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
      n_attention = sum(projections$attention),
      pressure_bump = projection_pressure_bump_summary(
        projections, bundle$model_config$pressure_bump_share
      ),
      plan_feeder = projection_plan_feeder_summary(
        projections, bundle$model_config$plan_feeder_change,
        bundle$model_config$plan_feeder_seasons
      ),
      # Bundle-wide, not filtered: the evidence for where error comes from is
      # every past forecast the rule would have published.
      error_sources = projection_error_sources_summary(
        bundle$backtests, bundle$model_config
      ),
      range_coverage = projection_range_coverage_summary(
        bundle$backtests, bundle$model_config
      ),
      target_schedule_as_of = bundle$target_schedule_as_of,
      summary_history_columns = history_summary$columns,
      bundle_path = attr(bundle, "bundle_path") %||% NA_character_
    ),
    projections = projections,
    table = table,
    delivery_components = bundle$delivery_components %>%
      dplyr::semi_join(
        dplyr::select(projections, market_id, subject_course),
        by = c("market_id", "subject_course")
      ),
    campus_history = bundle$recent_campus_history %>%
      dplyr::semi_join(
        dplyr::select(projections, market_id, subject_course),
        by = c("market_id", "subject_course")
      ),
    history = history,
    candidates = candidates,
    method_history = method_history,
    method_guide = method_guide
  )
}


enrollment_projection_filter_choices <- function(bundle, opt = list()) {
  scoped <- build_enrollment_projection_view(
    bundle,
    utils::modifyList(opt, list(
      courses = character(0), stability = character(0),
      depth = character(0), accuracy = character(0)
    ))
  )$projections
  list(
    groups = enrollment_projection_group_choices(),
    departments = sort(unique(stats::na.omit(scoped$department))),
    courses = sort(unique(stats::na.omit(scoped$subject_course))),
    stability = c("Stable", "Moderate", "Volatile", "Unrated"),
    depth = c("Deep", "Moderate", "Thin", "None"),
    accuracy = c("High", "Moderate", "Low", "Unrated")
  )
}


enrollment_projection_course_detail <- function(view, subject_course) {
  course <- as.character(subject_course %||% character(0))
  if (length(course) != 1L || is.na(course) || !nzchar(course)) return(NULL)
  current <- view$projections %>%
    dplyr::filter(subject_course == .env$course) %>%
    dplyr::slice_head(n = 1)
  if (nrow(current) == 0L) return(NULL)
  course_history <- view$history %>%
    dplyr::filter(subject_course == .env$course) %>%
    dplyr::arrange(recency_rank)
  list(
    current = current,
    plan_steps = projection_plan_steps(current),
    history = course_history,
    movement = build_enrollment_projection_movement_detail(course_history),
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


build_enrollment_projection_movement_detail <- function(history) {
  required <- c(
    "history_term", "history_term_label", "actual_classlist_total",
    "classlist_change", "scheduled_sections", "scheduled_capacity",
    "capacity_change", "capacity_usable", "capacity_reached", "source_term_label",
    "university_students", "university_student_change",
    "university_incoming_first_sem", "university_incoming_change",
    "market_students", "market_student_change", "source_outcomes_complete",
    "source_graded_students", "source_dfw_students", "source_dfw_rate",
    "source_dfw_next_term_repeaters", "source_dfw_repeater_share",
    "movement_context"
  )
  missing <- setdiff(required, names(history))
  if (length(missing) > 0L) {
    stop(
      "[enrollment-projections.R] Movement diagnostic needs column(s): ",
      paste(missing, collapse = ", "), call. = FALSE
    )
  }
  if (nrow(history) == 0L) {
    return(list(
      schedule_summary = "No comparable same-season history is available.",
      upstream_summary = "No upstream population comparison is available.",
      dfw_summary = "No prior-term DFW comparison is available.",
      caveat = paste(
        "These indicators are descriptive context. They do not establish",
        "that a schedule, population, or DFW change caused enrollment."
      ),
      data = tibble::tibble()
    ))
  }

  ordered <- history %>% dplyr::arrange(history_term)
  paired <- ordered %>%
    dplyr::filter(is.finite(classlist_change), is.finite(capacity_change))
  movement_correlation <- if (nrow(paired) >= 3L &&
                              stats::sd(paired$classlist_change) > 0 &&
                              stats::sd(paired$capacity_change) > 0) {
    stats::cor(paired$classlist_change, paired$capacity_change)
  } else {
    NA_real_
  }
  # A term counts only where first-day occupancy and capacity are both known;
  # capacity_reached is FALSE, not NA, for a term that cannot be judged.
  reached_n <- sum(ordered$capacity_reached %in% TRUE)
  usable_n <- sum(ordered$capacity_usable %in% TRUE)
  schedule_summary <- paste0(
    if (is.finite(movement_correlation)) {
      paste0(
        "Across ", nrow(paired), " comparable movements, enrollment and ",
        "scheduled-capacity changes had r = ",
        sprintf("%.2f", movement_correlation), ". "
      )
    } else {
      "There are too few comparable movements for a stable correlation. "
    },
    "First-day enrollment reached scheduled capacity (",
    scales::percent(CEDAR_FULL_FILL),
    " of seats or more) in ", reached_n, " of ",
    usable_n, " terms where first day and capacity are both known."
  )

  movement_row <- ordered %>%
    dplyr::filter(is.finite(classlist_change)) %>%
    dplyr::slice_max(abs(classlist_change), n = 1L, with_ties = FALSE)
  upstream_summary <- if (nrow(movement_row) == 0L) {
    "No prior same-season enrollment movement is available to compare."
  } else {
    paste0(
      "The largest observed move was ", movement_row$history_term_label[[1]],
      " (", projection_preview_percent(
        movement_row$classlist_change[[1]], signed = TRUE
      ), "). In the preceding ", movement_row$source_term_label[[1]],
      ", enrolled-student population changed ",
      projection_preview_percent(
        movement_row$university_student_change[[1]], signed = TRUE
      ), ", first-semester freshman population changed ",
      projection_preview_percent(
        movement_row$university_incoming_change[[1]], signed = TRUE
      ), ", and the projection market changed ",
      projection_preview_percent(
        movement_row$market_student_change[[1]], signed = TRUE
      ), "."
    )
  }

  dfw_summary <- if (nrow(movement_row) == 0L ||
                     !isTRUE(movement_row$source_outcomes_complete[[1]])) {
    paste(
      "Prior-term DFW is unavailable because that source term is not through",
      "the graded data edge."
    )
  } else {
    paste0(
      "For that move, ",
      projection_preview_integer(movement_row$source_dfw_students[[1]]),
      " students had a DFW in the course during the preceding term (",
      projection_preview_percent(movement_row$source_dfw_rate[[1]]), "). ",
      projection_preview_integer(
        movement_row$source_dfw_next_term_repeaters[[1]]
      ), " of them then enrolled in the course in ",
      movement_row$history_term_label[[1]], "—",
      projection_preview_percent(
        movement_row$source_dfw_repeater_share[[1]]
      ), " of that term's course enrollment."
    )
  }

  table <- ordered %>%
    dplyr::transmute(
      term = history_term_label,
      enrollment = round(actual_classlist_total),
      enrollment_change = classlist_change,
      sections = scheduled_sections,
      capacity = round(scheduled_capacity),
      capacity_change,
      source_term = source_term_label,
      university_students = round(university_students),
      university_change = university_student_change,
      incoming_first_sem = round(university_incoming_first_sem),
      incoming_change = university_incoming_change,
      market_students = round(market_students),
      market_change = market_student_change,
      prior_term_dfw = dplyr::if_else(
        source_outcomes_complete,
        paste0(
          projection_preview_integer(source_dfw_students), " / ",
          projection_preview_percent(source_dfw_rate)
        ),
        "Not graded"
      ),
      dfw_repeaters = dplyr::if_else(
        source_outcomes_complete,
        paste0(
          projection_preview_integer(source_dfw_next_term_repeaters), " / ",
          projection_preview_percent(source_dfw_repeater_share)
        ),
        "—"
      ),
      context = movement_context
    )

  list(
    schedule_summary = schedule_summary,
    upstream_summary = upstream_summary,
    dfw_summary = dfw_summary,
    caveat = paste(
      "These are upstream and post-hoc diagnostics, not causal attribution.",
      "Schedules may respond to anticipated demand, and DFW repeaters are",
      "observed after the following term begins."
    ),
    data = table
  )
}


build_enrollment_projection_method_history_plot <- function(
    method_history, selected_method_id = NULL) {
  required <- c(
    "subject_course", "term_type", "method_id", "method_label", "target_term",
    "applicable", "raw_projected_classlist_total", "actual_classlist_total",
    "actual_first_day", "actual_census", "actual_final_enrollment"
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
      target_term, actual_classlist_total, actual_first_day, actual_census,
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
      label = "Ever registered (model target)",
      column = "actual_classlist_total", color = unname(CEDAR_COLORS["green_dark"]),
      width = 4L, symbol = "circle"
    ),
    # Gaps where the class lists carry no status dates: an unknown first day
    # is drawn as missing, not as zero or as census.
    list(
      label = "First day (seats judged here)", column = "actual_first_day",
      color = unname(CEDAR_COLORS["amber"]), width = 3L, symbol = "triangle-up"
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
      `Feeder adjustment` = dplyr::if_else(
        plan_feeder_adjustment != 0, sprintf("%+.0f", plan_feeder_adjustment), "--"
      ),
      `Pressure bump` = dplyr::if_else(
        pressure_bump > 0, paste0("+", projection_preview_integer(pressure_bump)), "--"
      ),
      Planned = projection_preview_integer(planned_registrations),
      `Planned sections` = projection_preview_integer(recommended_sections),
      `First-day seats` = projection_preview_integer(projected_first_day_equivalent),
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
      Stability = stability,
      Depth = depth,
      Reliability = accuracy,
      `Seat consistency` = seat_consistency,
      `Why uncertain` = dplyr::if_else(
        accuracy %in% c("Unrated", "Low") | stability == "Volatile",
        why_uncertain, "--"
      ),
      Spine = projection_preview_integer(observed_baseline),
      Adjusted = projection_preview_integer(adjusted_projection),
      Floor = dplyr::case_when(
        adjusted_saturated_prior %in% TRUE & adjusted_floor_uplift > 0 ~
          paste0("Saturated; +", round(adjusted_floor_uplift)),
        adjusted_saturated_prior %in% TRUE ~ "Saturated; spine is a floor",
        adjusted_saturated_prior %in% FALSE ~ "Not saturated",
        TRUE ~ "Unknown"
      ),
      `Fall deltas` = dplyr::if_else(
        adjusted_applicable %in% TRUE,
        paste0(
          "repeat ", sprintf("%+.0f", adjusted_delta_repeat),
          dplyr::if_else(
            is.na(adjusted_sequence_courses), "",
            paste0(", sequence ", sprintf("%+.0f", adjusted_delta_sequence))
          ),
          ", feeder ", sprintf("%+.0f", adjusted_delta_feeder)
        ),
        "--"
      ),
      `Regime check` = dplyr::if_else(
        adjusted_regime_alarm %in% TRUE, "Review", "--"
      ),
      `Feeder adjustment basis` = plan_feeder_note,
      `Pressure bump basis` = pressure_bump_note,
      Recommendation = recommendation
    )
  history_table <- history %>%
    dplyr::transmute(
      Course = subject_course,
      Term = history_term_label,
      `Aftcast method` = dplyr::coalesce(aftcast_method_label, "--"),
      Aftcast = projection_preview_integer(aftcast_classlist_total),
      `Raw error` = projection_preview_percent(aftcast_pct_error, signed = TRUE),
      `Error assessment` = dplyr::case_when(
        !aftcast_applicable | !is.finite(aftcast_classlist_total) ~ "--",
        dplyr::coalesce(aftcast_capacity_censored, FALSE) ~
          "Capacity-bounded",
        TRUE ~ "Observed"
      ),
      `Ever registered` = projection_preview_integer(actual_classlist_total),
      `First day` = projection_preview_integer(actual_first_day),
      Census = projection_preview_integer(actual_census),
      `Final / last day` = projection_preview_integer(actual_final_enrollment),
      Sections = projection_preview_integer(scheduled_sections),
      Capacity = projection_preview_integer(scheduled_capacity),
      `First-day fill` = projection_preview_percent(first_day_fill),
      `Capacity status` = dplyr::case_when(
        !is.finite(actual_first_day) ~ "First day unknown",
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
      "Class-list demand", "Pressure bump", "Planned", "Planned sections",
      "First-day seats", "Aftcasts", "Raw WAPE",
      "Uncensored WAPE", "Bias", "Spine", "Adjusted"
    )
  )
  history_lines <- projection_preview_markdown_table(
    history_table,
    right_align = c(
      "Ever registered", "First day", "Census", "Final / last day",
      "Sections", "Capacity", "First-day fill",
      "Aftcast", "Raw error"
    )
  )
  error_sources <- projection_error_sources_summary(
    bundle$backtests, bundle$model_config
  )
  error_lines <- projection_preview_markdown_table(
    error_sources$table %>%
      dplyr::transmute(
        Source = label,
        `Past forecasts` = projection_preview_integer(folds),
        `Average error` = projection_preview_percent(wape),
        `Share of error` = projection_preview_percent(share_of_error)
      ),
    right_align = c("Past forecasts", "Average error", "Share of error")
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
    "## Where past forecast error came from (whole bundle)",
    error_sources$sentence,
    "",
    error_lines,
    "",
    paste(
      "Historical predictions are leakage-safe aftcasts of the method the",
      "rolling selection rule would have published that term; they are not",
      "claims about a forecast published at that time."
    ),
    paste(
      "Capacity-bounded means overprojection cannot be measured because",
      paste0(
        "first-day enrollment reached scheduled capacity (",
        scales::percent(CEDAR_FULL_FILL),
        " of seats or more); it is not a claim of zero error."
      )
    )
  )
}


print_enrollment_projection_preview <- function(bundle, courses = NULL) {
  output <- format_enrollment_projection_preview(bundle, courses = courses)
  cat(output, sep = "\n")
  invisible(output)
}
