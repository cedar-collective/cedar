# Comparisons describe captured language/structure, never certify equivalence.

catalog_rule_structure <- function(node) {
  structure <- list(operator = node$operator, minimum = node$minimum,
    courses = lapply(node$course_references, function(x) gsub("[[:space:]]", "", x$code)),
    children = lapply(node$children, catalog_rule_structure))
  # Optional constraint added by extractor 1.1.0. Do not change fingerprints
  # of older grade-free trees simply by introducing a new optional field.
  if (!is.null(node$minimum_grade)) structure$minimum_grade <- node$minimum_grade
  if (!is.null(node$milestone)) structure$milestone <- node$milestone[c("type", "relation", "value")]
  structure
}

catalog_canonical_value <- function(value) {
  if (!is.list(value)) return(value)
  if (!is.null(names(value))) value <- value[order(names(value))]
  lapply(value, catalog_canonical_value)
}

catalog_section_rows <- function(record) {
  entity <- paste(record$kind, record$pid, sep = ":")
  metadata <- catalog_canonical_value(record$metadata)
  metadata_text <- as.character(jsonlite::toJSON(metadata, auto_unbox = TRUE, digits = NA))
  make_row <- function(field, label, text, structure_hash, html_hash, review, phase) {
    data.frame(entity = entity, title = record$title, field = field, label = label, phase = phase, text = text,
      structure_sha256 = structure_hash, html_sha256 = html_hash, requires_review = review,
      source_url = record$source$url, source_sha256 = record$source$sha256, stringsAsFactors = FALSE)
  }
  rows <- list(make_row("@metadata", "Metadata", metadata_text,
    source_sha256(charToRaw(metadata_text)), source_sha256(charToRaw(metadata_text)), FALSE, "metadata"))
  for (section in record$sections) {
    rows[[length(rows) + 1L]] <- make_row(section$field, section$label, section$text,
      source_sha256(source_json_bytes(catalog_rule_structure(section$tree))),
      section$html_sha256, section$requires_review, section$phase)
  }
  do.call(rbind, rows)
}

#' Language and explicit list-structure differences, keyed by stable source pid
#'
#' Revision ids and list positions are evidence, not matching keys. Formatting
#' changes are separate; wording changes on a condition always require review.
compare_catalog_sections <- function(before, after) {
  required <- c("entity", "title", "field", "label", "text", "structure_sha256", "html_sha256", "source_sha256", "source_url")
  for (table in list(before, after)) {
    if (!all(required %in% names(table)) || anyDuplicated(paste(table$entity, table$field))) {
      stop("[catalog-comparison.R] Missing fields or ambiguous entity/field keys")
    }
  }
  old_key <- paste(before$entity, before$field, sep = "|")
  new_key <- paste(after$entity, after$field, sep = "|")
  rows <- list()
  for (key in union(old_key, new_key)) {
    i <- match(key, old_key); j <- match(key, new_key)
    old <- if (is.na(i)) NULL else before[i, ]
    new <- if (is.na(j)) NULL else after[j, ]
    kind <- if (is.null(old)) "added" else if (is.null(new)) "removed" else if (old$text != new$text) {
      if (old$field == "@metadata") "metadata_changed" else if (old$structure_sha256 != new$structure_sha256) "structure_and_wording_changed" else "wording_changed"
    } else if (old$structure_sha256 != new$structure_sha256) "structure_changed"
      else if (old$html_sha256 != new$html_sha256) "formatting_only" else "unchanged"
    if (kind == "unchanged") next
    identity <- if (is.null(new)) old else new
    rows[[length(rows) + 1L]] <- data.frame(entity = identity$entity, title = identity$title,
      field = identity$field, change = kind, before_text = if (is.null(old)) "" else old$text,
      after_text = if (is.null(new)) "" else new$text,
      before_source_url = if (is.null(old)) "" else old$source_url,
      after_source_url = if (is.null(new)) "" else new$source_url,
      before_source_sha256 = if (is.null(old)) "" else old$source_sha256,
      after_source_sha256 = if (is.null(new)) "" else new$source_sha256,
      review_status = "unreviewed", stringsAsFactors = FALSE)
  }
  if (length(rows)) return(do.call(rbind, rows))
  as.data.frame(stats::setNames(rep(list(character()), 11), c("entity", "title", "field", "change",
    "before_text", "after_text", "before_source_url", "after_source_url",
    "before_source_sha256", "after_source_sha256", "review_status")))
}
