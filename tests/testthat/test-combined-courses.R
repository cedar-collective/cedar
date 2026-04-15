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
# Non-crosslisted combined courses (the real Organismal Physiology pattern)
# ---------------------------------------------------------------------------
# Some C-suffix courses have multiple lab CRNs with NO crosslist_group — they
# are just separate sections. The crosslist "home" filter does not reduce them
# to one row. After enrolled → total_enrl correction, each row carries the full
# course enrollment; the dedup step must eliminate the extras before aggregation.

test_that("get_enrl() does not overcount non-crosslisted combined courses", {
  # Minimal fixture: 4 lab CRNs for BIOL 2410C, no crosslist_group.
  # Each section has enrolled = 22/22/23/22 (per-lab) and total_enrl = 89 (course total).
  # Without the dedup fix, sum = 4 × 89 = 356.
  non_xl_combined <- tibble::tibble(
    section_id        = c("BIOL01","BIOL02","BIOL03","BIOL04"),
    term              = 202610L,
    crn               = c("C001","C002","C003","C004"),
    subject           = "BIOL",
    course_number     = "2410C",
    subject_course    = "BIOL 2410C",
    section           = c("001","002","003","004"),
    course_title      = "Organismal Physiology",
    part_term         = "1",
    campus            = "ABQ",
    college           = "ARTS",
    department        = "BIOL",
    instructor_id     = "INS001",
    instructor_name   = "Smith, Jane",
    enrolled          = c(22L, 22L, 23L, 22L),
    total_enrl        = 89L,
    capacity          = 25L,
    available         = c(3L, 3L, 2L, 3L),
    status            = "A",
    delivery_method   = "ENH",
    level             = "lower",
    term_type         = "SP",
    waitlist_count    = 0L,
    waitlist_capacity = 0L,
    crosslist_primary = TRUE,   # non-XL rows are all primary by convention
    is_split          = FALSE,
    credits_min       = 4.0,
    credits_max       = 4.0,
    start_date        = as.Date("2026-01-20"),
    end_date          = as.Date("2026-05-08"),
    crosslist_code    = "0",
    crosslist_group   = NA_character_,  # NOT crosslisted
    crosslist_role    = NA_character_,
    crosslist_external = FALSE,
    crosslist_partners = NA_character_,
    split_sections    = NA_character_,
    is_combined       = TRUE,
    is_topics         = FALSE,
    job_cat           = NA_character_,
    gen_ed_area       = NA_integer_,
    as_of_date        = as.Date("2026-01-20")
  )

  result <- get_enrl(non_xl_combined, opt = list(
    dept      = "BIOL",
    term      = 202610L,
    crosslist = "home"
  ))

  biol_combined <- result %>% dplyr::filter(subject_course == "BIOL 2410C")

  # Should collapse to 1 row with correct total, not 4 × 89 = 356
  expect_equal(nrow(biol_combined), 1L)
  expect_equal(biol_combined$enrolled, 89L)
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
