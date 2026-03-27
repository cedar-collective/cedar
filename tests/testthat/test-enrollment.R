# Tests for enrollment analysis functions
# Tests R/branches/enrl.R: summarize_courses, aggregate_courses, get_enrl
#
# Uses designed_test_data.R fixtures (hand-crafted, transparent).
# calc_cl_enrls is also tested in test-course-demographics.R.
#
# Reference values (from designed_test_data.R, 82 total rows, 11 XL merged in):
#   Terms in fixture: 202010, 202060, 202080, 202110
#   Status=A sections per term: 202010=28, 202060=12, 202080=15, 202110=17
#   Total enrolled (status=A) per term: 202010=462, 202060=217, 202080=323, 202110=344
#   Cancelled sections per term: 202010=2, 202060=2, 202080=2, 202110=2
#   HIST dept, 202010, status=A: 10 sections, 109 enrolled
#   202010 active: xl_sections=11, reg_sections=17
#   Morgan, Rachel: 24 active sections across all 4 terms

context("Enrollment Analysis")


# =============================================================================
# summarize_courses() tests
# =============================================================================

test_that("summarize_courses returns correct structure", {
  active <- test_sections %>% filter(status == "A")
  opt    <- list(group_cols = c("campus", "college", "term", "subject_course"))
  result <- summarize_courses(active, opt)

  expect_s3_class(result, "data.frame")
  expect_true("sections"     %in% names(result))
  expect_true("xl_sections"  %in% names(result))
  expect_true("reg_sections" %in% names(result))
  expect_true("avg_size"     %in% names(result))
  expect_true("enrolled"     %in% names(result))
  expect_true("avail"        %in% names(result))
  expect_true("waiting"      %in% names(result))
})

test_that("summarize_courses grouped by term returns 4 rows (one per term)", {
  active <- test_sections %>% filter(status == "A")
  opt    <- list(group_cols = c("term"))
  result <- summarize_courses(active, opt)

  expect_equal(nrow(result), 4)
  expect_setequal(result$term, c(202010, 202060, 202080, 202110))
})

test_that("summarize_courses enrolled totals match fixture per term", {
  active <- test_sections %>% filter(status == "A")
  opt    <- list(group_cols = c("term"))
  result <- summarize_courses(active, opt) %>% arrange(term)

  expect_equal(result$sections, c(28, 12, 15, 17))
  expect_equal(result$enrolled, c(462, 217, 323, 344))
})

test_that("summarize_courses xl_sections and reg_sections sum to sections", {
  active <- test_sections %>% filter(status == "A", term == 202010)
  opt    <- list(group_cols = c("term"))
  result <- summarize_courses(active, opt)

  # 202010 active: 11 XL sections, 17 regular
  expect_equal(result$xl_sections,  11)
  expect_equal(result$reg_sections, 17)
  expect_equal(result$xl_sections + result$reg_sections, result$sections)
})

test_that("summarize_courses default group_cols includes standard columns", {
  active <- test_sections %>% filter(status == "A", term == 202010)
  opt    <- list(group_cols = NULL)
  result <- summarize_courses(active, opt)

  expect_true("campus"         %in% names(result))
  expect_true("college"        %in% names(result))
  expect_true("term"           %in% names(result))
  expect_true("subject_course" %in% names(result))
  expect_true("level"          %in% names(result))
})


# =============================================================================
# aggregate_courses() tests
# =============================================================================

test_that("aggregate_courses stops when group_cols is NULL", {
  active <- test_sections %>% filter(status == "A", term == 202010)
  opt    <- list(group_cols = NULL)

  expect_error(aggregate_courses(active, opt), "group_cols is null")
})

test_that("aggregate_courses returns same result as summarize_courses", {
  active <- test_sections %>% filter(status == "A")
  opt    <- list(group_cols = c("term"))

  result_agg  <- aggregate_courses(active, opt)
  result_summ <- summarize_courses(active, opt)

  expect_equal(nrow(result_agg), nrow(result_summ))
  expect_setequal(names(result_agg), names(result_summ))
})

test_that("aggregate_courses groups by department within term", {
  active <- test_sections %>% filter(status == "A", term == 202010)
  opt    <- list(group_cols = c("term", "department"))
  result <- aggregate_courses(active, opt)

  expect_true("department" %in% names(result))
  expect_true("enrolled"   %in% names(result))

  # HIST 202010: 10 sections, 109 enrolled
  hist_row <- result %>% filter(department == "HIST")
  expect_equal(hist_row$sections, 10)
  expect_equal(hist_row$enrolled, 109)
})


# =============================================================================
# get_enrl() tests
# =============================================================================

test_that("get_enrl returns correct structure", {
  opt    <- list(term = 202010, status = "A",
                 group_cols = c("campus", "college", "term", "subject_course"),
                 uel = FALSE)
  result <- get_enrl(test_sections, opt)

  expect_s3_class(result, "data.frame")
  expect_true("enrolled"  %in% names(result))
  expect_true("avail"     %in% names(result))
  expect_true("waiting"   %in% names(result))
  expect_true("sections"  %in% names(result))
})

test_that("get_enrl aggregated by term returns 4 rows with correct totals", {
  opt    <- list(status = "A", group_cols = c("term"), uel = FALSE)
  result <- get_enrl(test_sections, opt) %>% arrange(term)

  expect_equal(nrow(result), 4)
  expect_equal(result$sections, c(28, 12, 15, 17))
  expect_equal(result$enrolled, c(462, 217, 323, 344))
})

test_that("get_enrl filters by department correctly", {
  opt    <- list(dept = "HIST", term = 202010, status = "A",
                 group_cols = c("term", "department"), uel = FALSE)
  result <- get_enrl(test_sections, opt)

  expect_equal(nrow(result), 1)
  expect_true(result$department == "HIST")
  expect_equal(result$sections,   10)
  expect_equal(result$enrolled,   109)
})

test_that("get_enrl returns empty data frame for nonexistent term", {
  opt    <- list(term = 999999, status = "A",
                 group_cols = c("term"), uel = FALSE)
  result <- get_enrl(test_sections, opt)

  expect_equal(nrow(result), 0)
  expect_s3_class(result, "data.frame")
})

test_that("get_enrl without group_cols returns section-level data", {
  opt    <- list(term = 202010, status = "A", uel = FALSE)
  result <- get_enrl(test_sections, opt)

  # Section-level: 28 active sections in 202010
  expect_equal(nrow(result), 28)
  expect_true("crn"           %in% names(result))
  expect_true("subject_course" %in% names(result))
})

test_that("get_enrl filters by instructor correctly", {
  opt    <- list(inst = "Morgan, Rachel", status = "A", uel = FALSE)
  result <- get_enrl(test_sections, opt)

  expect_equal(nrow(result), 24)
  expect_true(all(result$instructor_name == "Morgan, Rachel"))
})

test_that("get_enrl returns cancelled sections when status=C", {
  opt    <- list(term = 202010, status = "C",
                 group_cols = c("term"), uel = FALSE)
  result <- get_enrl(test_sections, opt)

  expect_equal(result$sections, 2)
})

test_that("get_enrl combined dept and term filter works", {
  opt    <- list(dept = "HIST", term = 202010, status = "A", uel = FALSE)
  result <- get_enrl(test_sections, opt)

  expect_equal(nrow(result), 10)
  expect_true(all(grepl("^HIST", result$subject_course)))
  expect_true(all(result$term == 202010))
})

test_that("get_enrl handles multiple terms correctly", {
  opt    <- list(term = c(202010, 202060), status = "A",
                 group_cols = c("term"), uel = FALSE)
  result <- get_enrl(test_sections, opt) %>% arrange(term)

  expect_equal(nrow(result), 2)
  expect_equal(result$sections, c(28, 12))
})


# =============================================================================
# calc_cl_enrls() — brief structural coverage
# (full behavioral tests in test-course-demographics.R)
# =============================================================================

test_that("calc_cl_enrls returns correct structure for test_students", {
  filtered <- test_students %>%
    filter(department == "HIST",
           registration_status_code %in% c("RE", "RS", "RR"))

  result <- calc_cl_enrls(filtered)

  expect_s3_class(result, "data.frame")
  expect_true("registered"      %in% names(result))
  expect_true("registered_mean" %in% names(result))
  expect_true("subject_course"  %in% names(result))
  expect_true("dr_early"        %in% names(result))
})

test_that("calc_cl_enrls returns empty data frame for empty input", {
  empty  <- test_students %>% filter(term == 999999)
  result <- calc_cl_enrls(empty)

  expect_s3_class(result, "data.frame")
  expect_equal(nrow(result), 0)
})
