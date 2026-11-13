# What the tests in test-data-anomalies.R share: builders, option lists, constants.

# DA01 (local): three programs over 2024-2026, each with 50 majors a term.
#   SEL   50 undergrad majors,  5 grads/yr  -> ratio 10.0, flagged
#   NORM  50 undergrad majors, 25 grads/yr  -> ratio  2.0, not flagged
#   GRAD  45 GRADUATE + 5 undergrad majors, 5 baccalaureate grads/yr
#         -> ratio 1.0 when levels are paired; 10.0 if they are not.
anomaly_ratio_programs <- function() {
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
}

anomaly_ratio_degrees <- function() {
  terms <- c(202410L, 202510L, 202610L)
  build <- function(code, n) {
    tidyr::expand_grid(term = terms, i = seq_len(n)) %>%
      dplyr::transmute(
        student_id = paste0(code, "-grad-", term, "-", i), term, major_code = code,
        award_category = "Baccalaureate Degree"
      )
  }
  dplyr::bind_rows(build("SEL", 5L), build("NORM", 25L), build("GRAD", 5L))
}

# Scaffolding: mapping files for the designed fixture's synthetic institution,
# with one deliberate gap of each kind. BIOL has no subject row; section college
# AS and Translated College EDU name no college; ENGL-BA and FSEC-BS have no
# program row; PSYC has no home college. POLS-BA and BUSA-BBA are mapped to a
# college Banner's Translated College disagrees with -- BUSA-BBA's pre-major
# rows are the expected kind of difference, its others need review.
audit_files <- function() {
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
}
