# Scenario tables: the fixed tables one test file reads.
#
# fixtures/designed_test_data.R is the test database. This file holds what the
# tests read beyond it: a minimal frame typed by hand as the input of one
# function, or a table derived once from the designed fixtures (a population,
# an attempts table, a scenario's edges). Each is built once, when setup.R
# sources this file after the fixtures and the measure tables exist, and is the
# same object for every test. Nothing here is a function: a table that needs
# an argument is a helper (helper-<topic>.R), and a test that needs a variant
# says so in its own body.
#
# Sections are named for the test file that reads them, in the order testthat
# runs them. A table may read one defined above it.

# ── test-admin.R ────────────────────────────────────────────────────────────────

# Scaffolding: a mapping-file list with three program rows. FRAD carries
# students in the HP01 fixture; ZZZZ appears only in the file (a degree-only
# code) and must still be listed, with no students; NURS is confirmed and must
# not be.
review_files <- list(
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

# Scaffolding: what build_admin_mapping_issues() would say about three codes.
# FRAD is proposed in the file (merged into its row), NOFILE has no row at all
# (listed, unlinked), and NURS is already confirmed (not listed, but counted).
review_issues <- tibble::tibble(
  issue_type = c("pre_major_self_mapped_department", "declared_majors_far_exceed_graduates",
                 "identity_fallback_department"),
  severity = "warning", review_status = "needs_review",
  program_code = c(NA, "BA-NOFILE-AS", NA), major_code = c("FRAD", "NOFILE", "NURS"),
  college_code = NA, dept_code = NA, degree_level = NA, program_type = NA,
  details = c("pre-major maps to itself", "no department owner", "falls back to itself"))

# Scaffolding for build_counting_rules(): the transform's output columns the
# rules read, as small frames. Programs: two concentration rows (one under an
# undecided major, so no department, and flagged a pre-major by its name, as
# tables built before I21's fix show "Pre-Law"), one coded pre-major by name (FZZZ),
# one PHRD undergraduate, rows reporting Banner's college. Sections: a cross-list
# group spanning HIST and ENGL (home and partner) and one within HIST, an
# excluded course, levels 3 lower / 1 upper / 1 grad. Students: S1-S3 in
# 202080; S3 at TA has no program record. Student terms: their home campus and
# whether they declared, as cedar_student_terms records it, plus S4, declared
# with no class-list row, whom the no-program-record rule never counts.
counting_rule_tables <- local({
  programs <- tibble::tibble(
    student_id = c("S1", "S1", "S2", "S2", "S1", "S2"), term = 202080L,
    program_type = c("Major", "First Concentration", "Major", "First Concentration",
                     "Second Major", "First Minor"),
    program_name = c("History", "Public Policy", "Zed", "Law", "Pharmacy", "Undecided"),
    major_code = c("HIST", NA, "FZZZ", NA, "PHRD", "UNDC"),
    dept_code = c("HIST", "HIST", NA, NA, "PHRM", NA),
    is_pre_major = c(FALSE, FALSE, TRUE, TRUE, TRUE, FALSE),
    pre_major_basis = c("programs_csv", "name_prefix", "name_prefix", "name_prefix",
                        "phrd_undergraduate", "programs_csv"),
    college_basis = c("mapped", "mapped", "banner", "banner", "mapped", "banner"),
    student_campus = c("Albuquerque/Main", "Albuquerque/Main", "Albuquerque/Main",
                       "Albuquerque/Main", "Albuquerque/Main", "Albuquerque/Main"))
  sections <- tibble::tibble(
    term = 202080L, campus = c("ABQ", "ABQ", "ABQ", "ABQ", "EA"),
    subject = c("HIST", "ENGL", "HIST", "HIST", "ZZZZ"),
    subject_course = c("HIST 300", "ENGL 300", "HIST 101", "HIST 501", excluded_courses[1]),
    level = c("upper", "lower", "lower", "grad", "lower"),
    department = c("HIST", "ENGL", "HIST", "HIST", NA),
    college_basis = c("mapped", "mapped", "mapped", "mapped", "banner"),
    crosslist_group = c("G1", "G1", "G2", "G2", NA),
    crosslist_role = c("home", "partner", "internal", "internal", NA))
  # As the loader keys them (attach_course_ids()); no code is renamed here.
  sections$course_id <- sections$subject_course
  sections$listed_code <- sections$subject_course
  students <- tibble::tibble(
    student_id = c("S1", "S2", "S3", "S3"), term = 202080L,
    campus = c("ABQ", "EA", "TA", "ZZ"),
    college_basis = c("mapped", "mapped", "banner", "mapped"))
  student_terms <- tibble::tibble(
    student_id = c("S1", "S2", "S3", "S4"), term = 202080L,
    student_campus = c("ABQ", "ABQ", "TA", "ABQ"),
    declared = c(TRUE, TRUE, FALSE, TRUE), class_list_rows = c(1L, 1L, 2L, 0L))
  list(programs = programs, sections = sections, students = students,
       student_terms = student_terms)
})

# ── test-catalogs.R ─────────────────────────────────────────────────────────────

# One valid row of each mapping file: what a mapping directory holds when a
# test needs the file and nothing in particular in it.
mapping_program_row <- data.frame(
  program_code = "HIST", in_college = "", program_name = "HIST", unit_code = "HIST",
  college_code = "", is_pre_major = "FALSE", leads_to = "", basis = "decided",
  status = "confirmed", evidence = "", notes = "")

mapping_subject_row <- data.frame(
  subject_code = "HIST", in_college = "AS", in_level = "", unit_code = "HIST",
  college_code = "", status = "confirmed", evidence = "", notes = "")

mapping_history_row <- data.frame(
  kind = "course", from_code = "MATH 120", to_code = "MATH 1215",
  effective_term = "202080", scope = "", basis = "catalog", status = "confirmed",
  evidence = "", notes = "")

# programs.csv as five tests design it, typed once; a test reads its rows by
# name (mapping_programs$invalid). Every program's name is its code, and HIST
# is the unit of every row that names no other.
mapping_programs <- local({
  rows <- tibble::tribble(
    ~table,       ~program_code, ~in_college, ~unit_code, ~college_code, ~is_pre_major, ~leads_to, ~basis,          ~status,
    # invalid: one row per fault the programs validator names.
    "invalid",    "HIST",        "",          "HIST",     "",            "FALSE",       "",        "decided",       "confirmed",  # a duplicate...
    "invalid",    "HIST",        "",          "HIST",     "",            "FALSE",       "",        "decided",       "confirmed",  # ...of this row
    "invalid",    "FHIS",        "",          "HIST",     "",            "TRUE",        "NOPE",    "decided",       "confirmed",  # target not a program
    "invalid",    "ANTH",        "",          "ANTH",     "",            "FALSE",       "",        "decided",       "confirmed",  # unit not in units.csv
    "invalid",    "NOND",        "",          "",         "",            "FALSE",       "",        "decided",       "confirmed",  # confirmed, no unit, not no_unit
    "invalid",    "GUES",        "",          "",         "",            "FALSE",       "",        "unresolved",    "confirmed",  # unresolved but confirmed
    "invalid",    "ODD",         "",          "HIST",     "",            "FALSE",       "",        "vibes",         "maybe",      # no such basis, no such status
    "invalid",    "LEAD",        "",          "HIST",     "",            "FALSE",       "HIST",    "decided",       "confirmed",  # target on a non-pre-major
    "invalid",    "SOCI",        "",          "SOCI",     "",            "FALSE",       "",        "decided",       "confirmed",
    "invalid",    "FSOC",        "",          "HIST",     "",            "TRUE",        "SOCI",    "decided",       "confirmed",  # target in another unit
    "invalid",    "FSOX",        "",          "HIST",     "",            "TRUE",        "SOCI",    "course_taking", "proposed",   # ...which is a fault only once confirmed
    # colleges: CRIM's unit, and so its college, depends on the in_college row.
    # BCHM is owned by HIST (college AS) and sets its own college; its pre-major
    # FBCH sets none. GUES is undecided. Nothing owns UNDC or NOND; UNDC names
    # a college, NOND names none.
    "colleges",   "CRIM",        "",          "SOCI",     "",            "FALSE",       "",        "decided",       "confirmed",
    "colleges",   "CRIM",        "AD",        "CJUS",     "",            "FALSE",       "",        "override",      "confirmed",
    "colleges",   "BCHM",        "",          "HIST",     "AD",          "FALSE",       "",        "decided",       "confirmed",
    "colleges",   "FBCH",        "",          "HIST",     "",            "TRUE",        "BCHM",    "decided",       "confirmed",
    "colleges",   "GUES",        "",          "",         "",            "FALSE",       "",        "unresolved",    "proposed",
    "colleges",   "UNDC",        "",          "",         "AS",          "FALSE",       "",        "no_unit",       "confirmed",
    "colleges",   "NOND",        "",          "",         "",            "FALSE",       "",        "no_unit",       "confirmed",
    # line_order: CRIM's college-specific row is first, on purpose (file line 2);
    # its every-college row is last (line 4).
    "line_order", "CRIM",        "AD",        "CJUS",     "",            "FALSE",       "",        "override",      "confirmed",
    "line_order", "HIST",        "",          "HIST",     "",            "FALSE",       "",        "decided",       "confirmed",
    "line_order", "CRIM",        "",          "SOCI",     "",            "FALSE",       "",        "decided",       "confirmed",
    # units: mirrors UNM's CRIM, Sociology on main campus and Criminal Justice at
    # the branches (college AD); ART is a proposal; nothing owns NOND.
    "units",      "CRIM",        "",          "SOCI",     "",            "FALSE",       "",        "decided",       "confirmed",
    "units",      "CRIM",        "AD",        "CJUS",     "",            "FALSE",       "",        "override",      "confirmed",
    "units",      "ART",         "",          "HIST",     "",            "FALSE",       "",        "course_taking", "proposed",
    "units",      "NOND",        "",          "",         "",            "FALSE",       "",        "no_unit",       "confirmed",
    # attach: HIST and CRIM (SOCI, but CJUS at the branch college AD), BCHM owned
    # by HIST but credited to AD, its pre-major FBCH, and UNDC, which nothing
    # owns but college AS reports.
    "attach",     "HIST",        "",          "HIST",     "",            "FALSE",       "",        "decided",       "confirmed",
    "attach",     "CRIM",        "",          "SOCI",     "",            "FALSE",       "",        "decided",       "confirmed",
    "attach",     "CRIM",        "AD",        "CJUS",     "",            "FALSE",       "",        "override",      "confirmed",
    "attach",     "BCHM",        "",          "HIST",     "AD",          "FALSE",       "",        "decided",       "confirmed",
    "attach",     "FBCH",        "",          "HIST",     "",            "TRUE",        "BCHM",    "decided",       "confirmed",
    "attach",     "UNDC",        "",          "",         "AS",          "FALSE",       "",        "no_unit",       "confirmed"
  ) %>%
    mutate(program_name = program_code, evidence = "", notes = "")
  lapply(split(rows[names(mapping_program_row)], rows$table), as.data.frame)
})

# subjects.csv as four tests design it, typed once and read by name.
mapping_subjects <- local({
  rows <- tibble::tribble(
    ~table,           ~subject_code, ~in_college, ~in_level, ~unit_code, ~college_code, ~status,
    # invalid: ANTH names a unit units.csv does not have and a college
    # colleges.csv does not have.
    "invalid",        "HIST",        "AS",        "",        "HIST",     "",            "confirmed",
    "invalid",        "ANTH",        "XX",        "",        "ANTH",     "",            "confirmed",
    # with_proposals: HIST is confirmed; ANTH is a proposal with a suggested
    # unit; GEX is a proposal nothing settled.
    "with_proposals", "HIST",        "AS",        "",        "HIST",     "",            "confirmed",
    "with_proposals", "ANTH",        "AS",        "",        "SOCI",     "",            "proposed",
    "with_proposals", "GEX",         "AS",        "",        "",         "",            "proposed",
    # specificity: mirrors UNM's GLNS, one unit (SOCI, home college AS) whose
    # graduate courses keep the unit's college and whose other courses are
    # credited to AD, with its lower-division courses in AD sections taught by
    # CJUS. HIST has a row for section college AS and one for graduate courses
    # in any college.
    "specificity",    "HIST",        "AS",        "",        "HIST",     "",            "confirmed",
    "specificity",    "HIST",        "",          "grad",    "SOCI",     "",            "confirmed",
    "specificity",    "GLNS",        "",          "grad",    "SOCI",     "",            "confirmed",
    "specificity",    "GLNS",        "",          "",        "SOCI",     "AD",          "confirmed",
    "specificity",    "GLNS",        "AD",        "lower",   "CJUS",     "",            "confirmed",
    # bad_level: senior is not a level.
    "bad_level",      "HIST",        "AS",        "",        "HIST",     "",            "confirmed",
    "bad_level",      "HIST",        "AS",        "senior",  "HIST",     "",            "confirmed"
  ) %>%
    mutate(evidence = "", notes = "")
  lapply(split(rows[names(mapping_subject_row)], rows$table), as.data.frame)
})

# code_history.csv with one row or pair of rows per fault the code-history
# validator names.
mapping_code_history_invalid <- tibble::tribble(
  ~kind,     ~from_code, ~to_code,    ~effective_term, ~scope,          ~basis,    ~status,
  "course",  "SOCI 371", "SOCI 371",  "202080",        "",              "catalog", "confirmed",  # a code does not succeed itself
  "course",  "MATH 120", "MATH 1215", "202080",        "",              "catalog", "confirmed",  # a duplicate...
  "course",  "MATH 120", "MATH 1215", "202080",        "",              "catalog", "confirmed",  # ...of this row
  "course",  "MATH 121", "MATH 1220", "202080",        "",              "catalog", "confirmed",  # a confirmed split...
  "course",  "MATH 121", "MATH 1230", "202080",        "",              "catalog", "confirmed",  # ...into two codes
  "course",  "MATH 122", "MATH 1240", "202080",        "",              "catalog", "proposed",   # a proposed split is fine
  "course",  "MATH 122", "MATH 1250", "202080",        "",              "catalog", "proposed",
  "subject", "PSY",      "PSYC",      "202080",        "undergraduate", "catalog", "confirmed",  # scope on a subject row
  "subject", "ALB",      "ALBS",      "2020",          "",              "catalog", "confirmed",  # not a term code
  "subject", "A",        "B",         "202080",        "",              "catalog", "confirmed",  # a cycle...
  "subject", "B",        "A",         "202080",        "",              "catalog", "confirmed",  # ...of two
  "course",  "soci 371", "SOCI 3710", "202080",        "",              "catalog", "confirmed",  # a lower-case code
  "major",   "RADS",     "FRAD",      "202080",        "",              "vibes",   "maybe"       # no such kind, basis or status
) %>%
  mutate(evidence = "", notes = "") %>%
  as.data.frame()

unm_settings <- data.frame(
  setting = c("mapping_files_url", "source_files_url", "projection_history_start_term"),
  value   = c("https://github.com/org/repo/blob/main/institution/x",
              "https://github.com/org/repo/blob/main", "202210"))

one_unit <- list(
  colleges = data.frame(college_code = c("AS", "AD"), college_name = c("Arts and Sciences", "Branch"),
                        source_names = c("", "Branch Campuses|ED")),
  units    = data.frame(unit_code = c("HIST", "SOCI", "CJUS"),
                        unit_name = c("History", "Sociology", "Criminal Justice"),
                        college_code = c("AS", "AS", "AD"), kind = "department", notes = ""),
  subjects = mapping_subject_row
)

good_levels <- data.frame(leading_digit = as.character(0:9),
                          level = c(rep("lower", 3), rep("upper", 2), rep("grad", 5)))

unm_programs <- read_institution_mappings(cedar_institution_dir(cedar_base_dir, "unm"))$programs

# ── test-course-attempts.R ──────────────────────────────────────────────────────

# The designed seats of the DFW demographics tests: HIST 1110 rows copied from
# the fixture's first, one per student, with the status and grade each test
# reads.
#   demo:      demo-01 A, demo-02 F, demo-03 late drop, demo-04 early drop,
#              demo-05 C-, demo-06 A
#   threshold: threshold-01 C-, threshold-02 A
dfw_demo_rows <- local({
  base_row <- test_students %>%
    dplyr::filter(subject_course == "HIST 1110") %>%
    dplyr::slice(1)
  seats <- function(ids, statuses, grades) {
    dplyr::bind_rows(lapply(seq_along(ids), function(i) {
      base_row %>% dplyr::mutate(
        student_id = ids[[i]], crn = as.character(93000 + i),
        registration_status_code = statuses[[i]], final_grade = grades[[i]]
      )
    }))
  }
  list(
    demo = seats(paste0("demo-0", 1:6), c("RE", "RE", "DW", "DR", "RE", "RE"),
                 c("A", "F", NA, NA, "C-", "A")),
    threshold = seats(c("threshold-01", "threshold-02"), c("RE", "RE"), c("C-", "A"))
  )
})

# The groups are the student-term table's, never the class list's (ADR-001
# step 5): the loaded class list carries no description, so each designed seat
# gets its classification and primary major from a student-term row here. The
# demo seats carry two codes programs.csv does not, so each is named as itself;
# the second is a pre-major, so it reads with the suffix every major table uses.
dfw_demo_student_terms <- list(
  demo = tibble::tibble(
    student_id = dfw_demo_rows$demo$student_id, term = as.integer(dfw_demo_rows$demo$term),
    student_classification = c(rep("Freshman", 4), "Sophomore", "Sophomore"),
    primary_major_code = c(rep("ZZHIST", 4), "ZZBIOL", "ZZBIOL"),
    is_pre_major = c(rep(FALSE, 4), TRUE, TRUE)
  ),
  threshold = tibble::tibble(
    student_id = dfw_demo_rows$threshold$student_id,
    term = as.integer(dfw_demo_rows$threshold$term),
    student_classification = "Sophomore", primary_major_code = "ZZBIOL", is_pre_major = FALSE
  )
)

# ── test-course-demographics-donuts.R ───────────────────────────────────────────

# Same category at two campuses, and a percentage column deliberately
# inconsistent with the headcounts — both true of the real source.
multi_campus_demo <- local({
  majors <- c("HIST", "ANTH", "ENGL", "PSYC", "BIOL", "MATH", "CHEM", "ECON", "SOCI")
  demo <- expand.grid(major_code = majors, campus = c("ABQ", "EA"),
                      stringsAsFactors = FALSE)
  demo$college        <- "AS"
  demo$subject_course <- "HIST 1105"
  demo$term_type      <- "fall"
  demo$mean           <- c(40, 30, 20, 15, 10, 5, 4, 3, 2,
                           20, 15, 10,  8,  5, 3, 2, 1, 1)
  demo$term_type_pct  <- round(100 * demo$mean / sum(demo$mean[demo$campus == "ABQ"]), 1)
  demo
})

# ── test-course-demographics.R ──────────────────────────────────────────────────

.hist_1110_registered <- test_students %>%
  filter(subject_course == "HIST 1110",
         registration_status_code %in% STATUS_REGISTERED)

# ── test-course-impact.R ────────────────────────────────────────────────────────

# The two cones read outcomes off cedar_attempts (ADR-001 step 7): MC02's
# attempt table, built to these edges; a test that adds rows rebuilds it.
.impact_attempts <- keyed_attempts(test_students_mc, .impact_edges)

.sequence_audit_fixture <- local({
  late_y <- .mc_row(
    "SEQ_T2", 202080, "SEQ 201", "ABQ", "SEQ",
    grade = NA_character_, instructor = "SEQ_I1"
  ) %>%
    dplyr::mutate(registration_status_code = "DW")

  students <- dplyr::bind_rows(
    .mc_row("SEQ_T1", 202010, "SEQ 101", "ABQ", "SEQ", "A", "SEQ_I1"),
    .mc_row("SEQ_T2", 202010, "SEQ 101", "ABQ", "SEQ", "A", "SEQ_I1"),
    .mc_row("SEQ_T1", 202080, "SEQ 201", "ABQ", "SEQ", "F", "SEQ_I1"),
    late_y,
    .mc_row("SEQ_T1", 202110, "SEQ 201", "ABQ", "SEQ", "A", "SEQ_I1"),
    .mc_row("SEQ_C1", 202080, "SEQ 201", "ABQ", "SEQ", "A", "SEQ_I1"),
    .mc_row("SEQ_C2", 202080, "SEQ 201", "ABQ", "SEQ", "B", "SEQ_I1"),
    # This X pass is outside the requested campus. The student's ABQ Y attempt
    # must therefore remain in the control group.
    .mc_row("SEQ_XC", 202010, "SEQ 101", "GA", "SEQ", "A", "SEQ_I2"),
    .mc_row("SEQ_XC", 202080, "SEQ 201", "ABQ", "SEQ", "A", "SEQ_I1")
  )

  ids <- c("SEQ_T1", "SEQ_T2", "SEQ_C1", "SEQ_C2", "SEQ_XC")
  program_template <- test_programs_mc %>%
    dplyr::filter(student_id == "MC_A2", term == 202010L) %>%
    dplyr::slice(1L)
  programs <- dplyr::bind_rows(lapply(seq_along(ids), function(i) {
    program_template %>%
      dplyr::mutate(
        student_id = ids[[i]],
        program_id = paste0("SEQ-PROG-", i),
        student_campus = "ABQ"
      )
  }))

  list(students = students, programs = programs, ids = ids)
})

# The audit fixture plus SEQ_F1, who failed SEQ 101 on ABQ in 202010 and then
# failed SEQ 201 in 202080 (control: attempted X earlier, did not pass), and
# SEQ_M1, who passed SEQ 101 and then passed the modular SEQ 201X (in no group
# until SEQ 201X is read as part of the later course).
#   Treatment: SEQ_T1 (Y dfw, HS 3.0, ACT 20), SEQ_T2 (Y dfw, no HS, no ACT)
#   Control:   SEQ_C1 (pass, 3.2, 22), SEQ_C2 (pass, 2.8, 16),
#              SEQ_XC (pass, none, none), SEQ_F1 (dfw, 3.0, 19)
.sequence_band_fixture <- local({
  fixture <- .sequence_audit_fixture
  fixture$students <- dplyr::bind_rows(
    fixture$students,
    .mc_row("SEQ_F1", 202010, "SEQ 101", "ABQ", "SEQ", "F", "SEQ_I1"),
    .mc_row("SEQ_F1", 202080, "SEQ 201", "ABQ", "SEQ", "F", "SEQ_I1"),
    .mc_row("SEQ_M1", 202010, "SEQ 101", "ABQ", "SEQ", "A", "SEQ_I1"),
    .mc_row("SEQ_M1", 202080, "SEQ 201X", "ABQ", "SEQ", "A", "SEQ_I1")
  )
  extra <- c("SEQ_F1", "SEQ_M1")
  fixture$programs <- dplyr::bind_rows(fixture$programs, lapply(seq_along(extra), function(i) {
    fixture$programs %>% dplyr::slice(1L) %>%
      dplyr::mutate(student_id = extra[[i]], program_id = paste0("SEQ-PROG-X", i))
  }))
  fixture$applicants <- tibble::tibble(
    student_id = c(fixture$ids, extra),
    high_school_cum_gpa    = c(3.0, NA, 3.2, 2.8, NA, 3.0, NA),
    unm_act_combined_score = c(20, NA, 22, 16, NA, 19, NA)
  )
  fixture
})

# ── test-course-overview.R ──────────────────────────────────────────────────────

# A hand-built overview with only the columns the snapshot reads, so expected
# values are visible here: four falls at ABQ, two at EA.
.snapshot_overview <- local({
  lifecycle <- tibble::tibble(
    campus = c(rep("ABQ", 4), "EA", "EA"),
    term = c(202080L, 202180L, 202280L, 202380L, 202180L, 202280L),
    term_type = "fall",
    subject_course = "HIST 1110",
    first_day_enrl = c(NA, 64L, 80L, 1104L, 10L, 15L),
    census_enrl = c(55, 66, 80, 1110, 10, 15),
    current_enrl = c(50L, 60L, 75L, 1000L, 10L, 15L),
    early_drops = c(5L, 6L, 8L, 10L, 0L, 1L),
    late_drops = c(5L, 6L, 5L, 110L, 0L, 0L),
    waitlisted = c(1L, 2L, 4L, 8L, 0L, 0L)
  )
  list(
    lifecycle = lifecycle,
    sections = tibble::tibble(
      campus = lifecycle$campus, term = lifecycle$term, term_type = "fall",
      subject_course = "HIST 1110", sections = c(2L, 3L, 4L, 40L, 1L, 1L),
      avg_section_size = c(25, 20, 18.75, 25.04, 10, 15)
    ),
    listings = lifecycle[, c("campus", "term", "term_type", "subject_course",
                             "first_day_enrl", "census_enrl", "current_enrl",
                             "early_drops", "late_drops", "waitlisted")],
    overlap = tibble::tibble(
      campus = character(), term = integer(), term_type = character(),
      kind = character(), from_code = character(), to_code = character(),
      students = integer()
    )
  )
})

# ── test-course-planning-history.R ──────────────────────────────────────────────

course_history_terms <- course_terms_for(test_students_course_history, test_sections_course_history)

pending_session_terms <- course_terms_for(test_students_pending_session, test_sections_pending_session)

# Catalog membership is analytical scaffolding over EC-11's recorded histories.
planning_gen_ed <- data.frame(subject_course = c("SOCI 100", "SOCI 101", "SOCI 104"),
  area_label = c("4: Social sciences", "4: Social sciences", "5: Humanities"))

# ── test-course-similar-students.R ──────────────────────────────────────────────

ss_attempts <- keyed_attempts(test_students_rp, rp01_edges)

ss_attempts2 <- local({
  .ss_row <- function(sid, term_code, outcome_value, instructor = "RP_I1") {
    ss_attempts %>% slice(1L) %>%
      mutate(student_id = sid, term = as.integer(term_code), subject_course = "HIST 101",
             outcome = outcome_value, instructor_id = instructor, instructor_name = instructor)
  }
  bind_rows(
    ss_attempts,
    .ss_row("RP_BACK", 202010, "pass"), .ss_row("RP_FAIL", 202010, "pass", "RP_I3"),
    .ss_row("RP_REP", 202080, "dfw"), .ss_row("RP_BACK", 202080, "pass"), .ss_row("RP_FAIL", 202080, "dfw")
  )
})

ss_student_terms2 <- test_student_terms_rp %>%
  mutate(sem_gpa = case_when(
    term == 202080L & student_id == "RP_BACK" ~ 3.0,
    term == 202080L & student_id == "RP_FAIL" ~ 2.0,
    term == 202080L & student_id == "RP_REP" ~ 4.0,
    TRUE ~ sem_gpa
  ))

ss_ids <- unique(test_student_terms_rp$student_id)

ss_app <- tibble::tibble(student_id = ss_ids, high_school_cum_gpa = 3.0)

# ── test-courses.R ──────────────────────────────────────────────────────────────

demo_files <- read_institution_mappings(cedar_institution_dir(cedar_base_dir, "demo"))

# The demo institution's files, whichever institution load_funcs() read.
demo_dims <- build_cedar_dims(demo_files)

# ── test-credit-hours-outside-colors.R ──────────────────────────────────────────

# Home major codes the way Dept Trends resolves them (set_payload's prog_codes).
hist_major_codes <- names(major_to_dept)[!is.na(major_to_dept) & major_to_dept == "HIST"]

# test_student_terms names no primary major (built without programs), so the
# raw fixture cannot tell a home major from an outside one. Stamp one on the
# student-term table: HIST students sorted by id, first half "HIST-BA" (home),
# second half "BIOL-BS" (outside). Local scaffolding for this contract; the
# shared tables stay unchanged.
ch_student_terms_with_majors <- local({
  st  <- test_student_terms
  ids <- sort(unique(test_students$student_id[test_students$department == "HIST"]))
  home_ids <- ids[seq_len(ceiling(length(ids) / 2))]
  st$primary_major_code <- dplyr::case_when(
    st$student_id %in% home_ids ~ "HIST-BA",
    st$student_id %in% ids      ~ "BIOL-BS",
    TRUE                        ~ st$primary_major_code
  )
  st
})

# ── test-credit-timeline.R ──────────────────────────────────────────────────────

ct_population <- tibble::tibble(student_id = c("CT_A", "CT_C"), population_label = "ct")

# CT_A takes one course per term across their four terms.
ct_students <- tibble::tibble(
  student_id = rep("CT_A", 4),
  term = c(202080L, 202110L, 202180L, 202210L),
  subject_course = "CTMP 101",
  course_title = "Test Course",
  student_classification = "Freshman",
  registration_status_code = "RE",
  campus = "ABQ"
)

# ── test-crosslist-split.R ──────────────────────────────────────────────────────

# Derived view used throughout — mirrors how production code sees XL sections
xl_sections <- test_sections %>% filter(!is.na(crosslist_group))

# ── test-data-anomalies.R ───────────────────────────────────────────────────────

# DA01 (local): three programs over 2024-2026, each with 50 majors a term.
#   SEL   50 undergrad majors,  5 grads/yr  -> ratio 10.0, flagged
#   NORM  50 undergrad majors, 25 grads/yr  -> ratio  2.0, not flagged
#   GRAD  45 GRADUATE + 5 undergrad majors, 5 baccalaureate grads/yr
#         -> ratio 1.0 when levels are paired; 10.0 if they are not.
anomaly_ratio_programs <- local({
  terms <- c(202480L, 202580L, 202680L)
  build <- function(code, n, level) {
    tidyr::expand_grid(term = terms, i = seq_len(n)) %>%
      dplyr::transmute(
        student_id = paste0(code, "-", level, "-", i), term, major_code = code,
        program_name = code, is_pre_major = FALSE, program_type = "Major",
        student_level = level
      )
  }
  dplyr::bind_rows(
    build("SEL", 50L, "Undergraduate"),
    build("NORM", 50L, "Undergraduate"),
    build("GRAD", 45L, "Graduate"),
    build("GRAD", 5L, "Undergraduate")
  )
})

anomaly_ratio_degrees <- local({
  terms <- c(202410L, 202510L, 202610L)
  build <- function(code, n) {
    tidyr::expand_grid(term = terms, i = seq_len(n)) %>%
      dplyr::transmute(
        student_id = paste0(code, "-grad-", term, "-", i), term, major_code = code,
        award_category = "Baccalaureate Degree"
      )
  }
  dplyr::bind_rows(build("SEL", 5L), build("NORM", 25L), build("GRAD", 5L))
})

# Scaffolding: mapping files for the designed fixture's synthetic institution,
# with one deliberate gap of each kind. BIOL has no subject row; section college
# AS and Translated College EDU name no college; ENGL-BA and FSEC-BS have no
# program row; PSYC has no home college. POLS-BA and BUSA-BBA are mapped to a
# college Banner's Translated College disagrees with -- BUSA-BBA's pre-major
# rows are the expected kind of difference, its others need review.
audit_files <- local({
  prog <- function(code, unit, pre = "FALSE") data.frame(
    program_code = code, in_college = "", program_name = code, unit_code = unit,
    college_code = "", is_pre_major = pre, leads_to = "", basis = "decided",
    status = "confirmed", evidence = "", notes = "")
  list(
    colleges = data.frame(college_code = c("ARTS", "SOSC", "STEM", "NURS", "BUS"),
                          college_name = c("Arts", "Social Science", "STEM", "Nursing", "Business"),
                          source_names = ""),
    units = data.frame(unit_code = c("ANTH", "HIST", "MATH", "NURS", "BUSN", "PSYC"),
                       unit_name = "", college_code = c("SOSC", "ARTS", "STEM", "NURS", "BUS", ""),
                       kind = "department", notes = ""),
    subjects = data.frame(subject_code = c("ANTH", "HIST", "MATH", "NURS"),
                          in_college = c("SOSC", "ARTS", "STEM", "NURS"), in_level = "",
                          college_code = "",
                          unit_code = c("ANTH", "HIST", "MATH", "NURS"),
                          status = "confirmed", evidence = "", notes = ""),
    programs = rbind(
      prog(c("ANTH-BA", "ANTH"), "ANTH"), prog(c("HIST-BA", "HIST-MA", "HIST"), "HIST"),
      prog(c("MATH-BS", "BIOL-BS", "MATH"), "MATH"), prog("NURS-BS", "NURS"),
      prog(c("POLS-BA", "PSYC-MIN"), "HIST"),
      prog("BUSA-BBA", "MATH"), prog(c("ACCT-BBA", "BUAN-BBA", "BUMG-BBA", "FINC-BBA"), "BUSN")),
    settings = data.frame(setting = c("mapping_files_url", "source_files_url"),
                          value = c("https://github.com/org/repo/blob/main/institution/x",
                                    "https://github.com/org/repo/blob/main"))
  )
})

# ── test-data-edges.R ───────────────────────────────────────────────────────────

edge_students <- local({
  mk <- function(term, n, graded) tibble::tibble(
    term = rep(as.integer(term), n),
    final_grade = c(rep("A", graded), rep(NA_character_, n - graded))
  )
  dplyr::bind_rows(
    mk(202480, 100, 91),   # finished, graded
    mk(202580, 100, 91),   # finished, graded
    mk(202610, 100, 7),    # finished, grades still landing
    mk(202660, 100, 0),    # registration only
    mk(202680, 100, 0)     # registration only, partial
  )
})

edge_degrees <- tibble::tibble(
  term = c(202480L, 202580L, 202610L),
  graduation_status = c("Awarded", "Awarded", "Pending")
)

edge_settled_students <- local({
  mk <- function(term, n, graded, pull) tibble::tibble(
    term = rep(as.integer(term), n),
    final_grade = c(rep("A", graded), rep(NA_character_, n - graded)),
    as_of_date = as.Date(pull)
  )
  dplyr::bind_rows(
    mk(202580, 100, 91, "2026-03-07"),   # Fall 2025, pulled long after it began
    mk(202610, 100,  7, "2026-04-20"),   # Spring 2026, began Jan, pulled April
    mk(202660, 100,  0, "2026-04-27"),   # Summer 2026, pulled BEFORE it begins
    mk(202680,  70,  0, "2026-06-18")    # Fall 2026, pulled BEFORE it begins
  )
})

# ── test-data-integrity.R ───────────────────────────────────────────────────────

ids_tables <- list(
  ids_clean   = test_ids_clean,
  ids_split   = test_ids_split,
  ids_partial = test_ids_partial,
  ids_orphan  = test_ids_orphan
)

# ── test-declaration-context.R ──────────────────────────────────────────────────

decl_hist_ids <- unique(test_programs$student_id[test_programs$dept_code == "HIST"])

decl_hist_population <- tibble::tibble(
  student_id       = decl_hist_ids,
  population_label = "HIST",
  first_unm_term   = 202010L
)

# ── test-degree-explorer.R ──────────────────────────────────────────────────────

# Public-source ingestion uses an authored catalog fixture, just like the demo
# CSVs setup.R reads. It models nested alternatives/bundles, a prose condition, an
# unlabeled minor, an excluded graduate credential, and cyclic course links.
scan_fixture <- read_source_json(file.path(cedar_institution_dir(cedar_base_dir, "demo"), "catalog-source-fixture.json"))

scan_config <- local({
  dir <- cedar_institution_dir(cedar_base_dir, "demo")
  list(source = as.list(read_institution_file("catalog_scan_sources", dir)[1, ]),
    credentials = read_institution_file("catalog_scan_credentials", dir),
    fields = read_institution_file("catalog_scan_fields", dir))
})

# ── test-enrollment-projection-scenario.R, test-projection-inputs.R, ─────────────
# ── test-projection-model.R, test-projection-view.R ─────────────────────────────

# One prepared history row, as prepare_enrollment_projection_inputs() shapes
# it: a Fall of TEST 101 in the pooled market, complete on the first day, with
# 100 in every count column. projection_test_history() stamps a test's own
# series on it.
projection_history_row <- tibble::tibble(
  market_id = "abq_ea_course_market",
  college = "AS",
  subject_course = "TEST 101",
  term = 202380L,
  term_type = "fall",
  registered = 100,
  dr_early = 0,
  dr_late = 0,
  classlist_total = 100,
  first_day_enrl = 100,
  first_day_basis = "complete",
  first_day_started_enrl = 100,
  census_enrl = 100
)

# One prepared scope row: TEST 101, forced into scope, targeting Fall 2024.
projection_test_row <- tibble::tibble(
  market_id = "abq_ea_course_market",
  college = "AS",
  department = "TEST",
  subject_course = "TEST 101",
  term_type = "fall",
  target_term = 202480L,
  scheduled_sections = 4L,
  scheduled_capacity = 140,
  target_classlist_total_to_date = 135,
  target_registered_now = 130,
  target_early_drops_to_date = 5,
  target_late_drops_to_date = 0,
  target_other_status_to_date = 0,
  target_registration_observed = TRUE,
  target_available_seats = 10,
  target_classlist_fill = 135 / 140,
  target_active_fill = 130 / 140,
  target_capacity_reached = FALSE,
  n_delivery_components = 2L,
  n_campuses = 2L,
  target_schedule_available = TRUE,
  recent_high_fill_terms = 2L,
  recent_capacity_terms = 3L,
  is_forced = TRUE,
  pressure_capacity_shortfall = FALSE,
  pressure_chronic_fill = TRUE,
  pressure_growth = FALSE,
  included = TRUE,
  inclusion_reason = "Test scope"
)

# One aftcast row for one method, as backtest_course_projection_methods()
# shapes it before capacity censoring: seasonal_last projecting 100 against an
# actual 100 in twice the seats. projection_policy_backtests() stamps a test's
# method and series on it.
projection_backtest_row <- tibble::tibble(
  market_id = "abq_ea_course_market", college = "AS",
  subject_course = "TEST 101", term_type = "fall",
  target_term = 202080L, target_term_label = "Fall 2020",
  method_id = "seasonal_last",
  method_label = unname(CEDAR_ENROLLMENT_PROJECTION_METHODS[["seasonal_last"]]),
  method_role = unname(CEDAR_ENROLLMENT_PROJECTION_METHOD_ROLES[["seasonal_last"]]),
  applicable = TRUE, applicability_reason = "test",
  projected_classlist_total = 100,
  first_day_retention_rate = 1, projected_first_day_equivalent = 100,
  actual_classlist_total = 100, actual_first_day = 100,
  actual_census = 100, actual_final_enrollment = 100,
  scheduled_capacity = 200
)

# Six summarised aftcasts of seasonal_last for TEST 101, Falls 2018 to 2023:
# 110 projected against 100 actual every year, never capacity constrained.
projection_summary_backtests <- local({
  projected <- rep(110, 6)
  actual <- rep(100, 6)
  error <- projected - actual
  tibble::tibble(
    market_id = "abq_ea_course_market", college = "AS", department = "TEST",
    subject_course = "TEST 101", term_type = "fall",
    target_term = seq(201880L, by = 100L, length.out = 6),
    method_id = "seasonal_last",
    method_label = unname(CEDAR_ENROLLMENT_PROJECTION_METHODS[["seasonal_last"]]),
    method_role = "observed_enrollment", applicable = TRUE,
    projected_classlist_total = projected, actual_classlist_total = actual,
    first_day_retention_rate = 1,
    projected_first_day_equivalent = projected, actual_first_day = actual,
    actual_census = actual,
    scheduled_capacity = 2 * actual, capacity_fill = 0.5,
    capacity_usable = TRUE, capacity_reached = FALSE,
    error = error, abs_error = abs(error),
    capacity_censored_abs_error = abs(error),
    pct_error = error / actual, abs_pct_error = abs(error / actual)
  )
})

# EC-11's SOCI 100 at Fall 2020 is taught on two campuses: ABQ in a full-term
# and a first-half session (107 + 28 on the first day, 200 seats) and EA
# (58 of 100). Pooled, the market reads 193 of 300; each campus keeps its own.
campus_history_scaffold <- tibble::tibble(
  market_id = "abq_ea_course_market", subject_course = "SOCI 100",
  projection_target_term = 202180L, history_term = 202080L,
  recency_rank = 1L
)

# The spine / floor / delta model: one designed scenario, TEST 201, read by the
# floor, delta and regime tests.
#   Springs 2022 and 2023 enrolled 20 and 24 (the spine for Spring 2024 is 24).
#   Falls 2021 to 2023 enrolled 8, 8, 12 in the course itself.
#   FEED 1 enrolled 10, 10, 20 students in those Falls; half of each Fall's
#   FEED 1 students took TEST 201 the following Spring, and a quarter of each
#   Fall's TEST 201 students took it again.
# Three readings of it:
#   $base                    30 seats in Spring 2023, nobody waiting.
#   $sequence                SEQ 1 added as the course taken just before: 8, 8
#                            and 4 students in those Falls, half of each of the
#                            first two taking TEST 201 the next Spring. Two of
#                            Fall 2023's four also took FEED 1.
#   $capacity_22_waitlist_3  22 seats in Spring 2023 and three students waiting.
spine_scenarios <- local({
  scenario <- function(spring_capacity = 30, waitlisted = 0L, sequence = FALSE) {
    springs <- projection_test_history(
      c(20, 24), terms = c(202210L, 202310L), course = "TEST 201"
    ) %>% dplyr::mutate(term_type = "spring")
    falls <- projection_test_history(
      c(8, 8, 12), terms = c(202180L, 202280L, 202380L), course = "TEST 201"
    )
    ids <- function(prefix, n) paste0(prefix, seq_len(n))
    roster <- function(term, course, students) {
      tibble::tibble(student_id = students, term = term, subject_course = course)
    }
    # BIG 1 is the market's large course: 100 students each Fall, of whom two
    # take TEST 201 next Spring. By count it out-feeds FEED 1 over the two pairs
    # (4 transitions against FEED 1's 10 would both have passed the old
    # threshold of 3); by lift it is nothing like a prerequisite (0.02 against
    # the market's 0.064, lift 0.3), where FEED 1's half is lift 7.9.
    enrollments <- dplyr::bind_rows(
      roster(202180L, "FEED 1", ids("f", 10)), roster(202180L, "TEST 201", ids("r", 4)),
      roster(202180L, "BIG 1", ids("b", 100)),
      roster(202210L, "TEST 201", c(ids("f", 5), "r1", ids("x", 12), "b1", "b2")),
      roster(202280L, "FEED 1", ids("g", 10)), roster(202280L, "TEST 201", ids("s", 4)),
      roster(202280L, "BIG 1", ids("c", 100)),
      roster(202310L, "TEST 201", c(ids("g", 5), "s1", ids("y", 16), "c1", "c2")),
      roster(202380L, "FEED 1", ids("h", 20)), roster(202380L, "TEST 201", ids("t", 12)),
      roster(202380L, "BIG 1", ids("d", 100)),
      if (sequence) dplyr::bind_rows(
        roster(202180L, "SEQ 1", ids("q", 8)), roster(202210L, "TEST 201", ids("q", 4)),
        roster(202280L, "SEQ 1", ids("p", 8)), roster(202310L, "TEST 201", ids("p", 4)),
        roster(202380L, "SEQ 1", ids("u", 4)), roster(202380L, "FEED 1", ids("u", 2))
      )
    )
    sections <- tibble::tibble(
      market_id = "abq_ea_course_market", college = "AS", department = "TEST",
      course_title = "Test Course", subject_course = "TEST 201",
      term = c(202210L, 202310L), term_type = "spring",
      scheduled_sections = 1L, scheduled_enrl = c(20, 24),
      scheduled_capacity = c(30, spring_capacity), n_delivery_components = 1L,
      n_campuses = 1L, capacity_per_section = c(30, spring_capacity)
    )
    waitlists <- tibble::tibble(
      market_id = "abq_ea_course_market", subject_course = "TEST 201",
      term = 202310L, waitlisted = as.integer(waitlisted)
    )
    list(
      enrollment_history = springs,
      preceding_term_history = dplyr::bind_rows(springs, falls),
      section_history = sections,
      waitlist_history = waitlists,
      students = list(
        course_enrollments = enrollments,
        target_students = enrollments %>% dplyr::filter(subject_course == "TEST 201"),
        student_terms = tibble::tibble(
          student_id = character(), term = integer(), major_code = character(),
          student_classification = character()
        )
      ),
      row = projection_test_row %>%
        dplyr::mutate(subject_course = "TEST 201", term_type = "spring", target_term = 202410L)
    )
  }
  list(
    base = scenario(),
    sequence = scenario(sequence = TRUE),
    capacity_22_waitlist_3 = scenario(spring_capacity = 22, waitlisted = 3L)
  )
})

# 40 students in the baseline roster, 10 of them Nursing: a 25% share. Every
# expected value in the scenario tests is derived from these two numbers and
# the published projection, so a changed expectation means the arithmetic moved.
scenario_test_composition <- tibble::tibble(
  market_id = "abq_course_market",
  subject_course = "MATH 1215Z",
  baseline_term = 202010L,
  major_code = c("NURS", "BIOL"),
  student_classification = "Sophomore",
  n_students = c(10L, 30L)
)

empty_projection_test_waitlists <- tibble::tibble(
  market_id = character(), subject_course = character(), term = integer(),
  waitlisted = integer()
)

empty_projection_test_components <- tibble::tibble(
  market_id = character(), campus = character(), college = character(),
  department = character(), subject_course = character(),
  part_term = character(), target_term = integer(),
  target_term_label = character(), scheduled_sections = integer(),
  scheduled_enrl = numeric(), scheduled_capacity = numeric(),
  capacity_share = numeric(), prior_comparable_term = integer(),
  prior_census_enrl = numeric(), prior_scheduled_capacity = numeric(),
  prior_census_fill = numeric()
)

# No delivery campus rows: these inputs test the pooled market alone.
empty_projection_test_delivery_sections <- tibble::tibble(
  campus = character(), college = character(), subject_course = character(),
  part_term = character(), term = integer(), scheduled_sections = integer(),
  scheduled_capacity = numeric()
)

empty_projection_test_delivery_first_day <- tibble::tibble(
  campus = character(), term = integer(), subject_course = character(),
  first_day_enrl = numeric(), first_day_basis = character()
)

# ── test-gen-ed-grads.R ─────────────────────────────────────────────────────────

# GG_IN1 and GG_IN2 both take a GG-taught gen ed course; GG_IN3 still takes none.
# Uses HIST 1160's slot in area 5 via a GG-owned section of a real catalog course
# so gen_ed_course_lookup() still matches it.
gg_students_own <- dplyr::bind_rows(
  cedar_registrations_gg,
  .gg_row("GG_IN1", 202110, "PHIL 1115", "LING"),
  .gg_row("GG_IN2", 202110, "PHIL 1115", "LING")
)

gg_credits_own <- dplyr::bind_rows(
  cedar_student_terms_gg,
  tibble::tibble(student_id = "GG_IN2", term = 202110L,
                 completed_unm_credits = 3,
                 cumulative_completed_unm_credits = 3,
                 timeline_valid = TRUE,
                 student_classification = "Freshman", enrolled = TRUE)
)

# ── test-gpa-timeline.R ─────────────────────────────────────────────────────────

# GP_S1 — three terms, all graded, whole record inside the window.
# GP_S2 — starts in the first term of the data, so left-truncated.
# GP_S9 — one term with an A beside W, CR and I: points for the A only.
# GP_S8 — a W only: no graded hours, no timeline row.
# Rows through the ST01 constructor (3 credits each, registered, ABQ).
gpa_students <- dplyr::bind_rows(
  .st_row("GP_S1", 202080L, "AAA 101", "RE", "A"),
  .st_row("GP_S1", 202080L, "BBB 101", "RE", "B"),
  .st_row("GP_S1", 202110L, "CCC 101", "RE", "C"),
  .st_row("GP_S1", 202180L, "DDD 101", "RE", "A"),
  .st_row("GP_S2", 202010L, "EEE 101", "RE", "B"),
  .st_row("GP_S2", 202110L, "FFF 101", "RE", "A"),
  .st_row("GP_S9", 202080L, "GGG 101", "RE", "A"),
  .st_row("GP_S9", 202080L, "HHH 101", "RE", "W"),
  .st_row("GP_S9", 202080L, "III 101", "RE", "CR"),
  .st_row("GP_S9", 202080L, "JJJ 101", "RE", "I"),
  .st_row("GP_S8", 202080L, "KKK 101", "RE", "W")
)

# GP_S1..GP_S9 as build_student_terms() reads them, settled through Fall 2021.
gpa_student_terms <- suppressMessages(build_student_terms(
  gpa_students, programs = NULL, degrees = NULL,
  edges = list(last_enrolled_complete = 202180L)
))

# ── test-headcount-comprehensive.R ──────────────────────────────────────────────

# test_dims with the fixtures' own college names: the fixtures' student_college
# values (ARTS, STEM, ...) are not the institution's, so colleges.csv is
# replaced by the codes the Headcount URL uses for them. Units are test_dims'.
headcount_fixture_dims <- local({
  dims <- test_dims
  dims$colleges <- tibble::tibble(
    college_code = c("AS", "SC", "SO", "ED", "NR", "AD"),
    college_name = c("ARTS", "STEM", "SOSC", "EDU", "NURS", "BUS"),
    source_names = ""
  )
  validate_cedar_dims(dims)
})

# ── test-pathway.R ──────────────────────────────────────────────────────────────

pathway_students <- tibble(
  student_id = c(
    "S001", "S001", "S001",
    "S002", "S002", "S002",
    "S003", "S003",
    "S004", "S004", "S004",
    "S005", "S005"
  ),
  term = c(
    202410L, 202480L, 202510L,
    202410L, 202480L, 202510L,
    202410L, 202480L,
    202410L, 202480L, 202510L,
    202480L, 202510L
  ),
  subject_course = c(
    "CHEM 1215", "BIOL 2310", "ENGL 1110",
    "CHEM 1215", "BIOL 2310", "ENGL 1110",
    "CHEM 1215", "BIOL 2310",
    "CHEM 1215", "BIOL 2310", "ENGL 1110",
    "BIOL 2310",  "ENGL 1110"
  ),
  course_title = c(
    "General Chemistry", "General Biology", "Composition",
    "General Chemistry", "General Biology", "Composition",
    "General Chemistry", "General Biology",
    "General Chemistry", "General Biology", "Composition",
    "General Biology",   "Composition"
  ),
  student_classification = c(
    "Freshman",  "Sophomore", "Junior",
    "Freshman",  "Sophomore", "Junior",
    "Freshman",  "Sophomore",
    "Freshman",  "Sophomore", "Junior",
    "Sophomore", "Junior"
  ),
  registration_status_code = rep("RE", 13),
  # All ABQ: the timing and pairs expectations in test-pathway.R are stated
  # per course, so a single campus keeps them one row each. The two-campus
  # behaviour is pinned separately at the end of that file.
  campus = rep("ABQ", 13)
)

pathway_population <- tibble(
  student_id       = c("S001", "S002", "S003", "S004", "S005"),
  population_label = "bio_majors"
)

ep_population <- tibble(
  student_id       = c("S001", "S002", "S003", "S004", "S005", "S006", "S007"),
  population_label = "bio_majors",
  outcome          = c("ongoing", "ongoing", "ongoing",
                       "chose_elsewhere", "chose_elsewhere",
                       "ongoing",    # S006: entered, but first_unit_term=202410 (no prior)
                       "ongoing"),   # S007: switched_in, still "entered" by outcome
  entry_status     = c("pre_major", "pre_major", "pre_major",
                       "pre_major", "pre_major",
                       "pre_major",
                       "switched_in"),
  first_unit_term  = c(202480L, 202480L, 202480L,
                       202480L, 202480L,
                       202410L,   # earliest data term — no prior term exists
                       202480L),
  last_unit_term   = c(202510L, 202510L, 202510L,
                       202480L, 202480L,
                       202510L,
                       202510L)
)

ep_students <- tibble(
  student_id = c(
    # 202410: prior term window for first_unit_term=202480 students
    "S001", "S002", "S003", "S004", "S007",  # CHEM 1215 (S007 switched_in, now included)
    "S002", "S003", "S004", "S005",          # HIST 101
    "S006",                                  # PHYS 100 (S006 excluded: no prior term)
    # 202480: event term itself — should NOT appear in results
    "S001", "S002", "S003", "S004", "S005",
    # 202510: post-event — should NOT appear in results
    "S001", "S002"
  ),
  term = c(
    202410L, 202410L, 202410L, 202410L, 202410L,
    202410L, 202410L, 202410L, 202410L,
    202410L,
    202480L, 202480L, 202480L, 202480L, 202480L,
    202510L, 202510L
  ),
  subject_course = c(
    "CHEM 1215", "CHEM 1215", "CHEM 1215", "CHEM 1215", "CHEM 1215",
    "HIST 101",  "HIST 101",  "HIST 101",  "HIST 101",
    "PHYS 100",
    "BIOL 2310", "BIOL 2310", "BIOL 2310", "BIOL 2310", "BIOL 2310",
    "BIOL 3100", "BIOL 3100"
  ),
  course_title = c(
    rep("General Chemistry", 5),
    rep("World History",     4),
    rep("Physics",           1),
    rep("General Biology",   5),
    rep("Cell Biology",      2)
  ),
  registration_status_code = rep("RE", 17),
  campus = rep("ABQ", 17)
)

# The S00x students' student-term rows as typed: 15 credits attempted and
# completed each term, and the classification each student carried that term,
# as pathway_students records it; the classification axis and the start filter
# read it from here, never from the course row.
pathway_term_rows <- tibble(
  student_id = c("S001", "S001", "S001",
                 "S002", "S002", "S002",
                 "S003", "S003",
                 "S004", "S004", "S004",
                 "S005", "S005"),
  term = c(202410L, 202480L, 202510L,
           202410L, 202480L, 202510L,
           202410L, 202480L,
           202410L, 202480L, 202510L,
           202480L, 202510L),
  attempted_unm_credits = rep(15, 13),
  completed_unm_credits = rep(15, 13),
  student_classification = c("Freshman", "Sophomore", "Junior",
                             "Freshman", "Sophomore", "Junior",
                             "Freshman", "Sophomore",
                             "Freshman", "Sophomore", "Junior",
                             "Sophomore", "Junior"),
  enrolled = TRUE
)

# Those rows with the position columns of cedar_student_terms. The table opens
# at 202410, so every student who starts there is left-truncated.
pathway_student_terms <- pathway_position_columns(pathway_term_rows)

# The same rows beside S000, one Fall earlier (202380): the table now opens
# before every S00x student's first term, and none of them is truncated.
pathway_student_terms_earlier_window <- pathway_position_columns(dplyr::bind_rows(
  pathway_term_rows,
  tibble(student_id = "S000", term = 202380L,
         attempted_unm_credits = 12, completed_unm_credits = 12)
))

# MC02 in designed_test_data.R supplies the two-campus rows; the population is
# every one of its students under one label.
mc_population <- tibble(student_id = unique(test_students_mc$student_id),
                        population_label = "MC test population")

# ── test-pathways-helpers.R ─────────────────────────────────────────────────────

# The population below is intermediate membership scaffolding, not authored raw
# enrollment data. MC02 supplies all course rows, including concurrent labs,
# repeat attempts and a student moving between delivery campuses.
grouped_path_population <- test_students_mc %>% distinct(student_id) %>%
  mutate(population_label = "All", relevant_until = NA_integer_)

cov_pop <- tibble::tibble(
  student_id = paste0("S", 1:6),
  # S1 starts at the data edge -> truncated. S2 ends at the edge -> censored.
  # S3 is both. S4/S5/S6 sit inside the window -> complete.
  first_unm_term   = c(202010L, 202080L, 202010L, 202080L, 202110L, 202080L),
  last_record_term = c(202310L, 202480L, 202480L, 202310L, 202310L, 202380L)
)

graded_students <- local({
  mk <- function(term, n, graded) tibble::tibble(
    term = rep(as.integer(term), n),
    final_grade = c(rep("A", graded), rep(NA_character_, n - graded))
  )
  dplyr::bind_rows(
    mk(202480, 100, 91),   # complete
    mk(202580, 100, 91),   # complete
    mk(202610, 100, 7),    # grades not posted yet
    mk(202680, 100, 0)     # in progress
  )
})

# ── test-pathways-integration.R ─────────────────────────────────────────────────

# The populations the pipeline tests run on, built by build_population() from
# the shared fixtures, and each one's class list inside its Pathways window.
hist_pop <- build_population(
  test_programs, test_degrees,
  opt = list(type = "preset", program_names = "History")
)

math_pop <- build_population(
  test_programs,
  opt = list(type = "preset", program_names = "Mathematics")
)

anth_pop <- build_population(
  test_programs,
  opt = list(type = "dept", dept_code = "ANTH")
)

hist_students <- apply_pathways_population_window(test_students, hist_pop)

math_students <- apply_pathways_population_window(test_students, math_pop)

# ── test-pipeline-relevant-until.R ──────────────────────────────────────────────

# Fixtures here are deliberately local: the relevant_until window turns on exact
# term spacing that the shared fixture does not provide. See AGENTS.md.
pipeline_students <- tibble(
  student_id = c(
    "STU_ONGOING", "STU_ONGOING", "STU_ONGOING",
    "STU_BOUNDED", "STU_BOUNDED", "STU_BOUNDED"
  ),
  term = c(
    202410L, 202480L, 202510L,
    202410L, 202480L, 202510L
  ),
  subject_course = c(
    "CHEM 1215", "BIOL 2310", "ENGL 1110",
    "CHEM 1215", "BIOL 2310", "ENGL 1110"
  ),
  course_title = c(
    "General Chemistry", "General Biology", "Composition",
    "General Chemistry", "General Biology", "Composition"
  ),
  student_classification   = rep("Freshman", 6),
  registration_status_code = rep("RE", 6),
  campus                   = rep("ABQ", 6)
)

pipeline_population <- tibble(
  student_id       = c("STU_ONGOING", "STU_BOUNDED"),
  population_label = "test",
  relevant_until   = c(NA_integer_, 202480L)
)

# ── test-population-course-pressure.R ───────────────────────────────────────────

hp2_edges <- cedar_data_edges(test_students_hp2)

hp2_attempts <- attempts_for(test_students_hp2, hp2_edges)

hp2_course_terms <- course_terms_for(test_students_hp2, test_sections_hp2, hp2_edges)

hp2_population <- suppressMessages(build_population(
  test_programs_hp2, opt = list(type = "preset", program_names = "Nursing")
))

# Which designed catalogs name each HP02 course.
hp2_plans <- tibble::tribble(
  ~catalog_id,        ~subject_course,
  "nursing-bsn-2026", "BIOL 1140",
  "nursing-bsn-2026", "CHEM 1215",
  "medlab-bs-2026",   "BIOL 1140",
  "medlab-bs-2026",   "NUTR 2110",
  "pophealth-bs-2026", "BIOL 1140"
)

# ── test-population.R ───────────────────────────────────────────────────────────

# Fixtures here are deliberately local: these tests turn on term spacing relative
# to min/max_data_term, which the shared fixture's stable terms cannot express.
# See the domain-data-vs-input-contract rule in AGENTS.md.
# S009 row at 202380 anchors min_data_term to a term before S003/S004 (202480),
# so those students are NOT at the data boundary and correctly get "direct"
# rather than "unclear". A separate test covers the unclear case.
population_programs <- tibble(
  student_id         = c("S001", "S002", "S003", "S004", "S005",
                         "S006", "S007", "S007", "S008", "S009"),
  term               = c(202510L, 202510L, 202480L, 202480L, 202510L,
                         202510L, 202510L, 202510L, 202510L, 202380L),
  student_campus     = rep("M", 10),
  student_college    = c("NU", "PO", "NU", "NU", "AS", "NU", "NU", "NU", "AS", "AS"),
  program_type       = c("Major", "Major", "Major", "Major", "Major",
                         "Second Major", "Major", "Major", "Major", "Major"),
  program_name       = c("Nursing", "Public Health", "Nursing", "Nursing",
                         "History", "Nursing", "Nursing", "Nursing", "English",
                         "English"),
  major_code         = c("NURS", "POHE", "FNRS", "FNRS",
                         "HIST", "NURS", "NURS", "FNRS", "ENGL", "ENGL"),
  dept_code          = c("NURS", "POHE", "NURS", "NURS",
                         "HIST", "NURS", "NURS", "NURS", "ENGL", "ENGL"),
  is_pre_major       = c(FALSE, FALSE, TRUE, TRUE,
                         FALSE, FALSE, FALSE, TRUE, FALSE, FALSE),
  # S002 and S007 are transfers; rest are native continuing students
  student_population = c("Continuing Student", "Transfer Student",
                         "Continuing Student", "Continuing Student",
                         "Continuing Student", "Continuing Student",
                         "Transfer Student", "Transfer Student",
                         "Continuing Student", "Continuing Student")
)

# Minimal degrees fixture: S001 graduated in term 202510 with a Nursing degree
population_degrees <- tibble(
  student_id   = "S001",
  term         = 202510L,
  degree       = "BSN",
  program_name = "Nursing",
  major        = "Nursing",
  major_code   = "NURS"
)

# ── test-registration-snapshots.R ───────────────────────────────────────────────

# IS01 and WL01 in one class list, keyed as the loader keys it. The rows are
# tabulated at the top of test-registration-snapshots.R.
snapshot_students <- attach_test_course_ids(dplyr::bind_rows(test_students_intersession, test_students_wlmkt), "students")

# ── test-seatfinder.R ───────────────────────────────────────────────────────────

seatfinder_topic_sections <- local({
  start_base <- test_sections_sf %>%
    filter(term == 202410, subject_course == "HIST 1110") %>%
    slice(1)
  end_base <- test_sections_sf %>%
    filter(term == 202510, subject_course == "HIST 1110") %>%
    slice(1)

  bind_rows(
    start_base %>% mutate(
      section_id = "TOPIC-S1", crn = "49101", section = "001",
      subject = "HNRS", course_number = "1120", subject_course = "HNRS 1120",
      course_title = "Sem: Legacy of Algebra", college = "HC", department = "HNRS",
      enrolled = 10L, total_enrl = 10L, capacity = 18L, available = 8L,
      gen_ed_area = 5L
    ),
    start_base %>% mutate(
      section_id = "TOPIC-S2", crn = "49102", section = "002",
      subject = "HNRS", course_number = "1120", subject_course = "HNRS 1120",
      course_title = "Sem: Legacy of Comedy", college = "HC", department = "HNRS",
      enrolled = 12L, total_enrl = 12L, capacity = 18L, available = 6L,
      gen_ed_area = 5L
    ),
    end_base %>% mutate(
      section_id = "TOPIC-E1", crn = "59101", section = "001",
      subject = "HNRS", course_number = "1120", subject_course = "HNRS 1120",
      course_title = "Sem: Legacy of Algebra", college = "HC", department = "HNRS",
      enrolled = 11L, total_enrl = 11L, capacity = 18L, available = 7L,
      gen_ed_area = 5L
    ),
    end_base %>% mutate(
      section_id = "TOPIC-E2", crn = "59102", section = "002",
      subject = "HNRS", course_number = "1120", subject_course = "HNRS 1120",
      course_title = "Sem: Legacy of Comedy", college = "HC", department = "HNRS",
      enrolled = 13L, total_enrl = 13L, capacity = 18L, available = 5L,
      gen_ed_area = 5L
    )
  )
})

seatfinder_gen_ed_sections <- local({
  sections <- test_sections_sf %>%
    mutate(gen_ed_area = case_when(
      subject_course %in% c("HIST 1110", "HIST 1120") ~ 5L,
      subject_course == "ANTH 1110" ~ 4L,
      TRUE ~ gen_ed_area
    ))

  likely_to_open <- sections %>%
    filter(section_id == "SF20002") %>%
    slice(1) %>%
    mutate(
      section_id = "SF-GE-LIKELY",
      crn = "59999",
      subject = "HIST",
      course_number = "1999",
      subject_course = "HIST 1999",
      section = "001",
      course_title = "Topics in Public History",
      college = "ARTS",
      department = "HIST",
      instructor_id = "INS001",
      instructor_name = "Morgan, Rachel",
      enrolled = 0L,
      total_enrl = 0L,
      capacity = 0L,
      available = 0L,
      status = "A",
      delivery_method = "ENH",
      level = "lower",
      gen_ed_area = 5L,
      comments = NA_character_
    )

  bind_rows(sections, likely_to_open)
})

# The five attempts every active section gets in the grade tests: A, B, D, F
# and a late drop, so each course reads 60% DFW.
seatfinder_grade_pattern <- tibble(
  .attempt = 1:5,
  registration_status_code = c("RE", "RE", "RE", "RE", "DW"),
  final_grade = c("A", "B", "D", "F", "W")
)

# The class list over the seat-finder sections, and its attempts as seatfinder()
# reads them (ADR-001 step 7): loaded and built as the transform builds them,
# to the test edges' graded edge.
seatfinder_grade_students <- seatfinder_students_for(test_sections_sf)

seatfinder_grade_attempts <- keyed_attempts(seatfinder_grade_students, edges = seatfinder_test_edges)

# ── test-shared-requirements.R ──────────────────────────────────────────────────

# Derived planning/reference scaffolding: these invented memberships exercise
# allocation against the existing demo roadmap. They are not UNM claims or new
# student/section domain rows.
planning_reference <- local({
  ref <- list(source_id = "page", pointer = "/body", anchor = "Designed policy")
  area <- function(id, label, minimum, method = "listed_course", ...) c(list(
    rule_id = paste0("example.", id), area = id, label = label, statement = label,
    role = "gen_ed_area", minimum = minimum, planning_method = method, source_refs = list(ref)), list(...))
  gen <- list(planning = list(preparation_rule_id = "example.prep",
    completed_courses_by_english_start = list(complete = list("ENGL 1120")), note = "Designed illustrative policy."),
    rules = list(
      area("A", "Writing and communication", 6, planning_parts = list(
        list(label = "Writing", minimum = 3, subject_courses = list("ENGL 1120")),
        list(label = "Communication", minimum = 3, subject_courses = list("COMM 1130")))),
      area("B", "Math", 3), area("C", "Science", 4, "related_science"),
      area("F", "Flexible", 6, "distinct_areas", planning_course_count = 2),
      list(rule_id = "example.prep", subject_courses = list("ENGL 1110", "ENGL 1110Y"))))
  list(bundle = list(catalog_year = test_degree_catalog$catalogs$catalog_year[1], profiles = list(
      list(catalog_id = "demo-biology-bs-2026", rule_set_ids = list("example")))),
    sets = list(example = gen), provenance = list(sources = list(page = list(catalog_url = "https://example.invalid/policy"))),
    memberships = data.frame(area = c("A", "B", "C", "C", "C", "C"),
      subject_course = c("ENGL 1120", "MATH 1512", "CHEM 1215", "CHEM 1215L", "PHYS 1230", "PHYS 1230L"),
      credits = c(3, 4, 3, 1, 3, 1)))
})

# ── test-stopout.R ──────────────────────────────────────────────────────────────

# Fixtures here are deliberately local: these are intermediate frames (a graded
# term, a pre-joined stopout group) that are one function's input contract
# rather than domain data. See the rule in AGENTS.md.
stopout_grade_rows <- tibble(
  student_id               = paste0("S", sprintf("%03d", 1:12)),
  term                     = rep(202510, 12),
  campus                   = rep("ABQ", 12),
  subject_course           = rep("BIOL 2310", 12),
  final_grade              = c("A", "F", "W", "D-", "C", "W", "I", "AUD", "RB", "RF", "W", ""),
  registration_status_code = c("RE", "RE", "RE", "RE", "RE", "DR", "RE", "RE", "RE", "RE", "DW", "DG")
)

# stopped_out is pre-joined by get_stopout() before the per-course loop;
# tests must supply it directly (derived from returned_next_term logic).
#   S001: pass, returned     → stopped_out = FALSE
#   S002: pass, did NOT return → stopped_out = TRUE
#   S003: dfw,  returned     → stopped_out = FALSE
#   S004: dfw,  did NOT return → stopped_out = TRUE
#   S005: dfw,  did NOT return → stopped_out = TRUE
#   S006: pass, returned     → stopped_out = FALSE
stopout_group <- tibble(
  student_id     = c("S001", "S002", "S003", "S004", "S005", "S006"),
  term           = rep(202510, 6),
  subject_course = rep("BIOL 2310", 6),
  outcome        = c("pass", "pass", "dfw", "dfw", "dfw", "pass"),
  stopped_out    = c(FALSE, TRUE, FALSE, TRUE, TRUE, FALSE)
)

# All rows at 202480 = the graded term; "return" rows at 202510
stopout_students <- tibble(
  student_id = c(
    # Cohort graded at 202480
    "C001", "C002", "C003", "C004", "C005", "C006",
    # Cohort returns at 202510 (C001, C002, C004 returned; C003/C005/C006 did not)
    "C001", "C002", "C004",
    # Baseline graded at 202480
    "B001", "B002", "B003", "B004", "B005",
    # Baseline returns at 202510 (B001, B002, B004 returned; B003/B005 did not)
    "B001", "B002", "B004"
  ),
  term = c(
    rep(202480L, 6),   # cohort graded
    rep(202510L, 3),   # cohort returns
    rep(202480L, 5),   # baseline graded
    rep(202510L, 3)    # baseline returns
  ),
  campus = rep("ABQ", 17),
  subject_course = c(
    rep("BIOL 2310", 6),
    rep("MATH 1220",  3),   # any course — just needed for the term lookup
    rep("BIOL 2310",  5),
    rep("CHEM 1215",  3)    # any course
  ),
  final_grade = c(
    "A",  "B",  "C",  "F",  "W",  "D",    # cohort BIOL grades
    NA,   NA,   NA,                         # return rows — no grade needed
    "A",  "B+", "W",  "F",  "C",           # baseline BIOL grades
    NA,   NA,   NA                          # return rows
  ),
  registration_status_code = rep("RE", 17)
)

stopout_population <- tibble(
  student_id       = c("C001", "C002", "C003", "C004", "C005", "C006"),
  population_label = "bio_majors"
)

# The student-term rows get_stopout() reads for these students: the 202480
# anchors, judged into Fall-to-Spring 202510. Hand-written to the same shape as
# cedar_student_terms because stopout_students is an intermediate frame,
# not a fixture the production builder can read.
stopout_terms <- local({
  returned <- c("C001", "C002", "C004", "B001", "B002", "B004")
  ids <- c(paste0("C00", 1:6), paste0("B00", 1:5))
  bind_rows(
    tibble(student_id = ids, term = 202480L, enrolled = TRUE,
           returned_next_regular_term = ids %in% returned, return_observable = TRUE),
    tibble(student_id = returned, term = 202510L, enrolled = TRUE,
           returned_next_regular_term = NA, return_observable = FALSE)
  )
})

# EC-12: a student contributes once per course/campus, before thresholds or tests.
roadblocks_population <- test_students_roadblocks %>%
  filter(grepl("^RB_P", student_id)) %>% distinct(student_id) %>%
  mutate(population_label = "Roadblocks fixture")

roadblocks_options <- list(subject_code = "ECON", min_n = 1L, min_dfw_n = 0L,
     graded_through = 202110L, observation_end_term = 202110L)

# ── test-summary-functions.R ────────────────────────────────────────────────────

# Build a minimal downstream signals data frame for testing
downstream_flows <- tibble::tribble(
  ~source_course, ~dest_course,   ~recent_avg,
  "MATH 1215",    "MATH 1430",    12.3,
  "MATH 1215",    "PHYS 1310",     8.1,
  "HIST 1110",    "HIST 327",      5.4,
  "HIST 1110",    "ANTH 2175",     3.2,
  "ANTH 1140",    "ANTH 2175",     9.0,
)

# ── test-transform-measures.R ───────────────────────────────────────────────────

# The fixtures' pulls are all within a fortnight of their terms' start, so no
# settled edge can be determined from them (cedar_report_edges() stops, as it
# should in production); the tests state the edge, as test-course-flows.R does.
fixture_edges <- local({
  terms <- sort(unique(test_students$term))
  modifyList(data_objects$cedar_edges, list(last_enrolled_complete = terms[length(terms) - 1L]))
})

# ── test-transform-status.R ─────────────────────────────────────────────────────

# Scaffolding: the ADR-002 mapping files a transform reads, as small frames.
# Only HIST courses have a subject row, and there are no program rows; a test
# that needs programs sets $programs in its own body.
scaffold_mapping_files <- list(
  colleges = data.frame(college_code = c("AS", "FA", "PH"),
                        college_name = c("Arts and Sciences", "Fine Arts", "Pharmacy"),
                        source_names = c("College of Arts & Sciences", "College of Fine Arts", "")),
  units    = data.frame(unit_code = c("HIST", "ANTH", "PHRM", "ARTS"),
                        unit_name = c("History", "Anthropology", "Pharmacy", "Art Studio"),
                        college_code = c("AS", "AS", "PH", "FA"), kind = "department", notes = ""),
  subjects = data.frame(subject_code = "HIST", in_college = "", in_level = "", unit_code = "HIST",
                        college_code = "", status = "confirmed", evidence = "", notes = ""),
  programs = as.data.frame(stats::setNames(
    rep(list(character()), length(CEDAR_MAPPING_FILE_SPECS$programs)),
    CEDAR_MAPPING_FILE_SPECS$programs)),
  code_history = as.data.frame(stats::setNames(
    rep(list(character()), length(CEDAR_MAPPING_FILE_SPECS$code_history)),
    CEDAR_MAPPING_FILE_SPECS$code_history)),
  settings = data.frame(setting = character(), value = character())
)

# The same files as the loader reads them: the transform stores keys, and
# attach_unit() (R/branches/dims.R) resolves them at every start.
scaffold_dims <- build_cedar_dims(scaffold_mapping_files)
