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
  commands <- exercise()
  expect_true("RUN:cedar-shiny" %in% commands)
  expect_true("RUN:--entrypoint" %in% commands)
  expect_true("RUN:Rscript" %in% commands)
  expect_true(paste0("RUN:", root, "/output:/srv/shiny-server/cedar/output:rw") %in% commands)
  expect_true("RUN:--refresh" %in% commands)
  expect_true("OK" %in% commands)
  expect_true("FAILED" %in% exercise(build_rc = 1L))
})
