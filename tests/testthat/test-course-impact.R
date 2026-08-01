# D2: the observational machinery.
#
#   R/branches/comparison.R  — build_comparison(), compute_balance()
#   R/cones/course-impact.R  — get_course_sequence_effect(), get_instructor_effect()
#
# These feed Course Dynamics > Sequence Effect and > Downstream Success. Their
# failure mode is a plausible-looking number, not an error, so these tests pin
# arithmetic, denominators, and who ends up in which group — not output shape.
#
# NOTE: get_course_retention(), .compute_retention(), and .advance_n_terms()
# were removed from course-impact.R on 2026-08-01 — no callers, a name collision
# with cones/course-retention.R, and a duplicate of add_next_term_col().
# Course Dynamics > Retention is served by get_retention_trend() in that file,
# which has its own tests.

context("Course impact — observational machinery")

# ── build_comparison ─────────────────────────────────────────────────────────

bc_programs <- function() {
  tibble::tibble(
    student_id = c("t1", "t2", "c1", "c2"),
    term = 202480L,
    student_population = "UG", student_classification = "Freshman",
    student_level = "UG", student_campus = "ABQ",
    first_gen     = c(TRUE, FALSE, TRUE, FALSE),
    pell_eligible = c(TRUE, TRUE, FALSE, FALSE),
    ipeds_race = "X", gender = "F", time_status = "FT", residency = "R",
    inst_gpa = c(3.0, 3.2, 2.8, 3.1), academic_standing = "Good",
    overall_credits_earned = c(30, 32, 28, 31)
  )
}
bc_students <- function() {
  tibble::tibble(student_id = c("t1", "t2", "c1", "c2"), term = 202480L)
}

test_that("groups are labelled from the id vectors, not from the data", {
  r <- suppressMessages(build_comparison(
    c("t1", "t2"), c("c1", "c2"), bc_programs(), students = bc_students()))
  expect_equal(r$n_treatment, 2)
  expect_equal(r$n_control, 2)
  expect_setequal(r$groups$student_id[r$groups$group == "treatment"], c("t1", "t2"))
  expect_setequal(r$groups$student_id[r$groups$group == "control"],   c("c1", "c2"))
})

test_that("a student with no program record is dropped from the comparison", {
  # Documents real behaviour: covariates come from an inner join on
  # cedar_programs, so a student with no record at or before their covariate
  # term leaves the comparison entirely. n_treatment therefore reports students
  # actually compared, which can be fewer than the ids passed in — any caller
  # displaying its own sample size alongside this can disagree with it.
  r <- suppressMessages(build_comparison(
    c("t1", "ghost"), c("c1", "c2"), bc_programs(), students = bc_students()))
  expect_equal(r$n_treatment, 1)
  expect_false("ghost" %in% r$groups$student_id)
})

test_that("a student in both groups is counted once, as treatment", {
  # pool_ids is documented as needing to exclude treatment_ids; nothing enforces
  # it, so pin the fallback rather than leave it undefined.
  r <- suppressMessages(build_comparison(
    c("t1"), c("t1", "c1"), bc_programs(), students = bc_students()))
  expect_equal(nrow(r$groups), 2)
  expect_equal(r$n_treatment, 1)
  expect_equal(r$n_control, 1)
  expect_equal(r$groups$group[r$groups$student_id == "t1"], "treatment")
})

test_that("empty treatment or control is an explicit error, not a silent empty result", {
  expect_error(suppressMessages(build_comparison(
    character(0), c("c1"), bc_programs(), students = bc_students())))
  expect_error(suppressMessages(build_comparison(
    c("t1"), character(0), bc_programs(), students = bc_students())))
})

test_that("covariates are taken at or before the covariate term, most recent first", {
  progs <- dplyr::bind_rows(
    bc_programs(),
    dplyr::mutate(bc_programs()[1, ], term = 202510L, inst_gpa = 9.9)  # later term
  )
  # Default (entry term) must not pick up the later 9.9 row.
  r <- suppressMessages(build_comparison(
    c("t1"), c("c1"), progs, students = bc_students()))
  expect_equal(r$groups$inst_gpa[r$groups$student_id == "t1"], 3.0)

  # Asking for the later term does pick it up.
  r2 <- suppressMessages(build_comparison(
    c("t1"), c("c1"), progs, students = bc_students(),
    covariate_terms = tibble::tibble(student_id = "t1", covariate_term = 202510L)))
  expect_equal(r2$groups$inst_gpa[r2$groups$student_id == "t1"], 9.9)
})

# ── compute_balance ──────────────────────────────────────────────────────────

test_that("binary SMD matches the documented formula", {
  groups <- tibble::tibble(
    student_id = c("a", "b", "c", "d"),
    group      = c("treatment", "treatment", "control", "control"),
    first_gen  = c(TRUE, TRUE, FALSE, FALSE)
  )
  b <- compute_balance(groups)
  row <- dplyr::filter(b$smd_table, covariate == "first_gen")

  p_t <- 1; p_c <- 0; p_bar <- 0.5
  expect_equal(row$smd, round((p_t - p_c) / sqrt(p_bar * (1 - p_bar)), 3))
  expect_equal(row$value_treatment, 100)
  expect_equal(row$value_control, 0)
  expect_true(row$flagged)                    # |SMD| = 2 is far past 0.25
})

test_that("continuous SMD matches the documented formula", {
  groups <- tibble::tibble(
    student_id = c("a", "b", "c", "d"),
    group      = c("treatment", "treatment", "control", "control"),
    inst_gpa   = c(3.0, 3.4, 2.6, 3.0)
  )
  b <- compute_balance(groups)
  row <- dplyr::filter(b$smd_table, covariate == "inst_gpa")

  mu_t <- mean(c(3.0, 3.4)); mu_c <- mean(c(2.6, 3.0))
  v_t  <- var(c(3.0, 3.4));  v_c  <- var(c(2.6, 3.0))
  expect_equal(row$smd, round((mu_t - mu_c) / sqrt((v_t + v_c) / 2), 3))
})

test_that("identical groups are perfectly balanced and unflagged", {
  groups <- tibble::tibble(
    student_id = c("a", "b", "c", "d"),
    group      = c("treatment", "treatment", "control", "control"),
    inst_gpa   = c(3.0, 3.4, 3.0, 3.4),
    first_gen  = c(TRUE, FALSE, TRUE, FALSE)
  )
  b <- compute_balance(groups)
  expect_true(all(b$smd_table$smd == 0))
  expect_false(any(b$smd_table$flagged))
})

test_that("zero variance yields NA rather than a divide-by-zero", {
  groups <- tibble::tibble(
    student_id = c("a", "b", "c", "d"),
    group      = c("treatment", "treatment", "control", "control"),
    inst_gpa   = c(3.0, 3.0, 3.0, 3.0)
  )
  b <- compute_balance(groups)
  row <- dplyr::filter(b$smd_table, covariate == "inst_gpa")
  expect_true(is.na(row$smd))
  expect_false(row$flagged)
})

test_that("the flag threshold is |SMD| > 0.25", {
  b <- compute_balance(tibble::tibble(
    student_id = letters[1:4],
    group      = c("treatment", "treatment", "control", "control"),
    inst_gpa   = c(3.0, 3.2, 2.9, 3.1)   # small, well-balanced difference
  ))
  row <- dplyr::filter(b$smd_table, covariate == "inst_gpa")
  expect_equal(row$flagged, abs(row$smd) > 0.25)
})

test_that("categorical covariates are returned as distributions, not SMDs", {
  groups <- tibble::tibble(
    student_id = letters[1:4],
    group      = c("treatment", "treatment", "control", "control"),
    gender     = c("F", "M", "F", "F")
  )
  b <- compute_balance(groups)
  expect_false("gender" %in% b$smd_table$covariate)
  expect_true("gender" %in% names(b$categorical))
  expect_setequal(unique(b$categorical$gender$group), c("treatment", "control"))
  # Percentages are within-group, so each group sums to 100.
  sums <- tapply(b$categorical$gender$pct, b$categorical$gender$group, sum)
  expect_true(all(abs(sums - 100) < 0.5))
})
