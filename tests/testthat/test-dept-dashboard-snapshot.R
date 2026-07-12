# Tests for the Dept Dashboard current-term snapshot functions
# (R/reports/dept-dashboard.R). Regression coverage for issue #32:
# ANTH 2190C showed "51 down from an average of 47" because the displayed
# number (total_enrl) and the comparison basis (a single lab CRN's enrolled)
# came from different columns, and the historical average mixed whole-course
# totals with single-section counts. get_current_enrl_vs_avg() must compare
# crosslist-deduplicated course totals on BOTH sides, and the number shown
# must be the number the diff was computed from.
#
# Fixture design (XL06 / XL06-S in designed_test_data.R):
#   ANTH 2190C springs — 201910 total 52, 202010 total 50, 202110 total 47,
#   each term an internal-crosslist pair whose rows carry the course total in
#   total_enrl and per-lab counts in enrolled.
#   ANTH 2190C fall — 202080 total 47 (must not enter the spring average).

# The dashboard's exact course_history build (create_dept_dashboard_data).
build_dashboard_course_history <- function(dept) {
  ch_opt <- list(dept = dept, status = "A", crosslist = "home", uel = TRUE,
                 group_cols = c("subject_course", "course_title", "term"))
  get_enrl(test_sections, ch_opt) %>% dplyr::filter(enrolled > 0)
}

test_that("course_history reports combined courses at course-level totals, not per-lab counts", {
  ch <- build_dashboard_course_history("ANTH") %>%
    dplyr::filter(subject_course == "ANTH 2190C") %>%
    dplyr::arrange(term)

  springs <- ch %>% dplyr::filter(term %in% c(201910, 202010, 202110))
  expect_equal(springs$term, c(201910, 202010, 202110))
  # Each spring is a 2-CRN internal group: the group total must be counted
  # once (52/50/47), not per-row (104/100/94) and not one lab's count (26/25/24).
  expect_equal(springs$total_enrl, c(52, 50, 47))
  # For internal groups the home filter keeps all rows, so summed enrolled
  # equals the course total — enrolled and total_enrl must agree.
  expect_equal(springs$enrolled, springs$total_enrl)
})

test_that("get_current_enrl_vs_avg flags combined courses on deduplicated same-season totals", {
  ch <- build_dashboard_course_history("ANTH")
  cmp <- get_current_enrl_vs_avg(ch, 202110)

  row <- cmp$below %>% dplyr::filter(subject_course == "ANTH 2190C")
  expect_equal(nrow(row), 1)

  # The displayed number is the full combined enrollment...
  expect_equal(row$total_enrl, 47)
  # ...the average is over prior SPRING course totals only: (52 + 50) / 2.
  # The fall 202080 offering (total 47) must not contaminate the spring average.
  expect_equal(row$hist_avg_enrl, 51)
  expect_equal(row$n_hist, 2)
  # ...and the diff is computed from the same number that is displayed
  # (the issue #32 failure showed total 51 while diffing a lab CRN's 17).
  expect_equal(row$diff, -4L)
  expect_equal(row$diff, as.integer(round(row$total_enrl - row$hist_avg_enrl)))
  expect_equal(row$pct_diff, -8L)

  # A below-average course must not also appear as above-average.
  expect_false("ANTH 2190C" %in% cmp$above$subject_course)
})

test_that("get_current_enrl_vs_avg requires two prior same-season offerings", {
  ch <- build_dashboard_course_history("ANTH")
  cmp <- get_current_enrl_vs_avg(ch, 202110)
  flagged <- dplyr::bind_rows(cmp$above, cmp$below)

  # Everything flagged cleared the n_hist >= 2 gate.
  expect_true(all(flagged$n_hist >= 2))

  # Only ANTH 2190C has rows in 201910, so every other ANTH course current in
  # 202110 has at most one prior spring and must be excluded. If this fails
  # after a fixture change, another course now spans >= 3 springs — update
  # the design notes in designed_test_data.R, not just this expectation.
  expect_equal(flagged$subject_course, "ANTH 2190C")
})
