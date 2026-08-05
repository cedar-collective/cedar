context("Transform status metadata")

load_transform_helpers <- function() {
  env <- new.env(parent = .GlobalEnv)
  env$SOURCED_FROM_PARSE_DATA <- TRUE
  old_wd <- getwd()
  setwd(cedar_base_dir)
  on.exit(setwd(old_wd), add = TRUE)
  sys.source(file.path(cedar_base_dir, "R/data-parsers/transform-to-cedar.R"),
             envir = env)
  env
}

test_that("cedar-status writer emits valid JSON with null metadata", {
  env <- load_transform_helpers()
  status_file <- tempfile(fileext = ".json")

  saved_files <- list(
    students = list(
      filename = "cedar_students.qs", rows = 10L, size_mb = 1.2,
      as_of_date = "2026-02-04", min_term = "201980", max_term = "202610"
    ),
    lookups = list(
      filename = "cedar_lookups.qs", rows = NA_integer_, size_mb = 0,
      as_of_date = NA_character_, min_term = NA_character_, max_term = NA_character_
    )
  )

  env$write_cedar_status_file(saved_files, status_file,
                              generated = "2026-07-27 10:31:41")

  json_text <- paste(readLines(status_file, warn = FALSE), collapse = "\n")
  expect_true(jsonlite::validate(json_text))
  expect_match(json_text, '"rows": null', fixed = TRUE)
  expect_match(json_text, '"as_of_date": null', fixed = TRUE)

  parsed <- jsonlite::fromJSON(status_file)
  expect_equal(parsed$generated, "2026-07-27 10:31:41")
  expect_equal(parsed$tables$students$rows, 10L)
})
