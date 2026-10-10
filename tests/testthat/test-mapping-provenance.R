context("Mapping provenance and the rebuild gate")

test_that("the fingerprint covers every file that decides dept_code", {
  files <- cedar_mapping_source_files()
  # Institution configuration plus the transform logic that consumes it. Missing
  # one means an edit to it would not trigger a rebuild, which is the failure
  # this whole mechanism exists to prevent.
  expect_true(all(c(
    "R/lists/subj_dept_map.R",
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
  moved$files[["R/lists/mappings.R"]] <- "different"
  moved$combined <- "different"
  attr(stamped, "cedar_mapping_provenance") <- moved
  qs2::qs_save(stamped, path)
  drift <- cedar_programs_mapping_drift(path, "../..")
  expect_match(drift, "mapping source changed")
  expect_match(drift, "R/lists/mappings.R", fixed = TRUE)
})

# ISSUES.md M26: since ADR-002 Stage 3 subjects.csv decides every course's unit,
# so the gate checks every mapped table, not only cedar_programs. A subject
# decision used to wait for the next refresh to reach the course tables.
test_that("every mapped table is checked, and each stale one is named with its reason", {
  dir <- withr::local_tempdir()
  stamp <- function(df, prov) { attr(df, "cedar_mapping_provenance") <- prov; df }
  current <- cedar_mapping_provenance("../..")
  subjects_moved <- current
  subj <- file.path("institution", cedar_institution_id(), "subjects.csv")
  subjects_moved$files[[subj]] <- "different"
  subjects_moved$combined <- "different"

  qs2::qs_save(stamp(tibble::tibble(x = 1), current), file.path(dir, "cedar_programs.qs"))
  qs2::qs_save(tibble::tibble(x = 1), file.path(dir, "cedar_sections.qs"))
  qs2::qs_save(stamp(tibble::tibble(x = 1), subjects_moved), file.path(dir, "cedar_students.qs"))
  # cedar_degrees absent.

  stale <- cedar_stale_mapped_tables(dir, "../..")
  expect_setequal(names(stale), c("degrees", "sections", "students"))
  expect_match(stale[["degrees"]], "no cedar_degrees")
  expect_match(stale[["sections"]], "cedar_sections predates")
  expect_match(stale[["students"]], subj, fixed = TRUE)

  # The files that decide units are all in the fingerprint.
  expect_true(all(file.path("institution", cedar_institution_id(),
                            c("programs.csv", "subjects.csv", "units.csv", "colleges.csv"))
                  %in% cedar_mapping_source_files()))
})
