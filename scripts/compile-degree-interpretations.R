#!/usr/bin/env Rscript
# Degree compiler: print each catalog interpretation as draft board rows beside
# its hand-built board, and with --write, publish the compiled boards. No model
# or network calls. See docs/developers/catalog-normalization.md.
#
# Rscript --vanilla scripts/compile-degree-interpretations.R --root REVIEW_ROOT [--analysis DIR [--write]] [--institution ID]
#   REVIEW_ROOT  the prepared packets (scripts/normalize-degree-catalog.R prepare --output)
#   DIR          a catalog analysis from extractor 1.4.0 or later: with it, each
#                reading is also assembled into a draft board and placed beside
#                the hand-built board, semester by semester
#   --write      replace institution/<id>/degree_drafts/ with every compiled board.
#                Each takes the place of the hand-built board for its program on
#                the page (labelled a draft until its reading is signed off); the
#                hand-built files are not touched. Each reading must be staged in
#                REVIEW_ROOT (scripts/normalize-degree-catalog.R stage).
args <- commandArgs(trailingOnly = TRUE)
usage <- "Usage: Rscript --vanilla scripts/compile-degree-interpretations.R --root REVIEW_ROOT [--analysis DIR [--write]] [--institution ID]"
if (!length(args) || args[1] %in% c("--help", "-h")) { cat(usage, "\n"); quit(status = 0) }
write <- "--write" %in% args; args <- setdiff(args, "--write")
opts <- list()
while (length(args)) {
  if (!args[1] %in% c("--root", "--analysis", "--institution") || args[1] %in% names(opts) || length(args) < 2L) stop(usage, call. = FALSE)
  opts[[args[1]]] <- args[2]; args <- args[-c(1L, 2L)]
}
if (is.null(opts[["--root"]]) || (write && is.null(opts[["--analysis"]]))) stop(usage, call. = FALSE)
script <- sub("^--file=", "", grep("^--file=", commandArgs(FALSE), value = TRUE)[1])
base <- normalizePath(file.path(dirname(script), ".."))
cedar_base_dir <- base
cedar_data_dir <- file.path(base, "data")
cedar_output_dir <- file.path(base, "output")
suppressPackageStartupMessages(library(dplyr))
if (!is.null(opts[["--institution"]])) Sys.setenv(CEDAR_INSTITUTION = opts[["--institution"]])
source(file.path(base, "R/trunk/load-funcs.R")); load_funcs(base, modules = FALSE)

root <- normalizePath(opts[["--root"]], mustWork = TRUE)
keys <- basename(list.dirs(file.path(root, "programs"), recursive = FALSE))
packets <- lapply(stats::setNames(keys, keys), function(key) load_catalog_normalization_program(root, key)$packet)
packet_programs <- vapply(packets, function(p) p$program_id, "")
if (!is.null(opts[["--analysis"]])) {
  rule_nodes <- utils::read.csv(file.path(normalizePath(opts[["--analysis"]], mustWork = TRUE), "rule-nodes.csv"),
                                colClasses = "character", check.names = FALSE)
  # A program with no math requirement plans toward the shared course most
  # authored boards show as their illustrative general-education math.
  r <- CEDAR_DEGREE_ROADMAPS
  general <- r$basis$node_id[r$basis$basis == "general" & r$basis$node_id %in% r$nodes$node_id[r$nodes$catalog_id == "*" & r$nodes$track == "math"]]
  general_math <- names(sort(table(general), decreasing = TRUE))[1]
}
readings <- list.files(file.path(cedar_institution_dir(), "catalog_interpretations"), "\\.json$", recursive = TRUE, full.names = TRUE)
boards <- list(); manifest <- list()
if (!length(readings)) stop("No catalog interpretations under ", file.path(cedar_institution_dir(), "catalog_interpretations"))

for (path in readings) {
  reading <- read_source_json(path)
  key <- names(packet_programs)[packet_programs == reading$program_id]
  if (length(key) != 1L) stop("No single prepared packet for ", basename(path), " (", reading$program_id, ")")
  packet <- packets[[key]]
  compiled <- compile_degree_interpretation(reading$proposal, degree_packet_course_facts(packet))
  board <- CEDAR_DEGREE_CATALOG$catalogs$catalog_id[grepl(reading$program_id, CEDAR_DEGREE_CATALOG$catalogs$source_url, fixed = TRUE)]
  comparison <- if (length(board) == 1L) compare_compiled_degree(compiled, CEDAR_DEGREE_ROADMAPS, board)
  cat(format_compiled_degree_preview(packet$title, compiled, comparison), "\n\n")
  if (write && length(board) != 1L) cat("Not written:", packet$title, "has no hand-built board (and so no catalog row) for a draft to take the place of.\n\n")
  if (is.null(opts[["--analysis"]]) || length(board) != 1L) next
  courses <- degree_packet_course_facts(packet)
  # The draft takes its hand-built board's catalog id: it replaces that board on the page.
  row <- CEDAR_DEGREE_CATALOG$catalogs[CEDAR_DEGREE_CATALOG$catalogs$catalog_id == board, ]
  row$notes <- "Compiled from the catalog reading; a draft until the reading is signed off in Catalog Review."
  draft <- assemble_compiled_degree_board(compiled, courses, degree_packet_program_facts(packet),
    degree_course_requisites(rule_nodes, courses), row, CEDAR_DEGREE_ROADMAPS, CEDAR_DEGREE_CATALOG$evidence, general_math,
    degree_course_conditions(rule_nodes, courses), reading$proposal)
  for (math in c("calculus", "intermediate")) {
    placed <- build_degree_roadmap(draft$catalog, draft$roadmaps, row$catalog_id, math, "composition")
    hand <- build_degree_roadmap(CEDAR_DEGREE_CATALOG, CEDAR_DEGREE_ROADMAPS, board, math, "composition")
    cat(format_degree_board_comparison(packet$title, math, placed, hand, draft$held), "\n\n")
  }
  if (write) {
    boards[[board]] <- draft
    manifest[[board]] <- data.frame(catalog_id = board, program_id = reading$program_id,
      reading = sub(paste0("^", normalizePath(cedar_institution_dir()), "/"), "", normalizePath(path)), packet_key = key,
      unit_key = reading$unit_key, proposal_key = degree_reading_proposal_key(root, load_catalog_normalization_program(root, key), reading),
      reading_sha256 = source_sha256(source_json_bytes(reading$proposal)), analysis = basename(normalizePath(opts[["--analysis"]])),
      compiled_on = format(Sys.Date()))
  }
}
if (write) {
  dir <- file.path(cedar_institution_dir(), "degree_drafts")
  write_degree_drafts(boards, do.call(rbind, manifest), dir, CEDAR_DEGREE_CATALOG$evidence)
  cat("Wrote", length(boards), "compiled boards to", dir, "\n")
}
