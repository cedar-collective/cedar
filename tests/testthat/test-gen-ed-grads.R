# Tests for R/cones/gen-ed-grads.R and get_gen_ed_grad_profile()
# (R/reports/gen-ed.R), plus the get_course_timing() options they depend on.
#
# Fixture: GG01 in fixtures/designed_test_data.R. Read the block comment there
# first — every expected number below is stated in it, and the fixture is built
# around the cohort's EXCLUSIONS rather than its happy path.

source(file.path(dirname(getwd()), "testthat", "fixtures", "designed_test_data.R"))

context("Gen Ed Among Department Graduates")


gg_opt <- function(...) utils::modifyList(list(dept_code = "GG"), list(...))


# =============================================================================
# get_gen_ed_grad_cohort() — the sampling rule
# =============================================================================

test_that("cohort keeps only awarded graduates with a complete UNM record", {
  cohort <- get_gen_ed_grad_cohort(cedar_students_gg, cedar_degrees_gg, gg_opt())

  expect_equal(nrow(cohort), 3)
  expect_setequal(cohort$student_id, c("GG_IN1", "GG_IN2", "GG_IN3"))
  expect_true(all(c("student_id", "population_label", "grad_term",
                    "first_unm_term") %in% names(cohort)))
})

test_that("cohort_meta accounts for every excluded graduate", {
  cohort <- get_gen_ed_grad_cohort(cedar_students_gg, cedar_degrees_gg, gg_opt())
  m <- attr(cohort, "cohort_meta")

  # 5 awarded GG degrees. GG_PEND (pending) and GG_OTHER (different department)
  # are filtered before the count and are not "excluded graduates".
  expect_equal(m$n_awarded, 5)
  expect_equal(m$n_no_records, 1)      # GG_NOREC
  expect_equal(m$n_left_truncated, 1)  # GG_TRUNC, first enrolled in the first data term
  expect_equal(m$n_cohort, 3)
  expect_equal(m$min_data_term, 201980)
  expect_equal(m$dept_code, "GG")
  # The exclusion paths plus the cohort must exhaust the awarded count, or the
  # strip on screen silently loses graduates.
  expect_equal(m$n_cohort + m$n_no_records + m$n_left_truncated, m$n_awarded)
})

test_that("cohort excludes pending degrees", {
  cohort <- get_gen_ed_grad_cohort(cedar_students_gg, cedar_degrees_gg, gg_opt())
  expect_false("GG_PEND" %in% cohort$student_id)
})

test_that("cohort excludes graduates of other departments", {
  cohort <- get_gen_ed_grad_cohort(cedar_students_gg, cedar_degrees_gg, gg_opt())
  expect_false("GG_OTHER" %in% cohort$student_id)
})

test_that("cohort takes the latest degree term for a student with several", {
  degrees_two <- dplyr::bind_rows(
    cedar_degrees_gg,
    dplyr::filter(cedar_degrees_gg, student_id == "GG_IN1") %>%
      dplyr::mutate(degree_id = "GGDEG1b", term = 202180L)
  )
  cohort <- get_gen_ed_grad_cohort(cedar_students_gg, degrees_two, gg_opt())

  expect_equal(sum(cohort$student_id == "GG_IN1"), 1)
  expect_equal(cohort$grad_term[cohort$student_id == "GG_IN1"], 202410)
})

test_that("cohort is empty, not an error, for a department with no graduates", {
  cohort <- get_gen_ed_grad_cohort(cedar_students_gg, cedar_degrees_gg,
                                   gg_opt(dept_code = "NOPE"))
  expect_equal(nrow(cohort), 0)
  expect_equal(attr(cohort, "cohort_meta")$n_cohort, 0)
})

test_that("cohort requires a dept_code", {
  expect_error(
    get_gen_ed_grad_cohort(cedar_students_gg, cedar_degrees_gg, list()),
    "dept_code is required"
  )
})

test_that("cohort fails loudly on a degrees table missing required columns", {
  expect_error(
    get_gen_ed_grad_cohort(cedar_students_gg,
                           dplyr::select(cedar_degrees_gg, -graduation_status),
                           gg_opt()),
    "missing required column"
  )
})


# =============================================================================
# get_gen_ed_grad_uptake() — who took what
# =============================================================================

gg_uptake <- function(...) {
  cohort <- get_gen_ed_grad_cohort(cedar_students_gg, cedar_degrees_gg, gg_opt())
  get_gen_ed_grad_uptake(cedar_students_gg, cohort, gen_ed_course_lookup(),
                         opt = utils::modifyList(
                           list(campus = "ABQ", dept_code = "GG", min_n = 1L),
                           list(...)))
}

test_that("uptake counts each course once per student despite retakes", {
  u <- gg_uptake()
  engl <- dplyr::filter(u$by_course, subject_course == "ENGL 1120")

  # GG_IN1 took ENGL 1120 twice (202080 and 202110) and GG_IN2 once.
  expect_equal(engl$n_students, 2)
  expect_equal(engl$pct_cohort, 66.7)
})

test_that("uptake excludes non-gen-ed courses", {
  u <- gg_uptake()
  expect_false("GG 300" %in% u$by_course$subject_course)
})

test_that("uptake excludes coursework taken after graduation", {
  # GG_IN2 took HIST 1160 at 202480, after the 202410 degree. Only GG_IN1's
  # 202180 attempt should count.
  u <- gg_uptake()
  hist <- dplyr::filter(u$by_course, subject_course == "HIST 1160")

  expect_equal(hist$n_students, 1)
})

test_that("uptake excludes students who are not in the cohort", {
  # GG_TRUNC, GG_PEND and GG_OTHER all took ENGL 1120 in the fixture. If any
  # leaked in, n_students would exceed 2.
  u <- gg_uptake()
  expect_equal(max(u$by_course$n_students), 2)
})

test_that("uptake flags courses taught by the graduates' own unit", {
  u <- gg_uptake()
  # Every gen ed course in the fixture is taught by ENGL, MATH or HIST — none by
  # GG itself — so the flag must be FALSE everywhere rather than NA or missing.
  expect_true(all(!u$by_course$is_dept_course))
  expect_type(u$by_course$is_dept_course, "logical")
})

test_that("uptake averages divide by the whole cohort, not just gen ed takers", {
  u <- gg_uptake()

  # GG_IN1 = 3 courses, GG_IN2 = 2, GG_IN3 = 0. Mean over 3 graduates = 1.67.
  # Dividing by the 2 takers instead would give 2.5.
  expect_equal(u$summary$n_cohort, 3L)
  expect_equal(u$summary$n_with_any, 2L)
  expect_equal(u$summary$mean_courses, 1.67)
  expect_equal(u$summary$median_courses, 2)
})

test_that("uptake counts distinct gen ed areas per student", {
  u <- gg_uptake()
  # GG_IN1 spans areas 1, 2, 5; GG_IN2 spans 1, 2; GG_IN3 none. (3+2+0)/3.
  expect_equal(u$summary$mean_areas, 1.67)
})

test_that("uptake min_n drops courses below the threshold", {
  u <- gg_uptake(min_n = 2L)
  expect_false("HIST 1160" %in% u$by_course$subject_course)
  expect_true("ENGL 1120" %in% u$by_course$subject_course)
})

test_that("uptake returns typed empty tables for an empty cohort", {
  empty <- get_gen_ed_grad_cohort(cedar_students_gg, cedar_degrees_gg,
                                  gg_opt(dept_code = "NOPE"))
  u <- get_gen_ed_grad_uptake(cedar_students_gg, empty, gen_ed_course_lookup(),
                              opt = list(campus = "ABQ"))

  expect_equal(nrow(u$by_course), 0)
  expect_equal(u$summary$n_cohort, 0L)
  expect_equal(u$summary$n_with_any, 0L)
  expect_true(is.character(u$by_course$subject_course))
})

test_that("uptake fails loudly on a cohort that did not come from the cohort builder", {
  expect_error(
    get_gen_ed_grad_uptake(cedar_students_gg,
                           tibble::tibble(student_id = "GG_IN1"),
                           gen_ed_course_lookup()),
    "missing required column"
  )
})


# =============================================================================
# get_course_timing() — the new options this feature relies on
# =============================================================================

gg_population <- function() {
  get_gen_ed_grad_cohort(cedar_students_gg, cedar_degrees_gg, gg_opt()) %>%
    dplyr::select(student_id, population_label)
}

test_that("unm_credit_band places courses by credits entering the term", {
  timing <- suppressMessages(get_course_timing(
    cedar_students_gg, gg_population(),
    opt = list(x_axis = "unm_credit_band", min_n = 1L, campus = "ABQ",
               group_campus = FALSE),
    term_credits = cedar_student_term_credits_gg
  ))

  # GG_IN1: ENGL 1120 entering 0 credits (band 1), MATH 1350 entering 45
  # (band 2), HIST 1160 entering 95 (band 4). Using the cumulative total
  # through the term instead would push each one band later.
  band_of <- function(course, sid_band) {
    dplyr::filter(timing, subject_course == course, relative_term == sid_band)
  }
  expect_equal(nrow(band_of("ENGL 1120", 1L)), 1)
  expect_equal(nrow(band_of("MATH 1350", 2L)), 1)
  expect_equal(nrow(band_of("HIST 1160", 4L)), 1)
  expect_equal(attr(timing, "x_axis"), "unm_credit_band")
})

test_that("unm_credit_band fails loudly without term_credits", {
  expect_error(
    suppressMessages(get_course_timing(
      cedar_students_gg, gg_population(),
      opt = list(x_axis = "unm_credit_band", min_n = 1L, campus = "ABQ")
    )),
    "requires cedar_student_term_credits"
  )
})

test_that("unm_credit_band fails loudly on a malformed term_credits table", {
  expect_error(
    suppressMessages(get_course_timing(
      cedar_students_gg, gg_population(),
      opt = list(x_axis = "unm_credit_band", min_n = 1L, campus = "ABQ"),
      term_credits = dplyr::select(cedar_student_term_credits_gg,
                                   -cumulative_completed_unm_credits)
    )),
    "missing required column"
  )
})

test_that("opt$subject_course restricts to an explicit course list", {
  timing <- suppressMessages(get_course_timing(
    cedar_students_gg, gg_population(),
    opt = list(x_axis = "unm_credit_band", min_n = 1L, campus = "ABQ",
               group_campus = FALSE,
               subject_course = c("ENGL 1120", "MATH 1350")),
    term_credits = cedar_student_term_credits_gg
  ))

  expect_setequal(unique(timing$subject_course), c("ENGL 1120", "MATH 1350"))
})

test_that("opt$subject_course leaves n_eligible population-wide", {
  # The denominator must count everyone who reached the band, not just students
  # who took a course on the filter list — same contract as opt$subject_code.
  all_courses <- suppressMessages(get_course_timing(
    cedar_students_gg, gg_population(),
    opt = list(x_axis = "unm_credit_band", min_n = 1L, campus = "ABQ",
               group_campus = FALSE),
    term_credits = cedar_student_term_credits_gg
  ))
  filtered <- suppressMessages(get_course_timing(
    cedar_students_gg, gg_population(),
    opt = list(x_axis = "unm_credit_band", min_n = 1L, campus = "ABQ",
               group_campus = FALSE, subject_course = "MATH 1350"),
    term_credits = cedar_student_term_credits_gg
  ))

  band2 <- function(d) unique(d$n_eligible[d$relative_term == 2L])
  expect_equal(band2(filtered), band2(all_courses))
})

test_that("group_campus = FALSE counts a student once across delivery campuses", {
  # Same student, same course, same band, two campuses. Grouped by campus this
  # is two rows of 1; as a trajectory it is one student who took the course.
  students_split <- dplyr::bind_rows(
    cedar_students_gg,
    .gg_row("GG_IN1", 202080, "MATH 1350", "MATH", campus = "EA")
  )
  credits_split <- cedar_student_term_credits_gg

  grouped <- suppressMessages(get_course_timing(
    students_split, gg_population(),
    opt = list(x_axis = "unm_credit_band", min_n = 1L, campus = c("ABQ", "EA"),
               subject_course = "MATH 1350"),
    term_credits = credits_split
  ))
  ungrouped <- suppressMessages(get_course_timing(
    students_split, gg_population(),
    opt = list(x_axis = "unm_credit_band", min_n = 1L, campus = c("ABQ", "EA"),
               group_campus = FALSE, subject_course = "MATH 1350"),
    term_credits = credits_split
  ))

  expect_true("campus" %in% names(grouped))
  expect_false("campus" %in% names(ungrouped))
  # Band 1 holds GG_IN1's EA attempt only (their ABQ MATH 1350 is at band 2).
  expect_equal(sum(ungrouped$n_students[ungrouped$relative_term == 1L]), 1)
})


# =============================================================================
# get_gen_ed_grad_profile() — the assembled payload
# =============================================================================

test_that("profile returns cohort meta, timing and uptake in one payload", {
  res <- suppressMessages(get_gen_ed_grad_profile(
    cedar_students_gg, cedar_degrees_gg, cedar_student_term_credits_gg,
    opt = list(dept_code = "GG", campus = "ABQ", min_n = 1L, min_band_n = 1L,
               x_axis = "unm_credit_band")
  ))

  expect_equal(res$n_cohort, 3)
  expect_equal(res$cohort_meta$n_awarded, 5)
  expect_equal(res$summary$mean_courses, 1.67)
  expect_gt(nrow(res$timing), 0)
  expect_equal(attr(res$timing, "x_axis"), "unm_credit_band")
})

test_that("profile shows the same courses in the heatmap and the table", {
  # The two sit next to each other on the page; a course in one and not the
  # other reads as the data disagreeing with itself.
  res <- suppressMessages(get_gen_ed_grad_profile(
    cedar_students_gg, cedar_degrees_gg, cedar_student_term_credits_gg,
    opt = list(dept_code = "GG", campus = "ABQ", min_n = 1L, min_band_n = 1L,
               x_axis = "unm_credit_band")
  ))

  expect_setequal(unique(res$timing$subject_course), res$by_course$subject_course)
})

test_that("profile min_n filters both surfaces on distinct student counts", {
  res <- suppressMessages(get_gen_ed_grad_profile(
    cedar_students_gg, cedar_degrees_gg, cedar_student_term_credits_gg,
    opt = list(dept_code = "GG", campus = "ABQ", min_n = 2L, min_band_n = 1L,
               x_axis = "unm_credit_band")
  ))

  # HIST 1160 has one distinct student and must be gone from both, even though
  # get_course_timing()'s own min_n sums across cells.
  expect_false("HIST 1160" %in% res$by_course$subject_course)
  expect_false("HIST 1160" %in% res$timing$subject_course)
})

test_that("profile excludes post-graduation coursework from timing", {
  res <- suppressMessages(get_gen_ed_grad_profile(
    cedar_students_gg, cedar_degrees_gg, cedar_student_term_credits_gg,
    opt = list(dept_code = "GG", campus = "ABQ", min_n = 1L, min_band_n = 1L,
               x_axis = "unm_credit_band")
  ))

  # GG_IN2's 202480 HIST 1160 sits at band 3 in the credit fixture. Only
  # GG_IN1's band-4 attempt survives the graduation-term cap.
  hist_bands <- res$timing$relative_term[res$timing$subject_course == "HIST 1160"]
  expect_equal(hist_bands, 4L)
})

test_that("profile returns empty tables, not an error, when no cohort exists", {
  res <- suppressMessages(get_gen_ed_grad_profile(
    cedar_students_gg, cedar_degrees_gg, cedar_student_term_credits_gg,
    opt = list(dept_code = "NOPE", campus = "ABQ", min_band_n = 1L)
  ))

  expect_equal(res$n_cohort, 0L)
  expect_equal(nrow(res$timing), 0)
  expect_equal(nrow(res$by_course), 0)
  expect_equal(res$summary$n_cohort, 0L)
})

test_that("profile timing plots without error", {
  res <- suppressMessages(get_gen_ed_grad_profile(
    cedar_students_gg, cedar_degrees_gg, cedar_student_term_credits_gg,
    opt = list(dept_code = "GG", campus = "ABQ", min_n = 1L, min_band_n = 1L,
               x_axis = "unm_credit_band")
  ))
  p <- suppressMessages(plot_curriculum_map(res$timing,
                                            opt = list(min_pct = 0, top_n = 40L)))

  expect_s3_class(p, "ggplot")
})


# =============================================================================
# Own-unit scope — the same three views, restricted to the unit's own Gen Ed
# =============================================================================
#
# GG01 has no Gen Ed taught by GG itself (every gen ed course in the fixture is
# ENGL, MATH or HIST), so the fixture is extended per-test rather than globally:
# the "no own Gen Ed at all" case is a real state the page has to render, and
# keeping it as the fixture default means it is always covered.

# GG_IN1 and GG_IN2 both take a GG-taught gen ed course; GG_IN3 still takes none.
# Uses HIST 1160's slot in area 5 via a GG-owned section of a real catalog course
# so gen_ed_course_lookup() still matches it.
gg_students_own <- function() {
  dplyr::bind_rows(
    cedar_students_gg,
    .gg_row("GG_IN1", 202110, "PHIL 1115", "GG"),
    .gg_row("GG_IN2", 202110, "PHIL 1115", "GG")
  )
}

gg_credits_own <- function() {
  dplyr::bind_rows(
    cedar_student_term_credits_gg,
    tibble::tibble(student_id = "GG_IN2", term = 202110L,
                   completed_unm_credits = 3,
                   cumulative_completed_unm_credits = 3)
  )
}

gg_profile_own <- function(min_n = 1L) {
  suppressMessages(get_gen_ed_grad_profile(
    gg_students_own(), cedar_degrees_gg, gg_credits_own(),
    opt = list(dept_code = "GG", campus = "ABQ", min_n = min_n, min_band_n = 1L,
               x_axis = "unm_credit_band")
  ))
}

test_that("own-unit tables keep only courses taught by the graduates' unit", {
  res <- gg_profile_own()

  expect_equal(res$by_course_dept$subject_course, "PHIL 1115")
  expect_true(all(res$by_course_dept$department == "GG"))
  # And the all-Gen-Ed table still has everything, including the GG course.
  expect_true(all(c("ENGL 1120", "MATH 1350", "PHIL 1115") %in%
                    res$by_course$subject_course))
})

test_that("own-unit timing is exactly the all-Gen-Ed timing narrowed by course", {
  # This is the claim that lets the report cut both scopes from one
  # get_course_timing() run instead of running it twice. If it ever stops
  # holding, the two heatmaps stop being comparable cell for cell.
  res <- gg_profile_own()
  narrowed <- res$timing %>%
    dplyr::filter(subject_course %in% res$by_course_dept$subject_course) %>%
    dplyr::arrange(subject_course, relative_term)

  expect_equal(dplyr::arrange(res$timing_dept, subject_course, relative_term),
               narrowed)
})

test_that("own-unit timing keeps the cohort-wide denominator", {
  # The share must stay out of every graduate who reached the band, not just
  # those who took something from this unit — otherwise the two heatmaps are on
  # different denominators and reading them side by side is misleading.
  res <- gg_profile_own()
  band1 <- dplyr::filter(res$timing_dept, relative_term == 1L)
  all1  <- dplyr::filter(res$timing, relative_term == 1L)

  expect_equal(unique(band1$n_eligible), unique(all1$n_eligible))
  expect_equal(unique(band1$n_eligible), 3L)
})

test_that("own-unit timing carries the same axis attribute as the main timing", {
  res <- gg_profile_own()
  expect_equal(attr(res$timing_dept, "x_axis"), "unm_credit_band")
})

test_that("summary_dept counts only own-unit courses and divides by the cohort", {
  res <- gg_profile_own()
  sd <- res$summary_dept

  # GG_IN1 and GG_IN2 took 1 GG course each; GG_IN3 took none. Mean over 3.
  expect_equal(sd$n_with_any, 2L)
  expect_equal(sd$mean_courses, round(2 / 3, 2))
  expect_equal(sd$median_courses, 1)
})

test_that("dept_share_pct is own-unit course-takings over all course-takings", {
  res <- gg_profile_own()
  # GG_IN1: 4 gen ed courses (ENGL 1120, MATH 1350, HIST 1160, PHIL 1115), 1 GG.
  # GG_IN2: 3 (ENGL 1120, MATH 1350, PHIL 1115), 1 GG.  GG_IN3: 0.
  # 2 of 7 course-takings.
  expect_equal(res$summary_dept$dept_share_pct, round(100 * 2 / 7, 1))
})

test_that("own-unit average never exceeds the all-Gen-Ed average", {
  res <- gg_profile_own()
  expect_lte(res$summary_dept$mean_courses, res$summary$mean_courses)
  expect_lte(res$summary_dept$n_with_any, res$summary$n_with_any)
})

test_that("a unit that teaches no Gen Ed gets empty own-unit tables, not an error", {
  # The GG01 fixture as committed has no GG-taught gen ed at all.
  res <- suppressMessages(get_gen_ed_grad_profile(
    cedar_students_gg, cedar_degrees_gg, cedar_student_term_credits_gg,
    opt = list(dept_code = "GG", campus = "ABQ", min_n = 1L, min_band_n = 1L,
               x_axis = "unm_credit_band")
  ))

  expect_equal(nrow(res$by_course_dept), 0)
  expect_equal(nrow(res$timing_dept), 0)
  expect_equal(res$summary_dept$n_with_any, 0L)
  expect_equal(res$summary_dept$mean_courses, 0)
  expect_equal(res$summary_dept$dept_share_pct, 0)
  # The all-Gen-Ed scope is unaffected.
  expect_gt(nrow(res$by_course), 0)
})

test_that("own-unit min_n filters on distinct students like the main scope", {
  res <- gg_profile_own(min_n = 3L)
  # PHIL 1115 has 2 GG graduates, below a threshold of 3.
  expect_equal(nrow(res$by_course_dept), 0)
  expect_equal(nrow(res$timing_dept), 0)
})

test_that("uptake exposes per-student own-unit counts", {
  cohort <- get_gen_ed_grad_cohort(gg_students_own(), cedar_degrees_gg, gg_opt())
  u <- get_gen_ed_grad_uptake(gg_students_own(), cohort, gen_ed_course_lookup(),
                              opt = list(campus = "ABQ", dept_code = "GG", min_n = 1L))

  expect_true("n_dept_courses" %in% names(u$per_student))
  expect_equal(u$per_student$n_dept_courses[u$per_student$student_id == "GG_IN1"], 1L)
  expect_true(all(u$per_student$n_dept_courses <= u$per_student$n_courses))
})

test_that("uptake omits summary_dept when there is no department to scope to", {
  cohort <- get_gen_ed_grad_cohort(gg_students_own(), cedar_degrees_gg, gg_opt())
  u <- get_gen_ed_grad_uptake(gg_students_own(), cohort, gen_ed_course_lookup(),
                              opt = list(campus = "ABQ", min_n = 1L))

  expect_null(u$summary_dept)
  expect_true(all(is.na(u$by_course$is_dept_course)))
})

test_that("own-unit profile still renders a curriculum map", {
  res <- gg_profile_own()
  p <- suppressMessages(plot_curriculum_map(res$timing_dept,
                                            opt = list(min_pct = 0, top_n = 40L)))
  expect_s3_class(p, "ggplot")
})


# =============================================================================
# Small-cell guards
# =============================================================================
#
# These exist because of a real defect, kept here as the regression: on History
# the credit axis thinned from 101 eligible graduates in the 0-30 band to 4 in
# the 121+ band, and HIST 1110 rendered a bold "25%" in that top band that was
# one student out of four. UNM-only credits understate a degree that is
# commonly half transfer credit, so the far end of the axis is always thin.

test_that("bands below min_band_n are dropped from the timing map", {
  # The GG01 cohort is 3 students, so every band is under a threshold of 10.
  res <- suppressMessages(get_gen_ed_grad_profile(
    cedar_students_gg, cedar_degrees_gg, cedar_student_term_credits_gg,
    opt = list(dept_code = "GG", campus = "ABQ", min_n = 1L, min_band_n = 10L,
               x_axis = "unm_credit_band")
  ))

  expect_equal(nrow(res$timing), 0)
  expect_true(length(res$timing_guards$dropped_bands) > 0)
  # The table is NOT guarded by band — it reports course totals, not per-band
  # rates, so it stays complete.
  expect_gt(nrow(res$by_course), 0)
})

test_that("a band above min_band_n survives", {
  res <- suppressMessages(get_gen_ed_grad_profile(
    cedar_students_gg, cedar_degrees_gg, cedar_student_term_credits_gg,
    opt = list(dept_code = "GG", campus = "ABQ", min_n = 1L, min_band_n = 3L,
               x_axis = "unm_credit_band")
  ))

  # Band 1 has all 3 cohort members eligible; the later bands have fewer.
  expect_true(1L %in% res$timing$relative_term)
  expect_false(any(res$timing$n_eligible < 3L))
})

test_that("cells below min_n are dropped even inside a healthy band", {
  res <- suppressMessages(get_gen_ed_grad_profile(
    cedar_students_gg, cedar_degrees_gg, cedar_student_term_credits_gg,
    opt = list(dept_code = "GG", campus = "ABQ", min_n = 2L, min_band_n = 1L,
               x_axis = "unm_credit_band")
  ))

  # No tile may rest on a single student, whatever its percentage looks like.
  expect_true(all(res$timing$n_students >= 2L))
  expect_true(all(res$timing_dept$n_students >= 2L))
})

test_that("timing_guards reports what was dropped and the eligibility behind it", {
  res <- suppressMessages(get_gen_ed_grad_profile(
    cedar_students_gg, cedar_degrees_gg, cedar_student_term_credits_gg,
    opt = list(dept_code = "GG", campus = "ABQ", min_n = 1L, min_band_n = 3L,
               x_axis = "unm_credit_band")
  ))
  g <- res$timing_guards

  expect_equal(g$min_band_n, 3L)
  expect_equal(g$min_n, 1L)
  expect_true(all(c("relative_term", "n_eligible") %in% names(g$band_eligible)))
  # Every dropped band must be justified by its own eligibility count, so the
  # note on the page can quote a number rather than assert one.
  dropped <- dplyr::filter(g$band_eligible, relative_term %in% g$dropped_bands)
  expect_true(all(dropped$n_eligible < 3L))
  kept <- dplyr::filter(g$band_eligible, !relative_term %in% g$dropped_bands)
  expect_true(all(kept$n_eligible >= 3L))
})

test_that("guards apply identically to both scopes", {
  # If one scope were guarded and the other not, the two heatmaps would stop
  # being comparable cell for cell — the whole reason they share one axis.
  res <- gg_profile_own(min_n = 1L)
  expect_setequal(
    unique(res$timing_dept$relative_term),
    unique(res$timing$relative_term[
      res$timing$subject_course %in% res$by_course_dept$subject_course])
  )
})

test_that("guards never invent rows", {
  loose <- suppressMessages(get_gen_ed_grad_profile(
    cedar_students_gg, cedar_degrees_gg, cedar_student_term_credits_gg,
    opt = list(dept_code = "GG", campus = "ABQ", min_n = 1L, min_band_n = 1L,
               x_axis = "unm_credit_band")))
  tight <- suppressMessages(get_gen_ed_grad_profile(
    cedar_students_gg, cedar_degrees_gg, cedar_student_term_credits_gg,
    opt = list(dept_code = "GG", campus = "ABQ", min_n = 2L, min_band_n = 3L,
               x_axis = "unm_credit_band")))

  expect_lte(nrow(tight$timing), nrow(loose$timing))
  expect_true(all(paste(tight$timing$subject_course, tight$timing$relative_term) %in%
                    paste(loose$timing$subject_course, loose$timing$relative_term)))
})


# =============================================================================
# Axis choice
# =============================================================================

test_that("relative_term is the default axis", {
  res <- suppressMessages(get_gen_ed_grad_profile(
    cedar_students_gg, cedar_degrees_gg, cedar_student_term_credits_gg,
    opt = list(dept_code = "GG", campus = "ABQ", min_n = 1L, min_band_n = 1L)))

  expect_equal(attr(res$timing, "x_axis"), "relative_term")
  expect_equal(res$timing_guards$x_axis, "relative_term")
})

test_that("relative_term needs no term_credits", {
  # The credit table is only consulted by the credit-band axis. A department
  # should still get a map if that table is unavailable.
  res <- suppressMessages(get_gen_ed_grad_profile(
    cedar_students_gg, cedar_degrees_gg, term_credits = NULL,
    opt = list(dept_code = "GG", campus = "ABQ", min_n = 1L, min_band_n = 1L)))

  expect_gt(nrow(res$timing), 0)
})

test_that("relative_term places each course by terms enrolled, not credits", {
  res <- suppressMessages(get_gen_ed_grad_profile(
    cedar_students_gg, cedar_degrees_gg, cedar_student_term_credits_gg,
    opt = list(dept_code = "GG", campus = "ABQ", min_n = 1L, min_band_n = 1L)))

  # GG_IN1's enrolled terms are 202080, 202110, 202180 -> relative terms 1, 2, 3.
  # HIST 1160 sits in their third term. On the credit axis it landed in band 4,
  # so a mix-up between the two axes cannot pass this.
  hist <- dplyr::filter(res$timing, subject_course == "HIST 1160")
  expect_equal(hist$relative_term, 3L)
})

test_that("the axis choice changes only positions, never course membership", {
  by_axis <- lapply(c("relative_term", "unm_credit_band"), function(ax) {
    suppressMessages(get_gen_ed_grad_profile(
      cedar_students_gg, cedar_degrees_gg, cedar_student_term_credits_gg,
      opt = list(dept_code = "GG", campus = "ABQ", min_n = 1L, min_band_n = 1L,
                 x_axis = ax)))
  })
  # The uptake tables are axis-independent by construction; if switching the axis
  # moved them, the table under the map would change when only the map should.
  expect_equal(by_axis[[1]]$by_course, by_axis[[2]]$by_course)
  expect_equal(by_axis[[1]]$summary, by_axis[[2]]$summary)
  expect_equal(by_axis[[1]]$summary_dept, by_axis[[2]]$summary_dept)
})

test_that("an unsupported axis is rejected rather than silently defaulted", {
  # overall_credit_band is the one that matters: its source totals are frozen per
  # program record, so accepting it would produce a plausible, meaningless map.
  expect_error(
    suppressMessages(get_gen_ed_grad_profile(
      cedar_students_gg, cedar_degrees_gg, cedar_student_term_credits_gg,
      opt = list(dept_code = "GG", campus = "ABQ", x_axis = "overall_credit_band"))),
    "should be one of"
  )
})

test_that("max_relative_term caps the axis", {
  res <- suppressMessages(get_gen_ed_grad_profile(
    cedar_students_gg, cedar_degrees_gg, cedar_student_term_credits_gg,
    opt = list(dept_code = "GG", campus = "ABQ", min_n = 1L, min_band_n = 1L,
               max_relative_term = 2L)))

  expect_true(all(res$timing$relative_term <= 2L))
})
