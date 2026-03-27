# Tests for enrollment demand bottleneck functions
# Tests get_bottlenecks() and compute_waitlist_pressure() from R/cones/bottleneck.R

context("Bottleneck Analysis")

# =============================================================================
# Fixtures
# =============================================================================
#
# Cohort: S001, S002 are health_major; S003 is health_pre_major
# Students enrollment records:
#   BIOL 2310: S001=WL, S002=WL, S003=WL, S004=RE (S004 not in cohort)
#   CHEM 1215: S001=RE, S002=WL (S002 waitlisted but also registered in another section? no)
#   NURS 201:  S001=RE, S002=RE (both in, no waitlist pressure)
#   MATH 1220: S003=WL
#
# Expected waitlist pressure (all cohort = S001 + S002 + S003):
#   BIOL 2310: S001, S002, S003 all WL and not RE → 3 waitlisted
#   CHEM 1215: S002 WL and not RE → 1 waitlisted
#   MATH 1220: S003 WL → 1 waitlisted
#   NURS 201:  no WL → 0

make_test_cohort <- function() {
  tibble(
    student_id   = c("S001", "S002", "S003"),
    population_label = c("health_major", "health_major", "health_pre_major")
  )
}

make_test_students <- function() {
  tibble(
    student_id              = c("S001", "S002", "S003", "S004",
                                "S001", "S002",
                                "S001", "S002",
                                "S003"),
    subject_course          = c("BIOL 2310", "BIOL 2310", "BIOL 2310", "BIOL 2310",
                                "CHEM 1215", "CHEM 1215",
                                "NURS 201",  "NURS 201",
                                "MATH 1220"),
    registration_status_code = c("WL", "WL", "WL", "RE",
                                 "RE", "WL",
                                 "RE", "RE",
                                 "WL"),
    term   = rep(202510, 9),
    campus = rep("M", 9)
  )
}


# =============================================================================
# compute_waitlist_pressure()
# =============================================================================

test_that("compute_waitlist_pressure returns correct columns", {
  students  <- make_test_students()
  cohort_ids <- c("S001", "S002", "S003")
  result <- compute_waitlist_pressure(students, cohort_ids)

  expect_s3_class(result, "data.frame")
  expect_true("subject_course" %in% names(result))
  expect_true("n_waitlisted"   %in% names(result))
})

test_that("compute_waitlist_pressure counts unregistered waitlisted students", {
  students   <- make_test_students()
  cohort_ids <- c("S001", "S002", "S003")
  result     <- compute_waitlist_pressure(students, cohort_ids)

  biol <- result$n_waitlisted[result$subject_course == "BIOL 2310"]
  expect_equal(biol, 3)
})

test_that("compute_waitlist_pressure excludes students who are also registered", {
  # S002 is WL for CHEM 1215 but also RE for CHEM 1215 — should NOT count
  students <- tibble(
    student_id               = c("S001", "S002", "S002"),
    subject_course           = c("CHEM 1215", "CHEM 1215", "CHEM 1215"),
    registration_status_code = c("WL", "WL", "RE"),
    term = c(202510, 202510, 202510),
    campus = c("M", "M", "M")
  )
  result <- compute_waitlist_pressure(students, c("S001", "S002"))

  chem <- result$n_waitlisted[result$subject_course == "CHEM 1215"]
  # Only S001 should count — S002 is also registered
  expect_equal(chem, 1)
})

test_that("compute_waitlist_pressure excludes students not in cohort", {
  students   <- make_test_students()
  cohort_ids <- c("S001", "S002", "S003")
  result     <- compute_waitlist_pressure(students, cohort_ids)

  # S004 is WL for BIOL 2310 but not in cohort
  biol <- result$n_waitlisted[result$subject_course == "BIOL 2310"]
  expect_equal(biol, 3)  # S001, S002, S003 — not S004
})

test_that("compute_waitlist_pressure returns empty df when no waitlisted cohort students", {
  students <- make_test_students() %>%
    filter(registration_status_code == "RE")  # remove all WL rows
  result <- compute_waitlist_pressure(students, c("S001", "S002", "S003"))

  expect_equal(nrow(result), 0)
})

test_that("compute_waitlist_pressure sorts descending by n_waitlisted", {
  students   <- make_test_students()
  cohort_ids <- c("S001", "S002", "S003")
  result     <- compute_waitlist_pressure(students, cohort_ids)

  expect_true(all(diff(result$n_waitlisted) <= 0))
})


# =============================================================================
# get_bottlenecks()
# =============================================================================

test_that("get_bottlenecks returns correct top-level structure", {
  cohort   <- make_test_cohort()
  students <- make_test_students()
  result   <- get_bottlenecks(cohort, students, opt = list())

  expect_type(result, "list")
  expect_true("waitlist"    %in% names(result))
  expect_true("population_size" %in% names(result))
})

test_that("get_bottlenecks population_size matches cohort input", {
  cohort   <- make_test_cohort()
  students <- make_test_students()
  result   <- get_bottlenecks(cohort, students, opt = list())

  # cohort has 2 health_major, 1 health_pre_major
  expect_equal(unname(result$population_size["health_major"]),     2L)
  expect_equal(unname(result$population_size["health_pre_major"]), 1L)
})

test_that("get_bottlenecks$waitlist reflects all cohort students", {
  cohort   <- make_test_cohort()
  students <- make_test_students()
  result   <- get_bottlenecks(cohort, students, opt = list())

  # BIOL 2310: 3 cohort students waitlisted
  biol <- result$waitlist$n_waitlisted[result$waitlist$subject_course == "BIOL 2310"]
  expect_equal(biol, 3)
})

test_that("get_bottlenecks produces by_label when multiple cohort labels", {
  cohort   <- make_test_cohort()
  students <- make_test_students()
  result   <- get_bottlenecks(cohort, students, opt = list())

  expect_true("by_label" %in% names(result))
  expect_true("population_label" %in% names(result$by_label))
})

test_that("get_bottlenecks does NOT produce by_label for single-label cohort", {
  cohort_single <- make_test_cohort() %>%
    filter(population_label == "health_major")
  students <- make_test_students()
  result   <- get_bottlenecks(cohort_single, students, opt = list())

  expect_false("by_label" %in% names(result))
})

test_that("get_bottlenecks stops on malformed cohort input", {
  bad_cohort <- tibble(id = c("S001", "S002"))  # wrong column name
  students   <- make_test_students()
  expect_error(get_bottlenecks(bad_cohort, students, opt = list()),
               "student_id")
})

test_that("get_bottlenecks respects opt$term filter", {
  cohort   <- make_test_cohort()
  # Students include term 202510; filtering to 202480 should yield no results
  students <- make_test_students()
  result   <- get_bottlenecks(cohort, students, opt = list(term = 202480))

  expect_equal(nrow(result$waitlist), 0)
})

test_that("get_bottlenecks by_label splits counts by cohort group", {
  cohort   <- make_test_cohort()
  students <- make_test_students()
  result   <- get_bottlenecks(cohort, students, opt = list())

  # MATH 1220: only S003 (health_pre_major) is waitlisted
  math_major     <- result$by_label %>%
    filter(population_label == "health_major", subject_course == "MATH 1220")
  math_pre_major <- result$by_label %>%
    filter(population_label == "health_pre_major", subject_course == "MATH 1220")

  # health_major students (S001, S002) have no MATH 1220 WL record
  expect_true(nrow(math_major) == 0 || math_major$n_waitlisted == 0)
  expect_equal(math_pre_major$n_waitlisted, 1)
})
