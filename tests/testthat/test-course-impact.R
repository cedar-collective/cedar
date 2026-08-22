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

.impact_edges <- list(
  first_enrolled = 202010L,
  last_enrolled = 202180L,
  last_enrolled_complete = 202110L,
  last_graded = 202110L,
  last_degree = NULL
)

# ── build_comparison ─────────────────────────────────────────────────────────

# Covariates and ids come from MC02 (cedar_programs_mc / cedar_students_mc):
# six students, two campuses, varying GPA/Pell/first-gen, and a second program
# record for MC_A1 at 202110 so covariate-term selection has something to pick
# between.
bc_ids <- c("MC_A1", "MC_A2", "MC_A3", "MC_A4")

test_that("groups are labelled from the id vectors, not from the data", {
  r <- suppressMessages(build_comparison(
    c("MC_A1", "MC_A2"), c("MC_A3", "MC_A4"), test_programs_mc, students = test_students_mc))
  expect_equal(r$n_treatment, 2)
  expect_equal(r$n_control, 2)
  expect_setequal(r$groups$student_id[r$groups$group == "treatment"], c("MC_A1", "MC_A2"))
  expect_setequal(r$groups$student_id[r$groups$group == "control"],   c("MC_A3", "MC_A4"))
})

test_that("a student with no program record is dropped from the comparison", {
  # Documents real behaviour: covariates come from an inner join on
  # cedar_programs, so a student with no record at or before their covariate
  # term leaves the comparison entirely. n_treatment therefore reports students
  # actually compared, which can be fewer than the ids passed in — any caller
  # displaying its own sample size alongside this can disagree with it.
  r <- suppressMessages(build_comparison(
    c("MC_A1", "ghost"), c("MC_A3", "MC_A4"), test_programs_mc, students = test_students_mc))
  expect_equal(r$n_treatment, 1)
  expect_false("ghost" %in% r$groups$student_id)
})

test_that("a student in both groups is counted once, as treatment", {
  # pool_ids is documented as needing to exclude treatment_ids; nothing enforces
  # it, so pin the fallback rather than leave it undefined.
  r <- suppressMessages(build_comparison(
    c("MC_A1"), c("MC_A1", "MC_A3"), test_programs_mc, students = test_students_mc))
  expect_equal(nrow(r$groups), 2)
  expect_equal(r$n_treatment, 1)
  expect_equal(r$n_control, 1)
  expect_equal(r$groups$group[r$groups$student_id == "MC_A1"], "treatment")
})

test_that("empty treatment or control is an explicit error, not a silent empty result", {
  expect_error(suppressMessages(build_comparison(
    character(0), c("MC_A3"), test_programs_mc, students = test_students_mc)))
  expect_error(suppressMessages(build_comparison(
    c("MC_A1"), character(0), test_programs_mc, students = test_students_mc)))
})

test_that("covariates are taken at or before the covariate term, most recent first", {
  # MC_A1 has two program records in MC02: 202010 (standing "Good") and 202110
  # ("Probation"). Neither branch may simply take the latest row.
  r <- suppressMessages(build_comparison(
    c("MC_A1"), c("MC_A3"), test_programs_mc, students = test_students_mc))
  # Default is the entry term (202010), so the later Probation row must not win.
  expect_equal(r$groups$academic_standing[r$groups$student_id == "MC_A1"], "Good")

  # Asking for a term at or after the later record does pick it up.
  r2 <- suppressMessages(build_comparison(
    c("MC_A1"), c("MC_A3"), test_programs_mc, students = test_students_mc,
    covariate_terms = tibble::tibble(student_id = "MC_A1", covariate_term = 202110L)))
  expect_equal(r2$groups$academic_standing[r2$groups$student_id == "MC_A1"], "Probation")
})

test_that("the frozen cumulative fields never reach the comparison groups", {
  # This is the regression guard for the whole change. inst_gpa, inst_credits_*
  # and overall_credits_* are stamped as of the data pull and repeat a student's
  # final totals on every historical row, so matching on them means matching on
  # the outcome. They are present in the fixture and must be dropped anyway.
  r <- suppressMessages(build_comparison(
    c("MC_A1"), c("MC_A3"), test_programs_mc, students = test_students_mc))

  banned <- c("inst_gpa", "inst_credits_attempted", "inst_credits_earned",
              "overall_credits_attempted", "overall_credits_earned")
  expect_equal(intersect(banned, names(r$groups)), character(0))
  expect_equal(intersect(banned, r$balance$smd_table$covariate), character(0))
})

test_that("current_unm_gpa is carried for description but never balanced on", {
  # Institution GPA is measured at the data pull — after the treatment and after
  # the outcome — so it cannot certify that the groups were comparable at the
  # point of comparison. It is still the best-covered summary of overall academic
  # strength (populated for ~4x as many students as the reconstruction), so it
  # rides along in `groups` for the profile table and is excluded from the SMDs.
  r <- suppressMessages(build_comparison(
    c("MC_A1"), c("MC_A3"), test_programs_mc, students = test_students_mc))

  expect_true("current_unm_gpa" %in% names(r$groups))
  expect_false("current_unm_gpa" %in% r$balance$smd_table$covariate)
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
    cum_gpa_entering = c(3.0, 3.4, 2.6, 3.0)
  )
  b <- compute_balance(groups)
  row <- dplyr::filter(b$smd_table, covariate == "cum_gpa_entering")

  mu_t <- mean(c(3.0, 3.4)); mu_c <- mean(c(2.6, 3.0))
  v_t  <- var(c(3.0, 3.4));  v_c  <- var(c(2.6, 3.0))
  expect_equal(row$smd, round((mu_t - mu_c) / sqrt((v_t + v_c) / 2), 3))
})

test_that("identical groups are perfectly balanced and unflagged", {
  groups <- tibble::tibble(
    student_id = c("a", "b", "c", "d"),
    group      = c("treatment", "treatment", "control", "control"),
    cum_gpa_entering = c(3.0, 3.4, 3.0, 3.4),
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
    cum_gpa_entering = c(3.0, 3.0, 3.0, 3.0)
  )
  b <- compute_balance(groups)
  row <- dplyr::filter(b$smd_table, covariate == "cum_gpa_entering")
  expect_true(is.na(row$smd))
  expect_false(row$flagged)
})

test_that("the flag threshold is |SMD| > 0.25", {
  b <- compute_balance(tibble::tibble(
    student_id = letters[1:4],
    group      = c("treatment", "treatment", "control", "control"),
    cum_gpa_entering = c(3.0, 3.2, 2.9, 3.1)   # small, well-balanced difference
  ))
  row <- dplyr::filter(b$smd_table, covariate == "cum_gpa_entering")
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

# ── get_instructor_effect: the contract the Downstream Success tab renders ────
#
# This tab shipped telling readers to "read the balance table first" while the
# balance table was never rendered — the cone returned it and the UI dropped it.
# A UI omission is not directly testable here, but the reverse is: if the cone
# ever stops returning these fields, the tab silently loses the only thing on it
# that speaks to section self-selection. Pin the contract.

test_that("get_instructor_effect returns everything the balance section needs", {
  needed <- c("balance", "n_treatment", "n_control",
              "reference_instructor", "comparison_instructor",
              "instructor_counts", "outcomes", "order_audit_by_year",
              "course_summary")
  fmls <- names(formals(get_instructor_effect))
  expect_true(all(c("students", "programs", "opt") %in% fmls))

  # The documented return shape, asserted against the roxygen block so the two
  # cannot drift apart unnoticed.
  src <- readLines("../../R/cones/course-impact.R", warn = FALSE)
  start <- grep("^get_instructor_effect <- function", src)
  expect_length(start, 1)
  body_txt <- paste(src[start:length(src)], collapse = "\n")
  for (f in needed) {
    expect_match(body_txt, paste0("\\b", f, "\\s*=" ),
                 info = paste("get_instructor_effect no longer returns", f))
  }
})

test_that("the balance check is documented as pairwise, not all-instructors", {
  # The UI states which two instructors are compared and how many are excluded.
  # That claim comes from this cone choosing a reference and a comparison
  # instructor rather than pooling everyone else into one control group.
  src <- paste(readLines("../../R/cones/course-impact.R", warn = FALSE), collapse = "\n")
  expect_match(src, "ref_instructor\\s*<-")
  expect_match(src, "cmp_instructor\\s*<-")
  # One-vs-everyone would pool; assert the pool is a single named instructor.
  expect_match(src, "pool_ids\\s*<-\\s*filter\\(instructor_data, instructor_name == cmp_instructor\\)")
})

test_that("downstream balance is optional context below descriptive outcomes", {
  src <- readLines("../../server.R", warn = FALSE)
  outcomes_line <- grep('paste0\\("Downstream Outcomes in', src)
  optional_line <- grep(
    '"Optional context: were the two largest instructor groups similar?"',
    src,
    fixed = TRUE
  )

  expect_length(outcomes_line, 1L)
  expect_length(optional_line, 1L)
  expect_lt(outcomes_line, optional_line)

  optional_copy <- paste(src[optional_line:min(length(src), optional_line + 45L)],
                         collapse = "\n")
  expect_match(optional_copy, "do not require instructor groups to be similar")
  expect_match(optional_copy, "nothing in the rates above")
  expect_match(optional_copy, 'group_labels = c\\("Instructor A", "Instructor B"\\)')
})

test_that("sequence effect presents one interpretation panel before its controls", {
  src <- readLines("../../server.R", warn = FALSE)
  start <- grep("output\\$cr_impact_sequence_ui <- renderUI", src)
  end <- grep("^  observe\\(\\{", src)
  end <- min(end[end > start])
  block <- paste(src[start:(end - 1L)], collapse = "\n")

  panel_calls <- regmatches(
    block,
    gregexpr("cr_impact_limits_panel\\(\\)", block)
  )[[1]]
  expect_length(panel_calls, 1L)
  expect_false(grepl("info_panel\\(", block))

  panel_start <- grep("cr_impact_limits_panel <- function", src)
  panel_copy <- paste(src[panel_start:(start - 1L)], collapse = "\n")
  expect_match(panel_copy, "balance table")
  expect_match(panel_copy, "HS GPA filter")
  expect_match(panel_copy, "reconstructed from term records")
  expect_false(grepl("registrar's cumulative fields", panel_copy, fixed = TRUE))
})

test_that("downstream instructor display pairs percentages with counts", {
  raw <- tibble::tibble(
    instructor_name = "Instructor One",
    n_total_in_x = 80L,
    n_right_censored = 5L,
    n_passed_y_before_x = 2L,
    n_passed_y_same_term = 1L,
    n_eligible_for_y = 73L,
    n_took_y = 45L,
    pct_took_y = 61.6,
    n_outcome_observed = 40L,
    n_outcome_unobserved = 5L,
    n_pass = 28L,
    pct_pass = 70,
    n_failed = 8L,
    pct_failed = 20,
    n_dropped = 4L,
    pct_dropped = 10,
    pct_dfw = 30
  )

  display <- prepare_downstream_outcomes_display(raw)
  expect_named(display, c(
    "Instructor", "Students in X", "Eligible for Y",
    "Continued to Y % (n)", "Classified outcomes % (n)",
    "Passed % (n)", "Failed % (n)", "Late drops % (n)", "DFW % (n)"
  ))
  expect_equal(display$`Classified outcomes % (n)`, 88.9)
  expect_false(any(c("n_right_censored", "n_passed_y_before_x",
                     "n_passed_y_same_term") %in% names(display)))

  counts <- attr(display, "pct_count_n")
  expect_equal(counts$`Continued to Y % (n)`, 45L)
  expect_equal(counts$`Classified outcomes % (n)`, 40L)
  expect_equal(counts$`DFW % (n)`, 12L)
})

# ── Downstream course options and the department rollup ──────────────────────
#
# Both impact tabs used to offer the whole catalogue behind a search box, so a
# reader had no way to tell a curricular follow-on from a coincidence. These
# pin the picker's data and the rollup arithmetic behind it.

# MC02 in designed_test_data.R is built for exactly this: MCMP 101 is the
# gateway, MCMP 101L is a co-requisite taken in the SAME term (so it is not a
# follow-on), MCMP 201 is the genuine later course, and OTHR 105 is a
# cross-department later course. MC_A1 takes MCMP 201 twice.
test_that("downstream options list only courses taken after X, same dept first", {
  o <- get_downstream_course_options(test_students_mc, "MCMP 101",
                                     list(min_n = 1L, data_edges = .impact_edges))
  expect_false("MCMP 101" %in% o$subject_course)      # never itself
  expect_false("MCMP 101L" %in% o$subject_course)     # same term, not "after"
  expect_true(all(c("MCMP 201", "OTHR 105") %in% o$subject_course))
  # Same-department entries sort first so the picker leads with curriculum.
  expect_true(o$same_dept[[1]])
  expect_equal(o$subject_course[[1]], "MCMP 201")
})

test_that("downstream options report share of X's students, counting each once", {
  o <- get_downstream_course_options(test_students_mc, "MCMP 101",
                                     list(min_n = 1L, data_edges = .impact_edges))
  s201 <- dplyr::filter(o, subject_course == "MCMP 201")
  # MC_A1, MC_A2, MC_A4 and MC_G1 reach it; MC_A3 goes to OTHR 105, MC_G2 stops.
  expect_equal(s201$n_students, 4L)
  expect_equal(s201$pct_of_x, round(100 * 4 / 6, 1))   # 6 students took MCMP 101
})

test_that("campus scopes the picker to the campuses the analysis will use", {
  # The picker must count within the same scope the analysis runs in, or its
  # numbers and the results disagree. Restricting to ABQ removes MC_G1 and
  # MC_G2 from the MCMP 101 cohort entirely.
  o <- get_downstream_course_options(test_students_mc, "MCMP 101",
                                     list(campus = "ABQ", min_n = 1L,
                                          data_edges = .impact_edges))
  s201 <- dplyr::filter(o, subject_course == "MCMP 201")
  expect_equal(s201$n_students, 3L)     # MC_A1, MC_A2, MC_A4 — not MC_G1
  expect_equal(s201$pct_of_x, 75)       # 3 of the 4 ABQ students
})

test_that("min_n drops thin follow-on courses from the picker", {
  o <- get_downstream_course_options(test_students_mc, "MCMP 101",
                                     list(min_n = 2L, data_edges = .impact_edges))
  expect_true("MCMP 201" %in% o$subject_course)   # 4 students
  expect_false("OTHR 105" %in% o$subject_course)  # 1 student
})

test_that("the picker uses the same graded and opportunity edges as the analysis", {
  future_y <- .mc_row(
    "MC_G2", 202180, "MCMP 201", "GA", "MCMP",
    grade = NA_character_, instructor = "MC_I2"
  )
  recent_x <- .mc_row(
    "MC_RECENT", 202110, "MCMP 101", "ABQ", "MCMP",
    grade = "A", instructor = "MC_I1"
  )
  students <- dplyr::bind_rows(test_students_mc, future_y, recent_x)

  o <- get_downstream_course_options(
    students, "MCMP 101",
    list(min_n = 1L, data_edges = .impact_edges)
  )
  s201 <- dplyr::filter(o, subject_course == "MCMP 201")
  expect_equal(s201$n_students, 4L) # future ungraded Y is not counted
  expect_equal(s201$pct_of_x, round(100 * 4 / 6, 1)) # recent X is right-censored
})

test_that("a co-requisite in the rollup set does not erase students", {
  # The trap, built into MC02: MCMP 101L is taken in the SAME term as MCMP 101
  # and belongs to the department's course set. Deduplicating each student to
  # their earliest enrolment *before* applying the after-X filter picks the lab,
  # the filter then discards it, and the student vanishes from the rollup
  # despite having taken MCMP 201 later.
  r <- suppressMessages(get_instructor_effect(
    test_students_mc, test_programs_mc, NULL,
    list(course_x = "MCMP 101",
         course_y = c("MCMP 101L", "MCMP 201"),   # lab sorts first
         min_n = 1L), data_edges = .impact_edges))

  expect_true(r$rollup)
  expect_equal(r$n_courses_y, 2L)
  # MC_A1, MC_A2, MC_A4 and MC_G1 all reached MCMP 201 after MCMP 101.
  expect_equal(sum(r$outcomes$n_took_y), 4L)
})

test_that("n_took_y counts students, not enrolments, when a course is repeated", {
  # MC_A1 takes MCMP 201 twice in MC02 — fails at 202080, passes at 202110.
  # They are one student. Counting enrolments instead double-weights them and
  # reports a pass rate over attempts while labelling it students.
  r <- suppressMessages(get_instructor_effect(
    test_students_mc, test_programs_mc, NULL,
    list(course_x = "MCMP 101", course_y = "MCMP 201", min_n = 1L),
    data_edges = .impact_edges))

  expect_equal(sum(r$outcomes$n_took_y), 4L)   # not 5
  expect_true(all(r$outcomes$n_took_y <= r$outcomes$n_total_in_x))
})

test_that("pct_took_y divides students by students when course X is repeated", {
  # Derive a duplicate X attempt from MC02 without changing the shared fixture's
  # pinned counts. The outcome rate should still read MC_I1 as 3 of 4 students
  # continuing to MCMP 201, not 3 of 5 enrollments.
  repeated_x <- test_students_mc %>%
    dplyr::filter(student_id == "MC_A1", subject_course == "MCMP 101") %>%
    dplyr::mutate(
      enrollment_id = paste0(enrollment_id, "-REPEAT"),
      section_id = paste0(section_id, "-REPEAT"),
      term = 202080L,
      final_grade = "B"
    )
  students <- dplyr::bind_rows(test_students_mc, repeated_x)

  r <- suppressMessages(get_instructor_effect(
    students, test_programs_mc, NULL,
    list(course_x = "MCMP 101", course_y = "MCMP 201", min_n = 1L),
    data_edges = .impact_edges))

  i1 <- dplyr::filter(r$outcomes, instructor_name == "MC_I1")
  expect_equal(i1$n_total_in_x, 4L)
  expect_equal(i1$n_took_y, 3L)
  expect_equal(i1$pct_took_y, 75)
})

test_that("ungraded future registrations are not downstream failures", {
  future_y <- .mc_row(
    "MC_G2", 202180, "MCMP 201", "GA", "MCMP",
    grade = NA_character_, instructor = "MC_I2"
  )
  students <- dplyr::bind_rows(test_students_mc, future_y)

  r <- suppressMessages(get_instructor_effect(
    students, test_programs_mc, NULL,
    list(course_x = "MCMP 101", course_y = "MCMP 201", min_n = 1L),
    data_edges = .impact_edges
  ))

  expect_equal(sum(r$outcomes$n_took_y), 4L)
  expect_equal(sum(r$outcomes$n_outcome_unobserved), 0L)
  expect_equal(sum(r$outcomes$n_failed), 1L)
  expect_equal(r$analysis_end_term, 202110L)
})

test_that("recent X cohorts without a complete follow-up term are right-censored", {
  recent_x <- .mc_row(
    "MC_RECENT", 202110, "MCMP 101", "ABQ", "MCMP",
    grade = "A", instructor = "MC_I1"
  )
  students <- dplyr::bind_rows(test_students_mc, recent_x)

  r <- suppressMessages(get_instructor_effect(
    students, test_programs_mc, NULL,
    list(course_x = "MCMP 101", course_y = "MCMP 201", min_n = 1L),
    data_edges = .impact_edges
  ))

  i1 <- dplyr::filter(r$outcomes, instructor_name == "MC_I1")
  expect_equal(i1$n_total_in_x, 5L)
  expect_equal(i1$n_right_censored, 1L)
  expect_equal(i1$n_eligible_for_y, 4L)
  expect_equal(i1$pct_took_y, 75)
})

test_that("strictly prior and same-term passes are not conflated", {
  prior_pass <- .mc_row(
    "MC_A3", 201980, "MCMP 201", "ABQ", "MCMP",
    grade = "A", instructor = "MC_I9"
  )
  same_term_pass <- .mc_row(
    "MC_A4", 202010, "MCMP 201", "ABQ", "MCMP",
    grade = "A", instructor = "MC_I9"
  )
  students <- dplyr::bind_rows(test_students_mc, prior_pass, same_term_pass)

  r <- suppressMessages(get_instructor_effect(
    students, test_programs_mc, NULL,
    list(course_x = "MCMP 101", course_y = "MCMP 201", min_n = 1L),
    data_edges = .impact_edges
  ))

  i1 <- dplyr::filter(r$outcomes, instructor_name == "MC_I1")
  expect_equal(i1$n_passed_y_before_x, 1L)
  expect_equal(i1$n_passed_y_same_term, 1L)
  expect_equal(i1$n_eligible_for_y, 3L)
  expect_equal(i1$n_took_y, 3L)
  expect_equal(i1$pct_took_y, 100)

  order_2020 <- dplyr::filter(r$order_audit_by_year, year == 2020L)
  expect_equal(order_2020$students_taking_x, 6L)
  expect_equal(order_2020$passed_y_before_x, 1L)
  expect_equal(order_2020$passed_y_same_term, 1L)
  expect_equal(order_2020$passed_y_before_or_same, 2L)
})

test_that("dropdown and course summary use the same continuation denominator", {
  opts <- get_downstream_course_options(
    test_students_mc, "MCMP 101",
    list(min_n = 1L, data_edges = .impact_edges)
  )
  audit <- get_downstream_pair_audit(
    test_students_mc, "MCMP 101", "MCMP 201",
    list(data_edges = .impact_edges)
  )
  picker <- dplyr::filter(opts, subject_course == "MCMP 201")

  expect_equal(picker$n_students, audit$summary$n_took_y)
  expect_equal(picker$pct_of_x, audit$summary$pct_took_y)
})

test_that("unclassifiable grades inside the graded window are unknown, not failures", {
  students <- test_students_mc %>%
    dplyr::mutate(
      final_grade = dplyr::if_else(
        student_id == "MC_A2" & subject_course == "MCMP 201",
        NA_character_, final_grade
      )
    )

  r <- suppressMessages(get_instructor_effect(
    students, test_programs_mc, NULL,
    list(course_x = "MCMP 101", course_y = "MCMP 201", min_n = 1L),
    data_edges = .impact_edges
  ))

  expect_equal(sum(r$outcomes$n_took_y), 4L)
  expect_equal(sum(r$outcomes$n_outcome_observed), 3L)
  expect_equal(sum(r$outcomes$n_outcome_unobserved), 1L)
  expect_equal(sum(r$outcomes$n_failed), 1L)
})
