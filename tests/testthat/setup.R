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
test_students_mc     <<- cedar_registrations_mc       # MC02: sequence + co-req + repeat, 2 campuses
test_programs_mc     <<- cedar_programs_mc       # MC02 covariates
test_students_mcret  <<- cedar_registrations_mcret    # MC03: retention cohorts, incl. a campus move
test_students_wlmkt  <<- cedar_registrations_wlmkt    # WL01: a waitlist in the pooled ABQ+EA market
test_sections_intersession <<- cedar_sections_intersession # IS01: a December intersession, out of the forecast
test_students_intersession <<- cedar_registrations_intersession # IS01
test_students_rw     <<- cedar_registrations_rw      # RW01: last term's students, registered for the next
test_programs_rw     <<- cedar_programs_rw      # RW01
test_students_st     <<- cedar_registrations_st      # ST01: the student-term table, one rule per student
test_programs_st     <<- cedar_programs_st      # ST01
test_degrees_st      <<- cedar_degrees_st       # ST01
test_students_rp     <<- cedar_registrations_rp       # RP01: next-term return, graduates and next-term drops
test_degrees_rp      <<- cedar_degrees_rp        # RP01
test_sections_topics <<- cedar_sections_topics  # rotating-topics history (test-low-enrollment.R)
test_sections_schedule <<- cedar_sections_schedule  # SC01 schedule-check history (test-low-enrollment.R)
test_students_pcc    <<- cedar_registrations_pcc      # PCC01: courses before a major switch, with a baseline
test_programs_pcc    <<- cedar_programs_pcc      # PCC01: three switchers, three stayers
test_population_pcc  <<- cedar_population_pcc    # PCC01: the six-student comparison universe
test_ids_spine       <<- cedar_ids_spine         # IDS01: canonical ID space
test_ids_clean       <<- cedar_ids_clean         # IDS01: joins everywhere
test_ids_split       <<- cedar_ids_split         # IDS01: two ID spaces, the real defect
test_ids_partial     <<- cedar_ids_partial       # IDS01: wider population, never zero
test_ids_orphan      <<- cedar_ids_orphan        # IDS01: no overlap in any term
test_students    <<- cedar_registrations
test_students_reused_crn <<- cedar_registrations_reused_crn # EC-08: repeat attempts and extract duplicates
test_students_audits <<- cedar_registrations_audits # EC-09: audit/status precedence
test_programs    <<- cedar_programs
test_programs_concurrent <<- cedar_programs_concurrent # EC-10: same-term program intersections
test_programs_hp <<- cedar_programs_hp            # HP01: named population groups -> Banner codes
test_programs_hp2 <<- cedar_programs_hp2          # HP02: a pre-nursing population through its courses
test_students_hp2 <<- cedar_registrations_hp2
test_sections_hp2 <<- cedar_sections_hp2
test_students_regstats <<- cedar_registrations_regstats # EC-11: prior-only anomaly baselines
test_sections_regstats <<- cedar_sections_regstats
test_sections_course_history <<- cedar_sections_course_history
test_students_course_history <<- cedar_registrations_course_history
test_sections_pending_session <<- cedar_sections_pending_session # EC-11c: a session not yet begun (I28)
test_students_pending_session <<- cedar_registrations_pending_session
test_students_roadblocks <<- cedar_registrations_roadblocks # EC-12: first eligible outcomes
test_programs_many_programs <<- cedar_programs_many_programs # EC-13: dept over the rollup threshold
test_degrees_roadblocks <<- cedar_degrees_roadblocks
test_sections_xl_switch <<- cedar_sections_xl_switch # EC-15: listing switch in a crosslist
test_students_xl_switch <<- cedar_registrations_xl_switch
test_sections_rn     <<- cedar_sections_rn       # RN01: codes that succeed one another (course dimension)
test_students_rn     <<- cedar_registrations_rn
test_students_rn02   <<- cedar_registrations_rn02     # RN02: waitlisted under two live codes
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
test_student_terms            <<- .fixture_student_terms(cedar_registrations, cedar_degrees)
test_student_terms_audits     <<- .fixture_student_terms(cedar_registrations_audits, settled = 202110L)
test_student_terms_roadblocks <<- .fixture_student_terms(cedar_registrations_roadblocks, cedar_degrees_roadblocks)
test_student_terms_mcret      <<- .fixture_student_terms(cedar_registrations_mcret)
test_student_terms_rp         <<- .fixture_student_terms(cedar_registrations_rp, cedar_degrees_rp)
test_student_terms_mc         <<- .fixture_student_terms(cedar_registrations_mc)
# RW01 carries programs rows (unit, standing); Spring 2021 is in registration,
# so Fall 2020 is the settled edge.
test_student_terms_rw         <<- suppressMessages(build_student_terms(
  cedar_registrations_rw, cedar_programs_rw, edges = list(last_enrolled_complete = 202080L)))
# The Gen Ed association rows carry programs rows (GE_S1..GE_S4 declare HIST),
# so the major mix reads a programs primary major beside class-list ones.
test_student_terms_gen_ed_assoc <<- suppressMessages(build_student_terms(
  gen_ed_assoc_students, gen_ed_assoc_programs, cedar_degrees,
  edges = list(last_enrolled_complete = as.integer(max(gen_ed_assoc_students$term)))))
# ST01 carries its own programs and a settled edge of its own (Fall 2020).
test_student_terms_st         <<- suppressMessages(build_student_terms(
  cedar_registrations_st, cedar_programs_st, cedar_degrees_st))
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
# As global.R attaches at start (ADR-001 step 4): course_id on every section
# and class-list fixture, from a dimension built over that table alone. Neither
# institution's code_history.csv names a code these fixtures use, so the id is
# the code itself whichever institution load_funcs() read; RN01 (test_sections_rn,
# test_students_rn) is the exception and is attached by its tests with the demo
# institution's file.
attach_test_course_ids <<- function(tbl, role = c("sections", "students")) {
  role <- match.arg(role)
  empty <- tbl[0, intersect(c("term", "subject_course", "course_title", "level"), names(tbl))]
  courses <- suppressMessages(if (role == "sections") build_cedar_courses(tbl, empty, test_dims)
                              else build_cedar_courses(empty, tbl, test_dims))
  name <- if (role == "sections") "cedar_sections" else "cedar_registrations"
  suppressMessages(attach_course_ids(stats::setNames(list(tbl), name), courses))[[name]]
}
for (.sec in c("test_sections", "test_sections_sf", "test_sections_topics", "test_sections_schedule",
               "test_sections_regstats", "test_sections_course_history", "test_sections_xl_switch",
               "test_sections_intersession", "test_sections_pending_session", "test_sections_hp2")) {
  assign(.sec, attach_test_course_ids(get(.sec), "sections"), envir = globalenv())
}
# Loaded as global.R loads them: without the student-description columns
# (thin_class_list(), ADR-001 step 5); a reader attaches them from the
# student-term table built above from the full fixtures.
for (.stu in c("test_students", "test_students_xl_switch", "test_students_regstats",
               "test_students_course_history", "test_students_pending_session", "test_students_hp2")) {
  assign(.stu, attach_test_course_ids(thin_class_list(get(.stu)), "students"), envir = globalenv())
}
rm(.stu)
rm(.sec)
# RN01 read with the demo institution's code_history.csv, as its tests read it:
# both tables attached from one dimension built over both, as global.R does.
rn01_course_tables <<- function(students = test_students_rn) {
  dims <- build_cedar_dims(read_institution_mappings(cedar_institution_dir(cedar_base_dir, "demo")))
  courses <- suppressMessages(build_cedar_courses(test_sections_rn, students, dims))
  suppressMessages(attach_course_ids(
    list(cedar_sections = test_sections_rn, cedar_registrations = students), courses
  ))
}
# RN02 rides on RN01: its class-list rows added to RN01's.
rn02_course_tables <<- function() {
  rn01_course_tables(dplyr::bind_rows(test_students_rn, test_students_rn02))
}
# Degree Explorer: the demo institution's designed catalog (institution/demo/),
# two synthetic programs whose schedules are worked by hand in
# test-degree-explorer.R. Independent of any real institution's annual catalog.
test_degree_catalog  <<- read_degree_catalog(cedar_institution_dir(cedar_base_dir, "demo"))
test_degree_roadmaps <<- read_degree_roadmaps(test_degree_catalog, cedar_institution_dir(cedar_base_dir, "demo"))
test_faculty     <<- cedar_faculty

data_objects <<- list(
  cedar_programs = test_programs,
  cedar_degrees  = test_degrees,
  cedar_registrations = test_students,
  cedar_student_terms = test_student_terms,
  cedar_faculty  = test_faculty,
  cedar_sections = test_sections,
  cedar_dims     = test_dims
)
# global.R stores the data edges on data_objects; modules read them from there.
data_objects$cedar_edges <<- cedar_data_edges(test_students, degrees = test_degrees)
# The attempt and course-term measure tables as the transform builds them, over
# any keyed class-list fixture: attempts to the graded edge, then the course
# terms counted from the same class list and schedule with those attempts'
# outcomes.
attempts_for <<- function(students, edges = data_objects$cedar_edges) build_attempts(students, edges)
course_terms_for <<- function(students, sections, edges = data_objects$cedar_edges) {
  build_course_terms(students, attempts_for(students, edges), sections)
}
# A class list as a test designs it (extract rows, duplicates and all), made
# into the attempt table the outcome hub reads (ADR-001 step 7) the way the
# data reaches a reader: one row per student, course, campus and term
# (dedup_class_list_rows(), the transform's), thin and keyed on the course
# (as global.R loads it), then build_attempts() to the edge.
.transform_helpers <- load_transform_helpers()
keyed_attempts <<- function(students, edges = data_objects$cedar_edges) {
  students <- .transform_helpers$dedup_class_list_rows(students)
  students <- thin_class_list(students[setdiff(names(students), c("course_id", "listed_code"))])
  if (nrow(students) == 0L) {
    # No rows, no courses to key: the empty class list with the key columns.
    students$course_id <- character()
    students$listed_code <- character()
    return(attempts_for(students, edges))
  }
  attempts_for(attach_test_course_ids(students, "students"), edges)
}
test_attempts         <<- attempts_for(test_students)
gen_ed_assoc_attempts <<- keyed_attempts(gen_ed_assoc_students)
# The course-term table over the main fixtures and over EC-11's, the two class
# list and schedule pairs the readers of cedar_course_terms are tested on.
test_course_terms          <<- course_terms_for(test_students, test_sections)
test_course_terms_regstats <<- course_terms_for(test_students_regstats, test_sections_regstats)
# The course-flow measure table (every next-term pair) over a keyed class
# list. The designed fixtures settle no term on their own (their edges carry
# no last_enrolled_complete), so the edge is given: the newest term, as the
# other follow-up tests give theirs.
flows_for <<- function(students, edge = max(students$term)) {
  build_course_flows(students, list(last_enrolled_complete = as.integer(edge)))
}
test_course_flows <<- flows_for(test_students)
data_objects$cedar_attempts     <<- test_attempts
data_objects$cedar_course_terms <<- test_course_terms
data_objects$cedar_course_flows <<- test_course_flows

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
