# Catalog status gates are not course edges or student eligibility decisions.

#' Resolve explicit program links to stable captured program identities
#' Uncaptured targets stay conditions; no matching by names or inferred codes.
resolve_catalog_milestones <- function(records) {
  programs <- Filter(function(x) x$kind == "programs", records)
  aliases <- list()
  for (program in programs) {
    keys <- c(program$pid, if (nzchar(program$revision_id)) paste0("view/", program$revision_id))
    for (key in keys) {
      if (!is.null(aliases[[key]]) && aliases[[key]] != program$pid) {
        stop("[catalog-milestones.R] Ambiguous captured program link: ", key)
      }
      aliases[[key]] <- program$pid
    }
  }
  visit <- function(node) {
    if (!is.null(node$milestone) && node$milestone$type == "program_admission") {
      target <- aliases[[node$program_references[[1]]$key]]
      if (is.null(target)) {
        node$operator <- "condition"
        node$milestone$resolution <- "target_not_captured"
      } else {
        node$operator <- "milestone"
        node$milestone$value <- target
        node$milestone$id <- paste0("program_admission:", target)
        node$milestone$resolution <- "captured_program"
      }
    }
    node$children <- lapply(node$children, visit)
    node$requires_review <- node$operator == "condition" ||
      any(vapply(node$children, function(x) isTRUE(x$requires_review), logical(1)))
    node
  }
  lapply(records, function(record) {
    record$sections <- lapply(record$sections, function(section) {
      section$tree <- visit(section$tree)
      section$requires_review <- isTRUE(section$tree$requires_review) || section$phase == "unclassified"
      section
    })
    record
  })
}

#' One shared milestone definition; rule-nodes.csv carries each cited use
#' Counts describe catalog references, not enrollment or campus analytics.
catalog_milestone_rows <- function(records, rules) {
  uses <- rules[rules$operator == "milestone", ]
  columns <- c("milestone_id", "type", "relation", "value", "label", "rule_uses", "course_records",
    "target_program_id", "target_program_title", "admission_text", "admission_pointers",
    "definition_source_url", "definition_source_sha256", "review_status")
  rows <- lapply(unique(uses$milestone_id), function(id) {
    nodes <- uses[uses$milestone_id == id, ]
    identity <- unique(nodes[, c("milestone_type", "milestone_relation", "milestone_value")])
    if (nrow(identity) != 1L || !nzchar(id)) stop("[catalog-milestones.R] Conflicting milestone identity")
    target <- NULL; admissions <- list()
    if (identity$milestone_type == "program_admission") {
      targets <- Filter(function(x) x$kind == "programs" && x$pid == identity$milestone_value, records)
      if (length(targets) != 1L) stop("[catalog-milestones.R] Admission milestone lacks one captured program")
      target <- targets[[1]]
      admissions <- Filter(function(x) x$phase == "admission", target$sections)
    }
    data.frame(milestone_id = id, type = identity$milestone_type, relation = identity$milestone_relation,
      value = identity$milestone_value, label = nodes$milestone_label[1], rule_uses = nrow(nodes),
      course_records = length(unique(nodes$entity[startsWith(nodes$entity, "courses:")])),
      target_program_id = if (is.null(target)) "" else target$pid,
      target_program_title = if (is.null(target)) "" else target$title,
      admission_text = paste(vapply(admissions, function(x) x$text, character(1)), collapse = "\n\n"),
      admission_pointers = paste(vapply(admissions, function(x) x$source_pointer, character(1)), collapse = " | "),
      definition_source_url = if (is.null(target)) "" else target$source$url,
      definition_source_sha256 = if (is.null(target)) "" else target$source$sha256,
      review_status = "unreviewed", stringsAsFactors = FALSE)
  })
  if (length(rows)) return(do.call(rbind, rows))
  as.data.frame(stats::setNames(rep(list(character()), length(columns)), columns))
}
