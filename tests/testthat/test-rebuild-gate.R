context("The deploy's table gate")

# ISSUES.md I22 and I46: shiny-server starts the app's R process on the first
# request, which is the deploy's health check, and with app_idle_timeout 0 the
# process keeps the tables it loaded until the container restarts. So the gate
# (scripts/rebuild-programs-if-mappings-changed.R, which since ADR-001 step 3
# builds cedar_student_terms alone: units are attached at every start, so a
# mapping edit rebuilds nothing) runs after the container is replaced and
# before the health check: a table it rebuilds is on disk before the app reads
# it (a deploy whose gate ran after the health check never reached the gate
# when the app could not start without the rebuild, and took the site down:
# I46), and a rebuild still restarts the container so nothing started
# meanwhile serves the old table (I22). The deploy's own gate block runs here
# with docker stubbed.
test_that("the deploy's table gate runs before the first request and restarts on a rebuild", {
  # The script's lines as written; bash ignores their YAML indentation.
  deploy <- readLines("../../.github/workflows/deploy.yml", warn = FALSE)
  first <- grep("Checking whether the student-term table needs rebuilding", deploy, fixed = TRUE)
  last <- grep('rm -f "$MAPPING_LOG"', deploy, fixed = TRUE)
  expect_length(first, 1L)
  expect_length(last, 1L)
  # After the container is replaced, before anything can start the app.
  expect_lt(grep("docker compose up -d", deploy, fixed = TRUE), first)
  expect_gt(grep("wait_for_app || exit 1", deploy, fixed = TRUE)[1], last)
  expect_gt(grep("^\\s*clear_restarting$", deploy)[1], last)

  run_gate <- function(output, rc = 0L) {
    code <- paste(
      paste0("GATE_OUTPUT=", shQuote(output), "; GATE_RC=", rc),
      "docker() { if [ \"$2\" = exec ]; then printf '%s\\n' \"$GATE_OUTPUT\"; return $GATE_RC; fi; echo \"DOCKER:$*\"; }",
      "wait_for_app() { echo WAIT; }",
      "clear_restarting() { echo CLEAR; }",
      paste(deploy[first:last], collapse = "\n"),
      sep = "\n")
    system2("bash", c("-c", shQuote(code)), stdout = TRUE, stderr = TRUE)
  }
  rebuilt <- run_gate("[student-terms] Rebuilt: cedar_student_terms.")
  expect_true("DOCKER:compose restart cedar-shiny" %in% rebuilt)
  # The restart page stays up until the health check that follows the block.
  expect_false(any(grepl("WAIT|CLEAR", rebuilt)))
  unchanged <- run_gate("[student-terms] cedar_student_terms is current; no rebuild.")
  expect_false(any(grepl("restart", unchanged)))
  failed <- run_gate("Error: cedar_student_terms needs cedar_programs.qs, which has not been built.", rc = 1L)
  expect_false(any(grepl("DOCKER:compose restart", failed)))
  expect_true(any(grepl("WARNING: student-term check", failed, fixed = TRUE)))
})

# The gate's own decision, with the child process stubbed: current means no
# rebuild; stale, missing or forced means one build of cedar_student_terms and
# nothing else, checked again afterwards.
test_that("the gate builds cedar_student_terms only when it is stale or forced", {
  dir <- withr::local_tempdir()
  full_row <- tibble::as_tibble(stats::setNames(as.list(rep(1, length(STUDENT_TERMS_COLUMNS))),
                                                STUDENT_TERMS_COLUMNS))
  attr(full_row, "cedar_student_terms_build_version") <- STUDENT_TERMS_BUILD_VERSION
  t0 <- Sys.time() - 3600
  write_at <- function(name, when, data = tibble::tibble(x = 1)) {
    path <- file.path(dir, paste0(name, ".qs"))
    qs2::qs_save(data, path)
    Sys.setFileTime(path, when)
  }
  for (name in c("cedar_students", "cedar_programs", "cedar_degrees")) write_at(name, t0)

  env <- new.env(parent = globalenv())
  sys.source("../../scripts/rebuild-programs-if-mappings-changed.R", envir = env)
  transform <- load_transform_helpers()
  built <- character(0)
  # A build writes the table after its sources: the stub dates it a second
  # past the newest source, wherever the test has moved them.
  sources <- file.path(dir, paste0("cedar_", c("students", "programs", "degrees"), ".qs"))
  rebuild <- function(tables) {
    built <<- c(built, tables)
    write_at("cedar_student_terms", max(file.mtime(sources)) + 1, full_row)
  }
  gate <- function(force = FALSE, rebuild_with = rebuild) suppressMessages(
    env$build_student_terms_if_stale(dir, rebuild_with, force = force,
                                     staleness = transform$cedar_student_terms_staleness))

  # Absent: built once.
  expect_true(gate())
  expect_equal(built, "student_terms")
  # Current: nothing.
  expect_false(gate())
  expect_equal(built, "student_terms")
  # A source newer than the table: built again.
  write_at("cedar_programs", Sys.time() + 60)
  expect_true(gate())
  expect_equal(built, c("student_terms", "student_terms"))
  # Forced: built regardless.
  expect_true(gate(force = TRUE))
  expect_equal(built, rep("student_terms", 3L))
  # A rebuild that leaves the table stale is an error, not a success.
  stale <- function(tables) write_at("cedar_student_terms", t0 - 60, full_row)
  write_at("cedar_programs", Sys.time() + 120)
  expect_error(gate(rebuild_with = stale), "still stale")
})
