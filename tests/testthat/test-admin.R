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
