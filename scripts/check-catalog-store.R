#!/usr/bin/env Rscript
# Deploy-time check (ISSUES I101): every committed catalog reading has its
# source packet in the catalog store and the catalog pages that packet cites
# in the catalog archive. Neither is in Git: both live in the app's data
# directory (CEDAR_DATA_DIR), under catalog-normalizations/<institution>/ and
# catalog-scans/<institution>/. The deploy runs this in the new image before
# it recreates the app, so a reading cannot ship without its files; a failure
# names every reading short of them and leaves the running app as it was.
#
#   Rscript --vanilla scripts/check-catalog-store.R [--data DIR] [--institution ID]
#
# --data defaults to the repository's data/, which is the app's data directory
# inside the image. On a host, name the directory .env gives as CEDAR_DATA_DIR.
# Copy missing files from the machine that prepared them with
# scripts/sync-catalog-store.sh.

args <- commandArgs(trailingOnly = TRUE)
usage <- "Usage: Rscript --vanilla scripts/check-catalog-store.R [--data DIR] [--institution ID]"
if (length(args) && args[1] %in% c("--help", "-h")) { cat(usage, "\n"); quit(status = 0) }
opts <- list()
while (length(args)) {
  if (!args[1] %in% c("--data", "--institution") || args[1] %in% names(opts) || length(args) < 2L) stop(usage, call. = FALSE)
  opts[[args[1]]] <- args[2]; args <- args[-c(1L, 2L)]
}
script <- sub("^--file=", "", grep("^--file=", commandArgs(FALSE), value = TRUE)[1])
base <- normalizePath(file.path(dirname(script), ".."))
cedar_base_dir <- base
cedar_data_dir <- normalizePath(if (is.null(opts[["--data"]])) file.path(base, "data") else opts[["--data"]], mustWork = TRUE)
cedar_output_dir <- file.path(base, "output")
suppressPackageStartupMessages(library(dplyr))
if (!is.null(opts[["--institution"]])) Sys.setenv(CEDAR_INSTITUTION = opts[["--institution"]])
source(file.path(base, "R/trunk/load-funcs.R")); suppressMessages(load_funcs(base, modules = FALSE))

institution <- cedar_institution_id()
readings <- file.path(cedar_institution_dir(base), "catalog_interpretations")
store <- file.path(cedar_data_dir, "catalog-normalizations", institution)
archive <- file.path(cedar_data_dir, "catalog-scans", institution)
units <- catalog_normalization_draft_units(store, readings, archive)
cat(sprintf("[check-catalog-store] %s: %d committed catalog reading(s), each with its source packet and captured pages.\n",
  institution, length(units)))
