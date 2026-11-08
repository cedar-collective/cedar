# Tests for stop-out analysis functions
# Tests classify_outcomes() and compute_stopout_for_group() from R/cones/stopout.R
#
# Note: get_stopout() depends on add_next_term_col() from R/trunk/utils.R.
# Integration tests below also exercise the full function and its eligibility rules.
# These unit tests cover the pure helper functions that can be tested in isolation.

library(tibble)
library(dplyr)

context("Stopout: Stop-Out Analysis")

# cedar_attempts as production builds it from a CRN-level class-list fixture:
# the transform's dedup (one row per student, course, campus and term), keyed
# on the course, classified to the graded edge.
fixture_attempts <- function(students, last_graded) {
  rows <- load_transform_helpers()$dedup_class_list_rows(students)
  build_attempts(attach_test_course_ids(rows, "students"), list(last_graded = last_graded))
}

test_that("Roadblocks refuses attempts this build did not make and agrees with raw AUD exclusions", {
  students <- test_students_audits
  population <- students %>% distinct(student_id) %>% mutate(population_label = "EC09")
  opt <- list(min_n = 1L, min_dfw_n = 1L, campus = "ABQ", observation_end_term = 202110L)

  # A hand-classified frame, or a table built under another policy, is refused.
  unbuilt <- classify_enrollment_outcomes(students) %>%
    select(student_id, term, subject_course, outcome, campus, level)
  expect_error(get_dfw_rates(students, population, opt, attempts = unbuilt), "not built by build_attempts")
  saved <- fixture_attempts(students, 202110L)
  stale <- saved
  attr(stale, "cedar_outcome_policy_version") <- 0L
  expect_error(get_stopout(students, population, opt = opt, attempts = stale,
                           student_terms = test_student_terms_audits), "outcome policy")

  # Pathways windows this table before calling the cones: the stamp must survive.
  saved <- apply_pathways_population_window(
    saved, population %>% mutate(relevant_until = 202080L), analysis_through = 202110L
  ) %>% filter(campus == "ABQ")
  raw_rates <- get_dfw_rates(students, population, opt)
  saved_rates <- get_dfw_rates(students, population, opt, attempts = saved)
  expect_equal(saved_rates, raw_rates, ignore_attr = TRUE)
  expect_equal(saved_rates$pop_n_graded, 5L)
  expect_equal(saved_rates$pop_n_dfw, 4L)
  expect_equal(saved_rates$pop_dfw_rate, 0.8)

  raw_stopout <- get_stopout(students, population, opt = opt,
                             student_terms = test_student_terms_audits)
  saved_stopout <- get_stopout(students, population, opt = opt, attempts = saved,
                               student_terms = test_student_terms_audits)
  expect_equal(saved_stopout, raw_stopout, ignore_attr = TRUE)
  expect_equal(saved_stopout$by_course$pop_n_dfw, 4L)
  expect_equal(saved_stopout$by_course$pop_n_pass, 1L)
})


# =============================================================================
# classify_outcomes()
# =============================================================================
#
# Test data (canonical DFW policy — see AGENTS.md "CEDAR-wide DFW policy"):
#   S001 — registered, got A         → pass
#   S002 — registered, got F         → dfw
#   S003 — registered, got W         → dfw
#   S004 — registered, got D-        → dfw
#   S005 — registered, got C         → pass
#   S006 — early drop (DR)           → EXCLUDED (early drops are never DFW)
#   S007 — registered, got I (incomplete) → dfw
#   S008 — registered, got AUD       → excluded (ungraded)
#   S009 — registered, got RB (repeat pass) → pass
#   S010 — registered, got RF (repeat fail) → dfw
#   S011 — late drop (DW), grade W   → dfw (the W in DFW)
#   S012 — late drop (DG), blank grade → dfw (status alone carries the W)

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

test_that("classify_outcomes returns required columns", {
  result <- classify_outcomes(make_grade_data())

  expect_true("student_id"     %in% names(result))
  expect_true("term"           %in% names(result))
  expect_true("subject_course" %in% names(result))
  expect_true("outcome"        %in% names(result))
})

test_that("classify_outcomes only returns pass and dfw values", {
  result <- classify_outcomes(make_grade_data())
  expect_true(all(result$outcome %in% c("pass", "dfw")))
})

test_that("classify_outcomes correctly labels passing grades", {
  result <- classify_outcomes(make_grade_data())
  pass_ids <- result$student_id[result$outcome == "pass"]
  # S001 (A), S005 (C), S009 (RB)
  expect_true("S001" %in% pass_ids)
  expect_true("S005" %in% pass_ids)
  expect_true("S009" %in% pass_ids)
})

test_that("classify_outcomes correctly labels DFW grades", {
  result <- classify_outcomes(make_grade_data())
  dfw_ids <- result$student_id[result$outcome == "dfw"]
  # S002 (F), S003 (W), S004 (D-), S007 (I), S010 (RF)
  expect_true("S002" %in% dfw_ids)
  expect_true("S003" %in% dfw_ids)
  expect_true("S004" %in% dfw_ids)
  expect_true("S007" %in% dfw_ids)
  expect_true("S010" %in% dfw_ids)
})

test_that("classify_outcomes excludes early drops (DR) entirely", {
  # CEDAR-wide DFW policy: an early drop posts no grade and is never DFW.
  result <- classify_outcomes(make_grade_data())
  expect_false("S006" %in% result$student_id)
})

test_that("classify_outcomes counts late drops (DG/DW) as DFW", {
  # Late drops are the registration-status form of a W — most withdrawals
  # post as DG/DW status rows, not as W grades under a registered status.
  result <- classify_outcomes(make_grade_data())
  s011 <- result %>% filter(student_id == "S011")  # DW + W grade
  s012 <- result %>% filter(student_id == "S012")  # DG + blank grade
  expect_equal(s011$outcome, "dfw")
  expect_equal(s012$outcome, "dfw")
})

test_that("classify_outcomes excludes blank and audit records", {
  result <- classify_outcomes(make_grade_data())
  # I is a recorded nonpassing outcome; AUD is explicitly excluded.
  expect_equal(result$outcome[result$student_id == "S007"], "dfw")
  expect_false("S008" %in% result$student_id)
})

test_that("classify_outcomes returns empty df on empty input", {
  empty <- make_grade_data()[0, ]
  result <- classify_outcomes(empty)
  expect_equal(nrow(result), 0)
})


# =============================================================================
# compute_stopout_for_group()
# =============================================================================
#
# Test data: 6 students in BIOL 2310, term 202510
#   S001 — pass, returned next term
#   S002 — pass, did NOT return
#   S003 — dfw,  returned next term
#   S004 — dfw,  did NOT return
#   S005 — dfw,  did NOT return
#   S006 — pass, returned next term
#
# Expected:
#   n_pass = 3 (S001, S002, S006)
#   n_dfw  = 3 (S003, S004, S005)
#   pass_stopout_rate = 1/3 ≈ 0.333 (S002 didn't return)
#   dfw_stopout_rate  = 2/3 ≈ 0.667 (S004, S005 didn't return)
#   stopout_gap = 1/3 (dfw - pass)

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

test_that("compute_stopout_for_group returns correct column names", {
  result <- compute_stopout_for_group(make_stopout_group(), prefix = "cohort")
  expected_cols <- c("cohort_n_dfw", "cohort_n_pass",
                     "cohort_dfw_stopout_rate", "cohort_pass_stopout_rate",
                     "cohort_stopout_gap", "cohort_p_value")
  expect_true(all(expected_cols %in% names(result)))
})

test_that("compute_stopout_for_group counts pass and dfw students correctly", {
  result <- compute_stopout_for_group(make_stopout_group(), prefix = "cohort")
  expect_equal(result$cohort_n_pass, 3)
  expect_equal(result$cohort_n_dfw,  3)
})

test_that("compute_stopout_for_group computes correct stop-out rates", {
  result <- compute_stopout_for_group(make_stopout_group(), prefix = "cohort")
  expect_equal(result$cohort_pass_stopout_rate, 1/3)
  expect_equal(result$cohort_dfw_stopout_rate,  2/3)
})

test_that("compute_stopout_for_group stopout_gap is positive when dfw stops out more", {
  result <- compute_stopout_for_group(make_stopout_group(), prefix = "cohort")
  # dfw_stopout_rate > pass_stopout_rate, so gap should be positive
  expect_gt(result$cohort_stopout_gap, 0)
  # Preserve raw proportions through the gap and downstream ranking.
  expect_equal(result$cohort_stopout_gap, 2/3 - 1/3)
})

test_that("compute_stopout_for_group uses prefix correctly for baseline", {
  result <- compute_stopout_for_group(make_stopout_group(), prefix = "baseline")
  expect_true("baseline_n_dfw"  %in% names(result))
  expect_true("baseline_n_pass" %in% names(result))
  expect_false("cohort_n_dfw"   %in% names(result))
})

test_that("compute_stopout_for_group returns NA row for empty input", {
  empty_group <- make_stopout_group()[0, ]
  result <- compute_stopout_for_group(empty_group, prefix = "cohort")
  expect_equal(nrow(result), 1)
  expect_true(is.na(result$cohort_n_dfw))
})

test_that("roadblock ranking does not turn a missing baseline into zero", {
  rows <- tibble::tibble(
    campus = c("ABQ", "ABQ"),
    subject_course = c("HIST 100", "HIST 200"),
    pop_stopout_gap = c(0.4, 0.3),
    baseline_stopout_gap = c(NA_real_, 0.1),
    pop_n_dfw = c(20L, 10L)
  )

  result <- prepare_roadblock_results(rows)
  missing_baseline <- dplyr::filter(result, subject_course == "HIST 100")
  estimable <- dplyr::filter(result, subject_course == "HIST 200")

  expect_true(is.na(missing_baseline$excess_gap))
  expect_true(is.na(missing_baseline$impact_score))
  expect_equal(estimable$excess_gap, 0.2)
  expect_equal(estimable$impact_score, 2)
  expect_equal(result$subject_course[[1]], "HIST 200")
})

test_that("compute_stopout_for_group skips chi-sq when group too small", {
  # Only 2 DFW students — below the 5-student threshold for chi-sq
  small_group <- tibble(
    student_id     = c("S001", "S002", "S003"),
    term           = rep(202510, 3),
    subject_course = rep("BIOL 2310", 3),
    outcome        = c("pass", "dfw", "dfw"),
    stopped_out    = c(FALSE, TRUE, FALSE)
  )
  result <- compute_stopout_for_group(small_group, prefix = "cohort")
  expect_true(is.na(result$cohort_p_value))
})


# =============================================================================
# get_stopout() integration tests
# =============================================================================
#
# Fixture: BIOL 2310 at term 202480 with exactly hand-calculated stop-out rates.
# next-term return (add_next_term_col, no summer):
#   202410 (Spring SS=10) → next = 202410 + 70 = 202480
#   202480 (Fall  SS=80) → next = 202480 + 30 = 202510
#   202510 (Spring SS=10) → next = 202510 + 70 = 202580 (not in fixture → stopped out)
#
# Cohort students (C001–C006) in BIOL 2310 at 202480:
#   C001: grade=A (pass), enrolled at 202510 → returned   → stopped_out=FALSE
#   C002: grade=B (pass), enrolled at 202510 → returned   → stopped_out=FALSE
#   C003: grade=C (pass), NO 202510 record   → not returned → stopped_out=TRUE
#   C004: grade=F (dfw),  enrolled at 202510 → returned   → stopped_out=FALSE
#   C005: grade=W (dfw),  NO 202510 record   → not returned → stopped_out=TRUE
#   C006: grade=D (dfw),  NO 202510 record   → not returned → stopped_out=TRUE
#
# Expected cohort stats:
#   pop_n_pass = 3, pop_n_dfw = 3
#   pop_pass_stopout_rate = 1/3 = 0.333   (C003 stopped out)
#   pop_dfw_stopout_rate  = 2/3 = 0.667   (C005, C006 stopped out)
#   pop_stopout_gap       = 1/3 = 0.333
#
# Baseline students (B001–B005) in BIOL 2310 at 202480:
#   B001: grade=A  (pass), returned  → stopped_out=FALSE
#   B002: grade=B+ (pass), returned  → stopped_out=FALSE
#   B003: grade=W  (dfw),  NOT returned → stopped_out=TRUE
#   B004: grade=F  (dfw),  returned  → stopped_out=FALSE
#   B005: grade=C  (pass), NOT returned → stopped_out=TRUE
#
# Expected baseline stats:
#   baseline_n_pass = 3, baseline_n_dfw = 2
#   baseline_pass_stopout_rate = 1/3 = 0.333   (B005 stopped out)
#   baseline_dfw_stopout_rate  = round(1/2, 3) = 0.5     (B003 stopped out)
#   baseline_stopout_gap       = round(1/6, 3) = 0.167

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

test_that("a return that cannot be observed is omitted and counted, never a stop-out", {
  terms <- make_stopout_terms()
  # C003 did not come back, but suppose its next term were past the settled edge.
  terms$return_observable[terms$student_id == "C003" & terms$term == 202480L] <- FALSE
  terms$returned_next_regular_term[terms$student_id == "C003" & terms$term == 202480L] <- NA
  result <- suppressMessages(get_stopout(
    make_stopout_students(), make_stopout_population(), student_terms = terms,
    opt = list(min_n = 1L, min_dfw_n = 1L)
  ))
  row <- result$by_course[result$by_course$subject_course == "BIOL 2310", ]
  expect_equal(row$pop_n_pass, 2L)             # C001, C002: C003 is neither
  expect_equal(row$pop_pass_stopout_rate, 0)
  expect_equal(result$observation_info$n_return_unobservable, 1L)
  expect_match(result$observation_info$note, "1 observations omitted")
})

test_that("get_stopout needs the student-term table, with a row for every graded student-term", {
  expect_error(
    get_stopout(make_stopout_students(), make_stopout_population(), opt = list(min_n = 1L)),
    "student_terms"
  )
  expect_error(
    get_stopout(make_stopout_students(), make_stopout_population(), opt = list(min_n = 1L),
                student_terms = dplyr::filter(make_stopout_terms(), student_id != "C001")),
    "no row on the student-term table"
  )
})

test_that("stop-out anchors require a complete following regular term", {
  result <- suppressMessages(get_stopout(
    make_stopout_students(),
    student_terms = make_stopout_terms(),
    make_stopout_population(),
    opt = list(
      min_n = 5L, min_dfw_n = 2L,
      graded_through = 202480L,
      observation_end_term = 202480L
    )
  ))

  expect_equal(nrow(result$by_course), 0L)
  expect_true(all(is.na(result$term_range)))
})

test_that("get_stopout returns correct top-level structure", {
  result <- get_stopout(
    make_stopout_students(),
    student_terms = make_stopout_terms(),
    make_stopout_population(),
    opt = list(min_n = 5, min_dfw_n = 2)
  )

  expect_type(result, "list")
  expect_true("by_course"       %in% names(result))
  expect_true("population_size" %in% names(result))
  expect_s3_class(result$by_course, "data.frame")
})

test_that("get_stopout population_size matches cohort input", {
  result <- get_stopout(
    make_stopout_students(),
    student_terms = make_stopout_terms(),
    make_stopout_population(),
    opt = list(min_n = 5, min_dfw_n = 2)
  )
  expect_equal(result$population_size, 6L)
})

test_that("get_stopout BIOL 2310 cohort: n_pass=3 and n_dfw=3", {
  result  <- get_stopout(
    make_stopout_students(),
    student_terms = make_stopout_terms(),
    make_stopout_population(),
    opt = list(min_n = 5, min_dfw_n = 2)
  )
  biol <- result$by_course[result$by_course$subject_course == "BIOL 2310", ]

  expect_equal(nrow(biol), 1)
  expect_equal(biol$pop_n_pass, 3L)
  expect_equal(biol$pop_n_dfw,  3L)
})

test_that("get_stopout BIOL 2310 cohort: correct pass and DFW stop-out rates", {
  # pop pass: C003 stopped out (1 of 3) → 0.333
  # pop dfw:  C005, C006 stopped out (2 of 3) → 0.667
  result <- get_stopout(
    make_stopout_students(),
    student_terms = make_stopout_terms(),
    make_stopout_population(),
    opt = list(min_n = 5, min_dfw_n = 2)
  )
  biol <- result$by_course[result$by_course$subject_course == "BIOL 2310", ]

  expect_equal(biol$pop_pass_stopout_rate, 1/3)
  expect_equal(biol$pop_dfw_stopout_rate,  2/3)
})

test_that("get_stopout BIOL 2310 cohort: stop-out gap = dfw_rate - pass_rate", {
  result <- get_stopout(
    make_stopout_students(),
    student_terms = make_stopout_terms(),
    make_stopout_population(),
    opt = list(min_n = 5, min_dfw_n = 2)
  )
  biol <- result$by_course[result$by_course$subject_course == "BIOL 2310", ]

  expect_equal(biol$pop_stopout_gap, 1/3)
})

test_that("get_stopout BIOL 2310 baseline: n_pass=3 and n_dfw=2", {
  result <- get_stopout(
    make_stopout_students(),
    student_terms = make_stopout_terms(),
    make_stopout_population(),
    opt = list(min_n = 5, min_dfw_n = 2)
  )
  biol <- result$by_course[result$by_course$subject_course == "BIOL 2310", ]

  expect_equal(biol$baseline_n_pass, 3L)
  expect_equal(biol$baseline_n_dfw,  2L)
})

test_that("get_stopout BIOL 2310 baseline: correct stop-out rates", {
  # baseline pass: B005 stopped out (1 of 3) → 0.333
  # baseline dfw:  B003 stopped out (1 of 2) → 0.5
  result <- get_stopout(
    make_stopout_students(),
    student_terms = make_stopout_terms(),
    make_stopout_population(),
    opt = list(min_n = 5, min_dfw_n = 2)
  )
  biol <- result$by_course[result$by_course$subject_course == "BIOL 2310", ]

  expect_equal(biol$baseline_pass_stopout_rate, 1/3)
  expect_equal(biol$baseline_dfw_stopout_rate,  round(1/2, 3))
  expect_equal(biol$baseline_stopout_gap,        1/2 - 1/3)
})

test_that("get_stopout stops when population missing required columns", {
  bad_pop <- tibble(student_id = c("C001", "C002"))  # missing population_label
  expect_error(
    get_stopout(make_stopout_students(), bad_pop, opt = list(min_n = 1),
                student_terms = make_stopout_terms()),
    "population_label"
  )
})

test_that("get_stopout respects opt$min_n threshold", {
  # min_n=10 should exclude BIOL 2310 (only 6 cohort students)
  result <- get_stopout(
    make_stopout_students(),
    student_terms = make_stopout_terms(),
    make_stopout_population(),
    opt = list(min_n = 10)
  )
  expect_equal(nrow(result$by_course), 0)
})


# =============================================================================
# Subject scoping
# =============================================================================
#
# Roadblocks defaults to the department's own subject prefixes: the question a
# chair brings is "where are my students blocked in MY courses", and those are
# the ones they can act on. Unscoped, the table fills with large service courses
# from other departments.

test_that("subject_code restricts get_stopout to those prefixes", {
  all_courses <- get_stopout(make_stopout_students(), make_stopout_population(), student_terms = make_stopout_terms(),
                             opt = list(min_n = 5, min_dfw_n = 2))$by_course
  skip_if(nrow(all_courses) == 0, "fixture produced no qualifying courses")

  prefix <- sub(" .*", "", all_courses$subject_course[[1]])
  scoped <- get_stopout(make_stopout_students(), make_stopout_population(), student_terms = make_stopout_terms(),
                        opt = list(min_n = 5, min_dfw_n = 2,
                                   subject_code = prefix))$by_course

  expect_true(all(sub(" .*", "", scoped$subject_course) == prefix))
  expect_lte(nrow(scoped), nrow(all_courses))
})

test_that("an empty or NULL subject_code means every subject", {
  base <- get_stopout(make_stopout_students(), make_stopout_population(), student_terms = make_stopout_terms(),
                      opt = list(min_n = 5, min_dfw_n = 2))$by_course
  for (val in list(NULL, character(0))) {
    out <- get_stopout(make_stopout_students(), make_stopout_population(), student_terms = make_stopout_terms(),
                       opt = list(min_n = 5, min_dfw_n = 2, subject_code = val))$by_course
    expect_equal(nrow(out), nrow(base))
  }
})

test_that("get_dfw_rates honours the same subject scope", {
  # The two must agree: get_dfw_rates() supplies context columns joined onto the
  # departure table, so a mismatched scope would drop rows from the join.
  all_rates <- get_dfw_rates(make_stopout_students(), make_stopout_population(),
                             opt = list(min_n = 5, min_dfw_n = 2))
  skip_if(nrow(all_rates) == 0, "fixture produced no qualifying courses")

  prefix <- sub(" .*", "", all_rates$subject_course[[1]])
  scoped <- get_dfw_rates(make_stopout_students(), make_stopout_population(),
                          opt = list(min_n = 5, min_dfw_n = 2, subject_code = prefix))

  expect_true(all(sub(" .*", "", scoped$subject_course) == prefix))
})

test_that("a subject with no courses yields an empty result, not an error", {
  out <- get_stopout(make_stopout_students(), make_stopout_population(), student_terms = make_stopout_terms(),
                     opt = list(min_n = 5, min_dfw_n = 2,
                                subject_code = "ZZZZ"))$by_course
  expect_equal(nrow(out), 0)
})

test_that("stopout and DFW context keep campus-course cohorts separate", {
  population <- tibble(
    student_id = unique(test_students_mc$student_id),
    population_label = "MC population"
  )

  stopout <- suppressMessages(get_stopout(
    test_students_mc, student_terms = test_student_terms_mc, population, opt = list(min_n = 1L, min_dfw_n = 0L)
  ))$by_course
  rates <- suppressMessages(get_dfw_rates(
    test_students_mc, population, opt = list(min_n = 1L, min_dfw_n = 0L)
  ))

  expect_setequal(
    dplyr::filter(stopout, subject_course == "SPAN 101")$campus,
    c("ABQ", "GA")
  )
  expect_setequal(
    dplyr::filter(rates, subject_course == "SPAN 101")$campus,
    c("ABQ", "GA")
  )
})

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

test_that("Roadblocks uses mutually exclusive first-outcome groups for every statistic", {
  result <- get_stopout(test_students_roadblocks, roadblocks_population(), opt = roadblocks_options(),
                        student_terms = test_student_terms_roadblocks)
  row <- result$by_course %>% filter(campus == "ABQ", subject_course == "ECON 100")
  expect_equal(row$pop_n_pass, 5L)
  expect_equal(row$pop_n_dfw, 5L)
  expect_equal(row$pop_n_graded, 10L)
  expect_equal(row$pop_dfw_rate, .5)
  expect_equal(row$pop_pass_stopout_rate, .2)
  expect_equal(row$pop_dfw_stopout_rate, .8)
  expect_equal(row$pop_stopout_gap, .6)
  expect_equal(row$baseline_n_graded, 10L)
  expect_equal(row$baseline_dfw_rate, .5)
  expect_equal(row$baseline_pass_stopout_rate, .4)
  expect_equal(row$baseline_dfw_stopout_rate, .4)
  expect_equal(row$baseline_stopout_gap, 0)
  # Yates-corrected chi-square for [[4,1],[1,4]], with each student once.
  expect_equal(row$pop_p_value, 0.205903210732068, tolerance = 1e-12)
  ranked <- prepare_roadblock_results(row)
  expect_equal(ranked$excess_gap, .6)
  expect_equal(ranked$impact_score, 3)
  ga <- result$by_course %>% filter(campus == "GA")
  expect_equal(ga$pop_n_pass, 1L)
  expect_equal(ga$pop_pass_stopout_rate, 0) # returned on another campus
  expect_equal(result$term_range, c(202010L, 202080L))
  expect_equal(result$observation_info$n_ambiguous, 1L)
  expect_equal(result$observation_info$n_invalid, 1L)
  expect_equal(result$observation_info$n_later, 4L)
  expect_equal(result$observation_info$n_duplicates, 1L)
})

test_that("Roadblocks ignores row order and repeated extract rows on both paths", {
  students <- test_students_roadblocks
  opt <- roadblocks_options()
  raw <- get_stopout(students, roadblocks_population(), opt = opt,
                     student_terms = test_student_terms_roadblocks)
  # The class-list path: repeated, reordered extract rows never change the
  # analysis (classify_outcomes() collapses identical rows).
  repeated <- bind_rows(students, students) %>% arrange(desc(term), desc(final_grade))
  raw_repeated <- get_stopout(repeated, roadblocks_population(), opt = opt,
                              student_terms = test_student_terms_roadblocks)
  expect_equal(raw_repeated$by_course, raw$by_course)
  expect_equal(raw_repeated$term_range, raw$term_range)

  # cedar_attempts holds one row per student, course, campus and term, so its
  # order cannot matter either.
  attempts <- fixture_attempts(students, 202110L)
  from_attempts <- get_stopout(NULL, roadblocks_population(), opt = opt,
    attempts = attempts, student_terms = test_student_terms_roadblocks)
  shuffled <- attempts[rev(seq_len(nrow(attempts))), ]
  expect_equal(get_stopout(NULL, roadblocks_population(), opt = opt, attempts = shuffled,
                           student_terms = test_student_terms_roadblocks)$by_course,
               from_attempts$by_course)
  expect_equal(from_attempts$term_range, raw$term_range)

  # The one difference is by design. RB_P11 holds an A and an F in ECON 100 in
  # Spring 2020 on two CRNs: the class-list path cannot tell which is the
  # outcome and leaves P11 out; the loaded class list keeps one row of record
  # (dedup_class_list_rows(): both registered and graded, so the lower CRN), and
  # P11 counts once.
  expect_equal(raw$observation_info$n_ambiguous, 1L)
  expect_equal(from_attempts$observation_info$n_ambiguous, 0L)
  econ <- function(r) filter(r$by_course, campus == "ABQ", subject_course == "ECON 100")
  expect_equal(econ(from_attempts)$pop_n_graded, econ(raw)$pop_n_graded + 1L)
  other <- function(r) filter(r$by_course, !(campus == "ABQ" & subject_course == "ECON 100"))
  expect_equal(other(from_attempts), other(raw))
})

test_that("Roadblocks selects after term scope and both observation edges", {
  opt <- roadblocks_options()
  opt$term <- 202080L
  opt$observation_end_term <- 202080L
  empty <- get_stopout(test_students_roadblocks, roadblocks_population(), opt = opt,
                       student_terms = test_student_terms_roadblocks)
  expect_equal(nrow(empty$by_course), 0L)
  opt$observation_end_term <- 202110L
  result <- get_stopout(test_students_roadblocks, roadblocks_population(), opt = opt,
                       student_terms = test_student_terms_roadblocks)
  row <- result$by_course %>% filter(subject_course == "ECON 100")
  expect_equal(row$pop_n_pass, 2L) # P06 and P11 first within THIS scope
  expect_equal(row$pop_n_dfw, 1L) # P01
  expect_equal(result$observation_info$n_ambiguous, 0L)
  opt$min_n <- 11L
  opt$term <- NULL
  suppressed <- get_stopout(test_students_roadblocks, roadblocks_population(), opt = opt,
                       student_terms = test_student_terms_roadblocks)
  expect_equal(nrow(suppressed$by_course), 0L) # P11 cannot satisfy threshold
  expect_equal(suppressed$observation_info$n_ambiguous, 1L)
})

test_that("Roadblocks group statistics reject repeated or incomplete observations", {
  group <- make_stopout_group()
  expect_error(compute_stopout_for_group(bind_rows(group, group[1, ]), "pop"), "one observation per student")
  group$stopped_out[1] <- NA
  expect_error(compute_stopout_for_group(group, "pop"), "complete")
})

test_that("Roadblocks retains completion correction and full-history returns after windowing", {
  pop <- roadblocks_population() %>% mutate(relevant_until = 202010L)
  # RB_P11's conflicting CRNs are the row-order test's case; left out here so
  # the counts are the class-list path's.
  attempts <- fixture_attempts(filter(test_students_roadblocks, student_id %in% "RB_P11" == FALSE),
                               202110L)
  attempts <- apply_pathways_population_window(attempts, pop, analysis_through = 202110L)
  result <- get_stopout(NULL, pop, degrees = test_degrees_roadblocks,
    opt = roadblocks_options(), attempts = attempts,
    student_terms = test_student_terms_roadblocks)
  row <- result$by_course %>% filter(campus == "ABQ", subject_course == "ECON 100")
  expect_equal(row$pop_n_dfw, 5L)
  expect_equal(row$pop_dfw_rate, .5)
  expect_equal(row$pop_dfw_stopout_rate, .6) # P06 returned after window; P10 graduated
  expect_equal(row$pop_pass_stopout_rate, .2)
  expect_equal(row$pop_stopout_gap, row$pop_dfw_stopout_rate - row$pop_pass_stopout_rate)
})

test_that("Roadblocks reports invalid-only input without inventing a term range", {
  result <- get_stopout(test_students_roadblocks %>% filter(is.na(student_id)),
                        roadblocks_population(), opt = roadblocks_options(),
                        student_terms = test_student_terms_roadblocks)
  expect_equal(nrow(result$by_course), 0L)
  expect_equal(result$observation_info$n_invalid, 1L)
  expect_equal(result$observation_info$n_selected, 0L)
  expect_true(all(is.na(result$term_range)))
})
