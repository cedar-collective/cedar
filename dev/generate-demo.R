#!/usr/bin/env Rscript
# Without an explicit output path, write only the isolated Docker demo volume.
# An explicit path exports a portable bundle; populated unmarked targets fail.
args <- commandArgs(trailingOnly = TRUE)
if (length(args) > 1L) stop("Usage: Rscript dev/generate-demo.R [output-directory]")
if (!length(args) &&
    (!identical(Sys.getenv("CEDAR_DEMO"), "true") || !file.exists("/.dockerenv"))) {
  stop("Supply a new output directory or use bash scripts/dev.sh up inside Docker.")
}
# The demo is its own institution (ADR-002 Stage 5): institution/demo/.
Sys.setenv(docker = "TRUE", CEDAR_STUDENT_SALT = "public-synthetic-demo-only",
           CEDAR_INSTITUTION = "demo")
suppressPackageStartupMessages(library(tidyverse))
source("dev/demo-data.R")
target <- if (length(args)) args[[1]] else "/srv/shiny-server/cedar/data"
# The transform stamps cedar_programs with its mapping provenance and audits the
# mapping files, both of which need CEDAR's functions loaded (ISSUES.md I13).
# logging.R reads cedar_data_dir at load time for its log paths.
cedar_base_dir <- getwd()
cedar_data_dir <- target
source("R/trunk/load-funcs.R")
load_funcs(cedar_base_dir, modules = FALSE)
SOURCED_FROM_PARSE_DATA <- TRUE
source("R/data-parsers/transform-to-cedar.R")
marker <- file.path(target, "synthetic-demo.txt")
dir.create(target, recursive = TRUE, showWarnings = FALSE)
# The guard protects a real institutional data directory from being overwritten
# with synthetic records. A demo volume first seeded by an image from before
# ADR-002 Stage 4 holds program_map.qs alone -- a retired, non-institutional
# artifact the image used to bake -- so it does not count as evidence.
existing <- setdiff(list.files(target, all.files = TRUE, no.. = TRUE), "program_map.qs")
if (length(existing) > 0L && !file.exists(marker)) {
  stop("Refusing to write into an unmarked, nonempty data directory.")
}
# The mapping files decide every unit and college, so they are part of the
# demo's source too.
sources <- c("dev/demo-data.R", "dev/generate-demo.R", "dev/shiny_config.R",
             "tests/testthat/fixtures/designed_test_data.R",
             list.files("R", pattern = "\\.R$", recursive = TRUE, full.names = TRUE),
             list.files(file.path("institution", cedar_institution_id()), full.names = TRUE))
signature <- digest::digest(tools::md5sum(sources), algo = "sha256")
outputs <- paste0("cedar_", c("sections", "students", "programs", "degrees", "faculty",
                             "lookups", "grades", "next_term", "student_term_credits", "applicants"), ".qs")
if (file.exists(marker) && identical(readLines(marker), signature) &&
    all(file.exists(file.path(target, outputs)))) {
  message("Synthetic demo already matches the source; reusing it.")
  quit(status = 0)
}
# Build away from the live files. Publish only after every table exists.
stage <- tempfile("demo-build-")
dir.create(stage)
raw <- build_demo_sources()
for (nm in names(raw)) qs2::qs_save(raw[[nm]], file.path(stage, paste0(nm, ".qs")))
transform_to_cedar(data_dir = stage, use_qs = TRUE)
stopifnot(all(file.exists(file.path(stage, outputs))))
summary <- write_demo_provenance(raw, stage)
writeLines("building", marker)
for (nm in c(outputs, paste0(names(raw), ".qs"), "cedar-status.json",
             "fixture-people.csv", "fixture-sections.csv", "synthetic-institution.json")) {
  stopifnot(file.copy(file.path(stage, nm), file.path(target, paste0(nm, ".tmp")), overwrite = TRUE))
  stopifnot(file.rename(file.path(target, paste0(nm, ".tmp")), file.path(target, nm)))
}
writeLines(signature, marker)
unlink(stage, recursive = TRUE)
message("Synthetic institution ready: ", summary$students, " people, ",
        summary$enrollments, " enrollment records, ", summary$cohorts, " cohorts.")
