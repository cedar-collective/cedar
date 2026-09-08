# Automatic publication policy and semantic freshness checks. No model fitting
# happens here; the feature builder compares these before running the analyses.

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
  target <- config$target_term
  if (identical(target, "next_spring")) {
    target <- add_term(settled)
    while (get_term_type(target) != "spring") target <- add_term(target)
  }
  cutoff <- config$as_of_term
  if (identical(cutoff, "latest_settled")) cutoff <- settled
  if (!valid_term(target) || !valid_term(cutoff) ||
      get_term_type(as.integer(target)) != "spring" ||
      as.integer(cutoff) >= as.integer(target) || as.integer(cutoff) > settled) {
    stop("[projections] Require a Spring target and an earlier settled cutoff.",
         call. = FALSE)
  }
  if (!is.character(config$group) || length(config$group) != 1L ||
      is.na(config$group) || !config$group %in% names(CEDAR_ENROLLMENT_PROJECTION_GROUPS)) {
    stop("[projections] Unknown automatic refresh course group.", call. = FALSE)
  }
  list(target_term = as.integer(target), as_of_term = as.integer(cutoff),
       group = config$group)
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
enrollment_projection_model_drift <- function(
    output_dir = file.path(getwd(), "output", "projections"),
    base_dir = getwd()) {
  path <- find_latest_enrollment_projection_bundle(output_dir)
  if (is.null(path)) return("no saved projection bundle")

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

  current <- enrollment_projection_model_provenance(base_dir)

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
