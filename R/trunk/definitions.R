# Shared, versioned explanatory records. This is metadata, not a second
# implementation of the calculations. Both Shiny and Jekyll read the same YAML.
# Historical versions are retained so an older app can link to its own rules.

validate_definition_registry <- function(registry) {
  scalar_text <- function(x) {
    is.character(x) && length(x) == 1L && !is.na(x) && nzchar(trimws(x))
  }
  fail <- function(message) stop("Definition registry: ", message, call. = FALSE)
  if (!identical(registry$schema_version, 1L)) fail("unsupported schema_version")
  if (!is.list(registry$definitions) || !length(registry$definitions)) {
    fail("definitions must be a nonempty list")
  }
  required <- c("version", "title", "summary", "population", "unit",
                "numerator", "denominator", "campus", "time_window",
                "exclusions", "guide")
  ids <- character()
  for (definition in registry$definitions) {
    if (!scalar_text(definition$id) ||
        !grepl("^[a-z][a-z0-9-]*$", definition$id)) fail("invalid id")
    ids <- c(ids, definition$id)
    if (!scalar_text(definition$current_version)) fail("missing current_version")
    if (!is.list(definition$versions) || !length(definition$versions)) fail("missing versions")
    versions <- character()
    for (record in definition$versions) {
      if (!all(vapply(required, function(key) scalar_text(record[[key]]), logical(1)))) {
        fail(paste(definition$id, "has missing or empty required fields"))
      }
      if (!grepl("^[0-9]+\\.[0-9]+\\.[0-9]+$", record$version)) fail("invalid version")
      if (!grepl("^users/[a-z0-9-]+(#[a-z0-9-]+)?$", record$guide)) fail("invalid guide")
      versions <- c(versions, record$version)
      if (!is.character(record$limitations) || !length(record$limitations) ||
          !all(vapply(record$limitations, scalar_text, logical(1)))) fail("missing limitations")
      if (!is.list(record$implementation) || !length(record$implementation)) fail("missing implementation")
      for (source in record$implementation) {
        if (!scalar_text(source$file) || !grepl("^R/[a-z-]+/[a-z0-9-]+\\.R$", source$file) ||
            !is.character(source$functions) || !length(source$functions) ||
            !all(vapply(source$functions, scalar_text, logical(1)))) fail("invalid implementation reference")
      }
    }
    if (anyDuplicated(versions)) fail(paste(definition$id, "has duplicate versions"))
    if (!definition$current_version %in% versions) fail("current_version does not exist")
  }
  if (anyDuplicated(ids)) fail("duplicate definition ids")
  invisible(registry)
}

# ── Section concepts ──────────────────────────────────────────────────────────
# docs/_data/concepts.yml: one plain paragraph a section, keyed <page>.<section>.
# The app shows it at the top of the section's "How this is counted" dialog.

read_section_concepts <- function(path) {
  if (!file.exists(path)) stop("Section concepts not found: ", path, call. = FALSE)
  file <- read_utf8_yaml(path)
  if (!identical(file$schema_version, 1L)) stop("Section concepts: unsupported schema_version", call. = FALSE)
  concepts <- file$concepts
  ok <- is.list(concepts) && length(concepts) > 0L && !is.null(names(concepts)) &&
    all(grepl("^[a-z][a-z0-9-]*\\.[a-z][a-z0-9-]*$", names(concepts))) && !anyDuplicated(names(concepts)) &&
    all(vapply(concepts, function(x) is.character(x) && length(x) == 1L && nzchar(trimws(x)), logical(1)))
  if (!ok) stop("Section concepts: every entry is <page>.<section> with one paragraph of text", call. = FALSE)
  vapply(concepts, trimws, character(1))
}

#' A section's concept paragraph; an unknown id is an error, never blank text
cedar_section_concept <- function(id, concepts = CEDAR_SECTION_CONCEPTS) {
  if (length(id) != 1L || is.na(id) || !id %in% names(concepts)) {
    stop("Unknown section concept: ", paste(id, collapse = ", "), " (docs/_data/concepts.yml)", call. = FALSE)
  }
  concepts[[id]]
}

read_definition_registry <- function(path) {
  if (!file.exists(path)) stop("Definition registry not found: ", path, call. = FALSE)
  registry <- read_utf8_yaml(path)
  validate_definition_registry(registry)
  registry
}

cedar_definition <- function(id, version = NULL, registry = CEDAR_DEFINITIONS) {
  ids <- vapply(registry$definitions, `[[`, character(1), "id")
  if (length(id) != 1L || is.na(id) || !id %in% ids) {
    stop("Unknown definition id: ", paste(id, collapse = ", "), call. = FALSE)
  }
  definition <- registry$definitions[[match(id, ids)]]
  if (is.null(version)) version <- definition$current_version
  versions <- vapply(definition$versions, `[[`, character(1), "version")
  if (length(version) != 1L || is.na(version) || !version %in% versions) {
    stop("Unknown definition version for ", id, ": ", paste(version, collapse = ", "), call. = FALSE)
  }
  record <- definition$versions[[match(version, versions)]]
  record$id <- id
  record$anchor <- paste0(id, "-v", gsub(".", "-", version, fixed = TRUE))
  record
}

cedar_definition_summary <- function(id, version = NULL) {
  cedar_definition(id, version)$summary
}
