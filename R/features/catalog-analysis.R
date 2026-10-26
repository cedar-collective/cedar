# Reproducible offline extraction and review reports from frozen source captures.

catalog_config_rows <- function(rows) do.call(rbind, lapply(rows, function(x) as.data.frame(x, stringsAsFactors = FALSE)))

write_catalog_jsonl <- function(records, path) {
  lines <- vapply(records, function(x) as.character(jsonlite::toJSON(x,
    auto_unbox = TRUE, null = "null", na = "null", digits = NA)), character(1))
  writeLines(lines, path, useBytes = TRUE)
}

catalog_extractor_provenance <- function() {
  functions <- list(extract_catalog_record = extract_catalog_record,
    extract_catalog_rule_tree = extract_catalog_rule_tree, catalog_html_document = catalog_html_document,
    catalog_node_text = catalog_node_text, catalog_html_text = catalog_html_text,
    catalog_course_references = catalog_course_references, catalog_source_links = catalog_source_links,
    catalog_entity_references = catalog_entity_references, catalog_program_references = catalog_program_references,
    resolve_catalog_milestones = resolve_catalog_milestones, catalog_milestone_rows = catalog_milestone_rows,
    catalog_rule_rows = catalog_rule_rows,
    catalog_section_rows = catalog_section_rows, catalog_rule_structure = catalog_rule_structure,
    catalog_canonical_value = catalog_canonical_value, catalog_scalar = catalog_scalar,
    catalog_named_value = catalog_named_value, catalog_config_rows = catalog_config_rows,
    catalog_source_issue_rows = catalog_source_issue_rows,
    catalog_parse_credit_range = catalog_parse_credit_range,
    catalog_credit_mentions_in_text = catalog_credit_mentions_in_text,
    catalog_credit_conflict_rows = catalog_credit_conflict_rows,
    write_catalog_jsonl = write_catalog_jsonl, source_json_bytes = source_json_bytes,
    analyze_degree_catalog = analyze_degree_catalog)
  list(version = "1.3.0", r_version = R.version.string, locale = Sys.getlocale(),
    packages = lapply(stats::setNames(c("xml2", "jsonlite", "digest"), c("xml2", "jsonlite", "digest")),
      function(x) as.character(utils::packageVersion(x))),
    functions = lapply(functions, function(x) paste(deparse(x, width.cutoff = 500L), collapse = "\n")))
}

#' Re-extract frozen responses without network or paid model calls
analyze_degree_catalog <- function(directory, output = file.path(directory, "analysis")) {
  manifest <- catalog_capture_manifest(directory)
  if (dir.exists(output)) stop("[catalog-analysis.R] Analysis output already exists: ", output)
  requests <- manifest$requests
  load <- function(kind, key) {
    receipt <- requests[[paste(kind, key, sep = ":")]]
    if (is.null(receipt)) stop("[catalog-analysis.R] Missing captured request: ", kind, ":", key)
    read_captured_source(receipt, directory)
  }
  edition <- load("edition", manifest$catalog_id)
  schemas <- stats::setNames(lapply(c("programs", "courses", "specializations"),
    function(x) load("schema", x)), c("programs", "courses", "specializations"))
  fields <- catalog_config_rows(manifest$settings$fields)
  records <- list()
  for (id in unlist(manifest$program_ids, use.names = FALSE)) {
    program <- load("program", id)
    receipt <- requests[[paste0("program:", id)]]
    record <- extract_catalog_record(program, "programs", receipt, edition, schemas, fields)
    record$parent_program_id <- ""
    records[[length(records) + 1L]] <- record
    for (i in seq_along(program$specializations)) {
      receipt$json_pointer <- paste0("/specializations/", i - 1L)
      record <- extract_catalog_record(program$specializations[[i]], "specializations", receipt, edition, schemas, fields)
      record$parent_program_id <- id
      records[[length(records) + 1L]] <- record
    }
  }
  course_receipts <- Filter(function(x) x$kind == "course", requests)
  for (receipt in course_receipts) {
    record <- extract_catalog_record(read_captured_source(receipt, directory), "courses", receipt, edition, schemas, fields)
    record$parent_program_id <- ""
    records[[length(records) + 1L]] <- record
  }
  # One specialization may be published under several parents; one course may
  # be linked by pid and revision id. Keep every relationship in records.jsonl.
  # A comparison accepts a shared identity only when its extracted sections agree.
  records <- resolve_catalog_milestones(records)
  section_frames <- lapply(records, catalog_section_rows)
  sections <- do.call(rbind, section_frames)
  keys <- paste(sections$entity, sections$field)
  signature <- paste(keys, sections$text, sections$structure_sha256, sections$html_sha256, sep = "\r")
  if (anyDuplicated(keys[!duplicated(signature)])) {
    stop("[catalog-analysis.R] Conflicting revisions for the same entity/field; captured sources require review")
  }
  sections <- sections[!duplicated(keys), ]
  rule_frames <- unlist(lapply(records, function(record) lapply(record$sections,
    function(section) catalog_rule_rows(record, section))), recursive = FALSE)
  rules <- if (length(rule_frames)) do.call(rbind, rule_frames) else data.frame()
  if (nrow(rules)) rules <- rules[!duplicated(paste(rules$node_id, rules$source_sha256)), ]
  milestones <- catalog_milestone_rows(records, rules)
  queue <- if (nrow(rules)) rules[rules$operator == "condition" & rules$phase != "info", ] else data.frame()
  dir.create(output, recursive = TRUE)
  write_catalog_jsonl(records, file.path(output, "records.jsonl"))
  utils::write.csv(sections, file.path(output, "sections.csv"), row.names = FALSE, na = "")
  utils::write.csv(rules, file.path(output, "rule-nodes.csv"), row.names = FALSE, na = "")
  utils::write.csv(milestones, file.path(output, "milestones.csv"), row.names = FALSE, na = "")
  write_catalog_jsonl(lapply(seq_len(nrow(queue)), function(i) as.list(queue[i, , drop = FALSE])), file.path(output, "review-queue.jsonl"))
  inventory <- catalog_config_rows(manifest$inventory)
  source_issues <- rbind(catalog_source_issue_rows(records, inventory, requests, sections),
    catalog_credit_conflict_rows(records))
  utils::write.csv(source_issues, file.path(output, "source-issues.csv"), row.names = FALSE, na = "")
  status <- inventory[inventory$scope %in% c("undergraduate_degree", "undergraduate_candidate", "unclassified"), ]
  status$sections <- vapply(status$program_id, function(id) sum(sections$entity == paste0("programs:", id) & !sections$phase %in% c("metadata", "info")), integer(1))
  status$degree_sections <- vapply(status$program_id, function(id) sum(sections$entity == paste0("programs:", id) & sections$phase == "degree"), integer(1))
  status$review_items <- vapply(status$program_id, function(id) {
    if (!nrow(queue)) return(0L)
    sum(queue$entity == paste0("programs:", id))
  }, integer(1))
  utils::write.csv(status, file.path(output, "program-coverage.csv"), row.names = FALSE, na = "")
  provenance <- catalog_extractor_provenance()
  write_source_json(provenance, file.path(output, "extractor-source.json"))
  summary <- list(schema_version = "1.0.0", extractor_version = provenance$version, catalog_id = manifest$catalog_id,
    extractor_sha256 = source_sha256(source_json_bytes(provenance)),
    catalog_title = manifest$catalog_title, scope = "undergraduate_degrees",
    source_directory = normalizePath(directory), include_courses = manifest$settings$include_courses,
    settings_sha256 = manifest$settings_sha256,
    configuration_sha256 = source_sha256(source_json_bytes(manifest$settings[setdiff(names(manifest$settings), "requested_catalog_id")])),
    source_manifest_sha256 = source_sha256(readBin(file.path(directory, "source-manifest.json"), "raw", n = file.info(file.path(directory, "source-manifest.json"))$size)),
    sections_sha256 = source_sha256(readBin(file.path(output, "sections.csv"), "raw", n = file.info(file.path(output, "sections.csv"))$size)),
    counts = list(degrees = sum(inventory$scope == "undergraduate_degree"),
      undergraduate_candidates = sum(inventory$scope == "undergraduate_candidate"),
      unclassified = sum(inventory$scope == "unclassified"),
      specializations = sum(vapply(records, function(x) x$kind == "specializations", logical(1))),
      course_requests = length(course_receipts), sections = nrow(sections), rule_nodes = nrow(rules),
      review_items = nrow(queue), source_issues = nrow(source_issues), milestones = nrow(milestones),
      milestone_uses = sum(rules$operator == "milestone")),
    review_status = "unreviewed")
  escape <- function(x) gsub("[|\r\n]", " ", x)
  lines <- c(paste0("# Catalog scan: ", manifest$catalog_title), "",
    sprintf("%d declared undergraduate degrees; %d undergraduate candidates; %d still unclassified.", summary$counts$degrees, summary$counts$undergraduate_candidates, summary$counts$unclassified),
    sprintf("%d embedded specializations; %d linked course requests; %d narrative review items.", summary$counts$specializations, summary$counts$course_requests, summary$counts$review_items), "",
    sprintf("%d shared status milestones; %d cited uses. See milestones.csv and the milestone_id links in rule-nodes.csv. These preserve required standing/admission status, not inferred credits, semester placement, or admission awards.", nrow(milestones), summary$counts$milestone_uses), "",
    sprintf("%d source-query/coverage flags need review; see source-issues.csv. Source flags are preserved without inferring cancellation, scheduling, or a replacement course.", nrow(source_issues)), "",
    "Every extraction is unreviewed. Recognized lists and minimum-grade constraints are preserved without creating an interpretation flag for their headings. Flags identify unsupported extraction, not necessarily a problem in the catalog. Prose, query-based pools, linked policies and source conflicts still need review. Referenced courses are not automatically prerequisite edges.", "",
    "A missing field means not supplied in the published record, not no requirement. Concentrations retain their parent program. No institution runtime files are changed.", "",
    "Review this archive in CEDAR: Admin > Data & Usage > Catalog Review. Inspect each flagged item with its full captured section and source evidence; validate parsed sections too. Download the filtered queue to coordinate review. Viewing the report or page does not approve requirements.", "",
    "| Program | Credential | Scope | Requirement sections | Narrative review items |", "|---|---|---|---:|---:|")
  for (i in seq_len(nrow(status))) lines <- c(lines, sprintf("| %s | %s | %s | %d | %d |",
    escape(status$title[i]), escape(status$degree_type[i]), status$scope[i], status$sections[i], status$review_items[i]))
  writeLines(lines, file.path(output, "REPORT.md"), useBytes = TRUE)
  artifacts <- c("records.jsonl", "sections.csv", "rule-nodes.csv", "review-queue.jsonl",
    "program-coverage.csv", "source-issues.csv", "milestones.csv", "extractor-source.json", "REPORT.md")
  summary$files <- stats::setNames(lapply(artifacts, function(name) {
    path <- file.path(output, name)
    source_sha256(readBin(path, "raw", n = file.info(path)$size))
  }), artifacts)
  write_source_json(summary, file.path(output, "analysis-manifest.json"))
  message("[catalog-analysis.R] Extracted ", nrow(sections), " sections; ", nrow(queue), " narrative items need review. Report: ", file.path(output, "REPORT.md"))
  invisible(output)
}

read_catalog_analysis <- function(path, read_sections = TRUE) {
    meta <- read_source_json(file.path(path, "analysis-manifest.json"))
    if (!length(meta$files) || any(!grepl("^[A-Za-z0-9_.-]+$", names(meta$files)))) {
      stop("[catalog-analysis.R] Analysis artifact manifest is missing or invalid")
    }
    for (name in names(meta$files)) {
      artifact <- file.path(path, name)
      if (!file.exists(artifact) || !identical(source_sha256(readBin(artifact, "raw", n = file.info(artifact)$size)), meta$files[[name]])) {
        stop("[catalog-analysis.R] Missing or modified analysis artifact: ", artifact)
      }
    }
    section_path <- file.path(path, "sections.csv")
    if (!identical(meta$schema_version, "1.0.0") ||
        !identical(source_sha256(readBin(section_path, "raw", n = file.info(section_path)$size)), meta$sections_sha256)) {
      stop("[catalog-analysis.R] Unsupported or modified analysis: ", path)
    }
    list(meta = meta, sections = if (read_sections) utils::read.csv(section_path, colClasses = "character", check.names = FALSE) else NULL)
}

compare_degree_catalog_scans <- function(before, after, output) {
  old <- read_catalog_analysis(before); new <- read_catalog_analysis(after)
  if (!identical(old$meta$scope, new$meta$scope) || !identical(old$meta$include_courses, new$meta$include_courses)) {
    stop("[catalog-analysis.R] Comparisons require the same program and course capture scope")
  }
  if (dir.exists(output)) stop("[catalog-analysis.R] Comparison output already exists: ", output)
  changes <- compare_catalog_sections(old$sections, new$sections)
  extractor_changed <- !identical(old$meta$extractor_sha256, new$meta$extractor_sha256)
  configuration_changed <- !identical(old$meta$configuration_sha256, new$meta$configuration_sha256)
  dir.create(output, recursive = TRUE)
  utils::write.csv(changes, file.path(output, "changes.csv"), row.names = FALSE, na = "")
  write_source_json(list(before = old$meta, after = new$meta, changed_sections = nrow(changes),
    extractor_changed = extractor_changed, configuration_changed = configuration_changed), file.path(output, "comparison-manifest.json"))
  lines <- c("# Catalog language and structure comparison", "", paste("Before:", old$meta$catalog_title),
    paste("After:", new$meta$catalog_title), "", paste(nrow(changes), "changed sections."),
    paste("Extractor/code/packages changed:", extractor_changed),
    paste("Scope/extraction configuration changed:", configuration_changed), "",
    "Changes are unreviewed. Wording-only does not establish equivalent requirements. Check configuration/extractor provenance before attributing a difference to the catalog.")
  for (i in seq_len(nrow(changes))) {
    text <- c(changes$before_text[i], changes$after_text[i])
    runs <- regmatches(paste(text, collapse = "\n"), gregexpr("`+", paste(text, collapse = "\n")))[[1]]
    fence <- strrep("`", max(c(3L, nchar(runs) + 1L)))
    lines <- c(lines, "", paste("##", changes$title[i], "—", changes$field[i]), changes$change[i],
      "", paste0(fence, "diff"), paste0("- ", text[1]), paste0("+ ", text[2]), fence,
      paste("Before source:", changes$before_source_url[i]), paste("After source:", changes$after_source_url[i]))
  }
  writeLines(lines, file.path(output, "CHANGES.md"), useBytes = TRUE)
  message("[catalog-analysis.R] ", nrow(changes), " changed sections. Report: ", file.path(output, "CHANGES.md"))
  invisible(output)
}
