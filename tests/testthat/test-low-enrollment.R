# Tests for low-enrollment analysis dimensions
# Tests filter_DESRs() filtering behavior relevant to low-enrollment analysis
# (section status, enrollment thresholds, crosslist primary identification)
#
# Uses designed_test_data.R fixtures (hand-crafted, transparent).
#
# Reference values (from designed_test_data.R, 85 total rows: 71 base + 14 XL merged in):
#   status=A sections: 75  (61 base active + 14 XL all active)
#   zero total_enrl active sections: 2  (XL04: ANTH 490 + HIST 490, both 0 enrolled)
#   low-enrollment (1–10) active:    7
#   crosslist_primary=TRUE active:   67  (61 base active + 6 XL primaries)
#   Real campus codes: ABQ, EA, GA
#   Real delivery methods: ENH, MOPS, ONL, NA

context("Low Enrollment Analysis")


# =============================================================================
# Status filtering — active vs. cancelled
# =============================================================================

test_that("filtering to status=A excludes cancelled sections", {
  active    <- test_sections %>% filter(status == "A")
  cancelled <- test_sections %>% filter(status != "A")

  expect_true(all(active$status    == "A"))
  expect_true(all(cancelled$status != "A"))
  # 75 base + 14 C-suffix + 3 EC-07 + 6 XL06-S + 1 XL06-EA (all status="A") = 99
  expect_equal(nrow(active), 99)
})

test_that("active sections include the zero-enrollment edge case", {
  active_zero <- test_sections %>% filter(status == "A", total_enrl == 0)

  # XL0401 is ANTH 490 — zero-enrollment (XL04: tiebreak alpha case)
  expect_true("XL0401" %in% active_zero$section_id)
  expect_equal(nrow(active_zero), 2)
})


# =============================================================================
# Enrollment threshold filtering
# =============================================================================

test_that("threshold filter [1, 10] returns 48 active sections", {
  low_enrl <- test_sections %>%
    filter(status == "A", total_enrl >= 1, total_enrl <= 10)

  expect_equal(nrow(low_enrl), 7)
  expect_true(all(low_enrl$total_enrl >= 1))
  expect_true(all(low_enrl$total_enrl <= 10))
})

test_that("threshold filter [0, 0] captures only zero-enrollment active sections", {
  zero_enrl <- test_sections %>%
    filter(status == "A", total_enrl == 0)

  expect_equal(nrow(zero_enrl), 2)
  expect_true(all(zero_enrl$total_enrl == 0))
})

test_that("threshold filter with very high max returns all active sections", {
  all_active <- test_sections %>%
    filter(status == "A", total_enrl >= 0, total_enrl <= 9999)

  # 75 base + 14 C-suffix + 3 EC-07 + 6 XL06-S + 1 XL06-EA = 99
  expect_equal(nrow(all_active), 99)
})

test_that("threshold filter that matches nothing returns zero rows", {
  no_match <- test_sections %>%
    filter(status == "A", total_enrl >= 10000)

  expect_equal(nrow(no_match), 0)
})

test_that("shared low-enrollment builder can include or exclude buffer rows", {
  sections <- tibble::tibble(
    department = "HIST",
    term = 202410L,
    status = "A",
    subject_course = c("HIST 1010", "HIST 2010", "HIST 390", "HIST 501"),
    course_title = c("Intro", "Methods", "Research", "Graduate Topics"),
    campus = "ABQ",
    level = c("lower", "upper", "upper", "grad"),
    is_split = c(FALSE, TRUE, FALSE, FALSE),
    enrolled = c(13L, 11L, 8L, 6L),
    total_enrl = c(13L, 11L, 8L, 6L),
    crosslist_group = NA_character_,
    crosslist_role = NA_character_
  )
  opt <- list(term = 202410L, course_campus = "ABQ", dept = "HIST", status = "A", uel = TRUE)
  thresholds <- c(lower = 12, upper = 12, split = 10, grad = 5)

  strict <- build_low_enrollment_alerts(
    sections, opt, thresholds = thresholds,
    include_buffer = FALSE, add_history = FALSE
  )
  buffered <- build_low_enrollment_alerts(
    sections, opt, thresholds = thresholds,
    include_buffer = TRUE, add_history = FALSE
  )

  expect_equal(strict$subject_course, "HIST 390")
  expect_true(all(strict$enrolled <= strict$.threshold))
  expect_setequal(buffered$subject_course, sections$subject_course)
  expect_true(any(buffered$severity == "buffer"))
})


# =============================================================================
# Crosslist primary identification
# =============================================================================

test_that("crosslist_primary=TRUE correctly identifies primary sections", {
  primary    <- test_sections %>% filter(crosslist_primary == TRUE,  !is.na(crosslist_group))
  non_primary <- test_sections %>% filter(crosslist_primary == FALSE, !is.na(crosslist_group))

  # Primary sections exist in fixture
  expect_gt(nrow(primary), 0)

  # Non-primary sections (crosslist partners) also exist
  expect_gt(nrow(non_primary), 0)
})

test_that("sections without crosslist_group have NA crosslist_code and are standalone", {
  standalone <- test_sections %>% filter(is.na(crosslist_group))

  expect_gt(nrow(standalone), 0)
  # Standalone sections have no crosslist partner
  expect_true(all(is.na(standalone$crosslist_code)))
})

test_that("filtering to crosslist_primary avoids double-counting crosslisted enrollment", {
  # crosslist_primary=TRUE marks the section whose enrollment represents the group total.
  # In real CEDAR data not every active group has exactly one primary (the primary may be
  # cancelled, or data-quality anomalies may produce two), but the column exists and has
  # both TRUE and FALSE values so it can be used as a de-dup key.
  xl_active <- test_sections %>% filter(!is.na(crosslist_group), status == "A")

  expect_true("crosslist_primary" %in% names(xl_active))
  expect_true(any(xl_active$crosslist_primary == TRUE))
  expect_true(any(xl_active$crosslist_primary == FALSE))
})


# =============================================================================
# Fixture values — campus and delivery method codes
# =============================================================================

test_that("campus codes in fixture are real CEDAR values", {
  real_campuses <- c("ABQ", "EA", "EW", "GA", "LA", "TA", "VA")
  expect_true(all(test_sections$campus %in% real_campuses))
})

test_that("delivery_method values in fixture are real CEDAR values", {
  real_methods <- c("ENH", "MOPS", "OL", "ONL", NA)
  expect_true(all(is.na(test_sections$delivery_method) |
                  test_sections$delivery_method %in% real_methods))
})


# =============================================================================
# Level preservation through filtering
# =============================================================================

test_that("level values are preserved correctly when filtering active low-enrollment sections", {
  low_enrl <- test_sections %>%
    filter(status == "A", total_enrl >= 1, total_enrl <= 10)

  levels_present <- unique(na.omit(low_enrl$level))
  # Fixture covers lower, upper, and grad sections (some sections have NA level)
  expect_true(length(levels_present) > 1)
  expect_true(all(levels_present %in% c("lower", "upper", "grad")))
})


# =============================================================================
# Course-history grouping — topics courses vs. regular courses
# =============================================================================
# get_course_enrollment_history() drives the Low Enrollment tab's history column.
# For a rotating-topics slot (Banner "T:" convention) it must scope history to the
# specific topic shown, not splice unrelated topics that share the course number.
# Regular courses keep course-number-only matching so a retitle does not fragment
# a continuous history. Fixture: cedar_sections_topics (HIST 395 topics, HIST 401
# regular) in fixtures/designed_test_data.R.

test_that("topics-course history is scoped to the shown topic, not the whole slot", {
  history <- get_course_enrollment_history(
    courses    = test_sections_topics,
    campus     = "ABQ",
    dept       = "HIST",
    subj_crse  = "HIST 395",
    crse_title = "T: Black Sports History",
    im         = NULL,
    n_terms    = 10
  )

  # Only the two Black Sports History terms — the Digital History term (202110) is out.
  expect_equal(sort(history$term), c(202010L, 202080L))
  expect_equal(history$enrolled[history$term == 202010L], 12L)
  expect_equal(history$enrolled[history$term == 202080L], 15L)
})

test_that("a one-off topic returns only its own term of history", {
  history <- get_course_enrollment_history(
    courses    = test_sections_topics,
    campus     = "ABQ",
    dept       = "HIST",
    subj_crse  = "HIST 395",
    crse_title = "T: Digital History",
    im         = NULL,
    n_terms    = 10
  )

  expect_equal(history$term, 202110L)
  expect_equal(history$enrolled, 8L)
})

test_that("regular-course history ignores course_title so a retitle does not fragment it", {
  history <- get_course_enrollment_history(
    courses    = test_sections_topics,
    campus     = "ABQ",
    dept       = "HIST",
    subj_crse  = "HIST 401",
    crse_title = "Introduction to Historical Methods",  # differs from the 202010 title
    im         = NULL,
    n_terms    = 10
  )

  # Both terms kept despite the retitle — matched on course number only.
  expect_equal(sort(history$term), c(202010L, 202080L))
  expect_equal(history$enrolled[history$term == 202010L], 20L)
  expect_equal(history$enrolled[history$term == 202080L], 18L)
})


# =============================================================================
# Shared history helpers — drop_shell_sections / summarize_term_enrl_series /
# format_term_history (the consolidated spine used by both history functions)
# =============================================================================

test_that("drop_shell_sections removes active-empty-unstaffed rows but keeps cancelled ones", {
  kept <- drop_shell_sections(test_sections_topics)

  # SHELL01: active, 0 enrolled, unstaffed → dropped.
  expect_false("SHELL01" %in% kept$section_id)
  # CANC01: cancelled (status C) → kept, so its "C" can still show in history.
  expect_true("CANC01" %in% kept$section_id)
  # Real offerings are untouched.
  expect_true(all(c("TOP001","TOP002","TOP003","REG001","REG002") %in% kept$section_id))
})

test_that("summarize_term_enrl_series builds the per-term active-enrollment series", {
  hist395 <- test_sections_topics %>% filter(subject_course == "HIST 395")

  # Single course (keys default): one topic, pre-filtered → group by term only.
  vikings <- hist395 %>%
    filter(course_title == "T: Black Sports History") %>%
    summarize_term_enrl_series(n_terms = 10)
  expect_equal(vikings$term, c(202010L, 202080L))          # oldest → newest
  expect_equal(vikings$term_enrl, c(12L, 15L))
  expect_true(all(vikings$has_active))

  # Course group (keyed): each course_title is its own series.
  grouped <- summarize_term_enrl_series(
    hist395,
    keys = c("subject_course", "course_title", "campus"),
    n_terms = 10
  )
  digital <- grouped %>% filter(course_title == "T: Digital History")
  expect_equal(digital$term, 202110L)
  expect_equal(digital$term_enrl, 8L)
})

test_that("format_term_history renders active terms and marks cancelled terms 'C'", {
  # Parallel vectors, oldest → newest; the middle term was cancelled.
  txt <- format_term_history(
    term       = c(202010L, 202080L, 202110L),
    enrl       = c(12L, 0L, 8L),
    has_active = c(TRUE, FALSE, TRUE)
  )
  # ASCII-only assertion (the "->" separator is a multibyte arrow; matching it as a
  # regex/literal is brittle under the test's C locale). Verify order and that the
  # cancelled middle term renders "C" instead of an enrollment count.
  expect_match(txt, "Sp20: 12.*Fa20: C.*Sp21: 8")

  # No has_active → every term treated as active.
  expect_equal(format_term_history(202010L, 12L), "Sp20: 12")

  # Empty series → sentinel string.
  expect_equal(format_term_history(integer(0), integer(0)), "No history")
})
