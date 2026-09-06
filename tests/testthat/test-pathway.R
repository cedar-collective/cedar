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
    registration_status_code = rep("RE", 13),
    # All ABQ: the timing/pairs expectations above are stated per course, so a
    # single campus keeps them one row each. The two-campus behaviour is pinned
    # separately at the end of this file.
    campus = rep("ABQ", 13)
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

test_that("get_course_timing counts each course position against its eligible population", {
  result <- get_course_timing(
    make_pathway_students(), make_pathway_population(), opt = list(min_n = 1)
  ) %>% arrange(subject_course, relative_term)

  expect_s3_class(result, "data.frame")
  expect_true(all(c("subject_code", "course_title", "median_term") %in% names(result)))
  # S005 alone takes BIOL at RT1 and ENGL at RT2. Only three students reach RT3.
  expected <- tibble::tribble(
    ~subject_course, ~relative_term, ~n_students, ~n_eligible, ~pct_pop,
    "BIOL 2310",     1,              1,           5,           0.2,
    "BIOL 2310",     2,              4,           5,           0.8,
    "CHEM 1215",     1,              4,           5,           0.8,
    "ENGL 1110",     2,              1,           5,           0.2,
    "ENGL 1110",     3,              3,           3,           1.0
  )
  for (column in names(expected)) {
    expect_equal(result[[column]], expected[[column]], info = column)
  }
})


test_that("get_course_timing min_n drops courses below total-student threshold", {
  # CHEM 1215 total = 4; ENGL 1110 total = 4; BIOL 2310 total = 5
  # min_n=5 → CHEM and ENGL drop; BIOL survives
  result <- get_course_timing(
    make_pathway_students(),
    make_pathway_population(),
    opt = list(min_n = 5, min_band_n = 1L, min_cell_n = 1L)
  )

  expect_false("CHEM 1215" %in% result$subject_course)
  expect_false("ENGL 1110" %in% result$subject_course)
  expect_true( "BIOL 2310" %in% result$subject_course)
})

test_that("course minimum counts distinct students rather than repeated positions", {
  students <- tibble::tibble(
    student_id = c("R1", "R1"),
    term = c(202410L, 202480L),
    subject_course = "REPT 100",
    course_title = "Repeated Course",
    student_classification = c("Freshman", "Sophomore"),
    registration_status_code = "RE",
    campus = "ABQ"
  )
  population <- tibble::tibble(student_id = "R1", population_label = "repeat")

  result <- suppressMessages(get_course_timing(
    students, population,
    opt = list(
      min_n = 2L, min_band_n = 1L, min_cell_n = 1L,
      x_axis = "relative_term"
    ),
    students_full = students
  ))

  expect_equal(nrow(result), 0L)
})

test_that("relative term is assigned before course level filtering", {
  students <- tibble::tibble(
    student_id = c("S1", "S1"),
    term = c(202410L, 202480L),
    subject_course = c("LOW 100", "HIGH 300"),
    course_title = c("Lower Course", "Upper Course"),
    student_classification = c("Freshman", "Sophomore"),
    registration_status_code = "RE",
    campus = "ABQ",
    level = c("lower", "upper")
  )
  population <- tibble::tibble(student_id = "S1", population_label = "timing")

  result <- suppressMessages(get_course_timing(
    students, population,
    opt = list(
      min_n = 1L, min_band_n = 1L, min_cell_n = 1L,
      x_axis = "relative_term", level = "upper"
    ),
    students_full = students
  ))

  expect_equal(result$subject_course, "HIGH 300")
  expect_equal(result$relative_term, 2L)
})

test_that("timing suppresses thin bands and thin course cells separately", {
  students <- tibble::tibble(
    student_id = paste0("S", 1:6),
    term = 202410L,
    subject_course = c(rep("TARGET 100", 2), rep("OTHER 100", 4)),
    course_title = c(rep("Target", 2), rep("Other", 4)),
    student_classification = "Freshman",
    registration_status_code = "RE",
    campus = "ABQ"
  )
  population <- tibble::tibble(
    student_id = paste0("S", 1:6), population_label = "guards"
  )

  thin_cell <- suppressMessages(get_course_timing(
    students, population,
    opt = list(
      min_n = 1L, min_band_n = 5L, min_cell_n = 3L,
      x_axis = "classification", subject_course = "TARGET 100"
    )
  ))
  thin_band <- suppressMessages(get_course_timing(
    students, population,
    opt = list(
      min_n = 1L, min_band_n = 7L, min_cell_n = 1L,
      x_axis = "classification", subject_course = "TARGET 100"
    )
  ))

  expect_equal(nrow(thin_cell), 0L)
  expect_equal(nrow(thin_band), 0L)
  expect_equal(attr(thin_band, "timing_meta")$n_bands_suppressed, 1L)
})

test_that("get_course_timing start_classification excludes S005 from counts and eligibility", {
  result <- get_course_timing(
    make_pathway_students(), make_pathway_population(),
    opt = list(min_n = 1, start_classification = "Freshman")
  ) %>%
    filter(subject_course %in% c("BIOL 2310", "CHEM 1215")) %>%
    arrange(subject_course, relative_term)

  # S005 entered as a Sophomore: BIOL at RT1 disappears, leaving four eligible
  # Freshmen who all take CHEM at RT1 and BIOL at RT2.
  expected <- tibble::tribble(
    ~subject_course, ~relative_term, ~n_students, ~n_eligible, ~pct_pop,
    "BIOL 2310",     2,              4,           4,           1.0,
    "CHEM 1215",     1,              4,           4,           1.0
  )
  for (column in names(expected)) {
    expect_equal(result[[column]], expected[[column]], info = column)
  }
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

test_that("get_course_pairs preserves progression counts, rates, gaps, and frequency order", {
  result <- get_course_pairs(
    make_pathway_students(), make_pathway_population(),
    opt = list(min_n = 1, min_pair_n = 1)
  )

  expect_s3_class(result, "data.frame")
  expect_true(all(diff(result$n_students) <= 0))
  expected <- tibble::tribble(
    ~course_a,   ~course_b,   ~n_students, ~n_took_a, ~pct_a_to_b, ~median_term_gap,
    "BIOL 2310", "ENGL 1110", 4,           5,         0.80,        1,
    "CHEM 1215", "BIOL 2310", 4,           4,         1.00,        1,
    "CHEM 1215", "ENGL 1110", 3,           4,         0.75,        2
  )
  result <- result %>% arrange(course_a, course_b)
  for (column in names(expected)) {
    expect_equal(result[[column]], expected[[column]], info = column)
  }
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
    registration_status_code = rep("RE", 17),
    campus = rep("ABQ", 17)
  )
}


test_that("get_event_adjacent_courses compares prior courses with audited entry groups", {
  result <- get_event_adjacent_courses(
    make_ep_students(), make_ep_population(), event = "entry", min_n = 1
  )
  meta <- attr(result, "ep_meta")

  expect_s3_class(result, "data.frame")
  expect_true(all(c("subject_code", "course_title") %in% names(result)))
  # S007 switched in with outcome=ongoing and belongs among the four entrants.
  # S006 has no prior term: exclude their PHYS 100 and count that exclusion.
  # The default window also excludes event-term BIOL 2310 and later courses.
  expected <- tibble::tribble(
    ~subject_course, ~n_students_entered, ~pct_entered, ~n_students_did_not_enter, ~pct_did_not_enter, ~lift,
    "CHEM 1215",     4,                   1.0,          1,                         0.5,                2.0,
    "HIST 101",      2,                   0.5,          2,                         1.0,                0.5
  )
  result <- result %>% arrange(subject_course)
  for (column in names(expected)) {
    expect_equal(result[[column]], expected[[column]], info = column)
  }
  expect_equal(meta$event, "entry")
  expect_equal(meta$n_groups$entered, 4L)
  expect_equal(meta$n_groups$did_not_enter, 2L)
  expect_equal(meta$n_no_prior, 1L)
  expect_equal(meta$n_courses, nrow(result))
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


# ── Campus policy ────────────────────────────────────────────────────────────
#
# Course-delivery campus (`campus` on cedar_students) is not the same field as
# the population's home campus (`student_campus` on cedar_programs); they differ
# on roughly 28% of enrollment rows. Filtering only on home campus therefore
# leaves branch-delivered course rows inside a main-campus view. These tests pin
# the delivery-campus scope and grouping.

# MC02 in designed_test_data.R supplies the two-campus rows; the population
# wrapper is shape, not data.
mc_population <- function(ids) {
  tibble(student_id = ids, population_label = "MC test population")
}

test_that("course timing splits one course across its delivery campuses", {
  r <- suppressMessages(get_course_timing(
    test_students_mc, mc_population(unique(test_students_mc$student_id)),
    opt = list(min_n = 1L, x_axis = "relative_term")
  ))
  expect_true("campus" %in% names(r))
  gate <- dplyr::filter(r, subject_course == "SPAN 101")
  expect_setequal(gate$campus, c("ABQ", "GA"))
  # Two rows — 4 ABQ students and 2 GA — not one blended row of 6.
  expect_equal(sort(gate$n_students), c(2L, 4L))
})

test_that("curriculum map labels multi-campus course rows distinctly", {
  timing <- suppressMessages(get_course_timing(
    test_students_mc, mc_population(unique(test_students_mc$student_id)),
    opt = list(min_n = 1L, x_axis = "relative_term")
  ))
  plot <- suppressMessages(plot_curriculum_map(
    timing, opt = list(min_pct = 0, top_n = 40L)
  ))

  gate_labels <- unique(plot$data$.course_label[plot$data$subject_course == "SPAN 101"])
  expect_setequal(gate_labels, c("SPAN 101 · ABQ", "SPAN 101 · GA"))
})

test_that("opt$campus scopes course timing to the delivery campus", {
  r <- suppressMessages(get_course_timing(
    test_students_mc, mc_population(unique(test_students_mc$student_id)),
    opt = list(min_n = 1L, campus = "ABQ", x_axis = "relative_term")
  ))
  expect_equal(unique(r$campus), "ABQ")
  # Only the four ABQ students remain in the gateway row.
  expect_equal(
    dplyr::filter(r, subject_course == "SPAN 101")$n_students, 4L)
})

test_that("course timing without a campus column fails loudly", {
  # Degrading to a campus-blind result is the failure this policy prevents.
  no_campus <- dplyr::select(test_students_mc, -campus)
  expect_error(
    suppressMessages(get_course_timing(
      no_campus, mc_population(unique(test_students_mc$student_id)),
      opt = list(min_n = 1L, x_axis = "relative_term"))),
    "campus"
  )
})

test_that("course pairs scope by delivery campus but keep cross-campus pairs", {
  # A pair is a statement about one student taking two courses, and those two can
  # legitimately sit on different campuses. MC_G1 in MC02 is exactly that: they
  # took SPAN 101 at GA and the follow-on SPAN 201 at ABQ. Campus scopes which
  # rows enter the self-join; it is deliberately not part of the pair key.
  pop <- mc_population(unique(test_students_mc$student_id))

  both <- suppressMessages(get_course_pairs(
    test_students_mc, pop,
    list(min_n = 1L, min_pair_n = 1L, campus = c("ABQ", "GA"))))
  seq_pair <- dplyr::filter(both, course_a == "SPAN 101", course_b == "SPAN 201")

  # MC_A1, MC_A2, MC_A4 (ABQ throughout) plus MC_G1 (GA -> ABQ).
  expect_equal(seq_pair$n_students, 4L)
  # Pair rows are not campus-keyed — there is no single campus for the pair.
  expect_false("campus" %in% names(both))

  # Scoping to ABQ alone drops MC_G1's GA-side enrolment, so they leave the pair.
  abq_only <- suppressMessages(get_course_pairs(
    test_students_mc, pop, list(min_n = 1L, min_pair_n = 1L, campus = "ABQ")))
  abq_pair <- dplyr::filter(abq_only, course_a == "SPAN 101", course_b == "SPAN 201")
  expect_equal(abq_pair$n_students, 3L)
})


# =============================================================================
# Left-truncation guard on the credit-band axes
# =============================================================================
#
# A credit band says where a student was in their career. The running total that
# answers it starts at zero on the student's first term IN THE DATA, so anyone
# already enrolled when the window opens begins mid-career reading zero and lands
# in the 0-30 band regardless of how far along they actually were.
#
# In this fixture 202410 is the first term of the data:
#   S001-S004  first term 202410  == min_data_term  -> left-truncated, excluded
#   S005       first term 202480  >  min_data_term  -> full record visible, kept
#
# The classification axis reads a per-term Banner value and is unaffected, which
# is why it is the default and why the guard must not touch it.

make_pathway_term_credits <- function() {
  tibble(
    student_id = c("S001", "S001", "S001",
                   "S002", "S002", "S002",
                   "S003", "S003",
                   "S004", "S004", "S004",
                   "S005", "S005"),
    term = c(202410L, 202480L, 202510L,
             202410L, 202480L, 202510L,
             202410L, 202480L,
             202410L, 202480L, 202510L,
             202480L, 202510L),
    attempted_unm_credits = rep(15, 13),
    completed_unm_credits = rep(15, 13)
  ) %>%
    dplyr::group_by(student_id) %>%
    dplyr::arrange(term, .by_group = TRUE) %>%
    dplyr::mutate(
      cumulative_attempted_unm_credits = cumsum(attempted_unm_credits),
      cumulative_completed_unm_credits = cumsum(completed_unm_credits)
    ) %>%
    dplyr::ungroup()
}

test_that("inst_credit_band drops left-truncated students and reports the count", {
  result <- get_course_timing(
    make_pathway_students(),
    make_pathway_population(),
    opt = list(min_n = 1, x_axis = "inst_credit_band"),
    term_credits = make_pathway_term_credits()
  )

  meta <- attr(result, "timing_meta")
  # S001-S004 begin at the edge of the data; only S005 has a readable position.
  expect_equal(meta$n_truncated, 4)

  # n_analyzed is captured before the x-axis step, so it must be restated after
  # the guard runs. Otherwise the scope bar reports an analyzed count and an
  # excluded count that together exceed the population.
  expect_equal(meta$n_analyzed, 1)
  expect_lte(meta$n_analyzed + meta$n_truncated, meta$n_population)

  # CHEM 1215 was taken only by S001-S004, all excluded, so it cannot appear.
  expect_false("CHEM 1215" %in% result$subject_course)
  # BIOL 2310 was taken by S005 in a term we can place, so it survives.
  expect_true("BIOL 2310" %in% result$subject_course)
})

test_that("unm_credit_band carries the same guard as the other credit axes", {
  result <- get_course_timing(
    make_pathway_students(),
    make_pathway_population(),
    opt = list(min_n = 1, x_axis = "unm_credit_band"),
    term_credits = make_pathway_term_credits()
  )

  expect_equal(attr(result, "timing_meta")$n_truncated, 4)
  expect_false("CHEM 1215" %in% result$subject_course)
})

test_that("classification axis excludes nobody for truncation", {
  result <- get_course_timing(
    make_pathway_students(),
    make_pathway_population(),
    opt = list(min_n = 1, x_axis = "classification"),
    term_credits = make_pathway_term_credits()
  )

  expect_equal(attr(result, "timing_meta")$n_truncated, 0L)
  # Every course is still reachable, including the one only truncated students took.
  expect_true("CHEM 1215" %in% result$subject_course)
})

test_that("a fully-visible population loses no students to the guard", {
  # Same data, but an earlier term now exists in the credit table, so the window
  # opens before every S00x student's first term and none of them are truncated.
  tc <- make_pathway_term_credits()
  result <- get_course_timing(
    make_pathway_students(),
    make_pathway_population(),
    opt = list(min_n = 1, x_axis = "inst_credit_band"),
    term_credits = dplyr::bind_rows(
      tibble(student_id = "S000", term = 202380L,
             attempted_unm_credits = 12, completed_unm_credits = 12,
             cumulative_attempted_unm_credits = 12,
             cumulative_completed_unm_credits = 12),
      tc
    )
  )

  expect_equal(attr(result, "timing_meta")$n_truncated, 0)
  expect_true("CHEM 1215" %in% result$subject_course)
})
