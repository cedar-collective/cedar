# Gen Ed tables are grouped by campus, not just filtered by it.
#
# The same course delivered in ABQ and online through EA draws different student
# populations, and the default Gen Ed scope covers both, so a blended DFW rate
# hides the gap a chair is looking for. Adding campus to the grouping means
# every join downstream has to carry it too — a join keyed on
# (department, subject_course) against a table that is now one row per campus
# fans out silently and attaches the wrong course rate to an instructor.
#
# These tests pin the grain and the joins, not the presentation.

context("Gen Ed campus split")

ge_profile <- function(min_n = 1L, instructor = TRUE) {
  suppressMessages(get_gen_ed_profile(
    test_students, test_sections, test_programs, NULL,
    list(min_n = min_n,
         include_instructor_dfw = instructor,
         include_associations = FALSE)
  ))
}

# MC01 in designed_test_data.R mirrors the ABQ gen_ed_assoc rows onto EA: same
# course, same instructors, different students, opposite outcomes. Everything
# below reads from that fixture rather than building tibbles here.
ge_two_campus_profile <- function(min_n = 1L) {
  suppressMessages(get_gen_ed_profile(
    gen_ed_assoc_students,
    gen_ed_assoc_sections,
    gen_ed_assoc_programs,
    opt = list(dept_code = "HIST", min_n = min_n, include_instructor_dfw = TRUE)
  ))
}

test_that("dfw_by_course is one row per campus per course", {
  d <- ge_profile()$dfw_by_course
  skip_if(nrow(d) == 0, "fixture produced no DFW rows")

  expect_true("campus" %in% names(d))
  expect_equal(
    nrow(dplyr::distinct(d, campus, department, subject_course)),
    nrow(d)
  )
})

test_that("one course on two campuses produces two rows, not one blended row", {
  d <- ge_two_campus_profile()$dfw_by_course
  expect_setequal(d$campus, c("ABQ", "EA"))
  expect_equal(nrow(d), 2)

  # The whole point of the split: these must not average into one number.
  expect_equal(d$dfw_pct_display[d$campus == "ABQ"], 33.33, tolerance = 0.01)
  expect_equal(d$dfw_pct_display[d$campus == "EA"], 100)
})

test_that("grade_dist splits by campus so its rows line up with the DFW table", {
  # These two tables sit on the same page. If one is per campus and the other is
  # not, the same course shows a different number of rows in each and the page
  # reads as though the data disagrees with itself.
  r <- ge_two_campus_profile()
  g <- r$grade_dist
  expect_true("campus" %in% names(g))
  expect_setequal(g$campus, c("ABQ", "EA"))
  expect_setequal(
    paste(g$campus, g$subject_course),
    paste(r$dfw_by_course$campus, r$dfw_by_course$subject_course)
  )
})

test_that("instructor_dfw is one row per campus per course per instructor", {
  i <- ge_two_campus_profile()$instructor_dfw
  expect_true("campus" %in% names(i))
  expect_equal(
    nrow(dplyr::distinct(i, campus, department, subject_course, instructor_name)),
    nrow(i)
  )
  # Two instructors on two campuses.
  expect_equal(nrow(i), 4)
})

test_that("an instructor is compared against the course rate on their own campus", {
  # This is the join that fans out if campus is dropped from the keys. A miss
  # shows up as NA; a fan-out shows up as extra rows and a wrong course rate.
  r <- ge_two_campus_profile()
  d <- r$dfw_by_course
  i <- r$instructor_dfw

  expect_equal(sum(is.na(i$course_dfw_rate)), 0)

  joined <- dplyr::inner_join(
    i,
    dplyr::select(d, campus, department, subject_course, ref_rate = dfw_rate),
    by = c("campus", "department", "subject_course")
  )
  expect_equal(nrow(joined), nrow(i))
  expect_equal(joined$course_dfw_rate, joined$ref_rate)

  # Adams taught on both campuses. Her EA row must be measured against the EA
  # course rate (1.0), not the ABQ one — the specific error the keys prevent.
  adams_ea <- dplyr::filter(i, instructor_name == "Adams, Erin", campus == "EA")
  expect_equal(nrow(adams_ea), 1)
  expect_equal(adams_ea$course_dfw_rate, 1)
})

test_that("the instructor table's two rate columns agree with their 0-1 twins", {
  # The table renders dfw_pct_display and course_dfw_pct_display; the 0-1 forms
  # feed the plot. If they ever disagree the table and chart tell different
  # stories about the same instructor.
  i <- ge_two_campus_profile()$instructor_dfw

  expect_equal(i$dfw_pct_display, round(100 * i$dfw_rate, 1))
  expect_equal(i$course_dfw_pct_display, round(100 * i$course_dfw_rate, 1))
})

test_that("DFW % still equals Below C % + W % after the split", {
  # The split changes the denominator per row, so the identity the UI advertises
  # has to be re-checked at the new grain.
  d <- ge_profile()$dfw_by_course
  skip_if(nrow(d) == 0, "fixture produced no DFW rows")

  expect_equal(
    d$dfw_pct_display,
    round(d$below_c_no_w_pct + d$w_pct, 2),
    tolerance = 0.02
  )
})

test_that("the table renderers can select every column they display", {
  # The renderers name most columns bare, so a column missing from either the
  # populated or the empty shape is a runtime error on a tab nobody may open
  # until a chair does. dplyr::select() raises exactly that error, so running
  # the real select lists here is the check.
  course_sel <- function(d) {
    dplyr::select(d, dplyr::any_of("campus"), department, subject_course,
                  n_enrolled, early_drop_pct, dfw_pct_display, below_c_no_w_pct,
                  w_pct, c_minus_pct, d_pct, f_pct)
  }
  instr_sel <- function(d) {
    dplyr::select(d, dplyr::any_of("campus"), subject_course, instructor_name,
                  n_attempts, early_drop_pct, dfw_pct_display,
                  course_dfw_pct_display, dfw_diff_pp, below_c_no_w_pct, w_pct,
                  c_minus_pct, d_pct, f_pct, n_terms)
  }

  # Populated, and the empty shape the report falls back to when the small-cell
  # guard removes everything. Both must satisfy the same select.
  populated <- ge_two_campus_profile(min_n = 1L)
  empty     <- ge_two_campus_profile(min_n = 9999L)

  expect_no_error(course_sel(populated$dfw_by_course))
  expect_no_error(instr_sel(populated$instructor_dfw))

  expect_equal(nrow(empty$dfw_by_course), 0L)
  expect_no_error(course_sel(empty$dfw_by_course))
  expect_no_error(instr_sel(empty$instructor_dfw))
})

test_that("headline DFW does not move when the small-cell guard drops table rows", {
  # overall_dfw and the per-department cards are computed from their own
  # unfiltered rate table. If they were summed out of dfw_by_course instead,
  # raising min_n would silently drag the headline number with it.
  loose  <- ge_profile(min_n = 1L,   instructor = FALSE)
  strict <- ge_profile(min_n = 500L, instructor = FALSE)

  expect_lt(nrow(strict$dfw_by_course), nrow(loose$dfw_by_course))
  expect_equal(strict$summary$overall_dfw, loose$summary$overall_dfw)

  if (!is.null(loose$summary_by_dept) && nrow(loose$summary_by_dept) > 0) {
    expect_equal(
      strict$summary_by_dept$overall_dfw,
      loose$summary_by_dept$overall_dfw
    )
  }
})
