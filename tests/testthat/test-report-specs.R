# The report list parse-data.R reads (R/data-parsers/report-specs.R), and the
# two accommodations an export may need: column names below a title, and the
# export's own footer lines.

test_that("an export's column names are found below its title, and its footer lines dropped", {
  specs <- load_report_specs()
  csv <- withr::local_tempfile(lines = holds_export_lines, fileext = ".csv")

  header_line <- specs$find_report_header_line(csv, "ID")
  expect_equal(header_line, 3L)
  # Read as parse-data.R reads it: from the header, the ID as text.
  export <- data.table::fread(csv, colClasses = list(character = "ID"), skip = header_line - 1L)
  expect_equal(names(export), c("ID", "Student Full Name (LFMI)", "Hold Code", "Hold From Date"))
  # Read from the top, the same file has no column names at all.
  expect_false("ID" %in% names(data.table::fread(csv)))

  # The blank lines and the "ran on" line are not holds.
  holds <- specs$drop_report_noise_rows(export, "Hold Code")
  expect_equal(holds$`Hold Code`, c("AV", "BP"))
  expect_equal(holds$ID, c("012345678", "012345678"))
})

test_that("a missing header row or noise column stops the parse", {
  specs <- load_report_specs()
  csv <- withr::local_tempfile(lines = holds_export_lines, fileext = ".csv")

  expect_error(specs$find_report_header_line(csv, "Student ID"), "No header row found")
  export <- data.table::fread(csv, skip = 2L)
  expect_error(specs$drop_report_noise_rows(export, "Hold Type"), "is not a column of the report")
})

test_that("every report names the file, the term column and the stage it is built into", {
  specs <- load_report_specs()$report_specs
  transform <- load_transform_helpers()

  for (code in names(specs)) {
    spec <- specs[[code]]
    for (field in c("label", "data_file", "filename_sig", "term_col", "stage")) {
      expect_true(is.character(spec[[field]]) && length(spec[[field]]) == 1L && nzchar(spec[[field]]),
                  info = paste(code, field))
    }
    expect_true(isTRUE(spec$daily) || isFALSE(spec$daily), info = code)
    # A stage the transform does not have is ignored there, and builds nothing.
    expect_true(spec$stage %in% transform$CEDAR_TRANSFORM_STAGES, info = code)
    # A person's ID is hashed or dropped, never both and never left.
    expect_length(intersect(spec$ID_col, spec$drop_cols), 0L)
  }
  # No two reports share a file, a signature or a stage; no signature is part
  # of another, which would hand one report's download to both.
  for (field in c("data_file", "filename_sig", "stage")) {
    expect_false(anyDuplicated(vapply(specs, `[[`, character(1), field)) > 0L, info = field)
  }
  signatures <- vapply(specs, `[[`, character(1), "filename_sig")
  for (code in names(signatures)) {
    others <- signatures[names(signatures) != code]
    expect_false(any(grepl(signatures[[code]], others, fixed = TRUE)), info = code)
  }
})
