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

# ── test-scope-bar.R ────────────────────────────────────────────────────────────

# Scaffolding: unit_mapping_rows() output for one department with one subject,
# one program and one pre-major, the shape unit_codes_scope() reads.
scope_unit_rows <- list(
  units = tibble::tibble(unit_code = "HIST", unit_name = "History", college_code = "AS",
                         college_name = "Arts and Sciences"),
  subjects = tibble::tibble(unit_code = "HIST", subject_code = "HIST", in_college = NA_character_,
                            in_level = NA_character_),
  programs = tibble::tibble(unit_code = "HIST", program_code = c("HIST", "FHIS"),
                            program_name = c("History", "Pre-History"), is_pre_major = c(FALSE, TRUE),
                            leads_to = c(NA, "HIST"), in_college = NA_character_)
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

# code_history.csv program rows, one or a pair per fault the validator names,
# over programs.csv rows OLD, NEW, ALT, P and Q (mapping_program_row, each
# named for its code).
mapping_program_history <- list(
  programs = do.call(rbind, lapply(c("OLD", "NEW", "ALT", "P", "Q"), function(code)
    transform(mapping_program_row, program_code = code, program_name = code))),
  code_history = tibble::tribble(
    ~kind,     ~from_code, ~to_code, ~effective_term, ~scope,           ~basis,    ~status,
    "program", "GONE",     "NEW",    "202380",        "",               "decided", "confirmed",  # GONE is not in programs.csv
    "program", "OLD",      "NEW",    "202380",        "",               "decided", "confirmed",  # a confirmed split...
    "program", "OLD",      "ALT",    "202380",        "",               "decided", "confirmed",  # ...into two codes
    "program", "P",        "Q",      "202380",        "",               "decided", "confirmed",  # a cycle...
    "program", "Q",        "P",      "202380",        "",               "decided", "confirmed",  # ...of two
    "program", "NEW",      "P",      "202380",        "graduate only",  "decided", "confirmed"   # partial: not followed, so no split
  ) %>%
    mutate(evidence = "", notes = "") %>%
    as.data.frame()
)

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

# A program renamed in code_history.csv, stated on the shared fixture's
# STU-MGMT-CHG1 (Business Analytics, BUAN-BBA, in Spring 2020; Business
# Management, BUMG-BBA, in Fall 2020): read as one program renamed from Fall
# 2020. The real files rename no fixture code, so without this table the two
# are two programs. Read by test-population.R, test-pathways-helpers.R and
# test-pathways-integration.R.
program_rename_successions <- data.frame(
  from_code = "BUAN-BBA", to_code = "BUMG-BBA", effective_term = 202080L,
  stringsAsFactors = FALSE)

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

# The audit fixture plus two students whose rows give a choice of attempt:
#   SEQ_R1 passed SEQ 101 in 202010, passed SEQ 201 in 202080 and passed
#     SEQ 101 again in 202110: treatment, by the first pass.
#   SEQ_D1 sat SEQ 201 on two campuses in 202080, an A on ABQ (listed first)
#     and an F on EA, with no SEQ 101: control, and one outcome, the DFW.
# Read with campuses ABQ and EA:
#   Treatment: SEQ_T1 (Y dfw), SEQ_T2 (Y dfw), SEQ_R1 (Y pass)
#   Control:   SEQ_C1, SEQ_C2, SEQ_XC (pass), SEQ_D1 (dfw)
.sequence_repeat_fixture <- local({
  fixture <- .sequence_audit_fixture
  fixture$students <- dplyr::bind_rows(
    fixture$students,
    .mc_row("SEQ_R1", 202010, "SEQ 101", "ABQ", "SEQ", "A", "SEQ_I1"),
    .mc_row("SEQ_R1", 202080, "SEQ 201", "ABQ", "SEQ", "B", "SEQ_I1"),
    .mc_row("SEQ_R1", 202110, "SEQ 101", "ABQ", "SEQ", "A", "SEQ_I1"),
    .mc_row("SEQ_D1", 202080, "SEQ 201", "ABQ", "SEQ", "A", "SEQ_I1"),
    .mc_row("SEQ_D1", 202080, "SEQ 201", "EA", "SEQ", "F", "SEQ_I2")
  )
  extra <- c("SEQ_R1", "SEQ_D1")
  fixture$programs <- dplyr::bind_rows(fixture$programs, lapply(seq_along(extra), function(i) {
    fixture$programs %>% dplyr::slice(1L) %>%
      dplyr::mutate(student_id = extra[[i]], program_id = paste0("SEQ-PROG-R", i))
  }))
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

# ── test-course-pair-dfw.R ──────────────────────────────────────────────────────

# PD01: CHEM 121 on ABQ in three falls (202080, 202180, 202280), the same
# fourteen seats each fall (student ids carry the term):
#   low band (entering GPA 2.0), L1-L4: L1 and L2 also take ENGL 220; L1 and
#     L3 DFW, so CHEM 121's DFW is 1 of 2 with ENGL 220 and 1 of 2 without.
#   mid band (3.2), M1-M9: M1-M3 also take MATH 162 and M1, M2 DFW; of M4-M8,
#     M4 DFWs. M9's timeline is not valid, so M9 is left out.
#   F1, a first-term student (no entering GPA), takes MATH 162 too and DFWs.
# Every seat also takes the lab, CHEM 121L, one family with CHEM 121.
# Per fall, MATH 162: 2 of 3 DFW against 3 x 1/5 = 0.6 expected.
pd01 <- local({
  falls <- c(202080L, 202180L, 202280L)
  seats <- tibble::tribble(
    ~seat, ~gpa, ~valid, ~dfw,  ~others,
    "L1",  2.0,  TRUE,   TRUE,  "ENGL 220",
    "L2",  2.0,  TRUE,   FALSE, "ENGL 220",
    "L3",  2.0,  TRUE,   TRUE,  NA,
    "L4",  2.0,  TRUE,   FALSE, NA,
    "M1",  3.2,  TRUE,   TRUE,  "MATH 162",
    "M2",  3.2,  TRUE,   TRUE,  "MATH 162",
    "M3",  3.2,  TRUE,   FALSE, "MATH 162",
    "M4",  3.2,  TRUE,   TRUE,  NA,
    "M5",  3.2,  TRUE,   FALSE, NA,
    "M6",  3.2,  TRUE,   FALSE, NA,
    "M7",  3.2,  TRUE,   FALSE, NA,
    "M8",  3.2,  TRUE,   FALSE, NA,
    "M9",  3.2,  FALSE,  FALSE, NA,
    "F1",  NA,   TRUE,   TRUE,  "MATH 162"
  )
  rows <- tidyr::crossing(term = falls, seats) %>%
    dplyr::mutate(student_id = paste0("PD01-", seat, "-", term))
  attempt <- function(r, course, outcome) tibble::tibble(
    student_id = r$student_id, term = r$term, campus = "ABQ", subject_course = course, outcome = outcome)
  attempts <- dplyr::bind_rows(
    attempt(rows, "CHEM 121", ifelse(rows$dfw, "dfw", "pass")),
    attempt(rows, "CHEM 121L", "pass"),
    attempt(dplyr::filter(rows, !is.na(others)), dplyr::filter(rows, !is.na(others))$others, "pass")
  )
  # 30 earlier graded hours at the seat's GPA, then 12 this term; a first-term
  # student has only this term's.
  prior_hours <- ifelse(is.na(rows$gpa), 0, 30)
  student_terms <- tibble::tibble(
    student_id = rows$student_id, term = rows$term,
    quality_points = 36, graded_hours = 12,
    cumulative_quality_points = 36 + prior_hours * dplyr::coalesce(rows$gpa, 0),
    cumulative_graded_hours = 12 + prior_hours,
    timeline_valid = rows$valid
  )
  list(attempts = attempts, student_terms = student_terms)
})

# ── test-course-band-dfw.R ──────────────────────────────────────────────────────

# BD01: GATE 101 and OTHR 200 on ABQ in three falls (202080, 202180, 202280),
# the same seats each fall (student ids carry the term). Every seat but EA1
# takes both.
#   low band (entering GPA 2.0), L01-L10: L01-L06 DFW GATE 101; L01, L02 DFW
#     OTHR 200. GATE 101: 60% against 20% in their other course, excess 40.
#   higher band (3.2), H01-H10: H01, H02 DFW GATE 101; H01 DFWs OTHR 200.
#     GATE 101: 20% against 10%, excess 10.
# So GATE 101's gap is +30 points and OTHR 200's is -30 (its excesses are -40
# and -10): over three falls, 30 attempts a side,
#   se = 100 * sqrt((.6*.4 + .2*.8 + .2*.8 + .1*.9) / 30) = 100 * sqrt(.65 / 30).
# Left out of the entering-GPA reading: F1-F3, first-term students (no
# entering GPA), and V1, whose timeline is not valid. F1 (high-school GPA 2.5)
# DFWs GATE 101 and passes OTHR 200; F2 (3.9) passes both; F3 has no
# high-school GPA on file. EA1 (2.0) takes GATE 101 on EA and nothing else: a
# course of one, banded and never read.
bd01 <- local({
  falls <- c(202080L, 202180L, 202280L)
  seats <- tibble::tibble(
    seat = c(sprintf("L%02d", 1:10), sprintf("H%02d", 1:10), "F1", "F2", "F3", "V1", "EA1"),
    gpa = c(rep(2.0, 10), rep(3.2, 10), NA, NA, NA, 2.0, 2.0),
    valid = c(rep(TRUE, 23), FALSE, TRUE),
    gate_dfw = c(rep(TRUE, 6), rep(FALSE, 4), TRUE, TRUE, rep(FALSE, 8), TRUE, FALSE, FALSE, TRUE, TRUE),
    othr_dfw = c(TRUE, TRUE, rep(FALSE, 8), TRUE, rep(FALSE, 9), FALSE, FALSE, FALSE, TRUE, FALSE)
  )
  rows <- tidyr::crossing(term = falls, seats) %>%
    dplyr::mutate(student_id = paste0("BD01-", seat, "-", term))
  attempts <- dplyr::bind_rows(
    tibble::tibble(student_id = rows$student_id, term = rows$term,
                   campus = ifelse(rows$seat == "EA1", "EA", "ABQ"), subject_course = "GATE 101",
                   outcome = ifelse(rows$gate_dfw, "dfw", "pass")),
    tibble::tibble(student_id = rows$student_id, term = rows$term, campus = "ABQ", subject_course = "OTHR 200",
                   outcome = ifelse(rows$othr_dfw, "dfw", "pass")) %>%
      dplyr::filter(!grepl("-EA1-", student_id))
  )
  prior_hours <- ifelse(is.na(rows$gpa), 0, 30)
  student_terms <- tibble::tibble(
    student_id = rows$student_id, term = rows$term,
    quality_points = 36, graded_hours = 12,
    cumulative_quality_points = 36 + prior_hours * dplyr::coalesce(rows$gpa, 0),
    cumulative_graded_hours = 12 + prior_hours,
    timeline_valid = rows$valid
  )
  first_term <- rows[rows$seat %in% c("F1", "F2"), ]
  applicants <- tibble::tibble(student_id = first_term$student_id,
                               high_school_cum_gpa = ifelse(first_term$seat == "F1", 2.5, 3.9))
  list(attempts = attempts, student_terms = student_terms, applicants = applicants,
       edges = list(last_graded = 202280L, last_enrolled_complete = 202280L))
})

# BD02: BD01 as a page about students reads it. Every BD01 seat is an
# undergraduate whose home campus is ABQ (EA1 too: its GATE 101 is the one
# taught on EA), and twenty more seats take GATE 101 and OTHR 200 on ABQ in
# the same three falls:
#   G01-G10, graduate students, home campus ABQ, entering GPA 2.0: all pass
#     GATE 101, all DFW OTHR 200.
#   T01-T10, undergraduates whose home campus is EA, entering GPA 3.2: all
#     DFW GATE 101, all pass OTHR 200.
# and S1, the one student with two terms (home campus ABQ in both): an
#   undergraduate in 202080, in a first term (no entering GPA, so in no
#   band), who passes OTHR 200; a graduate student in 202180 (entering GPA
#   3.0), who passes SEMR 600, a course nobody else takes. A level is the
#   term's: the undergraduates' reading never holds SEMR 600.
# Undergraduates of home campus ABQ are BD01's seats: GATE 101 on ABQ is +30
#   points, harder, and EA's GATE 101 is read (EA1's home campus is ABQ). 61
#   student-terms are outside that scope: the 60 above and S1's 202180.
# Every level, home campus ABQ: GATE 101's low band is 60 attempts at 30%
#   against 60% in their other course (excess -30) and its other students'
#   excess is 10: gap -40, easier.
# Undergraduates of every home campus: GATE 101's other students are 60
#   attempts at 60% against 5% (excess 55): gap -15, inside chance
#   (se = 100 * sqrt(.6*.4/30 + .2*.8/30 + .6*.4/60 + .05*.95/60) = 13.5).
# No seat is a law student, and no graduate student-term is a first term.
bd02 <- local({
  more <- tidyr::crossing(
    term = c(202080L, 202180L, 202280L),
    tibble::tibble(
      seat = c(sprintf("G%02d", 1:10), sprintf("T%02d", 1:10)),
      gpa = rep(c(2.0, 3.2), each = 10),
      student_level = rep(c("GR", "UG"), each = 10),
      student_campus = rep(c("ABQ", "EA"), each = 10),
      gate_dfw = rep(c(FALSE, TRUE), each = 10),
      othr_dfw = rep(c(TRUE, FALSE), each = 10)
    )
  ) %>%
    dplyr::mutate(student_id = paste0("BD02-", seat, "-", term))
  attempts <- dplyr::bind_rows(
    bd01$attempts,
    tibble::tibble(student_id = more$student_id, term = more$term, campus = "ABQ", subject_course = "GATE 101",
                   outcome = ifelse(more$gate_dfw, "dfw", "pass")),
    tibble::tibble(student_id = more$student_id, term = more$term, campus = "ABQ", subject_course = "OTHR 200",
                   outcome = ifelse(more$othr_dfw, "dfw", "pass")),
    tibble::tibble(student_id = "BD02-S1", term = c(202080L, 202180L), campus = "ABQ",
                   subject_course = c("OTHR 200", "SEMR 600"), outcome = "pass")
  )
  student_terms <- dplyr::bind_rows(
    bd01$student_terms %>% dplyr::mutate(enrolled = TRUE, student_level = "UG", student_campus = "ABQ"),
    tibble::tibble(student_id = more$student_id, term = more$term, quality_points = 36, graded_hours = 12,
                   cumulative_quality_points = 36 + 30 * more$gpa, cumulative_graded_hours = 42,
                   timeline_valid = TRUE, enrolled = TRUE,
                   student_level = more$student_level, student_campus = more$student_campus),
    tibble::tibble(student_id = "BD02-S1", term = c(202080L, 202180L), quality_points = 36, graded_hours = 12,
                   cumulative_quality_points = c(36, 72), cumulative_graded_hours = c(12, 24),
                   timeline_valid = TRUE, enrolled = TRUE, student_level = c("UG", "GR"), student_campus = "ABQ")
  )
  list(attempts = attempts, student_terms = student_terms, applicants = bd01$applicants, edges = bd01$edges)
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

# The same attempts with two rows that are not classified attempts, for the
# count of a member's courses in 202010:
#   FAIL's HIST 101 is restated as an ungraded registration (no outcome): FAIL
#     holds a row in the course and is neither its taker nor its non-taker,
#     which leaves BACK the one taker against DROP, GONE, GRAD and REP.
#   BACK's HIST 101 is also listed on a second campus, ungraded, under another
#     instructor (RP_I9), ahead of the graded row: one member-course, whose
#     instructor is the classified attempt's (RP_I1).
ss_attempts_unclassified <- bind_rows(
  ss_attempts2 %>%
    filter(student_id == "RP_BACK", term == 202010L, subject_course == "HIST 101") %>%
    mutate(campus = "EA", outcome = NA_character_, instructor_id = "RP_I9", instructor_name = "RP_I9"),
  ss_attempts2 %>%
    mutate(outcome = if_else(student_id == "RP_FAIL" & term == 202010L & subject_course == "HIST 101",
                             NA_character_, outcome))
)

ss_student_terms2 <- test_student_terms_rp %>%
  mutate(sem_gpa = case_when(
    term == 202080L & student_id == "RP_BACK" ~ 3.0,
    term == 202080L & student_id == "RP_FAIL" ~ 2.0,
    term == 202080L & student_id == "RP_REP" ~ 4.0,
    TRUE ~ sem_gpa
  ))

ss_ids <- unique(test_student_terms_rp$student_id)

ss_app <- tibble::tibble(student_id = ss_ids, high_school_cum_gpa = 3.0)

# The same applicants with ACT scores, for the alike check. HIST 101's two
# takers in 202010 (BACK, FAIL) average 19; its non-takers with a score
# (DROP, GONE, GRAD; REP has none) average 24, variance 8/3.
ss_app_act <- ss_app %>%
  mutate(unm_act_combined_score = c(RP_BACK = 18, RP_DROP = 22, RP_EDROP = 30, RP_FAIL = 20,
                                    RP_GONE = 24, RP_GRAD = 26, RP_REP = NA)[student_id])
# The takers scoring as their non-takers do: 24 each.
ss_app_act_alike <- ss_app_act %>%
  mutate(unm_act_combined_score = if_else(student_id %in% c("RP_BACK", "RP_FAIL"), 24, unm_act_combined_score))

# Pell eligibility and first-generation status for 202010, in the declarations
# table's shape. HIST 101's takers split: BACK is Pell-eligible with GONE (who
# did not return) as the only non-taker like that; FAIL is not, with DROP,
# GRAD and REP. REP has two rows that term, one of them recording nothing.
ss_aid <- tibble::tibble(
  student_id    = c("RP_BACK", "RP_FAIL", "RP_GONE", "RP_DROP", "RP_GRAD", "RP_REP", "RP_REP"),
  term          = 202010L,
  pell_eligible = c(TRUE, FALSE, TRUE, FALSE, FALSE, FALSE, NA),
  first_gen     = c(FALSE, FALSE, FALSE, FALSE, FALSE, FALSE, NA)
)

# The same declarations with a term whose rows disagree and one that records
# nothing: REP's blank Pell row restated as eligible (a yes beside a no is a
# yes), and DROP's only row as blank (no label). First-generation status is
# as it was: REP's no beside a blank is a no.
ss_aid_mixed <- ss_aid %>%
  mutate(pell_eligible = case_when(student_id == "RP_REP" & is.na(pell_eligible) ~ TRUE,
                                   student_id == "RP_DROP" ~ NA,
                                   TRUE ~ pell_eligible))

# Per-term gaps in by_term's shape, four falls (2019-2022) with a spring and a
# summer between: GAP 100's return gap climbs 0, 2, 4, 6 (+2 a year) with
# standard error 0.5; GAP 200's falls 6, 4, 2, 0; GAP 300's zigzags 0, 6, 0, 6
# with standard error 0.1, a line chance alone calls rising and its scatter
# does not. The DFW gap is the return gap's; the GPA gap is NA but in two
# terms, too few for a line. A spring term (202110) sits in each course.
ss_gap_series <- local({
  terms <- c(201980L, 202080L, 202110L, 202160L, 202180L, 202280L)
  course_rows <- function(course, falls, se) {
    gap <- c(falls[1:2], 50, 50, falls[3:4])
    tibble::tibble(course = course, term = terms,
                   return_gap = gap, return_gap_se = se,
                   other_dfw_gap = gap, other_dfw_gap_se = se,
                   next_gpa_gap = c(0.1, 0.2, NA, NA, NA, NA), next_gpa_gap_se = 0.05)
  }
  bind_rows(course_rows("GAP 100", c(0, 2, 4, 6), 0.5),
            course_rows("GAP 200", c(6, 4, 2, 0), 0.5),
            course_rows("GAP 300", c(0, 6, 0, 6), 0.1))
})

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
  ids_orphan  = test_ids_orphan,
  ids_ahead   = test_ids_ahead
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

# ── test-degree-compiler.R ─────────────────────────────────────────────────────

# The designed Biology B.S. interpretation the degree compiler reads: every rule
# the demo catalog fixture states for the program and its concentration, cited
# to its source block (ids are content hashes of institution/demo/
# catalog-source-fixture.json). BIOL 200 against the lab pair is left
# unresolved, as a reader would.
compiler_biology_proposal <- local({
  compiler_rule <- function(id, parent, kind, label, block, quote, entity = "programs:biology", phase = "degree",
                            minimum = NULL, unit = "none", value = "", refs = list(), comparison = "none") {
    list(id = id, parent_id = parent, entity_id = entity, phase = phase, kind = kind, label = label,
         minimum = minimum, maximum = NULL, unit = unit, comparison = comparison, value = value, minimum_grade = "",
         course_refs = refs, program_ref = "", timing = "not_applicable",
         citations = list(list(block_id = block, quote = quote)))
  }
  compiler_cover <- function(block, disposition, nodes = character(), why = "Designed interpretation")
    list(block_id = block, disposition = disposition, node_ids = as.list(nodes), explanation = why)
  list(schema_version = "1.0.0", questions = list(),
    nodes = list(
      compiler_rule("major", "", "all", "Complete the Biology major", "b-7dcbcb97cd7ee63e0e5368a9", "Complete all of the following"),
      compiler_rule("start", "major", "choose_n", "Biology I with its lab, or Combined Biology", "b-d393fa921001d2c885dde016",
                    "Complete at least 1 of the following", minimum = 1, unit = "courses", comparison = "at_least"),
      compiler_rule("pair", "start", "all", "Biology I and its lab", "b-944c096cfb5151e26839fa49", "Complete the following"),
      compiler_rule("bio1", "pair", "course", "BIOL2110 - Biology I (3)", "b-f22d0c38b4ae90977f7c5b99", "BIOL2110 - Biology I (3)", refs = list("courses:course-one")),
      compiler_rule("lab", "pair", "course", "BIOL2110L - Biology I Lab (1)", "b-9e466020241662f635910b1d", "BIOL2110L - Biology I Lab (1)", refs = list("courses:course-lab")),
      compiler_rule("combined", "start", "course", "BIOL200 - Combined Biology (4)", "b-12cf2b1d2a007e540e5f8c49", "BIOL200 - Combined Biology (4)", refs = list("courses:course-two")),
      compiler_rule("combined-scope", "start", "unresolved", "Does Combined Biology replace both Biology I and its lab?",
                    "b-12cf2b1d2a007e540e5f8c49", "Combined Biology (4)", value = "The list offers BIOL200 beside the pair without saying it covers the lab"),
      compiler_rule("admit-upper", "", "course_pool", "At least two upper-level courses", "b-c83ed948337af5e15eada1e2",
                    "At least two upper-level courses", phase = "admission", minimum = 2, unit = "courses", value = "upper-level courses", comparison = "at_least"),
      compiler_rule("admit-permission", "", "permission", "Department permission", "b-c83ed948337af5e15eada1e2",
                    "department permission", phase = "admission", value = "department permission"),
      compiler_rule("degree-total", "", "credits", "At least 120 degree credits", "b-70866de17388f7d2b5a24491", "120",
                    minimum = 120, unit = "credits", comparison = "at_least"),
      compiler_rule("cellular", "", "all", "Cellular Biology concentration", "b-d0c4bcb6e7a2da072eaa9347", "Complete the following", entity = "specializations:cellular"),
      compiler_rule("cellular-combined", "cellular", "course", "BIOL200 - Combined Biology (4)", "b-5bd56eb0159be765a0e60837",
                    "BIOL200 - Combined Biology (4)", entity = "specializations:cellular", refs = list("courses:course-two"))),
    coverage = list(
      compiler_cover("b-7dcbcb97cd7ee63e0e5368a9", "requirements", "major"),
      compiler_cover("b-d393fa921001d2c885dde016", "requirements", "start"),
      compiler_cover("b-944c096cfb5151e26839fa49", "requirements", "pair"),
      compiler_cover("b-f22d0c38b4ae90977f7c5b99", "requirements", "bio1"),
      compiler_cover("b-9e466020241662f635910b1d", "requirements", "lab"),
      compiler_cover("b-12cf2b1d2a007e540e5f8c49", "unresolved", c("combined", "combined-scope")),
      compiler_cover("b-c83ed948337af5e15eada1e2", "requirements", c("admit-upper", "admit-permission")),
      compiler_cover("b-5450e022abf0d057ec85a9ce", "information"),
      compiler_cover("b-f5c805f0f7ad0f3f03b55b63", "information"),
      compiler_cover("b-cd9154d612042d822e5c8bc2", "information"),
      compiler_cover("b-f94d4b00cf84a04d3bcca5d1", "information"),
      compiler_cover("b-70866de17388f7d2b5a24491", "requirements", "degree-total"),
      compiler_cover("b-d0c4bcb6e7a2da072eaa9347", "requirements", "cellular"),
      compiler_cover("b-5bd56eb0159be765a0e60837", "requirements", "cellular-combined"),
      compiler_cover("b-5d7913605fd3394402fa1faf", "information")))
})

# The draft board's catalog entry: the designed Biology program, under its own
# id so it never collides with the authored demo board.
compiler_biology_catalog_row <- data.frame(catalog_id = "demo-biology-draft", program_name = "Biology",
  degree_label = "Biology B.S. (draft)", degree_code = "BS", program_codes = "BS-BIOL-AS", catalog_year = "2026-2027",
  source_url = "https://catalog.example.invalid/#/programs/biology", retrieved_on = "2026-10-17", coverage = "excerpt",
  notes = "Draft compiled from the designed reading")

# The math routes of a program with no math course of its own, as
# degree_general_math_routes() reads them from the demo boards (History B.A.):
# each start's preparation only, so a student at intermediate algebra takes
# MATH 1215 and every other start has nothing before the Gen Ed math card.
compiler_general_math_routes <- data.frame(catalog_id = "demo-history-ba-2026",
  start_id = c("calculus", "precalculus", "algebra", "intermediate"),
  label = c("Calculus-ready", "Pre-calculus-ready",
            "College-algebra-ready", "Start with Intermediate Algebra (MATH 1215)"),
  node_ids = c("", "", "", "math1215"))

# A reading that names no Gen Ed or remainder pools
# (degree_reading_gen_ed_pools() of a reading without gen_ed_pools).
compiler_no_gen_ed_pools <- data.frame(rule_id = character(), area = character(), credits = numeric())

# ── test-degree-drafts.R, test-degree-explorer.R ──────────────────────────────

# The page's board status (publish_degree_drafts()$status) for the demo
# institution's two boards: Biology compiled from its catalog reading and not
# yet signed off, History authored by hand.
degree_board_status_demo <- data.frame(catalog_id = c("demo-biology-bs-2026", "demo-history-ba-2026"),
  source = c("compiled", "authored"), review = c("draft", NA), note = c("Its catalog reading is not signed off in Catalog Review.", ""))

# ── test-catalog-questions.R ──────────────────────────────────────────────────

# degree_reading_questions.csv as the compile script writes it, for two
# designed programs (read_degree_drafts()$questions):
#   Biology B.S.  rule:combined-scope  settled by the catalog
#                 question:1           not sorted (its passage runs past 300
#                                      characters, so the document cuts it)
#   History B.A.  passage:b-hist-pool  settled by CEDAR's reading; no board
# Counts: any 3, the catalog 1, CEDAR's copy 0, CEDAR's reading 1, not sorted 1.
# Programs alphabetical: Bachelor of Arts in History, then Bachelor of Science in Biology.
catalog_questions_designed <- data.frame(
  reading = c(rep("catalog_interpretations/2026-2027/biology.v1.json", 2), "catalog_interpretations/2026-2027/history.v1.json"),
  reading_file_sha256 = c(rep(strrep("a", 64), 2), strrep("b", 64)),
  program_id = c("biology", "biology", "history"),
  program_title = c("Bachelor of Science in Biology", "Bachelor of Science in Biology", "Bachelor of Arts in History"),
  catalog_url = c(rep("https://catalog.example.invalid/#/programs/biology", 2), "https://catalog.example.invalid/#/programs/history"),
  catalog_id = c("demo-biology-draft", "demo-biology-draft", ""),
  item = c("rule:combined-scope", "question:1", "passage:b-hist-pool"),
  kind = c("rule", "question", "passage"),
  label = c("Does Combined Biology replace both Biology I and its lab?", "Interpretation question", "Unresolved source treatment"),
  question = c("The list offers BIOL200 beside the pair without saying it covers the lab.",
               "Is department permission required for admission, or only advised?",
               "The credit wording restates the elective requirement; read as the elective pool."),
  block_id = c("b-12cf2b1d2a007e540e5f8c49", "b-c83ed948337af5e15eada1e2", "b-hist-pool"),
  section = c("Program requirements", "Admission", "Major requirements"),
  passage = c("BIOL200 - Combined Biology (4)",
              paste("Admission to the major requires at least two upper-level courses and department permission.",
                    "Students should meet with an advisor before applying, and the department reviews each application",
                    "in the term after it is received. Students who are not admitted may apply again the following term",
                    "after completing additional coursework; the department may ask for an interview."),
              "Earned at least 12 credits from HIST 300 - 499."),
  settled_by = c("catalog", "", "reading"))

# One degree total the catalog states two ways, as the compile script adds it
# from the catalog scan (catalog_total_conflict_questions()): it names no
# reading, so no reading file can make it stale (test-degree-drafts.R).
catalog_total_question_designed <- data.frame(reading = "", reading_file_sha256 = "", program_id = "biology",
  program_title = "Bachelor of Science in Biology", catalog_url = "https://catalog.example.invalid/#/programs/biology",
  catalog_id = "", item = "total", kind = "total", label = "Degree total",
  question = "The catalog gives this degree two totals. Which is right?", block_id = "", section = "Total credits",
  passage = "Degree Hours field: 120; Grand Total Credits: 130", settled_by = "catalog")

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

# Four published past forecasts and one the rule did not publish, for the
# pressure bump's record: each projected 100. Registered 110 and 105 where the
# course was near full the year before, 100 where it was not, 95 where the
# year before's first day is unknown; the unpublished row is never read.
# Total 400 forecast against 410 registered. With 5% on the two near-full
# rows: 410 against 410, misses 5 + 0 + 0 + 5 = 10 where the forecast's were 20.
projection_bump_record_backtests <- tibble::tibble(
  subject_course = paste("TEST", 101:105),
  policy_selected = c(TRUE, TRUE, TRUE, TRUE, FALSE),
  projected_classlist_total = 100,
  actual_classlist_total = c(110, 105, 100, 95, 300),
  fold_prior_near_full = c(TRUE, TRUE, FALSE, NA, TRUE)
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

# ── test-course-topics.R ────────────────────────────────────────────────────────

# TP01's attempt table, built to its edges (graded through Fall 2021).
tp_attempts <- keyed_attempts(cedar_registrations_tp, tp01_edges)

# TP01's two reviewed merges, read as the app reads topic_titles.csv.
tp_topic_titles <- validate_topic_titles(cedar_topic_titles_tp)

# ── test-logging.R ──────────────────────────────────────────────────────────────

# Rows of the timing log, as most_run_report_values() reads them. For report
# "course_report" and field "course", since 2026-11-01:
#   HIST 1110  3   two runs and one with no success recorded (an older row);
#                  a fourth is from October
#   BIOL 1140  2   ties with CHEM 1215 and comes first, by name
#   CHEM 1215  2   a third run failed: counted, it would tie with HIST 1110
#                  and come first
#   ENGL 1110  1   on 2026-11-01 itself: the date is inside
# With no date, HIST 1110 has 4.
# Naming no course to count: a dept_dashboard run that names one, a row whose
# parameters are not JSON (the one row reported), a run naming two courses,
# and a run with no parameters.
.timing_log_rows <- data.frame(
  timestamp = c(
    "2026-11-20 10:00:00", "2026-11-21 10:00:00", "2026-11-22 10:00:00", "2026-11-22 11:00:00",
    "2026-10-15 10:00:00", "2026-11-05 10:00:00", "2026-11-06 10:00:00", "2026-11-07 10:00:00",
    "2026-11-08 10:00:00", "2026-11-01 00:00:05", "2026-11-10 10:00:00", "2026-11-11 10:00:00",
    "2026-11-12 10:00:00", "2026-11-13 10:00:00"),
  report_type = c(rep("course_report", 10L), "dept_dashboard", rep("course_report", 3L)),
  report_params = c(
    '{"course":"HIST 1110"}', '{"course":"HIST 1110"}', '{"course":"HIST 1110"}', '{"course":"CHEM 1215"}',
    '{"course":"HIST 1110"}', '{"course":"CHEM 1215"}', '{"course":"CHEM 1215"}', '{"course":"BIOL 1140"}',
    '{"course":"BIOL 1140"}', '{"course":"ENGL 1110"}', '{"course":"MATH 1220","dept":"MATH"}',
    '{course: FYEX 1110', '{"course":["PHYS 1230","PHYS 1240"]}', NA),
  success = c(1L, 1L, NA, 0L, 1L, 1L, 1L, 1L, 1L, 1L, 1L, 1L, 1L, 1L),
  stringsAsFactors = FALSE
)

# ── test-later-course.R ─────────────────────────────────────────────────────────

# DS01's attempt table, built to its edges (graded through Summer 2022).
ds_attempts <- keyed_attempts(test_students_ds, ds01_edges)

# One attempt per grade a class list can hold, classified once by
# build_attempts(), for add_attempt_grade_band(): twelve students in one
# section, GB_01 to GB_12, the last a late drop with no grade. The bands
# expected, in student order: A, A, B, C, C- to F, C- to F, C- to F,
# Other passing, Other nonpassing, Other nonpassing, Withdrew, Withdrew.
grade_band_attempts <- local({
  grades <- c("A-", "RA", "B+", "C", "C-", "D", "RF", "CR", "P", "NR", "W", NA)
  rows <- dplyr::bind_rows(lapply(seq_along(grades), function(i) {
    .mc_row(sprintf("GB_%02d", i), 202010, "SPAN 101", "ABQ", "SPAN", grade = grades[[i]])
  }))
  rows$registration_status_code[is.na(rows$final_grade)] <- "DW"
  keyed_attempts(rows, mc02_edges) %>% dplyr::arrange(student_id)
})

# A Later Course payload's per-term series, typed by hand for the trend
# reading (later_course_trend() and what is drawn and said from it). Only the
# fields those functions read are present. A rate needs 10 students.
#
#   ABQ, Fall 2018 to Fall 2022: 100 could have taken STAT 245 each term and
#     40, 45, 50, 55, 60 did. The share rises 5 points a year; at the pooled
#     50% chance alone gives a slope of 2 x 1.58 = 3.16, so it is rising. All
#     of them are graded and 30, 33, 38, 41, 45 passed (75.0, 73.3, 76.0,
#     74.5, 75.0%): +0.12 points a year against 2 x 1.98, steady.
#   ABQ, Fall 2023: 4 could have; no rate, so it is not a term of the trend.
#   ABQ, Fall 2024: 120 took STAT 145, all too recent.
#   ABQ, Spring 2019 and Spring 2020: two terms with a rate, too few to read.
#   GA, Fall 2018 to Fall 2022: the share falls 5 points a year, 60 to 40.
#   EA, Fall 2018 to Fall 2022: a large course that dips and recovers. 10,000
#     could have each term and 50, 40, 42, 52, 56% did: +2.4 points a year.
#     Binomial chance at the pooled 48% gives 2 x 0.16, which alone would call
#     it rising; the terms' scatter around the line gives 2 x 2.05, so it is
#     steady. Exactly 75% pass every term: a flat line.
later_course_trend_payload <- structure(
  list(
    course_x = "STAT 145", course_y = "STAT 245", course_y_label = "STAT 245",
    rollup = FALSE, window_terms = 3L, min_n = 10L,
    by_term = tibble::tribble(
      ~campus, ~term_x, ~n_in_x, ~n_eligible, ~n_took_y, ~n_graded, ~n_pass, ~n_not_graded,
      "ABQ",   201880L, 104L,    100L,        40L,       40L,       30L,     0L,
      "ABQ",   201910L,  52L,     50L,        20L,       20L,       15L,     0L,
      "ABQ",   201980L, 103L,    100L,        45L,       45L,       33L,     0L,
      "ABQ",   202010L,  51L,     50L,        22L,       22L,       16L,     0L,
      "ABQ",   202080L, 101L,    100L,        50L,       50L,       38L,     0L,
      "ABQ",   202180L, 102L,    100L,        55L,       55L,       41L,     0L,
      "ABQ",   202280L, 100L,    100L,        60L,       60L,       45L,     0L,
      "ABQ",   202380L,   4L,      4L,         2L,        1L,        1L,     1L,
      "ABQ",   202480L, 120L,      0L,         0L,        0L,        0L,     0L,
      "GA",    201880L, 100L,    100L,        60L,       60L,       45L,     0L,
      "GA",    201980L, 100L,    100L,        55L,       55L,       41L,     0L,
      "GA",    202080L, 100L,    100L,        50L,       50L,       38L,     0L,
      "GA",    202180L, 100L,    100L,        45L,       45L,       33L,     0L,
      "GA",    202280L, 100L,    100L,        40L,       40L,       30L,     0L,
      "EA",    201880L, 10000L,  10000L,      5000L,     5000L,     3750L,   0L,
      "EA",    201980L, 10000L,  10000L,      4000L,     4000L,     3000L,   0L,
      "EA",    202080L, 10000L,  10000L,      4200L,     4200L,     3150L,   0L,
      "EA",    202180L, 10000L,  10000L,      5200L,     5200L,     3900L,   0L,
      "EA",    202280L, 10000L,  10000L,      5600L,     5600L,     4200L,   0L
    ) %>%
      dplyr::mutate(
        term_type = get_term_type(term_x),
        pct_took_y = dplyr::if_else(n_eligible >= 10L, 100 * n_took_y / n_eligible, NA_real_),
        pct_pass = dplyr::if_else(n_graded >= 10L, 100 * n_pass / n_graded, NA_real_)
      )
  ),
  class = c("later_course", "list")
)

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

# MC02's arrivals, as student_term_entry_type() returns them. MC_A1 started
# first-time and has a later transfer record: the first on record starts the
# path. MC_A2's first term is recorded both ways and reads first-time. MC_A3
# transferred in the term after a course here, which is left out. MC_G2 has
# none and is left out. First-time: MC_A1, MC_A2, MC_A4, MC_G1; transfer: MC_A3.
grouped_path_arrivals <- tibble::tribble(
  ~student_id, ~term,   ~entry_type,
  "MC_A1",     202010L, "first_time",
  "MC_A1",     202110L, "transfer",
  "MC_A2",     202010L, "transfer",
  "MC_A2",     202010L, "first_time",
  "MC_A3",     202080L, "transfer",
  "MC_A4",     202010L, "first_time",
  "MC_G1",     202010L, "first_time")

# The course dimension over MC02's class list, to describe its courses.
grouped_path_courses <- suppressMessages(build_cedar_courses(test_sections[0, ], test_students_mc, test_dims))

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
  opt = list(type = "preset", program_codes = c("HIST-BA", "HIST-MA"))
)

math_pop <- build_population(
  test_programs,
  opt = list(type = "preset", program_codes = "MATH-BS")
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
  test_programs_hp2, opt = list(type = "preset", program_codes = "NURS")
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

# ── test-registration-watch.R ───────────────────────────────────────────────────

# A Regstats payload typed by hand: every pattern once, one course on two
# campuses, and a "usually near full" course. Fall 2026, part of term 1. Expected:
#   RW01 SPAN 1110 ABQ AS  dip + near full now + usually near full  -> seats cut, 60 below the usual range
#   RW02 SPAN 1110 EA  AS  bump + near full + running hot + 12 waiting -> students waiting, 12
#   RW03 BIOL 2210 ABQ AS  69 waiting + near full now + usually near full -> students waiting, 69
#   RW04 CHEM 1215 ABQ AS  bump (120 beyond) + early drops (15)  -> growth with churn, 15
#   RW05 HIST 1110 ABQ AS  dip (30 beyond), no fill flag         -> falling demand, 30
#   RW06 PSYC 1110 ABQ AS  bump (25 beyond), no fill flag        -> rising demand, 25
#   RW07 MATH 1215 ABQ AS  early drops 4 + late drops 18         -> drop spike, 22
#   RW08 ENGL 1120 ABQ AS  near full now + usually near full, nothing else -> usually near full (not listed)
#   RW09 ARTH 1120 ABQ FA  near full now + running hot, not usually   -> fuller than usual, no count
#   RW10 FDMA 1520 ABQ FA  dip (30 beyond) + near full now + usually  -> seats cut, 30
#   RW11 BIOL 2305 ABQ AS  bump (50 beyond) + full, no waitlist  -> growth at capacity, 50
#   RW12 MATH 1350 EA  AS  9 waiting, a first offering, no seats -> students waiting, 9
# course_context is every raised row's census, usual census, seats and fill,
# as Regstats returns it: CHEM 1215 has no usable seats (NA fill), MATH 1350
# no earlier offering (NA usual) and no seats, so neither can be placed on the
# watch's chart; HIST 1110 and PSYC 1110 have room; FDMA 1520 fell to under a
# fifth of its usual (12 against 62), past the chart's quarter, so it is drawn
# at the edge.
watch_flagged <- local({
  rw <- function(...) tibble::tribble(...) %>% dplyr::mutate(term = 202680L, part_term = "1")
  list(
    bumps = rw(
      ~campus, ~college, ~subject_course, ~course_title,     ~census_enrl, ~census_enrl_mean, ~impacted,
      "EA",    "AS",     "SPAN 1110",     "Elementary Span I", 80,          50,                20,
      "ABQ",   "AS",     "CHEM 1215",     "General Chem I",    700,         500,               120,
      "ABQ",   "AS",     "PSYC 1110",     "Intro Psychology",  300,         250,               25,
      "ABQ",   "AS",     "BIOL 2305",     "General Biology",   285,         210,               50),
    dips = rw(
      ~campus, ~college, ~subject_course, ~course_title,     ~census_enrl, ~census_enrl_mean, ~impacted,
      "ABQ",   "AS",     "SPAN 1110",     "Elementary Span I", 445,         548,               60,
      "ABQ",   "AS",     "HIST 1110",     "US History I",      60,          110,               30,
      "ABQ",   "FA",     "FDMA 1520",     "Film Production",   12,          62,                30),
    waits_by_course = rw(
      ~campus, ~college, ~subject_course, ~waiting,
      "EA",    "AS",     "SPAN 1110",     12,
      "ABQ",   "AS",     "BIOL 2210",     69,
      "EA",    "AS",     "MATH 1350",     9),
    sat = rw(
      ~campus, ~college, ~subject_course, ~course_title,     ~census_enrl, ~capacity, ~fill_rate, ~is_full_now, ~is_chronic_hist, ~is_running_hot,
      "ABQ",   "AS",     "SPAN 1110",     "Elementary Span I", 445,         456,       0.976,      TRUE,         TRUE,             FALSE,
      "EA",    "AS",     "SPAN 1110",     "Elementary Span I", 80,          80,        1.000,      TRUE,         FALSE,            TRUE,
      "ABQ",   "AS",     "BIOL 2210",     "Anatomy & Phys I",  165,         168,       0.982,      TRUE,         TRUE,             FALSE,
      "ABQ",   "AS",     "ENGL 1120",     "Composition II",    1080,        1100,      0.982,      TRUE,         TRUE,             FALSE,
      "ABQ",   "FA",     "ARTH 1120",     "Art Appreciation",  178,         180,       0.989,      TRUE,         FALSE,            TRUE,
      "ABQ",   "FA",     "FDMA 1520",     "Film Production",   12,          13,        0.923,      TRUE,         TRUE,             FALSE,
      "ABQ",   "AS",     "BIOL 2305",     "General Biology",   285,         288,       0.990,      TRUE,         TRUE,             TRUE),
    early_drops = rw(
      ~campus, ~college, ~subject_course, ~course_title,     ~impacted,
      "ABQ",   "AS",     "CHEM 1215",     "General Chem I",    15,
      "ABQ",   "AS",     "MATH 1215",     "Intermediate Alg",  4),
    late_drops = rw(
      ~campus, ~college, ~subject_course, ~course_title,     ~impacted,
      "ABQ",   "AS",     "MATH 1215",     "Intermediate Alg",  18),
    course_context = rw(
      ~campus, ~college, ~subject_course, ~census_enrl, ~census_enrl_mean, ~capacity, ~fill_rate,
      "ABQ",   "AS",     "SPAN 1110",     445,          548,               456,       0.976,
      "EA",    "AS",     "SPAN 1110",     80,           50,                80,        1.000,
      "ABQ",   "AS",     "BIOL 2210",     165,          160,               168,       0.982,
      "ABQ",   "AS",     "CHEM 1215",     700,          500,               NA,        NA,
      "ABQ",   "AS",     "HIST 1110",     60,           110,               150,       0.400,
      "ABQ",   "AS",     "PSYC 1110",     300,          250,               400,       0.750,
      "ABQ",   "AS",     "MATH 1215",     340,          330,               400,       0.850,
      "ABQ",   "AS",     "ENGL 1120",     1080,         1060,              1100,      0.982,
      "ABQ",   "FA",     "ARTH 1120",     178,          170,               180,       0.989,
      "ABQ",   "FA",     "FDMA 1520",     12,           62,                13,        0.923,
      "ABQ",   "AS",     "BIOL 2305",     285,          210,               288,       0.990,
      "EA",    "AS",     "MATH 1350",     40,           NA,                NA,        NA),
    thresholds = list(min_impacted = 10, pct_sd = 1, chronic_fill_rate = 0.9,
                      min_sat_terms = 3, min_wait = 8)
  )
})
watch_payload <- build_registration_watch(watch_flagged)

# The fixture Regstats run (EC-11, Fall 2020 against its two earlier Falls),
# with the thresholds test-regstats.R uses, so the watch reads real output.
watch_regstats <- get_reg_stats(
  test_students_regstats, test_sections_regstats,
  list(term = 202080L, bypass_cache = TRUE,
       thresholds = list(min_impacted = 1, pct_sd = 1, chronic_fill_rate = .60,
                         min_sat_terms = 1, min_wait = 1, section_proximity = .3)),
  course_terms = test_course_terms_regstats)

# A topics course on the waitlist under two titles (ISSUES I71). Three of
# SOCI 104's registered students become waitlisted: the first for both
# titles, the second for the first title, the third for the second. Four
# waitlist rows, two titles, three students.
watch_topic_students <- local({
  rows <- test_students_regstats %>%
    filter(term == 202080, subject_course == "SOCI 104", campus == "ABQ",
           registration_status_code %in% STATUS_REGISTERED) %>%
    arrange(student_id) %>%
    slice(1:3) %>%
    mutate(registration_status_code = STATUS_WAITLIST[1])
  waiting <- bind_rows(
    rows[c(1, 2), ] %>% mutate(course_title = "Topics: Cities"),
    rows[c(1, 3), ] %>% mutate(course_title = "Topics: Migration")
  )
  bind_rows(anti_join(test_students_regstats, rows,
                      by = c("student_id", "term", "subject_course", "campus")),
            waiting)
})
watch_topic_regstats <- get_reg_stats(
  watch_topic_students, test_sections_regstats,
  list(term = 202080L, bypass_cache = TRUE,
       thresholds = list(min_impacted = 1, pct_sd = 1, chronic_fill_rate = .60,
                         min_sat_terms = 1, min_wait = 1, section_proximity = .3)),
  course_terms = test_course_terms_regstats)

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

# HD01: the Student Holds report as parse-data.R stores it (student_holds),
# three pulls of three terms. A pull lists the whole hold history of the
# students registered in its term, so a hold repeats across pulls, each time
# as it stood that day.
#
#   pull  term    pulled      students
#   P1    202510  2026-11-20  HD-A, HD-B
#   P2    202580  2026-11-22  HD-A, HD-C
#   P3    202610  2026-11-22  HD-C          (the same day as P2)
#
#   H1  HD-A  AV  from 2025/01/10  open in P1, ended 2025/03/01 in P2
#             -> one row, as P2 saw it
#   H2  HD-A  BP  from 2025/02/01  in P1 only: gone from the student's later pull
#             -> one row, as P1 saw it, in_latest_pull FALSE
#   H3  HD-A  AV  from 2025/09/01  listed twice by P2, ended 2025/09/20 and open
#             -> two rows
#   H4  HD-B  BP  from 2025/04/15  in P1, the student's only pull; no
#             explanation, no office -> one row, in_latest_pull TRUE
#   H5  HD-C  RG  from 2025/08/20  open in P2, ended 2025/12/01 in P3
#             -> one row, as P3 saw it: the later term breaks the same-day tie
#
# 8 stored rows -> 6 holds; 3 with no end date (H2, H3's second, H4); 1 not in
# the student's latest pull (H2). Pulls: 202510 2 students 3 rows, 202580
# 2 students 4 rows, 202610 1 student 1 row. Major Code stands for the
# student's description on the report, which the table does not carry.
student_holds_hd01 <- tibble::tribble(
  ~ID,    ~`Academic Period Code`, ~`Hold Code`, ~Hold,                  ~`Hold Explanation`,             ~`Hold Originating Office Code`, ~`Hold Originating Office`, ~`Hold From Date`, ~`Hold To Date`, ~as_of_date,
  "HD-A", 202510L,                 "AV",         "Advisement",           "Mandatory Freshman Advisement", "UC",                            "University College",       "2025/01/10",      "2099/12/31",    "2026-11-20",
  "HD-A", 202510L,                 "BP",         "Bursar, Past Due Amt", "Payment Due",                   "BU",                            "Bursar",                   "2025/02/01",      "2099/12/31",    "2026-11-20",
  "HD-B", 202510L,                 "BP",         "Bursar, Past Due Amt", "",                              "",                              "",                         "2025/04/15",      "2099/12/31",    "2026-11-20",
  "HD-A", 202580L,                 "AV",         "Advisement",           "Mandatory Freshman Advisement", "UC",                            "University College",       "2025/01/10",      "2025/03/01",    "2026-11-22",
  "HD-A", 202580L,                 "AV",         "Advisement",           "Pre-Major Advisement",          "UC",                            "University College",       "2025/09/01",      "2025/09/20",    "2026-11-22",
  "HD-A", 202580L,                 "AV",         "Advisement",           "Pre-Major Advisement",          "UC",                            "University College",       "2025/09/01",      "2099/12/31",    "2026-11-22",
  "HD-C", 202580L,                 "RG",         "Registrar",            "Missing Transcript",            "RO",                            "Registrar",                "2025/08/20",      "2099/12/31",    "2026-11-22",
  "HD-C", 202610L,                 "RG",         "Registrar",            "Missing Transcript",            "RO",                            "Registrar",                "2025/08/20",      "2025/12/01",    "2026-11-22"
) %>%
  dplyr::mutate(`Hold User Creator` = "staff-1", `Major Code` = "HIST",
                as_of_date = as.Date(as_of_date))

# ── test-report-specs.R ─────────────────────────────────────────────────────────

# A Student Holds export as xlsx2csv writes it: the report's title, a blank
# line, the column names on line 3, two holds, a blank line and the line
# saying when the report ran. The ID opens with a zero, which a numeric read
# would lose.
holds_export_lines <- c(
  "Active Student Holds,,,",
  ",,,",
  "ID,Student Full Name (LFMI),Hold Code,Hold From Date",
  "012345678,\"Lovelace, Ada\",AV,2025/01/10",
  "012345678,\"Lovelace, Ada\",BP,2025/02/01",
  ",,,",
  "\"s_student_holds ran on Nov 22, 2026  at 10.43.26\",,,",
  ",,,"
)

# The same export as three files the reader cannot take as written (I79). Read
# with fread() alone, each comes back looking like a report:
#   cut_inside_a_cell   the file ends part-way through a third hold's name, as
#                       a conversion that stops mid-file leaves it: the two
#                       holds above come back and the third is dropped.
#   cut_after_a_cell    it ends after the name: the third hold comes back as a
#                       row, its name split over two columns.
#   too_many_cells      a third hold's name has a comma and no quotes, so the
#                       line has one cell too many: the hold below it is lost.
holds_export_unreadable <- list(
  cut_inside_a_cell = c(holds_export_lines[1:5], "012345679,\"Hopper, Gr"),
  cut_after_a_cell = c(holds_export_lines[1:5], "012345679,\"Hopper, Grace\",A"),
  too_many_cells = c(
    holds_export_lines[1:5],
    "012345679,Hopper, Grace,AV,2025/03/01",
    "012345680,\"Franklin, Rosalind\",AV,2025/03/02",
    holds_export_lines[6:8]
  )
)

# ── test-dfw-dashboard.R ────────────────────────────────────────────────────────

# DF01's attempt table, built to its edges (graded through Fall 2022).
df_attempts <- keyed_attempts(test_students_df, df01_edges)

# ── test-population-groups.R ────────────────────────────────────────────────────

# A confirmed rename into a group program: HSCI (in no file) renamed NURS from
# Fall 2020, so a group listing NURS reaches HSCI's students too.
population_group_rename_successions <- data.frame(
  from_code = "HSCI", to_code = "NURS", effective_term = 202080L,
  stringsAsFactors = FALSE)

# ── test-return-rates.R ─────────────────────────────────────────────────────────

# EC01: two entering classes followed term by term (test-entering-class-retention.R).
# Fall 2019 is the table's first term, so EC-P (enrolled then and in Fall
# 2020) enters no class. The Fall 2020 class is six students:
#   EC-A  every term through Fall 2022
#   EC-B  through Fall 2021
#   EC-C  through Spring 2021
#   EC-D  Fall 2020 only
#   EC-E  away in Spring 2021, back in Fall 2021 only
#   EC-G  Fall 2020 and Spring 2021, awarded a degree in Spring 2021
# so 4 of 6 are here in Spring 2021 (A B C G), 4 in Fall 2021 (A B E, and G
# by degree), 2 in Spring 2022 (A G) and 2 in Fall 2022 (A G). The Fall 2021
# class is three: EC-F1 (to Spring 2022), EC-F2 (Fall 2021 only), EC-F3 (to
# Fall 2022), and EC-X, a graduate student, entering at another level: 2 of 3
# in Spring 2022, 1 of 3 in Fall 2022. Settled through Fall 2022. EC-S (below)
# first enrolls in Summer 2021, so by first enrolled term is a summer entrant.
# Pace (15 credits a term for four years, 10 for six), read before each
# target term begins. Fall 2020 class, everyone new at the level (A B C D E G):
#   Spring 2021 (step 1)  A 15, C 15: four-year; B 9: slower; G: degree;
#                         D, E: gone
#   Fall 2021 (step 2)    A 30: four-year; B 18: slower; E 15: slower (back
#                         after a term away); G: degree; C, D: gone
#   Spring 2022 (step 3)  A 45: four-year; G: degree; four gone
# Fall 2021 class (F1 F2 F3 S, by first enrolled term S is a summer entrant
# and not in it): Spring 2022  F1 15: four-year; F3 12: six-year; F2: gone.
#   Fall 2022  F3 15 of 20 for six years: slower; F1, F2: gone.
ec01 <- local({
  terms <- list(
    `EC-P` = c(201980L, 202080L),
    `EC-A` = c(202080L, 202110L, 202180L, 202210L, 202280L),
    `EC-B` = c(202080L, 202110L, 202180L),
    `EC-C` = c(202080L, 202110L),
    `EC-D` = 202080L,
    `EC-E` = c(202080L, 202180L),
    `EC-G` = c(202080L, 202110L),
    `EC-F1` = c(202180L, 202210L),
    `EC-F2` = 202180L,
    `EC-F3` = c(202180L, 202210L, 202280L),
    `EC-X` = c(202180L, 202210L)
  )
  student_terms <- dplyr::bind_rows(lapply(names(terms), function(id) tibble::tibble(
    student_id = id, term = terms[[id]], enrolled = TRUE,
    student_level = if (id == "EC-X") "GR" else "UG", student_campus = "ABQ",
    student_classification = if (id == "EC-E") "Sophomore, 2nd Yr" else "Freshman, 1st Yr, 1st Sem")))
  # Who the record calls new, in the declarations table's shape. First-time in
  # Fall 2020: A, B, C, D (E is a new transfer, G is not called new). EC-P is
  # called first-time in Fall 2019, the table's first term. EC-S starts in
  # Summer 2021 and is enrolled that fall: a member of the Fall 2021 class
  # with F1, F2 and F3, part-time where they are full-time, and gone after it.
  # EC-N is called first-time in Fall 2021 and never enrolled.
  student_terms <- dplyr::bind_rows(
    student_terms %>% dplyr::mutate(time_status = "FT"),
    tibble::tibble(student_id = "EC-S", term = c(202160L, 202180L), enrolled = TRUE, student_level = "UG",
                   student_campus = "ABQ", student_classification = "Freshman, 1st Yr, 1st Sem", time_status = "PT"))
  programs <- tibble::tibble(
    student_id = c("EC-P", "EC-A", "EC-B", "EC-C", "EC-D", "EC-E", "EC-F1", "EC-F2", "EC-F3", "EC-S", "EC-N", "EC-A"),
    term = c(201980L, rep(202080L, 5), rep(202180L, 3), 202160L, 202180L, 202110L),
    student_population = c(rep("First Time/Beginning Freshman", 5), "New Transfer from NM Inst",
                           rep("First Time/Beginning Freshman", 3), "Summer First Time/Beg Freshman",
                           "First Time/Beginning Freshman", "Continuing")) %>%
    # EC-E, the new transfer, brought 45 credits; no one else brought any.
    dplyr::mutate(inst_credits_attempted = 15,
                  overall_credits_attempted = dplyr::if_else(student_id == "EC-E", 60, 15))
  # Credits completed each enrolled term, and the running total. EC-A 15 a
  # term; EC-B 9 a term; EC-F3 12 then 3 then 15; everyone else 15. EC-P's
  # first term is the table's first, so their running total is not whole.
  per_term <- function(id, k) if (id == "EC-B") 9 else if (id == "EC-F3") c(12, 3, 15)[k] else 15
  student_terms <- student_terms %>%
    dplyr::arrange(student_id, term) %>%
    dplyr::group_by(student_id) %>%
    dplyr::mutate(completed_unm_credits = mapply(per_term, student_id, dplyr::row_number()),
                  cumulative_completed_unm_credits = cumsum(completed_unm_credits),
                  # Everything attempted was completed.
                  cumulative_attempted_unm_credits = cumulative_completed_unm_credits,
                  unm_credits_entering = cumulative_attempted_unm_credits - completed_unm_credits,
                  timeline_valid = student_id != "EC-P") %>%
    dplyr::ungroup()
  list(student_terms = student_terms, programs = programs,
       degrees = tibble::tibble(student_id = "EC-G", term = 202110L),
       edges = list(last_enrolled_complete = 202280L, last_graded = 202280L, last_degree = 202280L))
})

# XC01: undergraduates whose last term is behind them (test-exit-credits.R).
# Enrollment is settled and degrees are posted through Fall 2022. ABQ unless
# said. Each student's last term, and what the declarations table stamped on it:
#   X-A  Spring 2021; 100 earned, 110 attempted, GPA 2.5, Pell; two
#        declarations that term, stamped alike. 90 to 104.
#   X-B  Spring 2021; 108 earned, 150 attempted, GPA 1.8, pulled 2021-03-01,
#        before Fall 2021 began: the term's own 12 completed and 12 attempted
#        credits are added. 120 earned, 162 attempted: below the floor, past
#        the ceiling. 120 or more.
#   X-C  Fall 2020; 20 earned, GPA 3.0, Pell never recorded. Under 30.
#   X-D  Spring 2021, a degree that term: not gone.
#   X-E  Spring 2022: its second regular term after is past the edge. Not judged.
#   X-F  Fall 2022, still enrolled. Not judged.
#   X-G  an undergraduate in Fall 2020, a graduate student in Fall 2021: the
#        last term is another level's.
#   X-H  Spring 2021, no declaration row that term. Not recorded.
#   X-I  Spring 2021, home campus EA; 65 earned, GPA 2.0 (at the floor, not
#        under it). 60 to 89.
#   X-J  Spring 2020, away, back in Spring 2021 and gone; 118 earned, no GPA.
#        105 to 119.
#   X-K  Spring 2021; 125 earned; a degree dated Spring 2023, past the degree
#        edge, so not yet a degree. 120 or more.
# Eight judged last terms: one with a degree, seven left. X-B and X-K are
# History majors, the rest Anthropology; every one in college AS.
# Programs that term: X-B and X-K BA-HIST-AS, X-J BA-ANTH-AS, the rest the
# Anthropology pre-major BA-FANT-AS. X-A brought 60 of their credits from
# elsewhere; everyone else earned all of theirs here.
# Two degree plans (`boards`), and what the four students who left with 90
# credits or more did in the courses each names (`attempts`):
#   hist-ba  HIST 1101 (the course HIST 101, renumbered): X-B passed it; X-K
#              failed it at ABQ and passed it at EA under the new number.
#            HIST 201 + HIST 201L, required together, a row each: X-B
#              passed the lecture and failed the lab; X-K took neither.
#            HIST 900: its first grade is in Fall 2022, after the latest last
#              term here (not readable).
#            one open choice tile (not read).
#   anth-ba  ANTH 101: X-A failed it (tried); X-J dropped it early (none).
# X-A also passed HIST 1101, which is not in their plan, and X-C (under 30
# credits) passed ANTH 101.
xc01 <- local({
  last <- c(`X-A` = 202110L, `X-B` = 202110L, `X-C` = 202080L, `X-D` = 202110L, `X-E` = 202210L,
            `X-F` = 202280L, `X-H` = 202110L, `X-I` = 202110L, `X-J` = 202110L, `X-K` = 202110L)
  row <- function(id, term, level = "UG") tibble::tibble(
    student_id = id, term = term, enrolled = TRUE, student_level = level,
    student_campus = if (id == "X-I") "EA" else "ABQ",
    primary_major_code = if (id %in% c("X-K", "X-B")) "HIST" else "ANTH", primary_college_code = "AS",
    is_pre_major = FALSE, completed_unm_credits = 12, attempted_unm_credits = 12,
    # No one here is called first-time, so the page's entering classes are empty,
    # and no one's attempted credits come near the ceiling.
    cumulative_completed_unm_credits = 12, timeline_valid = TRUE,
    unm_credits_entering = 0, cumulative_attempted_unm_credits = 12)
  student_terms <- dplyr::bind_rows(
    lapply(names(last), function(id) row(id, last[[id]])),
    row("X-J", 202010L), row("X-G", 202080L), row("X-G", 202180L, "GR"))
  stamp <- function(id, term, earned, attempted, gpa, pell, as_of = "2022-06-01") tibble::tibble(
    student_id = id, term = term, student_population = "Continuing",
    program_code = if (id %in% c("X-K", "X-B")) "BA-HIST-AS" else if (id == "X-J") "BA-ANTH-AS" else "BA-FANT-AS",
    # X-A brought 60 credits from elsewhere; everyone else earned all of theirs here.
    inst_credits_earned = if (id == "X-A") earned - 60 else earned, overall_credits_earned = earned,
    overall_credits_attempted = attempted, inst_credits_attempted = attempted, inst_gpa = gpa, pell_eligible = pell,
    as_of_date = as.Date(as_of))
  programs <- dplyr::bind_rows(
    stamp("X-A", 202110L, 100, 110, 2.5, TRUE), stamp("X-A", 202110L, 100, 110, 2.5, TRUE),
    stamp("X-B", 202110L, 108, 150, 1.8, FALSE, "2021-03-01"),
    stamp("X-C", 202080L, 20, 24, 3.0, NA),
    stamp("X-D", 202110L, 121, 125, 3.1, FALSE),
    stamp("X-I", 202110L, 65, 70, 2.0, FALSE),
    stamp("X-J", 202010L, 90, 95, 2.2, TRUE), stamp("X-J", 202110L, 118, 120, NA, FALSE),
    stamp("X-K", 202110L, 125, 130, 3.2, TRUE))
  list(
    student_terms = student_terms, programs = programs,
    degrees = tibble::tibble(student_id = c("X-D", "X-K"), term = c(202110L, 202310L)),
    terms = tibble::tibble(term = c(202080L, 202110L, 202180L, 202210L, 202280L),
                           start_date = as.Date(c("2020-08-17", "2021-01-19", "2021-08-23",
                                                  "2022-01-18", "2022-08-22"))),
    attempts = tibble::tribble(
      ~student_id, ~term,   ~campus, ~subject_course, ~listed_code, ~outcome,
      "X-B",       202080L, "ABQ",   "HIST 101",      "HIST 101",   "pass",
      "X-B",       202080L, "ABQ",   "HIST 201",      "HIST 201",   "pass",
      "X-B",       202080L, "ABQ",   "HIST 201L",     "HIST 201L",  "dfw",
      "X-K",       202080L, "ABQ",   "HIST 101",      "HIST 101",   "dfw",
      "X-K",       202110L, "EA",    "HIST 101",      "HIST 1101",  "pass",
      "X-A",       202080L, "ABQ",   "ANTH 101",      "ANTH 101",   "dfw",
      "X-A",       202080L, "ABQ",   "HIST 101",      "HIST 101",   "pass",
      "X-J",       202010L, "ABQ",   "ANTH 101",      "ANTH 101",   NA,
      "X-C",       202080L, "ABQ",   "ANTH 101",      "ANTH 101",   "pass",
      "X-F",       202280L, "ABQ",   "HIST 900",      "HIST 900",   "pass"),
    boards = list(
      catalog = list(
        catalogs = tibble::tibble(catalog_id = c("hist-ba", "anth-ba"),
                                  degree_label = c("History B.A.", "Anthropology B.A.")),
        program_codes = tibble::tibble(
          catalog_id = c("hist-ba", "hist-ba", "anth-ba", "anth-ba"),
          program_code = c("BA-HIST-AS", "BA-FHIS-AS", "BA-ANTH-AS", "BA-FANT-AS"),
          is_pre_major = c(FALSE, TRUE, FALSE, TRUE))),
      roadmaps = list(
        nodes = tibble::tribble(
          ~catalog_id, ~node_id,  ~track, ~kind,         ~code,              ~title,              ~semester,
          "hist-ba",   "survey",  "main", "major",       "HIST 1101",        "Survey",            1L,
          "hist-ba",   "methods", "main", "major",       "HIST 201 + 201L",  "Methods and lab",   3L,
          "hist-ba",   "new",     "main", "major",       "HIST 900",         "New seminar",       7L,
          "hist-ba",   "upper",   "main", "choice",      "HIST 300-499",     "Upper-level",       5L,
          "hist-ba",   "prep",    "main", "preparation", "HIST 100",         "Preparation",       1L,
          "anth-ba",   "intro",   "main", "major",       "ANTH 101",         "Introduction",      1L,
          "*",         "math",    "math", "support",     "MATH 101",         "Math",              1L),
        courses = tibble::tribble(
          ~catalog_id, ~node_id,  ~subject_course,
          "hist-ba",   "survey",  "HIST 1101",
          "hist-ba",   "methods", "HIST 201",
          "hist-ba",   "methods", "HIST 201L",
          "hist-ba",   "new",     "HIST 900",
          "hist-ba",   "prep",    "HIST 100",
          "anth-ba",   "intro",   "ANTH 101",
          "*",         "math",    "MATH 101"),
        options = tibble::tibble(catalog_id = character(), node_id = character()))),
    edges = list(last_enrolled_complete = 202280L, last_graded = 202280L, last_degree = 202280L),
    # Undergraduates, no small-cell guard, read through those edges.
    opt = list(student_level = "UG", min_n = 1L,
               data_edges = list(last_enrolled_complete = 202280L, last_graded = 202280L,
                                 last_degree = 202280L)))
})

# MT01: students entering Undecided, followed semester by semester
# (test-major-tenure.R). The data begin in Spring 2020; settled and degrees
# posted through Spring 2022. Each student's enrolled terms and major:
#   M-A  Fall 2020 UNDC, Spring 2021 UNDC, Fall 2021 HIST, Spring 2022 HIST.
#   M-B  Fall 2020 UNDC, away Spring 2021, Fall 2021 UNDC, away Spring 2022.
#   M-C  Fall 2020 UNDC, Spring 2021 BIOL, a degree in Fall 2021.
#   M-D  enters Fall 2021: UNDC, Spring 2022 UNDC. Two steps can be read.
#   M-E  UNDC in Spring 2020, when the data begin: no entry to count from.
#   M-F  Fall 2020 UNDC, Spring 2021 enrolled with no major on record, then away.
# How the record says each arrived, in the term they entered (`programs`):
#   M-A and M-D first-time, M-B a new transfer; M-C continuing and M-F
#   readmitted, so already at UNM.
mt01 <- local({
  row <- function(id, term, major) tibble::tibble(student_id = id, term = term, enrolled = TRUE, primary_major_code = major)
  list(
    population = tibble::tibble(student_id = c("M-A", "M-B", "M-C", "M-D", "M-E", "M-F"), population_label = "Undecided",
                                first_unit_term = c(202080L, 202080L, 202080L, 202180L, 202010L, 202080L)),
    student_terms = dplyr::bind_rows(
      row("M-A", 202080L, "UNDC"), row("M-A", 202110L, "UNDC"), row("M-A", 202180L, "HIST"), row("M-A", 202210L, "HIST"),
      row("M-B", 202080L, "UNDC"), row("M-B", 202180L, "UNDC"),
      row("M-C", 202080L, "UNDC"), row("M-C", 202110L, "BIOL"), row("M-C", 202180L, "BIOL"),
      row("M-D", 202180L, "UNDC"), row("M-D", 202210L, "UNDC"),
      row("M-E", 202010L, "UNDC"), row("M-E", 202080L, "UNDC"),
      row("M-F", 202080L, "UNDC"), row("M-F", 202110L, NA_character_)),
    degrees = tibble::tibble(student_id = "M-C", term = 202180L),
    programs = tibble::tibble(
      student_id = c("M-A", "M-B", "M-C", "M-D", "M-F", "M-A"),
      term = c(202080L, 202080L, 202080L, 202180L, 202080L, 202110L),
      student_population = c("First Time/Beginning Freshman", "New Transfer from NM Inst", "Continuing",
                             "First Time/Beginning Freshman", "Readmit", "Continuing")),
    opt = list(program_codes = "UNDC", n_terms = 3L,
               data_edges = list(last_enrolled_complete = 202210L, last_degree = 202210L)))
})

# ST01's degree plan (test-dept-report.R, Courses Taken): History B.A., keyed
# on Banner's BA-HIST-AS, which the declarations give major code HIST. It
# names HIST 1110 and MATH 1215 as required; its upper-level choice names no
# course. Anthropology's plan belongs to no HIST major and is not read.
st01_plan <- list(
  programs = tibble::tibble(major_code = c("HIST", "ANTH"), program_code = c("BA-HIST-AS", "BA-ANTH-AS")),
  boards = list(
    catalog = list(
      catalogs = tibble::tibble(catalog_id = c("hist-ba", "anth-ba"),
                                degree_label = c("History B.A.", "Anthropology B.A.")),
      program_codes = tibble::tibble(catalog_id = c("hist-ba", "anth-ba"),
                                     program_code = c("BA-HIST-AS", "BA-ANTH-AS"), is_pre_major = FALSE)),
    roadmaps = list(
      nodes = tibble::tribble(
        ~catalog_id, ~node_id, ~track, ~kind,    ~code,          ~title,        ~semester,
        "hist-ba",   "survey", "main", "major",  "HIST 1110",    "Survey",      1L,
        "hist-ba",   "math",   "main", "major",  "MATH 1215",    "Math",        1L,
        "hist-ba",   "upper",  "main", "choice", "HIST 300-499", "Upper-level", 5L,
        "anth-ba",   "intro",  "main", "major",  "ENGL 1110",    "Composition", 1L),
      courses = tibble::tribble(
        ~catalog_id, ~node_id, ~subject_course,
        "hist-ba",   "survey", "HIST 1110",
        "hist-ba",   "math",   "MATH 1215",
        "anth-ba",   "intro",  "ENGL 1110"),
      options = tibble::tibble(catalog_id = character(), node_id = character()))))

# ST01's plan with its choices' options listed (test-pathways-helpers.R, the
# course grid's plan row). The upper-level choice lists HIST 300, POLS 300
# and MATH 1215, which the plan also requires outright; a math-track route,
# not the plan's own track, lists MATH 1220. Read with options: HIST 1110
# and MATH 1215 required, HIST 300 and POLS 300 one of a choice, MATH 1220 not
# named.
st01_plan_options <- local({
  boards <- st01_plan$boards
  boards$roadmaps$nodes <- dplyr::bind_rows(boards$roadmaps$nodes, tibble::tibble(
    catalog_id = "hist-ba", node_id = "route", track = "math", kind = "choice", code = "MATH",
    title = "Math route", semester = 1L))
  boards$roadmaps$options <- tibble::tribble(
    ~catalog_id, ~node_id, ~subject_course,
    "hist-ba",   "upper",  "HIST 300",
    "hist-ba",   "upper",  "POLS 300",
    "hist-ba",   "upper",  "MATH 1215",
    "hist-ba",   "route",  "MATH 1220")
  list(programs = st01_plan$programs, boards = boards)
})

# CC01: undergraduates passing 160 attempted credits (test-credit-ceiling.R).
# Settled, graded and degrees posted through Fall 2022. ABQ undergraduates
# unless said. Credit from elsewhere, then the running attempted credits here
# after each enrolled term (completed here in brackets where it differs):
#   C-A  120 elsewhere; 15, 30, 45 [36] in Fall 2020, Spring 2021, Fall 2021:
#        passes in Fall 2021 at 165 (9 not completed). Enrolled Spring 2022,
#        awarded a degree that term.
#   C-B  none elsewhere; 60, 120, 165 [150]: passes in Fall 2021 (15 not
#        completed). Enrolled Spring and Fall 2022, no degree.
#   C-C  150 elsewhere; 12 in Fall 2021: passes at 162, awarded a degree that term.
#   C-D  150 elsewhere; 15 in Spring 2022: passes at 165, then not enrolled.
#   C-I  150 elsewhere; 12 in Fall 2022: passes in the last settled term.
#   C-E  170 elsewhere: already past in their first term.
#   C-F  a record that began before the class lists: not readable.
#   C-G  awarded a degree in Fall 2020, passes in Fall 2021: a second degree.
#   C-H  a graduate student passing in Fall 2021: another level.
#   C-J  10 elsewhere; 15, 30: never near.
# Five pass: three in Fall 2021, one in Spring 2022, one in Fall 2022.
cc01 <- local({
  row <- function(id, term, after, completed = after, level = "UG", valid = TRUE) tibble::tibble(
    student_id = id, term = term, enrolled = TRUE, student_level = level, student_campus = "ABQ",
    primary_major_code = "HIST", cumulative_attempted_unm_credits = after,
    cumulative_completed_unm_credits = completed, timeline_valid = valid)
  student_terms <- dplyr::bind_rows(
    row("C-A", 202080L, 15), row("C-A", 202110L, 30), row("C-A", 202180L, 45, 36), row("C-A", 202210L, 60, 51),
    row("C-B", 202080L, 60), row("C-B", 202110L, 120), row("C-B", 202180L, 165, 150),
    row("C-B", 202210L, 180, 165), row("C-B", 202280L, 195, 180),
    row("C-C", 202180L, 12), row("C-D", 202210L, 15), row("C-I", 202280L, 12),
    row("C-E", 202180L, 12), row("C-F", 202180L, 170, valid = FALSE),
    row("C-G", 202080L, 150), row("C-G", 202180L, 165),
    row("C-H", 202180L, 165, level = "GR"),
    row("C-J", 202080L, 15), row("C-J", 202110L, 30)) %>%
    dplyr::group_by(student_id) %>%
    dplyr::mutate(unm_credits_entering = dplyr::lag(cumulative_attempted_unm_credits, default = 0)) %>%
    dplyr::ungroup()
  elsewhere <- c(`C-A` = 120, `C-B` = 0, `C-C` = 150, `C-D` = 150, `C-I` = 150, `C-E` = 170, `C-F` = 0,
                 `C-G` = 0, `C-H` = 0, `C-J` = 10)
  list(student_terms = student_terms,
       programs = tibble::tibble(student_id = names(elsewhere), inst_credits_attempted = 30,
                                 overall_credits_attempted = 30 + unname(elsewhere)),
       degrees = tibble::tibble(student_id = c("C-A", "C-C", "C-G"), term = c(202210L, 202180L, 202080L)),
       opt = list(student_level = "UG", campus = "ABQ",
                  data_edges = list(last_enrolled_complete = 202280L, last_graded = 202280L,
                                    last_degree = 202280L)))
})

# RR01: four falls (202080, 202180, 202280, 202380, k = 1..4) of the same
# shape, and Fall 2024 with no settled next term. Each fall:
#   ABQ freshmen (college AS), RR01-A01..A40: A01..A(26+2k) come back (28,
#     30, 32, 34); A35..A40 withdrew late; A31..A37 got a DFW; A38 has no
#     posted grade (its DFW is unknown). Every one takes MATH 101: DFW for
#     A31..A37, no grade for A38, a pass otherwise.
#   EA sophomores (college EN), RR01-E01..E20: E01..E15 come back. In the
#     first two falls E01..E06 are juniors: a classification not read in the
#     latest fall.
#   Two ABQ seniors awarded a degree that term (left out, counted).
#   Five ABQ graduate students, all back (out of an undergraduate scope).
#     Each takes MATH 101 too and gets a DFW: 15 attempts over the three
#     graded falls that an undergraduate reading of the course never holds.
# Fall 2024: ten ABQ freshmen whose return cannot be observed yet.
rr01 <- local({
  falls <- c(202080L, 202180L, 202280L, 202380L)
  one <- function(term, k) {
    a <- tibble::tibble(i = 1:40, id = sprintf("RR01-A%02d", 1:40), student_campus = "ABQ",
                        student_classification = "Freshman, 1st Yr, 1st Sem", primary_college_code = "AS",
                        returned = (1:40) <= 26 + 2 * k, late_withdrawals = as.integer((1:40) >= 35),
                        dfw_grades = as.integer((1:40) >= 31 & (1:40) <= 37),
                        graded_rows = ifelse((1:40) == 38, 0L, 1L))
    e <- tibble::tibble(i = 1:20, id = sprintf("RR01-E%02d", 1:20), student_campus = "EA",
                        student_classification = ifelse(k <= 2 & (1:20) <= 6, "Junior, 3rd Yr", "Sophomore, 2nd Yr"),
                        primary_college_code = "EN",
                        returned = (1:20) <= 15, late_withdrawals = 0L, dfw_grades = 0L, graded_rows = 1L)
    s <- tibble::tibble(i = 1:2, id = sprintf("RR01-S%02d", 1:2), student_campus = "ABQ",
                        student_classification = "Senior, 4th Yr", primary_college_code = "AS",
                        returned = FALSE, late_withdrawals = 0L, dfw_grades = 0L, graded_rows = 1L)
    g <- tibble::tibble(i = 1:5, id = sprintf("RR01-G%02d", 1:5), student_campus = "ABQ",
                        student_classification = "Graduate, First Masters", primary_college_code = "AS",
                        returned = TRUE, late_withdrawals = 0L, dfw_grades = 0L, graded_rows = 1L)
    dplyr::bind_rows(a, e, s, g) %>%
      dplyr::mutate(term = term, student_id = paste0(id, "-", term), enrolled = TRUE,
                    student_level = ifelse(grepl("-G", id), "GR", "UG"),
                    return_observable = TRUE, degree_awarded = grepl("-S", id))
  }
  rows <- dplyr::bind_rows(lapply(seq_along(falls), function(k) one(falls[[k]], k)))
  unsettled <- tibble::tibble(
    id = sprintf("RR01-A%02d", 1:10), term = 202480L, student_id = paste0(id, "-", term), enrolled = TRUE,
    student_level = "UG", student_campus = "ABQ", student_classification = "Freshman, 1st Yr, 1st Sem",
    primary_college_code = "AS", returned = NA, late_withdrawals = 0L, dfw_grades = 0L, graded_rows = 0L,
    return_observable = FALSE, degree_awarded = FALSE)
  student_terms <- dplyr::bind_rows(rows, unsettled) %>%
    dplyr::transmute(student_id, term, enrolled, student_level, student_campus, student_classification,
                     primary_college_code, late_withdrawals, dfw_grades, graded_rows,
                     returned_next_regular_term = dplyr::if_else(return_observable, returned, NA),
                     return_observable, degree_awarded)
  # MATH 101 attempts, stamped as test_attempts is (one of its rows, restated).
  takers <- dplyr::filter(rows, (grepl("-A", id) & i != 38L) | grepl("-G", id))
  attempts <- test_attempts[rep(1L, nrow(takers)), ] %>%
    dplyr::mutate(student_id = takers$student_id, term = takers$term, campus = "ABQ",
                  subject_course = "MATH 101",
                  outcome = ifelse(takers$dfw_grades > 0L | grepl("-G", takers$id), "dfw", "pass"))
  dashboard <- build_retention_dashboard(student_terms, attempts, NULL, list(
    term_type = "fall", student_level = "UG", data_edges = rr01_edges,
    min_n = 5L, course_min_n = 10L, course_min_dfw_n = 5L))
  list(student_terms = student_terms, attempts = attempts, dashboard = dashboard)
})

# RT01: the return rate after each semester since arrival (test-return-rates.R).
# Four falls (202080..202380, k = 1..4), every undergraduate at home campus
# ABQ, every return observable, read with min_n 5. Each row is its own
# student; programs records each one's arrival ("First Time Freshman" or
# "New Transfer") in the term named:
#   RT01-F1  200 first-time, arrived that fall (1st semester): 140, 148,
#            156, 164 come back (70, 74, 78, 82%): rising.
#   RT01-F3  100 first-time, arrived the fall before (3rd): 85 back: steady.
#   RT01-F5  100 first-time, arrived two falls before (5th): 92, 86, 80, 74
#            back: falling.
#   RT01-F8  6 first-time in their 8th semester (a spring start three and a
#            half years before), 5 back: the last semester drawn.
#   RT01-F10 6 first-time in their 10th semester, all back: after the last
#            semester drawn, the overall line only (24 over the four falls).
#   RT01-F7  10 first-time in their 7th semester in the first two falls
#            only, all back: read earlier, not in the latest, left out.
#   RT01-F2  3 first-time in their 2nd semester (arrived that spring), 2
#            back: under min_n every fall, never read.
#   RT01-T1  40 new transfers in their 1st semester, 30 back (75%): one
#            semester, so no lowest; steady.
#   RT01-X   4 with no arrival on record, all back: the overall line only
#            (16 over the four falls).
# First-time students come back least often after their 1st semester in
# three of the four falls; after their 5th in the last. Every student
# together: 469 in each of the first two falls, 459 after. The arrival
# records begin with RT01-F10's first, Spring 2016, so every semester drawn is
# reached; `by_semester` is the rates table the semester lines read, for a
# test that sets the records' start later.
rt01 <- local({
  falls <- c(202080L, 202180L, 202280L, 202380L)
  block <- function(tag, n, back, arrived, entry) {
    tibble::tibble(i = seq_len(n), tag = tag, returned = seq_len(n) <= back, arrived = arrived, entry = entry)
  }
  one <- function(term, k) {
    dplyr::bind_rows(
      block("F1", 200L, 132L + 8L * k, term, "first_time"),
      block("F3", 100L, 85L, term - 100L, "first_time"),
      block("F5", 100L, 98L - 6L * k, term - 200L, "first_time"),
      block("F8", 6L, 5L, term - 370L, "first_time"),
      block("F10", 6L, 6L, term - 470L, "first_time"),
      if (k <= 2L) block("F7", 10L, 10L, term - 300L, "first_time"),
      block("F2", 3L, 2L, term - 70L, "first_time"),
      block("T1", 40L, 30L, term, "transfer"),
      block("X", 4L, 4L, NA_integer_, NA_character_)
    ) %>%
      dplyr::mutate(term = term, student_id = sprintf("RT01-%s%03d-%d", tag, i, term))
  }
  rows <- dplyr::bind_rows(lapply(seq_along(falls), function(k) one(falls[[k]], k)))
  student_terms <- rows %>%
    dplyr::transmute(student_id, term, enrolled = TRUE, student_level = "UG", student_campus = "ABQ",
                     student_classification = "Sophomore, 2nd Yr", primary_college_code = "AS", late_withdrawals = 0L,
                     dfw_grades = 0L, graded_rows = 1L, returned_next_regular_term = returned,
                     return_observable = TRUE, degree_awarded = FALSE)
  programs <- rows %>%
    dplyr::filter(!is.na(arrived)) %>%
    dplyr::transmute(student_id, term = arrived, student_level = "Undergraduate",
                     student_population = ifelse(entry == "first_time", "First Time Freshman", "New Transfer"))
  dashboard <- build_retention_dashboard(student_terms, NULL, NULL, list(
    term_type = "fall", student_level = "UG", data_edges = rr01_edges, min_n = 5L,
    courses = FALSE, milestones = FALSE), programs = programs)
  semesters <- student_term_semesters(student_terms, programs) %>% dplyr::select(student_id, term, entry_type, semester_here)
  by_semester <- get_return_rates(
    student_terms %>% dplyr::left_join(semesters, by = c("student_id", "term")),
    list(term_type = "fall", student_level = "UG", data_edges = rr01_edges, min_n = 5L,
         group_cols = c("entry_type", "semester_here")), NULL)$rates
  list(student_terms = student_terms, programs = programs, dashboard = dashboard, by_semester = by_semester)
})

# RT02: how student_term_semesters() counts (test-return-rates.R). Arrivals
# in programs' student_population, rows in student_terms:
#   A  first-time Fall 2020: Fall 2020, Spring 2021, Fall 2021 are its
#      1st, 2nd and 3rd semesters.
#   B  first-time Summer 2020: Summer 2020 has no semester; Fall 2020 is the
#      1st, Spring 2021 the 2nd.
#   C  first-time Fall 2020, away, back in Fall 2022: its 5th semester (terms
#      passed, not terms enrolled).
#   D  first-time Fall 2019, a new transfer in Fall 2022: Spring 2021 is its
#      4th semester as first-time; Fall 2022 its 1st as a transfer.
#   E  readmitted, no arrival on record: no row.
#   F  Fall 2020 recorded both ways: first-time.
#   G  a row in Spring 2020, before its Fall 2020 arrival: no row for it.
#   H  first-time Spring 2021: Spring 2021 the 1st, Fall 2021 the 2nd.
#   I  first-time Fall 2020 as an undergraduate, a graduate student in Fall
#      2024: Fall 2021 is its 3rd semester; the graduate term has no row (no
#      arrival at that level).
#   J  a new transfer graduate student in Fall 2022: Spring 2023 its 2nd
#      semester at that level.
# Every row is an undergraduate's (UG) but I's Fall 2024 and J's (GR).
rt02 <- list(
  student_terms = tibble::tibble(
    student_id = c("A", "A", "A", "B", "B", "B", "C", "C", "D", "D", "E", "F", "G", "G", "H", "H", "I", "I", "J"),
    term = c(202080L, 202110L, 202180L, 202060L, 202080L, 202110L, 202080L, 202280L, 202110L, 202280L,
             202080L, 202080L, 202010L, 202080L, 202110L, 202180L, 202180L, 202480L, 202310L),
    student_level = c(rep("UG", 17), "GR", "GR")),
  programs = tibble::tibble(
    student_id = c("A", "B", "C", "D", "D", "E", "F", "F", "G", "H", "I", "J"),
    term = c(202080L, 202060L, 202080L, 201980L, 202280L, 202080L, 202080L, 202080L, 202080L, 202110L, 202080L, 202280L),
    student_level = c(rep("Undergraduate", 11), "Graduate/GASM"),
    student_population = c("First Time Freshman", "First Time Freshman", "First Time Freshman",
                           "First Time Freshman", "New Transfer", "Readmit Student", "New Transfer",
                           "First Time Freshman", "First Time Freshman", "First Time Freshman",
                           "First Time Freshman", "New Transfer")))

# RS01: who the Retention page counts in Fall 2022 (test-return-rates.R).
# Enrolled that fall at home campus ABQ unless said; the record's arrivals:
#   W-A  undergraduate; first-time in Fall 2022 itself            first-time
#   W-B  undergraduate; first-time in Fall 2021, continuing since first-time
#   W-C  undergraduate; a new transfer in Spring 2022              transfer
#   W-D  undergraduate; first-time in Fall 2020, a new transfer in Fall 2022
#        (left and came back): the latest arrival reads            transfer
#   W-E  undergraduate; readmitted in Fall 2022, never called new  not on record
#   W-F  undergraduate; continuing in Fall 2022, called first-time in Spring
#        2023: an arrival after the term is not yet one            not on record
#   W-G  undergraduate; Fall 2022 recorded both ways (two declarations): a
#        term recorded both ways reads                             first-time
#   W-H, W-I  graduate students                                    another level
#   W-J  a student with no level recorded                          another level
#   W-K  undergraduate at EA, a new transfer in Fall 2022          another campus
#   W-L  undergraduate with a Fall 2022 row and no enrollment      not enrolled
#   W-M  undergraduate enrolled in Fall 2021 only, first-time then another term
# So Fall 2022 undergraduates at ABQ: 7 counted (A to G), 3 first-time, 2
# transfer, 2 with no start on record; 2 graduate students and 1 with no
# level left out. At every home campus: 8 counted, 3 transfer.
rs01 <- local({
  st <- function(id, term = 202280L, level = "UG", campus = "ABQ", enrolled = TRUE) tibble::tibble(
    student_id = id, term = term, enrolled = enrolled, student_level = level, student_campus = campus)
  said <- function(id, term, population, level = "Undergraduate") tibble::tibble(
    student_id = id, term = term, student_population = population, student_level = level)
  student_terms <- dplyr::bind_rows(
    st("W-A"), st("W-B", 202180L), st("W-B"), st("W-C", 202210L), st("W-C"),
    st("W-D", 202080L), st("W-D"), st("W-E"), st("W-F"), st("W-F", 202310L), st("W-G"),
    st("W-H", level = "GR"), st("W-I", level = "GR"), st("W-J", level = NA_character_),
    st("W-K", campus = "EA"), st("W-L", enrolled = FALSE), st("W-M", 202180L))
  list(
    student_terms = student_terms,
    # The same rows as the return rates read them: everyone came back.
    returns = dplyr::mutate(student_terms, returned_next_regular_term = TRUE, return_observable = TRUE,
                            degree_awarded = FALSE),
    programs = dplyr::bind_rows(
      said("W-A", 202280L, "First Time/Beginning Freshman"),
      said("W-B", 202180L, "First Time/Beginning Freshman"), said("W-B", 202280L, "Continuing"),
      said("W-C", 202210L, "New Transfer from NM Inst"), said("W-C", 202280L, "Continuing"),
      said("W-D", 202080L, "First Time/Beginning Freshman"), said("W-D", 202280L, "New Transfer from Out of State"),
      said("W-E", 202280L, "Readmit"),
      said("W-F", 202280L, "Continuing"), said("W-F", 202310L, "Summer First Time/Beg Freshman"),
      said("W-G", 202280L, "New Transfer from NM Inst"), said("W-G", 202280L, "First Time/Beginning Freshman"),
      said("W-H", 202280L, "Frst Time Grad/Prf Deg not UNM", "Graduate/GASM"),
      said("W-I", 202280L, "Continuing", "Graduate/GASM"),
      said("W-K", 202280L, "New Transfer from NM Inst"),
      said("W-L", 202280L, "First Time/Beginning Freshman"),
      said("W-M", 202180L, "First Time/Beginning Freshman")),
    opt = list(student_level = "UG", campus = "ABQ"))
})

# SG01: spring students who finish in the summer (test-return-rates.R,
# test-summer-finishers.R). Enrollment is settled through Fall 2023; degrees
# are posted and grades are in through Summer 2022. ABQ undergraduates unless
# said. Enrolled in Spring 2022:
#   S-A  awarded a degree in Summer 2022; 3 summer credits (MATH 101, ABQ)
#   S-B  awarded in Summer 2022; no summer enrollment
#   S-C  awarded in Summer 2022; 6 summer credits (MATH 101 at ABQ, HIST 101 at EA)
#   S-D  awarded in Spring 2022 itself
#   S-E  back in Fall 2022
#   S-F  not back, no degree
#   S-G  not back; a Summer 2022 degree on hold, which is not a degree
#   S-J  a graduate student awarded in Summer 2022 (another level)
# So of 7 undergraduates 4 finished (D in the term; A, B, C in between) and
# 1 of the other 3 came back. Without the degrees table only D finished: 1 of 6.
# Enrolled in Spring 2023: S-H, not back, with an application to graduate in
# Summer 2023, past the degree edge (applied); S-I, back in Fall 2023.
# S-K, enrolled in Fall 2022 and awarded in Spring 2023: not in between (a
# fall's next regular term is the spring).
sg01 <- local({
  row <- function(id, term, returned, level = "UG", awarded = FALSE, credits = 12, major = "HIST") tibble::tibble(
    student_id = id, term = term, enrolled = TRUE, student_level = level, student_campus = "ABQ",
    returned_next_regular_term = returned, return_observable = TRUE, degree_awarded = awarded,
    attempted_unm_credits = credits, primary_major_code = major)
  student_terms <- dplyr::bind_rows(
    row("S-A", 202210L, FALSE), row("S-A", 202260L, FALSE, credits = 3),
    row("S-B", 202210L, FALSE, major = "ANTH"),
    row("S-C", 202210L, FALSE), row("S-C", 202260L, FALSE, credits = 6),
    row("S-D", 202210L, FALSE, awarded = TRUE),
    row("S-E", 202210L, TRUE), row("S-E", 202280L, FALSE),
    row("S-F", 202210L, FALSE),
    row("S-G", 202210L, FALSE),
    row("S-J", 202210L, FALSE, level = "GR"),
    row("S-H", 202310L, FALSE),
    row("S-I", 202310L, TRUE), row("S-I", 202380L, FALSE),
    row("S-K", 202280L, FALSE))
  degrees <- tibble::tibble(
    student_id = c("S-A", "S-B", "S-C", "S-D", "S-G", "S-J", "S-H", "S-K"),
    term = c(202260L, 202260L, 202260L, 202210L, 202260L, 202260L, 202360L, 202310L),
    graduation_status = c("Awarded", "Awarded", "Awarded", "Awarded", "Hold Pending", "Awarded", "Pending", "Pending"))
  attempts <- test_attempts[rep(1L, 3L), ] %>%
    dplyr::mutate(student_id = c("S-A", "S-C", "S-C"), term = 202260L, campus = c("ABQ", "ABQ", "EA"),
                  subject_course = c("MATH 101", "MATH 101", "HIST 101"))
  list(student_terms = student_terms, degrees = degrees, attempts = attempts,
       opt = list(term_type = "spring", student_level = "UG", min_n = 1L,
                  data_edges = list(last_enrolled_complete = 202380L, last_graded = 202260L, last_degree = 202260L)))
})

# SS01: a spring's students in the summer after, and in the fall
# (get_summer_after_spring()). Seven students of Spring 2022, each two regular
# terms in, and one of Spring 2023. Enrollment is settled through Spring 2023;
# grades and degrees are posted through Summer 2022.
#   SS-A  24 credits through spring; 6 in the summer, all completed (30: caught
#         up to 15 a term); enrolled in the fall.
#   SS-B  24 through spring; 3 in the summer (27: still behind); enrolled in the fall.
#   SS-C  20 through spring; no summer; not back.
#   SS-D  30 through spring (not behind); no summer; enrolled in the fall.
#   SS-E  40 through spring; 3 attempted in the summer, none completed; awarded
#         a degree that summer, so back without a fall enrollment.
#   SS-F  running total not whole (`timeline_valid` FALSE); no summer; enrolled in the fall.
#   SS-G  Spring 2023: its fall is not settled and its summer not graded.
#   SS-H  20 through spring and awarded a degree that spring: finished, so
#         back without a fall enrollment and not read as behind.
# Summer 2022 attempts: SS-A and SS-B MATH 101 (ABQ), SS-E HIST 101 (EA).
ss01 <- local({
  row <- function(id, term, attempted = 12, completed = 12, cumulative = NA_real_, valid = TRUE) tibble::tibble(
    student_id = id, term = term, enrolled = TRUE, attempted_unm_credits = attempted,
    completed_unm_credits = completed, cumulative_completed_unm_credits = cumulative, timeline_valid = valid)
  student_terms <- dplyr::bind_rows(
    row("SS-A", 202210L, cumulative = 24), row("SS-A", 202260L, 6, 6, 30), row("SS-A", 202280L, cumulative = 42),
    row("SS-B", 202210L, cumulative = 24), row("SS-B", 202260L, 3, 3, 27), row("SS-B", 202280L, cumulative = 39),
    row("SS-C", 202210L, cumulative = 20),
    row("SS-D", 202210L, cumulative = 30), row("SS-D", 202280L, cumulative = 42),
    row("SS-E", 202210L, cumulative = 40), row("SS-E", 202260L, 3, 0, 40),
    row("SS-F", 202210L, cumulative = 12, valid = FALSE), row("SS-F", 202280L, cumulative = 24, valid = FALSE),
    row("SS-G", 202310L, cumulative = 10), row("SS-H", 202210L, cumulative = 20))
  spring_students <- tibble::tibble(
    student_id = paste0("SS-", c("A", "B", "C", "D", "E", "F", "G", "H")),
    term = c(rep(202210L, 6L), 202310L, 202210L), group = "Class", terms_completed = 2L)
  degrees <- tibble::tibble(student_id = c("SS-E", "SS-H"), term = c(202260L, 202210L), graduation_status = "Awarded")
  attempts <- test_attempts[rep(1L, 3L), ] %>%
    dplyr::mutate(student_id = c("SS-A", "SS-B", "SS-E"), term = 202260L, campus = c("ABQ", "ABQ", "EA"),
                  subject_course = c("MATH 101", "MATH 101", "HIST 101"))
  list(student_terms = student_terms, spring_students = spring_students, degrees = degrees, attempts = attempts,
       opt = list(min_n = 1L, pace_credits = 15,
                  data_edges = list(last_enrolled_complete = 202310L, last_graded = 202260L, last_degree = 202260L)))
})
