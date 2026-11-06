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
test_students_wlmkt  <<- cedar_students_wlmkt    # WL01: a waitlist in the pooled ABQ+EA market
test_sections_intersession <<- cedar_sections_intersession # IS01: a December intersession, out of the forecast
test_students_intersession <<- cedar_students_intersession # IS01
test_students_rw     <<- cedar_students_rw      # RW01: last term's students, registered for the next
test_programs_rw     <<- cedar_programs_rw      # RW01
test_students_st     <<- cedar_students_st      # ST01: the student-term table, one rule per student
test_programs_st     <<- cedar_programs_st      # ST01
test_degrees_st      <<- cedar_degrees_st       # ST01
test_students_rp     <<- cedar_students_rp       # RP01: next-term return, graduates and next-term drops
test_degrees_rp      <<- cedar_degrees_rp        # RP01
test_sections_topics <<- cedar_sections_topics  # rotating-topics history (test-low-enrollment.R)
test_sections_schedule <<- cedar_sections_schedule  # SC01 schedule-check history (test-low-enrollment.R)
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
test_programs_hp <<- cedar_programs_hp            # HP01: named population groups -> Banner codes
test_students_regstats <<- cedar_students_regstats # EC-11: prior-only anomaly baselines
test_sections_regstats <<- cedar_sections_regstats
test_sections_course_history <<- cedar_sections_course_history
test_students_course_history <<- cedar_students_course_history
test_sections_pending_session <<- cedar_sections_pending_session # EC-11c: a session not yet begun (I28)
test_students_pending_session <<- cedar_students_pending_session
test_students_roadblocks <<- cedar_students_roadblocks # EC-12: first eligible outcomes
test_programs_many_programs <<- cedar_programs_many_programs # EC-13: dept over the rollup threshold
test_degrees_roadblocks <<- cedar_degrees_roadblocks
test_sections_xl_switch <<- cedar_sections_xl_switch # EC-15: listing switch in a crosslist
test_students_xl_switch <<- cedar_students_xl_switch
test_degrees     <<- cedar_degrees

# Student-term tables (cedar_student_terms), built by the production builder
# from the class-list fixtures above, exactly as the transform builds them.
# Roadblocks and Course Dynamics retention read `enrolled` and
# `returned_next_regular_term` from here and nowhere else (ADR-001 step 2).
# The designed fixtures are pulled within days of their last term, so the
# settled edge they would compute is NULL; each table is built with the edge
# the tests observe through, and a return into a term with no class list is
# unobservable, never FALSE.
.fixture_student_terms <- function(students, degrees = NULL, settled = max(students$term)) {
  suppressMessages(build_student_terms(
    students, programs = NULL, degrees = degrees,
    edges = list(last_enrolled_complete = as.integer(settled))
  ))
}
test_student_terms            <<- .fixture_student_terms(cedar_students, cedar_degrees)
test_student_terms_audits     <<- .fixture_student_terms(cedar_students_audits, settled = 202110L)
test_student_terms_roadblocks <<- .fixture_student_terms(cedar_students_roadblocks, cedar_degrees_roadblocks)
test_student_terms_mcret      <<- .fixture_student_terms(cedar_students_mcret)
test_student_terms_rp         <<- .fixture_student_terms(cedar_students_rp, cedar_degrees_rp)
test_student_terms_mc         <<- .fixture_student_terms(cedar_students_mc)
# RW01 carries programs rows (unit, standing); Spring 2021 is in registration,
# so Fall 2020 is the settled edge.
test_student_terms_rw         <<- suppressMessages(build_student_terms(
  cedar_students_rw, cedar_programs_rw, edges = list(last_enrolled_complete = 202080L)))
# The Gen Ed association rows carry programs rows (GE_S1..GE_S4 declare HIST),
# so the major mix reads a programs primary major beside class-list ones.
test_student_terms_gen_ed_assoc <<- suppressMessages(build_student_terms(
  gen_ed_assoc_students, gen_ed_assoc_programs, cedar_degrees,
  edges = list(last_enrolled_complete = as.integer(max(gen_ed_assoc_students$term)))))
# ST01 carries its own programs and a settled edge of its own (Fall 2020).
test_student_terms_st         <<- suppressMessages(build_student_terms(
  cedar_students_st, cedar_programs_st, cedar_degrees_st))
# As global.R attaches at start (ADR-001 step 3): the built table stores its
# primary major's keys, and the unit and college (primary_dept_code,
# primary_college_code, primary_college_basis) are attached from the
# institution's mapping files, the ones load_funcs() read.
test_dims <<- build_cedar_dims()
attach_test_student_terms <<- function(st) {
  suppressMessages(attach_default_units(list(cedar_student_terms = st), test_dims))$cedar_student_terms
}
for (.st in c("test_student_terms", "test_student_terms_audits", "test_student_terms_roadblocks",
              "test_student_terms_mcret", "test_student_terms_rp", "test_student_terms_mc",
              "test_student_terms_rw", "test_student_terms_gen_ed_assoc", "test_student_terms_st")) {
  assign(.st, attach_test_student_terms(get(.st)), envir = globalenv())
}
# Degree Explorer: the demo institution's designed catalog (institution/demo/),
# two synthetic programs whose schedules are worked by hand in
# test-degree-explorer.R. Independent of any real institution's annual catalog.
test_degree_catalog  <<- read_degree_catalog(cedar_institution_dir(cedar_base_dir, "demo"))
test_degree_roadmaps <<- read_degree_roadmaps(test_degree_catalog, cedar_institution_dir(cedar_base_dir, "demo"))
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
  cedar_student_terms = test_student_terms,
  cedar_faculty  = test_faculty,
  cedar_sections = test_sections,
  cedar_lookups  = test_lookups,
  cedar_dims     = test_dims
)
# global.R stores the data edges on data_objects; modules read them from there.
data_objects$cedar_edges <<- cedar_data_edges(test_students, degrees = test_degrees)

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
cedar_report_latest_term <<- 202110L
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
