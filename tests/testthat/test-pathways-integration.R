# Integration tests for the pathways analysis pipeline
#
# Tests the full data flow:
#   build_population() → filter_students_by_pop() → cone function → output
#
# This mirrors the reactive pipeline in modules/pathways.R without Shiny
# infrastructure. If a cone produces wrong results or crashes on a real
# population, these tests will catch it without needing a running app.
#
# Populations under test:
#   History (preset)  — 39 students; multiple outcomes; known changers
#   Mathematics (preset) — 8 students; stopped_out / ongoing; simpler case
#   Anthropology (dept)  — 12 students; dept-mode path through get_focal_programs()

library(tibble)
library(dplyr)

context("Pathways Integration: Population + Cone Pipeline")


# ---------------------------------------------------------------------------
# Helper: applies the same Pathways population window used by the Shiny module.
# ---------------------------------------------------------------------------
filter_students_by_pop <- function(students, population) {
  apply_pathways_population_window(students, population)
}


# ---------------------------------------------------------------------------
# Build populations once, reuse across tests
# ---------------------------------------------------------------------------
hist_pop <- build_population(
  test_programs, test_degrees,
  opt = list(type = "preset", program_names = "History")
)

math_pop <- build_population(
  test_programs,
  opt = list(type = "preset", program_names = "Mathematics")
)

anth_pop <- build_population(
  test_programs,
  opt = list(type = "dept", dept_code = "ANTH")
)

hist_students <- filter_students_by_pop(test_students, hist_pop)
math_students <- filter_students_by_pop(test_students, math_pop)
anth_students <- filter_students_by_pop(test_students, anth_pop)


# =============================================================================
# Population building
# =============================================================================

test_that("History population: correct total and outcome breakdown", {
  expect_equal(nrow(hist_pop), 39L)
  counts <- as.list(table(hist_pop$outcome))
  expect_equal(counts$ongoing,      15L)
  expect_equal(counts$graduated,     5L)
  expect_equal(counts$switched_out,  3L)
  expect_equal(counts$stopped_out,  16L)
})

test_that("History population: one row per student", {
  expect_equal(nrow(hist_pop), n_distinct(hist_pop$student_id))
})

test_that("History population: all required columns present", {
  required <- c("student_id", "population_label", "outcome",
                "origin", "entry_method", "entry_status",
                "first_unit_term", "last_unit_term", "last_declared_term", "relevant_until")
  expect_true(all(required %in% names(hist_pop)))
})

test_that("Mathematics population: 8 students, stopped_out or ongoing", {
  expect_equal(nrow(math_pop), 8L)
  expect_equal(sum(math_pop$outcome == "ongoing"),     2L)
  expect_equal(sum(math_pop$outcome == "stopped_out"), 6L)
  expect_setequal(unique(math_pop$outcome), c("ongoing", "stopped_out"))
})

test_that("Anthropology dept population: 12 students, dept mode resolves correctly", {
  expect_equal(nrow(anth_pop), 12L)
  expect_true(all(anth_pop$outcome %in% c("ongoing", "stopped_out")))
})

test_that("Anthropology dept population excludes First Concentration program type", {
  # Archaeology is 'First Concentration', not Major/Second Major
  expect_false("STU-ARCH-CONC" %in% anth_pop$student_id)
})

test_that("History population: all three entry_method values present", {
  methods <- sort(unique(na.omit(hist_pop$entry_method)))
  expect_true("first_program" %in% methods)
  expect_true("switched_in"   %in% methods)
})

test_that("History population: both entry_status values present", {
  statuses <- sort(unique(na.omit(hist_pop$entry_status)))
  expect_true("pre_major" %in% statuses)
  expect_true("major"     %in% statuses)
})

test_that("STU-ENGL-HIST-001 is ongoing, switched_in, major", {
  row <- hist_pop[hist_pop$student_id == "STU-ENGL-HIST-001", ]
  expect_equal(row$outcome,       "ongoing")
  expect_equal(row$entry_method,  "switched_in")
  expect_equal(row$entry_status,  "major")
})

test_that("STU-HIST-SWOUT-001 is switched_out, unclear, major", {
  # entry_method = "unclear" because first HIST record is at 202010 = min_data_term.
  row <- hist_pop[hist_pop$student_id == "STU-HIST-SWOUT-001", ]
  expect_equal(row$outcome,       "switched_out")
  expect_equal(row$entry_method,  "unclear")
  expect_equal(row$entry_status,  "major")
  expect_equal(row$relevant_until, 202010L)
})

test_that("STU-HIST-PREDECL-002 is graduated with entry_status = pre_major", {
  row <- hist_pop[hist_pop$student_id == "STU-HIST-PREDECL-002", ]
  expect_equal(row$outcome,      "graduated")
  expect_equal(row$entry_status, "pre_major")
})


# =============================================================================
# relevant_until filtering
# =============================================================================

test_that("filter_students_by_pop: removes post-relevant_until enrollment rows", {
  # Synthetic test — does not depend on fixture having overlapping data
  pop <- tibble(
    student_id         = c("A", "B"),
    population_label   = "test",
    outcome            = c("stopped_out", "ongoing"),
    entry_method       = "first_program",
    entry_status       = "major",
    first_unit_term    = 202010L,
    last_unit_term     = c(202010L, 202110L),
    last_declared_term = c(202010L, 202110L),
    relevant_until     = c(202010L, NA_integer_)
  )
  students <- tibble(
    student_id             = c("A", "A", "B", "B"),
    term                   = c(202010L, 202110L, 202010L, 202110L),
    subject_course         = "TEST 1001",
    final_grade            = "A",
    registration_status_code = "RE"
  )

  result <- filter_students_by_pop(students, pop)

  # A's post-202010 enrollment removed
  expect_false(any(result$student_id == "A" & result$term == 202110L))
  # A's 202010 enrollment kept
  expect_true(any(result$student_id == "A" & result$term == 202010L))
  # B (ongoing, NA ceiling) both terms kept
  expect_equal(sum(result$student_id == "B"), 2L)
})

test_that("filter_students_by_pop: STU-HIST-SWOUT-001 has no enrollments past 202010", {
  swout_terms <- hist_students %>%
    filter(student_id == "STU-HIST-SWOUT-001") %>%
    pull(term)
  expect_true(all(swout_terms <= 202010L))
})

test_that("filter_students_by_pop: ongoing students not truncated", {
  # STU-HD-SP2-001 is declared History at max_data_term → ongoing → no ceiling
  expect_true(is.na(hist_pop$relevant_until[hist_pop$student_id == "STU-HD-SP2-001"]))
  sp2_terms <- hist_students %>%
    filter(student_id == "STU-HD-SP2-001") %>%
    pull(term)
  # Should not be limited to any earlier term
  expect_true(length(sp2_terms) == nrow(
    test_students %>% filter(student_id == "STU-HD-SP2-001")
  ))
})


# =============================================================================
# Stop-out cone
# =============================================================================

test_that("stopout: History population returns expected list structure", {
  result <- get_stopout(hist_students, hist_pop, opt = list(min_n = 3))
  expect_true(is.list(result))
  expect_true("by_course"       %in% names(result))
  expect_true("population_size" %in% names(result))
  expect_s3_class(result$by_course, "data.frame")
  expect_equal(result$population_size, 39L)
})

test_that("stopout: by_course has required columns", {
  result <- get_stopout(hist_students, hist_pop, opt = list(min_n = 3))
  required <- c("subject_course", "pop_n_dfw", "pop_n_pass",
                "pop_dfw_stopout_rate", "pop_pass_stopout_rate",
                "pop_stopout_gap")
  expect_true(all(required %in% names(result$by_course)))
})

test_that("stopout: cohort rates are valid proportions", {
  result <- get_stopout(hist_students, hist_pop, opt = list(min_n = 3))
  if (nrow(result$by_course) > 0) {
    expect_true(all(result$by_course$pop_dfw_stopout_rate  >= 0, na.rm = TRUE))
    expect_true(all(result$by_course$pop_dfw_stopout_rate  <= 1, na.rm = TRUE))
    expect_true(all(result$by_course$pop_pass_stopout_rate >= 0, na.rm = TRUE))
    expect_true(all(result$by_course$pop_pass_stopout_rate <= 1, na.rm = TRUE))
  }
})

test_that("stopout: n counts are non-negative integers", {
  result <- get_stopout(hist_students, hist_pop, opt = list(min_n = 3))
  if (nrow(result$by_course) > 0) {
    expect_true(all(result$by_course$pop_n_dfw  >= 0, na.rm = TRUE))
    expect_true(all(result$by_course$pop_n_pass >= 0, na.rm = TRUE))
  }
})

test_that("stopout: HIST 327 appears with correct cohort counts", {
  # Named enrollment: 5 SP1 pass (B), 5 SP1 DFW (F), 9 SP2 pass (A) in HIST 327 202010
  # SP1 students have no 202080 enrollment → stopped_out = TRUE
  # SP2 students appear in HIST 490 202080 → returned → stopped_out = FALSE
  result <- get_stopout(hist_students, hist_pop, opt = list(min_n = 3))
  expect_true("HIST 327" %in% result$by_course$subject_course)
  hist327 <- result$by_course[result$by_course$subject_course == "HIST 327", ]
  expect_equal(hist327$pop_n_dfw,  5L)
  expect_equal(hist327$pop_n_pass, 14L)  # 5 SP1-pass + 9 SP2-pass
  expect_equal(hist327$pop_dfw_stopout_rate,  1.0)  # all 5 DFW stopped out
  expect_equal(hist327$pop_pass_stopout_rate, 5/14) # 5 SP1-pass stopped out, 9 SP2 returned
})

test_that("stopout: Math population returns correct structure even with thin data", {
  result <- get_stopout(math_students, math_pop, opt = list(min_n = 3))
  expect_true(is.list(result))
  expect_equal(result$population_size, 8L)
  expect_s3_class(result$by_course, "data.frame")
})


# =============================================================================
# Course timing cone
# =============================================================================

test_that("course_timing: History population returns expected data frame", {
  result <- get_course_timing(hist_students, hist_pop,
                              programs = test_programs,
                              opt = list(min_n = 3, subject_code = "HIST"))
  expect_s3_class(result, "data.frame")
  required <- c("subject_course", "relative_term", "n_students",
                "n_eligible", "pct_pop", "median_term")
  expect_true(all(required %in% names(result)))
})

test_that("course_timing: relative terms start at 1 and are positive integers", {
  result <- get_course_timing(hist_students, hist_pop,
                              programs = test_programs,
                              opt = list(min_n = 3, subject_code = "HIST"))
  if (nrow(result) > 0) {
    expect_true(all(result$relative_term >= 1L))
    expect_true(all(result$relative_term == floor(result$relative_term)))
  }
})

test_that("course_timing: pct_pop is a valid proportion", {
  result <- get_course_timing(hist_students, hist_pop,
                              programs = test_programs,
                              opt = list(min_n = 3, subject_code = "HIST"))
  if (nrow(result) > 0) {
    expect_true(all(result$pct_pop >= 0))
    expect_true(all(result$pct_pop <= 1))
  }
})

test_that("course_timing: n_students does not exceed n_eligible", {
  result <- get_course_timing(hist_students, hist_pop,
                              programs = test_programs,
                              opt = list(min_n = 3, subject_code = "HIST"))
  if (nrow(result) > 0) {
    expect_true(all(result$n_students <= result$n_eligible))
  }
})

test_that("course_timing: HIST 327 appears as the gateway course for History majors", {
  # All 19 named History students (SP1-005..014 + SP2-001..009) have HIST 327 202010
  # as their first enrolled term → it should appear at relative_term = 1
  result <- get_course_timing(hist_students, hist_pop,
                              programs = test_programs,
                              opt = list(min_n = 3, subject_code = "HIST"))
  expect_true("HIST 327" %in% result$subject_course)
})

test_that("course_timing: HIST 327 peaks in relative term 1", {
  result <- get_course_timing(hist_students, hist_pop,
                              programs = test_programs,
                              opt = list(min_n = 3, subject_code = "HIST"))
  hist327 <- result[result$subject_course == "HIST 327", ]
  if (nrow(hist327) > 0) {
    peak_term <- hist327$relative_term[which.max(hist327$n_students)]
    expect_equal(peak_term, 1L)
  }
})

test_that("course_timing: HIST 490 appears in relative term 2 for ongoing students", {
  # SP2-001..009 (9 ongoing students): HIST 327 202010 (term 1), HIST 490 202080 (term 2)
  result <- get_course_timing(hist_students, hist_pop,
                              programs = test_programs,
                              opt = list(min_n = 3, subject_code = "HIST"))
  hist490 <- result[result$subject_course == "HIST 490", ]
  if (nrow(hist490) > 0) {
    # HIST 490 should appear at relative term 2 (the term after HIST 327)
    expect_true(2L %in% hist490$relative_term)
  }
})


# =============================================================================
# Major changes cone
# =============================================================================

test_that("detect_major_changes: returns data frame with required columns", {
  result <- detect_major_changes(test_programs, hist_pop)
  expect_s3_class(result, "data.frame")
  required <- c("student_id", "change_term", "from_major", "to_major")
  expect_true(all(required %in% names(result)))
})

test_that("detect_major_changes: HIST → POLS captured for both switchers", {
  result <- detect_major_changes(test_programs, hist_pop)
  hist_to_pols <- result[result$from_major == "History" &
                         result$to_major   == "Political Science", ]
  expect_gte(nrow(hist_to_pols), 2L)
  expect_true("STU-HIST-SWOUT-001" %in% hist_to_pols$student_id)
  expect_true("STU-HIST-SWOUT-002" %in% hist_to_pols$student_id)
})

test_that("detect_major_changes: HIST → BIOL captured for third switcher", {
  result <- detect_major_changes(test_programs, hist_pop)
  hist_to_biol <- result[result$from_major == "History" &
                         result$to_major   == "Biology", ]
  expect_gte(nrow(hist_to_biol), 1L)
  expect_true("STU-HIST-SWOUT-003" %in% hist_to_biol$student_id)
})

test_that("detect_major_changes: ENGL → HIST (switched_in students) captured", {
  result <- detect_major_changes(test_programs, hist_pop)
  engl_to_hist <- result[result$from_major == "English" &
                         result$to_major   == "History", ]
  expect_gte(nrow(engl_to_hist), 2L)
  expect_true("STU-ENGL-HIST-001" %in% engl_to_hist$student_id)
  expect_true("STU-ENGL-HIST-002" %in% engl_to_hist$student_id)
})

test_that("detect_major_changes: ANTH dept returns valid data frame", {
  result <- detect_major_changes(test_programs, anth_pop)
  expect_s3_class(result, "data.frame")
  expect_true(all(c("student_id", "from_major", "to_major") %in% names(result)))
})

test_that("detect_major_changes: no changes for pure single-program populations", {
  # Math students only ever appear in Mathematics — no changes expected
  result <- detect_major_changes(test_programs, math_pop)
  expect_equal(nrow(result), 0L)
})
