# Automatic publication policy and semantic freshness checks. No model fitting
# happens here; the feature builder compares these before running the analyses.

# Resolve the refresh policy into one scope PER PUBLISHED TARGET.
#
# Returns a list of scopes, not a single one: the policy may name several target
# terms (typically the next Fall and the next Spring), and each is published as
# its own bundle with its own signature and its own rebuild decision. A Spring
# rebuild must never force a Fall one.
#
# Targets are returned nearest-first, so an interrupted refresh leaves the
# soonest planning horizon published rather than the furthest.
resolve_enrollment_projection_refresh <- function(config, students) {
  fields <- c("enabled", "target_term", "as_of_term", "group")
  if (!is.list(config) || anyDuplicated(names(config)) ||
      !setequal(names(config), fields) ||
      !is.logical(config$enabled) || length(config$enabled) != 1L ||
      is.na(config$enabled)) {
    stop("[projections] Invalid automatic refresh configuration.", call. = FALSE)
  }
  if (!config$enabled) return(NULL)
  settled <- cedar_data_edges(students)$last_enrolled_complete
  if (length(settled) != 1L || is.na(settled)) {
    stop("[projections] Cannot determine a settled enrollment edge.", call. = FALSE)
  }
  valid_term <- function(x) {
    length(x) == 1L && !is.na(x) &&
      grepl("^[0-9]{4}(10|60|80)$", as.character(x))
  }
  # "next_spring" / "next_fall" resolve against the settled edge, never the
  # clock and never the newest (possibly still filling) registration term.
  resolve_target <- function(value) {
    season <- switch(as.character(value),
                     next_spring = "spring", next_fall = "fall", NULL)
    if (is.null(season)) return(suppressWarnings(as.integer(value)))
    term <- add_term(settled)
    while (get_term_type(term) != season) term <- add_term(term)
    as.integer(term)
  }
  requested <- config$target_term
  if (is.list(requested)) requested <- unlist(requested, use.names = FALSE)
  if (length(requested) == 0L) {
    stop("[projections] At least one target term is required.", call. = FALSE)
  }
  cutoff <- config$as_of_term
  if (identical(cutoff, "latest_settled")) cutoff <- settled
  if (!is.character(config$group) || length(config$group) != 1L ||
      is.na(config$group) || !config$group %in% names(CEDAR_ENROLLMENT_PROJECTION_GROUPS)) {
    stop("[projections] Unknown automatic refresh course group.", call. = FALSE)
  }
  targets <- vapply(requested, resolve_target, integer(1), USE.NAMES = FALSE)
  for (target in targets) {
    if (!valid_term(target) || !valid_term(cutoff) ||
        !get_term_type(as.integer(target)) %in% c("spring", "fall") ||
        as.integer(cutoff) >= as.integer(target) || as.integer(cutoff) > settled) {
      stop("[projections] Require Spring or Fall targets and an earlier settled cutoff.",
           call. = FALSE)
    }
  }
  lapply(sort(unique(targets)), function(target) {
    list(target_term = as.integer(target), as_of_term = as.integer(cutoff),
         group = config$group)
  })
}


projection_canonical_input <- function(value) {
  if (is.data.frame(value)) {
    value <- as.data.frame(value[, sort(names(value)), drop = FALSE])
    value[] <- lapply(value, projection_canonical_input)
    value <- dplyr::arrange(value, dplyr::across(dplyr::everything()))
    rownames(value) <- NULL
    return(value)
  }
  if (is.list(value)) return(lapply(value, projection_canonical_input))
  if (is.factor(value)) return(as.character(value))
  value
}


enrollment_projection_refresh_signature <- function(inputs, opt, force_courses,
                                                     provenance) {
  # Grades beyond the enrollment cutoff cannot affect the bounded outcomes.
  if (length(inputs$graded_through_term) == 1L &&
      !is.na(inputs$graded_through_term)) {
    inputs$graded_through_term <- min(inputs$graded_through_term,
                                    inputs$enrollment_through_term)
  }
  list(
    version = 1L,
    model_version = provenance$model_version,
    schema_version = provenance$schema_version,
    source_hashes = provenance$source_hashes,
    config = opt,
    force_courses = sort(unique(force_courses)),
    inputs_sha256 = digest::digest(projection_canonical_input(inputs),
                                   algo = "sha256", serialize = TRUE)
  )
}


# Has the projection MODEL changed since the saved bundle was built?
#
# Deliberately a different question from enrollment_projection_rebuild_reason(),
# which compares the whole refresh signature — model, scope, config AND a hash
# of the prepared inputs. Computing that hash means loading and preparing the
# data, which is the expensive half of a refresh. Most deploys touch no model
# source at all, so a deploy-time gate has to answer "did the model move?"
# without paying for "did the data move?".
#
# The saved signature keeps model_version, schema_version and per-file
# source_hashes as separate fields precisely so the model half can be compared
# on its own. This reads the saved bundle and hashes the 13 files named by
# enrollment_projection_model_source_files(); it never touches a CEDAR table.
#
# Returns NULL when the deployed model matches the one that produced the
# bundle, otherwise a human-readable reason. Anything unreadable, invalid, or
# predating freshness tracking counts as drift: failing towards a rebuild is
# correct, because the alternative is serving a page built by unknown code.
# Every published season is checked. A Spring bundle built by the current model
# says nothing about whether the Fall bundle beside it is stale, so drift in any
# saved bundle rebuilds -- the refresh then decides per target whether the work
# is actually needed.
enrollment_projection_model_drift <- function(
    output_dir = file.path(getwd(), "output", "projections"),
    base_dir = getwd()) {
  saved <- find_enrollment_projection_bundles(output_dir)
  if (nrow(saved) == 0L) return("no saved projection bundle")

  current <- enrollment_projection_model_provenance(base_dir)
  for (index in seq_len(nrow(saved))) {
    reason <- .enrollment_projection_bundle_drift(
      saved$path[[index]], current
    )
    if (!is.null(reason)) {
      return(paste0(fmt_term(saved$target_term[[index]]), ": ", reason))
    }
  }
  NULL
}


.enrollment_projection_bundle_drift <- function(path, current) {
  bundle <- tryCatch(
    read_enrollment_projection_bundle(path),
    error = function(error) error
  )
  if (inherits(bundle, "error")) {
    return(paste("saved bundle is unreadable or invalid:",
                 conditionMessage(bundle)))
  }

  saved <- bundle$source_fingerprint$refresh
  if (is.null(saved)) return("saved bundle predates model-provenance tracking")

  if (!identical(saved$schema_version, current$schema_version)) {
    return(paste0(
      "schema version changed: saved ", saved$schema_version,
      ", deployed ", current$schema_version
    ))
  }
  if (!identical(saved$model_version, current$model_version)) {
    return(paste0(
      "model version changed: saved ", saved$model_version,
      ", deployed ", current$model_version
    ))
  }

  saved_hashes <- saved$source_hashes
  current_hashes <- current$source_hashes
  # Name the files, not just the fact of a mismatch. A deploy log that says
  # "model source changed" sends someone diffing thirteen files by hand.
  added <- setdiff(names(current_hashes), names(saved_hashes))
  removed <- setdiff(names(saved_hashes), names(current_hashes))
  shared <- intersect(names(saved_hashes), names(current_hashes))
  altered <- shared[!vapply(shared, function(file) {
    identical(saved_hashes[[file]], current_hashes[[file]])
  }, logical(1))]

  changed <- c(altered, added, removed)
  if (length(changed) > 0L) {
    return(paste0(
      "model source changed: ", paste(sort(changed), collapse = ", ")
    ))
  }

  NULL
}


enrollment_projection_rebuild_reason <- function(bundle, signature) {
  if (is.null(bundle)) return("saved bundle missing or unreadable")
  invalid <- tryCatch({
    validate_enrollment_projection_bundle(bundle)
    NULL
  }, error = function(error) conditionMessage(error))
  if (!is.null(invalid)) return(paste("saved bundle incompatible:", invalid))
  saved <- bundle$source_fingerprint$refresh
  if (is.null(saved)) return("saved bundle predates automatic freshness tracking")
  if (!identical(saved, signature)) return("model, scope, or prepared data changed")
  NULL
}
