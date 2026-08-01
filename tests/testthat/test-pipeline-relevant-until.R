# Pipeline integration test: relevant_until enrollment window restriction
# Tests that apply_pathways_population_window() correctly limits
# enrollment records to a per-student term ceiling, and that get_course_timing()
# produces expected values when operating on enrollment-window-restricted data.
#
# Fixture:
#   STU_ONGOING  — relevant_until = NA (ongoing, no window ceiling)
#   STU_BOUNDED  — relevant_until = 202480 (switched out after Fall 2024)
#
#   Both students' course records:
#     202410: CHEM 1215
#     202480: BIOL 2310
#     202510: ENGL 1110   ← STU_BOUNDED's record at 202510 is cut by window
#
# Without relevant_until filtering:
#   ENGL 1110 has 2 students (both took it at 202510)
#
# After relevant_until filtering (STU_BOUNDED capped at 202480):
#   STU_BOUNDED's 202510 row is removed
#   ENGL 1110 has 1 student (only STU_ONGOING)
#   BIOL 2310 still has 2 students (202480 ≤ 202480 for STU_BOUNDED)
#   CHEM 1215 still has 2 students (202410 ≤ 202480)
#
# Derived relative terms after filtering:
#   STU_ONGOING: 202410→RT1, 202480→RT2, 202510→RT3 (3 terms)
#   STU_BOUNDED: 202410→RT1, 202480→RT2             (2 terms — 202510 cut)
#   n_eligible: RT1=2, RT2=2, RT3=1 (only STU_ONGOING reaches RT3)
#
# Expected get_course_timing() output after filtering (min_n=1):
#   ENGL 1110 at RT3: n_students=1, n_eligible=1, pct=1.0
#   BIOL 2310 at RT2: n_students=2, n_eligible=2, pct=1.0
#   CHEM 1215 at RT1: n_students=2, n_eligible=2, pct=1.0

context("Pipeline: relevant_until enrollment window restriction")


# Fixtures here are deliberately local: the relevant_until window turns on exact
# term spacing that the shared fixture does not provide. See AGENTS.md.
make_pipeline_students <- function() {
  tibble(
    student_id = c(
      "STU_ONGOING", "STU_ONGOING", "STU_ONGOING",
      "STU_BOUNDED", "STU_BOUNDED", "STU_BOUNDED"
    ),
    term = c(
      202410L, 202480L, 202510L,
      202410L, 202480L, 202510L
    ),
    subject_course = c(
      "CHEM 1215", "BIOL 2310", "ENGL 1110",
      "CHEM 1215", "BIOL 2310", "ENGL 1110"
    ),
    course_title = c(
      "General Chemistry", "General Biology", "Composition",
      "General Chemistry", "General Biology", "Composition"
    ),
    student_classification   = rep("Freshman", 6),
    registration_status_code = rep("RE", 6),
    campus                   = rep("ABQ", 6)
  )
}

make_pipeline_population <- function() {
  tibble(
    student_id       = c("STU_ONGOING", "STU_BOUNDED"),
    population_label = "test",
    relevant_until   = c(NA_integer_, 202480L)
  )
}

# =============================================================================
# Filter logic unit tests
# =============================================================================

test_that("relevant_until filter removes STU_BOUNDED records after 202480", {
  pop      <- make_pipeline_population()
  students <- make_pipeline_students()
  filtered <- apply_pathways_population_window(students, pop)

  bounded_terms <- filtered$term[filtered$student_id == "STU_BOUNDED"]
  expect_false(202510L %in% bounded_terms)
  expect_true( 202410L %in% bounded_terms)
  expect_true( 202480L %in% bounded_terms)
})

test_that("relevant_until filter keeps all STU_ONGOING records (NA window)", {
  pop      <- make_pipeline_population()
  students <- make_pipeline_students()
  filtered <- apply_pathways_population_window(students, pop)

  ongoing_terms <- filtered$term[filtered$student_id == "STU_ONGOING"]
  expect_true(202410L %in% ongoing_terms)
  expect_true(202480L %in% ongoing_terms)
  expect_true(202510L %in% ongoing_terms)
})

test_that("relevant_until filter removes exactly one row (STU_BOUNDED at 202510)", {
  pop      <- make_pipeline_population()
  students <- make_pipeline_students()
  filtered <- apply_pathways_population_window(students, pop)

  expect_equal(nrow(filtered), nrow(students) - 1L)
})

test_that("relevant_until filter with all-NA population is a no-op", {
  pop_all_na <- make_pipeline_population() %>%
    dplyr::mutate(relevant_until = NA_integer_)
  students <- make_pipeline_students()
  filtered <- apply_pathways_population_window(students, pop_all_na)

  expect_equal(nrow(filtered), nrow(students))
})


# =============================================================================
# Pipeline tests: filter → get_course_timing()
# =============================================================================

test_that("pipeline: ENGL 1110 at RT3 has n_students=1 after relevant_until filter", {
  pop      <- make_pipeline_population()
  students <- make_pipeline_students()
  filtered <- apply_pathways_population_window(students, pop)

  result <- get_course_timing(
    filtered,
    pop %>% dplyr::select(student_id, population_label),
    opt = list(min_n = 1)
  )
  engl_rt3 <- result[result$subject_course == "ENGL 1110" & result$relative_term == 3, ]

  expect_equal(nrow(engl_rt3), 1)
  expect_equal(engl_rt3$n_students, 1)
  expect_equal(engl_rt3$n_eligible, 1)
  expect_equal(engl_rt3$pct_pop,    1.0)
})

test_that("pipeline: without filter ENGL 1110 at RT3 would have n_students=2", {
  pop      <- make_pipeline_population()
  students <- make_pipeline_students()

  # Unfiltered — both students reach RT3
  result <- get_course_timing(
    students,
    pop %>% dplyr::select(student_id, population_label),
    opt = list(min_n = 1)
  )
  engl_rt3 <- result[result$subject_course == "ENGL 1110" & result$relative_term == 3, ]

  expect_equal(nrow(engl_rt3), 1)
  expect_equal(engl_rt3$n_students, 2)
  expect_equal(engl_rt3$n_eligible, 2)
})

test_that("pipeline: BIOL 2310 at RT2 still has n_students=2 after filter (202480 within window)", {
  pop      <- make_pipeline_population()
  students <- make_pipeline_students()
  filtered <- apply_pathways_population_window(students, pop)

  result <- get_course_timing(
    filtered,
    pop %>% dplyr::select(student_id, population_label),
    opt = list(min_n = 1)
  )
  biol_rt2 <- result[result$subject_course == "BIOL 2310" & result$relative_term == 2, ]

  expect_equal(nrow(biol_rt2), 1)
  expect_equal(biol_rt2$n_students, 2)
  expect_equal(biol_rt2$n_eligible, 2)
})

test_that("pipeline: CHEM 1215 at RT1 still has n_students=2 after filter (202410 within window)", {
  pop      <- make_pipeline_population()
  students <- make_pipeline_students()
  filtered <- apply_pathways_population_window(students, pop)

  result <- get_course_timing(
    filtered,
    pop %>% dplyr::select(student_id, population_label),
    opt = list(min_n = 1)
  )
  chem_rt1 <- result[result$subject_course == "CHEM 1215" & result$relative_term == 1, ]

  expect_equal(nrow(chem_rt1), 1)
  expect_equal(chem_rt1$n_students, 2)
  expect_equal(chem_rt1$n_eligible, 2)
})

test_that("pipeline: n_eligible at RT3 drops from 2 to 1 after relevant_until filter", {
  pop      <- make_pipeline_population()
  students <- make_pipeline_students()
  filtered <- apply_pathways_population_window(students, pop)

  result_filtered   <- get_course_timing(
    filtered,
    pop %>% dplyr::select(student_id, population_label),
    opt = list(min_n = 1)
  )
  result_unfiltered <- get_course_timing(
    students,
    pop %>% dplyr::select(student_id, population_label),
    opt = list(min_n = 1)
  )

  rt3_filtered   <- result_filtered[result_filtered$relative_term   == 3, ]
  rt3_unfiltered <- result_unfiltered[result_unfiltered$relative_term == 3, ]

  # Before filter: 2 students reach RT3
  expect_equal(max(rt3_unfiltered$n_eligible), 2)
  # After filter:  only STU_ONGOING reaches RT3
  expect_equal(max(rt3_filtered$n_eligible),   1)
})
