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


# =============================================================================
# get_event_adjacent_courses() tests
# =============================================================================
#
# Fixture: 7 students, terms 202410 / 202480 / 202510
#
#   Student  entry_status  outcome            first_unit_term   notes
#   S001     pre_major     ongoing            202480            entered, prior term = 202410
#   S002     pre_major     ongoing            202480            entered, prior term = 202410
#   S003     pre_major     ongoing            202480            entered, prior term = 202410
#   S004     pre_major     chose_elsewhere    202480            did not enter, prior term = 202410
#   S005     pre_major     chose_elsewhere    202480            did not enter, prior term = 202410
#   S006     pre_major     ongoing            202410            entered, NO prior term (n_no_prior)
#   S007     switched_in   ongoing            202480            entered via switch — included
#
#   Groups are assigned by outcome only (not entry_status). switched_in students
#   like S007 are included in "entered" because they took courses in the target
#   major before switching — that's exactly the signal we want to detect.
#
#   Enrollments in the prior term window (202410 only):
#     CHEM 1215: S001, S002, S003, S004, S007   (3 pre_major + S007 entered, 1 did_not_enter)
#     HIST 101:  S002, S003, S004, S005          (2 entered, 2 did_not_enter)
#     PHYS 100:  S006 only                       (S006 excluded: no prior term)
#
#   Students with a prior term on record (in student_windows):
#     entered:       S001, S002, S003, S007  → n_group_entered = 4
#     did_not_enter: S004, S005              → n_group_did_not_enter = 2
#     S006 excluded from windows (first_unit_term = 202410 = earliest term)
#
#   Expected CHEM 1215 values:
#     n_students_entered = 4,  pct_entered = 4/4 = 1.0
#     n_students_did_not_enter = 1,  pct_did_not_enter = 1/2 = 0.5
#     lift = 1.0 / 0.5 = 2.0
#
#   Expected HIST 101 values:
#     n_students_entered = 2,  pct_entered = 2/4 = 0.5
#     n_students_did_not_enter = 2,  pct_did_not_enter = 2/2 = 1.0
#     lift = round(0.5 / 1.0, 2) = 0.5
#
#   PHYS 100 must NOT appear (only taker is S006, excluded for no prior term).
#   BIOL 2310 (202480 = event term) must NOT appear when include_event_term=FALSE.

make_ep_population <- function() {
  tibble(
    student_id       = c("S001", "S002", "S003", "S004", "S005", "S006", "S007"),
    population_label = "bio_majors",
    outcome          = c("ongoing", "ongoing", "ongoing",
                         "chose_elsewhere", "chose_elsewhere",
                         "ongoing",    # S006: entered, but first_unit_term=202410 (no prior)
                         "ongoing"),   # S007: switched_in, still "entered" by outcome
    entry_status     = c("pre_major", "pre_major", "pre_major",
                         "pre_major", "pre_major",
                         "pre_major",
                         "switched_in"),
    first_unit_term  = c(202480L, 202480L, 202480L,
                         202480L, 202480L,
                         202410L,   # earliest data term — no prior term exists
                         202480L),
    last_unit_term   = c(202510L, 202510L, 202510L,
                         202480L, 202480L,
                         202510L,
                         202510L)
  )
}

make_ep_students <- function() {
  tibble(
    student_id = c(
      # 202410: prior term window for first_unit_term=202480 students
      "S001", "S002", "S003", "S004", "S007",  # CHEM 1215 (S007 switched_in, now included)
      "S002", "S003", "S004", "S005",          # HIST 101
      "S006",                                  # PHYS 100 (S006 excluded: no prior term)
      # 202480: event term itself — should NOT appear in results
      "S001", "S002", "S003", "S004", "S005",
      # 202510: post-event — should NOT appear in results
      "S001", "S002"
    ),
    term = c(
      202410L, 202410L, 202410L, 202410L, 202410L,
      202410L, 202410L, 202410L, 202410L,
      202410L,
      202480L, 202480L, 202480L, 202480L, 202480L,
      202510L, 202510L
    ),
    subject_course = c(
      "CHEM 1215", "CHEM 1215", "CHEM 1215", "CHEM 1215", "CHEM 1215",
      "HIST 101",  "HIST 101",  "HIST 101",  "HIST 101",
      "PHYS 100",
      "BIOL 2310", "BIOL 2310", "BIOL 2310", "BIOL 2310", "BIOL 2310",
      "BIOL 3100", "BIOL 3100"
    ),
    course_title = c(
      rep("General Chemistry", 5),
      rep("World History",     4),
      rep("Physics",           1),
      rep("General Biology",   5),
      rep("Cell Biology",      2)
    ),
    registration_status_code = rep("RE", 17)
  )
}


test_that("get_event_adjacent_courses returns correct structure", {
  result <- get_event_adjacent_courses(
    make_ep_students(), make_ep_population(),
    event = "entry", min_n = 1
  )

  expect_s3_class(result, "data.frame")
  expect_true("subject_course"            %in% names(result))
  expect_true("subject_code"              %in% names(result))
  expect_true("course_title"              %in% names(result))
  expect_true("n_students_entered"        %in% names(result))
  expect_true("pct_entered"               %in% names(result))
  expect_true("n_students_did_not_enter"  %in% names(result))
  expect_true("pct_did_not_enter"         %in% names(result))
  expect_true("lift"                      %in% names(result))
})

test_that("get_event_adjacent_courses CHEM 1215: correct entered count and rate", {
  result <- get_event_adjacent_courses(
    make_ep_students(), make_ep_population(),
    event = "entry", min_n = 1
  )
  row <- result[result$subject_course == "CHEM 1215", ]

  expect_equal(nrow(row), 1)
  expect_equal(row$n_students_entered, 4)   # S001, S002, S003, S007
  expect_equal(row$pct_entered, 1.0)
})

test_that("get_event_adjacent_courses CHEM 1215: correct did-not-enter count and rate", {
  result <- get_event_adjacent_courses(
    make_ep_students(), make_ep_population(),
    event = "entry", min_n = 1
  )
  row <- result[result$subject_course == "CHEM 1215", ]

  expect_equal(row$n_students_did_not_enter, 1)
  expect_equal(row$pct_did_not_enter, 0.5)
})

test_that("get_event_adjacent_courses CHEM 1215: lift = 2.0", {
  result <- get_event_adjacent_courses(
    make_ep_students(), make_ep_population(),
    event = "entry", min_n = 1
  )
  row <- result[result$subject_course == "CHEM 1215", ]

  expect_equal(row$lift, 2.0)
})

test_that("get_event_adjacent_courses HIST 101: correct entered count and rate", {
  result <- get_event_adjacent_courses(
    make_ep_students(), make_ep_population(),
    event = "entry", min_n = 1
  )
  row <- result[result$subject_course == "HIST 101", ]

  expect_equal(nrow(row), 1)
  expect_equal(row$n_students_entered, 2)
  expect_equal(row$pct_entered, 0.5)
})

test_that("get_event_adjacent_courses HIST 101: did-not-enter rate = 1.0 and lift < 1", {
  result <- get_event_adjacent_courses(
    make_ep_students(), make_ep_population(),
    event = "entry", min_n = 1
  )
  row <- result[result$subject_course == "HIST 101", ]

  expect_equal(row$pct_did_not_enter, 1.0)
  expect_true(row$lift < 1)
})

test_that("get_event_adjacent_courses switched_in student S007 is included in entered group", {
  # S007 is switched_in but outcome=ongoing — they entered the major.
  # Their prior-term enrollments reflect courses that may have preceded the switch,
  # so they belong in the "entered" group alongside pre_major converters.
  # n_group_entered should be 4 (S001/S002/S003/S007), not 3.
  result <- get_event_adjacent_courses(
    make_ep_students(), make_ep_population(),
    event = "entry", min_n = 1
  )
  meta <- attr(result, "ep_meta")

  expect_equal(meta$n_groups$entered,       4L)
  expect_equal(meta$n_groups$did_not_enter, 2L)
})

test_that("get_event_adjacent_courses S006 (no prior term) is counted in n_no_prior", {
  result <- get_event_adjacent_courses(
    make_ep_students(), make_ep_population(),
    event = "entry", min_n = 1
  )
  meta <- attr(result, "ep_meta")

  expect_equal(meta$n_no_prior, 1L)
})

test_that("get_event_adjacent_courses PHYS 100 does not appear (only taker has no prior term)", {
  # S006 is the only PHYS 100 taker in 202410; S006 is excluded from windows
  # because first_unit_term = 202410 = earliest data term.
  result <- get_event_adjacent_courses(
    make_ep_students(), make_ep_population(),
    event = "entry", min_n = 1
  )

  expect_false("PHYS 100" %in% result$subject_course)
})

test_that("get_event_adjacent_courses event-term courses do not appear (include_event_term=FALSE)", {
  result <- get_event_adjacent_courses(
    make_ep_students(), make_ep_population(),
    event = "entry", window = 1L, include_event_term = FALSE, min_n = 1
  )

  expect_false("BIOL 2310" %in% result$subject_course)
})

test_that("get_event_adjacent_courses include_event_term=TRUE adds event-term courses", {
  result <- get_event_adjacent_courses(
    make_ep_students(), make_ep_population(),
    event = "entry", window = 1L, include_event_term = TRUE, min_n = 1
  )

  expect_true("BIOL 2310" %in% result$subject_course)
})

test_that("get_event_adjacent_courses min_n threshold filters correctly", {
  # With min_n=3: CHEM entered n=4 survives; HIST entered n=2 dropped,
  # HIST did_not_enter n=2 dropped — only CHEM appears.
  result <- get_event_adjacent_courses(
    make_ep_students(), make_ep_population(),
    event = "entry", min_n = 3
  )

  expect_true( "CHEM 1215" %in% result$subject_course)
  expect_false("HIST 101"  %in% result$subject_course)
})

test_that("get_event_adjacent_courses ep_meta attribute has expected fields", {
  result <- get_event_adjacent_courses(
    make_ep_students(), make_ep_population(),
    event = "entry", min_n = 1
  )
  meta <- attr(result, "ep_meta")

  expect_true(!is.null(meta))
  expect_true("event"      %in% names(meta))
  expect_true("n_groups"   %in% names(meta))
  expect_true("n_no_prior" %in% names(meta))
  expect_true("n_courses"  %in% names(meta))
  expect_equal(meta$event, "entry")
  expect_equal(meta$n_courses, nrow(result))
})

test_that("get_event_adjacent_courses errors when population missing required columns", {
  bad_pop <- tibble(student_id = c("S001", "S002"), population_label = "x")
  expect_error(
    get_event_adjacent_courses(make_ep_students(), bad_pop),
    "missing columns"
  )
})

test_that("get_event_adjacent_courses returns empty when all outcomes unclassifiable", {
  # Population with only stopped_out outcomes that don't match entry groups
  # (stopped_out IS in "entered" now) — test with outcome = NA instead
  no_group_pop <- make_ep_population() %>%
    mutate(outcome = NA_character_)
  result <- get_event_adjacent_courses(
    make_ep_students(), no_group_pop, event = "entry", min_n = 1
  )
  expect_equal(nrow(result), 0)
})

test_that("get_event_adjacent_courses returns empty when all students entered in first data term", {
  early_pop <- make_ep_population() %>%
    mutate(first_unit_term = 202410L)
  result <- get_event_adjacent_courses(
    make_ep_students(), early_pop, event = "entry", min_n = 1
  )
  expect_equal(nrow(result), 0)
})

test_that("get_event_adjacent_courses errors on invalid event argument", {
  expect_error(
    get_event_adjacent_courses(make_ep_students(), make_ep_population(),
                               event = "middle"),
    "entry.*exit"
  )
})


# =============================================================================
# get_course_pairs() observation-window censoring (opt$censor_term)
# =============================================================================
# Data terms: 202410, 202480, 202510. With censor_term = 202510 (last complete
# term) and max_term_gap = 2, the A-side boundary is 202410 — so CHEM 1215
# rows (all 202410) stay on the A side, but BIOL 2310 rows (202480) are too
# recent to have a full 2-term follow-up window and drop off the A side.

test_that("get_course_pairs censor_term drops A-side rows without a full follow-up window", {
  result <- get_course_pairs(
    make_pathway_students(), make_pathway_population(),
    opt = list(min_n = 1, min_pair_n = 1, max_term_gap = 2, censor_term = 202510L)
  )

  # CHEM 1215 pairs unaffected (A rows at 202410 have the full window)
  chem_biol <- result %>% filter(course_a == "CHEM 1215", course_b == "BIOL 2310")
  expect_equal(chem_biol$n_students, 4)
  expect_equal(chem_biol$n_took_a,   4)

  # BIOL 2310 (202480) has only one complete follow-up term — excluded as A
  expect_false("BIOL 2310" %in% result$course_a)

  # Boundary recorded in metadata for scope display
  expect_equal(attr(result, "pair_meta")$a_boundary, 202410L)
})

test_that("get_course_pairs censor_term with a 1-term gap keeps BIOL as course A", {
  # gap = 1 → boundary = 202480; BIOL 2310 rows (202480) now have full follow-up.
  result <- get_course_pairs(
    make_pathway_students(), make_pathway_population(),
    opt = list(min_n = 1, min_pair_n = 1, max_term_gap = 1, censor_term = 202510L)
  )
  biol_engl <- result %>% filter(course_a == "BIOL 2310", course_b == "ENGL 1110")
  expect_equal(biol_engl$n_students, 4)
  expect_equal(biol_engl$n_took_a,   5)
})

test_that("get_course_pairs without censor_term preserves uncensored behavior", {
  result <- get_course_pairs(
    make_pathway_students(), make_pathway_population(),
    opt = list(min_n = 1, min_pair_n = 1, max_term_gap = 2)
  )
  expect_true("BIOL 2310" %in% result$course_a)
  expect_null(attr(result, "pair_meta")$a_boundary)
})


# =============================================================================
# get_course_pairs() lift — pct_a_to_b anchored against B's overall popularity
# =============================================================================
# Population of 5: BIOL 2310 taken by 5/5 (baseline 1.0), ENGL 1110 by 4/5
# (0.8), CHEM 1215 by 4/5 (0.8).

test_that("get_course_pairs lift compares the A-to-B rate with B's overall take rate", {
  result <- get_course_pairs(
    make_pathway_students(), make_pathway_population(),
    opt = list(min_n = 1, min_pair_n = 1, max_term_gap = 2)
  )

  chem_biol <- result %>% filter(course_a == "CHEM 1215", course_b == "BIOL 2310")
  expect_equal(chem_biol$pct_pop_took_b, 1)
  expect_equal(chem_biol$lift, 1)          # 1.0 / 1.0 — B is universal, no signal

  chem_engl <- result %>% filter(course_a == "CHEM 1215", course_b == "ENGL 1110")
  expect_equal(chem_engl$pct_pop_took_b, 0.8)
  expect_equal(chem_engl$lift, 0.94)       # 0.75 / 0.8 — below-baseline follow-on

  biol_engl <- result %>% filter(course_a == "BIOL 2310", course_b == "ENGL 1110")
  expect_equal(biol_engl$lift, 1)          # 0.8 / 0.8
})
