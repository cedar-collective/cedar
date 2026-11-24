# The report list parse-data.R reads (R/data-parsers/report-specs.R), the two
# accommodations an export may need (column names below a title, and the
# export's own footer lines), and the two steps that must take the whole
# export or stop: its conversion to CSV and the read of that CSV.

test_that("an export's column names are found below its title, and its footer lines dropped", {
  specs <- load_report_specs()
  csv <- withr::local_tempfile(lines = holds_export_lines, fileext = ".csv")

  header_line <- specs$find_report_header_line(csv, "ID")
  expect_equal(header_line, 3L)
  # Read as parse-data.R reads it: from the header, the ID as text.
  export <- specs$read_report_export(csv, id_cols = "ID", skip = header_line - 1L)
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

test_that("an export the reader cannot take as written stops the parse, and its row is not quoted", {
  specs <- load_report_specs()

  for (case in names(holds_export_unreadable)) {
    csv <- withr::local_tempfile(lines = holds_export_unreadable[[case]], fileext = ".csv")
    said <- tryCatch(specs$read_report_export(csv, id_cols = "ID", skip = 2L),
                     error = conditionMessage)
    # A table here is the rows the reader chose to return, stored as the report.
    expect_type(said, "character")
    expect_match(said, "was not read as written", info = case)
    # The line the reader stopped on is a person's row: none of it is repeated.
    expect_no_match(said, "Hopper|Franklin|012345679|012345680", info = case)
  }
})

test_that("a conversion that stops part-way stops the parse and leaves no unhashed file", {
  specs <- load_report_specs()
  csv <- withr::local_tempfile(fileext = ".csv")

  # The converter wrote the whole export and ended normally.
  specs$convert_report_export("holds.xlsx", csv, local_report_converter(holds_export_lines))
  expect_equal(readLines(csv), holds_export_lines)

  # It wrote the title, the header and one hold, then failed or was killed.
  # The lines it left read as a one-hold report with nothing wrong with it.
  for (status in c(1L, 137L)) {
    stopped <- local_report_converter(holds_export_lines[1:4], status = status)
    expect_error(specs$convert_report_export("holds.xlsx", csv, stopped),
                 paste("ended with status", status))
    expect_false(file.exists(csv))
  }

  # It ended normally and wrote nothing.
  expect_error(specs$convert_report_export("holds.xlsx", csv, local_report_converter(character(0))),
               "wrote an empty file")
  expect_false(file.exists(csv))
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
