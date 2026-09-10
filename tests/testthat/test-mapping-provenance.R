context("Mapping provenance and the rebuild gate")

test_that("the fingerprint covers every file that decides dept_code", {
  files <- cedar_mapping_source_files()
  # Institution configuration plus the transform logic that consumes it. Missing
  # one means an edit to it would not trigger a rebuild, which is the failure
  # this whole mechanism exists to prevent.
  expect_true(all(c(
    "R/lists/subj_dept_map.R",
    "R/lists/program_code_maps.R",
    "R/lists/catalog_lookups.R",
    "R/data-parsers/transform-to-cedar.R"
  ) %in% files))

  prov <- cedar_mapping_provenance("../..")
  expect_setequal(names(prov$files), files)
  expect_true(nzchar(prov$combined))
  # Same source, same fingerprint -- otherwise every deploy would rebuild.
  expect_identical(cedar_mapping_provenance("../..")$combined, prov$combined)
})

test_that("drift is detected, and an unstamped table counts as drifted", {
  dir <- withr::local_tempdir()
  path <- file.path(dir, "cedar_programs.qs")

  # Absent: rebuild.
  expect_match(cedar_programs_mapping_drift(path, "../.."), "no cedar_programs")

  # Present but unstamped: rebuild. Failing towards a rebuild is deliberate --
  # rebuilding costs minutes, while serving departments built by unknown code is
  # how a stale map went unnoticed for nine months (ISSUES.md I7).
  qs2::qs_save(tibble::tibble(x = 1), path)
  expect_match(cedar_programs_mapping_drift(path, "../.."), "predates")

  # Stamped with the current source: no rebuild.
  stamped <- tibble::tibble(x = 1)
  attr(stamped, "cedar_mapping_provenance") <- cedar_mapping_provenance("../..")
  qs2::qs_save(stamped, path)
  expect_null(cedar_programs_mapping_drift(path, "../.."))

  # Stamped with different source: rebuild, and NAME the file that moved.
  moved <- cedar_mapping_provenance("../..")
  moved$files[["R/lists/program_code_maps.R"]] <- "different"
  moved$combined <- "different"
  attr(stamped, "cedar_mapping_provenance") <- moved
  qs2::qs_save(stamped, path)
  drift <- cedar_programs_mapping_drift(path, "../..")
  expect_match(drift, "mapping source changed")
  expect_match(drift, "program_code_maps", fixed = TRUE)
})
