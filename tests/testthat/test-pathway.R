# Tests for curriculum pathway analysis functions
# Tests get_course_timing() and get_course_pairs() from R/cones/pathway.R
#
# Uses local fixtures (NOT designed_test_data.R) because pathway tests require
# a carefully controlled enrollment sequence with known relative terms.
#
# Fixture: 5 students, 3 non-summer terms (202410 Spring, 202480 Fall, 202510 Spring)
#
#   Student   Start    Terms                   Classification at first term
#   S001      202410   202410, 202480, 202510   Freshman
#   S002      202410   202410, 202480, 202510   Freshman
#   S003      202410   202410, 202480            Freshman (stops after 2 terms)
#   S004      202410   202410, 202480, 202510   Freshman
#   S005      202480   202480, 202510            Sophomore (late start)
#
#   Enrollments (all RE):
#     CHEM 1215 at 202410: S001, S002, S003, S004   (NOT S005)
#     BIOL 2310 at 202480: S001, S002, S003, S004, S005  (all 5)
#     ENGL 1110 at 202510: S001, S002, S004, S005   (NOT S003)
#
#   Derived relative terms (non-summer, so 202410/480/510 = RT1/RT2/RT3 per student):
#     CHEM 1215: S001-S004 at RT1
#     BIOL 2310: S001-S004 at RT2 | S005 at RT1
#     ENGL 1110: S001/S002/S004 at RT3 | S005 at RT2
#
#   n_eligible per RT (students whose max_relative_term >= RT):
#     S001=RT3, S002=RT3, S003=RT2, S004=RT3, S005=RT2
#     RT1: 5  |  RT2: 5  |  RT3: 3 (S001, S002, S004)
#
#   Expected values:
#     CHEM 1215 at RT1: n=4, n_eligible=5, pct=0.8
#     BIOL 2310 at RT1: n=1, n_eligible=5, pct=0.2   (S005 only)
#     BIOL 2310 at RT2: n=4, n_eligible=5, pct=0.8
#     ENGL 1110 at RT2: n=1, n_eligible=5, pct=0.2   (S005 only)
#     ENGL 1110 at RT3: n=3, n_eligible=3, pct=1.0
#
#   After start_classification="Freshman" (drops S005):
#     CHEM 1215 at RT1: n=4, n_eligible=4, pct=1.0
#     BIOL 2310 at RT1: 0 rows (S005 excluded)
#     BIOL 2310 at RT2: n=4, n_eligible=4, pct=1.0
#
#   get_course_pairs expected (min_n=1, min_pair_n=1):
#     CHEM 1215 → BIOL 2310: n_students=4, n_took_a=4, pct=1.0, median_gap=1
#     CHEM 1215 → ENGL 1110: n_students=3, n_took_a=4, pct=0.75, median_gap=2
#     BIOL 2310 → ENGL 1110: n_students=4, n_took_a=5, pct=0.8,  median_gap=1

context("Pathway Analysis")


make_pathway_students <- function() {
  tibble(
    student_id = c(
      "S001", "S001", "S001",
      "S002", "S002", "S002",
      "S003", "S003",
      "S004", "S004", "S004",
      "S005", "S005"
    ),
    term = c(
      202410L, 202480L, 202510L,
      202410L, 202480L, 202510L,
      202410L, 202480L,
      202410L, 202480L, 202510L,
      202480L, 202510L
    ),
    subject_course = c(
      "CHEM 1215", "BIOL 2310", "ENGL 1110",
      "CHEM 1215", "BIOL 2310", "ENGL 1110",
      "CHEM 1215", "BIOL 2310",
      "CHEM 1215", "BIOL 2310", "ENGL 1110",
      "BIOL 2310",  "ENGL 1110"
    ),
    course_title = c(
      "General Chemistry", "General Biology", "Composition",
      "General Chemistry", "General Biology", "Composition",
      "General Chemistry", "General Biology",
      "General Chemistry", "General Biology", "Composition",
      "General Biology",   "Composition"
    ),
    student_classification = c(
      "Freshman",  "Sophomore", "Junior",
      "Freshman",  "Sophomore", "Junior",
      "Freshman",  "Sophomore",
      "Freshman",  "Sophomore", "Junior",
      "Sophomore", "Junior"
    ),
    registration_status_code = rep("RE", 13)
  )
}

make_pathway_population <- function() {
  tibble(
    student_id       = c("S001", "S002", "S003", "S004", "S005"),
    population_label = "bio_majors"
  )
}


# =============================================================================
# get_course_timing() tests
# =============================================================================

test_that("get_course_timing returns correct structure", {
  result <- get_course_timing(
    make_pathway_students(),
    make_pathway_population(),
    opt = list(min_n = 1)
  )

  expect_s3_class(result, "data.frame")
  expect_true("subject_course" %in% names(result))
  expect_true("subject_code"   %in% names(result))
  expect_true("course_title"   %in% names(result))
  expect_true("relative_term"  %in% names(result))
  expect_true("n_students"     %in% names(result))
  expect_true("n_eligible"     %in% names(result))
  expect_true("pct_pop"        %in% names(result))
  expect_true("median_term"    %in% names(result))
})

test_that("get_course_timing CHEM 1215 at RT1: n_students=4, n_eligible=5, pct=0.8", {
  result <- get_course_timing(
    make_pathway_students(),
    make_pathway_population(),
    opt = list(min_n = 1)
  )
  row <- result[result$subject_course == "CHEM 1215" & result$relative_term == 1, ]

  expect_equal(nrow(row), 1)
  expect_equal(row$n_students, 4)
  expect_equal(row$n_eligible, 5)
  expect_equal(row$pct_pop,    0.8)
})

test_that("get_course_timing BIOL 2310 at RT2: n_students=4, n_eligible=5, pct=0.8", {
  result <- get_course_timing(
    make_pathway_students(),
    make_pathway_population(),
    opt = list(min_n = 1)
  )
  row <- result[result$subject_course == "BIOL 2310" & result$relative_term == 2, ]

  expect_equal(nrow(row), 1)
  expect_equal(row$n_students, 4)
  expect_equal(row$n_eligible, 5)
  expect_equal(row$pct_pop,    0.8)
})

test_that("get_course_timing BIOL 2310 at RT1 (S005 only): n_students=1, n_eligible=5, pct=0.2", {
  result <- get_course_timing(
    make_pathway_students(),
    make_pathway_population(),
    opt = list(min_n = 1)
  )
  row <- result[result$subject_course == "BIOL 2310" & result$relative_term == 1, ]

  expect_equal(nrow(row), 1)
  expect_equal(row$n_students, 1)
  expect_equal(row$n_eligible, 5)
  expect_equal(row$pct_pop,    0.2)
})

test_that("get_course_timing ENGL 1110 at RT3: n_students=3, n_eligible=3, pct=1.0", {
  result <- get_course_timing(
    make_pathway_students(),
    make_pathway_population(),
    opt = list(min_n = 1)
  )
  row <- result[result$subject_course == "ENGL 1110" & result$relative_term == 3, ]

  expect_equal(nrow(row), 1)
  expect_equal(row$n_students, 3)
  expect_equal(row$n_eligible, 3)
  expect_equal(row$pct_pop,    1.0)
})

test_that("get_course_timing ENGL 1110 at RT2 (S005 only): n_students=1, n_eligible=5, pct=0.2", {
  result <- get_course_timing(
    make_pathway_students(),
    make_pathway_population(),
    opt = list(min_n = 1)
  )
  row <- result[result$subject_course == "ENGL 1110" & result$relative_term == 2, ]

  expect_equal(nrow(row), 1)
  expect_equal(row$n_students, 1)
  expect_equal(row$n_eligible, 5)
  expect_equal(row$pct_pop,    0.2)
})

test_that("get_course_timing min_n drops courses below total-student threshold", {
  # CHEM 1215 total = 4; ENGL 1110 total = 4; BIOL 2310 total = 5
  # min_n=5 → CHEM and ENGL drop; BIOL survives
  result <- get_course_timing(
    make_pathway_students(),
    make_pathway_population(),
    opt = list(min_n = 5)
  )

  expect_false("CHEM 1215" %in% result$subject_course)
  expect_false("ENGL 1110" %in% result$subject_course)
  expect_true( "BIOL 2310" %in% result$subject_course)
})

test_that("get_course_timing start_classification=Freshman drops S005 (Sophomore)", {
  result <- get_course_timing(
    make_pathway_students(),
    make_pathway_population(),
    opt = list(min_n = 1, start_classification = "Freshman")
  )
  # S005 excluded:
  #   CHEM 1215 at RT1: 4 of 4 eligible → pct=1.0
  #   BIOL 2310 at RT1: no rows (S005 was the only RT1 taker)
  chem_row <- result[result$subject_course == "CHEM 1215" & result$relative_term == 1, ]
  biol_rt1 <- result[result$subject_course == "BIOL 2310" & result$relative_term == 1, ]

  expect_equal(nrow(chem_row), 1)
  expect_equal(chem_row$n_students, 4)
  expect_equal(chem_row$n_eligible, 4)
  expect_equal(chem_row$pct_pop,    1.0)
  expect_equal(nrow(biol_rt1), 0)
})

test_that("get_course_timing start_classification=Freshman BIOL 2310 RT2: n_eligible=4", {
  result <- get_course_timing(
    make_pathway_students(),
    make_pathway_population(),
    opt = list(min_n = 1, start_classification = "Freshman")
  )
  row <- result[result$subject_course == "BIOL 2310" & result$relative_term == 2, ]

  expect_equal(nrow(row), 1)
  expect_equal(row$n_students, 4)
  expect_equal(row$n_eligible, 4)
  expect_equal(row$pct_pop,    1.0)
})

test_that("get_course_timing subject_code filter restricts to BIOL courses only", {
  result <- get_course_timing(
    make_pathway_students(),
    make_pathway_population(),
    opt = list(min_n = 1, subject_code = "BIOL")
  )

  expect_true(all(result$subject_code == "BIOL"))
  expect_false("CHEM 1215" %in% result$subject_course)
  expect_false("ENGL 1110" %in% result$subject_course)
})

test_that("get_course_timing stops when population missing population_label column", {
  bad_pop <- tibble(student_id = c("S001", "S002"))
  expect_error(
    get_course_timing(make_pathway_students(), bad_pop, opt = list(min_n = 1)),
    "population_label"
  )
})

test_that("get_course_timing returns empty data frame for empty population", {
  empty_pop <- make_pathway_population()[0, ]
  result <- get_course_timing(make_pathway_students(), empty_pop, opt = list(min_n = 1))
  expect_equal(nrow(result), 0)
})


# =============================================================================
# get_course_pairs() tests
# =============================================================================
#
# Expected pairs (min_n=1, min_pair_n=1, max_term_gap=4 default):
#
#   CHEM 1215 → BIOL 2310:
#     S001: CHEM RT1, BIOL RT2 → gap=1
#     S002: CHEM RT1, BIOL RT2 → gap=1
#     S003: CHEM RT1, BIOL RT2 → gap=1
#     S004: CHEM RT1, BIOL RT2 → gap=1
#     n_students=4, n_took_a=4, pct=1.0, median_gap=1
#
#   CHEM 1215 → ENGL 1110:
#     S001: CHEM RT1, ENGL RT3 → gap=2
#     S002: CHEM RT1, ENGL RT3 → gap=2
#     S004: CHEM RT1, ENGL RT3 → gap=2
#     (S003 never takes ENGL 1110)
#     n_students=3, n_took_a=4, pct=0.75, median_gap=2
#
#   BIOL 2310 → ENGL 1110:
#     S001: BIOL RT2, ENGL RT3 → gap=1
#     S002: BIOL RT2, ENGL RT3 → gap=1
#     S004: BIOL RT2, ENGL RT3 → gap=1
#     S005: BIOL RT1, ENGL RT2 → gap=1
#     (S003 never takes ENGL 1110)
#     n_students=4, n_took_a=5, pct=0.8, median_gap=1

test_that("get_course_pairs returns correct structure", {
  result <- get_course_pairs(
    make_pathway_students(),
    make_pathway_population(),
    opt = list(min_n = 1, min_pair_n = 1)
  )

  expect_s3_class(result, "data.frame")
  expect_true("course_a"        %in% names(result))
  expect_true("course_b"        %in% names(result))
  expect_true("n_students"      %in% names(result))
  expect_true("n_took_a"        %in% names(result))
  expect_true("pct_a_to_b"      %in% names(result))
  expect_true("median_term_gap" %in% names(result))
})

test_that("get_course_pairs CHEM 1215 → BIOL 2310: all 4 takers proceed to BIOL", {
  result <- get_course_pairs(
    make_pathway_students(),
    make_pathway_population(),
    opt = list(min_n = 1, min_pair_n = 1)
  )
  pair <- result[result$course_a == "CHEM 1215" & result$course_b == "BIOL 2310", ]

  expect_equal(nrow(pair), 1)
  expect_equal(pair$n_students,      4)
  expect_equal(pair$n_took_a,        4)
  expect_equal(pair$pct_a_to_b,      1.0)
  expect_equal(pair$median_term_gap, 1)
})

test_that("get_course_pairs CHEM 1215 → ENGL 1110: 3 of 4 takers proceed (pct=0.75)", {
  result <- get_course_pairs(
    make_pathway_students(),
    make_pathway_population(),
    opt = list(min_n = 1, min_pair_n = 1)
  )
  pair <- result[result$course_a == "CHEM 1215" & result$course_b == "ENGL 1110", ]

  expect_equal(nrow(pair), 1)
  expect_equal(pair$n_students, 3)
  expect_equal(pair$n_took_a,   4)
  expect_equal(pair$pct_a_to_b, 0.75)
})

test_that("get_course_pairs BIOL 2310 → ENGL 1110: 4 of 5 takers proceed (pct=0.8)", {
  result <- get_course_pairs(
    make_pathway_students(),
    make_pathway_population(),
    opt = list(min_n = 1, min_pair_n = 1)
  )
  pair <- result[result$course_a == "BIOL 2310" & result$course_b == "ENGL 1110", ]

  expect_equal(nrow(pair), 1)
  expect_equal(pair$n_students, 4)
  expect_equal(pair$n_took_a,   5)
  expect_equal(pair$pct_a_to_b, 0.8)
})

test_that("get_course_pairs max_term_gap=1 excludes CHEM→ENGL (gap=2) but keeps CHEM→BIOL (gap=1)", {
  result <- get_course_pairs(
    make_pathway_students(),
    make_pathway_population(),
    opt = list(min_n = 1, min_pair_n = 1, max_term_gap = 1)
  )

  chem_engl <- result[result$course_a == "CHEM 1215" & result$course_b == "ENGL 1110", ]
  chem_biol  <- result[result$course_a == "CHEM 1215" & result$course_b == "BIOL 2310", ]

  expect_equal(nrow(chem_engl), 0)
  expect_equal(nrow(chem_biol), 1)
})

test_that("get_course_pairs min_pair_n=4 drops CHEM→ENGL (n=3) but keeps CHEM→BIOL (n=4)", {
  result <- get_course_pairs(
    make_pathway_students(),
    make_pathway_population(),
    opt = list(min_n = 1, min_pair_n = 4)
  )

  chem_engl <- result[result$course_a == "CHEM 1215" & result$course_b == "ENGL 1110", ]
  chem_biol  <- result[result$course_a == "CHEM 1215" & result$course_b == "BIOL 2310", ]

  expect_equal(nrow(chem_engl), 0)
  expect_equal(nrow(chem_biol), 1)
})

test_that("get_course_pairs result is sorted descending by n_students", {
  result <- get_course_pairs(
    make_pathway_students(),
    make_pathway_population(),
    opt = list(min_n = 1, min_pair_n = 1)
  )
  expect_true(all(diff(result$n_students) <= 0))
})

test_that("get_course_pairs returns empty tibble when no pairs meet thresholds", {
  result <- get_course_pairs(
    make_pathway_students(),
    make_pathway_population(),
    opt = list(min_n = 1, min_pair_n = 999)
  )
  expect_equal(nrow(result), 0)
})
