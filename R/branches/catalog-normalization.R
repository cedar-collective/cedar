# Source-bound AI proposals. Pure document/graph operations, never model calls.

# Partition visible prose without interpreting it. Inline text stays together;
# nested lists retain DOM ancestry and the full section HTML is kept separately.
catalog_normalization_blocks <- function(html, section, record) {
  root <- xml2::xml_find_first(catalog_html_document(html), "//div[@id='cedar-source']")
  rows <- list()
  structural <- "self::div or self::p or self::ul or self::ol or self::li or self::table or self::tr or self::h1 or self::h2 or self::h3 or self::h4 or self::h5 or self::h6"
  visit <- function(node, parent_path = "") {
    buffer <- character(); run <- 0L
    flush <- function() {
      text <- trimws(gsub("[[:space:]\u00a0]+", " ", paste(buffer, collapse = " ")))
      buffer <<- character()
      if (!nzchar(text)) return()
      run <<- run + 1L
      path <- paste0(xml2::xml_path(node), "/text-run[", run, "]")
      entity <- paste(record$kind, record$pid, sep = ":")
      id <- paste0("b-", substr(source_sha256(source_json_bytes(list(entity,
        record$source$sha256, section$source_pointer, path))), 1L, 24L))
      rows[[length(rows) + 1L]] <<- list(id = id, entity_id = entity, title = record$title,
        field = section$field, section = section$label, phase = section$phase, text = text,
        source_pointer = section$source_pointer, dom_path = path, parent_path = parent_path,
        source_sha256 = record$source$sha256, source_url = record$source$url)
    }
    for (child in xml2::xml_contents(node)) {
      if (xml2::xml_type(child) == "text") buffer <- c(buffer, xml2::xml_text(child))
      else if (xml2::xml_type(child) == "element" && !xml2::xml_name(child) %in% c("script", "style")) {
        is_block <- length(xml2::xml_find_all(child, paste0("self::*[", structural, "] | .//*[", structural, "]"))) > 0L
        if (is_block) { flush(); visit(child, xml2::xml_path(node)) }
        else buffer <- c(buffer, catalog_node_text(child))
      }
    }
    flush()
  }
  visit(root)
  rows
}

# Validate the shipped JSON schema locally too, including imported external AI
# output. No additional dependency and no trust in the producer's JSON mode.
validate_catalog_json_schema <- function(value, schema, path = "proposal", root = schema) {
  fail <- function(message) stop("[catalog-normalization.R] ", path, ": ", message, call. = FALSE)
  types <- unlist(schema$type, use.names = FALSE)
  type_ok <- function(type) switch(type,
    object = is.list(value) && !is.null(names(value)),
    array = is.list(value) && is.null(names(value)),
    string = is.character(value) && length(value) == 1L && !is.na(value),
    number = is.numeric(value) && length(value) == 1L && is.finite(value),
    null = is.null(value), FALSE)
  if (!any(vapply(types, type_ok, logical(1)))) fail(paste("expected", paste(types, collapse = " or ")))
  if (!is.null(schema$enum) && !value %in% unlist(schema$enum)) fail("value is outside the allowed vocabulary")
  if ("object" %in% types && !is.null(value)) {
    if (anyDuplicated(names(value))) fail("duplicate fields")
    missing <- setdiff(unlist(schema$required), names(value))
    extra <- setdiff(names(value), names(schema$properties))
    if (length(missing) || length(extra)) fail(paste("missing/extra fields:", paste(c(missing, extra), collapse = ", ")))
    for (name in names(value)) validate_catalog_json_schema(value[[name]], schema$properties[[name]], paste0(path, ".", name), root)
  }
  if ("array" %in% types) for (i in seq_along(value)) {
    validate_catalog_json_schema(value[[i]], schema$items, paste0(path, "[", i, "]"), root)
  }
  invisible(value)
}

catalog_normalization_ids <- function(rows, field = "id") vapply(rows, function(x) x[[field]], character(1))

#' Reject invented references, unsupported evidence and malformed AND/OR graphs
validate_catalog_normalization <- function(proposal, request) {
  validate_catalog_json_schema(proposal, request$response_schema)
  nodes <- proposal$nodes; ids <- catalog_normalization_ids(nodes)
  blocks <- request$source_blocks; block_ids <- catalog_normalization_ids(blocks)
  if (any(!grepl("^[A-Za-z0-9_-]+$", ids)) || anyDuplicated(ids)) stop("[catalog-normalization.R] Node IDs must be unique simple identifiers")
  parents <- vapply(nodes, function(x) x$parent_id, character(1))
  if (any(!parents %in% c("", ids))) stop("[catalog-normalization.R] Invalid parent reference")
  registry <- catalog_normalization_ids(request$reference_registry)
  groups <- c("all", "any", "choose_n", "credits", "grade")
  for (node in nodes) {
    if (!nzchar(trimws(node$label)) || !node$entity_id %in% unlist(request$target_entities)) stop("[catalog-normalization.R] A node lacks a label or targets a context-only entity")
    if (nzchar(node$parent_id)) {
      parent <- match(node$parent_id, ids)
      if (is.na(parent) || !nodes[[parent]]$kind %in% groups ||
          nodes[[parent]]$entity_id != node$entity_id || nodes[[parent]]$phase != node$phase) {
        stop("[catalog-normalization.R] Invalid parent, entity or phase boundary")
      }
      ancestors <- node$id; current <- node$parent_id
      while (nzchar(current)) {
        if (current %in% ancestors) stop("[catalog-normalization.R] Requirement graph contains a cycle")
        ancestors <- c(ancestors, current); current <- nodes[[match(current, ids)]]$parent_id
      }
    }
    for (bound in c("minimum", "maximum")) if (!is.null(node[[bound]]) && node[[bound]] < 0) stop("[catalog-normalization.R] Bounds cannot be negative")
    if (!is.null(node$minimum) && !is.null(node$maximum) && node$maximum < node$minimum) stop("[catalog-normalization.R] Maximum is below minimum")
    children <- sum(vapply(nodes, function(x) x$parent_id == node$id, logical(1)))
    if (node$kind %in% c("all", "any", "grade") && children == 0L) stop("[catalog-normalization.R] Logical/grade group has no children")
    if (node$kind == "choose_n" && (is.null(node$minimum) || node$minimum < 1 || node$minimum != floor(node$minimum) || node$minimum > children || node$unit != "courses")) stop("[catalog-normalization.R] Invalid choice count or unit")
    if (node$kind %in% c("credits", "gpa", "course_pool") && (is.null(node$minimum) || node$minimum <= 0 || node$unit != switch(node$kind, credits = "credits", gpa = "gpa", course_pool = "courses"))) stop("[catalog-normalization.R] Missing or invalid minimum/unit")
    if (node$kind == "course_pool" && (node$minimum != floor(node$minimum) || !nzchar(node$value))) stop("[catalog-normalization.R] Course pool needs an integer count and explicit qualification")
    refs <- vapply(node$course_refs, identity, character(1))
    if (anyDuplicated(refs) || any(!refs %in% registry) || any(!startsWith(refs, "courses:"))) stop("[catalog-normalization.R] Unknown or duplicate course reference")
    if (node$kind == "course" && length(refs) != 1L) stop("[catalog-normalization.R] A course node names exactly one course")
    if (nzchar(node$program_ref) && (!node$program_ref %in% registry || !startsWith(node$program_ref, "programs:"))) stop("[catalog-normalization.R] Unknown admission program reference")
    if (node$kind == "program_admission" && !nzchar(node$program_ref)) stop("[catalog-normalization.R] Admission milestone needs a program reference")
    if (node$kind %in% c("class_standing", "permission", "restriction", "unresolved", "information", "gpa") && !nzchar(trimws(node$value))) stop("[catalog-normalization.R] Predicate/scope text is required")
    if (node$kind == "class_standing" && node$comparison == "none") stop("[catalog-normalization.R] Standing needs an explicit comparison")
    if (!length(node$citations)) stop("[catalog-normalization.R] Every node needs source evidence")
    for (citation in node$citations) {
      index <- match(citation$block_id, block_ids)
      if (is.na(index) || blocks[[index]]$entity_id != node$entity_id || !nzchar(trimws(citation$quote)) ||
          !grepl(citation$quote, blocks[[index]]$text, fixed = TRUE)) stop("[catalog-normalization.R] Citation does not match its requested source block")
    }
  }
  coverage_ids <- catalog_normalization_ids(proposal$coverage, "block_id")
  if (anyDuplicated(coverage_ids) || !setequal(coverage_ids, block_ids)) stop("[catalog-normalization.R] Coverage must account for every requested block exactly once")
  for (coverage in proposal$coverage) {
    mapped <- unlist(coverage$node_ids, use.names = FALSE)
    if (anyDuplicated(mapped) || any(!mapped %in% ids)) stop("[catalog-normalization.R] Coverage refers to missing/duplicate nodes")
    if (coverage$disposition != "information" && !length(mapped)) stop("[catalog-normalization.R] Requirement/unresolved coverage needs nodes")
    if (!nzchar(trimws(coverage$explanation))) stop("[catalog-normalization.R] Every coverage decision needs an explanation")
    for (id in mapped) if (!coverage$block_id %in% vapply(nodes[[match(id, ids)]]$citations, function(x) x$block_id, character(1))) stop("[catalog-normalization.R] Coverage mapping lacks a matching citation")
    cited <- ids[vapply(nodes, function(x) coverage$block_id %in% vapply(x$citations, function(y) y$block_id, character(1)), logical(1))]
    if (!setequal(mapped, cited)) stop("[catalog-normalization.R] Coverage must list every node citing the passage")
    if (coverage$disposition == "information" && any(vapply(nodes[match(mapped, ids)], function(x) x$kind != "information", logical(1)))) stop("[catalog-normalization.R] A requirement cannot be classified as information")
  }
  for (question in proposal$questions) if (!question$block_id %in% block_ids || !nzchar(trimws(question$question))) stop("[catalog-normalization.R] Question lacks a source block or text")
  invisible(proposal)
}

catalog_normalization_review_state <- function(proposal) {
  list(proposal = proposal,
    nodes = stats::setNames(as.list(rep("pending", length(proposal$nodes))), catalog_normalization_ids(proposal$nodes)),
    blocks = stats::setNames(as.list(rep("pending", length(proposal$coverage))), catalog_normalization_ids(proposal$coverage, "block_id")),
    notes = list(), approval = "pending", head = "", revision = 0L)
}

validate_catalog_normalization_state <- function(state, request) {
  validate_catalog_normalization(state$proposal, request)
  if (!setequal(names(state$nodes), catalog_normalization_ids(state$proposal$nodes)) ||
      !setequal(names(state$blocks), catalog_normalization_ids(state$proposal$coverage, "block_id")) ||
      any(!unlist(state$nodes) %in% c("pending", "approved", "needs_clarification")) ||
      any(!unlist(state$blocks) %in% c("pending", "confirmed", "needs_clarification"))) stop("[catalog-normalization.R] Invalid review decisions")
  for (node in state$proposal$nodes) if (node$kind == "unresolved" && state$nodes[[node$id]] == "approved") stop("[catalog-normalization.R] An unresolved rule cannot be approved")
  if (!is.null(state$approval) && !state$approval %in% c("pending", "unit")) stop("[catalog-normalization.R] Invalid unit approval")
  if (identical(state$approval, "unit") && nrow(catalog_normalization_issues(state))) stop("[catalog-normalization.R] Approved units cannot contain open review cases")
  invisible(state)
}

catalog_normalization_issues <- function(state) {
  rows <- list()
  add <- function(type, id, label, reason) {
    rows[[length(rows) + 1L]] <<- data.frame(type = type, id = id, label = label, reason = reason)
  }
  for (node in state$proposal$nodes) {
    if (node$kind == "unresolved") add("nodes", node$id, node$label, node$value)
    else if (state$nodes[[node$id]] == "needs_clarification") add("nodes", node$id, node$label, state$notes[[paste0("nodes:", node$id)]])
  }
  for (block in state$proposal$coverage) {
    represented <- any(vapply(state$proposal$nodes, function(x) x$id %in% unlist(block$node_ids) && x$kind == "unresolved", logical(1)))
    if (block$disposition == "unresolved" && !represented) add("blocks", block$block_id, "Unresolved source treatment", block$explanation)
    else if (state$blocks[[block$block_id]] == "needs_clarification") add("blocks", block$block_id, "Flagged source passage", state$notes[[paste0("blocks:", block$block_id)]])
  }
  for (question in state$proposal$questions) add("blocks", question$block_id, "Interpretation question", question$question)
  if (!length(rows)) return(data.frame(type = character(), id = character(), label = character(), reason = character()))
  unique(do.call(rbind, rows))
}

# The reviewer signs off the complete interpretation once. Mechanical coverage
# validation does not require a separate click for each passage or routine rule.
approve_catalog_normalization <- function(state) {
  if (nrow(catalog_normalization_issues(state))) stop("[catalog-normalization.R] Resolve the open review cases before approving this unit")
  state$nodes <- lapply(state$nodes, function(x) "approved")
  state$blocks <- lapply(state$blocks, function(x) "confirmed")
  state$approval <- "unit"
  state
}

catalog_normalization_approved <- function(state) {
  identical(state$approval, "unit") && length(state$blocks) > 0L && all(unlist(state$blocks) == "confirmed") &&
    all(unlist(state$nodes) == "approved") && !length(state$proposal$questions) &&
    !any(vapply(state$proposal$nodes, function(x) x$kind == "unresolved", logical(1))) &&
    !any(vapply(state$proposal$coverage, function(x) x$disposition == "unresolved", logical(1)))
}

# Edits reset approvals because changing a group can change every descendant's
# meaning. The original AI response and all previous review revisions survive.
edit_catalog_normalization <- function(state, proposal, request) {
  validate_catalog_normalization(proposal, request)
  changed <- catalog_normalization_review_state(proposal)
  changed$head <- state$head; changed$revision <- state$revision
  changed
}

catalog_normalization_node_summary <- function(node, registry) {
  refs <- unlist(node$course_refs, use.names = FALSE)
  titles <- vapply(registry, function(x) paste(x$code, x$title), character(1))
  paste(c(node$kind, if (!is.null(node$minimum)) paste("minimum", node$minimum, node$unit),
    if (!is.null(node$maximum)) paste("maximum", node$maximum, node$unit),
    if (nzchar(node$value)) paste(node$comparison, node$value),
    if (nzchar(node$minimum_grade)) paste("minimum grade", node$minimum_grade),
    if (length(refs)) titles[match(refs, catalog_normalization_ids(registry))],
    if (nzchar(node$program_ref)) titles[match(node$program_ref, catalog_normalization_ids(registry))],
    if (node$timing != "not_applicable") node$timing), collapse = " · ")
}

catalog_normalization_decision <- function(state, type, id, decision, note) {
  choices <- if (type == "nodes") c("approved", "needs_clarification") else if (type == "blocks") c("confirmed", "needs_clarification") else character()
  if (!id %in% names(state[[type]]) || !decision %in% choices) stop("[catalog-normalization.R] Invalid review selection or decision")
  if (decision == "needs_clarification" && !nzchar(trimws(note))) stop("[catalog-normalization.R] Explain what needs clarification")
  if (type == "nodes" && decision == "approved") {
    node <- state$proposal$nodes[[match(id, catalog_normalization_ids(state$proposal$nodes))]]
    if (node$kind == "unresolved") stop("[catalog-normalization.R] Edit the unresolved interpretation before approving it")
  }
  state[[type]][[id]] <- decision
  state$notes[[paste(type, id, sep = ":")]] <- note
  state$approval <- "pending"
  state
}

clear_catalog_normalization_flag <- function(state, type, id, note) {
  if (!type %in% c("nodes", "blocks") || !id %in% names(state[[type]]) || !nzchar(trimws(note))) stop("[catalog-normalization.R] Select a flagged item and explain its resolution")
  if (state[[type]][[id]] != "needs_clarification") stop("[catalog-normalization.R] Only reviewer flags can be cleared here; edit an unresolved interpretation to resolve it")
  state[[type]][[id]] <- "pending"
  state$notes[[paste(type, id, sep = ":")]] <- note
  state$approval <- "pending"
  state
}

edit_catalog_normalization_node <- function(state, id, fields, request) {
  proposal <- state$proposal
  index <- match(id, catalog_normalization_ids(proposal$nodes))
  if (is.na(index)) stop("[catalog-normalization.R] Select an available requirement")
  node <- proposal$nodes[[index]]
  for (name in names(fields)) node[name] <- list(fields[[name]])
  proposal$nodes[[index]] <- node
  # A reviewer resolving an unresolved node also resolves its coverage marker
  # when no other unresolved interpretation cites that passage. Keep questions
  # and other unresolved nodes intact; they still block whole-unit sign-off.
  if (state$proposal$nodes[[index]]$kind == "unresolved" && node$kind != "unresolved") {
    proposal$coverage <- lapply(proposal$coverage, function(block) {
      if (block$disposition == "unresolved" && id %in% unlist(block$node_ids)) {
        kinds <- vapply(proposal$nodes[match(unlist(block$node_ids), catalog_normalization_ids(proposal$nodes))], function(x) x$kind, character(1))
        if (!"unresolved" %in% kinds) {
          block$disposition <- if (all(kinds == "information")) "information" else "requirements"
          block$explanation <- paste("Coverage updated with the reviewer's corrected interpretation of", id)
        }
      }
      block
    })
  }
  edit_catalog_normalization(state, proposal, request)
}

catalog_normalization_rule_rows <- function(state, request) {
  nodes <- state$proposal$nodes; ids <- catalog_normalization_ids(nodes)
  if (!length(nodes)) return(data.frame(id = character(), requirement = character(), meaning = character(), status = character()))
  rows <- lapply(nodes, function(node) {
    depth <- 0L; parent <- node$parent_id
    while (nzchar(parent)) { depth <- depth + 1L; parent <- nodes[[match(parent, ids)]]$parent_id }
    list(id = node$id, requirement = paste0(strrep("\u00a0\u00a0", depth), node$label),
      meaning = catalog_normalization_node_summary(node, request$reference_registry),
      status = if (node$kind == "unresolved" || state$nodes[[node$id]] == "needs_clarification") "Needs attention" else if (catalog_normalization_approved(state)) "Reviewed" else "Included in sign-off")
  })
  do.call(rbind, lapply(rows, as.data.frame, stringsAsFactors = FALSE))
}
