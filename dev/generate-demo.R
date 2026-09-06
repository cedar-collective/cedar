#!/usr/bin/env Rscript
# Without an explicit output path, write only the isolated Docker demo volume.
# An explicit path exports a portable bundle; populated unmarked targets fail.
args <- commandArgs(trailingOnly = TRUE)
if (length(args) > 1L) stop("Usage: Rscript dev/generate-demo.R [output-directory]")
if (!length(args) &&
    (!identical(Sys.getenv("CEDAR_DEMO"), "true") || !file.exists("/.dockerenv"))) {
  stop("Supply a new output directory or use bash scripts/dev.sh up inside Docker.")
}
Sys.setenv(docker = "TRUE", CEDAR_STUDENT_SALT = "public-synthetic-demo-only")
suppressPackageStartupMessages(library(tidyverse))
source("dev/demo-data.R")
SOURCED_FROM_PARSE_DATA <- TRUE
source("R/data-parsers/transform-to-cedar.R")
target <- if (length(args)) args[[1]] else "/srv/shiny-server/cedar/data"
marker <- file.path(target, "synthetic-demo.txt")
dir.create(target, recursive = TRUE, showWarnings = FALSE)
# The guard protects a real institutional data directory from being overwritten
# with synthetic records. `program_map.qs` cannot serve as that evidence: the
# image bakes it (see .dockerignore) so the in-image R suite can run without
# mounted data, and Docker seeds a *fresh* named volume from the image, so the
# demo volume always starts holding exactly that one file. Counting it made
# every clean run of the isolated demo stack — including the PR gate on a new
# runner — refuse to initialise. It is a committed, regenerable artifact that
# this script copies into the target anyway, never institutional data.
existing <- setdiff(list.files(target, all.files = TRUE, no.. = TRUE), "program_map.qs")
if (length(existing) > 0L && !file.exists(marker)) {
  stop("Refusing to write into an unmarked, nonempty data directory.")
}
program_map_path <- if (length(args)) "data/program_map.qs" else "/opt/cedar-program-map.qs"
sources <- c("dev/demo-data.R", "dev/generate-demo.R", "dev/shiny_config.R",
             "tests/testthat/fixtures/designed_test_data.R",
             list.files("R", pattern = "\\.R$", recursive = TRUE, full.names = TRUE),
             program_map_path)
signature <- digest::digest(tools::md5sum(sources), algo = "sha256")
outputs <- paste0("cedar_", c("sections", "students", "programs", "degrees", "faculty",
                             "lookups", "grades", "next_term", "student_term_credits", "applicants"), ".qs")
if (file.exists(marker) && identical(readLines(marker), signature) &&
    all(file.exists(file.path(target, c(outputs, "program_map.qs"))))) {
  message("Synthetic demo already matches the source; reusing it.")
  quit(status = 0)
}
# Build away from the live files. Publish only after every table exists.
stage <- tempfile("demo-build-")
dir.create(stage)
raw <- build_demo_sources()
for (nm in names(raw)) qs2::qs_save(raw[[nm]], file.path(stage, paste0(nm, ".qs")))
stopifnot(file.copy(program_map_path, file.path(stage, "program_map.qs")))
transform_to_cedar(data_dir = stage, use_qs = TRUE)
stopifnot(all(file.exists(file.path(stage, outputs))))
summary <- write_demo_provenance(raw, stage)
writeLines("building", marker)
for (nm in c(outputs, paste0(names(raw), ".qs"), "program_map.qs", "cedar-status.json",
             "fixture-people.csv", "fixture-sections.csv", "synthetic-institution.json")) {
  stopifnot(file.copy(file.path(stage, nm), file.path(target, paste0(nm, ".tmp")), overwrite = TRUE))
  stopifnot(file.rename(file.path(target, paste0(nm, ".tmp")), file.path(target, nm)))
}
writeLines(signature, marker)
unlink(stage, recursive = TRUE)
message("Synthetic institution ready: ", summary$students, " people, ",
        summary$enrollments, " enrollment records, ", summary$cohorts, " cohorts.")
