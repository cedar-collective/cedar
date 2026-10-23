# Offline, readable views and refreshed source candidates for shared rules.

format_shared_requirement_preview <- function(reference) {
  lines <- c(paste0("# Shared bachelor requirements · ", reference$bundle$catalog_year), "",
    "Readable paraphrases of the saved catalog rules. Transcribed does not mean advisor-approved.",
    reference$bundle$runtime_status %||% "This reference bundle is not yet used to schedule courses or evaluate students.", "",
    "## How the layers combine", "", paste0("- ", unlist(reference$bundle$composition_policy)))
  for (set in reference$sets) {
    coverage <- switch(set$coverage, selected_sections = "Selected catalog sections",
      requirements_and_enumerated_course_memberships = "Requirements and explicitly listed course memberships",
      not_located_on_checked_overview = "Overview checked; no common bachelor completion block located")
    lines <- c(lines, "", paste0("## ", set$title), "", paste0("Coverage: ", coverage, "."), "", unlist(set$notes))
    for (rule in shared_requirement_nodes(set$rules)) {
      links <- vapply(rule$source_refs, function(ref) {
        source <- reference$provenance$sources[[ref$source_id]]
        paste0("[", source$title, "](", source$catalog_url, ")")
      }, character(1))
      lines <- c(lines, "", paste0(strrep("  ", rule$depth), "- **", rule$label, "** (`", rule$rule_id, "`): ", rule$statement,
        " Source: ", paste(unique(links), collapse = "; "), "."))
    }
    if (!length(set$rules)) lines <- c(lines, "", "No shared bachelor rule was located on the checked overview. This is a coverage limit, not an exemption.")
    for (attention in set$attention) lines <- c(lines, "", paste0("**Source question — ", attention$case_id, ":** ", attention$statement))
  }
  paste(lines, collapse = "\n")
}

#' Refresh the pinned source URLs, never the authored rules or program graph
capture_shared_requirement_sources <- function(reference, directory, fetch = fetch_public_source) {
  if (dir.exists(directory)) stop("[shared-requirements.R] Choose a new capture directory")
  sources <- lapply(reference$provenance$sources, function(source) {
    receipt <- capture_public_source(source$url, directory, source$kind, source$key,
      fetch = fetch, document_format = if (source$kind == "landing") "html" else "json")
    utils::modifyList(source, receipt)
  })
  manifest <- reference$provenance
  manifest$sources <- sources
  manifest$capture_directory <- directory
  manifest$status <- "source_candidate_only"
  write_source_json(manifest, file.path(directory, "source-manifest.json"))
  manifest
}
