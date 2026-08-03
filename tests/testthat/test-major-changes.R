# Tests for major-changes.R functions
# Tests R/cones/major-changes.R
#
# Uses designed_test_data.R fixtures (hand-crafted, transparent).
# Expected values match designed cedar_programs rows exactly.
#
# Reference values (from designed_test_data.R):
#   detect_major_changes(test_programs) → 4 change events
#   tag_major_changers(test_programs)   → one row per Major student, 4 changers
#
# Concrete changers used in specific-value assertions (from designed_test_data.R):
#   Credit columns now come from the class-list series (fixture MCC01) via
#   build_credit_timeline(), NOT from cedar_programs' cumulative columns — those
#   are stamped at pull time and frozen across a student's history. See the field
#   reliability contract in AGENTS.md. The decision-point figure is the position
#   AFTER prev_term; the *_at_change columns are gone with the frozen source.
#   CHANGER_A: STU-CHANGER-A — Political Science → Secondary Education,
#              change_term=202110, prev_term=202080.
#              unm_credits_before_change=150, total_credits_before_change=180
#   CHANGER_B: STU-CHANGER-B — Biology → Nursing,
#              change_term=202110, prev_term=202060.
#              unm_credits_before_change=75,  total_credits_before_change=105
#
# Non-changer (same program_name across all terms):
#   NON_CHANGER: STU-NON-CHANGER — Business Administration in MGMT, 4 terms, no change

CHANGER_A   <- "STU-CHANGER-A"
CHANGER_B   <- "STU-CHANGER-B"
NON_CHANGER <- "STU-NON-CHANGER"

context("Major Changes")


# =============================================================================
# detect_major_changes() tests
# =============================================================================

test_that("detect_major_changes returns correct structure", {
  result <- detect_major_changes(test_programs)

  expect_s3_class(result, "data.frame")
  expect_true("student_id"        %in% names(result))
  expect_true("change_term"       %in% names(result))
  expect_true("prev_term"         %in% names(result))
  expect_true("from_major"        %in% names(result))
  expect_true("to_major"          %in% names(result))
  expect_true("unm_credits_before_change"   %in% names(result))
  expect_true("total_credits_before_change" %in% names(result))
  expect_true("credits_position_valid"      %in% names(result))
  expect_true("dept_code"         %in% names(result))
  expect_true("student_level"     %in% names(result))
  expect_true("degree"            %in% names(result))
})

test_that("detect_major_changes finds exactly 9 change events", {
  result <- detect_major_changes(test_programs)
  # 4 original changers + 3 HIST→POLS/BIOL switched-out + 2 ENGL→HIST switched-in
  expect_equal(nrow(result), 9)
})

test_that("detect_major_changes records correct from/to majors for CHANGER_A", {
  result  <- detect_major_changes(test_programs)
  row_a   <- result[result$student_id == CHANGER_A, ]

  expect_equal(nrow(row_a), 1)
  expect_equal(row_a$from_major,        "Political Science")
  expect_equal(row_a$to_major,          "Secondary Education")
  expect_equal(row_a$change_term,       202110L)
  expect_equal(row_a$prev_term,        202080L)
})

test_that("detect_major_changes reports CHANGER_A's credit position at the decision point", {
  result <- detect_major_changes(test_programs,
                                 term_credits = cedar_student_term_credits_mcc)
  row_a  <- result[result$student_id == CHANGER_A, ]

  # Position after prev_term (202080): 150 UNM, +30 transfer = 180 total.
  expect_equal(row_a$unm_credits_before_change,   150)
  expect_equal(row_a$total_credits_before_change, 180)
})

test_that("detect_major_changes records correct from/to majors for CHANGER_B", {
  result  <- detect_major_changes(test_programs)
  row_b   <- result[result$student_id == CHANGER_B, ]

  expect_equal(nrow(row_b), 1)
  expect_equal(row_b$from_major,        "Biology")
  expect_equal(row_b$to_major,          "Nursing")
  expect_equal(row_b$change_term,       202110L)
  expect_equal(row_b$prev_term,         202060L)
})

test_that("detect_major_changes reports CHANGER_B's credit position at the decision point", {
  result <- detect_major_changes(test_programs,
                                 term_credits = cedar_student_term_credits_mcc)
  row_b  <- result[result$student_id == CHANGER_B, ]

  # Position after prev_term (202060): 75 UNM, +30 transfer = 105 total.
  expect_equal(row_b$unm_credits_before_change,   75)
  expect_equal(row_b$total_credits_before_change, 105)
})

test_that("credit columns are NA without term_credits, never read off the frozen columns", {
  # The failure mode this guards: cedar_programs carries plausible-looking
  # cumulative columns, and silently falling back to them would restore exactly
  # the defect the migration removed.
  result <- suppressMessages(detect_major_changes(test_programs))
  expect_true(all(is.na(result$unm_credits_before_change)))
  expect_true(all(is.na(result$total_credits_before_change)))
  # Change detection itself is unaffected — the events are still found.
  expect_equal(nrow(result), 9)
})

test_that("avg_credits_before_major drops events with no usable position", {
  no_credits <- suppressMessages(detect_major_changes(test_programs))
  expect_equal(nrow(avg_credits_before_major(no_credits, opt = list(min_n = 1L))), 0)

  with_credits <- detect_major_changes(test_programs,
                                       term_credits = cedar_student_term_credits_mcc)
  out <- avg_credits_before_major(with_credits, opt = list(min_n = 1L))
  expect_gt(nrow(out), 0)
  expect_true(all(!is.na(out$avg_unm_credits)))
})

test_that("detect_major_changes does not flag pre-major to declared transition as a change", {
  # NON_CHANGER: Business Administration, MGMT dept.
  # Appears as is_pre_major=TRUE then FALSE, but program_name never changes.
  result <- detect_major_changes(test_programs)
  expect_false(NON_CHANGER %in% result$student_id)
})

test_that("detect_major_changes filters by dept_code via opt", {
  # opt$dept_code filters programs BEFORE detecting changes, so it detects within-dept
  # changes only (student changes from one program to another within the same dept).
  # MGMT has 2 within-dept changers; HIST has none in this fixture.
  result_mgmt <- detect_major_changes(test_programs, opt = list(dept_code = "MGMT"))
  result_hist <- detect_major_changes(test_programs, opt = list(dept_code = "HIST"))

  expect_gt(nrow(result_mgmt), 0)
  expect_true(all(result_mgmt$dept_code == "MGMT"))
  expect_equal(nrow(result_hist), 0)
})

test_that("detect_major_changes applies cohort filter", {
  cohort <- tibble(student_id = CHANGER_B, population_label = "test")
  result  <- detect_major_changes(test_programs, population = cohort)

  expect_equal(nrow(result), 1)
  expect_true(CHANGER_B %in% result$student_id)
})

test_that("detect_major_changes returns empty tibble when no changes exist", {
  # Students with only one distinct program_name per term sequence
  no_changers <- test_programs %>%
    filter(!student_id %in% detect_major_changes(test_programs)$student_id)
  result <- detect_major_changes(no_changers)

  expect_equal(nrow(result), 0)
  expect_s3_class(result, "data.frame")
})


# =============================================================================
# tag_major_changers() tests
# =============================================================================

test_that("tag_major_changers returns correct structure", {
  result <- tag_major_changers(test_programs)

  expect_s3_class(result, "data.frame")
  expect_true("student_id"    %in% names(result))
  expect_true("changed_major" %in% names(result))
  expect_true("n_changes"     %in% names(result))
  expect_true("n_majors_held" %in% names(result))
  expect_true("majors_held"   %in% names(result))
})

test_that("tag_major_changers returns one row per student", {
  result     <- tag_major_changers(test_programs)
  n_students <- n_distinct(
    test_programs[test_programs$program_type == "Major", "student_id", drop = TRUE]
  )
  expect_equal(nrow(result), n_students)
})

test_that("tag_major_changers identifies exactly 9 changers", {
  result <- tag_major_changers(test_programs)
  # 4 original + 3 HIST→POLS/BIOL switched-out + 2 ENGL→HIST switched-in
  expect_equal(sum(result$changed_major), 9)
})

test_that("tag_major_changers marks CHANGER_B as a changer", {
  result  <- tag_major_changers(test_programs)
  row_b   <- result[result$student_id == CHANGER_B, ]

  expect_equal(row_b$changed_major, TRUE)
  expect_equal(row_b$n_changes,     1L)
})

test_that("tag_major_changers marks NON_CHANGER as not a changer", {
  result <- tag_major_changers(test_programs)
  row_nc <- result[result$student_id == NON_CHANGER, ]

  expect_equal(row_nc$changed_major, FALSE)
  expect_equal(row_nc$n_changes,     0L)
})

test_that("tag_major_changers shows 0 changes for all non-changers", {
  result       <- tag_major_changers(test_programs)
  non_changers <- result[result$changed_major == FALSE, ]
  expect_true(all(non_changers$n_changes == 0))
})


# =============================================================================
# major_change_pathways() tests
# =============================================================================

test_that("major_change_pathways returns correct structure", {
  changes <- detect_major_changes(test_programs)
  result  <- major_change_pathways(changes, opt = list(min_n = 1))

  expect_s3_class(result, "data.frame")
  expect_true("from_major" %in% names(result))
  expect_true("to_major"   %in% names(result))
  expect_true("n_changes"  %in% names(result))
})

test_that("major_change_pathways includes Biology → Nursing pathway", {
  changes <- detect_major_changes(test_programs)
  result  <- major_change_pathways(changes, opt = list(min_n = 1))

  pairs <- paste(result$from_major, result$to_major, sep = "→")
  expect_true("Biology→Nursing" %in% pairs)
})

test_that("major_change_pathways respects min_n filter", {
  changes <- detect_major_changes(test_programs)
  # A very high threshold should return nothing
  result  <- major_change_pathways(changes, opt = list(min_n = 9999))
  expect_equal(nrow(result), 0)
})


# =============================================================================
# majors_moved_out_of() tests
# =============================================================================

test_that("majors_moved_out_of returns correct structure", {
  changes <- detect_major_changes(test_programs)
  result  <- majors_moved_out_of(changes, opt = list(min_n = 1))

  expect_s3_class(result, "data.frame")
  expect_true("from_major" %in% names(result))
  expect_true("n_exits"    %in% names(result))
})

test_that("majors_moved_out_of includes Biology as an exit source", {
  changes <- detect_major_changes(test_programs)
  result  <- majors_moved_out_of(changes, opt = list(min_n = 1))

  expect_true("Biology" %in% result$from_major)
})


# =============================================================================
# avg_credits_before_major() tests
# =============================================================================

test_that("avg_credits_before_major returns correct structure", {
  changes <- detect_major_changes(test_programs,
                                  term_credits = cedar_student_term_credits_mcc)
  result  <- avg_credits_before_major(changes, opt = list(min_n = 1))

  expect_s3_class(result, "data.frame")
  expect_true("to_major"             %in% names(result))
  expect_true("avg_unm_credits"      %in% names(result))
  expect_true("median_unm_credits"   %in% names(result))
  expect_true("avg_total_credits"    %in% names(result))
  expect_true("median_total_credits" %in% names(result))
})

test_that("avg_credits_before_major Nursing entry uses the decision-point position (CHANGER_B = 75 UNM)", {
  changes <- detect_major_changes(test_programs,
                                  term_credits = cedar_student_term_credits_mcc)
  result  <- avg_credits_before_major(changes, opt = list(min_n = 1))

  nursing_row <- result[result$to_major == "Nursing", ]
  expect_true(nrow(nursing_row) > 0)
  # CHANGER_B entered Nursing with 75 UNM credits behind them (105 incl. transfer);
  # the average reflects this (among others)
  expect_true(!is.na(nursing_row$avg_unm_credits))
  expect_true(nursing_row$avg_total_credits > nursing_row$avg_unm_credits)
})


# =============================================================================
# time_to_first_change() tests
# =============================================================================

test_that("time_to_first_change returns one row per changing student", {
  result <- time_to_first_change(test_programs)

  expect_s3_class(result, "data.frame")
  # Should have exactly as many rows as distinct changers
  expect_equal(nrow(result), n_distinct(result$student_id))
})

test_that("time_to_first_change records correct first change for CHANGER_B", {
  result  <- time_to_first_change(test_programs)
  row_b   <- result[result$student_id == CHANGER_B, ]

  expect_equal(nrow(row_b), 1)
  expect_equal(row_b$first_change_term, 202110L)
})


# =============================================================================
# get_major_change_courses() tests
# =============================================================================

test_that("get_major_change_courses returns correct structure", {
  changes <- detect_major_changes(test_programs)
  result  <- get_major_change_courses(changes, test_students, opt = list(min_n = 1))

  expect_s3_class(result, "data.frame")
  expect_true("subject_course"  %in% names(result))
  expect_true("n_students"      %in% names(result))
  expect_true("pct_of_changers" %in% names(result))
})

test_that("get_major_change_courses returns empty tibble for empty changes", {
  empty_changes <- detect_major_changes(test_programs) %>% filter(FALSE)
  result <- get_major_change_courses(empty_changes, test_students)

  expect_equal(nrow(result), 0)
  expect_s3_class(result, "data.frame")
})
