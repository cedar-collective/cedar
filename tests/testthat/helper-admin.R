# What the tests in test-admin.R share: builders, option lists, constants.

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
counting_rule_tables <- function() {
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
}
