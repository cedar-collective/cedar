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
    "campus", "term", "term_type", "current_enrl", "census_enrl",
    "early_drops", "late_drops", "waitlisted"
  ) %in% names(overview$lifecycle)))
  expect_true(all(c(
    "campus", "term", "term_type", "sections", "total_enrl",
    "avg_section_size"
  ) %in% names(overview$sections)))
  expect_true(all(overview$lifecycle$term_type %in% c("fall", "spring", "summer")))
  expect_true(all(overview$sections$term_type %in% c("fall", "spring", "summer")))
})

test_that("course overview separates selected-code and crosslist-family enrollment", {
  xl <- test_sections %>%
    dplyr::filter(crosslist_group == "XL01") %>%
    dplyr::mutate(
      enrolled = dplyr::if_else(subject_course == "HIST 480", 8L, 15L),
      total_enrl = 23L,
      available = capacity - enrolled
    )
  standalone <- test_sections %>%
    dplyr::filter(subject_course == "HIST 1110", term == 202010L, campus == "ABQ") %>%
    dplyr::slice_head(n = 1L) %>%
    dplyr::mutate(
      section_id = "OVERVIEW-STANDALONE",
      crn = "OV003",
      subject = "HIST",
      course_number = "480",
      subject_course = "HIST 480",
      course_title = "Advanced Topics in History",
      enrolled = 7L,
      total_enrl = 7L,
      crosslist_code = NA_character_,
      crosslist_group = NA_character_,
      crosslist_role = NA_character_,
      crosslist_primary = TRUE,
      crosslist_external = NA,
      crosslist_partners = NA_character_
    )
  sections <- dplyr::bind_rows(xl, standalone)

  student_rows <- function(section, n) {
    tibble::tibble(
      student_id = paste0(section$crn, "-", seq_len(n)),
      crn = section$crn,
      term = section$term,
      term_type = section$term_type,
      campus = section$campus,
      college = section$college,
      department = section$department,
      subject_course = section$subject_course,
      registration_status_code = "RE"
    )
  }
  students <- dplyr::bind_rows(
    student_rows(xl %>% dplyr::filter(subject_course == "HIST 480"), 8L),
    student_rows(xl %>% dplyr::filter(subject_course == "ANTH 480"), 15L),
    student_rows(standalone, 7L)
  )
  opt <- create_test_opt(list(course = "HIST 480", course_campus = "ABQ"))

  overview_cl <- get_course_crosslist_classlist_enrl(students, sections, opt)
  overview <- assemble_course_overview(
    sections, overview_cl$selected, opt,
    crosslist_cl_enrls = overview_cl$family
  )
  enrollment_payload <- assemble_course_enrollment_payload(
    students, sections, opt
  )

  expect_equal(overview$lifecycle$selected_current_enrl, 15L)
  expect_equal(overview$lifecycle$current_enrl, 30L)
  expect_equal(overview$lifecycle$selected_census_enrl, 15L)
  expect_equal(overview$lifecycle$census_enrl, 30L)
  expect_equal(overview$sections$department_enrl, 15L)
  expect_equal(overview$sections$total_enrl, 30L)
  expect_equal(overview$sections$sections, 2L)
  expect_equal(overview$sections$crosslist_courses, "ANTH 480 + HIST 480")
  expect_true(overview$sections$has_crosslist)
  expect_equal(enrollment_payload$classlist$registered, 30L)
  expect_equal(enrollment_payload$selected_classlist$registered, 15L)
  expect_equal(
    enrollment_payload$overview$lifecycle$current_enrl,
    enrollment_payload$classlist$registered
  )

  partner_history <- get_course_section_history(
    sections, create_test_opt(list(course = "ANTH 480", course_campus = "ABQ"))
  )
  expect_equal(partner_history$department_enrl, 15L)
  expect_equal(partner_history$total_enrl, 23L)
  expect_equal(partner_history$sections, 1L)
  expect_equal(partner_history$subject_course, "ANTH 480")
})

test_that("course overview cards label crosslist totals and selected-course counts", {
  server_source <- paste(
    readLines(file.path(cedar_base_dir, "server.R"), warn = FALSE),
    collapse = "\n"
  )

  expect_match(server_source, "Census · crosslist total", fixed = TRUE)
  expect_match(server_source, "Current · crosslist total", fixed = TRUE)
  expect_match(server_source, 'paste0(item$subject_course, " only: "', fixed = TRUE)
  expect_match(server_source, "lifecycle <- data$overview$lifecycle", fixed = TRUE)
})

test_that("overview retains the latest descriptive enrollment term", {
  opt <- create_test_opt(list(course = "HIST 1110"))
  students <- filter_class_list(test_students, opt)
  classlist <- calc_cl_enrls(students)
  overview <- assemble_course_overview(test_sections, classlist, opt)

  expect_equal(max(overview$lifecycle$term), max(classlist$term))
  expect_equal(
    max(overview$sections$term),
    max(test_sections$term[test_sections$subject_course == "HIST 1110"])
  )
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

  all_terms <- filter_course_overview(overview, campuses = "ABQ", term_type = "all")
  expect_setequal(all_terms$lifecycle$term_type, overview$lifecycle$term_type)
  expect_setequal(all_terms$sections$term_type, overview$sections$term_type)

  snapshot <- course_overview_snapshot(overview, campuses = "ABQ", term_type = "spring")
  expect_true(nrow(snapshot) > 0)
  expect_true(all(snapshot$campus == "ABQ"))
  expect_equal(length(unique(snapshot$term)), 1L)
})

test_that("overview snapshot adds exact same-season one-to-three-year changes", {
  overview <- list(
    lifecycle = tibble::tibble(
      campus = "ABQ",
      term = c(202080L, 202180L, 202280L, 202380L),
      term_type = "fall",
      subject_course = "HIST 1110",
      current_enrl = c(50, 60, 75, 100),
      census_enrl = c(55, 66, 80, 110),
      early_drops = c(5, 6, 8, 10),
      late_drops = c(5, 6, 5, 10),
      waitlisted = c(1, 2, 4, 8)
    ),
    sections = tibble::tibble(
      campus = "ABQ",
      term = c(202080L, 202180L, 202280L, 202380L),
      term_type = "fall",
      subject_course = "HIST 1110",
      sections = c(2, 3, 4, 4),
      total_enrl = c(40, 60, 80, 100),
      avg_section_size = c(20, 20, 20, 25)
    )
  )

  snapshot <- course_overview_snapshot(overview, term_type = "fall")

  expect_equal(snapshot$term, 202380L)
  expect_equal(snapshot$current_enrl_change_1y, 33.3)
  expect_equal(snapshot$current_enrl_change_2y, 66.7)
  expect_equal(snapshot$current_enrl_change_3y, 100)
  expect_equal(snapshot$waitlisted_change_1y, 100)
  expect_equal(snapshot$sections_change_2y, 33.3)
  expect_equal(snapshot$avg_section_size_change_3y, 25)
})

test_that("overview snapshot keeps each campus's latest offering", {
  overview <- list(
    lifecycle = tibble::tibble(
      campus = c("ABQ", "ABQ", "EA", "EA"),
      term = c(202280L, 202380L, 202180L, 202280L),
      term_type = "fall",
      subject_course = "HIST 1110",
      current_enrl = c(50, 60, 10, 15),
      census_enrl = c(55, 66, 10, 15),
      early_drops = c(0, 0, 0, 0),
      late_drops = c(5, 6, 0, 0),
      waitlisted = c(0, 0, 0, 0)
    ),
    sections = tibble::tibble(
      campus = c("ABQ", "ABQ", "EA", "EA"),
      term = c(202280L, 202380L, 202180L, 202280L),
      term_type = "fall",
      subject_course = "HIST 1110",
      sections = c(2, 2, 1, 1),
      total_enrl = c(50, 60, 10, 15),
      avg_section_size = c(25, 30, 10, 15)
    )
  )

  snapshot <- course_overview_snapshot(overview, term_type = "fall")

  expect_equal(snapshot$term[snapshot$campus == "ABQ"], 202380L)
  expect_equal(snapshot$term[snapshot$campus == "EA"], 202280L)
  expect_equal(snapshot$waitlisted_change_1y, c(0, 0))
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

  enrollment_plot <- build_course_enrollment_history_plot(
    overview$lifecycle,
    term_type = "spring",
    campuses = c("ABQ", "EA")
  )
  expect_s3_class(enrollment_plot, "plotly")
})
