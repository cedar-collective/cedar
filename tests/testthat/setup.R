# Test setup - runs before all tests
#
# DESIGNED FIXTURES (test_sections, test_students, etc.)
#   Hand-crafted, transparent, inspectable. Source of truth is
#   fixtures/designed_test_data.R — edit that file to change test data.
#   XL/crosslist sections live in test_sections alongside regular sections,
#   exactly as they do in production. Tests filter from test_sections directly.

# Load necessary libraries
suppressPackageStartupMessages({
  library(dplyr)
})

# -----------------------------------------------------------------------------
# DESIGNED FIXTURES - hand-crafted, transparent, and inspectable
# -----------------------------------------------------------------------------
source("fixtures/designed_test_data.R")

test_sections        <<- cedar_sections
test_sections_sf     <<- cedar_sections_sf      # seatfinder-specific: 2024/2025 terms (test-seatfinder.R)
test_students_mc     <<- cedar_students_mc       # MC02: sequence + co-req + repeat, 2 campuses
test_programs_mc     <<- cedar_programs_mc       # MC02 covariates
test_students_mcret  <<- cedar_students_mcret    # MC03: retention cohorts, incl. a campus move
test_sections_topics <<- cedar_sections_topics  # rotating-topics history (test-low-enrollment.R)
test_students_pcc    <<- cedar_students_pcc      # PCC01: courses before a major switch, with a baseline
test_programs_pcc    <<- cedar_programs_pcc      # PCC01: three switchers, three stayers
test_population_pcc  <<- cedar_population_pcc    # PCC01: the six-student comparison universe
test_ids_spine       <<- cedar_ids_spine         # IDS01: canonical ID space
test_ids_clean       <<- cedar_ids_clean         # IDS01: joins everywhere
test_ids_split       <<- cedar_ids_split         # IDS01: two ID spaces, the real defect
test_ids_partial     <<- cedar_ids_partial       # IDS01: wider population, never zero
test_ids_orphan      <<- cedar_ids_orphan        # IDS01: no overlap in any term
test_students    <<- cedar_students
test_students_reused_crn <<- cedar_students_reused_crn # EC-08: repeat attempts and extract duplicates
test_students_audits <<- cedar_students_audits # EC-09: audit/status precedence
test_programs    <<- cedar_programs
test_programs_concurrent <<- cedar_programs_concurrent # EC-10: same-term program intersections
test_students_regstats <<- cedar_students_regstats # EC-11: prior-only anomaly baselines
test_sections_regstats <<- cedar_sections_regstats
test_students_roadblocks <<- cedar_students_roadblocks # EC-12: first eligible outcomes
test_degrees_roadblocks <<- cedar_degrees_roadblocks
test_degrees     <<- cedar_degrees
test_faculty     <<- cedar_faculty
test_dept_codes  <- sort(unique(test_programs$dept_code[!is.na(test_programs$dept_code)]))
test_lookups     <<- list(
  program_name_lookup = test_programs %>%
    filter(!is.na(program_name), program_name != "",
           !is.na(dept_code), dept_code != "") %>%
    distinct(program_name, dept_code),
  dept_name_lookup = tibble::tibble(
    dept_code = test_dept_codes,
    dept_name = paste(test_dept_codes, "Department")
  ),
  college_code_to_name = c(
    AS = "ARTS",
    SC = "STEM",
    SO = "SOSC",
    ED = "EDU",
    NR = "NURS",
    AD = "BUS"
  ),
  subject_lookup = tibble::tibble(
    subject_code = names(subj_to_dept),
    dept_code    = unname(subj_to_dept)
  )
)

data_objects <<- list(
  cedar_programs = test_programs,
  cedar_degrees  = test_degrees,
  cedar_students = test_students,
  cedar_faculty  = test_faculty,
  cedar_sections = test_sections,
  cedar_lookups  = test_lookups
)

Sys.setenv(shiny = "FALSE")

# Config globals — minimal values sufficient for test runs
cedar_regstats_thresholds <<- list(
  min_impacted      = 20,
  pct_sd            = 1,
  chronic_fill_rate = 0.90,
  min_wait          = 20,
  section_proximity = 0.3
)
cedar_data_dir <<- tempdir()
cedar_log_level <<- "INFO"

# Report config globals required by set_payload() and course-report.R
cedar_report_start_term <<- 202010L
cedar_report_end_term   <<- 202110L
cedar_report_palette    <<- NULL

message(sprintf("  test_sections: %d rows (%d XL) | test_students: %d rows | test_programs: %d rows",
                nrow(test_sections),
                sum(!is.na(test_sections$crosslist_group)),
                nrow(test_students), nrow(test_programs)))
message(sprintf("  test_faculty:  %d rows | test_degrees:  %d rows",
                nrow(test_faculty), nrow(test_degrees)))

# Helper function to create standard opt list
create_test_opt <- function(overrides = list()) {
  default_opt <- list(
    course_campus  = NULL,
    course_college = NULL,
    dept_code      = NULL,
    term           = NULL,
    pt             = NULL,
    im             = NULL,
    level          = NULL,
    status         = "A",
    uel            = TRUE,
    group_cols     = NULL,
    bypass_cache   = TRUE   # always recompute in tests; never read production cache
  )

  modifyList(default_opt, overrides)
}
