# Offline source acquisition. It never writes institution degree/planning files.

catalog_capture_settings <- function(source, credentials, fields, catalog_id, include_courses) {
  rows <- function(x) lapply(seq_len(nrow(x)), function(i) as.list(x[i, , drop = FALSE]))
  list(source = source, credentials = rows(credentials), fields = rows(fields),
    requested_catalog_id = catalog_id, include_courses = include_courses)
}

catalog_capture_manifest <- function(directory, require_complete = TRUE, verify_sources = TRUE) {
  manifest <- read_source_json(file.path(directory, "source-manifest.json"))
  if (!identical(manifest$schema_version, "1.0.0") ||
      (require_complete && !identical(manifest$status, "complete"))) {
    stop("[catalog-capture.R] Unsupported or incomplete catalog capture: ", directory)
  }
  if (verify_sources) for (receipt in manifest$requests) read_captured_source(receipt, directory, json = FALSE)
  manifest
}

catalog_record_classification <- function(record, initial, source, credentials) {
  type <- catalog_named_value(record, "degreeType")
  if (nzchar(type)) {
    i <- match(type, credentials$degree_type)
    if (is.na(i)) stop("[catalog-capture.R] Unclassified full-record degree type: ", type)
    return(credentials$scope[i])
  }
  exclusion_fields <- strsplit(source$untyped_exclusion_fields, "|", fixed = TRUE)[[1]]
  if (any(vapply(exclusion_fields, function(k) !is.null(record[[k]]) &&
    is.character(record[[k]]) && nzchar(record[[k]]), logical(1)))) return("excluded")
  if (identical(catalog_scalar(record, source$level_field), source$graduate_level)) return("excluded")
  if (identical(catalog_scalar(record, source$level_field), source$undergraduate_level)) {
    return("undergraduate_candidate") # Retain and flag an undergraduate whose credential is unspecified.
  }
  initial
}

catalog_record_references <- function(record) {
  if (is.character(record)) {
    return(unlist(lapply(record[grepl("#/courses/", record, fixed = TRUE)], catalog_course_references), recursive = FALSE))
  }
  if (!is.list(record)) return(list())
  unlist(lapply(record, catalog_record_references), recursive = FALSE)
}

#' Capture all classified undergraduate degrees, their specializations, and
#' optionally the transitive closure of linked course records. Resume keeps the
#' original edition/index frozen and verifies every already saved response.
capture_degree_catalog <- function(source, credentials, fields, directory,
                                   catalog_id = NULL, include_courses = TRUE,
                                   resume = FALSE, fetch = fetch_public_source, pause = 0.1) {
  if (!identical(source$provider, "kuali")) stop("[catalog-capture.R] Unsupported catalog provider")
  if (!all(c("field", "phase") %in% names(fields)) || !nrow(fields) ||
      anyNA(fields) || any(!nzchar(fields$field)) || anyDuplicated(fields$field) ||
      any(!fields$phase %in% c("admission", "degree", "prerequisite", "corequisite", "info"))) {
    stop("[catalog-capture.R] Invalid source field/phase mapping")
  }
  required <- c("landing_url", "api_base", "level_field", "undergraduate_level", "graduate_level", "untyped_exclusion_fields")
  if (any(!required %in% names(source)) || any(!nzchar(unlist(source[required])))) {
    stop("[catalog-capture.R] Incomplete catalog source configuration")
  }
  if (!is.null(catalog_id) && !grepl("^[A-Za-z0-9_-]+$", catalog_id)) stop("[catalog-capture.R] Invalid catalog ID")
  settings <- catalog_capture_settings(source, credentials, fields, catalog_id, include_courses)
  settings_hash <- source_sha256(source_json_bytes(settings))
  manifest_path <- file.path(directory, "source-manifest.json")
  if (resume) {
    manifest <- catalog_capture_manifest(directory, require_complete = FALSE)
    if (manifest$status == "complete" || !identical(manifest$settings_sha256, settings_hash)) {
      stop("[catalog-capture.R] Resume requires an incomplete capture with identical configuration")
    }
  } else {
    if (dir.exists(directory)) stop("[catalog-capture.R] Output directory already exists: ", directory)
    dir.create(directory, recursive = TRUE)
    manifest <- list(schema_version = "1.0.0", status = "incomplete", settings = settings,
      settings_sha256 = settings_hash, started_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC"),
      requests = list())
    write_source_json(manifest, manifest_path)
  }
  get_source <- function(kind, key, url, format = "json") {
    name <- paste(kind, key, sep = ":")
    receipt <- manifest$requests[[name]]
    if (is.null(receipt)) {
      receipt <- capture_public_source(url, directory, kind, key, fetch, format)
      manifest$requests[[name]] <<- receipt
      write_source_json(manifest, manifest_path)
      if (pause > 0) Sys.sleep(pause)
    } else if (!identical(receipt$url, url)) stop("[catalog-capture.R] Cached request URL disagrees")
    read_captured_source(receipt, directory, json = format == "json")
  }
  landing <- get_source("landing", "page", source$landing_url, "html")
  if (is.null(catalog_id)) {
    pattern <- "window[.]catalogId[[:space:]]*=[[:space:]]*['\"]([A-Za-z0-9_-]+)['\"]"
    match <- regmatches(landing, regexec(pattern, landing, perl = TRUE))[[1]]
    if (length(match) != 2L) stop("[catalog-capture.R] Landing page lacks one explicit catalog ID; supply --catalog-id")
    catalog_id <- match[2]
  }
  base <- sub("/+$", "", source$api_base)
  get_source("catalogs", "published", paste0(base, "/public/catalogs"))
  edition <- get_source("edition", catalog_id, paste0(base, "/public/catalogs/", catalog_id))
  if (!identical(edition$`_id`, catalog_id) || !nzchar(catalog_scalar(edition, "title"))) stop("[catalog-capture.R] Invalid edition response")
  manifest$catalog_id <- catalog_id; manifest$catalog_title <- edition$title
  for (kind in c("programs", "courses", "specializations")) {
    get_source("schema", kind, paste0(base, "/schema/", catalog_id, "/", kind))
  }
  index_url <- paste0(base, "/programs/", catalog_id)
  index <- get_source("index", "programs", index_url)
  inventory <- catalog_program_scope(index, credentials)
  programs <- list()
  candidates <- which(inventory$scope %in% c("undergraduate_degree", "unclassified"))
  message("[catalog-capture.R] ", edition$title, ": ", nrow(inventory), " index entries; ",
    sum(inventory$scope == "undergraduate_degree"), " declared undergraduate degrees; ",
    sum(inventory$scope == "unclassified"), " unlabeled records to classify.")
  for (i in candidates) {
    id <- inventory$program_id[i]
    record <- get_source("program", id, paste0(base, "/program/", catalog_id, "/", id))
    if (!identical(record$pid, id) || !identical(record$id, index[[i]]$id)) {
      stop("[catalog-capture.R] Program identity/revision disagrees with index: ", id)
    }
    inventory$scope[i] <- catalog_record_classification(record, inventory$scope[i], source, credentials)
    if (inventory$scope[i] %in% c("undergraduate_degree", "undergraduate_candidate")) programs[[id]] <- record
    if (match(i, candidates) %% 20L == 0L) message("[catalog-capture.R] Classified ", match(i, candidates), "/", length(candidates), " program records.")
  }
  if (!length(programs)) stop("[catalog-capture.R] No undergraduate degrees found; capture remains incomplete")
  if (include_courses) {
    references <- catalog_record_references(programs)
    pending <- unique(vapply(references, function(x) x$key, character(1)))
    visited <- character()
    while (length(pending)) {
      key <- pending[1]; pending <- pending[-1]
      if (key %in% visited) next
      path <- if (startsWith(key, "view/")) paste0("/course/byId/", catalog_id, "/", substring(key, 6))
              else paste0("/course/", catalog_id, "/", key)
      course <- get_source("course", key, paste0(base, path))
      if (!nzchar(catalog_scalar(course, "pid"))) stop("[catalog-capture.R] Course response lacks identity: ", key)
      visited <- c(visited, key)
      references <- catalog_record_references(course)
      pending <- setdiff(unique(c(pending, vapply(references, function(x) x$key, character(1)))), visited)
      if (length(visited) %% 50L == 0L) message("[catalog-capture.R] Captured ", length(visited), " linked courses; ", length(pending), " pending.")
    }
  }
  final_index <- get_source("index", "programs-check", index_url)
  validate_catalog_index(final_index)
  identity <- function(x) sort(vapply(x, function(r) paste(r$pid, r$id, sep = ":"), character(1)))
  if (!identical(identity(index), identity(final_index))) stop("[catalog-capture.R] Program index changed during capture; start a new capture")
  utils::write.csv(inventory, file.path(directory, "program-inventory.csv"), row.names = FALSE, na = "")
  manifest$program_ids <- names(programs)
  manifest$inventory <- lapply(seq_len(nrow(inventory)), function(i) as.list(inventory[i, , drop = FALSE]))
  manifest$status <- "complete"
  manifest$finished_at <- format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC")
  write_source_json(manifest, manifest_path)
  message("[catalog-capture.R] Complete: ", length(programs), " undergraduate degree/candidate records, ",
    sum(vapply(manifest$requests, function(x) x$kind == "course", logical(1))), " linked course records.")
  invisible(directory)
}
