# Review payloads over frozen catalog records. No filesystem or global reads.

catalog_review_phase <- function(phase) {
  labels <- c(admission = "Admission", degree = "Degree", prerequisite = "Prerequisite",
    corequisite = "Corequisite", info = "Information", unclassified = "Unclassified")
  if (any(!phase %in% names(labels))) stop("[catalog-review.R] Unknown catalog phase")
  unname(labels[phase])
}

catalog_review_record <- function(records, entity, hash) {
  matches <- Filter(function(x) paste(x$kind, x$pid, sep = ":") == entity && x$source$sha256 == hash, records)
  if (!length(matches)) stop("[catalog-review.R] Review item has no matching source record: ", entity)
  matches[[1]]
}

#' One actionable work list, with separate source checks and section checks
build_catalog_review_items <- function(records, nodes, issues) {
  rows <- list()
  record_keys <- vapply(records, function(x) paste(x$kind, x$pid, x$source$sha256, sep = ":"), character(1))
  add <- function(category, entity, hash, field, node_id, pointer, excerpt, reason, next_step, milestone_id = "") {
    index <- match(paste(entity, hash, sep = ":"), record_keys)
    if (is.na(index)) stop("[catalog-review.R] Review item has no matching source record: ", entity)
    record <- records[[index]]
    section <- Filter(function(x) x$field == field, record$sections)
    if (nzchar(field) && length(section) != 1L) stop("[catalog-review.R] Review section is missing or ambiguous")
    kind <- switch(record$kind, programs = "Degree", specializations = "Concentration", courses = "Course",
      stop("[catalog-review.R] Unknown record kind"))
    rows[[length(rows) + 1L]] <<- list(
      item_id = source_sha256(source_json_bytes(list(category, entity, hash, field, node_id, pointer, reason))),
      category = category, entity = entity, title = if (nzchar(record$course_code))
        paste(record$course_code, "—", record$title) else record$title,
      kind = kind, field = field, section = if (length(section)) section[[1]]$label else "Source record",
      phase = if (length(section)) catalog_review_phase(section[[1]]$phase) else "Source",
      reason = reason, next_step = next_step, excerpt = excerpt, node_id = node_id, milestone_id = milestone_id,
      source_pointer = pointer, source_sha256 = hash, source_url = record$source$url,
      review_status = "Unreviewed")
  }
  for (i in which(nodes$operator == "milestone")) {
    x <- nodes[i, ]
    standing <- x$milestone_type == "class_standing"
    add("Milestone", x$entity, x$source_sha256, x$field, x$node_id, x$source_pointer, x$text,
      if (standing) "Class standing milestone" else "Program admission milestone",
      if (standing) "Preserve the required class standing and the surrounding AND/OR choices. Standing is a recorded status, not an inferred credit total or semester number. This extraction does not establish a student's eligibility."
      else "This course requires admission to the linked program. The program's captured admission policy is context; satisfying academic criteria is distinct from admission recorded. Automatic admission must be explicitly supported by that policy.",
      milestone_id = x$milestone_id)
  }
  for (i in which(nodes$operator == "condition" & nodes$phase != "info")) {
    x <- nodes[i, ]
    missing_course <- identical(x$text, "Course Not Found")
    missing_program <- "milestone_type" %in% names(nodes) && x$milestone_type == "program_admission"
    add("Interpretation", x$entity, x$source_sha256, x$field, x$node_id, x$source_pointer, x$text,
      if (missing_course) "Unresolved course in source" else if (missing_program) "Admission target not captured" else "Rule not yet supported",
      if (missing_course) "The captured catalog displays Course Not Found. Check the enclosing rule and published course link with the catalog owner; do not guess a replacement or drop this requirement."
      else if (missing_program) "The admission rule links to a program outside this saved undergraduate capture. Verify the linked program and its admission policy; do not guess a target by its label or equate completed coursework with admission."
      else "The extractor has not fully represented this rule; this flag does not establish a catalog error. Read the full section and decide how to preserve its conditions, alternatives, exceptions, or linked policies. Repeated standard wording should become a supported parsing pattern, not an ignored requirement.")
  }
  actions <- c(source_query_flag_false = "Check whether the course belongs in this catalog edition. Follow the catalog link and consult the catalog owner if necessary; this flag does not establish cancellation or availability.",
    no_degree_section = "Check the published program requirements and the captured field schema. Repair the field mapping or extraction before building a degree plan.",
    credential_needs_review = "Check the published credential and undergraduate classification, then update the institution's catalog scan configuration if needed.",
    total_credit_conflict = "Check the catalog's own Degree Hours field against every other total-credit figure printed on this program's own page (Grand Total Credits, Total Credits, etc.) and resolve with the catalog owner. This flag does not say which number is correct, and does not compare against concentration-level totals.")
  reasons <- c(source_query_flag_false = "Catalog inclusion flag", no_degree_section = "Degree requirements missing",
    credential_needs_review = "Credential needs classification", total_credit_conflict = "Conflicting total-credit figures")
  if (any(!issues$issue %in% names(actions))) stop("[catalog-review.R] Unknown source issue type")
  for (i in seq_len(nrow(issues))) {
    x <- issues[i, ]
    add("Source", x$entity, x$source_sha256, "", "", x$source_pointer, x$detail,
      unname(reasons[x$issue]), unname(actions[x$issue]))
  }
  for (record in records) for (section in record$sections) {
    if (section$phase == "info") next
    add("Section", paste(record$kind, record$pid, sep = ":"), record$source$sha256,
      section$field, "", section$source_pointer, section$text, "Section has not been validated",
      "Compare the full captured section with the draft structure. Check every required course, alternative, minimum, grade condition and exception. Parsed lists still need human validation before becoming an executable degree plan.")
  }
  if (!length(rows)) stop("[catalog-review.R] Capture has no reviewable sections or source issues")
  items <- unique(as.data.frame(bind_rows(rows)))
  if (anyDuplicated(items$item_id)) stop("[catalog-review.R] Review item identities are ambiguous")
  items[order(items$title, items$section, items$category, items$node_id), ]
}

#' Program scope includes its concentrations and the transitive course references
#' This is a reference closure, never a claim that all those courses are required.
catalog_review_program_entities <- function(records, program_id) {
  entities <- vapply(records, function(x) paste(x$kind, x$pid, sep = ":"), character(1))
  root <- paste0("programs:", program_id)
  if (!root %in% entities) stop("[catalog-review.R] Unknown program selection")
  aliases <- list()
  for (i in seq_along(records)) if (records[[i]]$kind == "courses") {
    record <- records[[i]]
    aliases[[record$pid]] <- entities[i]
    if (nzchar(record$revision_id)) aliases[[paste0("view/", record$revision_id)]] <- entities[i]
  }
  todo <- c(root, entities[vapply(records, function(x) identical(x$parent_program_id, program_id), logical(1))])
  visited <- character()
  while (length(todo)) {
    entity <- todo[1]; todo <- todo[-1]
    if (entity %in% visited) next
    visited <- c(visited, entity)
    for (record in records[entities == entity]) for (section in record$sections) {
      for (ref in section$course_references) {
        target <- aliases[[ref$key]]
        # Program-only captures intentionally have no course records.
        if (!is.null(target) && !target %in% visited) todo <- c(todo, target)
      }
    }
  }
  unique(visited)
}

filter_catalog_review <- function(payload, program = "", kind = "", phase = "") {
  items <- payload$items
  if (nzchar(program)) items <- items[items$entity %in% catalog_review_program_entities(payload$records, program), ]
  if (nzchar(kind)) items <- items[items$kind == kind, ]
  if (nzchar(phase)) items <- items[items$phase == phase, ]
  coverage <- payload$coverage
  if (nzchar(program)) coverage <- coverage[coverage$program_id == program, ]
  list(interpretation = items[items$category == "Interpretation", ],
    milestones = items[items$category == "Milestone", ],
    source = items[items$category == "Source", ], sections = items[items$category == "Section", ],
    items = items, coverage = coverage)
}

# A compact draft tree belongs beside the full source, not in place of it.
catalog_review_tree_text <- function(tree, level = 0L) {
  labels <- c(document = "Section", group = "Group", all = "All of", choose_n = "Choose at least",
    credits = "Minimum credits", course = "Course", milestone = "Status milestone", condition = "Needs interpretation", text = "Text")
  if (!tree$operator %in% names(labels)) stop("[catalog-review.R] Unknown draft operator: ", tree$operator)
  title <- paste0(strrep("  ", level), labels[[tree$operator]],
    if (!is.null(tree$minimum)) paste0(" ", tree$minimum) else "",
    if (!is.null(tree$minimum_grade)) paste0(" [minimum grade ", tree$minimum_grade, "]") else "", ": ",
    if (is.null(tree$text)) "" else tree$text,
    if (!is.null(tree$milestone$id)) paste0(" [", tree$milestone$id, "]") else "")
  c(title, unlist(lapply(tree$children, catalog_review_tree_text, level = level + 1L), use.names = FALSE))
}
