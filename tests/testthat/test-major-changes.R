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

test_that("Major Changes prose separates transfer origin from credit eligibility", {
  module_source <- paste(
    readLines("../../R/modules/pathways.R", warn = FALSE),
    collapse = "\n"
  )
  guide_source <- paste(
    readLines("../../docs/users/pathways.md", warn = FALSE),
    collapse = "\n"
  )

  expect_match(
    module_source,
    "Transfer origin comes from the Academic Studies Student Population label"
  )
  expect_match(
    module_source,
    "the 30-credit entry rule does not classify transfer origin",
    fixed = TRUE
  )
  expect_match(
    guide_source,
    "No credit threshold is used for this origin label",
    fixed = TRUE
  )
  expect_match(
    guide_source,
    "cedar_student_term_credits",
    fixed = TRUE
  )
})


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

test_that("detect_major_changes respects the settled observation edge", {
  result <- detect_major_changes(
    test_programs,
    opt = list(observation_end_term = 202080L)
  )

  expect_true(all(result$change_term <= 202080L))
  expect_lt(nrow(result), nrow(detect_major_changes(test_programs)))
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

test_that("major pathway credit averages exclude invalid timelines", {
  changes <- tibble::tibble(
    student_id = c("VALID", "TRUNCATED"),
    change_term = c(202080L, 202080L),
    from_major = "History",
    to_major = "Political Science",
    unm_credits_before_change = c(60, 0),
    total_credits_before_change = c(75, 15),
    credits_position_valid = c(TRUE, FALSE),
    student_college = "AS"
  )

  result <- major_change_pathways(changes, opt = list(min_n = 1L))

  expect_equal(result$n_changes, 2L)
  expect_equal(result$n_credit_positions, 1L)
  expect_equal(result$n_excluded_position, 1L)
  expect_equal(result$avg_unm_credits, 60)
  expect_equal(result$avg_total_credits, 75)
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


# =============================================================================
# get_pre_change_courses() tests — PCC01 fixture
# =============================================================================
#
# See the PCC01 block in designed_test_data.R for the layout. The short version:
# PCC 100 is universal (ratio 1.0), PCC 250 is genuinely concentrated before the
# switch (ratio 12.0), PCC 260 is a single-student cell, PCC 300/350 occur only
# in stayers' terms.

pcc_changes <- function() {
  suppressMessages(detect_major_changes(test_programs_pcc)) %>%
    filter(from_major == "Pre Change Studies")
}

pcc_result <- function(min_n = 1L) {
  suppressMessages(get_pre_change_courses(
    pcc_changes(), test_students_pcc, test_population_pcc,
    opt = list(min_n = min_n)
  ))
}

test_that("get_pre_change_courses reports the switch and baseline denominators", {
  result <- pcc_result()

  expect_equal(result$n_switches, 3L)
  expect_equal(result$n_switches_with_courses, 3L)
  expect_equal(result$n_students, 3L)
  # All six students at 202010, plus the three stayers at 202080 and 202110.
  # The switchers' prev_term and change_term are held out of both sides.
  expect_equal(result$n_baseline_terms, 12L)
})

test_that("get_pre_change_courses builds the baseline from stayers too, not just switchers", {
  result <- pcc_result()

  # The three switchers contribute only their 202010 terms to the baseline (their
  # 202080 and 202110 are held out), so a switchers-only baseline would be 3
  # student-terms. 12 is the whole population's non-switch-adjacent terms. If this
  # ever reads 3, the denominator has quietly become a within-person comparison
  # and every ratio in the table means something different.
  expect_equal(result$n_baseline_terms, 12L)

  # PCC 300 and PCC 350 exist only in stayers' terms. Their presence in the
  # baseline is what makes PCC 250's ratio meaningful rather than tautological.
  concentrated <- filter(result$courses, subject_course == "PCC 250")
  expect_equal(concentrated$n_other_terms_with_course, 1L)
  expect_equal(concentrated$pct_other_terms, round(1 / 12, 4))
})

test_that("get_pre_change_courses anchors on prev_term, not change_term", {
  courses <- pcc_result()$courses

  # PCC 250 is only ever taken at 202080; OTH 400 only at the change term.
  expect_true("PCC 250" %in% courses$subject_course)
  expect_false("OTH 400" %in% courses$subject_course)
})

test_that("get_pre_change_courses separates a universal course from a concentrated one", {
  courses <- pcc_result()

  universal   <- filter(courses$courses, subject_course == "PCC 100")
  concentrated <- filter(courses$courses, subject_course == "PCC 250")

  # Both are in every switcher's prior term — identical on the raw count.
  expect_equal(universal$n_switches, 3L)
  expect_equal(concentrated$n_switches, 3L)
  expect_equal(universal$pct_before_switch, 1)
  expect_equal(concentrated$pct_before_switch, 1)

  # The baseline is what tells them apart.
  expect_equal(universal$pct_other_terms, 1)
  expect_equal(universal$ratio, 1)
  expect_equal(concentrated$n_other_terms_with_course, 1L)
  expect_equal(concentrated$ratio, 12)
})

test_that("get_pre_change_courses excludes courses never taken before a switch", {
  courses <- pcc_result()$courses

  expect_false(any(c("PCC 300", "PCC 350") %in% courses$subject_course))
})

test_that("get_pre_change_courses suppresses cells below min_n", {
  expect_true("PCC 260" %in% pcc_result(min_n = 1L)$courses$subject_course)
  expect_false("PCC 260" %in% pcc_result(min_n = 2L)$courses$subject_course)
})

test_that("get_pre_change_courses returns NA ratio when a course has no baseline term", {
  pcc_260 <- filter(pcc_result()$courses, subject_course == "PCC 260")

  expect_equal(pcc_260$n_other_terms_with_course, 0L)
  expect_true(is.na(pcc_260$ratio))
})

test_that("get_pre_change_courses returns an empty contract for no change events", {
  no_changes <- pcc_changes() %>% filter(FALSE)
  result <- suppressMessages(get_pre_change_courses(
    no_changes, test_students_pcc, test_population_pcc, opt = list(min_n = 1L)
  ))

  expect_equal(nrow(result$courses), 0)
  expect_equal(result$n_switches, 0L)
  expect_true(all(c("subject_course", "n_switches", "pct_before_switch",
                    "pct_other_terms", "ratio") %in% names(result$courses)))
})

test_that("get_pre_change_courses stops loudly on a missing required column", {
  bad_changes <- pcc_changes() %>% select(-prev_term)

  expect_error(
    suppressMessages(get_pre_change_courses(
      bad_changes, test_students_pcc, test_population_pcc)),
    "prev_term"
  )
})


test_that("entry heatmap keeps course denominators separate by campus", {
  population <- tibble(
    student_id = unique(test_students_mc$student_id),
    population_label = "MC population",
    first_unit_term = 202080L
  )

  result <- suppressMessages(get_entry_heatmap(
    test_students_mc,
    test_programs_mc,
    population,
    focal_subjects = "MCMP",
    opt = list(max_lag = 1L, min_n = 1L)
  ))
  gateway <- dplyr::filter(result$in_unit, subject_course == "MCMP 101")

  expect_setequal(gateway$campus, c("ABQ", "GA"))
  expect_equal(sort(gateway$n_in_course), c(2L, 4L))
  expect_equal(sort(gateway$n_became_major), c(2L, 4L))
})
