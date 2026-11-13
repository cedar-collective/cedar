# What the tests in test-stopout.R share: builders, option lists, constants.

# cedar_attempts as production builds it from a CRN-level class-list fixture:
# the transform's dedup (one row per student, course, campus and term), keyed
# on the course, classified to the graded edge.
fixture_attempts <- function(students, last_graded) {
  rows <- load_transform_helpers()$dedup_class_list_rows(students)
  build_attempts(attach_test_course_ids(rows, "students"), list(last_graded = last_graded))
}

# Fixtures here are deliberately local: these are intermediate frames (a graded
# term, a pre-joined stopout group) that are one function's input contract
# rather than domain data. See the rule in AGENTS.md.
make_grade_data <- function() {
  tibble(
    student_id               = paste0("S", sprintf("%03d", 1:12)),
    term                     = rep(202510, 12),
    campus                   = rep("ABQ", 12),
    subject_course           = rep("BIOL 2310", 12),
    final_grade              = c("A", "F", "W", "D-", "C", "W", "I", "AUD", "RB", "RF", "W", ""),
    registration_status_code = c("RE", "RE", "RE", "RE", "RE", "DR", "RE", "RE", "RE", "RE", "DW", "DG")
  )
}

make_stopout_group <- function() {
  # stopped_out is pre-joined by get_stopout() before the per-course loop;
  # tests must supply it directly (derived from returned_next_term logic).
  #   S001: pass, returned     → stopped_out = FALSE
  #   S002: pass, did NOT return → stopped_out = TRUE
  #   S003: dfw,  returned     → stopped_out = FALSE
  #   S004: dfw,  did NOT return → stopped_out = TRUE
  #   S005: dfw,  did NOT return → stopped_out = TRUE
  #   S006: pass, returned     → stopped_out = FALSE
  tibble(
    student_id     = c("S001", "S002", "S003", "S004", "S005", "S006"),
    term           = rep(202510, 6),
    subject_course = rep("BIOL 2310", 6),
    outcome        = c("pass", "pass", "dfw", "dfw", "dfw", "pass"),
    stopped_out    = c(FALSE, TRUE, FALSE, TRUE, TRUE, FALSE)
  )
}

make_stopout_students <- function() {
  # All rows at 202480 = the graded term; "return" rows at 202510
  tibble(
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
}

make_stopout_population <- function() {
  tibble(
    student_id       = c("C001", "C002", "C003", "C004", "C005", "C006"),
    population_label = "bio_majors"
  )
}

# The student-term rows get_stopout() reads for these students: the 202480
# anchors, judged into Fall-to-Spring 202510. Hand-written to the same shape as
# cedar_student_terms because make_stopout_students() is an intermediate frame,
# not a fixture the production builder can read.
make_stopout_terms <- function() {
  returned <- c("C001", "C002", "C004", "B001", "B002", "B004")
  ids <- c(paste0("C00", 1:6), paste0("B00", 1:5))
  bind_rows(
    tibble(student_id = ids, term = 202480L, enrolled = TRUE,
           returned_next_regular_term = ids %in% returned, return_observable = TRUE),
    tibble(student_id = returned, term = 202510L, enrolled = TRUE,
           returned_next_regular_term = NA, return_observable = FALSE)
  )
}

# EC-12: a student contributes once per course/campus, before thresholds or tests.
roadblocks_population <- function() {
  test_students_roadblocks %>%
    filter(grepl("^RB_P", student_id)) %>% distinct(student_id) %>%
    mutate(population_label = "Roadblocks fixture")
}

roadblocks_options <- function() {
  list(subject_code = "ECON", min_n = 1L, min_dfw_n = 0L,
       graded_through = 202110L, observation_end_term = 202110L)
}
