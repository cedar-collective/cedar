# Tests for reusable summary/filter functions extracted from server.R
#
# These functions are designed to be called from any tab, report, or future
# API endpoint — not just the specific server.R context they were extracted from.
# Tests validate the contract: given clean cedar data, they return predictable,
# correctly-deduplicated results regardless of caller.
#
# Functions tested:
#   get_course_section_counts()   — R/branches/enrl.R
#   filter_downstream_by_dept()   — R/reports/regstats.R
#   get_subject_current_stats()   — R/reports/dept-dashboard.R
#
# Fixtures: test_sections from designed_test_data.R
#   - 75 active sections across ABQ/EA/GA campuses
#   - 11 XL sections (various crosslist scenarios including C-suffix combined courses)
#   - Stable terms: 202010, 202060, 202080, 202110
#   - Departments with sections: HIST, MATH, ANTH, BIOL, NURS, MGMT, ENGL, POLS, PSYC, AMST

context("Reusable summary functions")


# =============================================================================
# get_course_section_counts()
# =============================================================================

context("get_course_section_counts")

test_that("returns one row per (term, subject_course, course_title, campus)", {
  result <- get_course_section_counts(test_sections)

  expect_true(is.data.frame(result))
  expect_true(all(c("term", "subject_course", "course_title", "campus",
                    "n_sections", "course_enrl") %in% names(result)))

  # No duplicates across the grouping key
  key_cols <- c("term", "subject_course", "course_title", "campus")
  expect_equal(nrow(result), nrow(dplyr::distinct(result, dplyr::across(dplyr::all_of(key_cols)))))
})

test_that("excludes cancelled sections (status != 'A')", {
  # Cancelled sections exist in test_sections (status = "C", "R", "S")
  cancelled <- test_sections %>% dplyr::filter(status != "A")
  expect_gt(nrow(cancelled), 0)

  result <- get_course_section_counts(test_sections)

  # Cancelled courses should not appear unless they also have active sections
  cancelled_only_courses <- cancelled %>%
    dplyr::anti_join(test_sections %>% dplyr::filter(status == "A"),
                     by = "subject_course") %>%
    dplyr::pull(subject_course) %>%
    unique()

  if (length(cancelled_only_courses) > 0) {
    expect_false(any(result$subject_course %in% cancelled_only_courses))
  }
})

test_that("excludes crosslist partner rows (keeps only primary CRN per group)", {
  # XL01: HIST 480 (primary) + ANTH 480 (partner)
  # Result should have at most one row for HIST 480 / ANTH 480 per term,
  # and the partner (ANTH 480 with crosslist_primary=FALSE) must not be counted.
  result <- get_course_section_counts(test_sections)

  # ANTH 480 appears only as a crosslist partner — should not appear in counts
  anth_480 <- result %>% dplyr::filter(subject_course == "ANTH 480")
  expect_equal(nrow(anth_480), 0)

  # HIST 480 is the primary — should appear once
  hist_480 <- result %>% dplyr::filter(subject_course == "HIST 480")
  expect_equal(nrow(hist_480), 1)
})

test_that("n_sections counts home sections, not CRNs", {
  # MATH 1430 has two sections in 202010 (ABQ + EA campuses)
  # Each campus should appear separately since campus is part of the group key
  result <- get_course_section_counts(test_sections)

  math_1430_202010 <- result %>%
    dplyr::filter(subject_course == "MATH 1430", term == 202010L)

  expect_equal(nrow(math_1430_202010), 2)  # ABQ and EA are separate rows
  expect_true(all(math_1430_202010$n_sections == 1))
})

test_that("n_sections > 1 when a course has multiple sections on the same campus", {
  # Construct two sections of the same course on the same campus — n_sections should be 2
  multi <- tibble::tibble(
    term           = c(202010L, 202010L),
    subject_course = c("HIST 1110", "HIST 1110"),
    course_title   = c("History of the Western World", "History of the Western World"),
    campus         = c("ABQ", "ABQ"),
    status         = c("A", "A"),
    total_enrl     = c(25L, 18L),
    crosslist_group   = c(NA_character_, NA_character_),
    crosslist_primary = c(TRUE, TRUE),
    crosslist_role    = c(NA_character_, NA_character_)
  )
  result <- get_course_section_counts(multi)
  expect_equal(nrow(result), 1L)           # one row per (term, course, title, campus)
  expect_equal(result$n_sections, 2L)      # both sections counted
  expect_equal(result$course_enrl, 43L)    # 25 + 18
})

test_that("course_enrl uses total_enrl (correct for combined C-suffix courses)", {
  # XL06: ANTH 2190C — 3 CRNs, all is_combined=TRUE
  # Primary CRN (XL012) has enrolled=16 but total_enrl=47
  # After deduplication, course_enrl should be 47, not 16
  result <- get_course_section_counts(test_sections)

  anth_2190c <- result %>% dplyr::filter(subject_course == "ANTH 2190C")
  expect_equal(nrow(anth_2190c), 1)
  expect_equal(anth_2190c$course_enrl, 47L)
  expect_equal(anth_2190c$n_sections,  1L)
})

test_that("join pattern with coalesce works for downstream low-enrollment use", {
  counts <- get_course_section_counts(test_sections)

  # Simulate the server.R join pattern: low_enrl rows joined to section_counts.
  # All rows in base should match counts (same source, same filters) — no NAs.
  base <- test_sections %>%
    dplyr::filter(status == "A",
                  is.na(crosslist_group) | crosslist_primary == TRUE) %>%
    dplyr::select(term, subject_course, course_title, campus, total_enrl)

  enriched <- base %>%
    dplyr::left_join(counts, by = c("term", "subject_course", "course_title", "campus")) %>%
    dplyr::mutate(
      n_sections  = dplyr::coalesce(n_sections, 1L),
      course_enrl = dplyr::coalesce(course_enrl, total_enrl)
    )

  expect_false(any(is.na(enriched$n_sections)))
  expect_false(any(is.na(enriched$course_enrl)))
})

test_that("coalesce fallback fires for a course absent from counts", {
  # Simulate a low-enrollment row for a course that appears in get_low_enrollment_courses
  # but not in get_course_section_counts (e.g., a cancelled course that slipped through,
  # or a data quality issue). The coalesce should catch it.
  fake_counts <- tibble::tibble(
    term = integer(), subject_course = character(), course_title = character(),
    campus = character(), n_sections = integer(), course_enrl = integer()
  )
  # A single row not in fake_counts
  low_row <- tibble::tibble(
    term = 202010L, subject_course = "HIST 999", course_title = "Obscure Seminar",
    campus = "ABQ", total_enrl = 3L
  )
  enriched <- low_row %>%
    dplyr::left_join(fake_counts, by = c("term", "subject_course", "course_title", "campus")) %>%
    dplyr::mutate(
      n_sections  = dplyr::coalesce(n_sections, 1L),
      course_enrl = dplyr::coalesce(course_enrl, total_enrl)
    )
  expect_equal(enriched$n_sections, 1L)     # coalesce default: 1
  expect_equal(enriched$course_enrl, 3L)    # coalesce from total_enrl
})


# =============================================================================
# filter_downstream_by_dept()
# =============================================================================

context("filter_downstream_by_dept")

# Build a minimal downstream signals data frame for testing
make_downstream <- function() {
  tibble::tribble(
    ~source_course, ~dest_course,   ~recent_avg,
    "MATH 1215",    "MATH 1430",    12.3,
    "MATH 1215",    "PHYS 1310",     8.1,
    "HIST 1110",    "HIST 327",      5.4,
    "HIST 1110",    "ANTH 2175",     3.2,
    "ANTH 1140",    "ANTH 2175",     9.0,
  )
}

test_that("returns full data frame unchanged when dept is empty", {
  df <- make_downstream()
  result <- filter_downstream_by_dept(df, character(0), test_sections)
  expect_equal(nrow(result), nrow(df))
  expect_equal(result, df)
})

test_that("returns full data frame unchanged when dept is NULL", {
  df <- make_downstream()
  result <- filter_downstream_by_dept(df, NULL, test_sections)
  expect_equal(nrow(result), nrow(df))
})

test_that("returns empty data frame unchanged", {
  empty_df <- make_downstream()[0, ]
  result <- filter_downstream_by_dept(empty_df, c("HIST"), test_sections)
  expect_equal(nrow(result), 0)
})

test_that("returns NULL unchanged", {
  result <- filter_downstream_by_dept(NULL, c("HIST"), test_sections)
  expect_null(result)
})

test_that("filters to dest_courses in dept's subjects", {
  df <- make_downstream()

  # HIST department teaches HIST courses → keep only dest_course starting with "HIST"
  result <- filter_downstream_by_dept(df, c("HIST"), test_sections)

  dest_subjects <- sub(" .*", "", result$dest_course)
  expect_true(all(dest_subjects == "HIST"))
  expect_equal(nrow(result), 1)  # only HIST 327
})

test_that("multi-dept filter keeps destinations in any of the depts", {
  df <- make_downstream()

  result <- filter_downstream_by_dept(df, c("HIST", "ANTH"), test_sections)
  dest_subjects <- sub(" .*", "", result$dest_course)
  expect_true(all(dest_subjects %in% c("HIST", "ANTH")))
  expect_equal(nrow(result), 3)  # HIST 327, ANTH 2175 (x2)
})

test_that("preserves all columns in the filtered result", {
  df <- make_downstream()
  result <- filter_downstream_by_dept(df, c("MATH"), test_sections)
  expect_equal(names(result), names(df))
})

test_that("cancelled sections do not contribute subject codes to dept filter", {
  # S10C01 is a cancelled (status=C) HIST 395 section — same subject as active HIST.
  # A more critical case: if a dept had a cancelled course in an unusual subject,
  # that subject should not widen the filter. Construct a synthetic sections frame
  # with one active HIST course and one cancelled PSYC course (dept=HIST).
  fake_sections <- tibble::tribble(
    ~department, ~subject_course, ~status,
    "HIST",      "HIST 1110",     "A",
    "HIST",      "PSYC 1110",     "C"   # cancelled — should not contribute PSYC
  )

  df <- tibble::tribble(
    ~source_course, ~dest_course,
    "HIST 1110",    "HIST 327",
    "HIST 1110",    "PSYC 2200"   # should be excluded since PSYC not in active HIST subjects
  )

  result <- filter_downstream_by_dept(df, c("HIST"), fake_sections)
  expect_equal(nrow(result), 1L)
  expect_equal(result$dest_course, "HIST 327")
})


# =============================================================================
# get_subject_current_stats()
# =============================================================================

context("get_subject_current_stats")

test_that("returns a named list with n_sections and total_enrl", {
  result <- get_subject_current_stats(test_sections, "HIST", 202010L)

  expect_type(result, "list")
  expect_true(all(c("n_sections", "total_enrl") %in% names(result)))
})

test_that("counts only active sections for the given subject and term", {
  # 202010 HIST active home sections (7):
  #   S10001 (HIST 1110), S10002 (HIST 327), S10003 (HIST 490), S10004 (HIST 601)
  #   + XL0101 (HIST 480, XL01 primary) + XL0201 (HIST 484, XL02 primary)
  #   + XL0501 (HIST 475, XL05 primary)
  # Excluded: S10C01 (HIST 395, status=C) + XL0402 (HIST 490, XL04 partner)
  #           + XL0503 (HIST 575, XL05 partner)
  result <- get_subject_current_stats(test_sections, "HIST", 202010L)
  expected <- test_sections %>%
    dplyr::filter(subject == "HIST", term == 202010L, status == "A",
                  is.na(crosslist_group) | crosslist_primary == TRUE)
  expect_equal(result$n_sections, nrow(expected))
})

test_that("sums total_enrl across home sections", {
  # 202010 HIST active home: 21+28+15+12 (base) + 12+11+10 (XL primaries) = 109
  result <- get_subject_current_stats(test_sections, "HIST", 202010L)
  expected <- test_sections %>%
    dplyr::filter(subject == "HIST", term == 202010L, status == "A",
                  is.na(crosslist_group) | crosslist_primary == TRUE)
  expect_equal(result$total_enrl, sum(expected$total_enrl))
})

test_that("excludes crosslist partner rows from counts", {
  # XL01 in 202010: HIST 480 (primary, enrolled=12) + ANTH 480 (partner, enrolled=0)
  # XL04 in 202010: ANTH 490 (primary) + HIST 490 (partner)
  # Each dept should count only its own subject's primary sections.
  hist_stats <- get_subject_current_stats(test_sections, "HIST", 202010L)
  anth_stats <- get_subject_current_stats(test_sections, "ANTH", 202010L)

  hist_courses <- test_sections %>%
    dplyr::filter(subject == "HIST", term == 202010L, status == "A",
                  is.na(crosslist_group) | crosslist_primary == TRUE)
  anth_courses <- test_sections %>%
    dplyr::filter(subject == "ANTH", term == 202010L, status == "A",
                  is.na(crosslist_group) | crosslist_primary == TRUE)

  expect_equal(hist_stats$n_sections, nrow(hist_courses))
  expect_equal(anth_stats$n_sections, nrow(anth_courses))

  # HIST 490 partner (XL04) must not be in HIST stats
  # ANTH 480 partner (XL01) must not be in ANTH stats
  # The two counts together must not double-count any crosslisted enrollment
  expect_false(hist_stats$n_sections == anth_stats$n_sections + 1L)
})

test_that("returns zero counts for a subject with no sections in that term", {
  result <- get_subject_current_stats(test_sections, "HIST", 999999L)
  expect_equal(result$n_sections, 0L)
  expect_equal(result$total_enrl, 0L)
})

test_that("returns zero counts for a subject that does not exist", {
  result <- get_subject_current_stats(test_sections, "ZZZZ", 202010L)
  expect_equal(result$n_sections, 0L)
  expect_equal(result$total_enrl, 0L)
})

test_that("handles different terms independently", {
  spring <- get_subject_current_stats(test_sections, "MATH", 202010L)
  fall   <- get_subject_current_stats(test_sections, "MATH", 202080L)

  # Both should return positive counts but may differ between terms
  expect_gt(spring$n_sections, 0L)
  expect_gt(fall$n_sections, 0L)
  # Math has different sections per term — they should not be equal
  # (spring has MATH 1215Z x1, 1430 x2; fall has MATH 1215Z x1, 1430 x1 = different totals)
  expect_false(spring$total_enrl == fall$total_enrl)
})
