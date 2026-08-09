# Course Dynamics Overview assembly tests.
# Uses the standard designed fixtures; no production data or ad hoc scripts.

context("Course Dynamics Overview")

test_that("course section history preserves campus and uses the shared size definition", {
  history <- get_course_section_history(
    test_sections,
    create_test_opt(list(course = "MATH 1430"))
  )
  spring_2020 <- history %>%
    dplyr::filter(term == 202010L)

  expect_setequal(spring_2020$campus, c("ABQ", "EA"))
  expect_equal(nrow(spring_2020), 2L)
  expect_true(all(spring_2020$term_type == "spring"))
  expect_equal(
    spring_2020$avg_section_size,
    round(spring_2020$total_enrl / spring_2020$sections, 1)
  )
})

test_that("course overview only assembles canonical lifecycle and section outputs", {
  students <- filter_class_list(
    test_students,
    create_test_opt(list(course = "HIST 1110"))
  )
  overview <- assemble_course_overview(
    test_sections,
    calc_cl_enrls(students),
    create_test_opt(list(course = "HIST 1110"))
  )

  expect_named(overview, c("lifecycle", "sections"))
  expect_true(all(c(
    "campus", "term", "term_type", "final_enrl", "census_enrl"
  ) %in% names(overview$lifecycle)))
  expect_true(all(c(
    "campus", "term", "term_type", "sections", "total_enrl",
    "avg_section_size"
  ) %in% names(overview$sections)))
  expect_true(all(overview$lifecycle$term_type %in% c("fall", "spring", "summer")))
  expect_true(all(overview$sections$term_type %in% c("fall", "spring", "summer")))
})

test_that("overview term scoping and defaults follow same-season history", {
  students <- filter_class_list(
    test_students,
    create_test_opt(list(course = "HIST 1110"))
  )
  overview <- assemble_course_overview(
    test_sections,
    calc_cl_enrls(students),
    create_test_opt(list(course = "HIST 1110"))
  )

  scoped <- filter_course_overview(overview, campuses = "ABQ", term_type = "spring")
  expect_true(all(scoped$lifecycle$campus == "ABQ"))
  expect_true(all(scoped$sections$campus == "ABQ"))
  expect_true(all(scoped$lifecycle$term_type == "spring"))
  expect_true(all(scoped$sections$term_type == "spring"))
  expect_equal(default_course_overview_term_type(overview, 202080L), "fall")

  snapshot <- course_overview_snapshot(overview, campuses = "ABQ", term_type = "spring")
  expect_true(nrow(snapshot) > 0)
  expect_true(all(snapshot$campus == "ABQ"))
  expect_equal(length(unique(snapshot$term)), 1L)
})

test_that("overview plot builders return campus-separated Plotly charts", {
  students <- filter_class_list(
    test_students,
    create_test_opt(list(course = "MATH 1430"))
  )
  overview <- assemble_course_overview(
    test_sections,
    calc_cl_enrls(students),
    create_test_opt(list(course = "MATH 1430"))
  )

  section_plot <- build_course_overview_metric_plot(
    overview,
    source = "sections",
    metric = "sections",
    y_label = "Active sections",
    term_type = "spring",
    campuses = c("ABQ", "EA")
  )

  expect_s3_class(section_plot, "plotly")
  expect_setequal(
    unique(plotly::plotly_data(section_plot)$campus),
    c("ABQ", "EA")
  )
})
