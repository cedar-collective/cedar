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


test_that("morning projection builds are gated and use a writable publisher mount", {
  script <- readLines("../../scripts/update-data.sh", warn = FALSE)
  first <- grep("# ── Automatic projection refresh", script, fixed = TRUE)
  last <- grep("# ── Step 4: Warm Dept Dashboard cache", script, fixed = TRUE)
  block <- paste(script[(first + 1L):(last - 1L)], collapse = "\n")
  root <- tempfile("projection refresh ")
  dir.create(file.path(root, "output", "projections"), recursive = TRUE)
  on.exit(unlink(root, recursive = TRUE), add = TRUE)
  request <- file.path(root, "output", "projections", "rebuild-request.yml")

  exercise <- function(success = TRUE, build_rc = 0L) {
    code <- paste(
      paste0("CEDAR_HOST_DIR=", shQuote(root)),
      "CEDAR_CONTAINER_DIR=/srv/shiny-server/cedar",
      "DOCKER_COMPOSE_FILE=/production/docker-compose.yml",
      "MODE=production",
      paste0("PIPELINE_SUCCESS=", if (success) "true" else "false"),
      "record_step() { printf '%s\\n' \"$@\"; }",
      "log_step() { :; }; log_error() { :; }",
      paste0("run_cmd() { printf 'RUN:%s\\n' \"$@\"; return ", build_rc, "; }"),
      block, sep = "\n"
    )
    system2("bash", c("-c", shQuote(code)), stdout = TRUE, stderr = TRUE)
  }

  # No flag is necessary: a successful refresh always checks freshness.
  expect_true(any(startsWith(exercise(), "RUN:")))
  expect_false(any(startsWith(exercise(success = FALSE), "RUN:")))
  # The publisher service owns the only writable output/. The app service with a
  # CLI --volume looks writable here but is not: Compose keeps the app's
  # read-only mount, and the build failed every morning (ISSUES.md I19).
  commands <- exercise()
  expect_true("RUN:cedar-projections" %in% commands)
  expect_false("RUN:cedar-shiny" %in% commands)
  expect_false(any(commands %in% c("RUN:--volume", "RUN:-v")))
  expect_true("RUN:scripts/build-enrollment-projections.R" %in% commands)
  expect_true("RUN:--refresh" %in% commands)
  expect_true("OK" %in% commands)
  expect_true("FAILED" %in% exercise(build_rc = 1L))
})


# ISSUES.md I33: mrgather exited 0 after a MyReports login timeout (Oct 20) and
# after crashing before the class list and applicants (Oct 23); parse found no
# file, and the transform republished tables from older raw exports.
test_that("a fetch that produces no file from today fails, so nothing is republished", {
  script <- readLines("../../scripts/update-data.sh", warn = FALSE)
  first <- grep("^report_file_glob\\(\\) \\{", script)
  last <- grep('^record_step "mrgather fetch"', script)
  expect_length(first, 1L)
  expect_length(last, 1L)
  block <- paste(script[first:last], collapse = "\n")
  downloads <- tempfile("mrgather downloads ")
  dir.create(downloads)
  on.exit(unlink(downloads, recursive = TRUE), add = TRUE)

  exercise <- function(files = character(0), fetch_rc = 0L) {
    file.create(file.path(downloads, files))
    on.exit(unlink(file.path(downloads, files)), add = TRUE)
    code <- paste(
      paste0("MRGATHER_DATA_DIR=", shQuote(downloads)),
      "TODAY=20261020", "MODE=local", "DRY_RUN=false", "SECONDS=0", "STEP_START=0",
      "MRGATHER_DIR=/nonexistent", "START_TERM=202480", "END_TERM=202510",
      "REPORTS=(cl desr)", "SKIP_FETCH=true",
      "record_step() { printf 'STEP:%s|%s\\n' \"$2\" \"$4\"; }",
      "log_step() { :; }; log_success() { :; }; log_warning() { :; }; log_error() { :; }",
      paste0("run_cmd() { return ", fetch_rc, "; }"),
      block, sep = "\n"
    )
    out <- system2("bash", c("-c", shQuote(code)), stdout = TRUE, stderr = TRUE)
    out[startsWith(out, "STEP:")]
  }

  # Nothing arrived: the fetch exits 0 and still fails, naming the reports.
  expect_equal(exercise(), "STEP:FAILED|no file from today for: cl desr; see mrgather output")
  # One of two arrived: the missing one is named.
  expect_equal(
    exercise("Class_List_Guided_Adhoc_20261020.xlsx"),
    "STEP:FAILED|no file from today for: desr; see mrgather output"
  )
  # An older file is not today's.
  expect_match(exercise("Class_List_Guided_Adhoc_20261008.xlsx"), "^STEP:FAILED")
  # Both present before the run: no fetch at all.
  both <- c("Class_List_Guided_Adhoc_20261020.xlsx", "Department_Enrollment_Status_20261020.xlsx")
  expect_equal(exercise(both), "STEP:SKIPPED|files already from today")
  # A failing mrgather is still reported by its exit code.
  expect_equal(exercise(fetch_rc = 3L), "STEP:FAILED|exit code 3")
})
