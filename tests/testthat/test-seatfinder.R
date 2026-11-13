# Tests for seatfinder functions
# Tests R/cones/seatfinder.R
#
# Uses test_sections_sf fixture (seatfinder-specific) from designed_test_data.R.
# test_sections_sf has 2024/2025 terms (202410, 202480, 202510, 202580).
# test_sections_sf (main fixture) only has 2020/2021 terms — not used here.
# See designed_test_data.R cedar_sections_sf block for expected values.
#
# IMPORTANT: No fallback column checking - tests enforce CEDAR data model
# Required input columns: available (not avail)
#
# Tests cover both the isolated comparison helpers and the main seatfinder()
# integration path through get_enrl() and get_course_outcome_rates().

context("Seatfinder")

# =============================================================================
# Helper to prepare term_courses structure from known_sections
# =============================================================================
# Seatfinder expects term_courses as a list with start/end dataframes
# containing the full Open Seats course identity. Course title and part of term
# are required so topic/seminar courses sharing one catalog number never create
# many-to-many comparisons.

# =============================================================================
# get_courses_diff() tests
# =============================================================================

test_that("get_courses_diff returns correct structure", {
  term_courses <- prepare_term_courses(test_sections_sf, 202410, 202510)
  result <- get_courses_diff(term_courses)

  expect_type(result, "list")
  expect_named(result, c("prev", "new"))
  expect_s3_class(result$prev, "data.frame")
  expect_s3_class(result$new, "data.frame")
})

test_that("get_courses_diff identifies discontinued courses correctly (Spring)", {
  # Compare Spring 2024 (202410) vs Spring 2025 (202510)
  term_courses <- prepare_term_courses(test_sections_sf, 202410, 202510)
  result <- get_courses_diff(term_courses)

  # Known: PHYS 1010 was in 202410 but not in 202510 (discontinued)
  expect_equal(nrow(result$prev), 1)
  expect_equal(result$prev$subject_course, "PHYS 1010")
})

test_that("get_courses_diff identifies new courses correctly (Spring)", {
  # Compare Spring 2024 (202410) vs Spring 2025 (202510)
  term_courses <- prepare_term_courses(test_sections_sf, 202410, 202510)
  result <- get_courses_diff(term_courses)

  # Known: MATH 1220 is new in 202510 (not in 202410)
  expect_equal(nrow(result$new), 1)
  expect_equal(result$new$subject_course, "MATH 1220")
})

test_that("get_courses_diff identifies discontinued courses correctly (Fall)", {
  # Compare Fall 2024 (202480) vs Fall 2025 (202580)
  term_courses <- prepare_term_courses(test_sections_sf, 202480, 202580)
  result <- get_courses_diff(term_courses)

  # Known: CHEM 1010 was in 202480 but not in 202580 (discontinued)
  expect_equal(nrow(result$prev), 1)
  expect_equal(result$prev$subject_course, "CHEM 1010")
})

test_that("get_courses_diff identifies new courses correctly (Fall)", {
  # Compare Fall 2024 (202480) vs Fall 2025 (202580)
  term_courses <- prepare_term_courses(test_sections_sf, 202480, 202580)
  result <- get_courses_diff(term_courses)

  # Known: MATH 4310 and ANTH 2050 are new in 202580
  # Note: MATH 4310 has status "C" (cancelled) so only ANTH 2050 should appear
  expect_equal(nrow(result$new), 1)
  expect_equal(result$new$subject_course, "ANTH 2050")
})

test_that("get_courses_diff handles identical course lists", {
  # When both terms have same courses, both prev and new should be empty
  same_courses <- test_sections_sf %>%
    filter(term == 202510, status == "A") %>%
    select(all_of(SEATFINDER_COURSE_KEYS)) %>%
    distinct()

  term_courses <- list(start = same_courses, end = same_courses)
  result <- get_courses_diff(term_courses)

  expect_equal(nrow(result$prev), 0)
  expect_equal(nrow(result$new), 0)
})

test_that("get_courses_diff handles empty start term", {
  # Edge case: no courses in start term
  term_courses <- prepare_term_courses(test_sections_sf, 999999, 202510)
  result <- get_courses_diff(term_courses)

  # All end term courses should be "new"
  expect_equal(nrow(result$prev), 0)
  expect_equal(nrow(result$new), 5)  # 5 active courses in 202510
})

test_that("get_courses_diff handles empty end term", {
  # Edge case: no courses in end term
  term_courses <- prepare_term_courses(test_sections_sf, 202510, 999999)
  result <- get_courses_diff(term_courses)

  # All start term courses should be "previously offered"
  expect_equal(nrow(result$prev), 5)  # 5 active courses in 202510
  expect_equal(nrow(result$new), 0)
})


# =============================================================================
# get_courses_common() tests
# =============================================================================

test_that("get_courses_common returns courses in both terms (Spring)", {
  term_courses <- prepare_term_courses(test_sections_sf, 202410, 202510)
  enrl_summary <- prepare_enrl_summary(test_sections_sf, c(202410, 202510))
  result <- get_courses_common(term_courses, enrl_summary)

  # Known common courses: HIST 1110, HIST 1120, MATH 1215, ANTH 1110 (4 courses)
  common_courses <- unique(result$subject_course)
  expect_equal(length(common_courses), 4)
  expect_setequal(common_courses, c("HIST 1110", "HIST 1120", "MATH 1215", "ANTH 1110"))

  # Should NOT include discontinued or new courses
  expect_false("PHYS 1010" %in% common_courses)  # only in 202410
  expect_false("MATH 1220" %in% common_courses)  # only in 202510
})

test_that("get_courses_common returns courses in both terms (Fall)", {
  term_courses <- prepare_term_courses(test_sections_sf, 202480, 202580)
  enrl_summary <- prepare_enrl_summary(test_sections_sf, c(202480, 202580))
  result <- get_courses_common(term_courses, enrl_summary)

  # Known common courses: HIST 3010, MATH 3140 (2 courses)
  common_courses <- unique(result$subject_course)
  expect_equal(length(common_courses), 2)
  expect_setequal(common_courses, c("HIST 3010", "MATH 3140"))
})

test_that("get_courses_common calculates enrollment difference (Spring)", {
  term_courses <- prepare_term_courses(test_sections_sf, 202410, 202510)
  enrl_summary <- prepare_enrl_summary(test_sections_sf, c(202410, 202510))
  result <- get_courses_common(term_courses, enrl_summary)

  # Should have enrl_diff_from_last_year column
  expect_true("enrl_diff_from_last_year" %in% colnames(result))

  # Known enrollment changes (from fixture comments):
  # HIST 1110: 25 (2025) vs 22 (2024) = +3
  hist_result <- result %>% filter(subject_course == "HIST 1110", term == 202510)
  expect_equal(hist_result$enrl_diff_from_last_year, 3)

  # MATH 1215: 35 (2025) vs 30 (2024) = +5
  math_result <- result %>% filter(subject_course == "MATH 1215", term == 202510)
  expect_equal(math_result$enrl_diff_from_last_year, 5)

  # ANTH 1110: 40 (2025) vs 38 (2024) = +2
  anth_result <- result %>% filter(subject_course == "ANTH 1110", term == 202510)
  expect_equal(anth_result$enrl_diff_from_last_year, 2)
})

test_that("get_courses_common calculates enrollment difference (Fall)", {
  term_courses <- prepare_term_courses(test_sections_sf, 202480, 202580)
  enrl_summary <- prepare_enrl_summary(test_sections_sf, c(202480, 202580))
  result <- get_courses_common(term_courses, enrl_summary)

  # Known enrollment changes Fall 2024 vs Fall 2025:
  # HIST 3010: 22 (2025) vs 20 (2024) = +2
  hist_result <- result %>% filter(subject_course == "HIST 3010", term == 202580)
  expect_equal(hist_result$enrl_diff_from_last_year, 2)

  # MATH 3140: 15 (2025) vs 12 (2024) = +3
  math_result <- result %>% filter(subject_course == "MATH 3140", term == 202580)
  expect_equal(math_result$enrl_diff_from_last_year, 3)
})

test_that("get_courses_common returns empty for no common courses", {
  # Use non-overlapping terms
  term_courses <- list(
    start = tibble(
      campus = "Main", college = "AS", part_term = "1",
      subject_course = "FAKE 1000", course_title = "Fake Course",
      gen_ed_area = NA_character_
    ),
    end = tibble(
      campus = "Main", college = "AS", part_term = "1",
      subject_course = "OTHER 2000", course_title = "Other Course",
      gen_ed_area = NA_character_
    )
  )
  enrl_summary <- tibble(
    campus = character(), college = character(), term = integer(),
    part_term = character(), subject_course = character(),
    course_title = character(), gen_ed_area = character(),
    enrolled = integer(), capacity = integer(), avail = integer()
  )

  result <- get_courses_common(term_courses, enrl_summary)
  expect_equal(nrow(result), 0)
})


# =============================================================================
# normalize_inst_method() tests
# =============================================================================

test_that("normalize_inst_method returns data with method column", {
  test_courses <- test_sections_sf %>%
    filter(term == 202510) %>%
    select(subject_course, delivery_method)

  result <- normalize_inst_method(test_courses)

  expect_true("method" %in% colnames(result))
  expect_equal(nrow(result), nrow(test_courses))
})

test_that("normalize_inst_method converts face-to-face variants to f2f", {
  test_courses <- tibble(
    subject_course = c("HIST 1110", "MATH 1215", "ANTH 1110", "HIST 2010"),
    delivery_method = c("0", "ENH", "HYB", "Online")
  )

  result <- normalize_inst_method(test_courses)

  # "0", "ENH", "HYB" should all become "f2f"
  expect_equal(result$method[1], "f2f")  # "0" -> "f2f"
  expect_equal(result$method[2], "f2f")  # "ENH" -> "f2f"
  expect_equal(result$method[3], "f2f")  # "HYB" -> "f2f"

  # Other values preserved as-is
  expect_equal(result$method[4], "Online")
})

test_that("normalize_inst_method preserves original delivery_method column", {
  test_courses <- tibble(
    subject_course = c("HIST 1110"),
    delivery_method = c("ENH")
  )

  result <- normalize_inst_method(test_courses)

  # Original column should still exist unchanged
  expect_equal(result$delivery_method, "ENH")
  # New column should have normalized value
  expect_equal(result$method, "f2f")
})

test_that("normalize_inst_method handles NA delivery methods", {
  test_courses <- tibble(
    subject_course = c("TEST 1000", "TEST 2000"),
    delivery_method = c(NA_character_, "In Person")
  )

  result <- normalize_inst_method(test_courses)

  # NA should stay NA
  expect_true(is.na(result$method[1]))
  # "In Person" should stay as-is (not converted to f2f)
  expect_equal(result$method[2], "In Person")
})

test_that("normalize_inst_method handles empty dataframe", {
  test_courses <- tibble(
    subject_course = character(),
    delivery_method = character()
  )

  result <- normalize_inst_method(test_courses)

  expect_equal(nrow(result), 0)
  expect_true("method" %in% colnames(result))
})


# =============================================================================
# Fixture data integrity tests
# =============================================================================

test_that("test_sections_sf has required columns for seatfinder", {
  required_cols <- c("campus", "college", "term", "subject_course", "gen_ed_area",
                     "enrolled", "capacity", "available", "status", "department")

  missing <- setdiff(required_cols, colnames(test_sections_sf))
  expect_equal(length(missing), 0,
               info = paste("Missing columns:", paste(missing, collapse = ", ")))
})

test_that("test_sections_sf has expected term pairs for year-over-year comparison", {
  terms <- unique(test_sections_sf$term)

  # Should have Spring 2024 and Spring 2025 for comparison

  expect_true(202410 %in% terms, info = "Missing Spring 2024 (202410)")
  expect_true(202510 %in% terms, info = "Missing Spring 2025 (202510)")

  # Should have Fall 2024 and Fall 2025 for comparison
  expect_true(202480 %in% terms, info = "Missing Fall 2024 (202480)")
  expect_true(202580 %in% terms, info = "Missing Fall 2025 (202580)")
})

test_that("test_sections_sf enrollment values are consistent", {
  # Verify available = capacity - enrolled for fixture integrity
  inconsistent <- test_sections_sf %>%
    filter(available != (capacity - enrolled))

  expect_equal(nrow(inconsistent), 0,
               info = "Fixture has inconsistent available/capacity/enrolled values")
})

test_that("empty_seatfinder_result returns every table slot empty", {
  result <- empty_seatfinder_result()

  expect_type(result, "list")
  expect_named(result, c(
    "type_summary", "courses_common", "courses_prev", "courses_new",
    "gen_ed_summary", "gen_ed_likely", "gen_ed_combined"
  ))
  expect_true(all(vapply(result, function(df) {
    is.data.frame(df) && nrow(df) == 0
  }, logical(1))))
})


# =============================================================================
# Main seatfinder() function integration tests
# =============================================================================

test_that("seatfinder returns expected list structure", {
  with_seatfinder_test_terms({
    expect_no_error(
      result <- seatfinder(
        seatfinder_grade_attempts,
        test_sections_sf,
        test_faculty,
        list(data_edges = seatfinder_test_edges, term = "202510", course_campus = "ABQ", level = "lower")
      )
    )

    expect_type(result, "list")
    expect_named(result, c(
      "type_summary", "courses_common", "courses_prev", "courses_new",
      "gen_ed_summary", "gen_ed_likely", "gen_ed_combined"
    ))
    expect_true(all(vapply(result, is.data.frame, logical(1))))
    expect_gt(nrow(result$type_summary), 0)
    expect_true("dfw_pct" %in% names(result$type_summary))
  })
})

test_that("seatfinder parses single term correctly", {
  with_seatfinder_test_terms({
    result <- seatfinder(
      seatfinder_grade_attempts,
      test_sections_sf,
      test_faculty,
      list(data_edges = seatfinder_test_edges, term = "202510", course_campus = "ABQ", level = "lower")
    )

    expect_equal(unique(result$type_summary$term), 202510L)
    expect_setequal(result$courses_new$subject_course, "MATH 1220")
    expect_setequal(result$courses_prev$subject_course, "PHYS 1010")
    expect_setequal(
      unique(result$courses_common$subject_course),
      c("HIST 1110", "HIST 1120", "MATH 1215", "ANTH 1110")
    )

    hist_common <- result$courses_common %>%
      filter(subject_course == "HIST 1110")
    expect_equal(hist_common$enrl_diff_from_last_year, 3)
  })
})

test_that("seatfinder keeps topic titles distinct without many-to-many repeats", {
  with_seatfinder_test_terms({
    sections <- seatfinder_topic_sections
    result <- seatfinder(
      keyed_attempts(seatfinder_students_for(sections), edges = seatfinder_test_edges),
      sections,
      test_faculty,
      list(data_edges = seatfinder_test_edges, term = "202510", course_campus = "ABQ", dept_code = "HNRS", level = "lower")
    )

    display <- result$type_summary %>%
      ungroup() %>%
      select(college, subject_course, course_title, part_term, avail,
             sections, avg_size, enrolled, dfw_pct, avail_diff)

    expect_equal(nrow(display), 2L)
    expect_equal(
      nrow(display %>% count(across(everything()), name = "rows") %>% filter(rows > 1)),
      0L
    )
    expect_setequal(display$course_title,
                    c("Sem: Legacy of Algebra", "Sem: Legacy of Comedy"))

    algebra <- display %>% filter(course_title == "Sem: Legacy of Algebra")
    comedy <- display %>% filter(course_title == "Sem: Legacy of Comedy")
    expect_equal(algebra$avail_diff, -1)
    expect_equal(comedy$avail_diff, -1)
  })
})

test_that("seatfinder parses comma-separated terms correctly", {
  with_seatfinder_test_terms({
    result <- seatfinder(
      seatfinder_grade_attempts,
      test_sections_sf,
      test_faculty,
      list(data_edges = seatfinder_test_edges, term = "202480,202580", course_campus = "ABQ")
    )

    expect_equal(unique(result$type_summary$term), 202580L)
    expect_setequal(result$courses_new$subject_course, "ANTH 2050")
    expect_false("MATH 4310" %in% result$courses_new$subject_course)
    expect_setequal(result$courses_prev$subject_course, "CHEM 1010")
    expect_setequal(
      unique(result$courses_common$subject_course),
      c("HIST 3010", "MATH 3140")
    )
  })
})

test_that("seatfinder filters gen ed courses correctly", {
  with_seatfinder_test_terms({
    sections <- seatfinder_gen_ed_sections
    result <- seatfinder(
      keyed_attempts(seatfinder_students_for(sections), edges = seatfinder_test_edges),
      sections,
      test_faculty,
      list(data_edges = seatfinder_test_edges, term = "202510", course_campus = "ABQ", level = "lower")
    )

    expect_gt(nrow(result$gen_ed_summary), 0)
    expect_true(all(!is.na(result$gen_ed_summary$gen_ed_area)))
    expect_true(all(result$gen_ed_summary$avail > 0))

    expect_setequal(result$gen_ed_likely$subject_course, "HIST 1999")
    expect_true(all(result$gen_ed_likely$avail == 0))
    expect_true(all(result$gen_ed_likely$enrolled == 0))

    expect_true("likely" %in% names(result$gen_ed_combined))
    expect_true(any(result$gen_ed_combined$likely))
    expect_true(any(!result$gen_ed_combined$likely))
  })
})

test_that("seatfinder merges DFW rates correctly", {
  with_seatfinder_test_terms({
    result <- seatfinder(
      seatfinder_grade_attempts,
      test_sections_sf,
      test_faculty,
      list(data_edges = seatfinder_test_edges, term = "202510", course_campus = "ABQ", level = "lower")
    )

    expect_true(is.numeric(result$type_summary$dfw_pct))
    expect_false(any(is.na(result$type_summary$dfw_pct)))
    expect_true(all(result$type_summary$dfw_pct >= 0))
    expect_true(all(result$type_summary$dfw_pct <= 100))
    expect_equal(unique(result$type_summary$dfw_pct), 60)
  })
})

test_that("seatfinder delegates unfinished-term exclusion to the graded edge", {
  with_seatfinder_test_terms({
    students <- seatfinder_grade_students
    current_failure <- students %>%
      filter(subject_course == "HIST 1110", campus == "ABQ") %>%
      slice(1) %>%
      mutate(
        enrollment_id = "SF-CURRENT-FAIL",
        student_id = "SF-CURRENT-FAIL",
        term = 202680L,
        registration_status_code = "RE",
        final_grade = "F"
      )

    result <- seatfinder(
      keyed_attempts(bind_rows(students, current_failure), edges = seatfinder_test_edges),
      test_sections_sf,
      test_faculty,
      list(data_edges = seatfinder_test_edges, term = "202510", course_campus = "ABQ", level = "lower")
    )

    expect_equal(unique(result$type_summary$dfw_pct), 60)
  })
})

test_that("seatfinder continues when no grade rows match", {
  with_seatfinder_test_terms({
    result <- seatfinder(
      keyed_attempts(seatfinder_grade_students[0, ], edges = seatfinder_test_edges),
      test_sections_sf,
      test_faculty,
      list(data_edges = seatfinder_test_edges, term = "202510", course_campus = "ABQ", level = "lower")
    )

    expect_gt(nrow(result$type_summary), 0)
    expect_true(all(is.na(result$type_summary$dfw_pct)))
  })
})

test_that("seatfinder returns empty result when filters match no enrollment rows", {
  with_seatfinder_test_terms({
    result <- seatfinder(
      seatfinder_grade_attempts,
      test_sections_sf,
      test_faculty,
      list(data_edges = seatfinder_test_edges, term = "202510", course_campus = "ABQ", dept_code = "SHS", level = "lower")
    )

    expect_true(all(vapply(result, function(df) {
      is.data.frame(df) && nrow(df) == 0
    }, logical(1))))
  })
})
