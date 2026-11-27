# Compiled degree boards on the page: written offline, loaded at startup in
# place of the hand-built board for the same program, or beside the hand-built
# boards for a program that has none, and labelled from the review store.
#
# scripts/compile-degree-interpretations.R --write compiles each catalog reading
# (degree-compiler.R, degree-compiler-board.R) and writes its board's own rows
# to institution/<id>/degree_drafts/, beside a manifest naming the reading it
# came from. The app reads that folder, puts each draft in place of the
# authored board with the same catalog id, adds a draft whose program has no
# authored board after the authored ones (its catalog row is the institution's
# degree_reading_catalogs.csv row, carried in the draft), and validates the
# result with the same validators: a draft's Banner program codes are checked
# against programs.csv like an authored board's, and a code on two boards
# stops startup. The authored files are never edited; they stay the baseline
# the compiler is compared with.
#
# A draft shows as reviewed only when Admin > Catalog Review holds a complete
# sign-off of that exact reading. Anything else (no review store, the reading
# not staged, not signed off, or signed off after edits the board was not
# recompiled from) shows it as a draft, saying which.

DEGREE_DRAFT_TABLES <- c(catalogs = "degree_catalogs", rules = "degree_rules", courses = "degree_rule_courses",
  evidence = "degree_catalog_evidence", nodes = "degree_roadmap_nodes", links = "degree_roadmap_links",
  math_routes = "degree_roadmap_math_routes", conditions = "degree_roadmap_conditions", basis = "degree_roadmap_basis",
  plans = "degree_roadmap_plans", roadmap_courses = "degree_roadmap_courses", options = "degree_roadmap_options")

# One row per line, as every institution file is (read_institution_file()).
degree_draft_one_line <- function(df) {
  df[] <- lapply(df, function(x) gsub("[[:space:]]*[\r\n]+[[:space:]]*", " ", as.character(x)))
  df
}

#' Write compiled boards to a drafts folder, replacing what it held
#'
#' @param boards Named list (by catalog id) of `assemble_compiled_degree_board()`
#'   output, each built with its authored board's catalog id.
#' @param manifest One `degree_drafts` row per board.
#' @param authored_evidence The institution's evidence: a draft writes only the
#'   citations it adds.
#' @param questions Every latest reading's open items, board or not
#'   (`degree_reading_question_rows()` with the `degree_reading_questions`
#'   columns), written to `degree_reading_questions.csv`.
write_degree_drafts <- function(boards, manifest, dir, authored_evidence, questions) {
  if (!setequal(names(boards), manifest$catalog_id) || anyDuplicated(manifest$catalog_id)) {
    stop("[degree-drafts.R] One manifest row per compiled board")
  }
  dir.create(dir, recursive = TRUE, showWarnings = FALSE)
  own <- function(b, table) {
    x <- if (table %in% c("catalogs", "rules", "courses", "evidence")) b$catalog[[table]]
         else b$roadmaps[[if (table == "roadmap_courses") "courses" else table]]
    id <- b$catalog$catalogs$catalog_id
    if (table == "evidence") x[!x$evidence_id %in% authored_evidence$evidence_id, ]
    else if (table == "courses") x[x$rule_id %in% b$catalog$rules$rule_id[b$catalog$rules$catalog_id == id], ]
    else x[x$catalog_id == id, ]
  }
  for (table in names(DEGREE_DRAFT_TABLES)) {
    name <- DEGREE_DRAFT_TABLES[[table]]
    rows <- do.call(rbind, lapply(boards[manifest$catalog_id], own, table = table))
    rows <- degree_draft_one_line(rows[CEDAR_CONFIG_FILE_SPECS[[name]]])
    utils::write.csv(rows, file.path(dir, paste0(name, ".csv")), row.names = FALSE, na = "")
  }
  utils::write.csv(degree_draft_one_line(manifest[CEDAR_CONFIG_FILE_SPECS$degree_drafts]),
                   file.path(dir, "degree_drafts.csv"), row.names = FALSE, na = "")
  utils::write.csv(degree_draft_one_line(as.data.frame(questions)[CEDAR_CONFIG_FILE_SPECS$degree_reading_questions]),
                   file.path(dir, "degree_reading_questions.csv"), row.names = FALSE, na = "")
  invisible(dir)
}

# A reading file's own bytes, hashed: its triage is outside the proposal, so a
# change to who settles a question changes this and not the proposal's hash.
degree_reading_file_sha256 <- function(path) source_sha256(readBin(path, "raw", file.size(path)))

#' The staged proposal a reading became in Catalog Review
#'
#' Staging (`stage_catalog_normalization_drafts()`) keys a reading by its unit,
#' its bytes and its producer; the key is the same in every review store.
degree_reading_proposal_key <- function(root, program, reading) {
  unit <- catalog_normalization_unit(program, reading$unit_key)
  model <- paste(reading$producer, paste0("draft v", reading$version), sep = " \u00b7 ")
  hit <- Filter(function(m) identical(m$model, model), list_catalog_normalization_proposals(root, unit))
  if (length(hit) != 1L) stop("[degree-drafts.R] Stage the reading in ", root, " first (scripts/normalize-degree-catalog.R stage): ", reading$program_id)
  hit[[1]]$key
}

#' Read a drafts folder
#'
#' @param programs The institution's `programs` file, which each draft's Banner
#'   program codes are checked against (degree_catalog_program_codes()).
#' @return NULL when the institution has no drafts folder; otherwise a list of
#'   the draft tables (named as in `DEGREE_DRAFT_TABLES`), `manifest`,
#'   `program_codes`, `questions` (`degree_reading_questions`) and
#'   `questions_stale`: the readings, by path, edited or removed since the
#'   questions were compiled (the folder sits in the institution's directory,
#'   and each `reading` is a path from there).
read_degree_drafts <- function(dir, programs) {
  if (!dir.exists(dir)) return(NULL)
  drafts <- lapply(DEGREE_DRAFT_TABLES, read_institution_file, dir = dir)
  drafts$manifest <- read_institution_file("degree_drafts", dir)
  if (anyDuplicated(drafts$manifest$catalog_id) || !setequal(drafts$manifest$catalog_id, drafts$catalogs$catalog_id)) {
    stop("[degree-drafts.R] ", dir, ": each draft board needs one manifest row and one catalog row")
  }
  drafts$program_codes <- degree_catalog_program_codes(drafts$catalogs, programs)
  drafts$questions <- read_institution_file("degree_reading_questions", dir)
  if (!all(drafts$questions$settled_by %in% c("", names(CATALOG_QUESTION_SETTLERS)))) {
    stop("[degree-drafts.R] ", dir, ": degree_reading_questions.csv has an unknown settled_by")
  }
  compiled <- unique(drafts$questions[c("reading", "reading_file_sha256")])
  paths <- file.path(dirname(dir), compiled$reading)
  now <- vapply(paths, function(p) if (file.exists(p)) degree_reading_file_sha256(p) else "", "", USE.NAMES = FALSE)
  drafts$questions_stale <- compiled$reading[now != compiled$reading_file_sha256]
  drafts
}

#' The boards the page shows: each draft in place of its authored board
#'
#' A draft with an authored board's catalog id takes that board's place in the
#' degree list; a draft for a program with no authored board follows the
#' authored boards, in the manifest's order.
#'
#' @param drafts `read_degree_drafts()` output, or NULL.
#' @param status `degree_board_review_status()` for the drafts.
#' @return List: `catalog`, `roadmaps` (validated), `status` (one row per
#'   catalog: `catalog_id`, `source` "authored" or "compiled", `review`
#'   "draft" / "reviewed" / NA for authored, `note`).
publish_degree_drafts <- function(catalog, roadmaps, drafts, status) {
  authored <- data.frame(catalog_id = catalog$catalogs$catalog_id, source = "authored", review = NA_character_, note = "")
  if (is.null(drafts)) return(list(catalog = catalog, roadmaps = roadmaps, status = authored))
  ids <- drafts$manifest$catalog_id
  if (!setequal(status$catalog_id, ids)) stop("[degree-drafts.R] One review status per draft board")
  added <- setdiff(ids, catalog$catalogs$catalog_id)
  clash <- intersect(drafts$evidence$evidence_id, catalog$evidence$evidence_id)
  if (length(clash)) stop("[degree-drafts.R] Draft evidence ids already in the institution's evidence: ", paste(clash, collapse = ", "))
  swap <- function(old, new) rbind(old[!old$catalog_id %in% ids, ], new)
  kept_rules <- catalog$rules[!catalog$rules$catalog_id %in% ids, ]
  # Keep the authored order of the degree list; a draft takes its board's
  # place, and a program with no authored board follows them.
  catalogs <- catalog$catalogs
  replaced <- drafts$catalogs[!drafts$catalogs$catalog_id %in% added, ]
  # A draft copies its board's row when compiled; codes decided since need a recompile.
  stale <- replaced$catalog_id[replaced$program_codes != catalogs$program_codes[match(replaced$catalog_id, catalogs$catalog_id)]]
  if (length(stale)) {
    stop("[degree-drafts.R] A draft's Banner program codes differ from its authored board's (recompile the drafts): ",
         paste(stale, collapse = ", "))
  }
  catalogs[match(replaced$catalog_id, catalogs$catalog_id), ] <- replaced[names(catalogs)]
  catalogs <- rbind(catalogs, drafts$catalogs[match(added, drafts$catalogs$catalog_id), names(catalogs)])
  published <- validate_degree_catalog(list(catalogs = catalogs, rules = rbind(kept_rules, drafts$rules),
    courses = rbind(catalog$courses[catalog$courses$rule_id %in% kept_rules$rule_id, ], drafts$courses),
    evidence = rbind(catalog$evidence, drafts$evidence)))
  published$program_codes <- rbind(catalog$program_codes[!catalog$program_codes$catalog_id %in% ids, ], drafts$program_codes)
  boards <- roadmaps
  for (table in c("nodes", "links", "math_routes", "conditions", "basis", "plans", "options")) boards[[table]] <- swap(roadmaps[[table]], drafts[[table]])
  boards$courses <- swap(roadmaps$courses, drafts$roadmap_courses)
  boards <- validate_degree_roadmaps(boards, published)
  status_rows <- data.frame(catalog_id = catalogs$catalog_id, source = "authored", review = NA_character_, note = "")
  at <- match(status$catalog_id, status_rows$catalog_id)
  status_rows$source[at] <- "compiled"; status_rows$review[at] <- status$review; status_rows$note[at] <- status$note
  list(catalog = published, roadmaps = boards, status = status_rows)
}

#' Whether each draft's reading is signed off in Catalog Review
#'
#' Reads the review store the Catalog Review admin writes. Reviewed only when
#' the reading is signed off as a whole and the signed-off reading is the one
#' the board was compiled from; otherwise a draft, with the reason.
#' @param drafts `read_degree_drafts()` output, or NULL.
#' @param review_root The institution's `catalog-normalizations` store.
#' @return Tibble: `catalog_id`, `review` ("draft" or "reviewed"), `note`.
degree_board_review_status <- function(drafts, review_root) {
  none <- tibble::tibble(catalog_id = character(), review = character(), note = character())
  if (is.null(drafts)) return(none)
  m <- drafts$manifest
  dplyr::bind_rows(none, lapply(seq_len(nrow(m)), function(i) {
    row <- m[i, ]
    draft <- function(note) tibble::tibble(catalog_id = row$catalog_id, review = "draft", note = note)
    packet <- file.path(review_root, "programs", row$packet_key)
    proposal <- file.path(review_root, "proposals", row$unit_key, catalog_normalization_key(row$proposal_key))
    if (!dir.exists(packet) || !dir.exists(proposal)) return(draft("Its catalog reading is not staged in Catalog Review."))
    program <- load_catalog_normalization_program(review_root, row$packet_key)
    unit <- catalog_normalization_unit(program, row$unit_key)
    imported <- load_catalog_normalization_proposal(review_root, unit, row$proposal_key)
    state <- read_catalog_normalization_review(review_root, unit, imported)
    if (!catalog_normalization_approved(state)) return(draft("Its catalog reading is not signed off in Catalog Review."))
    if (!identical(source_sha256(source_json_bytes(state$proposal)), row$reading_sha256)) {
      return(draft("Its reading was signed off after edits; the board has not been recompiled from the edited reading."))
    }
    tibble::tibble(catalog_id = row$catalog_id, review = "reviewed",
      note = paste0("Its catalog reading was signed off in Catalog Review on ", substr(state$last_review$reviewed_at, 1, 10), "."))
  }))
}
