# Offline packets, imported AI proposals and append-only human review receipts.
# Catalog captures and the current semester planner are never edited here.

catalog_normalization_hash_file <- function(path) {
  if (!file.exists(path)) stop("[catalog-normalization.R] Missing artifact: ", path)
  source_sha256(readBin(path, "raw", n = file.info(path)$size))
}

catalog_normalization_document <- function(record, directory, landing) {
  original <- read_captured_source(record$source, directory)
  blocks <- list(); sections <- list()
  for (section in record$sections) {
    value <- source_json_pointer(original, section$source_pointer)
    html <- if (is.character(value) && length(value) == 1L) value else rawToChar(source_json_bytes(value))
    blocks <- c(blocks, catalog_normalization_blocks(html, section, record))
    sections[[length(sections) + 1L]] <- list(field = section$field, label = section$label,
      phase = section$phase, source_pointer = section$source_pointer, html = html)
  }
  prefix <- if (is.null(record$source$json_pointer)) "" else record$source$json_pointer
  # Metadata can contain requirements too (degree hours, concentration required,
  # minimum major hours). It is evidence, not a trusted set of derived defaults.
  for (field in setdiff(names(record$metadata), "specialization_ids")) {
    value <- source_json_pointer(original, paste0(prefix, "/", field))
    text <- as.character(jsonlite::toJSON(value, auto_unbox = TRUE, null = "null", digits = NA))
    section <- list(field = field, label = paste("Record field:", field), phase = "unclassified", source_pointer = paste0(prefix, "/", field))
    block <- catalog_normalization_blocks(htmltools::htmlEscape(text), section, record)
    blocks <- c(blocks, block)
  }
  entity <- paste(record$kind, record$pid, sep = ":")
  list(id = entity, title = record$title, code = if (record$kind == "courses") record$course_code else record$code,
    catalog_url = paste0(sub("#.*$", "", landing), "#/", if (record$kind == "specializations")
      paste0("programs/", record$parent_program_id) else paste(record$kind, record$pid, sep = "/")),
    receipt = record$source, sections = sections, blocks = blocks)
}

#' Prepare complete program/concentration context plus separately reusable course units
prepare_catalog_normalization <- function(payload, program_id, root, prompt, schema) {
  if (!nzchar(trimws(prompt))) stop("[catalog-normalization.R] Interpretation instructions are required")
  entities <- catalog_review_program_entities(payload$records, program_id)
  records <- payload$records
  ids <- vapply(records, function(x) paste(x$kind, x$pid, sep = ":"), character(1))
  eligible <- which(vapply(records, function(x) x$kind != "specializations" || x$parent_program_id == program_id, logical(1)))
  selected <- records[eligible[match(entities, ids[eligible])]]
  aliases <- list()
  for (record in records) {
    entity <- paste(record$kind, record$pid, sep = ":")
    aliases[[paste0(record$kind, ":", record$pid)]] <- entity
    if (nzchar(record$revision_id)) aliases[[paste0(record$kind, ":view/", record$revision_id)]] <- entity
  }
  # Admission context is resolved by frozen IDs, never by display-name matching.
  contexts <- character()
  for (record in selected) for (section in record$sections) {
    value <- source_json_pointer(read_captured_source(record$source, payload$source_directory), section$source_pointer)
    html <- if (is.character(value) && length(value) == 1L) value else rawToChar(source_json_bytes(value))
    for (ref in catalog_program_references(html)) {
      target <- aliases[[paste0("programs:", ref$key)]]
      if (!is.null(target)) contexts <- c(contexts, target)
    }
  }
  context_ids <- setdiff(unique(contexts), entities)
  documents <- lapply(c(selected, records[match(context_ids, ids)]), catalog_normalization_document,
    directory = payload$source_directory, landing = payload$manifest$settings$source$landing_url)
  names(documents) <- catalog_normalization_ids(documents)
  program_entities <- entities[!startsWith(entities, "courses:")]
  targets <- c(list(program_entities), as.list(entities[startsWith(entities, "courses:")]))
  units <- lapply(targets, function(target) {
    own <- documents[target]
    linked_programs <- character()
    for (doc in own) for (section in doc$sections) for (ref in catalog_program_references(section$html)) {
      resolved <- aliases[[paste0("programs:", ref$key)]]
      if (!is.null(resolved)) linked_programs <- c(linked_programs, resolved)
    }
    context <- Filter(function(x) x$id %in% linked_programs && !x$id %in% target, documents)
    context <- lapply(context, function(x) { x$sections <- Filter(function(s) s$phase == "admission", x$sections); x })
    context_blocks <- unname(unlist(lapply(context, function(x) Filter(function(y) y$phase == "admission", x$blocks)), recursive = FALSE))
    refs <- unique(c(target, vapply(context, function(x) x$id, character(1))))
    unresolved_links <- list()
    for (doc in c(own, context)) for (section in doc$sections) for (kind in c("courses", "programs")) {
      for (ref in catalog_entity_references(section$html, kind)) {
        resolved <- aliases[[paste(kind, ref$key, sep = ":")]]
        if (is.null(resolved)) unresolved_links[[length(unresolved_links) + 1L]] <- ref
        else refs <- c(refs, resolved)
      }
    }
    refs <- unique(refs)
    registry <- lapply(records[match(refs, ids)], function(x) list(id = paste(x$kind, x$pid, sep = ":"),
      code = if (x$kind == "courses") x$course_code else x$code, title = x$title,
      aliases = as.list(c(x$pid, if (nzchar(x$revision_id)) paste0("view/", x$revision_id)))))
    request <- list(instructions = prompt, response_schema = schema, catalog_id = payload$meta$catalog_id,
      catalog_title = payload$meta$catalog_title, target_entities = as.list(target),
      scope_note = "Normalize the target entities only. Linked course requirements are separate units; a program reference is not a required course. Context-only admission text is not a new rule for a target course.",
      documents = unname(lapply(own, function(x) x[setdiff(names(x), "blocks")])),
      source_blocks = unname(unlist(lapply(own, function(x) x$blocks), recursive = FALSE)),
      context_blocks = context_blocks, reference_registry = registry, unresolved_links = unresolved_links)
    list(key = source_sha256(source_json_bytes(request)), title = if (length(target) > 1L || startsWith(target[1], "programs:"))
      "Program and concentrations" else paste(own[[1]]$code, own[[1]]$title), request = request)
  })
  program <- records[[match(paste0("programs:", program_id), ids)]]
  packet <- list(schema_version = "1.0.0", program_id = program_id, title = program$title,
    catalog_title = payload$meta$catalog_title, catalog_id = payload$meta$catalog_id,
    source_directory = normalizePath(payload$source_directory),
    source_manifest_sha256 = payload$meta$source_manifest_sha256, units = units)
  key <- source_sha256(source_json_bytes(packet))
  directory <- file.path(root, "programs", key)
  if (dir.exists(directory)) {
    existing <- load_catalog_normalization_program(root, key)
    if (!identical(existing$packet, packet)) stop("[catalog-normalization.R] Existing program packet differs")
    return(invisible(directory))
  }
  dir.create(directory, recursive = TRUE)
  write_source_json(packet, file.path(directory, "packet.json"))
  write_source_json(list(schema_version = "1.0.0", packet_sha256 = catalog_normalization_hash_file(file.path(directory, "packet.json")),
    key = key, title = packet$title, program_id = program_id, catalog_title = packet$catalog_title,
    created_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC")), file.path(directory, "program-manifest.json"))
  invisible(directory)
}

list_catalog_normalization_programs <- function(root) {
  empty <- data.frame(key = character(), title = character(), label = character())
  if (!dir.exists(file.path(root, "programs"))) return(empty)
  paths <- list.files(file.path(root, "programs"), pattern = "^program-manifest[.]json$", recursive = TRUE, full.names = TRUE)
  if (!length(paths)) return(empty)
  rows <- lapply(paths, function(path) {
    meta <- read_source_json(path)
    data.frame(key = basename(dirname(path)), title = meta$title,
      label = paste(meta$title, "·", meta$catalog_title, "·", substr(meta$key, 1L, 8L)))
  })
  do.call(rbind, rows)[order(file.info(paths)$mtime, decreasing = TRUE), ]
}

catalog_normalization_key <- function(key) {
  if (length(key) != 1L || !grepl("^[a-f0-9]{64}$", key)) stop("[catalog-normalization.R] Invalid artifact identifier")
  key
}

load_catalog_normalization_program <- function(root, key) {
  directory <- file.path(root, "programs", catalog_normalization_key(key))
  meta <- read_source_json(file.path(directory, "program-manifest.json"))
  if (!identical(meta$schema_version, "1.0.0") || !identical(meta$key, key) ||
      !identical(meta$packet_sha256, catalog_normalization_hash_file(file.path(directory, "packet.json")))) stop("[catalog-normalization.R] Program packet hash mismatch")
  packet <- read_source_json(file.path(directory, "packet.json"))
  if (!identical(source_sha256(source_json_bytes(packet)), key)) stop("[catalog-normalization.R] Program identity does not match its content")
  for (unit in packet$units) if (!identical(unit$key, source_sha256(source_json_bytes(unit$request)))) stop("[catalog-normalization.R] Unit request hash mismatch")
  list(packet = packet, meta = meta, directory = directory)
}

catalog_normalization_unit <- function(program, key) {
  matches <- Filter(function(x) identical(x$key, key), program$packet$units)
  if (length(matches) != 1L) stop("[catalog-normalization.R] Select an available interpretation unit")
  matches[[1]]
}

# Original bytes are rechecked when a reviewer opens a unit or source passage.
catalog_normalization_capture_directory <- function(program, capture_root) {
  packet <- program$packet
  candidates <- unique(c(file.path(capture_root, basename(packet$source_directory)), packet$source_directory))
  matches <- vapply(candidates, function(x) file.exists(file.path(x, "source-manifest.json")) &&
    identical(catalog_normalization_hash_file(file.path(x, "source-manifest.json")), packet$source_manifest_sha256), logical(1))
  if (!any(matches)) stop("[catalog-normalization.R] The matching source capture is unavailable")
  candidates[which(matches)[1]]
}

verify_catalog_normalization_sources <- function(program, unit, capture_root) {
  directory <- catalog_normalization_capture_directory(program, capture_root)
  documents <- unit$request$documents
  hashes <- vapply(documents, function(x) x$receipt$sha256, character(1))
  for (document in documents[!duplicated(hashes)]) read_captured_source(document$receipt, directory)
  # Context blocks cite other documents; their captured hash-named blobs must
  # still exist even when the original host path differs inside Docker.
  for (hash in unique(vapply(unit$request$context_blocks, function(x) x$source_sha256, character(1)))) {
    if (!identical(catalog_normalization_hash_file(file.path(directory, "sources", paste0(hash, ".body"))), hash)) stop("[catalog-normalization.R] Context source hash mismatch")
  }
  invisible(TRUE)
}

catalog_normalization_context_sources <- function(program, unit, capture_root) {
  directory <- catalog_normalization_capture_directory(program, capture_root)
  blocks <- unit$request$context_blocks
  keys <- vapply(blocks, function(x) paste(x$source_sha256, x$source_pointer), character(1))
  lapply(blocks[!duplicated(keys)], function(block) {
    path <- file.path(directory, "sources", paste0(block$source_sha256, ".body"))
    if (!identical(catalog_normalization_hash_file(path), block$source_sha256)) stop("[catalog-normalization.R] Context source hash mismatch")
    list(title = block$title, section = block$section, source_sha256 = block$source_sha256,
      source_pointer = block$source_pointer, value = source_json_pointer(read_source_json(path), block$source_pointer))
  })
}

import_catalog_normalization <- function(root, unit, path, model) {
  if (!nzchar(trimws(model))) stop("[catalog-normalization.R] Record the AI model or tool used")
  proposal <- read_source_json(path)
  validate_catalog_normalization(proposal, unit$request)
  response_hash <- catalog_normalization_hash_file(path)
  key <- source_sha256(source_json_bytes(list(unit$key, response_hash, model)))
  directory <- file.path(root, "proposals", unit$key, key)
  if (dir.exists(directory)) {
    load_catalog_normalization_proposal(root, unit, key)
    return(invisible(key)) # Identical imported bytes are already preserved.
  }
  dir.create(directory, recursive = TRUE)
  if (!file.copy(path, file.path(directory, "response.json"))) stop("[catalog-normalization.R] Cannot retain original AI response")
  write_source_json(list(schema_version = "1.0.0", key = key, unit_key = unit$key,
    response_sha256 = response_hash, model = trimws(model),
    imported_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC")), file.path(directory, "proposal-manifest.json"))
  invisible(key)
}

list_catalog_normalization_proposals <- function(root, unit) {
  paths <- list.files(file.path(root, "proposals", unit$key), pattern = "^proposal-manifest[.]json$", recursive = TRUE, full.names = TRUE)
  paths <- paths[order(file.info(paths)$mtime, decreasing = TRUE)]
  lapply(paths, read_source_json)
}

# Maintainer-authored AI drafts live in Git beside the institution's data. Stage
# them through the same validator/immutable store as future API or file input.
# Merely discovering a draft never creates a human review or inherits approval.
stage_catalog_normalization_drafts <- function(root, directory, capture_root) {
  paths <- sort(list.files(directory, pattern = "[.]json$", recursive = TRUE, full.names = TRUE))
  if (!length(paths)) return(invisible(character()))
  programs <- lapply(list_catalog_normalization_programs(root)$key, function(key) load_catalog_normalization_program(root, key))
  staged <- vapply(paths, function(path) {
    draft <- read_source_json(path)
    if (!identical(draft$schema_version, "1.0.0") || !is.numeric(draft$version) || length(draft$version) != 1L ||
        draft$version < 1 || draft$version != floor(draft$version) || !nzchar(trimws(draft$producer))) stop("[catalog-normalization.R] Invalid versioned draft: ", path)
    matches <- Filter(function(x) identical(x$packet$program_id, draft$program_id) && identical(x$packet$catalog_id, draft$catalog_id) &&
      draft$unit_key %in% vapply(x$packet$units, function(u) u$key, character(1)), programs)
    if (!length(matches)) stop("[catalog-normalization.R] Prepare the matching source packet before loading draft: ", path)
    program <- matches[[1]]; unit <- catalog_normalization_unit(program, draft$unit_key)
    verify_catalog_normalization_sources(program, unit, capture_root)
    response <- tempfile("cedar-draft-", fileext = ".json")
    on.exit(unlink(response), add = TRUE)
    write_source_json(draft$proposal, response)
    import_catalog_normalization(root, unit, response, paste(draft$producer, paste0("draft v", draft$version), sep = " · "))
  }, character(1))
  invisible(staged)
}

load_catalog_normalization_proposal <- function(root, unit, key) {
  directory <- file.path(root, "proposals", unit$key, catalog_normalization_key(key))
  meta <- read_source_json(file.path(directory, "proposal-manifest.json"))
  if (!identical(meta$schema_version, "1.0.0") || !identical(meta$key, key) || !identical(meta$unit_key, unit$key) ||
      !identical(meta$response_sha256, catalog_normalization_hash_file(file.path(directory, "response.json"))) ||
      !identical(key, source_sha256(source_json_bytes(list(unit$key, meta$response_sha256, meta$model))))) stop("[catalog-normalization.R] Imported proposal hash mismatch")
  proposal <- read_source_json(file.path(directory, "response.json"))
  validate_catalog_normalization(proposal, unit$request)
  list(meta = meta, original = proposal)
}

# Hash-linked complete revisions make decisions portable and stale tabs fail
# explicitly. A directory lock serializes writers across Shiny sessions.
read_catalog_normalization_review <- function(root, unit, imported) {
  directory <- file.path(root, "reviews", imported$meta$key)
  paths <- sort(list.files(directory, pattern = "^[0-9]{8}-[a-f0-9]{64}[.]json$", full.names = TRUE))
  state <- catalog_normalization_review_state(imported$original)
  for (path in paths) {
    hash <- catalog_normalization_hash_file(path)
    event <- read_source_json(path)
    if (!identical(basename(path), sprintf("%08d-%s.json", state$revision + 1L, hash)) ||
        !identical(event$previous, state$head) || event$revision != state$revision + 1L ||
        !identical(event$proposal_key, imported$meta$key) || !identical(event$unit_key, unit$key) || !nzchar(event$reviewer)) stop("[catalog-normalization.R] Review history is broken or belongs to different evidence")
    validate_catalog_normalization_state(event$state, unit$request)
    state <- event$state; state$head <- hash; state$revision <- event$revision
    state$last_review <- list(reviewer = event$reviewer, reviewed_at = event$reviewed_at)
  }
  state
}

save_catalog_normalization_review <- function(root, unit, imported, state, reviewer, expected_head) {
  if (!nzchar(trimws(reviewer))) stop("[catalog-normalization.R] Enter your name for the review record")
  imported <- load_catalog_normalization_proposal(root, unit, imported$meta$key)
  validate_catalog_normalization_state(state, unit$request)
  directory <- file.path(root, "reviews", imported$meta$key)
  dir.create(directory, recursive = TRUE, showWarnings = FALSE)
  lock <- file.path(directory, ".lock")
  if (!dir.create(lock, showWarnings = FALSE)) stop("[catalog-normalization.R] Another review is being saved; refresh and try again")
  on.exit(unlink(lock, recursive = TRUE), add = TRUE)
  current <- read_catalog_normalization_review(root, unit, imported)
  if (!identical(current$head, expected_head)) stop("[catalog-normalization.R] This review changed in another session. Refresh before saving")
  event <- list(schema_version = "1.0.0", proposal_key = imported$meta$key, unit_key = unit$key,
    previous = current$head, revision = current$revision + 1L, reviewer = trimws(reviewer),
    reviewed_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC"),
    state = state[setdiff(names(state), c("head", "revision", "last_review"))])
  bytes <- source_json_bytes(event); hash <- source_sha256(bytes)
  path <- file.path(directory, sprintf("%08d-%s.json", event$revision, hash))
  if (file.exists(path)) stop("[catalog-normalization.R] Review revision already exists")
  write_source_json(event, path)
  read_catalog_normalization_review(root, unit, imported)
}

export_catalog_normalization <- function(program, unit, imported, state) {
  if (!catalog_normalization_approved(state) || !nzchar(state$head) || state$revision < 1L) stop("[catalog-normalization.R] Resolve open review cases and sign off the complete unit before exporting reviewed requirements")
  list(schema_version = "1.0.0", status = "human_reviewed", catalog_id = program$packet$catalog_id,
    catalog_title = program$packet$catalog_title, target_entities = unit$request$target_entities,
    unit_key = unit$key, proposal_key = imported$meta$key, model = imported$meta$model,
    review_head = state$head, review_revision = state$revision, last_review = state$last_review,
    review_decisions = state[c("nodes", "blocks", "notes", "approval")], original_response_sha256 = imported$meta$response_sha256,
    requirements = state$proposal, source_blocks = unit$request$source_blocks,
    reference_registry = unit$request$reference_registry,
    runtime_status = "Canonical review export; not yet compiled into semester plans or projections")
}
