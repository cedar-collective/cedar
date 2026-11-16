#!/usr/bin/env Rscript
# Degree compiler, step 1: print each catalog interpretation as draft board
# rows beside its hand-built board. Read-only: no model or network calls, and
# nothing is written. See docs/developers/catalog-normalization.md.
#
# Rscript --vanilla scripts/compile-degree-interpretations.R --root REVIEW_ROOT [--institution ID]
#   REVIEW_ROOT  the prepared packets (scripts/normalize-degree-catalog.R prepare --output)
args <- commandArgs(trailingOnly = TRUE)
usage <- "Usage: Rscript --vanilla scripts/compile-degree-interpretations.R --root REVIEW_ROOT [--institution ID]"
if (!length(args) || args[1] %in% c("--help", "-h")) { cat(usage, "\n"); quit(status = 0) }
opts <- list()
while (length(args)) {
  if (!args[1] %in% c("--root", "--institution") || args[1] %in% names(opts) || length(args) < 2L) stop(usage, call. = FALSE)
  opts[[args[1]]] <- args[2]; args <- args[-c(1L, 2L)]
}
if (is.null(opts[["--root"]])) stop(usage, call. = FALSE)
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
readings <- list.files(file.path(cedar_institution_dir(), "catalog_interpretations"), "\\.json$", recursive = TRUE, full.names = TRUE)
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
}
