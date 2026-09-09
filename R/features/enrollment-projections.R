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
    graded_through_term = graded_through_term
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
    built_at = built_at
  )
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
    length(stability), length(depth), length(accuracy),
    length(n_backtests), length(wape), length(history_terms),
    length(history_cv), length(history_median_yoy),
    length(coverage_rate), length(term_type), length(selection_basis),
    length(pct_error_sd), length(capacity_constrained),
    length(selection_uses_uncensored), length(n_capacity_reached),
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
    n <- dplyr::coalesce(n_backtests[[i]], 0L)
    error <- wape[[i]]
    variation <- pct_error_sd[[i]]
    coverage <- coverage_rate[[i]]
    season <- switch(
      term_type[[i]], spring = "Spring", summer = "Summer", fall = "Fall",
      "same-term-type"
    )
    basis_suffix <- if (identical(selection_basis[[i]], "Unconstrained-term WAPE")) {
      "WAPE (unconstrained terms)"
    } else {
      "WAPE (all terms)"
    }

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
        " aftcasts stand behind the selected method."
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
      "Depth: no comparable aftcast for the selected method."
    )

    accuracy_text <- switch(
      accuracy[[i]],
      Close = paste0(
        "Accuracy: aftcasts landed within ",
        scales::percent(error, accuracy = 0.1), " ", basis_suffix,
        if (is.finite(variation)) paste0(
          ", varying ", scales::percent(variation, accuracy = 0.1),
          " term to term"
        ) else "", "."
      ),
      Fair = paste0(
        "Accuracy: aftcasts averaged ",
        scales::percent(error, accuracy = 0.1), " ", basis_suffix,
        " — usable for planning, not for a precise seat count."
      ),
      Poor = paste0(
        "Accuracy: aftcasts averaged ",
        scales::percent(error, accuracy = 0.1), " ", basis_suffix,
        ". Treat this projection as a rough scale, not a number to schedule to."
      ),
      "Accuracy: not enough comparable aftcasts to measure how close past forecasts were."
    )

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
          "Accuracy describes fit to observed enrollment, not proof of ",
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
    paste(c(stability_text, depth_text, accuracy_text, caveats), collapse = " ")
  }, character(1))
}


# Compact one-line summary for a table cell: the three axes in reading order.
projection_axis_brief <- function(stability, depth, accuracy,
                                  capacity_constrained = FALSE,
                                  methods_disagree = FALSE,
                                  method_role = NA_character_,
                                  coverage_rate = NA_real_) {
  size <- max(
    length(stability), length(depth), length(accuracy),
    length(capacity_constrained), length(methods_disagree),
    length(method_role), length(coverage_rate)
  )
  stability <- rep_len(as.character(stability), size)
  depth <- rep_len(as.character(depth), size)
  accuracy <- rep_len(as.character(accuracy), size)
  capacity_constrained <- rep_len(as.logical(capacity_constrained), size)
  methods_disagree <- rep_len(as.logical(methods_disagree), size)
  method_role <- rep_len(as.character(method_role), size)
  coverage_rate <- rep_len(as.numeric(coverage_rate), size)

  vapply(seq_len(size), function(i) {
    qualifier <- dplyr::case_when(
      isTRUE(capacity_constrained[[i]]) ~ "capacity-limited",
      isTRUE(methods_disagree[[i]]) ~ "methods differ",
      identical(method_role[[i]], "anchored_upstream") &&
        is.finite(coverage_rate[[i]]) && coverage_rate[[i]] < 0.60 ~
        "limited upstream coverage",
      TRUE ~ NA_character_
    )
    parts <- c(
      paste0(stability[[i]], " history"),
      paste0(depth[[i]], " evidence"),
      paste0(accuracy[[i]], " aftcasts"),
      qualifier
    )
    paste(parts[!is.na(parts)], collapse = " \u00b7 ")
  }, character(1))
}


build_enrollment_projection_history_summary <- function(
    projections, history, n_terms = 4L) {
  n_terms <- as.integer(n_terms)
  if (length(n_terms) != 1L || is.na(n_terms) || n_terms < 1L) {
    stop(
      "[enrollment-projections.R] Summary history terms must be positive.",
      call. = FALSE
    )
  }

  column_names <- paste0("history_", seq_len(n_terms))
  # CAMPUS_ROLLUP: subject_course is unique inside the bundle's explicitly named
  # pooled planning market (currently ABQ + EA); campus components were already
  # reconciled into that market before publication and must stay combined here.
  summary <- projections %>%
    dplyr::distinct(course = subject_course)
  for (column_name in column_names) summary[[column_name]] <- NA_character_

  if (nrow(summary) == 0L || nrow(history) == 0L) {
    return(list(data = summary, columns = tibble::tibble(
      name = character(), term = integer(), term_label = character(),
      header = character()
    )))
  }

  terms <- history %>%
    dplyr::distinct(term = history_term, term_label = history_term_label) %>%
    dplyr::arrange(dplyr::desc(term)) %>%
    dplyr::slice_head(n = n_terms) %>%
    dplyr::arrange(term) %>%
    dplyr::mutate(
      name = column_names[seq_len(dplyr::n())],
      header = paste0(
        vapply(term, abbr_term, character(1)), ": first day / sects"
      )
    )

  for (i in seq_len(nrow(terms))) {
    column_name <- terms$name[[i]]
    values <- history %>%
      dplyr::filter(history_term == terms$term[[i]]) %>%
      dplyr::transmute(
        course = subject_course,
        value = dplyr::if_else(
          is.finite(actual_classlist_total) & !is.na(scheduled_sections),
          paste0(
            format(
              round(actual_classlist_total), big.mark = ",",
              scientific = FALSE, trim = TRUE
            ),
            " / ", scheduled_sections
          ),
          NA_character_
        )
      )
    summary <- summary %>%
      dplyr::select(-dplyr::all_of(column_name)) %>%
      dplyr::left_join(values, by = "course")
    names(summary)[names(summary) == "value"] <- column_name
  }

  list(
    data = summary,
    columns = terms %>%
      dplyr::select(name, term, term_label, header)
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
        "indicators, and %d selectable anchored blends."
      ),
      n_candidates,
      family_count("observed_enrollment"),
      family_count("structural_demand"),
      family_count("anchored_upstream")
    ),
    overview = sprintf(
      paste0(
        "The %d labels represent %d underlying ideas. %d upstream signals ",
        "appear twice: once raw for diagnosis and once as a 50/50 blend with ",
        "prior same-season enrollment."
      ),
      n_candidates, n_ideas, repeated_ideas
    ),
    selection_process = paste(
      "CEDAR does not treat every row as an equal choice. It first identifies",
      "the best observed-enrollment baseline and the best eligible anchored",
      "candidate, then compares those two. Raw upstream indicators never win",
      "directly. Anchored candidates must clear minimum aftcast, coverage, and",
      "error requirements before they can compete."
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
          projection_preview_percent(selection_wape), " ", selection_basis
        )
      ),
      axis_explanation = projection_axis_explanation(
        stability, depth, accuracy, n_backtests, wape,
        history_terms = history_terms,
        history_cv = history_cv,
        history_median_yoy = history_median_yoy_change,
        coverage_rate = coverage_rate,
        term_type, selection_basis, selection_pct_error_sd,
        capacity_constrained_history, selection_uses_uncensored,
        n_capacity_reached, n_capacity_unreached, method_role,
        methods_disagree
      ),
      axis_brief = projection_axis_brief(
        stability, depth, accuracy,
        capacity_constrained = capacity_constrained_history,
        methods_disagree = methods_disagree,
        method_role = method_role,
        coverage_rate = coverage_rate
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
      projected_demand = projected_classlist_total,
      expected_census = projected_census_equivalent,
      planning_sections = recommended_sections,
      method = method_label,
      aftcast_accuracy,
      stability,
      stability_reason,
      history_terms,
      history_cv,
      history_median_yoy_change,
      depth,
      depth_reason,
      accuracy,
      accuracy_reason,
      axis_brief,
      axis_explanation,
      demand_signal,
      why_uncertain
    ) %>%
    dplyr::left_join(history_summary$data, by = "course") %>%
    dplyr::select(
      # The three evidence axes sit immediately after the projection they
      # qualify, not at the far right past four history columns and the method
      # description. A reader scanning for "which of these can we actually
      # forecast" should not have to scroll horizontally to find out.
      course, department, projected_demand, expected_census,
      stability, stability_reason, depth, depth_reason,
      accuracy, accuracy_reason,
      dplyr::all_of(paste0("history_", 1:4)), planning_sections,
      method, aftcast_accuracy,
      axis_brief, axis_explanation, demand_signal, why_uncertain
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
      summary_history_columns = history_summary$columns,
      bundle_path = attr(bundle, "bundle_path") %||% NA_character_
    ),
    projections = projections,
    table = table,
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
    accuracy = c("Close", "Fair", "Poor", "Unrated")
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
    "capacity_change", "capacity_reached", "source_term_label",
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
  reached_n <- sum(ordered$capacity_reached %in% TRUE, na.rm = TRUE)
  usable_n <- sum(!is.na(ordered$capacity_reached))
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
    "Registration reached scheduled capacity in ", reached_n, " of ",
    usable_n, " terms with usable capacity."
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
      Stability = stability,
      Depth = depth,
      Accuracy = accuracy,
      `Why uncertain` = dplyr::if_else(
        accuracy %in% c("Unrated", "Poor") | stability == "Volatile",
        why_uncertain, "--"
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
