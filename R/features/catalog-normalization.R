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

#' Every committed catalog reading, matched to its files
#'
#' A reading is staged from its source packet (in the store, `root`) and the
#' catalog pages that packet cites (in the archive, `capture_root`); neither
#' is in Git. A reading short of either is named, every such reading in one
#' error, so a server without the files says which (ISSUES I101). The deploy
#' runs this before it recreates the app (`scripts/check-catalog-store.R`),
#' so a reading cannot ship without its files; staging runs it first.
#'
#' @param root The institution's catalog-normalization store.
#' @param directory The committed readings (`catalog_interpretations/`).
#' @param capture_root The institution's catalog archive.
#' @param paths The reading files, when not every one in `directory`
#'   (`check_catalog_reading()` matches one).
#' @return One list per reading: `path`, `draft`, its packet's `program` and
#'   the packet's `unit` it was read from.
catalog_normalization_draft_units <- function(root, directory, capture_root,
    paths = sort(list.files(directory, pattern = "[.]json$", recursive = TRUE, full.names = TRUE))) {
  if (!length(paths)) return(list())
  programs <- lapply(list_catalog_normalization_programs(root)$key, function(key) load_catalog_normalization_program(root, key))
  short <- character()
  drafts <- lapply(paths, function(path) {
    draft <- read_source_json(path)
    if (!identical(draft$schema_version, "1.0.0") || !is.numeric(draft$version) || length(draft$version) != 1L ||
        draft$version < 1 || draft$version != floor(draft$version) || !nzchar(trimws(draft$producer))) stop("[catalog-normalization.R] Invalid versioned draft: ", path)
    matches <- Filter(function(x) identical(x$packet$program_id, draft$program_id) && identical(x$packet$catalog_id, draft$catalog_id) &&
      draft$unit_key %in% vapply(x$packet$units, function(u) u$key, character(1)), programs)
    if (!length(matches)) {
      short <<- c(short, paste0(path, ": no matching source packet in ", root))
      return(NULL)
    }
    program <- matches[[1]]; unit <- catalog_normalization_unit(program, draft$unit_key)
    # Collected, not recovered: every reading short of its sources is named below.
    missing <- tryCatch({
      verify_catalog_normalization_sources(program, unit, capture_root)
      NULL
    }, error = function(e) conditionMessage(e))
    if (!is.null(missing)) {
      short <<- c(short, paste0(path, ": ", missing))
      return(NULL)
    }
    list(path = path, draft = draft, program = program, unit = unit)
  })
  if (length(short)) stop("[catalog-normalization.R] ", length(short), " of ", length(paths),
    " catalog readings are missing their source packet or captured pages here. Copy them from the machine ",
    "that prepared them with scripts/sync-catalog-store.sh.\n", paste(short, collapse = "\n"), call. = FALSE)
  drafts
}

#' Every problem in one catalog reading, found before it is committed
#'
#' What staging would refuse, and the triage the board compiler checks, all
#' in one pass, so a reading is fixed in one round rather than one error at a
#' time: the file's own fields and its source packet and captured pages
#' (`catalog_normalization_draft_units()`), every problem in its proposal
#' (`catalog_normalization_problems()`, each naming its node, block or
#' question), and its triage against the open items
#' (`degree_reading_question_rows()`). A problem that stops the rest from
#' being read (no packet, a proposal of the wrong shape) is reported alone.
#' What needs the board too (`gen_ed_pools`, the degree total, a catalog row)
#' is checked when the readings are compiled.
#'
#' @param path The reading file.
#' @param root The institution's catalog-normalization store.
#' @param capture_root The institution's catalog archive.
#' @return List: `path`, `problems` (character, empty when the reading is
#'   ready to commit) and `open` (its open items, `degree_reading_question_rows()`,
#'   or NULL when problems keep them from being read).
check_catalog_reading <- function(path, root, capture_root) {
  result <- function(problems, open = NULL) list(path = path, problems = problems, open = open)
  # Collected, not recovered: a reading that cannot be matched is reported as its one problem.
  matched <- tryCatch(catalog_normalization_draft_units(root, capture_root = capture_root, paths = path)[[1]],
    error = function(e) conditionMessage(e))
  if (is.character(matched)) return(result(sub("^\\[catalog-normalization\\.R\\] ", "", matched)))
  proposal <- matched$draft$proposal; request <- matched$unit$request
  problems <- catalog_normalization_problems(proposal, request)
  # A proposal of the wrong shape has no open items to check the triage against.
  if (length(catalog_json_schema_problems(proposal, request$response_schema))) return(result(problems))
  # Collected, not recovered: the triage's problem is the reading's.
  open <- tryCatch(degree_reading_question_rows(matched$draft, matched$program$packet), error = function(e) conditionMessage(e))
  if (is.character(open)) return(result(c(problems, sub("^\\[catalog-normalization\\.R\\] ", "", open))))
  result(problems, if (!length(problems)) open)
}

#' A reading check as lines for the terminal
#'
#' @param check `check_catalog_reading()` output.
#' @return Character vector: the file and its verdict, then one line per
#'   problem, or the reading's open items by who can settle them.
format_catalog_reading_check <- function(check) {
  if (length(check$problems)) {
    return(c(paste0(check$path, ": ", length(check$problems), if (length(check$problems) == 1L) " problem" else " problems"),
             paste0("  ", gsub("\n", "\n  ", check$problems, fixed = TRUE))))
  }
  who <- catalog_question_settler_label(check$open$settled_by)
  counts <- table(factor(who, levels = unique(c(unname(CATALOG_QUESTION_SETTLERS), CATALOG_QUESTION_NOT_SORTED))))
  counts <- counts[counts > 0]
  c(paste0(check$path, ": ready to commit; ", nrow(check$open), if (nrow(check$open) == 1L) " open item" else " open items",
           if (length(counts)) paste0(" (", paste(paste0(names(counts), " ", counts), collapse = ", "), ")")),
    if (nrow(check$open)) paste0("  ", check$open$item, " [", who, "]: ", check$open$label))
}

# A packet's one unit for its program and embedded concentrations; the rest
# are its linked courses' units.
catalog_normalization_program_unit <- function(program) {
  units <- Filter(function(u) identical(u$title, "Program and concentrations"), program$packet$units)
  if (length(units) != 1L) stop("[catalog-normalization.R] Packet ", program$meta$key, " has ", length(units), " program units, not one")
  units[[1]]
}

#' The packet a new reading of a program is written from
#'
#' A program can have several packets in the store, one for each prompt and
#' schema it was prepared under, kept for the readings written from them. A
#' new reading is written from the one prepared under the current prompt and
#' schema; passing a packet key selects that packet instead. Packets whose
#' program units are the same unit (the same sources, prepared again from an
#' archive somewhere else: ISSUES I103) are one choice, and the most recently
#' prepared is returned.
#'
#' @param root The institution's catalog-normalization store.
#' @param program The catalog's program id (as in the program's catalog
#'   page), or a packet key.
#' @param prompt,schema The current instructions and response schema
#'   (`config/catalog-normalization-prompt.txt`, `...schema.json`).
#' @return `load_catalog_normalization_program()` output.
catalog_normalization_current_packet <- function(root, program, prompt, schema) {
  if (grepl("^[a-f0-9]{64}$", program)) return(load_catalog_normalization_program(root, program))
  loaded <- lapply(list_catalog_normalization_programs(root)$key, function(key) load_catalog_normalization_program(root, key))
  mine <- Filter(function(x) identical(x$packet$program_id, program), loaded)
  if (!length(mine)) {
    stop("[catalog-normalization.R] No packet for program ", program, " in ", root,
         ": prepare it first (scripts/normalize-degree-catalog.R prepare)", call. = FALSE)
  }
  current <- Filter(function(x) {
    request <- catalog_normalization_program_unit(x)$request
    identical(request$instructions, prompt) && identical(request$response_schema, schema)
  }, mine)
  # The listing is newest first, so the first packet of each unit is kept.
  units <- vapply(current, function(x) catalog_normalization_program_unit(x)$key, "")
  current <- current[!duplicated(units)]
  if (!length(current)) {
    stop("[catalog-normalization.R] None of program ", program, "'s ", length(mine),
         " packets was prepared under the current prompt and schema: prepare it again", call. = FALSE)
  }
  if (length(current) > 1L) {
    stop("[catalog-normalization.R] Program ", program, " has ", length(current),
         " packets from different sources under the current prompt and schema; pass one of their keys: ",
         paste(vapply(current, function(x) paste(x$meta$key, x$packet$catalog_title), ""), collapse = "; "), call. = FALSE)
  }
  current[[1]]
}

#' A program unit as the lines a reading is written from
#'
#' Everything a reading needs from its packet, in one place: the fields its
#' file names, every passage it must cover (full id, entity, record field,
#' section, text) and every reference a node may name.
#'
#' @param program `load_catalog_normalization_program()` output.
#' @return Character vector.
format_catalog_normalization_unit <- function(program) {
  packet <- program$packet; unit <- catalog_normalization_program_unit(program); request <- unit$request
  blocks <- request$source_blocks; registry <- request$reference_registry
  links <- vapply(request$unresolved_links, function(x) paste(unlist(x), collapse = " "), "")
  c(paste0(packet$title, " · ", packet$catalog_title),
    paste0("The reading's fields: program_id ", packet$program_id, ", catalog_id ", packet$catalog_id,
           ", unit_key ", unit$key),
    paste0("Packet ", program$meta$key),
    paste0("Targets (a node's entity_id): ", paste(unlist(request$target_entities), collapse = ", ")),
    if (length(links)) paste0("Linked, not captured: ", paste(links, collapse = "; ")),
    "", paste0(length(blocks), " passages, each covered exactly once:"),
    unlist(lapply(blocks, function(b) c(paste0("[", b$id, "] ", b$entity_id, " · ", b$field, " · ", b$section),
                                        paste0("    ", b$text)))),
    "", paste0(length(registry), " references a node may name:"),
    vapply(registry, function(r) paste0("    ", r$id, "  ", r$code, "  ", r$title), ""))
}

# Maintainer-authored AI drafts live in Git beside the institution's data. Stage
# them through the same validator/immutable store as future API or file input.
# Merely discovering a draft never creates a human review or inherits approval.
stage_catalog_normalization_drafts <- function(root, directory, capture_root) {
  drafts <- catalog_normalization_draft_units(root, directory, capture_root)
  if (!length(drafts)) return(invisible(character()))
  staged <- vapply(drafts, function(x) {
    response <- tempfile("cedar-draft-", fileext = ".json")
    on.exit(unlink(response), add = TRUE)
    write_source_json(x$draft$proposal, response)
    import_catalog_normalization(root, x$unit, response, paste(x$draft$producer, paste0("draft v", x$draft$version), sep = " · "))
  }, character(1))
  names(staged) <- vapply(drafts, function(x) x$path, character(1))
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
