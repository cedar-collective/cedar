# Create test fixtures from real CEDAR data
# Run this after transform-to-cedar.R regenerates data/cedar_*.qs
#
# Design principles:
#   1. Foundation is real CEDAR data — wide stratified sample across all
#      filtering dimensions (campus, delivery, part_term, crosslist, DFW)
#   2. Uses stable completed terms so fixtures never change once generated
#   3. Edge cases that don't appear in real data are added inline below —
#      they are plain rows, no different from sampled rows once in the .qs file
#   4. No fallback logic — if columns are missing, fix transform-to-cedar.R
#
# Workflow:
#   1. Download MyReports data
#   2. Rscript R/data-parsers/parse-data.R
#   3. Rscript R/data-parsers/transform-to-cedar.R
#   4. Rscript tests/testthat/create-test-fixtures.R  ← this script
#   5. Run tests: devtools::test()

library(tidyverse)
library(qs)

message("Creating test fixtures from CEDAR data files...")

# =============================================================================
# Configuration
# =============================================================================

# Stable completed terms — old enough that data will never change.
# 202010 = Spring 2020 (spring term_type)
# 202060 = Summer 2020 (summer term_type — for term_type filtering tests)
# 202080 = Fall 2020   (fall term_type)
# 202110 = Spring 2021 (second spring — for trend/comparison tests)
TEST_TERMS  <- c(202010, 202060, 202080, 202110)

# Main analysis departments (sections, students, faculty).
# NURS is included so health-domain code paths have real data.
TEST_DEPTS <- c("HIST", "MATH", "ANTH", "NURS")

# Faculty data only covers CAS departments — nursing and other colleges
# are not in the HR extract.
FACULTY_DEPTS <- c("HIST", "MATH", "ANTH")

# Degree terms: one prior term for seatfinder/completion comparisons.
DEGREE_TERMS <- c(201980, 202010, 202060, 202080, 202110)

# =============================================================================
# Helpers
# =============================================================================

require_cols <- function(df, name, cols) {
  missing <- setdiff(cols, names(df))
  if (length(missing) > 0) {
    stop(
      "\n\u274c ", name, " missing required columns: ", paste(missing, collapse = ", "),
      "\n   Fix transform-to-cedar.R \u2014 do NOT add workarounds here.\n"
    )
  }
  message("  \u2713 ", name, " has all required columns")
}

bind_unique <- function(..., id_col) {
  bind_rows(...) %>% distinct(across(all_of(id_col)), .keep_all = TRUE)
}

# =============================================================================
# Load full CEDAR data
# =============================================================================

message("Loading CEDAR data files...")
sections <- qread("data/cedar_sections.qs")
students  <- qread("data/cedar_students.qs")
programs  <- qread("data/cedar_programs.qs")
degrees   <- qread("data/cedar_degrees.qs")
faculty   <- qread("data/cedar_faculty.qs")

message(sprintf("  sections:  %s rows", format(nrow(sections),  big.mark = ",")))
message(sprintf("  students:  %s rows", format(nrow(students),  big.mark = ",")))
message(sprintf("  programs:  %s rows", format(nrow(programs),  big.mark = ",")))
message(sprintf("  degrees:   %s rows", format(nrow(degrees),   big.mark = ",")))
message(sprintf("  faculty:   %s rows", format(nrow(faculty),   big.mark = ",")))

# =============================================================================
# Validate required columns
# =============================================================================

message("\nValidating required columns...")

require_cols(sections, "cedar_sections", c(
  "section_id", "term", "department", "subject_course", "instructor_id",
  "crosslist_code", "crosslist_group", "crosslist_primary", "is_split",
  "total_enrl", "level", "status", "delivery_method", "part_term",
  "campus", "term_type", "is_combined", "comments", "census1"
))

require_cols(students, "cedar_students", c(
  "student_id", "term", "section_id", "subject_course", "department",
  "registration_status_code", "final_grade", "credits"
))

require_cols(programs, "cedar_programs", c(
  "student_id", "term", "program_type", "program_name", "major_code",
  "student_college", "student_campus", "dept_code", "is_pre_major",
  "residency", "academic_standing", "inst_gpa"
))

require_cols(degrees, "cedar_degrees", c(
  "term", "student_id", "degree", "major_code", "department"
))

require_cols(faculty, "cedar_faculty", c(
  "term", "instructor_id", "department", "job_category", "appointment_pct"
))

message("\u2713 All required columns present\n")

# =============================================================================
# SECTIONS
#
# Built from several explicit strata so tests have real examples of every
# filtering dimension. Each stratum is documented with its test purpose.
# Summer term (202060) is included for term_type filtering tests.
# =============================================================================

message("Sampling sections...")

stable <- sections %>% filter(term %in% TEST_TERMS, department %in% TEST_DEPTS)

# ── Stratum 1: active sections, stratified by term × dept × level ────────────
# 3 per stratum gives variety without blowing up student counts.
# This is the base; later strata add coverage for specific dimensions.
s_base <- stable %>%
  filter(status == "A") %>%
  group_by(term, department, level) %>%
  slice_head(n = 3) %>%
  ungroup()

# ── Stratum 2: cancelled sections ────────────────────────────────────────────
# Tests for status filtering ("only active", "show cancelled").
# 2 per (term × dept) from target depts; cancel status = C or S.
s_cancelled <- stable %>%
  filter(status != "A") %>%
  group_by(term, department) %>%
  slice_head(n = 2) %>%
  ungroup()

# ── Stratum 3: EA campus ─────────────────────────────────────────────────────
# Ensures campus != ABQ is present. ANTH and NURS both have EA sections.
s_ea <- stable %>%
  filter(status == "A", campus == "EA") %>%
  group_by(term, department) %>%
  slice_head(n = 2) %>%
  ungroup()

# ── Stratum 4: delivery method variety ───────────────────────────────────────
# Need ENH and ONL explicitly represented (base stratum may miss these).
s_enh <- stable %>%
  filter(status == "A", delivery_method == "ENH") %>%
  group_by(term, department) %>%
  slice_head(n = 2) %>%
  ungroup()

s_onl <- stable %>%
  filter(status == "A", delivery_method == "ONL") %>%
  group_by(term, department) %>%
  slice_head(n = 2) %>%
  ungroup()

# ── Stratum 5: part_term variety ─────────────────────────────────────────────
# 1H and 2H (half-term). NF is NURS-only and will appear via base stratum.
s_1h <- stable %>%
  filter(status == "A", part_term == "1H") %>%
  group_by(term, department) %>%
  slice_head(n = 2) %>%
  ungroup()

s_2h <- stable %>%
  filter(status == "A", part_term == "2H") %>%
  group_by(term, department) %>%
  slice_head(n = 2) %>%
  ungroup()

# ── Stratum 6: crosslisted sections ──────────────────────────────────────────
# Pull complete crosslist groups so crosslist logic tests have real data.
# We want a variety of scenarios. Find groups within our target depts.
#
# Scenario A: split-level (upper + grad in same group) — already in 202080 ANTH
# Scenario B: cross-dept (2+ departments in one group)
# Scenario C: 3+ section group
# Scenario D: group where the grad section is primary (highest enrollment)

xl_stable <- stable %>% filter(!is.na(crosslist_group), status == "A")

# A: split-level groups in target depts (pick up to 2 groups)
xl_split_groups <- xl_stable %>%
  filter(is_split) %>%
  distinct(crosslist_group, term) %>%
  slice_head(n = 2)

# B: cross-dept groups involving target depts
xl_crossdept_groups <- xl_stable %>%
  group_by(crosslist_group, term) %>%
  filter(n_distinct(department) > 1) %>%
  ungroup() %>%
  distinct(crosslist_group, term) %>%
  slice_head(n = 2)

# C: 3+ section groups in target depts
xl_threeway_groups <- xl_stable %>%
  group_by(crosslist_group, term) %>%
  filter(n() >= 3) %>%
  ungroup() %>%
  distinct(crosslist_group, term) %>%
  slice_head(n = 2)

# D: groups where grad section is the primary
xl_gradprimary_groups <- xl_stable %>%
  filter(crosslist_primary == TRUE, level == "grad") %>%
  distinct(crosslist_group, term) %>%
  slice_head(n = 2)

xl_target_groups <- bind_rows(
  xl_split_groups, xl_crossdept_groups,
  xl_threeway_groups, xl_gradprimary_groups
) %>% distinct(crosslist_group, term)

# Pull ALL sections belonging to those groups (not just target-dept rows)
# so crosslist joins are internally consistent.
s_crosslist <- sections %>%
  filter(term %in% TEST_TERMS) %>%
  semi_join(xl_target_groups, by = c("crosslist_group", "term"))

# ── Stratum 7: DFW-rich sections ─────────────────────────────────────────────
# Sections that have DR + W + F + passing grades all present in students.
# Used for DFW integration tests. Prefer small sections (easier to reason about).
# Identified by running: students with all grade types in one section.
dfw_rich_section_ids <- students %>%
  filter(term %in% TEST_TERMS) %>%
  group_by(section_id, term, department) %>%
  summarise(
    n_dr   = sum(registration_status_code == "DR"),
    n_w    = sum(final_grade == "W", na.rm = TRUE),
    n_fail = sum(final_grade %in% c("F", "D", "D+", "D-"), na.rm = TRUE),
    n_pass = sum(final_grade %in% c("A+","A","A-","B+","B","B-","C+","C","C-","S","CR"), na.rm = TRUE),
    .groups = "drop"
  ) %>%
  filter(n_dr > 0, n_w > 0, n_fail > 0, n_pass > 0,
         department %in% TEST_DEPTS) %>%
  arrange(n_dr + n_w + n_fail + n_pass) %>%  # smallest first
  slice_head(n = 6) %>%
  pull(section_id)

s_dfw <- sections %>% filter(section_id %in% dfw_rich_section_ids)

# ── Edge cases ────────────────────────────────────────────────────────────────
# Rows added here cover scenarios not guaranteed by the strata above.
# Add new edge cases here as tests require them; re-run and commit .qs files.
#
# EC-01: Zero-enrollment active section — tests that low-enrollment logic
#   handles 0 (not NA) enrolled. Rare enough to be sampled out.
# EC-02: Cancelled section with enrollment > 0 — tests that cancel status
#   is not confused with "empty" section logic.
# EC-03: Combined C-suffix course (3 CRNs, 1 crosslist group) — mimics the
#   real ANTH 2190C pattern that caused Keith's enrollment bug. Each CRN has
#   enrolled = per-lab-section count (~15-17), but total_enrl = 47 (correct
#   course-level enrollment). Only one CRN is crosslist_primary. Without the
#   combined-course correction, get_enrl() would report enrolled=16 instead
#   of 47 after the crosslist "home" filter keeps only the primary CRN.
ec_sections <- tibble(
  section_id        = c("EC-202010-00001",            "EC-202010-00002",
                        "EC-202080-00003",            "EC-202080-00004",            "EC-202080-00005"),
  term              = c(202010L,                       202010L,
                        202080L,                       202080L,                       202080L),
  crn               = c("EC001",                      "EC002",
                        "EC003",                      "EC004",                      "EC005"),
  subject           = c("HIST",                       "HIST",
                        "ANTH",                       "ANTH",                       "ANTH"),
  course_number     = c("1110",                       "2110",
                        "2190C",                      "2190C",                      "2190C"),
  subject_course    = c("HIST 1110",                  "HIST 2110",
                        "ANTH 2190C",                 "ANTH 2190C",                 "ANTH 2190C"),
  section           = c("901",                        "001",
                        "002",                        "003",                        "004"),
  course_title      = c("Survey of World History I",  "US History I",
                        "Forensic Anthropology",      "Forensic Anthropology",      "Forensic Anthropology"),
  part_term         = c("1",                          "1",
                        "1",                          "1",                          "1"),
  campus            = c("ABQ",                        "ABQ",
                        "ABQ",                        "ABQ",                        "ABQ"),
  college           = c("AS",                         "AS",
                        "AS",                         "AS",                         "AS"),
  department        = c("HIST",                       "HIST",
                        "ANTH",                       "ANTH",                       "ANTH"),
  instructor_id     = c("EC-INST-001",                "EC-INST-001",
                        "EC-INST-002",                "EC-INST-002",                "EC-INST-002"),
  instructor_name   = c("Edge, Case",                 "Edge, Case",
                        "Combined, Case",             "Combined, Case",             "Combined, Case"),
  enrolled          = c(0L,                           12L,
                        16L,                          16L,                          15L),
  total_enrl        = c(0L,                           12L,
                        47L,                          47L,                          47L),
  capacity          = c(25L,                          30L,
                        48L,                          48L,                          48L),
  available         = c(25L,                          18L,
                        1L,                           1L,                           1L),
  status            = c("A",                          "C",
                        "A",                          "A",                          "A"),
  delivery_method   = c("ENH",                        "ENH",
                        "ENH",                        "ENH",                        "ENH"),
  level             = c("lower",                      "lower",
                        "lower",                      "lower",                      "lower"),
  term_type         = c("spring",                     "spring",
                        "fall",                        "fall",                       "fall"),
  is_combined       = c(FALSE,                        FALSE,
                        TRUE,                         TRUE,                         TRUE),
  waitlist_count    = c(0L,                           0L,
                        0L,                           0L,                           0L),
  waitlist_capacity = c(0L,                           0L,
                        0L,                           0L,                           0L),
  crosslist_group   = c(NA_character_,                NA_character_,
                        "EC",                         "EC",                         "EC"),
  crosslist_code    = c(NA_character_,                NA_character_,
                        "EC",                         "EC",                         "EC"),
  crosslist_primary = c(TRUE,                         TRUE,
                        TRUE,                         FALSE,                        FALSE),
  is_split          = c(FALSE,                        FALSE,
                        FALSE,                        FALSE,                        FALSE),
  credits_min       = c(3,                            3,
                        4,                            4,                            4),
  credits_max       = c(3,                            3,
                        4,                            4,                            4),
  start_date        = as.Date(c("2020-01-20",         "2020-01-20",
                                "2020-08-17",         "2020-08-17",                 "2020-08-17")),
  end_date          = as.Date(c("2020-05-16",         "2020-05-16",
                                "2020-12-12",         "2020-12-12",                 "2020-12-12"))
)

# ── Combine all strata ────────────────────────────────────────────────────────
test_sections <- bind_unique(
  s_base, s_cancelled, s_ea, s_enh, s_onl, s_1h, s_2h, s_crosslist, s_dfw,
  ec_sections,
  id_col = "section_id"
)

message(sprintf("  %d sections selected", nrow(test_sections)))
message("  By term × dept:")
test_sections %>%
  count(term, department) %>%
  pwalk(~ message(sprintf("    %d / %-5s : %d sections", ..1, ..2, ..3)))
message("  Campus breakdown:")
test_sections %>% count(campus) %>%
  pwalk(~ message(sprintf("    %-6s: %d", ..1, ..2)))
message("  Status breakdown:")
test_sections %>% count(status) %>%
  pwalk(~ message(sprintf("    %s: %d", ..1, ..2)))
message("  Delivery method breakdown:")
test_sections %>% count(delivery_method) %>%
  pwalk(~ message(sprintf("    %-8s: %d", ..1, ..2)))
message("  Level breakdown:")
test_sections %>% count(level) %>%
  pwalk(~ message(sprintf("    %-8s: %d", ..1, ..2)))
message("  Part_term breakdown:")
test_sections %>% count(part_term) %>%
  pwalk(~ message(sprintf("    %-4s: %d", ..1, ..2)))
message("  Crosslisted sections: ",
        sum(!is.na(test_sections$crosslist_group)))

# =============================================================================
# STUDENTS
# All students enrolled in the sampled active sections.
# =============================================================================

message("\nSampling students...")

active_section_ids <- test_sections %>%
  filter(status == "A") %>%
  pull(section_id)

test_student_ids <- unique(
  students$student_id[students$section_id %in% active_section_ids]
)

test_students <- students %>%
  filter(section_id %in% active_section_ids)

message(sprintf("  %d enrollment records for %d unique students",
                nrow(test_students), length(test_student_ids)))
message("  Grade distribution:")
test_students %>%
  filter(!is.na(final_grade)) %>%
  count(final_grade) %>%
  arrange(desc(n)) %>%
  pwalk(~ message(sprintf("    %-6s: %d", ..1, ..2)))
message("  Registration status breakdown:")
test_students %>%
  count(registration_status_code) %>%
  pwalk(~ message(sprintf("    %-4s: %d", ..1, ..2)))

# =============================================================================
# PROGRAMS
#
# Three sources:
#   1. All program records for students in our section sample (cross-table joins)
#   2. Direct health-college sample (pre-major + declared health scenarios)
#   3. Major changers — students who switched dept_code across stable terms
#   4. Pre-major → declared transitions within same dept
# =============================================================================

message("\nSampling programs...")

prog_stable <- programs %>% filter(term %in% TEST_TERMS)

# Source 1: students from sections
programs_from_students <- prog_stable %>%
  filter(student_id %in% test_student_ids)

# Source 2: health colleges
programs_health_direct <- prog_stable %>%
  filter(student_college %in% c("College of Nursing", "College of Population Health")) %>%
  group_by(term, student_college, program_type) %>%
  slice_head(n = 10) %>%
  ungroup()

# Source 3: major changers — students with 2+ distinct dept_codes across stable terms
# Provides real data for detect_major_changes() tests.
changer_ids <- prog_stable %>%
  filter(program_type == "Major") %>%
  group_by(student_id) %>%
  filter(n_distinct(dept_code) > 1) %>%
  ungroup() %>%
  distinct(student_id) %>%
  slice_head(n = 20) %>%
  pull(student_id)

programs_changers <- prog_stable %>%
  filter(student_id %in% changer_ids)

# Source 4: pre-major → declared transitions
# Students who appear as pre-major in one term and declared in a later term
# within the same dept_code. Provides data for population-trend tests.
transition_ids <- prog_stable %>%
  filter(program_type == "Major") %>%
  group_by(student_id, dept_code) %>%
  filter(any(is_pre_major) & any(!is_pre_major)) %>%
  ungroup() %>%
  distinct(student_id) %>%
  slice_head(n = 20) %>%
  pull(student_id)

programs_transitions <- prog_stable %>%
  filter(student_id %in% transition_ids)

test_programs <- bind_unique(
  programs_from_students,
  programs_health_direct,
  programs_changers,
  programs_transitions,
  id_col = "program_id"
)

n_changers_added   <- n_distinct(programs_changers$student_id[
  !programs_changers$student_id %in% programs_from_students$student_id])
n_transitions_added <- n_distinct(programs_transitions$student_id[
  !programs_transitions$student_id %in% programs_from_students$student_id])

message(sprintf("  %d program records", nrow(test_programs)))
message(sprintf("    from section students : %d records", nrow(programs_from_students)))
message(sprintf("    health direct         : %d net-new students",
  n_distinct(programs_health_direct$student_id[
    !programs_health_direct$student_id %in% programs_from_students$student_id])))
message(sprintf("    major changers        : %d net-new students", n_changers_added))
message(sprintf("    pre→declared          : %d net-new students", n_transitions_added))

message("  Pre-major breakdown:")
test_programs %>%
  filter(program_type == "Major") %>%
  count(is_pre_major) %>%
  pwalk(~ message(sprintf("    is_pre_major = %-5s : %d", ..1, ..2)))

message("  Major changers (students with 2+ dept_codes):")
test_programs %>%
  filter(program_type == "Major") %>%
  group_by(student_id) %>%
  filter(n_distinct(dept_code) > 1) %>%
  ungroup() %>%
  summarise(students = n_distinct(student_id), records = n()) %>%
  pwalk(~ message(sprintf("    %d students, %d records", ..1, ..2)))

# =============================================================================
# DEGREES
# =============================================================================

message("\nSampling degrees...")

test_degrees <- degrees %>%
  filter(term %in% DEGREE_TERMS) %>%
  group_by(term) %>%
  slice_head(n = 20) %>%
  ungroup()

message(sprintf("  %d degrees selected", nrow(test_degrees)))
test_degrees %>%
  count(term) %>%
  pwalk(~ message(sprintf("    %d: %d degrees", ..1, ..2)))

# =============================================================================
# FACULTY
# All faculty in CAS test departments and terms.
# =============================================================================

message("\nSampling faculty...")

test_faculty <- faculty %>%
  filter(term %in% TEST_TERMS, department %in% FACULTY_DEPTS) %>%
  distinct(instructor_id, term, .keep_all = TRUE)

message(sprintf("  %d faculty records, %d unique instructors",
                nrow(test_faculty), n_distinct(test_faculty$instructor_id)))
test_faculty %>%
  count(term, department) %>%
  pwalk(~ message(sprintf("    %d / %-5s : %d faculty", ..1, ..2, ..3)))

# =============================================================================
# Save fixtures
# =============================================================================

message("\nSaving fixtures...")

fixture_dir <- "tests/testthat/fixtures"
dir.create(fixture_dir, recursive = TRUE, showWarnings = FALSE)

qsave(test_sections, file.path(fixture_dir, "cedar_sections_test.qs"))
qsave(test_students, file.path(fixture_dir, "cedar_students_test.qs"))
qsave(test_programs, file.path(fixture_dir, "cedar_programs_test.qs"))
qsave(test_degrees,  file.path(fixture_dir, "cedar_degrees_test.qs"))
qsave(test_faculty,  file.path(fixture_dir, "cedar_faculty_test.qs"))

message("\n\u2705 Test fixtures written to tests/testthat/fixtures/")
message(sprintf("   cedar_sections_test.qs  : %d rows", nrow(test_sections)))
message(sprintf("   cedar_students_test.qs  : %d rows", nrow(test_students)))
message(sprintf("   cedar_programs_test.qs  : %d rows", nrow(test_programs)))
message(sprintf("   cedar_degrees_test.qs   : %d rows", nrow(test_degrees)))
message(sprintf("   cedar_faculty_test.qs   : %d rows", nrow(test_faculty)))
message(sprintf("\n   Stable terms: %s", paste(TEST_TERMS, collapse = ", ")))
message(sprintf("   Section/student depts: %s", paste(TEST_DEPTS, collapse = ", ")))
message(sprintf("   Faculty depts: %s (CAS only)", paste(FACULTY_DEPTS, collapse = ", ")))
message("\n   Run tests: devtools::test()")
