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

# The base class list carries no CRNs, so it cannot reach a section family
# through the full payload; these tests count its rows directly instead.
base_overview <- function(course) {
  opt <- create_test_opt(list(course = course))
  students <- filter_class_list(test_students, opt)
  assemble_course_overview(
    test_sections,
    add_first_day_enrl(calc_cl_enrls(students), students, test_sections),
    opt
  )
}

test_that("course overview only assembles canonical lifecycle and section outputs", {
  overview <- base_overview("HIST 1110")

  expect_named(overview, c("lifecycle", "sections", "listings"))
  expect_true(all(c(
    "campus", "term", "term_type", "first_day_enrl", "current_enrl",
    "census_enrl", "early_drops", "late_drops", "waitlisted"
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
      registration_status_code = "RE",
      registration_date = as.Date(NA),
      as_of_date = as.Date("2020-06-01")
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

test_that("a student who switches crosslist listings counts once, as enrolled", {
  # EC-15: EC15-S1 dropped and EC15-S2 waitlisted under CS 3750, and both hold
  # their seat under MATH 3750 in the same shared section. Their CS rows come
  # first, so a dedup left to data order counted them as a drop and a waitlist.
  opt <- create_test_opt(list(course = "MATH 3750", course_campus = "ABQ"))
  payload <- assemble_course_enrollment_payload(
    test_students_xl_switch, test_sections_xl_switch, opt
  )

  expect_equal(payload$classlist$registered, 11L)
  # E1 and E2 only; S1's drop under CS is superseded by their MATH seat.
  expect_equal(payload$classlist$dr_early, 2L)
  expect_equal(payload$classlist$wl_all, 0L)
  expect_equal(payload$classlist$dr_late, 1L)
  expect_equal(payload$overview$lifecycle$current_enrl, 11L)
  expect_equal(payload$overview$lifecycle$census_enrl, 12)
  # The class-list total agrees with the DESR sections it was drawn from.
  expect_equal(payload$overview$sections$total_enrl, 11)

  listings <- payload$overview$listings
  expect_equal(listings$current_enrl[listings$subject_course == "MATH 3750"], 7L)
  expect_equal(listings$current_enrl[listings$subject_course == "CS 3750"], 4L)
  expect_equal(listings$census_enrl[listings$subject_course == "CS 3750"], 5)
  expect_equal(payload$overview$lifecycle$selected_current_enrl, 7L)
  expect_equal(
    course_listing_count_line(
      payload$overview, "ABQ", 202110L, "current_enrl", "MATH 3750"
    ),
    "MATH 3750 7 \u00b7 CS 3750 4"
  )

  # From the partner code the family is the shared section alone, so the
  # total differs: MATH 3750's own section is not crosslisted with CS 3750.
  partner <- assemble_course_enrollment_payload(
    test_students_xl_switch, test_sections_xl_switch,
    create_test_opt(list(course = "CS 3750", course_campus = "ABQ"))
  )
  expect_equal(partner$overview$lifecycle$current_enrl, 9L)
  expect_equal(partner$overview$lifecycle$census_enrl, 10)
  expect_equal(
    course_listing_count_line(
      partner$overview, "ABQ", 202110L, "census_enrl", "CS 3750"
    ),
    "CS 3750 5 \u00b7 MATH 3750 5"
  )
})

test_that("first-day enrollment is reconstructed from status dates, or not at all", {
  # EC-15: status dates against a 2021-01-19 first class day; the fixture
  # header lists who was present and why.
  opt <- create_test_opt(list(course = "MATH 3750", course_campus = "ABQ"))
  payload <- assemble_course_enrollment_payload(
    test_students_xl_switch, test_sections_xl_switch, opt
  )
  expect_equal(payload$overview$lifecycle$first_day_enrl, 12L)
  # S1's MATH row is dated after day one; only the family sees their CS seat.
  expect_equal(payload$selected_classlist$first_day_enrl, 6L)

  partner <- assemble_course_enrollment_payload(
    test_students_xl_switch, test_sections_xl_switch,
    create_test_opt(list(course = "CS 3750", course_campus = "ABQ"))
  )
  expect_equal(partner$overview$lifecycle$first_day_enrl, 10L)

  # A class list pulled before classes began cannot say who came.
  early_pull <- test_students_xl_switch %>%
    dplyr::mutate(as_of_date = as.Date("2021-01-15"))
  expect_true(all(is.na(
    calc_first_day_enrl(early_pull, test_sections_xl_switch)$first_day_enrl
  )))

  # One undated row withholds its group's count rather than shrinking it.
  one_undated <- test_students_xl_switch %>%
    dplyr::mutate(registration_date = dplyr::if_else(
      student_id == "EC15-M4", as.Date(NA), registration_date
    ))
  by_listing <- calc_first_day_enrl(one_undated, test_sections_xl_switch)
  expect_true(is.na(by_listing$first_day_enrl[by_listing$subject_course == "MATH 3750"]))
  expect_equal(by_listing$first_day_enrl[by_listing$subject_course == "CS 3750"], 6L)

  # The base class list carries no status dates, like pulls before 2021.
  undated <- base_overview("HIST 1110")
  expect_true(all(is.na(undated$lifecycle$first_day_enrl)))
  expect_true(all(!is.na(undated$lifecycle$census_enrl)))
})

test_that("enrollment history draws first day, census, and final as labelled lines", {
  overview <- assemble_course_enrollment_payload(
    test_students_xl_switch, test_sections_xl_switch,
    create_test_opt(list(course = "MATH 3750", course_campus = "ABQ"))
  )$overview
  built <- plotly::plotly_build(build_course_enrollment_history_plot(
    overview$lifecycle, in_progress_terms = 202110L
  ))

  traces <- built$x$data
  expect_equal(
    vapply(traces, function(tr) tr$name, character(1)),
    c("ABQ \u00b7 First day", "ABQ \u00b7 Census", "ABQ \u00b7 Final")
  )
  expect_equal(vapply(traces, function(tr) tr$line$dash, character(1)),
               c("dot", "solid", "dash"))
  expect_equal(vapply(traces, function(tr) as.numeric(tr$y[[1]]), numeric(1)),
               c(12, 12, 11))
  # The in-progress term is shaded, and its final point says it is current.
  expect_true(any(vapply(built$x$layout$annotations,
                         function(a) identical(a$text, "In progress"), logical(1))))
  expect_match(traces[[3]]$customdata[[1]], "term in progress", fixed = TRUE)

  undated <- base_overview("HIST 1110")
  undated_traces <- plotly::plotly_build(
    build_course_enrollment_history_plot(undated$lifecycle)
  )$x$data
  # With no status dates in scope there is no first-day line at all, never a
  # line of zeros; census and final still say why on hover.
  undated_names <- vapply(undated_traces, function(tr) tr$name, character(1))
  expect_false(any(grepl("First day", undated_names)))
  expect_true(all(grepl("Census|Final", undated_names)))
  expect_match(undated_traces[[1]]$customdata[[1]], "not reconstructable", fixed = TRUE)
})

test_that("course overview cards label all-listing totals and per-listing counts", {
  server_source <- paste(
    readLines(file.path(cedar_base_dir, "server.R"), warn = FALSE),
    collapse = "\n"
  )

  expect_match(server_source, "Census · all listings", fixed = TRUE)
  expect_match(server_source, "Current · all listings", fixed = TRUE)
  expect_match(server_source, "course_listing_count_line(", fixed = TRUE)
  expect_match(server_source, "lifecycle <- data$overview$lifecycle", fixed = TRUE)
  expect_match(server_source, "course_overview_snapshot(", fixed = TRUE)
})

test_that("overview retains the latest descriptive enrollment term", {
  students <- filter_class_list(
    test_students, create_test_opt(list(course = "HIST 1110"))
  )
  overview <- base_overview("HIST 1110")

  expect_equal(max(overview$lifecycle$term), max(students$term))
  expect_equal(
    max(overview$sections$term),
    max(test_sections$term[test_sections$subject_course == "HIST 1110"])
  )
})

test_that("overview term scoping and defaults follow same-season history", {
  overview <- base_overview("HIST 1110")

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
  overview <- base_overview("MATH 1430")

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
