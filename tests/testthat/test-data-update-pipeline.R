context("Data update pipeline")


test_that("update-data.sh has valid bash syntax", {
  rc <- system2("bash", c("-n", "../../scripts/update-data.sh"))

  expect_equal(rc, 0)
})


test_that("update-data.sh skips transform when parse or fetch has failed", {
  script <- readLines("../../scripts/update-data.sh", warn = FALSE)
  step3_start <- grep("Step 3: Transform to CEDAR model", script, fixed = TRUE)[1]
  step4_start <- grep("Step 4: Warm Dept Dashboard cache", script, fixed = TRUE)[1]
  expect_false(is.na(step3_start))
  expect_false(is.na(step4_start))

  step3 <- script[step3_start:step4_start]
  gate_line <- grep('if [[ "$PIPELINE_SUCCESS" != true ]]; then', step3, fixed = TRUE)[1]
  transform_line <- grep('Rscript .*transform-to-cedar\\.R', step3)[1]
  step3_text <- paste(step3, collapse = "\n")

  expect_false(is.na(gate_line))
  expect_false(is.na(transform_line))
  expect_lt(gate_line, transform_line)
  expect_true(grepl('TRANSFORM_STATUS="SKIPPED"', step3_text, fixed = TRUE))
  expect_true(grepl("prior step failed; transform not run", step3_text, fixed = TRUE))
})


test_that("parse-data.R fails closed when a data file is not saved", {
  parser <- paste(readLines("../../R/data-parsers/parse-data.R", warn = FALSE), collapse = "\n")

  expect_true(grepl('stop\\("\\[parse-data.R\\] ERROR: File was not saved:', parser))
  expect_true(grepl('stop\\("\\[parse-data.R\\] ERROR during save:', parser))
  expect_true(grepl("Could not write parse-data summary log", parser, fixed = TRUE))
})
