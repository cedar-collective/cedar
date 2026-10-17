# Tests for SFR (Student-Faculty Ratio) functions
# Tests R/cones/sfr.R
#
# Uses test_faculty and test_programs (from fixtures/designed_test_data.R).
#
# Reference values (from designed_test_data.R fixtures):
#   get_perm_faculty_count(test_faculty) → 28 rows, depts: ANTH, BIOL, ENGL, HIST, MATH, NURS, PSYC
#   (MGMT and POLS have only Term Teacher rows — excluded as non-permanent)
#   get_sfr(test_programs, test_faculty) → no summer terms, program_types: all_majors, all_minors
#   get_sfr_data_for_dept_report(test_programs, test_faculty, opt = list(dept_code = "HIST"))
#                                        → plots: ug_sfr_plot, grad_sfr_plot, sfr_scatterplot

context("SFR")


# =============================================================================
# get_perm_faculty_count() tests
# =============================================================================

test_that("get_perm_faculty_count returns correct structure", {
  result <- get_perm_faculty_count(test_faculty)

  expect_s3_class(result, "data.frame")
  expect_true("term"       %in% names(result))
  expect_true("department" %in% names(result))
  expect_true("total"      %in% names(result))
})

test_that("get_perm_faculty_count returns only CAS departments in fixture", {
  result <- get_perm_faculty_count(test_faculty)

  # test_faculty covers all departments with permanent faculty (excludes MGMT and POLS
  # which have only Term Teacher rows)
  expect_setequal(unique(result$department), c("ANTH", "BIOL", "ENGL", "HIST", "MATH", "NURS", "PSYC"))
})

test_that("get_perm_faculty_count FTE totals are positive", {
  result <- get_perm_faculty_count(test_faculty)
  expect_true(all(result$total > 0))
})

test_that("get_perm_faculty_count excludes non-permanent job categories", {
  # Permanent = Professor, Associate Professor, Assistant Professor, Lecturer
  # Excluded = Grad, TPT, Term Teacher, Professor Emeritus
  # After filtering, all rows represent permanent appointments
  result <- get_perm_faculty_count(test_faculty)

  # 28 rows = 7 departments × 4 terms (MGMT and POLS excluded as non-permanent only)
  expect_equal(nrow(result), 28)
})

test_that("get_perm_faculty_count raw faculty has multiple job categories", {
  # Verify fixture has non-permanent categories the function should exclude
  all_cats <- unique(test_faculty$job_category)
  expect_true("Term Teacher" %in% all_cats)   # non-permanent (excluded)
  expect_true("Professor"    %in% all_cats)   # permanent (included)
})


# =============================================================================
# get_sfr() tests
# =============================================================================

test_that("get_sfr returns correct structure", {
  result <- get_sfr(test_programs, test_faculty)

  expect_s3_class(result, "data.frame")
  expect_true("term"          %in% names(result))
  expect_true("dept_code"     %in% names(result))
  expect_true("student_level" %in% names(result))
  expect_true("program_type"  %in% names(result))
  expect_true("students"      %in% names(result))
  expect_true("total"         %in% names(result))
  expect_true("sfr"           %in% names(result))
})

test_that("get_sfr excludes summer terms", {
  result <- get_sfr(test_programs, test_faculty)

  expect_false(any(grepl("60$", as.character(result$term))))
})

test_that("get_sfr separates all_majors and all_minors program types", {
  result <- get_sfr(test_programs, test_faculty)

  expect_true("all_majors" %in% result$program_type)
  expect_true("all_minors" %in% result$program_type)
})

test_that("get_sfr dept_code column contains known CEDAR department codes", {
  result <- get_sfr(test_programs, test_faculty)

  dept_codes <- unique(na.omit(result$dept_code))
  # Programs fixture spans many departments; HIST, ANTH, MATH are guaranteed
  expect_true("HIST" %in% dept_codes)
  expect_true("ANTH" %in% dept_codes)
  expect_true("MATH" %in% dept_codes)
})


# =============================================================================
# get_sfr_data_for_dept_report() tests
# =============================================================================

test_that("get_sfr_data_for_dept_report returns three plot keys for HIST", {
  result <- get_sfr_data_for_dept_report(test_programs, test_faculty, opt = list(dept_code = "HIST"))

  expect_true("plots"          %in% names(result))
  expect_true("ug_sfr_plot"    %in% names(result$plots))
  expect_true("grad_sfr_plot"  %in% names(result$plots))
  expect_true("sfr_scatterplot" %in% names(result$plots))
})

test_that("get_sfr_data_for_dept_report produces at least one plotly plot for HIST", {
  result <- get_sfr_data_for_dept_report(test_programs, test_faculty, opt = list(dept_code = "HIST"))

  has_plotly <- any(sapply(result$plots, function(p) inherits(p, "plotly")))
  expect_true(has_plotly)
})

test_that("get_sfr_data_for_dept_report still returns plot keys for unknown department", {
  result <- get_sfr_data_for_dept_report(test_programs, test_faculty, opt = list(dept_code = "FAKE_DEPT"))

  expect_true("plots"       %in% names(result))
  expect_true("ug_sfr_plot" %in% names(result$plots))
})

test_that("get_sfr_data_for_dept_report requires opt$dept_code and never guesses one", {
  expect_error(get_sfr_data_for_dept_report(test_programs, test_faculty),
               "opt\\$dept_code")
  expect_error(get_sfr_data_for_dept_report(test_programs, test_faculty, opt = list(dept_code = NA)),
               "opt\\$dept_code")
})

test_that("get_sfr and get_perm_faculty_count stop on a missing table or column", {
  # M12: every table is a parameter. A missing one is an error, not a silent empty result.
  expect_error(get_sfr(NULL, test_faculty), "cedar_programs")
  expect_error(get_sfr(test_programs, NULL), "cedar_faculty")
  expect_error(get_perm_faculty_count(select(test_faculty, -appointment_pct)),
               "appointment_pct")
})
