# D2: the observational machinery.
#
#   R/branches/comparison.R  — build_comparison(), compute_balance()
#   R/cones/course-sequence-effect.R    — get_course_sequence_effect()
#
# These feed Course Dynamics > Downstream > Course Sequence. Their failure
# mode is a plausible-looking number, not an error, so these tests pin
# arithmetic, denominators, and who ends up in which group — not output shape.
# Downstream > Later Course, and the instructor balance check that also reads
# build_comparison(), are tested in test-later-course.R.
#
# NOTE: get_course_retention(), .compute_retention(), and .advance_n_terms()
# were removed from the former course-impact.R on 2026-08-01 — no callers, a name collision
# with cones/course-retention.R, and a duplicate of add_next_term_col().
# Course Dynamics > Retention is served by get_retention_trend() in that file,
# which has its own tests.

context("Course impact — observational machinery")

# ── build_comparison ─────────────────────────────────────────────────────────

# Covariates and ids come from MC02 (cedar_programs_mc / cedar_registrations_mc):
# six students, two campuses, varying GPA/Pell/first-gen, and a second program
# record for MC_A1 at 202110 so covariate-term selection has something to pick
# between.

test_that("groups are labelled from the id vectors, not from the data", {
  r <- suppressMessages(build_comparison(
    c("MC_A1", "MC_A2"), c("MC_A3", "MC_A4"), test_programs_mc, student_terms = test_student_terms_mc))
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
    c("MC_A1", "ghost"), c("MC_A3", "MC_A4"), test_programs_mc, student_terms = test_student_terms_mc))
  expect_equal(r$n_treatment, 1)
  expect_false("ghost" %in% r$groups$student_id)
})

test_that("a student in both groups is counted once, as treatment", {
  # pool_ids is documented as needing to exclude treatment_ids; nothing enforces
  # it, so pin the fallback rather than leave it undefined.
  r <- suppressMessages(build_comparison(
    c("MC_A1"), c("MC_A1", "MC_A3"), test_programs_mc, student_terms = test_student_terms_mc))
  expect_equal(nrow(r$groups), 2)
  expect_equal(r$n_treatment, 1)
  expect_equal(r$n_control, 1)
  expect_equal(r$groups$group[r$groups$student_id == "MC_A1"], "treatment")
})

test_that("empty treatment or control is an explicit error, not a silent empty result", {
  expect_error(suppressMessages(build_comparison(
    character(0), c("MC_A3"), test_programs_mc, student_terms = test_student_terms_mc)))
  expect_error(suppressMessages(build_comparison(
    c("MC_A1"), character(0), test_programs_mc, student_terms = test_student_terms_mc)))
})

test_that("covariates are taken at or before the covariate term, most recent first", {
  # MC_A1 has two program records in MC02: 202010 (standing "Good") and 202110
  # ("Probation"). Neither branch may simply take the latest row.
  r <- suppressMessages(build_comparison(
    c("MC_A1"), c("MC_A3"), test_programs_mc, student_terms = test_student_terms_mc))
  # Default is the entry term (202010), so the later Probation row must not win.
  expect_equal(r$groups$academic_standing[r$groups$student_id == "MC_A1"], "Good")

  # Asking for a term at or after the later record does pick it up.
  r2 <- suppressMessages(build_comparison(
    c("MC_A1"), c("MC_A3"), test_programs_mc, student_terms = test_student_terms_mc,
    covariate_terms = tibble::tibble(student_id = "MC_A1", covariate_term = 202110L)))
  expect_equal(r2$groups$academic_standing[r2$groups$student_id == "MC_A1"], "Probation")
})

test_that("the frozen cumulative fields never reach the comparison groups", {
  # This is the regression guard for the whole change. inst_gpa, inst_credits_*
  # and overall_credits_* are stamped as of the data pull and repeat a student's
  # final totals on every historical row, so matching on them means matching on
  # the outcome. They are present in the fixture and must be dropped anyway.
  r <- suppressMessages(build_comparison(
    c("MC_A1"), c("MC_A3"), test_programs_mc, student_terms = test_student_terms_mc))

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
    c("MC_A1"), c("MC_A3"), test_programs_mc, student_terms = test_student_terms_mc))

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
  expect_equal(row$smd, (p_t - p_c) / sqrt(p_bar * (1 - p_bar)))
  expect_equal(row$value_treatment, 100)
  expect_equal(row$value_control, 0)
  expect_identical(row$balance_band, "substantial")
  expect_true(row$flagged)                    # Legacy alias for substantial only.
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
  expect_equal(row$smd, (mu_t - mu_c) / sqrt((v_t + v_c) / 2))
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
  expect_true(all(b$smd_table$balance_band == "small"))
  expect_identical(b$overall_balance, "small")
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
  expect_identical(row$balance_band, "unavailable")
  expect_identical(b$overall_balance, "unavailable")
  expect_false(row$flagged)
})

test_that("SMD bands preserve both threshold boundaries", {
  smd <- c(NA_real_, 0, 0.0999, 0.10, -0.10, 0.25, -0.25, 0.2501, -0.2501)
  expect_identical(
    classify_smd_balance(smd),
    c("unavailable", "small", "small", "review", "review", "review",
      "review", "substantial", "substantial")
  )
  expect_identical(summarize_smd_balance(c("small", "review")), "review")
  expect_identical(summarize_smd_balance(c("small", "substantial")), "substantial")
  expect_identical(summarize_smd_balance(c("unavailable", "unavailable")), "unavailable")
})

test_that("Course Sequence definition v2 documents the measured-difference bands", {
  definition <- cedar_definition("course-sequence")
  copy <- paste(
    definition$summary,
    definition$limitations,
    collapse = " "
  )

  expect_identical(definition$version, "2.0.0")
  expect_match(copy, "below 0.10", fixed = TRUE)
  expect_match(copy, "0.10 through 0.25", fixed = TRUE)
  expect_match(copy, "above 0.25", fixed = TRUE)
  expect_match(copy, "do not", ignore.case = TRUE)
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

test_that("Course Dynamics groups both downstream questions under one top-level tab", {
  ui_src <- paste(readLines("../../ui.R", warn = FALSE), collapse = "\n")
  server_src <- paste(readLines("../../server.R", warn = FALSE), collapse = "\n")

  expect_match(
    ui_src,
    'nav_panel\\(\\s*"Downstream"[\\s\\S]{0,180}cr_impact_downstream_ui',
    perl = TRUE
  )
  expect_false(grepl('nav_panel\\(\\s*"Sequence Effect"', ui_src, perl = TRUE))
  expect_false(grepl('nav_panel\\(\\s*"Downstream Success"', ui_src, perl = TRUE))

  combined_start <- regexpr(
    "output\\$cr_impact_downstream_ui <- renderUI",
    server_src,
    perl = TRUE
  )
  expect_gt(combined_start, 0L)
  combined_copy <- substr(server_src, combined_start, combined_start + 2200L)
  expect_match(combined_copy, 'nav_panel\\(\\s*"Later Course"', perl = TRUE)
  expect_match(combined_copy, 'nav_panel\\(\\s*"Course Sequence"', perl = TRUE)
  expect_match(combined_copy, 'laterCourseUI("cr_later")', fixed = TRUE)
  expect_match(combined_copy, "cr_impact_sequence_ui", fixed = TRUE)
  # Instructor Patterns is Later Course's gated breakdown now, not a tab.
  expect_false(grepl("Instructor Patterns", combined_copy, fixed = TRUE))
})

test_that("sequence effect uses one canonical Y outcome and scopes both courses", {
  fixture <- .sequence_audit_fixture
  result <- suppressMessages(get_course_sequence_effect(
    fixture$students,
    keyed_attempts(fixture$students, .impact_edges),
    fixture$programs,
    opt = list(
      course_x = "SEQ 101", course_y = "SEQ 201", campus = "ABQ", min_n = 1L
    ),
    data_edges = .impact_edges
  ))

  expect_equal(result$n_treatment, 2L)
  expect_equal(result$n_control, 3L)
  expect_equal(result$n_took_x_before_y, 2L)
  expect_equal(result$n_took_y_without_x, 3L)
  expect_equal(sum(result$outcomes$n), 5L)

  treatment_dfw <- result$outcomes %>%
    dplyr::filter(group == "treatment", outcome == "dfw") %>%
    dplyr::pull(n)
  expect_equal(treatment_dfw, 2L)
  expect_false(any(result$outcomes$group == "treatment" &
                     result$outcomes$outcome == "pass"))
  expect_match(result$y_attempt_rule, "earliest classifiable")
})

test_that("an active HS GPA band excludes and reports missing GPAs", {
  fixture <- .sequence_audit_fixture
  applicants <- tibble::tibble(
    student_id = fixture$ids,
    high_school_cum_gpa = c(3.0, NA, 3.2, 2.8, NA)
  )

  result <- suppressMessages(get_course_sequence_effect(
    fixture$students,
    keyed_attempts(fixture$students, .impact_edges),
    fixture$programs,
    applicants = applicants,
    opt = list(
      course_x = "SEQ 101", course_y = "SEQ 201", campus = "ABQ", min_n = 1L,
      hs_gpa_min = 2.5, hs_gpa_max = 3.5
    ),
    data_edges = .impact_edges
  ))

  expect_equal(result$n_missing_hs_gpa_excluded, 2L)
  expect_equal(result$n_treatment, 1L)
  expect_equal(result$n_control, 2L)
  expect_equal(sum(result$outcomes$n), 3L)
})

test_that("the control group splits into attempted-not-passed and never-sat X", {
  result <- .run_sequence_bands(.sequence_band_fixture, course_y = "SEQ 201")
  expect_equal(result$n_treatment, 2L)
  expect_equal(result$n_control, 4L)
  # Every Y attempt is in Fall 2020: one term, both groups, rates over min_n = 1.
  expect_equal(result$by_term$term, c(202080L, 202080L))
  expect_equal(result$by_term$group, c("treatment", "control"))
  expect_equal(result$by_term$n, c(2L, 4L))
  expect_equal(result$by_term$dfw_pct, c(100, 25))
  split <- result$control_split
  expect_equal(split$prior_x, c("attempted_not_passed", "no_prior_attempt"))
  expect_equal(split$n, c(1L, 3L))
  expect_equal(split$n_dfw, c(1L, 0L))
  expect_equal(split$dfw_pct, c(100, 0))
})

test_that("the sequence over time is one row per term, never per calendar year", {
  # SEQ_C2's SEQ 201 attempt moves from Fall 2020 to Spring 2020: the same
  # calendar year as everyone else's, another term type. By year the control
  # group would be 4 students at 25%; by term it is 1 in Spring (passed) and
  # 3 in Fall (SEQ_C1 and SEQ_XC passed, SEQ_F1 did not: 33.3%).
  fixture <- .sequence_band_fixture
  moved <- fixture$students$student_id == "SEQ_C2" & fixture$students$subject_course == "SEQ 201"
  expect_equal(sum(moved), 1L)
  fixture$students$term[moved] <- 202010L
  result <- .run_sequence_bands(fixture, course_y = "SEQ 201")
  by_term <- result$by_term
  expect_equal(by_term$term, c(202010L, 202080L, 202080L))
  expect_equal(by_term$term_type, c("spring", "fall", "fall"))
  expect_equal(by_term$group, c("control", "treatment", "control"))
  expect_equal(by_term$n, c(1L, 2L, 3L))
  expect_equal(round(by_term$dfw_pct, 1), c(0, 100, 33.3))
  expect_equal(result$main_term_type, "fall")
  expect_equal(result$n_min_term, 1L)
})

test_that("outcomes are compared inside HS GPA bands and standardized to the treatment mix", {
  fixture <- .sequence_band_fixture
  result <- .run_sequence_bands(fixture, course_y = "SEQ 201", min_band_n = 1L)
  bands <- result$by_hs_gpa_band
  expect_equal(as.character(bands$band), c("2.76 to 3.25", "2.76 to 3.25", "not on file", "not on file"))
  expect_equal(bands$group, c("treatment", "control", "treatment", "control"))
  expect_equal(bands$n, c(1L, 3L, 1L, 1L))
  expect_equal(bands$n_dfw, c(1L, 1L, 1L, 0L))
  std <- result$standardized
  expect_equal(std$n_treatment_covered, 2L)
  expect_equal(std$n_treatment_left_out, 0L)
  expect_equal(std$actual_dfw_pct, 100)
  # (1 x 1/3 + 1 x 0/1) / 2
  expect_equal(std$expected_dfw_pct, 100 / 6)

  # A band whose control group is under the guard supplies no rate, and its
  # treatment students leave both sides.
  guarded <- .run_sequence_bands(fixture, course_y = "SEQ 201", min_band_n = 2L)$standardized
  expect_equal(guarded$bands_used, "2.76 to 3.25")
  expect_equal(guarded$n_treatment_covered, 1L)
  expect_equal(guarded$n_treatment_left_out, 1L)
  expect_equal(guarded$expected_dfw_pct, 100 / 3)

  # No applicants table: no bands, and no sentence about them.
  no_app <- fixture; no_app["applicants"] <- list(NULL)
  bare <- .run_sequence_bands(no_app, course_y = "SEQ 201")
  expect_null(bare$by_hs_gpa_band)
  expect_null(bare$standardized)

  testthat::local_edition(3)
  expect_snapshot(cat(course_sequence_headline(result), sep = "\n"))
})

test_that("an ACT window keeps both groups inside it and reports the students with no score", {
  result <- .run_sequence_bands(.sequence_band_fixture, course_y = "SEQ 201", act_min = 18)
  expect_equal(result$n_missing_act_excluded, 2L)
  expect_equal(result$n_treatment, 1L)
  expect_equal(result$n_control, 2L)
  no_app <- .sequence_band_fixture; no_app["applicants"] <- list(NULL)
  expect_error(.run_sequence_bands(no_app, course_y = "SEQ 201", act_min = 18), "ACT window")
})

test_that("several later-course codes are one course: each student once, at the earliest attempt", {
  fixture <- .sequence_band_fixture
  family <- .run_sequence_bands(fixture, course_y = c("SEQ 201", "SEQ 201X"))
  expect_equal(family$course_y, c("SEQ 201", "SEQ 201X"))
  expect_equal(family$n_treatment, 3L)
  expect_equal(family$n_control, 4L)
  treated <- family$outcomes %>% dplyr::filter(group == "treatment")
  expect_equal(treated$outcome, c("dfw", "pass"))
  expect_equal(treated$n, c(2L, 1L))
  testthat::local_edition(3)
  expect_snapshot(cat(course_sequence_headline(family)[1], sep = "\n"))
})

test_that("every table that names an instructor beside outcomes waits for the instructor gate", {
  server <- paste(readLines("../../server.R", warn = FALSE), collapse = "\n")
  # Retention: the breakout is honoured only behind the gate.
  expect_true(grepl("isTRUE(input$cr_ret_by_instructor) && isTRUE(dfw_authenticated())", server, fixed = TRUE))
  # The modules that name instructors, or show the rates of a topic one
  # instructor taught (Topics), are handed the shared flag.
  expect_equal(lengths(regmatches(server, gregexpr("instructor_access = dfw_authenticated", server, fixed = TRUE))), 4L)
  # Later Course: the breakdown and its balance check render only while open.
  later <- paste(readLines("../../R/modules/later-course.R", warn = FALSE), collapse = "\n")
  expect_true(grepl("if (access) .later_course_instructor_reactable(later_course_instructor_table(r), r)\n      else instructorGateUI(ns(\"instructor_gate\"))",
                    later, fixed = TRUE))
  expect_true(grepl("if (access) .later_course_balance_section(r)", later, fixed = TRUE))
  expect_true(grepl("later_course_view(r, ns, isTRUE(instructor_access()))", later, fixed = TRUE))
  cohort <- paste(readLines("../../R/modules/course-cohort.R", warn = FALSE), collapse = "\n")
  expect_true(grepl("req(s, nrow(s$instructors) > 0L, isTRUE(instructor_access()))", cohort, fixed = TRUE))
  pathways <- paste(readLines("../../R/modules/pathways.R", warn = FALSE), collapse = "\n")
  expect_true(grepl("output$ge_instructor_table <- reactable::renderReactable({\n      req(isTRUE(instructor_access()))",
                    pathways, fixed = TRUE))
})

test_that("cross-department follow-ons are not treated as invalid sequences", {
  src <- paste(readLines("../../server.R", warn = FALSE), collapse = "\n")

  expect_false(grepl("probably reflects who enrols", src, fixed = TRUE))
  expect_false(grepl("cr_impact_seq_pair_note", src, fixed = TRUE))
  expect_false(grepl("cr_impact_inst_pair_note", src, fixed = TRUE))
  expect_match(src, "Department ownership and continuation share do not establish")
})

test_that("balance values preserve meaningful continuous precision", {
  ui_helpers <- new.env(parent = globalenv())
  sys.source("../../R/modules/ui-helpers.R", envir = ui_helpers)
  values <- ui_helpers$cedar_format_balance_value(
    c(3.234, 3, 57.04, NA_real_),
    c("continuous", "continuous", "binary", "continuous")
  )

  expect_equal(values, c("3.23", "3.00", "57.0", "—"))
})

# ── course_sequence_headline ────────────────────────────────────────────────
#
# The page's first sentence over the cone's payload (R/features/course-report.R).
# MC02, SPAN 101 -> SPAN 201 on ABQ: MC_A1, MC_A2 and MC_A4 passed SPAN 101 in
# 202010 and took SPAN 201 in 202080 (MC_A1 F, the others pass); MC_G1 passed
# SPAN 101 on GA, out of the ABQ scope, so their ABQ SPAN 201 (A) is control.
# Treatment DFW 1 of 3; control 0 of 1.

test_that("course_sequence_headline says the two rates, their counts and the balance verdict", {
  testthat::local_edition(3)
  result <- suppressMessages(get_course_sequence_effect(
    test_students_mc, .impact_attempts, test_programs_mc, NULL,
    opt = list(course_x = "SPAN 101", course_y = "SPAN 201", campus = "ABQ", min_n = 1L),
    student_terms = test_student_terms_mc, data_edges = .impact_edges
  ))
  expect_equal(result$n_treatment, 3L)
  expect_equal(result$n_control, 1L)
  headline <- course_sequence_headline(result)
  expect_length(headline, 2L)
  expect_snapshot(cat(headline, sep = "\n"))

  # The verdict names the most imbalanced covariate and counts the flagged ones.
  smd <- result$balance$smd_table
  n_flagged <- sum(smd$balance_band %in% "substantial")
  if (n_flagged > 0) expect_match(headline[2], paste0("on ", n_flagged, " of "))
  else expect_match(headline[2], "did not differ substantially")

  # Rounding is the display's: the sentence is built from the counts.
  expect_match(headline[1], "33.3% of the time (1 of 3)", fixed = TRUE)
  expect_match(headline[1], "0.0% (0 of 1)", fixed = TRUE)
  expect_match(headline[1], "a higher rate, by 33.3 points", fixed = TRUE)
})

test_that("course_sequence_headline stops on a payload without its tables", {
  expect_error(course_sequence_headline(list(course_x = "A", course_y = "B")), "lacks")
})
