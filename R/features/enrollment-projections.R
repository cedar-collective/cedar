# Building, fingerprinting and finding enrollment projection bundles.
#
# The same builder is used by the persistent R lab, the standalone publisher,
# and future CEDAR tabs. UI code should consume its saved bundle, not reproduce
# any calculation here. Everything that only reads a saved bundle for the page
# lives in enrollment-projection-view.R, outside the model source.

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
    "R/branches/enrollment-projection-inputs.R",
    "R/branches/enrollment-projection-candidates.R",
    "R/branches/enrollment-projection-context.R",
    "R/branches/enrollment-projection-backtests.R",
    "R/branches/enrollment-projection-history.R",
    "R/branches/enrollment-projection-plan.R",
    "R/branches/enrollment-projection-error-sources.R",
    "R/branches/enrollment-projection-bundle.R",
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
