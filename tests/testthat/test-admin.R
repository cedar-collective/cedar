# Tests for the small Data & Usage administration modules.

context("Admin modules")

suppressPackageStartupMessages({
  library(shiny)
  library(bslib)
})

source(file.path(cedar_base_dir, "R", "modules", "ui-helpers.R"))
source(file.path(cedar_base_dir, "R", "modules", "admin.R"))

test_that("data freshness is complete static HTML with honest missing states", {
  summary <- list(
    display_terms = c(202080L, 202110L),
    sections_count = nrow(test_sections), students_count = nrow(test_students),
    programs_count = nrow(test_programs), degrees_count = nrow(test_degrees),
    faculty_count = 0L,
    sections_term_dates = list("202080" = "2026-09-04"),
    students_term_dates = list("202080" = "2026-09-03", "202110" = NA_character_),
    computed_at = as.POSIXct("2026-09-04 08:00:00", tz = "UTC")
  )
  data <- build_admin_data_status(summary, 202080L)
  expect_equal(nrow(data$table), 5L)
  expect_equal(data$current_column, 3L)
  expect_equal(data$table$Rows[[2]], as.character(nrow(test_students)))
  html <- as.character(dataStatusUI(summary, 202080L,
                                  list(version = "test", title = "Test version")))
  expect_match(html, '<table id="data_status_table"', fixed = TRUE)
  expect_match(html, "2026-09-04", fixed = TRUE)
  expect_match(html, "2026-09-03", fixed = TRUE)
  expect_match(html, "Fall 2020", fixed = TRUE)
  expect_match(html, "Not loaded", fixed = TRUE)
  expect_match(html, "Not available", fixed = TRUE)
  expect_match(html, "App snapshot loaded", fixed = TRUE)
  expect_false(grepl("reactable|shiny-html-output|html-widget-output", html))
  expect_false(grepl("202,080|202080\\.0", html))
})

test_that("freshness has no server output and app wiring parses", {
  server <- paste(readLines(file.path(cedar_base_dir, "server.R")), collapse = "\n")
  ui <- paste(readLines(file.path(cedar_base_dir, "ui.R")), collapse = "\n")
  expect_false(grepl("output$data_status_table", server, fixed = TRUE))
  expect_false(grepl('reactableOutput("data_status_table")', ui, fixed = TRUE))
  expect_match(ui, "dataStatusUI(cedar_data_summary, cedar_current_term)", fixed = TRUE)
  expect_match(server, "req(projection_tab_opened())", fixed = TRUE)
  expect_match(server, "req(integrity_tab_opened())", fixed = TRUE)
  expect_silent(parse(file.path(cedar_base_dir, "ui.R")))
  expect_silent(parse(file.path(cedar_base_dir, "server.R")))
})

test_that("Cache UI exposes the report timing reset control", {
  html <- as.character(cacheUI("cache"))

  expect_match(html, "Report Timing Estimates", fixed = TRUE)
  expect_match(html, "cache-refresh_timing_stats", fixed = TRUE)
  expect_match(html, "cache-reset_report_timings", fixed = TRUE)
  expect_match(html, "Reset Timing History", fixed = TRUE)
})

test_that("loading overlays request current timing estimates when opened", {
  html <- as.character(cedar_loading_overlay(
    "demo", "run",
    report_type = "demo-report",
    fresh_default = 8,
    cached_default = 2
  ))

  expect_match(html, "cedar_timing_estimate_request", fixed = TRUE)
  expect_match(html, "_timing_estimates", fixed = TRUE)
  expect_match(html, "demo-report", fixed = TRUE)
  expect_match(html, "cedar_client_render_timing", fixed = TRUE)
  expect_match(html, "payload_bytes", fixed = TRUE)
  expect_match(html, "fresh_range", fixed = TRUE)
  expect_match(html, "queue_delivery_sec", fixed = TRUE)
  expect_match(html, "browser_settle_sec", fixed = TRUE)
  expect_match(html, "operation_id", fixed = TRUE)
})

test_that("loading overlays can explain a multi-part preload", {
  html <- as.character(cedar_loading_overlay(
    "demo", "run",
    loading_label = "Preparing department trends…",
    loading_detail = "Loading the visible tabs now so they are ready later."
  ))

  expect_match(html, "Preparing department trends", fixed = TRUE)
  expect_match(html, "Loading the visible tabs now", fixed = TRUE)
  expect_match(html, 'role="dialog"', fixed = TRUE)
  expect_match(html, 'aria-modal="true"', fixed = TRUE)
})

test_that("loading overlays embed learned ranges before a report can block", {
  old_estimator <- report_time_estimates
  assign("report_time_estimates", function(...) list(
    fresh = 7L, cached = 2L,
    fresh_range = list(lower = 7L, upper = 29L),
    cached_range = list(lower = 2L, upper = 5L)
  ), envir = .GlobalEnv)
  on.exit(assign("report_time_estimates", old_estimator,
                 envir = .GlobalEnv), add = TRUE)

  html <- as.character(cedar_loading_overlay(
    "demo", "run", report_type = "demo-report",
    fresh_default = 8, cached_default = 2
  ))

  expect_match(html, 'var EXPECTED = 7, CACHED = 2', fixed = TRUE)
  expect_match(html, '{"lower":7,"upper":29}', fixed = TRUE)
})

# ── Admin > Mappings: programs.csv rows awaiting a decision ──────────────────
# Scaffolding: a mapping-file list with three program rows. FRAD carries
# students in the HP01 fixture; ZZZZ appears only in the file (a degree-only
# code) and must still be listed, with no students; NURS is confirmed and must
# not be.
review_files <- function() {
  list(
    programs = data.frame(
      program_code = c("NURS", "FRAD", "ZZZZ"), in_college = "",
      program_name = c("Nursing", "Radiologic Sciences", "Ghost"),
      unit_code = c("NURS", "RADS", ""), college_code = "", is_pre_major = c("FALSE", "TRUE", "FALSE"),
      leads_to = "", basis = c("decided", "inherited", "unresolved"),
      status = c("confirmed", "proposed", "proposed"), evidence = "", notes = ""),
    settings = data.frame(setting = c("mapping_files_url", "source_files_url"),
                          value = c("https://github.com/org/repo/blob/main/institution/x",
                                    "https://github.com/org/repo/blob/main"))
  )
}

# Scaffolding: what build_admin_mapping_issues() would say about three codes.
# FRAD is proposed in the file (merged into its row), NOFILE has no row at all
# (listed, unlinked), and NURS is already confirmed (not listed, but counted).
review_issues <- function() {
  tibble::tibble(
    issue_type = c("pre_major_self_mapped_department", "unmapped_program_code",
                   "identity_fallback_department"),
    severity = "warning", review_status = "needs_review",
    program_code = c(NA, "BA-NOFILE-AS", NA), major_code = c("FRAD", "NOFILE", "NURS"),
    college_code = NA, dept_code = NA, degree_level = NA, program_type = NA,
    details = c("pre-major maps to itself", "no department owner", "falls back to itself"))
}

test_that("the program queue merges proposed rows with today's issues, most students first", {
  res <- build_program_mapping_queue(review_files(), test_programs_hp, review_issues(),
                                     known_units = c("NURS", "RADS", "MEDL", "BIOL"))
  q <- res$queue
  expect_equal(q$program_code, c("FRAD", "NOFILE", "ZZZZ"))
  expect_equal(q$students, c(3L, 0L, 0L))
  # FRAD's department today is a phantom named after itself (fixture HP01).
  expect_equal(q$today, c("FRAD (phantom)", "none", "none"))
  expect_equal(q$problem, c("pre-major mapped to itself", "no department in program_map", NA))
  expect_equal(q$problem_detail[1], "pre-major maps to itself")
  bad <- review_issues(); bad$issue_type[1] <- "new_screen"
  expect_error(build_program_mapping_queue(review_files(), test_programs_hp, bad, "NURS"),
               "No Problem label for issue type\\(s\\): new_screen")
  expect_equal(q$basis, c("inherited", "no row in programs.csv", "unresolved"))
  expect_equal(q$program_name[2], "Banner program BA-NOFILE-AS")
  # Row 2 of the file (FRAD) is line 3: the header is line 1. No row, no link.
  expect_equal(q$line_url,
               c("https://github.com/org/repo/blob/main/institution/x/programs.csv?plain=1#L3",
                 NA, "https://github.com/org/repo/blob/main/institution/x/programs.csv?plain=1#L4"))
  expect_equal(res$n_decided_issues, 1L)
  expect_error(build_program_mapping_queue(review_files(), dplyr::select(test_programs_hp, -term),
                                           review_issues(), "NURS"),
               "cedar_programs lacks term")
})

test_that("the mapping work list separates decisions from problems no mapping fixes", {
  # Scaffolding: the program files above, and an audit with one row of each
  # kind of work -- a subject to decide, a college check to review, an expected
  # pre-major difference, and a Banner organisation ID in the major code.
  audit <- tibble::tibble(
    kind = c("subject", "college_disagreement", "college_disagreement", "program_code"),
    value = c("BIOL", "POLS-BA", "FBIO", "1084"),
    context = c("college STEM", "mapped ARTS, Banner Translated College SOSC",
                "mapped STEM, Banner Translated College UC",
                "a Banner organisation ID in the major code column, not a program"),
    rows = c(2L, 4L, 1L, 2L), first_term = NA_integer_, last_term = NA_integer_,
    status = c("unmapped", "review", "expected", "unmapped"),
    consequence = "", needs = c("A subjects.csv row: department and college",
                                "A decision: confirm, or set the program's college_code",
                                "Nothing: an expected difference",
                                "Nothing to map: a source data error to report"),
    file = c("subjects", "programs", "programs", "programs"), line = c(NA, 9L, 5L, NA))
  sd <- data.frame(source_name = "Catch-all", unit_code = "", kind = "bucket", notes = "")
  w <- build_mapping_worklist(c(review_files(), list(
    units = data.frame(unit_code = c("NURS", "RADS", "MEDL", "BIOL"),
                       unit_name = c("Nursing", "Radiologic Sciences", "Medical Lab", "Biology"),
                       college_code = "", kind = "department", notes = ""),
    colleges = data.frame(college_code = "AS", college_name = "Arts and Sciences", source_names = ""),
    subjects = data.frame(
    subject_code = character(), in_college = character(), in_level = character(),
    unit_code = character(), college_code = character(), status = character(),
    evidence = character(), notes = character()))), test_programs_hp, review_issues(), audit, sd)
  # FRAD is a pre-major in the file; ZZZZ has no program rows to say more.
  expect_setequal(paste(w$decisions$kind, w$decisions$code),
                  c("Program (pre-major) FRAD", "Program ZZZZ", "Course subject BIOL",
                    "College check POLS-BA"))
  frad <- w$decisions[w$decisions$code == "FRAD", ]
  expect_equal(frad$suggested_name, "Radiologic Sciences")
  expect_equal(frad$confidence, "Strong: the program it leads to")
  expect_equal(w$decisions$suggested[w$decisions$code == "POLS-BA"], "ARTS")
  expect_setequal(paste(w$other$kind, w$other$code),
                  c("Program code 1084", "Old program_map check NOFILE"))
  expect_equal(w$n_expected, 1L)
  # Named columns reach the browser as JSON objects and break the table.
  expect_false(any(vapply(w$decisions, function(x) !is.null(names(x)), logical(1))))
})


test_that("a suggestion's confidence follows the evidence the assistant recorded", {
  # Scaffolding: one suggestion per rule. Course-taking is Plausible only when
  # clear (5x or more, over 100 or more enrolments) and never in a catch-all
  # ("bucket") source department, whose students' courses say little.
  sd <- data.frame(source_name = c("Catch-all", "History Dept"), unit_code = c("", "HIST"),
                   kind = c("bucket", "department"), notes = "")
  ev <- c("source department \"History Dept\" on 100% of primary-major rows",
          "unit named \"History\"",
          "students take HIST courses at 7.7x the overall rate (1131 enrolments)",
          "students take HIST courses at 4.8x the overall rate (291 enrolments)",
          "students take HIST courses at 12.4x the overall rate (38 enrolments)",
          "source department \"Catch-all\" on 100% of rows; students take HIST courses at 30.0x the overall rate (500 enrolments)",
          "nothing")
  got <- .suggestion_confidence(
    basis = c("source_department", "name_match", "course_taking", "course_taking",
              "course_taking", "course_taking", "unresolved"),
    evidence = ev, suggested = c(rep("HIST", 6), ""), source_departments = sd)
  expect_equal(sub(":.*", "", got),
               c("Strong", "Strong", "Plausible", "Weak", "Weak", "Weak", "None"))
  expect_match(got[3], "7.7x")
})
