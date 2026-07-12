# Tests for combined C-suffix course enrollment handling
#
# Combined courses (e.g., ANTH 2190C) have multiple CRNs — one per lab section —
# but are a single course. After crosslist dedup, the primary CRN's `enrolled`
# holds only one lab section's count (~16) while `total_enrl` holds the correct
# course-level enrollment (47). These tests verify that all enrollment paths
# report the correct total, not the deflated per-lab number.
#
# Fixture data in designed_test_data.R:
#   ANTH 2190C, Fall 2020 (202080), 3 CRNs in crosslist group "EC"
#   enrolled = 16, 16, 15 (per-lab); total_enrl = 47; crosslist_primary: EC003=TRUE, others=FALSE
#   EC-04: BIOL 2110C, Fall 2020, 4 non-crosslisted CRNs, enrolled=22/22/23/22, total_enrl=89
#   EC-05: BIOL 304C,  Fall 2020, 4 non-crosslisted CRNs, enrolled=25/22/22/20, total_enrl=same
#   EC-06: BIOL 300C,  Fall 2020, 6 internal-crosslist CRNs (groups 6G=92, 62=138), total=230

context("Combined C-suffix courses")

# ---------------------------------------------------------------------------
# Verify fixture data is present
# ---------------------------------------------------------------------------

test_that("test fixtures contain combined-course edge cases", {
  # XL06: ANTH 2190C fall 202080 — crosslisted combined (3 CRNs, 1 primary).
  # Scoped to the fall term: XL06-S adds spring pairs of the same course in
  # 201910/202010/202110 for the dashboard vs-average test (issue #32).
  anth <- test_sections %>% filter(subject_course == "ANTH 2190C", term == 202080)
  expect_equal(nrow(anth), 3L)
  expect_equal(anth$enrolled, c(16L, 16L, 15L))
  expect_true(all(anth$total_enrl == 47L))
  expect_equal(sum(anth$crosslist_primary), 1L)

  # XL06-S: ANTH 2190C spring pairs — internal crosslist, one primary per term;
  # XL06-EA adds a single non-crosslisted EA row in 201910 (campus separation)
  anth_s <- test_sections %>% filter(subject_course == "ANTH 2190C", term != 202080)
  expect_equal(nrow(anth_s), 7L)
  expect_true(all(anth_s$crosslist_role[!is.na(anth_s$crosslist_group)] == "internal"))
  expect_equal(sort(unique(anth_s$term)), c(201910, 202010, 202110))
  expect_equal(sort(unique(anth_s$campus)), c("ABQ", "EA"))

  # EC-04: BIOL 2110C — Pattern A non-crosslisted (4 CRNs, XL_ENRL present)
  biol_a <- test_sections %>% filter(subject_course == "BIOL 2110C")
  expect_equal(nrow(biol_a), 4L)
  expect_equal(sort(biol_a$enrolled), c(22L, 22L, 22L, 23L))
  expect_true(all(biol_a$total_enrl == 89L))
  expect_true(all(is.na(biol_a$crosslist_group)))

  # EC-05: BIOL 304C — Pattern B non-crosslisted (4 CRNs, no XL_ENRL)
  biol_b <- test_sections %>% filter(subject_course == "BIOL 304C")
  expect_equal(nrow(biol_b), 4L)
  expect_equal(sort(biol_b$enrolled), c(20L, 22L, 22L, 25L))
  expect_true(all(biol_b$total_enrl == biol_b$enrolled))
  expect_true(all(is.na(biol_b$crosslist_group)))

  # EC-06: BIOL 300C — Pattern C internal crosslist (2 groups × 3 CRNs)
  biol_c <- test_sections %>% filter(subject_course == "BIOL 300C")
  expect_equal(nrow(biol_c), 6L)
  expect_true(all(biol_c$crosslist_role == "internal"))
  expect_equal(sort(unique(biol_c$crosslist_group)), c("62", "6G"))
  # Group totals: sum(enrolled per group) equals total_enrl for that group
  group_sums <- biol_c %>%
    group_by(crosslist_group) %>%
    summarize(sum_enrl = sum(enrolled), total = unique(total_enrl), .groups = "drop")
  expect_true(all(group_sums$sum_enrl == group_sums$total))
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

# Pattern A: non-crosslisted C course WITH XL_ENRL (total_enrl > enrolled).
# Fixture EC-04: BIOL 2110C, Fall 2020, 4 CRNs, enrolled=22/22/23/22, total_enrl=89.
# Banner populates XL_ENRL = course total on every lab row; enrolled = per-lab count.
# Without dedup, correction inflates every row to course total → n-fold overcounting.
test_that("get_enrl() does not overcount Pattern A non-crosslisted combined courses", {
  result <- get_enrl(test_sections, opt = list(
    dept      = "BIOL",
    term      = 202080L,
    crosslist = "home"
  ))

  biol_2110c <- result %>% dplyr::filter(subject_course == "BIOL 2110C")

  # Correction → dedup: 1 row with enrolled = total_enrl = 89, not 4 × 89 = 356
  expect_equal(nrow(biol_2110c), 1L)
  expect_equal(biol_2110c$enrolled, 89L)
})

# Pattern B: non-crosslisted C course WITHOUT XL_ENRL (total_enrl == enrolled).
# Fixture EC-05: BIOL 304C, Fall 2020, 4 CRNs, enrolled=25/22/22/20, total_enrl=same.
# No shared XL total; each lab row carries its own per-section count.
# Natural sum (25+22+22+20=89) is already correct — dedup must NOT fire.
test_that("get_enrl() does not undercount Pattern B non-crosslisted combined courses", {
  result <- get_enrl(test_sections, opt = list(
    dept       = "BIOL",
    term       = 202080L,
    crosslist  = "home",
    group_cols = c("subject_course", "course_title", "term")
  ))

  biol_304c <- result %>% dplyr::filter(subject_course == "BIOL 304C")

  # Natural sum: 25+22+22+20 = 89 — dedup must not fire and discard sections
  expect_equal(biol_304c$enrolled, 89L)
})

# Pattern C: internal crosslist C course (the BIOL 300C / BIOL 304C pattern).
# Fixture EC-06: BIOL 300C, Fall 2020, 6 CRNs across 2 internal crosslist groups.
#   Group 6G: enrolled=0/45/47 (sum=92), total_enrl=92 on every row.
#   Group 62: enrolled=0/68/70 (sum=138), total_enrl=138 on every row.
# Individual rows appear Pattern A (total_enrl > enrolled) but the groups
# naturally sum correctly. The fix must skip the correction + dedup entirely.
test_that("get_enrl() does not collapse Pattern C internal-crosslist combined courses", {
  result <- get_enrl(test_sections, opt = list(
    dept       = "BIOL",
    term       = 202080L,
    crosslist  = "home",
    group_cols = c("subject_course", "course_title", "term")
  ))

  biol_300c <- result %>% dplyr::filter(subject_course == "BIOL 300C")

  # Natural sum across both groups: (0+45+47) + (0+68+70) = 92 + 138 = 230
  expect_equal(biol_300c$enrolled,   230L)
  # total_enrl must also equal 230 — dashboard displays total_enrl, not enrolled.
  # Without the Pattern C normalization, sum(total_enrl) = 3×92 + 3×138 = 690.
  expect_equal(biol_300c$total_enrl, 230L)
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
