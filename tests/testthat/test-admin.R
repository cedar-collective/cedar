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
    issue_type = c("pre_major_self_mapped_department", "declared_majors_far_exceed_graduates",
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
  expect_equal(q$problem, c("pre-major mapped to itself", "far more majors than graduates", NA))
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
  # kind of work -- a subject to decide (taught in a named college, one under
  # an old code colleges.csv translates, and an unnamed one), a college check to review, an expected pre-major difference,
  # a Banner organisation ID in the major code, a program code with no
  # programs.csv row (FNRS, which HP01 names "Nursing"), and a unit with no
  # home college.
  audit <- tibble::tibble(
    kind = c("subject", "college_disagreement", "college_disagreement", "program_code",
             "program_code", "unit_college"),
    value = c("BIOL", "NURS", "FBIO", "1084", "FNRS", "MEDL"),
    context = c("college AS, ED, STEM", "mapped AS, Banner Translated College SOSC",
                "mapped STEM, Banner Translated College UC",
                "a Banner organisation ID in the major code column, not a program",
                "program record", "units.csv"),
    rows = c(2L, 4L, 1L, 2L, 3L, NA), first_term = NA_integer_, last_term = NA_integer_,
    status = c("unmapped", "review", "expected", "unmapped", "unmapped", "unmapped"),
    consequence = "", needs = c("A subjects.csv row: department and college",
                                "A decision: confirm, or set the program's college_code",
                                "Nothing: an expected difference",
                                "Nothing to map: a source data error to report",
                                "A programs.csv row: run propose-mappings.R --write",
                                "A home college in units.csv"),
    file = c("subjects", "programs", "programs", "programs", "programs", "units"),
    line = c(NA, 2L, 5L, NA, NA, 4L))
  sd <- data.frame(source_name = "Catch-all", unit_code = "", kind = "bucket", notes = "")
  w <- build_mapping_worklist(c(review_files(), list(
    units = data.frame(unit_code = c("NURS", "RADS", "MEDL", "BIOL"),
                       unit_name = c("Nursing", "Radiologic Sciences", "Medical Lab", "Biology"),
                       college_code = "", kind = "department", notes = ""),
    colleges = data.frame(college_code = c("AS", "EH"), college_name = c("Arts and Sciences", "Education"),
                          source_names = c("", "ED")),
    subjects = data.frame(
    subject_code = character(), in_college = character(), in_level = character(),
    unit_code = character(), college_code = character(), status = character(),
    evidence = character(), notes = character()))), test_programs_hp, review_issues(), audit, sd)
  # FRAD is a pre-major in the file; ZZZZ has no program rows to say more.
  expect_setequal(paste(w$decisions$kind, w$decisions$code),
                  c("Program (pre-major) FRAD", "Program ZZZZ", "Course subject BIOL",
                    "College check NURS", "Program code FNRS", "Unit college MEDL"))
  row <- function(code) w$decisions[w$decisions$code == code, ]
  frad <- row("FRAD")
  expect_equal(frad$suggested_name, "Radiologic Sciences")
  expect_equal(frad$confidence, "Strong: the program it leads to")
  expect_equal(row("NURS")$suggested, "AS")
  expect_equal(row("NURS")$suggested_name, "Arts and Sciences")
  # One tab per kind of decision.
  expect_equal(vapply(c("FRAD", "ZZZZ", "NURS", "FNRS", "BIOL", "MEDL"),
                      function(code) row(code)$group, character(1), USE.NAMES = FALSE),
               c("programs", "programs", "programs", "programs", "subjects", "colleges"))
  # Name is the code's own name or nothing -- never the audit's working context.
  expect_equal(frad$name, "Radiologic Sciences")          # programs.csv
  expect_equal(row("NURS")$name, "Nursing")               # a college check names its program
  expect_equal(row("FNRS")$name, "Nursing")               # no row: the name its records carry
  expect_equal(row("MEDL")$name, "Medical Lab")           # units.csv
  expect_true(is.na(row("BIOL")$name))                    # a subject has none
  expect_equal(row("BIOL")$taught_in, "AS (Arts and Sciences), ED (Education), STEM")
  expect_equal(row("BIOL")$reported_today, "none; college AS, ED, STEM from Banner")
  expect_equal(row("NURS")$reported_today, "college AS; Banner: SOSC")
  expect_equal(row("FNRS")$detail, "program record")
  expect_equal(row("MEDL")$detail, "units.csv")
  expect_true(is.na(row("NURS")$detail))
  expect_equal(paste(w$other$kind, w$other$code), "Program code 1084")
  expect_equal(w$n_expected, 1L)
  # Named columns reach the browser as JSON objects and break the table.
  expect_false(any(vapply(w$decisions, function(x) !is.null(names(x)), logical(1))))
})

# The reference tables under the decisions: every confirmed row, each code with
# its name. Scaffolding: the program rows above (NURS confirmed, FRAD and ZZZZ
# proposed) plus a no_unit program and a branch-only row, and subjects with an
# every-college row and a college- and level-specific one.
test_that("the mapping reference tables carry every confirmed row, with names", {
  files <- review_files()
  files$programs <- rbind(files$programs, data.frame(
    program_code = c("NOND", "BADM"), in_college = c("", "AD"),
    program_name = c("Non-Degree", "Business Administration"),
    unit_code = c("", "BUSA"), college_code = "", is_pre_major = "FALSE", leads_to = "",
    basis = c("no_unit", "decided"), status = "confirmed", evidence = "", notes = ""))
  files$units <- data.frame(unit_code = c("NURS", "BUSA", "HLED", "HED"),
                            unit_name = c("Nursing", "Business (Branch)", "Health Ed (Branch)", "Health Education"),
                            college_code = c("NU", "AD", "AD", "EH"), kind = "department", notes = "")
  files$colleges <- data.frame(college_code = c("AD", "EH"),
                               college_name = c("Associate Degree", "Education"), source_names = "")
  files$subjects <- data.frame(
    subject_code = c("HLED", "HLED", "XXXX"), in_college = c("", "AD", ""), in_level = c("", "lower", ""),
    unit_code = c("HED", "HLED", ""), college_code = "", status = c("confirmed", "confirmed", "proposed"),
    evidence = "", notes = "")
  ref <- build_mapping_reference_tables(files)

  expect_equal(ref$programs$program_code, c("BADM", "NOND", "NURS"))   # confirmed only
  expect_equal(ref$programs$program_name, c("Business Administration", "Non-Degree", "Nursing"))
  expect_equal(ref$programs$in_college, c("AD (Associate Degree)", NA, NA))
  expect_equal(ref$programs$dept_name, c("Business (Branch)", "None: no department owns it", "Nursing"))
  expect_true(is.na(ref$programs$dept_code[2]))
  # Both HLED rows, every-college first: the first row alone would hide the branch's.
  expect_equal(ref$subjects$subject_code, c("HLED", "HLED"))
  expect_equal(ref$subjects$in_college, c(NA, "AD (Associate Degree)"))
  expect_equal(ref$subjects$in_level, c(NA, "lower"))
  expect_equal(ref$subjects$dept_name, c("Health Education", "Health Ed (Branch)"))
  expect_equal(ref$units$college[ref$units$dept_code == "HED"], "EH (Education)")
  expect_equal(ref$units$college[ref$units$dept_code == "NURS"], "NU")   # a college no file names
  for (tbl in ref) expect_false(any(vapply(tbl, function(x) !is.null(names(x)), logical(1))))
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
