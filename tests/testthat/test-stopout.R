# Tests for stop-out analysis functions
# Tests classify_outcomes() and compute_stopout_for_group() from R/cones/stopout.R
#
# Note: get_stopout() depends on add_next_term_col() from R/trunk/utils.R.
# Integration tests for the full function live in test-stopout-standalone.R.
# These unit tests cover the pure helper functions that can be tested in isolation.

library(tibble)
library(dplyr)

context("Stopout: Stop-Out Analysis")


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
#   S007 — registered, got I (incomplete) → excluded (ungraded)
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
  # S002 (F), S003 (W), S004 (D-), S010 (RF)
  expect_true("S002" %in% dfw_ids)
  expect_true("S003" %in% dfw_ids)
  expect_true("S004" %in% dfw_ids)
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

test_that("classify_outcomes excludes ungraded records", {
  result <- classify_outcomes(make_grade_data())
  # S007 (I = incomplete), S008 (AUD = audit) should be absent
  expect_false("S007" %in% result$student_id)
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
#   stopout_gap ≈ 0.334 (dfw - pass)

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
  expect_equal(result$cohort_pass_stopout_rate, round(1/3, 3))
  expect_equal(result$cohort_dfw_stopout_rate,  round(2/3, 3))
})

test_that("compute_stopout_for_group stopout_gap is positive when dfw stops out more", {
  result <- compute_stopout_for_group(make_stopout_group(), prefix = "cohort")
  # dfw_stopout_rate > pass_stopout_rate, so gap should be positive
  expect_gt(result$cohort_stopout_gap, 0)
  # Gap should be the raw difference, rounded to 3 decimal places
  # (computed from raw proportions, not from already-rounded rates)
  expect_equal(result$cohort_stopout_gap, round(2/3 - 1/3, 3))
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
#   pop_pass_stopout_rate = round(1/3, 3) = 0.333   (C003 stopped out)
#   pop_dfw_stopout_rate  = round(2/3, 3) = 0.667   (C005, C006 stopped out)
#   pop_stopout_gap       = round(1/3, 3) = 0.333
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
#   baseline_pass_stopout_rate = round(1/3, 3) = 0.333   (B005 stopped out)
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

test_that("get_stopout returns correct top-level structure", {
  result <- get_stopout(
    make_stopout_students(),
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
    make_stopout_population(),
    opt = list(min_n = 5, min_dfw_n = 2)
  )
  expect_equal(result$population_size, 6L)
})

test_that("get_stopout BIOL 2310 cohort: n_pass=3 and n_dfw=3", {
  result  <- get_stopout(
    make_stopout_students(),
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
    make_stopout_population(),
    opt = list(min_n = 5, min_dfw_n = 2)
  )
  biol <- result$by_course[result$by_course$subject_course == "BIOL 2310", ]

  expect_equal(biol$pop_pass_stopout_rate, round(1/3, 3))
  expect_equal(biol$pop_dfw_stopout_rate,  round(2/3, 3))
})

test_that("get_stopout BIOL 2310 cohort: stop-out gap = dfw_rate - pass_rate", {
  result <- get_stopout(
    make_stopout_students(),
    make_stopout_population(),
    opt = list(min_n = 5, min_dfw_n = 2)
  )
  biol <- result$by_course[result$by_course$subject_course == "BIOL 2310", ]

  expect_equal(biol$pop_stopout_gap, round(1/3, 3))
})

test_that("get_stopout BIOL 2310 baseline: n_pass=3 and n_dfw=2", {
  result <- get_stopout(
    make_stopout_students(),
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
    make_stopout_population(),
    opt = list(min_n = 5, min_dfw_n = 2)
  )
  biol <- result$by_course[result$by_course$subject_course == "BIOL 2310", ]

  expect_equal(biol$baseline_pass_stopout_rate, round(1/3, 3))
  expect_equal(biol$baseline_dfw_stopout_rate,  round(1/2, 3))
  expect_equal(biol$baseline_stopout_gap,        round(1/2 - 1/3, 3))
})

test_that("get_stopout stops when population missing required columns", {
  bad_pop <- tibble(student_id = c("C001", "C002"))  # missing population_label
  expect_error(
    get_stopout(make_stopout_students(), bad_pop, opt = list(min_n = 1)),
    "population_label"
  )
})

test_that("get_stopout respects opt$min_n threshold", {
  # min_n=10 should exclude BIOL 2310 (only 6 cohort students)
  result <- get_stopout(
    make_stopout_students(),
    make_stopout_population(),
    opt = list(min_n = 10)
  )
  expect_equal(nrow(result$by_course), 0)
})
