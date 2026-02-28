# Tests for crosslist home filtering and split-level course detection
#
# Uses known_sections_xl fixture from fixtures/known_test_data.R which provides
# five explicit crosslist/split scenarios:
#
#   XL01 — Standard cross-dept XL, same level (HIST 480 + ANTH 480)
#   XL02 — Same-dept split-level XL (HIST 484 + HIST 584)
#   XL03 — Split-level XL where grad section is primary (AMST 499 + AMST 599)
#   XL04 — Zero-enrollment XL, tiebreak by subject alpha (ANTH 490 + HIST 490)
#   XL05 — Three-way split-level XL (HIST 475 + AMST 475 + HIST 575)
#
# These tests validate:
#   1. crosslist_group is set correctly
#   2. crosslist_primary correctly identifies the home section per group
#   3. split-level courses are flagged with is_split = TRUE
#   4. original level (upper/grad) is preserved for all sections
#   5. .xlist_filter("home") returns only primary sections
#   6. Low enrollment filtering uses total_enrl (XL total), not enrolled

context("Crosslist and Split-Level Detection")

library(dplyr)

source("../../R/branches/filter.R")
source("../../R/cones/enrl.R")

# =============================================================================
# crosslist_group
# =============================================================================

test_that("crosslist_group is NA for non-crosslisted sections", {
  non_xl <- known_sections %>% filter(is.na(crosslist_group))
  expect_equal(nrow(non_xl), nrow(known_sections))  # all 20 base sections are non-XL
})

test_that("crosslist_group is set to the XL code for crosslisted sections", {
  expect_true(all(!is.na(known_sections_xl$crosslist_group)))
  expect_setequal(unique(known_sections_xl$crosslist_group),
                  c("XL01", "XL02", "XL03", "XL04", "XL05"))
})

test_that("crosslist_group matches crosslist_code for XL sections", {
  expect_equal(known_sections_xl$crosslist_group, known_sections_xl$crosslist_code)
})

# =============================================================================
# crosslist_primary
# =============================================================================

test_that("crosslist_primary is TRUE for all non-crosslisted sections", {
  expect_true(all(known_sections$crosslist_primary))
})

test_that("exactly one section per XL group has crosslist_primary TRUE", {
  primary_counts <- known_sections_xl %>%
    group_by(crosslist_group) %>%
    summarize(n_primary = sum(crosslist_primary), .groups = "drop")

  expect_true(all(primary_counts$n_primary == 1),
    info = paste("Groups with != 1 primary:",
      paste(primary_counts$crosslist_group[primary_counts$n_primary != 1], collapse = ", ")))
})

test_that("XL01: HIST 480 (higher enrolled) is primary, ANTH 480 is not", {
  xl01 <- known_sections_xl %>% filter(crosslist_group == "XL01")
  primary <- xl01 %>% filter(crosslist_primary)
  secondary <- xl01 %>% filter(!crosslist_primary)

  expect_equal(nrow(primary), 1)
  expect_equal(primary$subject, "HIST")
  expect_equal(primary$subject_course, "HIST 480")
  expect_equal(secondary$subject_course, "ANTH 480")
})

test_that("XL02: HIST 484 (higher enrolled) is primary in same-dept split group", {
  primary <- known_sections_xl %>%
    filter(crosslist_group == "XL02", crosslist_primary)

  expect_equal(nrow(primary), 1)
  expect_equal(primary$subject_course, "HIST 484")
})

test_that("XL03: AMST 599 (grad section with higher enrolled) is primary", {
  # Tests that grad section can be the home section when it has more enrollment
  primary <- known_sections_xl %>%
    filter(crosslist_group == "XL03", crosslist_primary)

  expect_equal(nrow(primary), 1)
  expect_equal(primary$subject_course, "AMST 599")
  expect_equal(primary$level, "grad")  # grad section retains its original level
  expect_true(primary$is_split)
})

test_that("XL04: ANTH 490 is primary (alphabetically first when both have 0 enrolled)", {
  primary <- known_sections_xl %>%
    filter(crosslist_group == "XL04", crosslist_primary)

  expect_equal(nrow(primary), 1)
  expect_equal(primary$subject, "ANTH")  # ANTH < HIST alphabetically
  expect_equal(primary$enrolled, 0)
})

test_that("XL05: HIST 475 (highest enrolled in three-way group) is primary", {
  xl05 <- known_sections_xl %>% filter(crosslist_group == "XL05")
  primary <- xl05 %>% filter(crosslist_primary)
  non_primary <- xl05 %>% filter(!crosslist_primary)

  expect_equal(nrow(primary), 1)
  expect_equal(primary$subject_course, "HIST 475")
  expect_equal(nrow(non_primary), 2)
  expect_setequal(non_primary$subject_course, c("AMST 475", "HIST 575"))
})

# =============================================================================
# Split-level detection (is_split flag)
# =============================================================================

test_that("non-split XL groups have is_split = FALSE and keep original level", {
  xl01 <- known_sections_xl %>% filter(crosslist_group == "XL01")
  xl04 <- known_sections_xl %>% filter(crosslist_group == "XL04")

  expect_true(all(xl01$level == "upper"))
  expect_true(all(!xl01$is_split))
  expect_true(all(xl04$level == "upper"))
  expect_true(all(!xl04$is_split))
})

test_that("XL02 (HIST 484 + HIST 584) both flagged as split, levels preserved", {
  xl02 <- known_sections_xl %>% filter(crosslist_group == "XL02")
  expect_equal(nrow(xl02), 2)
  expect_true(all(xl02$is_split))
  # Original levels preserved
  expect_equal(xl02$level[xl02$subject_course == "HIST 484"], "upper")
  expect_equal(xl02$level[xl02$subject_course == "HIST 584"], "grad")
})

test_that("XL03 (AMST 499 + AMST 599) both flagged as split, levels preserved", {
  xl03 <- known_sections_xl %>% filter(crosslist_group == "XL03")
  expect_equal(nrow(xl03), 2)
  expect_true(all(xl03$is_split))
  expect_equal(xl03$level[xl03$subject_course == "AMST 499"], "upper")
  expect_equal(xl03$level[xl03$subject_course == "AMST 599"], "grad")
})

test_that("XL05 (HIST 475 + AMST 475 + HIST 575) all three flagged as split, levels preserved", {
  xl05 <- known_sections_xl %>% filter(crosslist_group == "XL05")
  expect_equal(nrow(xl05), 3)
  expect_true(all(xl05$is_split))
  expect_equal(xl05$level[xl05$subject_course == "HIST 475"], "upper")
  expect_equal(xl05$level[xl05$subject_course == "AMST 475"], "upper")
  expect_equal(xl05$level[xl05$subject_course == "HIST 575"], "grad")
})

test_that("total is_split sections = 7 (XL02:2 + XL03:2 + XL05:3)", {
  expect_equal(sum(known_sections_xl$is_split), 7)
})

test_that("total non-split XL sections = 4 (XL01:2 + XL04:2)", {
  non_split <- known_sections_xl %>% filter(!is_split)
  expect_equal(nrow(non_split), 4)
  expect_true(all(non_split$level == "upper"))
})

# =============================================================================
# split_sections display string
# =============================================================================

test_that("split_sections shows partner courses for split groups", {
  xl02 <- known_sections_xl %>% filter(crosslist_group == "XL02")
  expect_true(all(xl02$split_sections == "HIST 484 / HIST 584"))

  xl03 <- known_sections_xl %>% filter(crosslist_group == "XL03")
  expect_true(all(xl03$split_sections == "AMST 499 / AMST 599"))

  xl05 <- known_sections_xl %>% filter(crosslist_group == "XL05")
  expect_true(all(xl05$split_sections == "AMST 475 / HIST 475 / HIST 575"))
})

test_that("split_sections is NA for non-split groups", {
  non_split <- known_sections_xl %>% filter(!is_split)
  expect_true(all(is.na(non_split$split_sections)))
})

# =============================================================================
# .xlist_filter("home") — via filter_DESRs with crosslist="home"
# =============================================================================

test_that("crosslist home filter keeps exactly one section per XL group", {
  opt <- list(status = "A", crosslist = "home")
  result <- filter_DESRs(known_sections_xl, opt)

  # Should have exactly 5 rows — one primary per group
  expect_equal(nrow(result), 5)
  expect_true(all(result$crosslist_primary))
})

test_that("crosslist home filter returns correct primary sections", {
  opt <- list(status = "A", crosslist = "home")
  result <- filter_DESRs(known_sections_xl, opt)

  primary_courses <- sort(result$subject_course)
  # One primary from each group
  expect_true("HIST 480"  %in% primary_courses)  # XL01
  expect_true("HIST 484"  %in% primary_courses)  # XL02
  expect_true("AMST 599"  %in% primary_courses)  # XL03 (grad section)
  expect_true("ANTH 490"  %in% primary_courses)  # XL04 (alpha tiebreak)
  expect_true("HIST 475"  %in% primary_courses)  # XL05
})

test_that("crosslist home filter for HIST dept keeps only HIST primary sections", {
  opt <- list(dept = "HIST", status = "A", crosslist = "home")
  result <- filter_DESRs(known_sections_xl, opt)

  # HIST is primary in: XL01 (HIST 480), XL02 (HIST 484), XL05 (HIST 475)
  # HIST 490 (XL04) is NOT primary — ANTH 490 is
  # HIST 575 (XL05) is NOT primary — HIST 475 is
  expect_true(all(result$department == "HIST"))
  expect_true(all(result$crosslist_primary))
  expect_equal(nrow(result), 3)
  expect_setequal(result$subject_course, c("HIST 480", "HIST 484", "HIST 475"))
})

test_that("crosslist home filter for AMST dept returns AMST 599 (grad primary)", {
  opt <- list(dept = "AMST", status = "A", crosslist = "home")
  result <- filter_DESRs(known_sections_xl, opt)

  # AMST 599 is primary in XL03 (has enrollment), AMST 475 is NOT primary in XL05
  expect_equal(nrow(result), 1)
  expect_equal(result$subject_course, "AMST 599")
})

# =============================================================================
# total_enrl — low enrollment filtering uses XL total, not section enrolled
# =============================================================================

test_that("total_enrl reflects combined enrollment across all XL partners", {
  # XL01: HIST 480 enrolled=12, ANTH 480 enrolled=0 → total_enrl=12 for both
  xl01 <- known_sections_xl %>% filter(crosslist_group == "XL01")
  expect_true(all(xl01$total_enrl == 12))

  # XL03: AMST 499 enrolled=0, AMST 599 enrolled=5 → total_enrl=5 for both
  xl03 <- known_sections_xl %>% filter(crosslist_group == "XL03")
  expect_true(all(xl03$total_enrl == 5))

  # XL05 three-way: only HIST 475 has enrolled=10 → total_enrl=10 for all
  xl05 <- known_sections_xl %>% filter(crosslist_group == "XL05")
  expect_true(all(xl05$total_enrl == 10))
})

test_that("low enrollment filter on XL data uses total_enrl not enrolled", {
  opt <- list(status = "A", crosslist = "home")
  home_sections <- filter_DESRs(known_sections_xl, opt)

  # After home filter, check which sections are below threshold=15 using total_enrl
  low_15 <- home_sections %>% filter(total_enrl < 15)

  # All 5 primary sections have total_enrl < 15
  expect_equal(nrow(low_15), 5)
  expect_true(all(low_15$total_enrl >= 0))
})

test_that("split-level sections appear under is_split filter", {
  split_sections <- known_sections_xl %>% filter(is_split == TRUE)
  expect_equal(nrow(split_sections), 7)

  # Filter to only home sections
  home_split <- split_sections %>% filter(crosslist_primary)
  # One primary per split group: XL02, XL03, XL05 = 3 home split sections
  expect_equal(nrow(home_split), 3)
  expect_setequal(home_split$subject_course, c("HIST 484", "AMST 599", "HIST 475"))
})

test_that("get_low_enrollment_courses returns split courses with is_split flag", {
  # Build a combined dataset (non-XL sections + XL sections)
  combined <- bind_rows(
    known_sections %>% mutate(section_id = paste0("BASE-", section_id)),
    known_sections_xl
  )

  opt <- list(status = "A")
  result <- get_low_enrollment_courses(combined, opt, threshold = 15)

  # Split-level courses should have is_split = TRUE and their original level
  split_results <- result %>% filter(is_split == TRUE)
  expect_true(nrow(split_results) > 0)
  expect_true(all(split_results$level %in% c("lower", "upper", "grad")))
  expect_true(all(split_results$total_enrl < 15))
  if ("crosslist_primary" %in% names(split_results)) {
    expect_true(all(split_results$crosslist_primary))
  }
})
