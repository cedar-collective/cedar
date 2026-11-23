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
  gate_line <- grep('if [[ "$REFRESH_CAN_CONTINUE" != true ]]; then', step3, fixed = TRUE)[1]
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
  # A report named with -r and no file stops the parse (ISSUES.md I33).
  expect_true(grepl('"ERROR: No .xlsx file for requested report(s): "', parser, fixed = TRUE))
  expect_true(grepl("require_files = reports_named", parser, fixed = TRUE))
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
      paste0("REFRESH_CAN_CONTINUE=", if (success) "true" else "false"),
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
  # Nothing arrived: the fetch exits 0 and still fails, naming the reports.
  none <- run_fetch_step()
  expect_equal(none$step, "FAILED|no file from today for: cl desr; see mrgather output")
  expect_equal(none$parse, "")
  # An older file is not today's.
  expect_match(run_fetch_step("Class_List_Guided_Adhoc_20261008.xlsx")$step, "^FAILED")
  # Both present before the run: no fetch at all, and both are refreshed.
  both <- c("Class_List_Guided_Adhoc_20261020.xlsx", "Department_Enrollment_Status_20261020.xlsx")
  skipped <- run_fetch_step(both)
  expect_equal(skipped$step, "SKIPPED|files already from today")
  expect_equal(skipped$parse, "cl,desr")
  expect_true(is.na(skipped$args))
  # A failing mrgather is reported by its exit code, beside what is missing.
  expect_equal(run_fetch_step(fetch = "exit 3")$step,
               "FAILED|exit code 3; no file from today for: cl desr; see mrgather output")
  # A fetch that brings every report is a success naming them.
  fetched <- run_fetch_step(fetch = paste0("touch ", paste(both, collapse = " ")))
  expect_equal(fetched$step, "OK|files from today: cl desr")
  expect_equal(fetched$tables, "--tables students,sections")
})

# ISSUES.md I33, I43: one missing report failed the whole fetch step, so a run
# that downloaded everything but one report published nothing: three mornings
# running in October, and every morning from Oct 28 to Nov 3.
test_that("a report that arrived is still refreshed when another did not", {
  # The class list was already there; the fetch brings nothing more.
  partial <- run_fetch_step("Class_List_Guided_Adhoc_20261020.xlsx")
  expect_equal(partial$step, "PARTIAL|no file from today for: desr; continuing with: cl")
  expect_equal(partial$parse, "cl")
  expect_equal(partial$tables, "--tables students")
  # The fetch itself brings one of the two, then crashes.
  crashed <- run_fetch_step(
    fetch = "touch Department_Enrollment_Status_20261020.xlsx; exit 1")
  expect_equal(crashed$step,
               "PARTIAL|exit code 1; no file from today for: cl; continuing with: desr")
  expect_equal(crashed$tables, "--tables sections")

  # PARTIAL is an error for the run and lets the later steps go on; FAILED
  # stops them. The summary never shows a step that did not run as a success.
  script <- readLines("../../scripts/update-data.sh", warn = FALSE)
  record <- script[grep("^record_step\\(\\) \\{", script):grep("^# ── Colors", script) - 1L]
  rows <- script[grep('^for i in "\\$\\{!STEP_NAMES\\[@\\]\\}"; do', script):length(script)]
  rows <- rows[seq_len(grep("^done$", rows)[1])]
  summarize <- function(status) {
    code <- paste(
      "declare -a STEP_NAMES=() STEP_STATUSES=() STEP_DURATIONS=() STEP_NOTES=()",
      "PIPELINE_SUCCESS=true; REFRESH_CAN_CONTINUE=true",
      paste(record, collapse = "\n"),
      paste0("record_step step ", status, " 0s note"),
      "echo \"FLAGS:$PIPELINE_SUCCESS/$REFRESH_CAN_CONTINUE\"",
      paste(rows, collapse = "\n"), sep = "\n")
    system2("bash", c("-c", shQuote(code)), stdout = TRUE, stderr = TRUE)
  }
  expect_equal(summarize("PARTIAL")[1], "FLAGS:false/true")
  expect_equal(summarize("FAILED")[1], "FLAGS:false/false")
  expect_equal(summarize("SKIPPED")[1], "FLAGS:true/true")
  expect_true(grepl("✅", summarize("OK")[2], fixed = TRUE))
  for (status in c("SKIPPED", "PARTIAL", "FAILED")) {
    expect_false(grepl("✅", summarize(status)[2], fixed = TRUE), info = status)
  }
})

# ISSUES.md I32: mrgather waits for ever at a 2FA prompt nobody can answer (the
# 2026-10-11 cron run sat there 12 days), and the fetch had no time limit.
test_that("a fetch nobody can answer, or one that overruns, is stopped and its container removed", {
  asked <- run_fetch_step(
    fetch = "echo 'Please enter the 2FA code (or press Enter to stop): '; exec sleep 60")
  expect_equal(asked$step, paste0(
    "FAILED|2FA required and nobody at a terminal to enter the code; ",
    "no file from today for: cl desr; see mrgather output"))
  # The container removed is the one the fetch was started as.
  expect_match(asked$removed, "^cedar-mrgather-fetch-[0-9]+$")
  expect_true(grepl(paste("--name", asked$removed), asked$args, fixed = TRUE))
  # With nobody at a terminal, mrgather is told so, and it then stops at a 2FA
  # prompt before a text message is asked for. The flag is the last word: a
  # mrgather that does not know it reads a following word as the flag's value,
  # and a report code after it would be lost.
  expect_match(asked$args, "node mrgather\\.js cl desr -s 202480 -e 202510 --unattended$")

  hung <- run_fetch_step(fetch = "exec sleep 60", time_limit = 2L)
  expect_match(hung$step, "^FAILED\\|stopped after the 2s time limit; no file from today for: cl desr")
  expect_match(hung$removed, "^cedar-mrgather-fetch-[0-9]+$")

  # Production and local runs share that one guarded command: there is no
  # second mrgather invocation that could lose the limit.
  script <- readLines("../../scripts/update-data.sh", warn = FALSE)
  expect_length(grep("node mrgather\\.js", script[!grepl("^\\s*#", script)]), 1L)
})


# ISSUES.md I43: the cron names no reports, and the default asked for the
# applicants report, which production mrgather never fetches. Under the check
# above, every scheduled refresh failed from 2026-10-24 and kept the old tables.
# The default is now the registry's daily reports: a report production mrgather
# cannot fetch stays out of it until its row says daily.
test_that("the scheduled refresh's default reports leave out the ones only fetched when named", {
  script <- readLines("../../scripts/update-data.sh", warn = FALSE)
  default <- grep("^\\[\\[ \\$\\{#REPORTS\\[@\\]\\} -eq 0 \\]\\]", script, value = TRUE)
  expect_length(default, 1L)
  expect_match(default, "REPORTS=($(report_daily_codes));", fixed = TRUE)

  registry <- read_report_registry()
  expect_equal(registry$code[registry$daily], c("desr", "deg", "as", "cl"))
  expect_equal(registry$code[!registry$daily], c("aa", "holds"))
})

# The reports are listed twice, once for R and once for the shell. They
# drifted when the shell's copy was typed by hand (ISSUES.md I2: three of five
# skip checks could never fire), so the two lists are held to each other.
test_that("the shell scripts' report registry and the parser's report specs agree", {
  specs <- load_report_specs()$report_specs
  registry <- read_report_registry()

  # The registry's order is the order the default reports are fetched in.
  expect_setequal(registry$code, names(specs))
  registry <- registry[match(names(specs), registry$code), ]
  expect_equal(registry$filename_sig, unname(vapply(specs, `[[`, character(1), "filename_sig")))
  expect_equal(registry$stage, unname(vapply(specs, `[[`, character(1), "stage")))
  expect_equal(registry$daily, unname(vapply(specs, `[[`, logical(1), "daily")))

  # Both scripts take any report in the registry, and no other word.
  for (script in c("update-data.sh", "restart-cedar.sh")) {
    path <- normalizePath(file.path("../../scripts", script))
    expect_equal(system2("bash", c("-n", shQuote(path))), 0, info = script)
    unknown <- suppressWarnings(
      system2("bash", c(shQuote(path), "-s", "202680", "bogus"), stdout = TRUE, stderr = TRUE))
    expect_true(any(grepl("Unknown option or report: bogus (reports: desr deg as cl aa holds)",
                          unknown, fixed = TRUE)), info = script)
  }
})

# The transform was told its stages only when fewer than five reports arrived,
# five being every report there was. With a sixth, five arriving named no
# stage, and the transform rebuilt every table, the missing report's from its
# old export.
test_that("the transform is told its stages however many reports arrived", {
  todays <- c(desr = "Department_Enrollment_Status_20261020.xlsx",
              deg = "Graduates_and_Pending_Graduates_20261020.xlsx",
              as = "Academic_Study_Detail_Guided_20261020.xlsx",
              cl = "Class_List_Guided_Adhoc_20261020.xlsx",
              aa = "S_Admissions_Applicants_Detail_20261020.xlsx",
              holds = "S_Student_Holds_20261020_104513.xlsx")

  one <- run_fetch_step(todays[["holds"]], reports = "holds")
  expect_equal(one$step, "SKIPPED|files already from today")
  expect_equal(one$parse, "holds")
  expect_equal(one$tables, "--tables holds")

  five <- run_fetch_step(unname(todays[names(todays) != "aa"]), reports = names(todays))
  expect_match(five$step, "^PARTIAL\\|no file from today for: aa; continuing with: desr deg as cl holds$")
  expect_equal(five$tables, "--tables sections,degrees,programs,students,holds")

  all_six <- run_fetch_step(unname(todays), reports = names(todays))
  expect_equal(all_six$tables, "--tables sections,degrees,programs,students,applicants,holds")
})
