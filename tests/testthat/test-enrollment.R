# Tests for enrollment analysis functions
# Tests R/branches/enrl.R: summarize_courses, aggregate_courses, get_enrl
#
# Uses designed_test_data.R fixtures (hand-crafted, transparent).
# calc_cl_enrls is also tested in test-course-demographics.R.
#
# Reference values (from designed_test_data.R, 85 total rows, 14 XL merged in):
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

  # 202080 (Fall 2020): 18 base + 14 C-suffix sections (EC-04:4, EC-05:4, EC-06:6) = 32
  # enrolled for 202080: 370 base + 89 (EC-04) + 89 (EC-05) + 230 (EC-06) = 778
  expect_equal(result$sections, c(28, 12, 32, 17))
  expect_equal(result$enrolled, c(462, 217, 778, 344))
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
  # 202080: 18 base + 14 C-suffix (EC-04:4, EC-05:4, EC-06:6) = 32; enrolled=370+89+89+230=778
  expect_equal(result$sections, c(28, 12, 32, 17))
  expect_equal(result$enrolled, c(462, 217, 778, 344))
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
# calc_cl_enrls() — structural coverage + numeric value regression tests
# (additional behavioral tests in test-course-demographics.R)
#
# Numeric baselines derived from designed_test_data.R:
#   HIST 1110 202010: 21 RE + 9 DW = registered=21, dr_late=9, dr_all=9,
#                     dr_early=0, wl_all=0, cl_total=30
#   MATH 1215Z 202010: 2 RE + 3 DW = registered=2, dr_late=3, dr_all=3,
#                      dr_early=0, cl_total=5
#   HIST 327 202010: 3 DW for squeeze baseline → dr_late and dr_all non-zero
# =============================================================================

test_that("calc_cl_enrls returns correct structure for test_students", {
  filtered <- test_students %>%
    filter(department == "HIST",
           registration_status_code %in% STATUS_REGISTERED)

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

test_that("calc_cl_enrls output has all expected status columns", {
  result <- calc_cl_enrls(test_students)

  expected_cols <- c(
    "registered", "registered_mean",
    "dr_early",   "dr_early_mean",
    "dr_late",    "dr_late_mean",
    "dr_all",     "dr_all_mean",
    "wl_all",
    "cl_total",   "cl_total_mean"
  )
  for (col in expected_cols) {
    expect_true(col %in% names(result), info = paste("missing column:", col))
  }
})

test_that("calc_cl_enrls HIST 1110 202010 registered count matches fixture", {
  # Fixture: 21 RE students, 9 DW students → registered = 21
  result <- calc_cl_enrls(test_students %>% filter(department == "HIST"))
  row <- result %>%
    filter(subject_course == "HIST 1110", term == 202010L, campus == "ABQ")

  expect_equal(nrow(row), 1)
  expect_equal(row$registered, 21)
})

test_that("calc_cl_enrls HIST 1110 202010 drop counts match fixture", {
  # Fixture: 9 DW (late drop), 0 DR (early drop), 0 WL
  # dr_late = 9, dr_all = 9, dr_early = 0, wl_all = 0, cl_total = 30
  result <- calc_cl_enrls(test_students %>% filter(department == "HIST"))
  row <- result %>%
    filter(subject_course == "HIST 1110", term == 202010L, campus == "ABQ")

  expect_equal(row$dr_early, 0)
  expect_equal(row$dr_late,  9)
  expect_equal(row$dr_all,   9)
  expect_equal(row$wl_all,   0)
  expect_equal(row$cl_total, 30)
})

test_that("calc_cl_enrls zero-count status columns are 0, not NA", {
  # Courses with no early drops must return 0 not NA (important for downstream math)
  result <- calc_cl_enrls(test_students %>% filter(department == "HIST"))
  h1110  <- result %>% filter(subject_course == "HIST 1110")

  expect_true(all(!is.na(h1110$dr_early)),
              info = "dr_early must be 0 not NA when no early drops exist")
  expect_true(all(!is.na(h1110$wl_all)),
              info = "wl_all must be 0 not NA when no waitlisted students exist")
})

test_that("calc_cl_enrls by_part_term adds the part_term dimension only when requested", {
  hist <- test_students %>% filter(department == "HIST")

  default_out <- calc_cl_enrls(hist)
  part_out    <- calc_cl_enrls(hist, by_part_term = TRUE)

  # Off by default so existing callers keep one row per course/term.
  expect_false("part_term" %in% names(default_out))
  # On request, part_term becomes a grouping column carried into the output.
  expect_true("part_term" %in% names(part_out))
})

test_that("calc_cl_enrls by_part_term preserves single-part counts", {
  # The fixtures have no part-of-term variation, so turning the dimension on
  # must not change the enrollment counts — it only adds the column.
  hist <- test_students %>% filter(department == "HIST")

  default_row <- calc_cl_enrls(hist) %>%
    filter(subject_course == "HIST 1110", term == 202010L, campus == "ABQ")
  part_row <- calc_cl_enrls(hist, by_part_term = TRUE) %>%
    filter(subject_course == "HIST 1110", term == 202010L, campus == "ABQ")

  expect_equal(nrow(part_row), 1)
  expect_equal(part_row$registered, default_row$registered)
  expect_equal(part_row$dr_all,     default_row$dr_all)
})

test_that("calc_cl_enrls by_part_term stops loudly when part_term is absent", {
  no_pt <- test_students %>% filter(department == "HIST") %>% select(-part_term)
  expect_error(calc_cl_enrls(no_pt, by_part_term = TRUE), "part_term")
})

test_that("calc_cl_enrls registered_mean is mean across term_type not raw sum", {
  # HIST 1110 appears in SP (202010, 202110) and FA (202080) terms.
  # registered_mean for SP rows = mean of the two spring registered counts.
  result <- calc_cl_enrls(test_students %>% filter(department == "HIST"))
  sp_rows <- result %>%
    filter(subject_course == "HIST 1110", term_type == "SP", campus == "ABQ") %>%
    arrange(term)

  # All SP rows for a course share the same _mean value
  expect_equal(length(unique(sp_rows$registered_mean)), 1,
               info = "registered_mean must be identical across all rows of same term_type")

  # The mean must be the average of actual registered counts, not the sum
  expect_lt(sp_rows$registered_mean[1], sum(sp_rows$registered))
})

test_that("calc_cl_enrls with non-NULL reg_status returns only matching codes", {
  # reg_status path: returns raw filtered data, not the full pivot summary
  result <- calc_cl_enrls(test_students %>% filter(department == "HIST"),
                          reg_status = c("DW"))

  expect_true(all(result$registration_status_code == "DW"),
              info = "non-NULL reg_status should filter to only specified codes")
})
