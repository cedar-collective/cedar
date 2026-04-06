# Tests for combined C-suffix course enrollment handling
#
# Combined courses (e.g., ANTH 2190C) have multiple CRNs — one per lab section —
# but are a single course. After crosslist dedup, the primary CRN's `enrolled`
# holds only one lab section's count (~16) while `total_enrl` holds the correct
# course-level enrollment (47). These tests verify that all enrollment paths
# report the correct total, not the deflated per-lab number.
#
# Fixture data: EC-03 edge case in create-test-fixtures.R
#   ANTH 2190C, Fall 2020 (202080), 3 CRNs in crosslist group "EC"
#   enrolled = 16, 16, 15 (per-lab)
#   total_enrl = 47 (correct course total, same on all 3 CRNs)
#   crosslist_primary: EC003=TRUE, EC004=FALSE, EC005=FALSE

context("Combined C-suffix courses")

# ---------------------------------------------------------------------------
# Verify fixture data is present
# ---------------------------------------------------------------------------

test_that("test fixtures contain combined-course edge cases", {
  combined <- test_sections %>% filter(is_combined == TRUE)
  expect_equal(nrow(combined), 3L)
  expect_true(all(combined$subject_course == "ANTH 2190C"))
  expect_equal(combined$enrolled, c(16L, 16L, 15L))
  expect_true(all(combined$total_enrl == 47L))
  expect_equal(sum(combined$crosslist_primary), 1L)
})

# ---------------------------------------------------------------------------
# get_enrl() should report total_enrl, not per-lab enrolled
# ---------------------------------------------------------------------------

test_that("get_enrl() reports correct enrollment for combined courses", {
  result <- get_enrl(test_sections, opt = list(
    dept = "ANTH",
    term = 202080,
    campus = "ABQ",
    crosslist = "home"
  ))

  anth_combined <- result %>%
    filter(subject_course == "ANTH 2190C")

  # After crosslist home filter + combined correction:
  # only 1 row (primary CRN), enrolled corrected to total_enrl = 47
  expect_equal(nrow(anth_combined), 1L)
  expect_equal(anth_combined$enrolled, 47L)
})

test_that("get_enrl() does not inflate non-combined course enrollment", {
  result <- get_enrl(test_sections, opt = list(
    dept = "ANTH",
    term = 202080,
    campus = "ABQ",
    crosslist = "home"
  ))

  # Non-combined ANTH courses should have enrolled unchanged
  non_combined <- result %>%
    filter(subject_course != "ANTH 2190C")

  # For non-combined rows, enrolled should equal total_enrl (no correction needed)
  # or be less than total_enrl for regular crosslists — but never inflated
  for (i in seq_len(nrow(non_combined))) {
    expect_true(non_combined$enrolled[i] <= non_combined$total_enrl[i],
      info = paste("Row", i, non_combined$subject_course[i],
                   "enrolled=", non_combined$enrolled[i],
                   "total_enrl=", non_combined$total_enrl[i]))
  }
})

# ---------------------------------------------------------------------------
# get_course_enrollment_history() should use total_enrl after XL dedup
# ---------------------------------------------------------------------------

test_that("get_course_enrollment_history() uses total_enrl for combined courses", {
  history <- get_course_enrollment_history(
    courses    = test_sections,
    campus     = "ABQ",
    dept       = "ANTH",
    subj_crse  = "ANTH 2190C",
    crse_title = "Forensic Anthropology",
    im         = NULL,
    n_terms    = 10
  )

  fall_2020 <- history %>% filter(term == 202080)
  expect_equal(nrow(fall_2020), 1L)
  # Should be 47 (total_enrl), not 16 (single lab CRN enrolled)
  expect_equal(fall_2020$enrolled, 47L)
})
