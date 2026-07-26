context("Gen Ed profile and course-major associations")


test_that("get_course_major_associations excludes prior affiliates and counts later declarations", {
  result <- get_course_major_associations(
    gen_ed_assoc_students,
    gen_ed_assoc_programs,
    opt = list(
      subject_code = "HIST",
      dept_codes = "HIST",
      gen_ed_only = TRUE,
      gen_ed_courses = "HIST 1110",
      min_n = 1L,
      group_cols = c("subject_course", "instructor_name")
    )
  )

  adams <- result %>% dplyr::filter(instructor_name == "Adams, Erin")
  baker <- result %>% dplyr::filter(instructor_name == "Baker, Lee")

  expect_equal(adams$n_eligible, 2L)
  expect_equal(adams$n_later_declared, 2L)
  expect_equal(adams$declaration_pct, 1)

  expect_equal(baker$n_eligible, 3L)
  expect_equal(baker$n_later_declared, 2L)
  expect_equal(round(baker$declaration_pct, 3), 0.667)
})


test_that("get_course_major_associations supports aggregate course grouping", {
  result <- get_course_major_associations(
    gen_ed_assoc_students,
    gen_ed_assoc_programs,
    opt = list(
      subject_code = "HIST",
      dept_codes = "HIST",
      gen_ed_only = TRUE,
      gen_ed_courses = "HIST 1110",
      min_n = 1L,
      group_cols = "subject_course"
    )
  )

  expect_equal(nrow(result), 1L)
  expect_equal(result$subject_course, "HIST 1110")
  expect_equal(result$n_eligible, 4L)
  expect_equal(result$n_later_declared, 3L)
  expect_equal(result$declaration_pct, 0.75)
})


test_that("old instructor conversion function name is intentionally absent", {
  expect_false(exists("get_instructor_conversion", mode = "function"))
  expect_true(exists("get_course_major_associations", mode = "function"))
})


test_that("get_gen_ed_profile runs all-Gen-Ed default without department selection", {
  result <- get_gen_ed_profile(
    gen_ed_assoc_students,
    gen_ed_assoc_sections,
    gen_ed_assoc_programs,
    opt = list(min_n = 1L)
  )

  expect_equal(result$summary$n_courses, 1L)
  expect_equal(result$summary$n_departments, 1L)
  expect_equal(result$summary$n_students, 5L)
  expect_equal(result$summary$registered_enrollments, 6L)
  expect_equal(result$summary$overall_dfw, 33.3)
  expect_true(all(c("n_sections", "avg_section_enrl") %in% names(result$summary)))
  expect_true(all(c("n_sections", "avg_section_enrl") %in% names(result$enrl_by_dept)))
  expect_equal(
    result$summary$avg_section_enrl,
    round(result$summary$total_enrl / result$summary$n_sections, 1)
  )

  expect_true(nrow(result$enrl_by_course) > 0)
  expect_true(nrow(result$enrl_by_course_modality) > 0)
  expect_true(all(c("subject_course", "modality", "enrl", "term_label") %in% names(result$enrl_by_course_modality)))
  expect_true(nrow(result$dfw_by_course) > 0)
  expect_true("below_c_no_w_pct" %in% names(result$dfw_by_course))
  expect_true(all(c("early_drop_pct", "c_minus_pct", "d_pct", "f_pct") %in% names(result$dfw_by_course)))
  expect_false("below_c_pct" %in% names(result$dfw_by_course))
  expect_false("n_other_nonpassing" %in% names(result$dfw_by_course))
  expect_true(nrow(result$grade_dist) > 0)
  expect_true(nrow(result$major_mix) > 0)
  expect_equal(sum(result$major_mix$n_enrollments), result$summary$registered_enrollments)
  expect_true("History" %in% result$major_mix$major_label)
  expect_true(any(c("Undecided", "UNDC") %in% result$major_mix$major_label))
  expect_null(result$instructor_dfw)
  expect_true(nrow(result$associations) > 0)
  expect_true(all(c("n_later_declared", "declaration_pct") %in% names(result$associations)))
})


test_that("get_gen_ed_profile applies core filters consistently", {
  result <- get_gen_ed_profile(
    gen_ed_assoc_students,
    gen_ed_assoc_sections,
    gen_ed_assoc_programs,
    opt = list(
      campus = "ABQ",
      terms = 202010L,
      gen_ed_area = 5L,
      college = "ARTS",
      dept = "HIST",
      level = "lower",
      min_n = 1L
    )
  )

  expect_equal(result$summary$n_courses, 1L)
  expect_equal(result$summary$registered_enrollments, 3L)
  expect_true(all(result$enrl_by_course$term == 202010L))
  expect_true(all(result$enrl_by_course_modality$term == 202010L))
  expect_equal(unique(result$enrl_by_course_modality$modality), "F2F / ABQ")
  expect_true(all(result$courses$department == "HIST"))
  expect_true(all(result$courses$gen_ed_area == 5L))
})


test_that("get_gen_ed_profile can have section enrollment without qualifying student detail", {
  no_matching_students <- gen_ed_assoc_students %>%
    dplyr::filter(subject_course != "HIST 1110")

  result <- get_gen_ed_profile(
    no_matching_students,
    gen_ed_assoc_sections,
    gen_ed_assoc_programs,
    opt = list(dept = "HIST", min_n = 5L)
  )

  expect_gt(result$summary$total_enrl, 0)
  expect_equal(result$summary$registered_enrollments, 0L)
  expect_gt(nrow(result$enrl_by_course), 0)
  expect_equal(nrow(result$dfw_by_course), 0L)
  expect_equal(nrow(result$grade_dist), 0L)
  expect_equal(nrow(result$associations), 0L)
})


test_that("get_gen_ed_profile can include chair-facing instructor DFW rows", {
  result <- get_gen_ed_profile(
    gen_ed_assoc_students,
    gen_ed_assoc_sections,
    gen_ed_assoc_programs,
    opt = list(
      dept = "HIST",
      min_n = 1L,
      include_instructor_dfw = TRUE
    )
  )

  expect_true(all(c(
    "subject_course", "instructor_name", "n_attempts", "n_dfw",
    "dfw_rate", "course_dfw_rate", "dfw_diff_pp", "c_minus_pct",
    "d_pct", "f_pct", "w_pct", "early_drop_pct", "n_terms"
  ) %in% names(result$instructor_dfw)))

  adams <- result$instructor_dfw %>% dplyr::filter(instructor_name == "Adams, Erin")
  baker <- result$instructor_dfw %>% dplyr::filter(instructor_name == "Baker, Lee")

  expect_equal(adams$n_attempts, 3L)
  expect_equal(adams$n_dfw, 0L)
  expect_equal(adams$dfw_rate, 0)
  expect_equal(adams$course_dfw_rate, 0.3333)
  expect_equal(adams$dfw_diff_pp, -33.3)
  expect_equal(adams$f_pct, 0)
  expect_equal(adams$w_pct, 0)
  expect_equal(adams$early_drop_pct, 0)
  expect_equal(adams$n_terms, 1L)

  expect_equal(baker$n_attempts, 3L)
  expect_equal(baker$n_dfw, 2L)
  expect_equal(round(baker$dfw_rate, 3), 0.667)
  expect_equal(baker$course_dfw_rate, 0.3333)
  expect_equal(baker$dfw_diff_pp, 33.3)
  expect_equal(baker$f_pct, 33.3)
  expect_equal(baker$w_pct, 33.3)
  expect_equal(baker$early_drop_pct, 0)
  expect_equal(baker$n_terms, 1L)
})
