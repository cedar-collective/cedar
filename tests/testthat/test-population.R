# Tests for population building functions
# Tests build_population() and classify_population_outcomes() from R/branches/population.R

context("Population Building")

# =============================================================================
# Minimal fixture: a cedar_programs-shaped data frame with known values
# =============================================================================
#
# Students and their declared programs (one campus "M"):
#   S001 — Nursing / NURS (Major)            → focal, declared, ongoing       (term 202510)
#   S002 — Public Health / POHE (Major)      → focal, declared, ongoing       (term 202510)
#   S003 — Nursing / FNRS (Major, pre)       → focal, pre-major only → never_declared, entry = "direct" (term 202480)
#   S004 — Nursing / FNRS (Major, pre)       → focal, pre-major only → never_declared, entry = "direct" (term 202480)
#   S005 — History / HIST (Major)            → not focal                       (term 202510)
#   S006 — Nursing / NURS (Second Major)     → focal, declared, ongoing       (term 202510)
#   S007 — Nursing / NURS (Major, non-pre) + Nursing / FNRS (Major, pre)
#          both in same term → declared wins → ongoing, entry = "direct"      (term 202510)
#   S008 — English / ENGL (Major)            → not focal                       (term 202510)
#
# max_data_term = 202510 (most students' last term).
# S003 and S004 are at 202480 (< max_data_term), so they are historical pre-majors
# with outcome = "never_declared". Their entry_method = "first_program" because they had
# no prior program record before their first pre-major term.
# (A pre-major student with last_unit_term == max_data_term would become "ongoing".)
#
# is_pre_major is set at transform time (detect "Pre-" prefix in program_name).
# program_name is normalized: "Pre-Nursing" → "Nursing" so pre-majors share
# the same name as their declared counterpart.

# =============================================================================
# build_population() dispatch
# =============================================================================

test_that("build_population returns data frame with required columns", {
  programs <- population_programs
  result <- build_population(programs,
                             opt = list(type = "preset",
                                        program_names = c("Nursing", "Public Health")))
  expect_s3_class(result, "data.frame")
  expect_true(all(c("student_id", "population_label", "outcome",
                    "origin", "entry_method", "entry_status",
                    "first_unit_term", "last_unit_term", "last_declared_term",
                    "relevant_until") %in% names(result)))
})

test_that("build_population stops on unknown type", {
  programs <- population_programs
  expect_error(
    build_population(programs, opt = list(type = "banana")),
    "not supported|Unknown"
  )
})

test_that("build_population errors without program_names for preset type", {
  programs <- population_programs
  expect_error(
    build_population(programs, opt = list(type = "preset")),
    "program_names is required"
  )
})

test_that("build_population errors on unknown outcome value", {
  programs <- population_programs
  expect_error(
    build_population(programs,
                     opt = list(type = "preset",
                                program_names = "Nursing",
                                outcomes = "banana")),
    "Unknown outcome values"
  )
})


# =============================================================================
# Default outcomes (declared students only — excludes never_declared)
# =============================================================================

test_that("default scope includes declared majors (outcome = ongoing in single-term fixture)", {
  programs <- population_programs
  pop <- build_population(programs,
                          opt = list(type = "preset",
                                     program_names = c("Nursing", "Public Health")))
  # With all records in one term (max_data_term), declared students are "ongoing"
  expect_setequal(pop$student_id, c("S001", "S002", "S006", "S007"))
  expect_true(all(pop$population_label == "preset"))
  expect_true(all(pop$outcome == "ongoing"))
})

test_that("default scope omits pre-major-only students", {
  programs <- population_programs
  pop <- build_population(programs,
                          opt = list(type = "preset",
                                     program_names = c("Nursing", "Public Health")))
  expect_false("S003" %in% pop$student_id)
  expect_false("S004" %in% pop$student_id)
})

test_that("default scope omits students with no focal program", {
  programs <- population_programs
  pop <- build_population(programs,
                          opt = list(type = "preset",
                                     program_names = c("Nursing", "Public Health")))
  expect_false("S005" %in% pop$student_id)
  expect_false("S008" %in% pop$student_id)
})

test_that("Second Major counts as a declared major", {
  programs <- population_programs
  pop <- build_population(programs,
                          opt = list(type = "preset",
                                     program_names = c("Nursing")))
  expect_true("S006" %in% pop$student_id)  # S006 has Nursing as Second Major
})

test_that("one row per student", {
  programs <- population_programs
  pop <- build_population(programs,
                          opt = list(type = "preset",
                                     program_names = c("Nursing", "Public Health")))
  expect_equal(nrow(pop), n_distinct(pop$student_id))
})


# =============================================================================
# outcomes = c("chose_elsewhere", "left_undeclared") — pre-major-only scope
# =============================================================================

test_that("pre-major sub-outcomes give pre-major-only students", {
  programs <- population_programs
  pop <- build_population(programs,
                          opt = list(type = "preset",
                                     program_names = c("Nursing", "Public Health"),
                                     outcomes = c("chose_elsewhere", "left_undeclared")))
  expect_true("S003" %in% pop$student_id)
  expect_true("S004" %in% pop$student_id)
  # S003/S004 never declared elsewhere → left_undeclared
  expect_true(all(pop$outcome %in% c("chose_elsewhere", "left_undeclared")))
})

test_that("pre-major scope excludes declared students", {
  programs <- population_programs
  pop <- build_population(programs,
                          opt = list(type = "preset",
                                     program_names = c("Nursing", "Public Health"),
                                     outcomes = c("chose_elsewhere", "left_undeclared")))
  expect_false("S001" %in% pop$student_id)
  expect_false("S002" %in% pop$student_id)
})

test_that("S007 is not in pre-major scope (has both declared and pre in same term)", {
  programs <- population_programs
  pop <- build_population(programs,
                          opt = list(type = "preset",
                                     program_names = c("Nursing", "Public Health"),
                                     outcomes = c("chose_elsewhere", "left_undeclared")))
  expect_false("S007" %in% pop$student_id)
})


# =============================================================================
# outcomes = all — lump mode equivalent
# =============================================================================

test_that("all outcomes includes both declared and pre-major students", {
  programs <- population_programs
  pop <- build_population(programs,
                          opt = list(type = "preset",
                                     program_names = c("Nursing", "Public Health"),
                                     outcomes = c("ongoing", "chose_elsewhere", "left_undeclared",
                                                  "graduated", "switched_out", "stopped_out")))
  expect_setequal(pop$student_id, c("S001", "S002", "S003", "S004", "S006", "S007"))
})

test_that("all outcomes still excludes non-focal students", {
  programs <- population_programs
  pop <- build_population(programs,
                          opt = list(type = "preset",
                                     program_names = c("Nursing", "Public Health"),
                                     outcomes = c("ongoing", "chose_elsewhere", "left_undeclared",
                                                  "graduated", "switched_out", "stopped_out")))
  expect_false("S005" %in% pop$student_id)
  expect_false("S008" %in% pop$student_id)
})


# =============================================================================
# split_by = "outcome"
# =============================================================================

test_that("split_by = outcome assigns distinct labels per outcome group", {
  programs <- population_programs
  pop <- build_population(programs,
                          opt = list(type = "preset",
                                     program_names = c("Nursing", "Public Health"),
                                     outcomes = c("ongoing", "chose_elsewhere", "left_undeclared",
                                                  "graduated", "switched_out", "stopped_out"),
                                     split_by = "outcome"))
  # All declared are ongoing in this fixture; all pre-only are left_undeclared
  expect_true(all(pop$population_label == pop$outcome))
  expect_true("ongoing" %in% pop$population_label)
  expect_true("left_undeclared" %in% pop$population_label)
})

test_that("split_by = outcome: declared students labeled 'ongoing' in single-term fixture", {
  programs <- population_programs
  pop <- build_population(programs,
                          opt = list(type = "preset",
                                     program_names = c("Nursing", "Public Health"),
                                     outcomes = c("ongoing", "chose_elsewhere", "left_undeclared",
                                                  "graduated", "switched_out", "stopped_out"),
                                     split_by = "outcome"))
  declared_ids <- c("S001", "S002", "S006", "S007")
  declared_labels <- pop$population_label[pop$student_id %in% declared_ids]
  expect_true(all(declared_labels == "ongoing"))
})


# =============================================================================
# split_by = "entry"
# =============================================================================

test_that("split_by = entry assigns entry_method as label", {
  programs <- population_programs
  pop <- build_population(programs,
                          opt = list(type = "preset",
                                     program_names = c("Nursing", "Public Health"),
                                     outcomes = c("ongoing", "chose_elsewhere", "left_undeclared",
                                                  "graduated", "switched_out", "stopped_out"),
                                     split_by = "entry"))
  expect_true(all(pop$population_label == pop$entry_method))
})

test_that("S007 gets entry_method = first_program, entry_status = major", {
  programs <- population_programs
  pop <- build_population(programs,
                          opt = list(type = "preset",
                                     program_names = c("Nursing", "Public Health"),
                                     outcomes = c("ongoing", "chose_elsewhere", "left_undeclared",
                                                  "graduated", "switched_out", "stopped_out"),
                                     split_by = "entry"))
  s007 <- pop[pop$student_id == "S007", ]
  expect_equal(s007$entry_method, "first_program")
  expect_equal(s007$entry_status, "major")
  expect_equal(nrow(s007), 1)
})

test_that("S003 and S004 (left_undeclared) get entry_method = first_program, entry_status = pre_major", {
  # S003 and S004 are historical pre-majors with no prior program record of any kind.
  programs <- population_programs
  pop <- build_population(programs,
                          opt = list(type = "preset",
                                     program_names = c("Nursing", "Public Health"),
                                     outcomes = c("ongoing", "chose_elsewhere", "left_undeclared",
                                                  "graduated", "switched_out", "stopped_out"),
                                     split_by = "entry"))
  s003 <- pop[pop$student_id == "S003", ]
  s004 <- pop[pop$student_id == "S004", ]
  expect_equal(s003$entry_method, "first_program")
  expect_equal(s003$entry_status, "pre_major")
  expect_equal(s004$entry_method, "first_program")
  expect_equal(s004$entry_status, "pre_major")
})

test_that("split_by = entry_status distinguishes declared majors from pre-majors", {
  programs <- population_programs
  pop <- build_population(programs,
                          opt = list(type = "preset",
                                     program_names = c("Nursing", "Public Health"),
                                     outcomes = c("ongoing", "chose_elsewhere", "left_undeclared",
                                                  "graduated", "switched_out", "stopped_out"),
                                     split_by = "entry_status"))

  expect_true(all(pop$population_label == pop$entry_status))
  expect_true("major" %in% pop$population_label)
  expect_true("pre_major" %in% pop$population_label)
})

test_that("entry_method values are only first_program, switched_in, or unclear", {
  programs <- population_programs
  pop <- build_population(programs,
                          opt = list(type = "preset",
                                     program_names = c("Nursing", "Public Health"),
                                     outcomes = c("ongoing", "chose_elsewhere", "left_undeclared",
                                                  "graduated", "switched_out", "stopped_out")))
  expect_true(all(pop$entry_method %in% c("first_program", "switched_in", "unclear")))
})

test_that("students at min_data_term get entry_method = unclear", {
  # Left-truncation detection: a student whose first_unit_term == min(programs$term)
  # appears "first_program" only because we can't see earlier program records.
  # Build a fixture where the focal student's only record is at the earliest term.
  trunc_programs <- tibble(
    student_id         = c("TRUNC", "ANCHOR"),
    term               = c(202010L,  202010L),
    student_campus     = c("M", "M"),
    student_college    = c("AS", "AS"),
    program_type       = c("Major", "Major"),
    program_name       = c("History", "English"),
    major_code         = c("HIST", "ENGL"),
    dept_code          = c("HIST", "ENGL"),
    is_pre_major       = c(FALSE, FALSE),
    student_population = c("Continuing Student", "Continuing Student")
  )
  pop <- build_population(trunc_programs,
                          opt = list(type = "preset", program_names = "History"))
  trunc_row <- pop[pop$student_id == "TRUNC", ]
  expect_equal(trunc_row$entry_method, "unclear")
})

test_that("no duplicate student IDs in split_by = entry mode", {
  programs <- population_programs
  pop <- build_population(programs,
                          opt = list(type = "preset",
                                     program_names = c("Nursing", "Public Health"),
                                     outcomes = c("ongoing", "chose_elsewhere", "left_undeclared",
                                                  "graduated", "switched_out", "stopped_out"),
                                     split_by = "entry"))
  expect_equal(nrow(pop), n_distinct(pop$student_id))
})


# =============================================================================
# relevant_until column
# =============================================================================

test_that("ongoing students have relevant_until = NA", {
  programs <- population_programs
  pop <- build_population(programs,
                          opt = list(type = "preset",
                                     program_names = c("Nursing", "Public Health")))
  ongoing <- pop[pop$outcome == "ongoing", ]
  expect_true(all(is.na(ongoing$relevant_until)))
})

test_that("pre-major-only students have relevant_until = their last pre-major term", {
  programs <- population_programs
  pop <- build_population(programs,
                          opt = list(type = "preset",
                                     program_names = c("Nursing", "Public Health"),
                                     outcomes = c("chose_elsewhere", "left_undeclared")))
  nd <- pop[pop$outcome %in% c("chose_elsewhere", "left_undeclared"), ]
  expect_true(all(!is.na(nd$relevant_until)))
  expect_true(all(nd$relevant_until == 202480L))  # S003/S004 last seen at 202480
})


test_that("current pre-major (last_unit_term == max_data_term) gets outcome = ongoing", {
  # STU-HP-SP2-001 is a HIST pre-major in 202110 = max_data_term(test_programs)
  # → hasn't had a chance to declare yet → should be "ongoing", not a pre-major sub-outcome
  pop <- build_population(test_programs,
                          opt = list(type = "preset",
                                     program_names = "History",
                                     outcomes = c("ongoing", "chose_elsewhere", "left_undeclared",
                                                  "graduated", "switched_out", "stopped_out")))
  expect_equal(pop$outcome[pop$student_id == "STU-HP-SP2-001"], "ongoing")
})

test_that("historical pre-major (last_unit_term < max_data_term) gets left_undeclared", {
  # STU-HP-FA1-001 is a HIST pre-major in 202080 < max_data_term 202110
  # → never declared elsewhere → left_undeclared
  pop <- build_population(test_programs,
                          opt = list(type = "preset",
                                     program_names = "History",
                                     outcomes = c("chose_elsewhere", "left_undeclared")))
  expect_equal(pop$outcome[pop$student_id == "STU-HP-FA1-001"], "left_undeclared")
})


# =============================================================================
# Graduation detection via degrees
# =============================================================================

test_that("student with matching degree in last focal term gets outcome = graduated", {
  programs <- population_programs
  degrees  <- population_degrees  # S001 graduated with NURS in 202510

  # Add a second term so 202510 is no longer max_data_term — otherwise everyone is ongoing
  programs2 <- bind_rows(
    programs,
    tibble(
      student_id = "S002", term = 202580L, student_campus = "M",
      student_college = "PO", program_type = "Major",
      program_name = "Public Health", major_code = "POHE",
      dept_code = "POHE", is_pre_major = FALSE
    )
  )

  pop <- build_population(programs2, degrees = degrees,
                          opt = list(type = "preset",
                                     program_names = c("Nursing", "Public Health"),
                                     outcomes = c("graduated", "switched_out", "stopped_out", "ongoing")))

  # S001: last focal term = 202510, has NURS degree in 202510 → graduated
  s001_outcome <- pop$outcome[pop$student_id == "S001"]
  expect_equal(s001_outcome, "graduated")
})


# =============================================================================
# Switched_out detection via students table
# =============================================================================

test_that("student whose last focal term < max_data_term (no declared switch) gets stopped_out", {
  # STU-HD-SP1-005 is HIST declared in 202010 only — no degree, no later major → stopped_out
  # STU-HD-SP2-001 is HIST declared in 202110 = max_data_term → ongoing
  pop <- build_population(test_programs,
                          opt = list(type = "preset",
                                     program_names = "History",
                                     outcomes = c("graduated", "switched_out", "stopped_out", "ongoing")))
  expect_equal(pop$outcome[pop$student_id == "STU-HD-SP1-005"], "stopped_out")
  expect_equal(pop$outcome[pop$student_id == "STU-HD-SP2-001"], "ongoing")
})


# =============================================================================
# switched_in entry pathway
# =============================================================================

test_that("student who switched from non-focal to focal gets entry_method = switched_in", {
  # STU-ENGL-HIST-001: English (202010) → History (202110) → switched_in for HIST population
  pop <- build_population(test_programs,
                          opt = list(type = "preset",
                                     program_names = "History"))
  expect_equal(pop$entry_method[pop$student_id == "STU-ENGL-HIST-001"], "switched_in")
})


# =============================================================================
# Campus filter
# =============================================================================

test_that("campus filter restricts cohort to specified campus", {
  programs <- population_programs
  pop <- build_population(programs,
                          opt = list(type = "preset",
                                     program_names = c("Nursing", "Public Health"),
                                     campus = "V"))
  expect_equal(nrow(pop), 0)
})

test_that("campus and level scope candidate membership without truncating history", {
  programs <- tibble::tibble(
    student_id = c("SCOPE", "SCOPE", "OUT"),
    term = c(202410L, 202510L, 202510L),
    student_campus = c("M", "V", "V"),
    student_college = "AS",
    student_level = c("Undergraduate", "Graduate", "Undergraduate"),
    program_type = "Major",
    program_name = c("History", "English", "History"),
    major_code = c("HIST", "ENGL", "HIST"),
    dept_code = c("HIST", "ENGL", "HIST"),
    is_pre_major = FALSE,
    student_population = "Continuing Student"
  )

  pop <- build_population(
    programs,
    opt = list(
      type = "major", program_names = "History", campus = "M",
      student_level = "Undergraduate",
      outcomes = c("ongoing", "graduated", "switched_out", "stopped_out")
    )
  )

  expect_equal(pop$student_id, "SCOPE")
  expect_equal(pop$outcome, "switched_out")
  expect_equal(pop$last_unit_term, 202410L)
})

test_that("demographic populations honor level and carry enrollment bookends", {
  programs <- tibble::tibble(
    student_id = c("D1", "D1", "D2"),
    term = c(202010L, 202110L, 202010L),
    student_campus = c("M", "V", "M"),
    student_level = c("Undergraduate", "Graduate", "Graduate"),
    pell_eligible = c(TRUE, FALSE, TRUE)
  )
  # cedar_student_terms-shaped: D1's 202280 row is a waitlist, not an enrolled
  # term, so it is not a bookend.
  student_terms <- tibble::tibble(
    student_id = c("D1", "D1", "D1", "D2"),
    term = c(201980L, 202180L, 202280L, 202010L),
    enrolled = c(TRUE, TRUE, FALSE, TRUE)
  )

  pop <- build_population(
    programs,
    student_terms = student_terms,
    opt = list(
      type = "demographic", pell_eligible = TRUE, campus = "M",
      student_level = "Undergraduate"
    )
  )

  expect_equal(pop$student_id, "D1")
  expect_equal(pop$first_unm_term, 201980L)
  expect_equal(pop$last_record_term, 202180L)
  expect_true(all(c("first_unit_term", "last_unit_term", "relevant_until") %in% names(pop)))

  # cedar_registrations handed in the table's place would count every class-list
  # row as a term at UNM; it is refused by column.
  expect_error(
    build_population(programs, student_terms = student_terms %>% select(-enrolled),
                     opt = list(type = "demographic", pell_eligible = TRUE)),
    "Pass cedar_student_terms"
  )
})


# =============================================================================
# Enrollment evidence comes from cedar_student_terms (ADR-001 step 2)
# =============================================================================
#
# ST01 (test_programs_st / test_student_terms_st): every student declared HIST
# in 202010, ST_I in 202110 (the last term) and ST_E again in 202080. A
# candidate for stopped_out is switched_out when enrolled at UNM after the
# last focal term, and `enrolled` is the table's: a late withdrawal counts
# (ST_A), a waitlist (ST_C) or an early drop (ST_B) does not. Before the move
# any class-list row counted, so ST_B and ST_C read as switched_out.

test_that("enrollment-based switch detection and the UNM bookends read enrolled student-terms", {
  pop <- suppressMessages(build_population(
    test_programs_st, degrees = test_degrees_st, student_terms = test_student_terms_st,
    opt = list(type = "major", program_names = "HIST")
  ))
  outcome <- setNames(pop$outcome, pop$student_id)

  expect_equal(outcome[["ST_I"]], "ongoing")
  expect_equal(outcome[["ST_J"]], "graduated")
  expect_equal(outcome[["ST_A"]], "switched_out")   # only a DW in 202080: enrolled
  expect_equal(outcome[["ST_D"]], "switched_out")   # registered in Summer 2020
  expect_equal(outcome[["ST_B"]], "stopped_out")    # only a DR in 202080: not enrolled
  expect_equal(outcome[["ST_C"]], "stopped_out")    # only WL in 202080: not enrolled
  expect_equal(outcome[["ST_H"]], "stopped_out")

  bookend <- pop %>% filter(student_id %in% c("ST_A", "ST_B", "ST_C"))
  expect_equal(bookend$first_unm_term, rep(202010L, 3))
  expect_equal(setNames(bookend$last_record_term, bookend$student_id),
               c(ST_A = 202080L, ST_B = 202010L, ST_C = 202010L))

  # Without the table: no reclassification, NA bookends, never a guess.
  bare <- suppressMessages(build_population(
    test_programs_st, degrees = test_degrees_st,
    opt = list(type = "major", program_names = "HIST")
  ))
  expect_equal(bare$outcome[bare$student_id == "ST_A"], "stopped_out")
  expect_true(all(is.na(bare$first_unm_term)))
})


# =============================================================================
# Dept type
# =============================================================================

test_that("dept type builds population from dept_code", {
  programs <- population_programs
  pop <- build_population(programs, opt = list(type = "dept", dept_code = "NURS"))
  # S001, S006, S007 have dept_code NURS and !is_pre_major
  expect_true("S001" %in% pop$student_id)
  expect_true("S006" %in% pop$student_id)
  expect_false("S005" %in% pop$student_id)
})

test_that("dept type uses dept code as label", {
  programs <- population_programs
  pop <- build_population(programs, opt = list(type = "dept", dept_code = "NURS"))
  expect_true(all(pop$population_label == "NURS"))
})


# =============================================================================
# origin detection
# =============================================================================

test_that("origin column is present in result", {
  programs <- population_programs
  pop <- build_population(programs,
                          opt = list(type = "preset",
                                     program_names = c("Nursing", "Public Health")))
  expect_true("origin" %in% names(pop))
})

test_that("S002 (Transfer Student) gets origin = 'transfer'", {
  programs <- population_programs
  pop <- build_population(programs,
                          opt = list(type = "preset",
                                     program_names = c("Nursing", "Public Health")))
  expect_equal(pop$origin[pop$student_id == "S002"], "transfer")
})

test_that("S001 (Continuing Student) gets origin = 'unm'", {
  programs <- population_programs
  pop <- build_population(programs,
                          opt = list(type = "preset",
                                     program_names = c("Nursing", "Public Health")))
  expect_equal(pop$origin[pop$student_id == "S001"], "unm")
})

test_that("missing student_population column yields origin = 'unknown'", {
  programs <- population_programs %>% select(-student_population)
  pop <- build_population(programs,
                          opt = list(type = "preset",
                                     program_names = c("Nursing", "Public Health")))
  expect_true(all(pop$origin == "unknown"))
})

test_that("split_by = transfer sets population_label to origin", {
  programs <- population_programs
  pop <- build_population(programs,
                          opt = list(type = "preset",
                                     program_names = c("Nursing", "Public Health"),
                                     split_by = "transfer"))
  expect_true(all(pop$population_label == pop$origin))
  expect_true("transfer" %in% pop$population_label)
  expect_true("unm" %in% pop$population_label)
})
