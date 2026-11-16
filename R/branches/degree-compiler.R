# Degree compiler, step 1: a reviewed catalog interpretation as draft board rows.
#
# An interpretation (institution/<id>/catalog_interpretations/, the
# normalized schema in config/catalog-normalization.schema.json) states a
# program's rules as a tree: required courses, choose-N groups, credit pools,
# conditions and unresolved questions, each citing catalog text. The semester
# board needs tiles. This file turns one into the other, as drafts:
#
#   course   a required course                       -> one tile
#   choice   choose-N, any-of, or N credits from a list -> one tile with options
#   slot     a credit or course pool inside a major group with no listed
#            courses ("12 upper-level HIST credits")  -> credits / 3 tiles, rounded
#   credit_rule  a credit requirement at the top of the tree with no listed
#            courses. The schema cannot say whether it is an elective pool
#            (CS's 9 technical-elective credits), a total (120 degree credits)
#            or residency, so it is listed for a reviewer, never made a tile.
#   condition    admission, policy, GPA, grade, permission, standing, restriction
#   flag         an unresolved interpretation, never guessed
#
# Concentrations (nodes whose entity is a specialization) are listed, not
# compiled. Semesters are not placed and prerequisite arrows are not drawn:
# that is step 2 (ROADMAP: Degree Explorer). Nothing here writes a board file.

DEGREE_COMPILER_CONDITION_KINDS <- c("gpa", "grade", "permission", "class_standing",
                                     "program_admission", "restriction")
DEGREE_COMPILER_SLOT_CREDITS <- 3

# A registry code ("CSCI1230", "ENGL1110Y") as CEDAR writes a course ("CSCI 1230").
degree_compiler_course_code <- function(code) {
  out <- sub("^([A-Z]+)\\s*([0-9].*)$", "\\1 \\2", code)
  bad <- !grepl("^[A-Z]+ [0-9]", out)
  if (any(bad)) stop("[degree-compiler.R] Not a course code: ", paste(code[bad], collapse = ", "))
  out
}

#' The courses a prepared catalog packet cites, from each course unit's record
#'
#' @param packet A prepared packet (`load_catalog_normalization_program()$packet`).
#' @return Tibble: `course_ref` (`courses:<id>`), `subject_course`, `title`,
#'   `credits_min`, `credits_max`. A course record without credits stops.
degree_packet_course_facts <- function(packet) {
  rows <- lapply(packet$units, function(unit) {
    docs <- unit$request$documents
    if (length(docs) != 1L || !startsWith(docs[[1]]$id, "courses:")) return(NULL)
    fields <- unit$request$source_blocks
    field <- function(name) {
      hit <- Filter(function(b) identical(b$field, name), fields)
      if (!length(hit)) stop("[degree-compiler.R] Course ", docs[[1]]$code, " has no '", name, "' field")
      jsonlite::fromJSON(hit[[1]]$text, simplifyVector = FALSE)
    }
    credits <- field("credits")$credits
    if (is.null(credits$min) || is.null(credits$max)) stop("[degree-compiler.R] Course ", docs[[1]]$code, " has no credit range")
    tibble::tibble(course_ref = docs[[1]]$id, subject_course = degree_compiler_course_code(docs[[1]]$code),
                   title = docs[[1]]$title, credits_min = as.numeric(credits$min),
                   credits_max = as.numeric(credits$max))
  })
  dplyr::bind_rows(rows)
}

# The proposal's nodes as a tibble, one row each, with the first citation.
degree_compiler_nodes <- function(proposal) {
  if (is.null(proposal$nodes) || !length(proposal$nodes)) stop("[degree-compiler.R] The interpretation has no rules")
  num <- function(x) if (is.null(x)) NA_real_ else as.numeric(x)
  dplyr::bind_rows(lapply(proposal$nodes, function(n) tibble::tibble(
    id = n$id, parent_id = n$parent_id, entity_id = n$entity_id, phase = n$phase, kind = n$kind,
    label = n$label, minimum = num(n$minimum), unit = n$unit, value = n$value,
    course_ref = if (length(n$course_refs)) unlist(n$course_refs)[1] else NA_character_,
    quote = if (length(n$citations)) n$citations[[1]]$quote else NA_character_)))
}

#' Compile one interpretation's base program into draft board rows
#'
#' @param proposal The interpretation's `proposal` (parsed JSON, unsimplified).
#' @param courses `degree_packet_course_facts()` for the same packet.
#' @return List: `rules` (one row per compiled rule: `rule_id`, `role`, `subject_course`,
#'   `label`, `tiles`, `credits`, `quote`), `options` (`rule_id`, `option_id`,
#'   `subject_course`), `conditions`, `credit_rules`, `flags`, `concentrations`,
#'   and `skipped` (information nodes).
compile_degree_interpretation <- function(proposal, courses) {
  needed <- c("course_ref", "subject_course", "credits_min")
  if (length(setdiff(needed, names(courses)))) stop("[degree-compiler.R] courses needs ", paste(needed, collapse = ", "))
  nodes <- degree_compiler_nodes(proposal)
  refs <- stats::na.omit(nodes$course_ref[nodes$kind == "course"])
  unknown <- setdiff(refs, courses$course_ref)
  if (length(unknown)) stop("[degree-compiler.R] Courses missing from the packet: ", paste(unknown, collapse = ", "))
  nodes <- dplyr::left_join(nodes, courses[c("course_ref", "subject_course", "credits_min")], by = "course_ref")

  base <- nodes[startsWith(nodes$entity_id, "programs:"), ]
  other <- nodes[!startsWith(nodes$entity_id, "programs:"), ]
  concentrations <- other %>%
    dplyr::group_by(entity_id) %>%
    dplyr::summarize(label = label[parent_id == "" | !parent_id %in% id][1], n_rules = dplyr::n(), .groups = "drop")

  kids <- function(id) base[base$parent_id == id, ]
  out <- list(rules = list(), options = list())
  add_rule <- function(node, role, tiles, credits, code = NA_character_) {
    out$rules[[length(out$rules) + 1L]] <<- tibble::tibble(rule_id = node$id, role = role, subject_course = code,
      label = node$label, tiles = as.integer(tiles), credits = credits, quote = node$quote)
  }
  add_options <- function(rule_id, children) {
    for (k in seq_len(nrow(children))) {
      codes <- degree_compiler_descendant_codes(base, children[k, ])
      out$options[[length(out$options) + 1L]] <<- tibble::tibble(rule_id = rule_id,
        option_id = children$id[k], subject_course = codes)
    }
  }
  # A choice needs k options; its credits are known when every option carries the same.
  choice_credits <- function(children, k) {
    each <- vapply(seq_len(nrow(children)), function(i)
      sum(base$credits_min[base$id %in% degree_compiler_descendants(base, children$id[i]) | base$id == children$id[i]], na.rm = TRUE), 0)
    if (length(unique(each)) == 1L) unique(each) * k else NA_real_
  }
  structural_kinds <- c("all", "any", "choose_n", "credits", "course_pool")
  # Inside a major group or a credit group, an unlisted pool is elective space.
  in_group <- function(id) {
    parent <- base$parent_id[base$id == id]
    while (nzchar(parent)) {
      if (base$kind[base$id == parent] %in% c("all", "credits", "course_pool")) return(TRUE)
      parent <- base$parent_id[base$id == parent]
    }
    FALSE
  }
  # Tiles a choice fills: k options, each as many courses as its largest option
  # (a two-course survey sequence is two tiles).
  option_size <- function(children) max(vapply(seq_len(nrow(children)), function(i)
    length(degree_compiler_descendant_codes(base, children[i, ])), 1L))
  walk <- function(id) {
    level <- kids(id)
    for (i in seq_len(nrow(level))) {
      node <- level[i, ]
      children <- kids(node$id)
      listed <- children[children$kind == "course", ]
      if (node$kind == "information" || node$kind == "unresolved") next
      if (node$phase %in% c("admission", "policy") || node$kind %in% DEGREE_COMPILER_CONDITION_KINDS) next
      if (node$kind == "course") { add_rule(node, "course", 1L, node$credits_min, node$subject_course); next }
      if (node$kind == "all") { walk(node$id); next }
      if (node$kind %in% c("choose_n", "any")) {
        k <- if (node$kind == "any" || is.na(node$minimum)) 1 else node$minimum
        options <- children[children$kind %in% c("course", structural_kinds), ]
        add_rule(node, "choice", k * option_size(options), choice_credits(options, k))
        add_options(node$id, options); next
      }
      if (node$kind %in% c("credits", "course_pool")) {
        # A credit group with sub-pools or groups: its courses are required, its pools are slots.
        if (any(children$kind %in% structural_kinds)) { walk(node$id); next }
        if (nrow(listed)) {
          if (node$kind == "credits" && isTRUE(sum(listed$credits_min) == node$minimum)) { walk(node$id); next }
          n <- if (node$kind == "credits") degree_compiler_slot_tiles(node$minimum) else node$minimum
          add_rule(node, "choice", n, if (node$kind == "credits") node$minimum else NA_real_)
          add_options(node$id, listed); next
        }
        if (in_group(node$id)) {
          n <- if (node$kind == "credits") degree_compiler_slot_tiles(node$minimum) else node$minimum
          add_rule(node, "slot", n, if (node$kind == "credits") node$minimum else NA_real_)
        }
        # Otherwise a credit requirement the schema cannot place: listed below.
      }
    }
  }
  walk("")
  chosen <- unlist(lapply(out$rules, function(r) if (r$role == "choice") degree_compiler_descendants(base, r$rule_id)))
  in_choice <- function(ids) ids %in% chosen
  is_tile <- base$id %in% vapply(out$rules, function(r) r$rule_id, "")
  has_structure <- vapply(base$id, function(id) any(base$kind[base$parent_id == id] %in% c("course", structural_kinds)), TRUE)
  credit_rule <- base$kind %in% c("credits", "course_pool") & base$phase == "degree" & !is_tile &
    !has_structure & !in_choice(base$id)
  list(
    rules = dplyr::bind_rows(out$rules),
    options = dplyr::bind_rows(out$options),
    conditions = base[base$phase %in% c("admission", "policy") & !base$kind %in% c("unresolved", "information") |
                        base$phase == "degree" & base$kind %in% DEGREE_COMPILER_CONDITION_KINDS,
                      c("id", "phase", "kind", "label", "minimum", "unit")],
    credit_rules = base[credit_rule, c("id", "label", "minimum", "unit")],
    flags = base[base$kind == "unresolved", c("id", "phase", "label", "value")],
    concentrations = concentrations,
    skipped = base[base$kind == "information", c("id", "label")]
  )
}

# Tiles for a pool of credits: the nearest whole number of 3-credit courses,
# at least one (a 4-credit lab science is one course, 18 credits six).
degree_compiler_slot_tiles <- function(credits) max(1L, as.integer(round(credits / DEGREE_COMPILER_SLOT_CREDITS)))

degree_compiler_descendants <- function(nodes, id) {
  found <- character(); frontier <- id
  while (length(frontier)) {
    frontier <- nodes$id[nodes$parent_id %in% frontier]
    found <- c(found, frontier)
  }
  found
}

# The course codes an option stands for: itself, or every course under a bundle.
degree_compiler_descendant_codes <- function(nodes, option) {
  if (option$kind == "course") return(option$subject_course)
  within <- nodes[nodes$id %in% degree_compiler_descendants(nodes, option$id) & nodes$kind == "course", ]
  if (!nrow(within)) stop("[degree-compiler.R] Option ", option$id, " lists no course")
  within$subject_course
}

#' Compare a compiled program with its hand-built board
#'
#' @param compiled `compile_degree_interpretation()` output.
#' @param roadmaps `read_degree_roadmaps()` output.
#' @param catalog_id The hand-built board's catalog id.
#' @return List: `required_on_board`, `required_on_shared_routes` (math and
#'   English starting routes), `required_not_on_board` (compiled required
#'   courses), `board_not_compiled` (courses the board shows that the compiled
#'   rules neither require nor offer), `choices` (each compiled choice
#'   with the board courses among its options), `slot_credits` (compiled vs board),
#'   `tiles` (compiled vs board count).
compare_compiled_degree <- function(compiled, roadmaps, catalog_id) {
  board <- roadmaps$nodes[roadmaps$nodes$catalog_id == catalog_id, ]
  if (!nrow(board)) stop("[degree-compiler.R] No hand-built board for ", catalog_id)
  # A tile's courses are the board's own component list (a lecture + lab tile
  # is two courses), and a choice tile's are its options.
  board_codes <- unique(c(roadmaps$courses$subject_course[roadmaps$courses$catalog_id == catalog_id],
                          roadmaps$options$subject_course[roadmaps$options$catalog_id == catalog_id]))
  board_slot_credits <- sum(as.numeric(board$credits[grepl("^[A-Z]+ [0-9]+[\u2013-][0-9]+$", board$code)]))
  # Math and English courses reach every board through the shared starting
  # routes (catalog_id "*"); a required one there is on the board.
  shared <- roadmaps$courses$subject_course[roadmaps$courses$catalog_id == "*"]
  rules <- compiled$rules
  required <- rules$subject_course[rules$role == "course"]
  offered <- unique(compiled$options$subject_course)
  choices <- rules[rules$role == "choice", c("rule_id", "label")]
  choices$options <- vapply(choices$rule_id, function(id) length(unique(compiled$options$subject_course[compiled$options$rule_id == id])), 1L, USE.NAMES = FALSE)
  choices$on_board <- vapply(choices$rule_id, function(id)
    paste(sort(intersect(compiled$options$subject_course[compiled$options$rule_id == id], c(board_codes, shared))), collapse = ", "), "", USE.NAMES = FALSE)
  list(
    required_on_board = sort(intersect(required, board_codes)),
    required_on_shared_routes = sort(intersect(setdiff(required, board_codes), shared)),
    required_not_on_board = sort(setdiff(required, c(board_codes, shared))),
    board_not_compiled = sort(setdiff(board_codes, c(required, offered))),
    choices = choices,
    slot_credits = c(compiled = sum(rules$credits[rules$role == "slot"], na.rm = TRUE), board = board_slot_credits),
    tiles = c(compiled = sum(rules$tiles), board = nrow(board))
  )
}

# ── Text preview ─────────────────────────────────────────────────────────────

#' The compiled program and its comparison as plain text, for a reviewer
#'
#' @param title The program's name.
#' @param compiled `compile_degree_interpretation()` output.
#' @param comparison `compare_compiled_degree()` output, or `NULL` when the
#'   program has no hand-built board.
format_compiled_degree_preview <- function(title, compiled, comparison = NULL) {
  codes <- function(x) if (length(x)) paste(x, collapse = ", ") else "none"
  credits <- function(x) ifelse(is.na(x), "credits vary", paste(x, "credits"))
  rules <- compiled$rules
  tile_lines <- vapply(seq_len(nrow(rules)), function(i) {
    r <- rules[i, ]
    what <- switch(r$role,
      course = r$subject_course,
      choice = paste0("Choice: ", r$label, " [", codes(unique(compiled$options$subject_course[compiled$options$rule_id == r$rule_id])), "]"),
      slot = paste0("Elective space: ", r$label))
    paste0("  ", what, " \u00b7 ", r$tiles, if (r$tiles == 1L) " tile" else " tiles", " \u00b7 ", credits(r$credits))
  }, "")
  listed <- function(heading, frame, text) c(paste0(heading, " (", nrow(frame), ")"), if (nrow(frame)) paste0("  ", text(frame)))
  out <- c(title,
    paste0("Board tiles (", sum(rules$tiles), "):"), tile_lines,
    listed("Credit rules the reading cannot place on the board", compiled$credit_rules, function(f) f$label),
    listed("Conditions", compiled$conditions, function(f) paste0(f$phase, ": ", f$label)),
    listed("Unresolved, for a reviewer", compiled$flags, function(f) f$label),
    listed("Concentrations not compiled", compiled$concentrations, function(f) paste0(f$label, " (", f$n_rules, " rules)")))
  if (!is.null(comparison)) {
    out <- c(out, "Against the hand-built board:",
      paste0("  Tiles: ", comparison$tiles[["compiled"]], " compiled, ", comparison$tiles[["board"]], " on the board"),
      paste0("  Elective credits: ", comparison$slot_credits[["compiled"]], " compiled, ", comparison$slot_credits[["board"]], " on the board"),
      paste0("  Required and on the board: ", codes(comparison$required_on_board)),
      paste0("  Required, on the shared math and English routes: ", codes(comparison$required_on_shared_routes)),
      paste0("  Required, missing from the board: ", codes(comparison$required_not_on_board)),
      paste0("  On the board, not in the reading: ", codes(comparison$board_not_compiled)),
      if (nrow(comparison$choices)) paste0("  Choice ", comparison$choices$label, ": ", comparison$choices$options,
                                           " options; the board shows ", ifelse(nzchar(comparison$choices$on_board), comparison$choices$on_board, "none")))
  }
  paste(out, collapse = "\n")
}
