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

  expect_named(overview, c("lifecycle", "sections", "listings", "overlap"))
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
  # E1, E2, and D1 (who dropped both codes, counted once); S1's drop under
  # CS is superseded by their MATH seat.
  expect_equal(payload$classlist$dr_early, 3L)
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

  # From the partner code the family is the shared section alone, so the
  # total differs: MATH 3750's own section is not crosslisted with CS 3750.
  partner <- assemble_course_enrollment_payload(
    test_students_xl_switch, test_sections_xl_switch,
    create_test_opt(list(course = "CS 3750", course_campus = "ABQ"))
  )
  expect_equal(partner$overview$lifecycle$current_enrl, 9L)
  expect_equal(partner$overview$lifecycle$census_enrl, 10)
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

test_that("the snapshot splits a crosslisted term by code and explains the overlap", {
  # EC-15 from MATH 3750: the code columns are each listing's own rows, so
  # early drops read 3 + 2 against an All of 3 -- D1 dropped both codes and S1
  # dropped CS on the way to MATH. The footnote names exactly those students.
  overview <- assemble_course_enrollment_payload(
    test_students_xl_switch, test_sections_xl_switch,
    create_test_opt(list(course = "MATH 3750", course_campus = "ABQ"))
  )$overview
  tables <- prepare_course_snapshot_tables(
    overview, "MATH 3750", in_progress_terms = 202110L
  )
  expect_length(tables, 1L)
  spec <- tables[[1]]
  expect_equal(spec$caption, "MATH 3750 \u00b7 ABQ")
  expect_equal(spec$current_label, "Spring 2021 \u00b7 in progress")
  expect_equal(spec$sub_labels, c("All", "MATH 3750", "CS 3750"))
  expect_equal(spec$prior_labels, c("Spring 2020", "Spring 2019", "Spring 2018"))

  row <- function(label) spec$rows[[which(vapply(spec$rows, `[[`, "", "label") == label)]]
  expect_equal(row("First day")$current, c("12", "6", "6"))
  expect_equal(row("Census")$current, c("12", "7", "5"))
  expect_equal(row("Final (so far)")$current, c("11", "7", "4"))
  expect_equal(row("Early drops")$current, c("3", "3", "2"))
  expect_equal(row("Late drops (so far)")$current, c("1", "0", "1"))
  expect_equal(row("Waitlisted")$current, c("0", "0", "1"))
  # A shared section is one room: section rows carry the total only.
  expect_equal(row("Active sections")$current, "2")
  expect_true(row("Active sections")$span_listings)
  expect_equal(row("Average size")$current, "5.5")
  # No earlier spring exists in this scenario: a dash, never a zero.
  expect_equal(row("Census")$prior, rep("\u2014", 3))
  expect_equal(
    spec$footnote,
    paste0(
      "3 students are listed under both codes: 2 moved from CS 3750 to MATH 3750 ",
      "and 1 dropped both. All counts each student once, so the code columns ",
      "can add up to more than All."
    )
  )

  # Viewed from the partner, the partner leads and the same students appear.
  partner <- prepare_course_snapshot_tables(
    assemble_course_enrollment_payload(
      test_students_xl_switch, test_sections_xl_switch,
      create_test_opt(list(course = "CS 3750", course_campus = "ABQ"))
    )$overview,
    "CS 3750"
  )[[1]]
  expect_equal(partner$sub_labels, c("All", "CS 3750", "MATH 3750"))
  expect_equal(partner$current_label, "Spring 2021")
  expect_match(partner$footnote, "2 moved from CS 3750 to MATH 3750", fixed = TRUE)

  # The renderer lays the split out as a spanning header with code sub-columns.
  # Shiny is not attached under test; htmltools supplies the same tag builders.
  ui_helpers <- new.env(parent = asNamespace("htmltools"))
  sys.source("../../R/modules/ui-helpers.R", envir = ui_helpers)
  html <- as.character(ui_helpers$cedar_snapshot_table(spec))
  expect_match(html, '<th colspan="3" scope="colgroup" class="snap-current">Spring 2021', fixed = TRUE)
  expect_match(html, '<td colspan="2" class="snap-current snap-listing snap-span"></td>', fixed = TRUE)
  # The footnote spans every column: label, three current, three prior.
  expect_match(html, '<tfoot>\\s*<tr>\\s*<td colspan="7" class="cedar-snapshot-note">3 students')
})

test_that("a course offered under one code gets the plain snapshot", {
  tables <- prepare_course_snapshot_tables(
    base_overview("HIST 1110"), "HIST 1110", campuses = "ABQ", term_type = "spring"
  )
  expect_length(tables, 1L)
  spec <- tables[[1]]
  expect_null(spec$sub_labels)
  expect_null(spec$footnote)
  expect_true(all(lengths(lapply(spec$rows, `[[`, "current")) == 1L))
  expect_false(any(vapply(spec$rows, `[[`, logical(1), "span_listings")))

  ui_helpers <- new.env(parent = asNamespace("htmltools"))
  sys.source("../../R/modules/ui-helpers.R", envir = ui_helpers)
  html <- as.character(ui_helpers$cedar_snapshot_table(spec))
  expect_false(grepl("colspan=\"3\" scope=\"colgroup\" class=\"snap-current\"", html))
  expect_false(grepl("cedar-snapshot-note", html, fixed = TRUE))
})

test_that("Course Dynamics renders the snapshot from the shared table helper", {
  server_source <- paste(
    readLines(file.path(cedar_base_dir, "server.R"), warn = FALSE),
    collapse = "\n"
  )

  expect_match(server_source, "prepare_course_snapshot_tables(", fixed = TRUE)
  expect_match(server_source, "lapply(tables, cedar_snapshot_table)", fixed = TRUE)
  expect_match(server_source, "lifecycle <- data$overview$lifecycle", fixed = TRUE)
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

  tables <- prepare_course_snapshot_tables(
    overview, "HIST 1110", campuses = "ABQ", term_type = "spring"
  )
  expect_length(tables, 1L)
  expect_equal(tables[[1]]$caption, "HIST 1110 \u00b7 ABQ")
  expect_match(tables[[1]]$current_label, "^Spring ")
})

# A hand-built overview with only the columns the snapshot reads, so expected
# values are visible here: four falls at ABQ, two at EA.
.snapshot_overview <- function() {
  lifecycle <- tibble::tibble(
    campus = c(rep("ABQ", 4), "EA", "EA"),
    term = c(202080L, 202180L, 202280L, 202380L, 202180L, 202280L),
    term_type = "fall",
    subject_course = "HIST 1110",
    first_day_enrl = c(NA, 64L, 80L, 1104L, 10L, 15L),
    census_enrl = c(55, 66, 80, 1110, 10, 15),
    current_enrl = c(50L, 60L, 75L, 1000L, 10L, 15L),
    early_drops = c(5L, 6L, 8L, 10L, 0L, 1L),
    late_drops = c(5L, 6L, 5L, 110L, 0L, 0L),
    waitlisted = c(1L, 2L, 4L, 8L, 0L, 0L)
  )
  list(
    lifecycle = lifecycle,
    sections = tibble::tibble(
      campus = lifecycle$campus, term = lifecycle$term, term_type = "fall",
      subject_course = "HIST 1110", sections = c(2L, 3L, 4L, 40L, 1L, 1L),
      avg_section_size = c(25, 20, 18.75, 25.04, 10, 15)
    ),
    listings = lifecycle[, c("campus", "term", "term_type", "subject_course",
                             "first_day_enrl", "census_enrl", "current_enrl",
                             "early_drops", "late_drops", "waitlisted")],
    overlap = tibble::tibble(
      campus = character(), term = integer(), term_type = character(),
      kind = character(), from_code = character(), to_code = character(),
      students = integer()
    )
  )
}

test_that("the snapshot sets the latest term beside the same term in earlier years", {
  spec <- prepare_course_snapshot_tables(
    .snapshot_overview(), "HIST 1110", campuses = "ABQ", term_type = "fall"
  )[[1]]
  row <- function(label) spec$rows[[which(vapply(spec$rows, `[[`, "", "label") == label)]]

  expect_equal(spec$current_label, "Fall 2023")
  expect_equal(spec$prior_labels, c("Fall 2022", "Fall 2021", "Fall 2020"))
  # Values, not percent changes; thousands separated, sizes to one decimal.
  expect_equal(row("Final")$current, "1,000")
  expect_equal(row("Final")$prior, c("75", "60", "50"))
  expect_equal(row("Average size")$current, "25.0")
  expect_equal(row("Average size")$prior, c("18.8", "20.0", "25.0"))
  # A first day that cannot be reconstructed is a dash, not a zero.
  expect_equal(row("First day")$prior, c("80", "64", "\u2014"))
  expect_equal(vapply(spec$rows, `[[`, "", "group")[c(1, 4, 7)],
               c("Enrollment", "Churn", "Sections"))
})

test_that("the snapshot keeps each campus's latest offering and labels terms in progress", {
  tables <- prepare_course_snapshot_tables(
    .snapshot_overview(), "HIST 1110", term_type = "fall",
    in_progress_terms = 202380L
  )
  expect_equal(vapply(tables, `[[`, "", "caption"),
               c("HIST 1110 \u00b7 ABQ", "HIST 1110 \u00b7 EA"))
  expect_equal(tables[[1]]$current_label, "Fall 2023 \u00b7 in progress")
  # EA's latest fall is 2022, which is settled: no "so far" there.
  expect_equal(tables[[2]]$current_label, "Fall 2022")
  labels <- function(spec) vapply(spec$rows, `[[`, "", "label")
  expect_true(all(c("Final (so far)", "Late drops (so far)") %in% labels(tables[[1]])))
  expect_true(all(c("Final", "Late drops") %in% labels(tables[[2]])))
  expect_equal(tables[[2]]$rows[[3]]$prior, c("10", "\u2014", "\u2014"))
})

test_that("the snapshot refuses an overview with a campus-term twice", {
  # Joining or reading a doubled key would double a measure or quietly keep
  # one row; either way the table would show a number nobody computed.
  doubled <- .snapshot_overview()
  doubled$lifecycle <- dplyr::bind_rows(doubled$lifecycle, doubled$lifecycle[4, ])
  expect_error(
    prepare_course_snapshot_tables(doubled, "HIST 1110", term_type = "fall"),
    "overview\\$lifecycle has more than one row"
  )
  doubled <- .snapshot_overview()
  doubled$sections <- dplyr::bind_rows(doubled$sections, doubled$sections[1, ])
  expect_error(
    prepare_course_snapshot_tables(doubled, "HIST 1110", term_type = "fall"),
    "overview\\$sections has more than one row"
  )
})

test_that("a course with sections but no class-list rows shows sections, not an error", {
  # GEOG 591 in the real data: active sections, no students in the class list.
  # The overview failed on a column-less empty history from 2026-09-04 on.
  payload <- assemble_course_enrollment_payload(
    test_students_xl_switch[0, ], test_sections_xl_switch,
    create_test_opt(list(course = "MATH 3750", course_campus = "ABQ"))
  )
  expect_equal(nrow(payload$overview$lifecycle), 0L)
  spec <- prepare_course_snapshot_tables(payload$overview, "MATH 3750")[[1]]
  row <- function(label) spec$rows[[which(vapply(spec$rows, `[[`, "", "label") == label)]]
  expect_equal(row("Active sections")$current, "2")
  # No class list is not zero students: enrollment stays blank.
  expect_equal(row("Census")$current, "\u2014")
  expect_null(spec$sub_labels)
})

test_that("the snapshot renderer takes optional hover text and rejects short rows", {
  ui_helpers <- new.env(parent = asNamespace("htmltools"))
  sys.source("../../R/modules/ui-helpers.R", envir = ui_helpers)
  spec <- list(
    caption = "X 100 \u00b7 ABQ", current_label = "Fall 2023",
    sub_labels = c("All", "X 100", "Y 100"),
    prior_labels = c("Fall 2022", "Fall 2021"),
    rows = list(
      list(group = "Enrollment", label = "Census", current = c("9", "5", "4"),
           span_listings = FALSE, prior = c("8", "7")),
      list(group = "Sections", label = "Active sections", current = "2",
           span_listings = TRUE, prior = c("2", "2"))
    )
  )
  # No prior_titles at all: the table renders without hover text.
  html <- as.character(ui_helpers$cedar_snapshot_table(spec))
  expect_match(html, '<td class="snap-prior">8</td>', fixed = TRUE)
  expect_false(grepl("title=", html, fixed = TRUE))

  short_prior <- spec
  short_prior$rows[[1]]$prior <- "8"
  expect_error(ui_helpers$cedar_snapshot_table(short_prior),
               "row 'Census' has 1 earlier value\\(s\\) for 2 earlier term")
  short_titles <- spec
  short_titles$rows[[1]]$prior_titles <- "X 100 5"
  expect_error(ui_helpers$cedar_snapshot_table(short_titles),
               "row 'Census' has 1 hover title\\(s\\) for 2 earlier value")
  unspanned <- spec
  unspanned$rows[[2]]$span_listings <- FALSE
  expect_error(ui_helpers$cedar_snapshot_table(unspanned),
               "row 'Active sections' has 1 current value\\(s\\) for 3 column")
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
