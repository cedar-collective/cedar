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
