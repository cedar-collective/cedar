# Local catalog review. No network, model calls, or edits to source/runtime files.

list_catalog_review_scans <- function(root) {
  empty <- data.frame(scan_id = character(), label = character(), title = character(), stringsAsFactors = FALSE)
  if (!dir.exists(root)) return(empty) # An optional archive has an explicit UI empty state.
  root <- normalizePath(root)
  paths <- list.files(root, pattern = "^analysis-manifest[.]json$", recursive = TRUE, full.names = TRUE)
  if (!length(paths)) return(empty)
  rows <- lapply(paths, function(path) {
    meta <- read_source_json(path)
    if (!identical(meta$schema_version, "1.0.0") || !identical(meta$scope, "undergraduate_degrees")) {
      stop("[catalog-review.R] Unsupported catalog analysis: ", path)
    }
    id <- substring(normalizePath(dirname(path)), nchar(root) + 2L)
    data.frame(scan_id = id, label = paste(meta$catalog_title, "·", id), title = meta$catalog_title,
      stringsAsFactors = FALSE)
  })
  rows <- do.call(rbind, rows)
  rows[order(file.info(paths)$mtime, decreasing = TRUE), ]
}

catalog_review_directory <- function(root, scan_id) {
  scans <- list_catalog_review_scans(root)
  selected <- match(scan_id, scans$scan_id)
  if (length(selected) != 1L || is.na(selected)) stop("[catalog-review.R] Select an available catalog scan")
  file.path(root, scans$scan_id[selected])
}

catalog_review_capture_directory <- function(directory, meta) {
  # Whole archives can be moved into a container. The sibling capture is used
  # only when its manifest is exactly the one this analysis cites.
  candidates <- unique(c(dirname(directory), meta$source_directory))
  matches <- vapply(candidates, function(dir) {
    path <- file.path(dir, "source-manifest.json")
    file.exists(path) && identical(source_sha256(readBin(path, "raw", n = file.info(path)$size)), meta$source_manifest_sha256)
  }, logical(1))
  if (!any(matches)) stop("[catalog-review.R] The matching captured source archive is unavailable; keep the analysis with its source-manifest.json and sources folder")
  candidates[which(matches)[1]]
}

# Recheck actual artifact bytes before a cache lookup, not only their recorded
# hashes or modification dates. Corruption must fail even on a warm cache.
catalog_review_cache_key <- function(root, scan_id) {
  directory <- catalog_review_directory(root, scan_id)
  analysis <- read_catalog_analysis(directory, read_sections = FALSE)
  capture <- catalog_review_capture_directory(directory, analysis$meta)
  # Bump when review payload shape, item interpretation or source checks change.
  list(version = 3L, directory = normalizePath(directory), source_directory = normalizePath(capture),
    analysis = analysis$meta)
}

#' Verify the derived review artifacts; verify original source bytes on Inspect
load_catalog_review <- function(root, scan_id) {
  directory <- catalog_review_directory(root, scan_id)
  analysis <- read_catalog_analysis(directory)
  meta <- analysis$meta
  source_directory <- catalog_review_capture_directory(directory, meta)
  manifest <- catalog_capture_manifest(source_directory, verify_sources = FALSE)
  records <- lapply(readLines(file.path(directory, "records.jsonl"), warn = FALSE),
    jsonlite::fromJSON, simplifyVector = FALSE)
  csv <- function(name) utils::read.csv(file.path(directory, name), colClasses = "character", check.names = FALSE)
  # Apply the same source checks to every frozen analysis, including schema
  # 1.0.0 analyses produced before source-issues.csv was added to the report.
  # This is always computed from the saved records, never a network refresh.
  issues <- catalog_source_issue_rows(records, catalog_config_rows(manifest$inventory), manifest$requests, analysis$sections)
  nodes <- csv("rule-nodes.csv")
  milestone_support <- "milestone_id" %in% names(nodes)
  if (milestone_support && (!"milestones.csv" %in% names(meta$files) || is.null(meta$counts$milestones))) {
    stop("[catalog-review.R] Milestone analysis lacks its verified definition artifact or count")
  }
  items <- build_catalog_review_items(records, nodes, issues)
  milestones <- if (milestone_support) csv("milestones.csv") else NULL # Older immutable analyses predate this artifact.
  programs <- records[vapply(records, function(x) x$kind == "programs", logical(1))]
  choices <- stats::setNames(vapply(programs, function(x) x$pid, character(1)),
    vapply(programs, function(x) x$title, character(1)))
  list(meta = meta, manifest = manifest, source_directory = source_directory, directory = directory,
    records = records, items = items, milestones = milestones, milestone_support = milestone_support,
    source_check_count = nrow(issues), coverage = csv("program-coverage.csv"),
    programs = choices[order(names(choices))])
}

catalog_review_detail <- function(payload, item_id) {
  row <- payload$items[payload$items$item_id == item_id, ]
  if (nrow(row) != 1L) stop("[catalog-review.R] Select one available review item")
  record <- catalog_review_record(payload$records, row$entity, row$source_sha256)
  document <- read_captured_source(record$source, payload$source_directory)
  source <- source_json_pointer(document, row$source_pointer)
  section <- Filter(function(x) x$field == row$field, record$sections)
  tree <- if (length(section)) paste(catalog_review_tree_text(section[[1]]$tree), collapse = "\n") else ""
  landing <- sub("#.*$", "", payload$manifest$settings$source$landing_url)
  # Embedded concentrations are read in their parent program's published page.
  route <- if (record$kind == "specializations") paste0("programs/", record$parent_program_id) else
    paste0(record$kind, "/", record$pid)
  admission_evidence <- list(); admission_policy_missing <- FALSE
  if (nzchar(row$milestone_id)) {
    definition <- payload$milestones[payload$milestones$milestone_id == row$milestone_id, ]
    if (nrow(definition) != 1L) stop("[catalog-review.R] Milestone definition is missing or ambiguous")
    if (definition$type == "program_admission") {
      target <- catalog_review_record(payload$records, paste0("programs:", definition$target_program_id), definition$definition_source_sha256)
      target_source <- read_captured_source(target$source, payload$source_directory)
      admission_evidence <- lapply(Filter(function(x) x$phase == "admission", target$sections), function(x)
        list(label = x$label, value = source_json_pointer(target_source, x$source_pointer),
          pointer = x$source_pointer, sha256 = target$source$sha256,
          catalog_url = paste0(landing, "#/programs/", target$pid)))
      admission_policy_missing <- !length(admission_evidence)
    }
  }
  list(item = row, source = source, is_html = is.character(source) && length(source) == 1L,
    admission_evidence = admission_evidence,
    admission_policy_missing = admission_policy_missing,
    tree = tree, catalog_url = paste0(landing, "#/", route), captured_at = record$source$fetched_at,
    catalog_title = payload$meta$catalog_title,
    section_text = if (length(section)) section[[1]]$text else row$excerpt)
}
