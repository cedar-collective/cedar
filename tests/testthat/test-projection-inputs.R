# Enrollment projections, the inputs: history, class-list demand, seats and
# first-day fill, the pressure screen, and what each saved bundle covers. The
# saved reasons and notes are words a reader sees, held in snapshots
# (tests/testthat/_snaps): a wording change is accepted with
# testthat::snapshot_accept() and reviewed as a diff.
testthat::local_edition(3)

test_that("projections have a standalone canonical route", {
  expect_identical(unname(CEDAR_TAB_SLUGS[["projections"]]), "Projections")
})

test_that("capacity censoring follows first-day occupancy, not census or ever-registered demand", {
  # Row 1 has ever-registered demand at the 500 seats but 420 on the first
  # day: seats turned over, they were never full. Row 3 filled every seat on
  # the first day and read 94% at census after three weeks of drops: it is
  # capacity-bounded, and a census test would miss it. Row 4 has no
  # reconstructable first day; census says full, but an unknown first day is
  # unknown occupancy, so it is not judged at all. Rows 5 and 6 sit either side
  # of the 98% line: ten empty seats of 500 is full, fifteen is not.
  backtests <- tibble::tibble(
    projected_classlist_total = c(600, 480, 600, 600, 600, 600),
    actual_classlist_total = c(500, 450, 450, 520, 495, 495),
    projected_first_day_equivalent = c(450, 400, 500, 450, 495, 495),
    actual_first_day = c(420, 450, 500, NA, 490, 485),
    actual_census = c(400, 450, 470, 500, 470, 470),
    scheduled_capacity = c(500, 500, 500, 500, 500, 500)
  ) %>%
    add_projection_capacity_censoring()

  expect_equal(backtests$capacity_fill, c(0.84, 0.9, 1.0, NA, 0.98, 0.97))
  expect_equal(backtests$capacity_gap, c(80, 50, 0, NA, 10, 15))
  expect_equal(
    backtests$capacity_usable, c(TRUE, TRUE, TRUE, FALSE, TRUE, TRUE)
  )
  expect_equal(
    backtests$capacity_reached, c(FALSE, FALSE, TRUE, FALSE, TRUE, FALSE)
  )
  expect_equal(backtests$abs_error, c(100, 30, 150, 80, 105, 105))
  expect_equal(
    backtests$capacity_censored_classlist_projection,
    c(600, 480, 450, 600, 495, 600)
  )
  expect_equal(
    backtests$capacity_censored_abs_error, c(100, 30, 0, 80, 0, 105)
  )
  expect_equal(
    backtests$capacity_explained_classlist_error, c(0, 0, 150, 0, 105, 0)
  )
  expect_equal(
    backtests$capacity_censored_miss, c(FALSE, FALSE, TRUE, FALSE, TRUE, FALSE)
  )
})

test_that("Gen Ed and FYEX monitoring group has an explicit campus scope", {
  expected_always_monitored <- c(
    "FYEX 1010", "FYEX 1030", "FYEX 1110",
    "MATH 1215", "MATH 1220", "MATH 1350", "BIOL 1140",
    "CHEM 1215", "CHEM 1215L", "ENGL 1110", "ENGL 1120"
  )
  # Second-language courses (area 6) are limited by instructors, not demand,
  # and are left out; the two the file names stay in.
  second_language <- CEDAR_GEN_ED_COURSES$subject_course[CEDAR_GEN_ED_COURSES$area == 6L]
  named_second_language <- c("SPAN 1110", "SPAN 1210")
  expected_courses <- sort(unique(c(
    setdiff(unlist(gen_ed_all, use.names = FALSE), second_language),
    expected_always_monitored,
    named_second_language
  )))
  expect_length(second_language, 55L)
  expect_setequal(
    intersect(projection_course_group_courses("critical_courses"), second_language),
    named_second_language
  )

  expect_setequal(
    projection_course_group_courses("critical_courses"),
    expected_courses
  )
  expect_length(projection_course_group_courses("critical_courses"), 141L)
  expect_setequal(
    projection_course_group_campuses("critical_courses"),
    c("ABQ", "EA")
  )
  expect_equal(
    projection_course_group_market_id("critical_courses"),
    "abq_ea_course_market"
  )
  expect_setequal(
    projection_course_group_always_monitored_courses("critical_courses"),
    expected_always_monitored
  )
  expect_true("HNRS 2221" %in% projection_course_group_courses("critical_courses"))
  expect_false("CHEM 1220" %in%
                 projection_course_group_courses("critical_courses"))
  expect_false("HNRS2221" %in% projection_course_group_courses("critical_courses"))
  expect_false(any(c("MATH 1215X", "MATH 1215Y", "MATH 1215Z") %in%
                     projection_course_group_courses("critical_courses")))
  expect_equal(names(CEDAR_ENROLLMENT_PROJECTION_METHODS),
               c("seasonal_last", "spine_adjusted"))
  expect_true(all(CEDAR_ENROLLMENT_PROJECTION_METHOD_ROLES == "observed_enrollment"))
  config <- enrollment_projection_model_config()
  expect_equal(config$history_start_term, 202210L)
  expect_equal(config$course_history_start_terms[["MATH 1215"]], 202580L)
  expect_equal(config$course_first_day_retention_min_terms[["MATH 1215"]], 1L)
  expect_equal(config$saturation_fill_threshold, 0.90)
  expect_equal(config$projection_methods, names(CEDAR_ENROLLMENT_PROJECTION_METHODS))
  expect_identical(
    CEDAR_ENROLLMENT_PROJECTION_METHOD_GUIDE$method_id,
    names(CEDAR_ENROLLMENT_PROJECTION_METHODS)
  )
  expect_identical(
    CEDAR_ENROLLMENT_PROJECTION_METHOD_GUIDE$family_id,
    unname(CEDAR_ENROLLMENT_PROJECTION_METHOD_ROLES)
  )
  expect_equal(CEDAR_ENROLLMENT_PROJECTION_DEFAULT_METHOD, "seasonal_last")
  expect_equal(config$selection_challenger_margin, 0.02)
  expect_equal(config$selection_min_backtests, 3L)
  guide <- build_enrollment_projection_method_guide(config$projection_methods)
  expect_equal(guide$n_candidates, 2L)
  expect_equal(guide$n_ideas, 2L)
  expect_equal(vapply(guide$families, function(x) nrow(x$methods), integer(1)), 2L)
  # Only the forecasts that exist are counted: retired candidate families
  # once read "0 diagnostic upstream indicators" on the page.
  expect_false(grepl("0 ", guide$summary, fixed = TRUE) || grepl("0 ", guide$overview, fixed = TRUE))
  expect_snapshot({
    cat(guide$summary, "\n\n")
    cat(guide$selection_process, "\n")
  })
  expect_error(
    enrollment_projection_model_config(list(saturation_fill_threshold = 2)),
    "saturation_fill_threshold"
  )
  expect_error(projection_course_group_courses("missing"), "Unknown projection")
  expect_error(projection_course_group_campuses("missing"), "Unknown projection")
  expect_error(
    projection_course_group_always_monitored_courses("missing"),
    "Unknown projection"
  )
  expect_error(projection_course_group_market_id("missing"), "Unknown projection")
})

test_that("model history starts at Spring 2022 with a MATH 1215 curriculum break", {
  history <- tibble::tibble(
    subject_course = c("TEST 101", "TEST 101", "MATH 1215", "MATH 1215"),
    term = c(202110L, 202210L, 202510L, 202580L)
  )

  filtered <- projection_filter_history_window(
    history, enrollment_projection_model_config()
  )

  expect_equal(filtered$term, c(202210L, 202580L))
  expect_equal(
    projection_course_history_starts(c("TEST 101", "MATH 1215")),
    c(202210L, 202580L)
  )
})

test_that("projection history retains class-list demand and census occupancy", {
  cl <- calc_cl_enrls(test_students, by_part_term = TRUE)
  history <- prepare_projection_enrollment_history(cl)

  expect_true(all(c(
    "campus", "subject_course", "part_term", "classlist_total", "census_enrl"
  ) %in% names(history)))
  expect_equal(history$classlist_total, history$registered + history$dr_early + history$dr_late)
  expect_equal(history$census_enrl, history$registered + history$dr_late)
  expect_equal(
    anyDuplicated(history[c("campus", "college", "subject_course", "term", "part_term")]),
    0L
  )
})

test_that("projection preparation filters campuses and matches course codes exactly", {
  cl <- calc_cl_enrls(test_students, by_part_term = TRUE)
  seed <- cl %>%
    dplyr::filter(subject_course == "MATH 1215Z") %>%
    dplyr::slice_head(n = 1)
  scoped <- dplyr::bind_rows(
    dplyr::mutate(seed, campus = "ABQ", subject_course = "MATH 1215"),
    dplyr::mutate(seed, campus = "ABQ", subject_course = "MATH 1215Z"),
    dplyr::mutate(seed, campus = "EA", subject_course = "MATH 1215"),
    dplyr::mutate(seed, campus = "GA", subject_course = "MATH 1215")
  )

  history <- prepare_projection_enrollment_history(
    scoped,
    courses = "MATH 1215",
    campuses = c("ABQ", "EA")
  )

  expect_setequal(history$campus, c("ABQ", "EA"))
  expect_equal(unique(history$subject_course), "MATH 1215")
})

test_that("course-market class-list demand includes drops and deduplicates delivery", {
  # Classes begin 2023-08-21. s5 dropped in the first week (DR dated after the
  # start): on the first day, gone by census -- the case that separates the
  # two counts. s6 dropped before classes began. Fall 2024 has an undated row,
  # so its first day is unknown rather than a partial count.
  students <- tibble::tribble(
    ~student_id, ~term, ~campus, ~college, ~subject_course, ~registration_status_code, ~crn, ~registration_date,
    "s1", 202380L, "ABQ", "AS", "MATH 1215", "RE", "A1", "2023-08-01",
    "s1", 202380L, "EA",  "AS", "MATH 1215", "RE", "E1", "2023-08-01",
    "s2", 202380L, "ABQ", "AS", "MATH 1215", "DW", "A1", "2023-10-15",
    "s5", 202380L, "EA",  "AS", "MATH 1215", "DR", "E1", "2023-08-25",
    "s6", 202380L, "ABQ", "AS", "MATH 1215", "DD", "A1", "2023-08-10",
    "s7", 202380L, "EA",  "AS", "MATH 1215", "DG", "E1", "2023-10-01",
    "s8", 202380L, "ABQ", "AS", "MATH 1215", "WL", "A1", NA,
    "s9", 202380L, "EA",  "AS", "MATH 1215", "XX", "E1", "2023-08-01",
    "s3", 202380L, "GA",  "AS", "MATH 1215", "RE", "G1", "2023-08-01",
    "s4", 202380L, "ABQ", "AS", "MATH 1215Z", "RE", "Z1", "2023-08-01",
    "s1", 202480L, "ABQ", "AS", "MATH 1215", "RE", "A2", "2024-08-01",
    "s2", 202480L, "ABQ", "AS", "MATH 1215", "RE", "A2", NA
  ) %>%
    dplyr::mutate(
      registration_date = as.Date(registration_date),
      as_of_date = as.Date(dplyr::if_else(term == 202380L, "2023-12-20", "2024-12-20"))
    )
  sections <- tibble::tibble(
    term = c(202380L, 202380L, 202380L, 202380L, 202480L),
    crn = c("A1", "E1", "G1", "Z1", "A2"),
    start_date = as.Date(c(rep("2023-08-21", 4), "2024-08-19"))
  )

  history <- prepare_projection_market_enrollment_history(
    students, sections,
    courses = "MATH 1215",
    campuses = c("ABQ", "EA"),
    market_id = "abq_ea_course_market"
  )
  fall_2023 <- dplyr::filter(history, term == 202380L)

  expect_equal(nrow(history), 2L)
  expect_equal(fall_2023$registered, 1L)
  expect_equal(fall_2023$dr_early, 2L)
  expect_equal(fall_2023$dr_late, 2L)
  expect_equal(fall_2023$other_non_waitlist, 1L)
  expect_equal(fall_2023$classlist_total, 6L)
  expect_equal(fall_2023$census_enrl, 3L)
  # s1 once across both campuses, plus s2, s5 and s7.
  expect_equal(fall_2023$first_day_enrl, 4)
  expect_equal(fall_2023$first_day_retention_rate, 4 / 6)
  expect_true(is.na(history$first_day_enrl[history$term == 202480L]))
  expect_true(is.na(history$first_day_retention_rate[history$term == 202480L]))
})

test_that("first-day retention reads prior same-season first days and skips unknown ones", {
  # Fall 2020 has no reconstructable first day: it is skipped, not read as
  # census. Census runs lower throughout, so a census rate would be 0.70.
  history <- projection_test_history(
    c(100, 100, 100, 100), terms = c(201980L, 202080L, 202180L, 202280L)
  ) %>%
    dplyr::mutate(
      first_day_enrl = c(80, NA, 90, 100),
      census_enrl = c(60, 70, 80, 95)
    )

  result <- projection_first_day_retention_for_row(
    history, projection_test_row(), 202280L,
    opt = list(first_day_retention_min_terms = 2L)
  )

  expect_equal(result$first_day_retention_rate, 0.85)
  expect_equal(result$first_day_retention_n_terms, 2L)
  expect_equal(result$first_day_retention_terms, "201980,202180")
})

test_that("course-market capacity pools campus and part-term components", {
  delivery <- tibble::tibble(
    campus = c("ABQ", "EA", "EA"), college = "AS", department = "TEST",
    course_title = "Test Course", subject_course = "TEST 101",
    term = 202480L, term_type = "fall", part_term = c("1", "1", "2H"),
    scheduled_sections = c(2L, 1L, 1L), scheduled_enrl = c(70, 20, 15),
    scheduled_capacity = c(80, 25, 20),
    capacity_per_section = c(40, 25, 20)
  )

  market <- prepare_projection_market_section_history(
    delivery, "abq_ea_course_market"
  )

  expect_equal(nrow(market), 1L)
  expect_equal(market$scheduled_sections, 4L)
  expect_equal(market$scheduled_capacity, 125)
  expect_equal(market$n_delivery_components, 3L)
  expect_equal(market$n_campuses, 2L)

  components <- prepare_projection_delivery_components(
    delivery_enrollment_history = tibble::tibble(
      campus = character(), college = character(),
      subject_course = character(), term = integer(), term_type = character(),
      part_term = character(), census_enrl = numeric()
    ),
    delivery_section_history = delivery,
    target_term = 202480L,
    market_id = "abq_ea_course_market"
  )
  expect_equal(nrow(components), 3L)
  expect_equal(sum(components$capacity_share), 1)
  expect_equal(components$capacity_share, c(0.64, 0.20, 0.16))
})

test_that("projection student signals read each student-term's description off cedar_student_terms (0.29.0)", {
  # The loaded class list carries no classification or major; the incoming
  # first-semester counts and the market's majors are the student-term table's.
  # Mark every student-term in 202080 a first-semester freshman with a designed
  # major, and the signals follow the table.
  st <- test_student_terms
  fall <- st$term == 202080L
  st$student_classification[fall] <- "Freshman, 1st Yr, 1st Sem"
  st$primary_major_code[fall] <- "ZZDESIGNED"
  inputs <- suppressMessages(prepare_projection_student_inputs(
    test_students, st, target_courses = "MATH 1215Z", campuses = "ABQ",
    through_term = 202110L
  ))
  uni <- inputs$university_term_signals
  expect_equal(uni$university_incoming_first_sem[uni$term == 202080L],
               uni$university_students[uni$term == 202080L])
  market <- inputs$student_terms
  expect_true(all(market$major_code[market$term == 202080L] == "ZZDESIGNED"))
  expect_false("ZZDESIGNED" %in% market$major_code[market$term != 202080L])
  expect_false(any(c("major_code", "student_classification") %in% names(test_students)))

  # A class-list student-term the table lacks is refused, never left unknown.
  expect_error(
    suppressMessages(prepare_projection_student_inputs(
      test_students, st[!fall, ], target_courses = "MATH 1215Z", campuses = "ABQ",
      through_term = 202110L
    )),
    "no row on cedar_student_terms"
  )
})

test_that("intersession is left out of every projection input (IS01)", {
  # IS01's students carry no description that matters here (IS_D's two
  # campuses in one pull would stop build_student_terms()); one row each.
  intersession_student_terms <- test_students_intersession %>%
    dplyr::distinct(student_id, term) %>%
    dplyr::mutate(term = as.integer(term), student_classification = NA_character_,
                  primary_major_code = NA_character_)
  prepare <- function(parts) {
    prepare_enrollment_projection_inputs(
      cl_enrls = calc_cl_enrls(test_students_intersession, by_part_term = TRUE),
      sections = test_sections_intersession,
      students = test_students_intersession,
      student_terms = intersession_student_terms,
      target_courses = "BIOL 1140",
      target_campuses = c("ABQ", "EA"),
      target_market_id = "abq_ea_course_market",
      enrollment_through_term = 202080L,
      section_through_term = 202080L,
      intersession_parts_of_term = parts
    )
  }

  # IS_C registered only for December and IS_F waits for a December seat:
  # neither is demand. IS_D counts once, by the regular seat.
  inputs <- prepare("INT")
  demand <- inputs$enrollment_history
  expect_equal(demand$classlist_total, 4L)
  expect_equal(demand$registered, 3L)
  expect_equal(demand$dr_early, 1L)
  expect_equal(demand$first_day_enrl, 4)
  expect_equal(inputs$section_history$scheduled_capacity, 50)
  expect_equal(inputs$delivery_components$part_term, c("1", "1"))
  expect_setequal(inputs$students$target_students$student_id,
                  c("IS_A", "IS_B", "IS_D", "IS_E"))
  expect_equal(nrow(inputs$waitlist_history), 0L)

  # Read as a regular session -- the defect -- the December rows pulled before
  # it began leave the whole course's first day unknown, its seats join the
  # term's, and its students join the demand.
  pooled <- prepare(character(0))
  expect_true(is.na(pooled$enrollment_history$first_day_enrl))
  expect_equal(pooled$section_history$scheduled_capacity, 65)
  expect_equal(pooled$enrollment_history$classlist_total, 5L)
  expect_equal(pooled$waitlist_history$waitlisted, 1L)
  expect_identical(CEDAR_INTERSESSION_PARTS_OF_TERM, "INT")
})

test_that("recent history pairs actuals and sections with current-method aftcasts", {
  projections <- projection_test_row() %>%
    dplyr::mutate(
      method_id = "seasonal_last",
      method_label = unname(CEDAR_ENROLLMENT_PROJECTION_METHODS[["seasonal_last"]]),
      applicability_reason = "Unique class-list registrants in prior fall term"
    )
  history <- projection_test_history(
    c(100, 110, 120, 130),
    terms = c(202080L, 202180L, 202280L, 202380L)
  )
  sections <- tibble::tibble(
    market_id = "abq_ea_course_market", college = "AS", department = "TEST",
    course_title = "Test Course", subject_course = "TEST 101",
    term = c(202080L, 202180L, 202280L, 202380L), term_type = "fall",
    scheduled_sections = c(3L, 3L, 4L, 4L),
    scheduled_capacity = c(105, 115, 125, 135),
    n_delivery_components = 2L, n_campuses = 2L,
    capacity_per_section = c(35, 115 / 3, 31.25, 33.75)
  )
  backtests <- tibble::tibble(
    market_id = "abq_ea_course_market", subject_course = "TEST 101",
    term_type = "fall", method_id = "seasonal_last",
    method_label = unname(CEDAR_ENROLLMENT_PROJECTION_METHODS[["seasonal_last"]]),
    policy_selected = TRUE,
    target_term = c(202180L, 202280L, 202380L), applicable = TRUE,
    applicability_reason = "Prior fall",
    projected_classlist_total = c(100, 110, 120),
    actual_classlist_total = c(110, 120, 130),
    capacity_censored_miss = FALSE,
    capacity_censored_error = -10
  )

  recent <- build_projection_recent_history(
    projections, history, sections, backtests,
    list(recent_history_terms = 3L)
  )

  expect_equal(recent$history_term, c(202380L, 202280L, 202180L))
  expect_equal(recent$recency_rank, 1:3)
  expect_equal(recent$actual_classlist_total, c(130, 120, 110))
  expect_equal(recent$actual_final_enrollment, c(130, 120, 110))
  expect_equal(recent$scheduled_sections, c(4L, 4L, 3L))
  expect_equal(recent$aftcast_classlist_total, c(120, 110, 100))
  expect_equal(recent$aftcast_method_label,
               rep(unname(CEDAR_ENROLLMENT_PROJECTION_METHODS[["seasonal_last"]]), 3))
  expect_equal(recent$first_day_fill, c(130 / 135, 120 / 125, 110 / 115))
  expect_equal(round(recent$aftcast_pct_error, 3), c(-0.077, -0.083, -0.091))
  expect_equal(
    round(recent$classlist_change, 3),
    c(0.083, 0.091, 0.100)
  )
  expect_true(all(grepl("within 10%", recent$potential_miss_explanation)))
})

test_that("movement diagnostics attach upstream, capacity, and canonical DFW context", {
  history <- empty_projection_recent_history() %>%
    tibble::add_row(
      market_id = "abq_ea_course_market", college = "AS", department = "TEST",
      subject_course = "TEST 101", term_type = "fall",
      projection_target_term = 202480L, history_term = 202280L,
      history_term_label = "Fall 2022", recency_rank = 2L,
      actual_classlist_total = 100, actual_first_day = NA_real_,
      actual_census = 95,
      actual_final_enrollment = 90, scheduled_sections = 3L,
      scheduled_capacity = 105, prior_classlist_total = 80,
      prior_scheduled_capacity = 85, classlist_change = 0.25,
      capacity_change = 20 / 85, first_day_fill = NA_real_,
      capacity_usable = FALSE, capacity_reached = FALSE,
      potential_miss_explanation = "Test"
    ) %>%
    tibble::add_row(
      market_id = "abq_ea_course_market", college = "AS", department = "TEST",
      subject_course = "TEST 101", term_type = "fall",
      projection_target_term = 202480L, history_term = 202380L,
      history_term_label = "Fall 2023", recency_rank = 1L,
      actual_classlist_total = 130, actual_first_day = 135,
      actual_census = 125,
      actual_final_enrollment = 120, scheduled_sections = 4L,
      scheduled_capacity = 135, prior_classlist_total = 100,
      prior_scheduled_capacity = 105, classlist_change = 0.30,
      capacity_change = 30 / 105, first_day_fill = 1,
      capacity_usable = TRUE, capacity_reached = TRUE,
      potential_miss_explanation = "Test"
    )
  signals <- list(
    university_term_signals = tibble::tibble(
      term = c(202110L, 202210L, 202310L),
      university_students = c(25000L, 26000L, 27300L),
      university_incoming_first_sem = c(2000L, 2100L, 2400L)
    ),
    market_term_signals = tibble::tibble(
      term = c(202110L, 202210L, 202310L),
      market_students = c(22000L, 23000L, 24150L),
      market_incoming_first_sem = c(1800L, 1900L, 2200L)
    ),
    course_outcomes = tibble::tibble(
      term = c(202110L, 202210L, 202310L), subject_course = "TEST 101",
      graded_students = c(50L, 60L, 80L), dfw_students = c(5L, 9L, 16L),
      dfw_rate = c(0.10, 0.15, 0.20)
    ),
    course_repeat_pressure = tibble::tibble(
      term = c(202210L, 202310L), next_term = c(202280L, 202380L),
      subject_course = "TEST 101", dfw_next_term_repeaters = c(4L, 10L)
    )
  )

  attached <- attach_projection_movement_signals(
    history, signals, graded_through_term = 202310L
  ) %>% dplyr::arrange(history_term)

  expect_equal(attached$source_term, c(202210L, 202310L))
  expect_equal(attached$university_student_change, c(0.04, 0.05))
  expect_equal(attached$source_dfw_students, c(9, 16))
  expect_equal(attached$source_dfw_next_term_repeaters, c(4, 10))
  expect_equal(attached$source_dfw_repeater_share, c(0.04, 10 / 130))
  expect_true(all(attached$source_outcomes_complete))
  expect_match(attached$movement_context[[2]], "capacity")

  detail <- build_enrollment_projection_movement_detail(attached)
  expect_equal(nrow(detail$data), 2L)
  # Fall 2022 has no reconstructable first day: it is not a usable term, so
  # the schedule summary counts it neither as reached nor as a term judged
  # (1 of 1, not 1 of 2).
  expect_snapshot({
    cat("schedule:", detail$schedule_summary, "\n\n")
    cat("upstream:", detail$upstream_summary, "\n\n")
    cat("dfw:", detail$dfw_summary, "\n\n")
    cat("caveat:", detail$caveat, "\n")
  })

  incomplete <- attach_projection_movement_signals(
    history, signals, graded_through_term = 202210L
  ) %>% dplyr::filter(history_term == 202380L)
  expect_false(incomplete$source_outcomes_complete)
  expect_true(is.na(incomplete$source_dfw_students))
})

test_that("projection summary history aligns four same-season terms", {
  # TEST 201 was not offered in Fall 2021, and Fall 2022's class lists carry no
  # status dates: both read as missing, never as zero or as another count.
  projections <- tibble::tibble(
    subject_course = c("TEST 101", "TEST 201")
  )
  history <- tibble::tibble(
    subject_course = c(
      rep("TEST 101", 4), "TEST 201", "TEST 201", "TEST 201"
    ),
    history_term = c(
      202080L, 202180L, 202280L, 202380L, 202080L, 202280L, 202380L
    ),
    history_term_label = c(
      "Fall 2020", "Fall 2021", "Fall 2022", "Fall 2023",
      "Fall 2020", "Fall 2022", "Fall 2023"
    ),
    actual_classlist_total = c(100, 110, 120, 130, 50, 60, 70),
    actual_first_day = c(95, 104, NA, 1210, 48, NA, 66),
    scheduled_sections = c(3L, 3L, 4L, 4L, 1L, 2L, 3L)
  )

  summary <- build_enrollment_projection_history_summary(
    projections, history
  )
  first <- summary$data[summary$data$course == "TEST 101", ]
  second <- summary$data[summary$data$course == "TEST 201", ]

  expect_equal(summary$columns$term, c(202080L, 202180L, 202280L, 202380L))
  expect_equal(summary$columns$abbr, c("Fa20", "Fa21", "Fa22", "Fa23"))
  expect_equal(first$recent_first_day[[1]], c(95, 104, NA, 1210))
  expect_equal(first$recent_sections[[1]], c(3, 3, 4, 4))
  expect_equal(second$recent_first_day[[1]], c(48, NA, NA, 66))
  expect_equal(second$recent_sections[[1]], c(1, NA, 2, 3))
  # One section is singular; an unknown count keeps the plural.
  expect_equal(
    second$recent_terms,
    paste(
      "Fa20 48 first day / 1 section; Fa21 \u2014 first day / \u2014 sections;",
      "Fa22 \u2014 first day / 2 sections; Fa23 66 first day / 3 sections"
    )
  )
  expect_equal(
    first$recent_terms,
    paste(
      "Fa20 95 first day / 3 sections; Fa21 104 first day / 3 sections;",
      "Fa22 \u2014 first day / 4 sections; Fa23 1,210 first day / 4 sections"
    )
  )
  expect_equal(enrollment_projection_model_config()$recent_history_terms, 4L)
  expect_error(
    build_enrollment_projection_history_summary(
      projections, dplyr::select(history, -actual_first_day)
    ),
    "actual_first_day"
  )
})

test_that("seasonal methods exclude the target and all future terms", {
  history <- dplyr::bind_rows(
    projection_test_history(c(10, 20, 30, 40)),
    projection_test_history(999, terms = 202580L)
  )
  row <- projection_test_row()

  last_result <- project_seasonal_last(history, row, 202480L)

  expect_true(last_result$applicable)
  expect_equal(last_result$projected_classlist_total, 40)
  expect_equal(last_result$spine_term, 202380L)
  expect_false(grepl("999", last_result$component_summary, fixed = TRUE))
})

test_that("candidate methods can be limited for fast computational audits", {
  row <- projection_test_row()
  inputs <- list(
    enrollment_history = projection_test_history(),
    students = list()
  )

  result <- project_course_method_candidates(
    inputs, row, 202480L,
    opt = list(projection_methods = "seasonal_last")
  )

  expect_equal(result$method_id, "seasonal_last")
  expect_error(
    project_course_method_candidates(
      inputs, row, 202480L,
      opt = list(projection_methods = "imaginary")
    ),
    "Unknown projection method"
  )
})

test_that("pressure screen retains forced courses and records why", {
  history <- projection_test_history(c(90, 95, 100, 105))
  sections <- tibble::tibble(
    market_id = "abq_ea_course_market", college = "AS", department = "TEST",
    course_title = "Test Course", subject_course = "TEST 101",
    term = c(202080L, 202180L, 202280L, 202380L, 202480L),
    term_type = "fall",
    scheduled_sections = c(3L, 3L, 3L, 3L, 2L),
    scheduled_enrl = c(90, 95, 100, 105, 0),
    scheduled_capacity = c(100, 100, 100, 110, 80),
    n_delivery_components = 2L, n_campuses = 2L,
    capacity_per_section = c(100, 100, 100, 110, 80) /
      c(3, 3, 3, 3, 2)
  )

  screen <- build_projection_pressure_screen(
    history, sections, 202480L,
    force_courses = "TEST 101", scope_courses = "TEST 101",
    opt = list(pressure_min_seat_gap = 10)
  )

  expect_true(screen$included)
  expect_true(screen$is_forced)
  expect_true(screen$pressure_capacity_shortfall)
  expect_true(screen$target_schedule_available)
  expect_snapshot(cat(screen$inclusion_reason))
})

test_that("pressure exclusions report the comparable-term evidence", {
  history <- projection_test_history(
    c(50, 95, 70), terms = c(202180L, 202280L, 202380L)
  )
  sections <- tibble::tibble(
    market_id = "abq_ea_course_market", college = "AS", department = "TEST",
    course_title = "Test Course", subject_course = "TEST 101",
    term = c(202180L, 202280L, 202380L, 202480L), term_type = "fall",
    scheduled_sections = 3L, scheduled_enrl = c(50, 95, 70, 0),
    scheduled_capacity = 100, n_delivery_components = 2L,
    n_campuses = 2L, capacity_per_section = 100 / 3
  )

  screen <- build_projection_pressure_screen(
    history, sections, 202480L, scope_courses = "TEST 101"
  )

  expect_false(screen$included)
  expect_equal(screen$recent_high_fill_terms, 1L)
  expect_equal(screen$recent_capacity_terms, 3L)
  # The reason gives the evidence (1 of 3 terms, within 10 seats), not a
  # verdict ("Below pressure thresholds").
  expect_false(grepl("Below pressure thresholds", screen$inclusion_reason))
  expect_snapshot(cat(screen$inclusion_reason))
})

test_that("a trend exactly at the seat gap counts on every platform (I34)", {
  # NATV 1150, Spring 2027: 109, 120, 122 fit exactly 130, which R's reference
  # BLAS computes as 129.99999999999997. Against 120 seats that is the
  # 10-seat minimum, met, so the course is included wherever it is built.
  history <- projection_test_history(
    c(109, 120, 122), terms = c(202180L, 202280L, 202380L)
  )
  sections <- tibble::tibble(
    market_id = "abq_ea_course_market", college = "AS", department = "TEST",
    course_title = "Test Course", subject_course = "TEST 101",
    term = c(202180L, 202280L, 202380L, 202480L), term_type = "fall",
    scheduled_sections = 5L, scheduled_enrl = c(109, 120, 122, 0),
    scheduled_capacity = c(200, 200, 200, 120),
    n_delivery_components = 2L, n_campuses = 2L, capacity_per_section = 40
  )

  screen <- build_projection_pressure_screen(
    history, sections, 202480L, scope_courses = "TEST 101"
  )

  expect_true(screen$pressure_growth)
  expect_true(screen$included)
  # The reason states the gap as 10, never 9.99999.
  expect_snapshot(cat(screen$inclusion_reason))
  expect_true(projection_seat_gap_reached(130 - 1e-13 - 120, 10))
  expect_false(projection_seat_gap_reached(9.99, 10))
})

test_that("the pressure screen reads first-day fill, so neither seat churn nor census drops decide pressure", {
  # 120 students ever registered against 100 seats every term, but only 80
  # held seats on the first day: the course never filled. Under the retired
  # ever-registered rule this would have passed as chronically full.
  history <- projection_test_history(
    c(120, 120, 120), terms = c(202180L, 202280L, 202380L)
  ) %>% dplyr::mutate(first_day_enrl = 80, census_enrl = 70, registered = 70)
  sections <- tibble::tibble(
    market_id = "abq_ea_course_market", college = "AS", department = "TEST",
    course_title = "Test Course", subject_course = "TEST 101",
    term = c(202180L, 202280L, 202380L), term_type = "fall",
    scheduled_sections = 3L, scheduled_enrl = 80, scheduled_capacity = 100,
    n_delivery_components = 2L, n_campuses = 2L, capacity_per_section = 100 / 3
  )

  screen <- build_projection_pressure_screen(
    history, sections, 202480L, scope_courses = "TEST 101"
  )

  expect_false(screen$included)
  expect_equal(screen$recent_high_fill_terms, 0L)
  expect_snapshot(cat(screen$inclusion_reason))

  # Full on the first day (95%) and 80% at census after week-one drops: a
  # census rule would not call this chronic.
  full <- build_projection_pressure_screen(
    dplyr::mutate(history, first_day_enrl = 95, census_enrl = 80),
    sections, 202480L, scope_courses = "TEST 101"
  )
  expect_true(full$included)
  expect_true(full$pressure_chronic_fill)

  # A first day that cannot be reconstructed is no evidence either way.
  unknown <- build_projection_pressure_screen(
    dplyr::mutate(history, first_day_enrl = NA_real_, census_enrl = 95),
    sections, 202480L, scope_courses = "TEST 101"
  )
  expect_false(unknown$pressure_chronic_fill)
  expect_equal(unknown$recent_capacity_terms, 0L)
})

test_that("capacity context distinguishes saturation, growth, and added-seat response", {
  history <- projection_test_history(
    c(80, 100, 125), terms = c(202180L, 202280L, 202380L)
  )
  sections <- tibble::tibble(
    market_id = "abq_ea_course_market", college = "AS", department = "TEST",
    course_title = "Test Course", subject_course = "TEST 101",
    term = c(202180L, 202280L, 202380L), term_type = "fall",
    scheduled_sections = c(2L, 2L, 3L), scheduled_enrl = c(80, 100, 125),
    scheduled_capacity = c(100, 100, 120),
    n_delivery_components = 2L, n_campuses = 2L,
    capacity_per_section = c(50, 50, 40)
  )

  context <- projection_capacity_context(
    history, sections, projection_test_row()
  )

  expect_equal(context$capacity_data_quality, "Usable")
  expect_equal(context$recent_capacity_reached_terms, 2L)
  expect_true(context$persistent_capacity_reached)
  expect_true(context$observed_enrollment_rising)
  expect_equal(context$capacity_increase_terms, 1L)
  expect_equal(context$demand_followed_capacity_terms, 1L)
})

test_that("target class-list snapshot drives the active seat check", {
  history <- projection_test_history(
    c(300, 400, 600), terms = c(202180L, 202280L, 202380L)
  )
  sections <- tibble::tibble(
    market_id = "abq_ea_course_market", college = "AS", department = "TEST",
    course_title = "Test Course", subject_course = "TEST 101",
    term = c(202180L, 202280L, 202380L, 202480L), term_type = "fall",
    scheduled_sections = c(7L, 9L, 13L, 10L),
    scheduled_enrl = c(300, 400, 600, 500),
    scheduled_capacity = c(350, 450, 650, 500),
    n_delivery_components = 2L, n_campuses = 2L,
    capacity_per_section = c(50, 50, 50, 50)
  )
  empty_students <- list(
    target_students = tibble::tibble(
      student_id = character(), term = integer(), subject_course = character()
    ),
    student_terms = tibble::tibble(
      student_id = character(), term = integer(), major_code = character(),
      student_classification = character()
    )
  )
  inputs <- list(
    enrollment_history = history, preceding_term_history = history,
    waitlist_history = empty_projection_test_waitlists(),
    section_history = sections,
    target_registration_snapshot = tibble::tibble(
      market_id = "abq_ea_course_market", college = "AS",
      subject_course = "TEST 101", term = 202480L, term_type = "fall",
      registered = 500, dr_early = 20, dr_late = 0,
      other_non_waitlist = 0,
      classlist_total = 520, census_enrl = 500,
      first_day_retention_rate = 500 / 520
    ),
    students = empty_students, target_courses = "TEST 101",
    target_campuses = c("ABQ", "EA"),
    target_market_id = "abq_ea_course_market",
    enrollment_through_term = 202380L,
    delivery_components = empty_projection_test_components(),
    delivery_section_history = empty_projection_test_delivery_sections(),
    delivery_first_day = empty_projection_test_delivery_first_day()
  )

  result <- get_course_enrollment_projections(
    inputs,
    202480L,
    force_courses = "TEST 101",
    opt = list(projection_methods = "seasonal_last")
  )$projections

  # The target term has no census yet, so the students registered right now
  # are its occupancy; ever-registered to date is a demand count beside it.
  expect_equal(result$method_id, "seasonal_last")
  expect_equal(result$projected_classlist_total, 600)
  expect_equal(result$projected_first_day_equivalent, 600)
  expect_equal(result$target_classlist_total_to_date, 520)
  expect_equal(result$target_registered_now, 500)
  expect_equal(result$target_available_seats, 0)
  expect_equal(result$target_classlist_fill, 1.04)
  expect_equal(result$target_active_fill, 1)
  expect_true(result$target_capacity_reached)
  expect_equal(result$projected_over_capacity, 100)
  expect_true(result$capacity_limit_signal)

  # Before registration opens there is no active fill to quote; the saved
  # note once read "active registration fill is NA".
  unopened <- inputs
  unopened$target_registration_snapshot <- inputs$target_registration_snapshot[0, ]
  early <- get_course_enrollment_projections(
    unopened, 202480L, force_courses = "TEST 101",
    opt = list(projection_methods = "seasonal_last")
  )$projections
  expect_true(is.na(early$target_active_fill))
  expect_false(grepl("NA", early$capacity_limit_note, fixed = TRUE))
  expect_snapshot({
    cat("status:", result$capacity_limit_status, "\n\n")
    cat("note, registration open:", result$capacity_limit_note, "\n\n")
    cat("note, before registration:", early$capacity_limit_note, "\n")
  })
})

test_that("registrations over the recorded cap still count as capacity reached", {
  history <- projection_test_history(
    c(100, 105), terms = c(202280L, 202380L)
  )
  sections <- tibble::tibble(
    market_id = "abq_ea_course_market", college = "AS", department = "TEST",
    course_title = "Test Course", subject_course = "TEST 101",
    term = c(202280L, 202380L, 202480L), term_type = "fall",
    scheduled_sections = 1L, scheduled_enrl = c(100, 105, 0),
    scheduled_capacity = c(10, 10, 50),
    n_delivery_components = 1L, n_campuses = 1L,
    capacity_per_section = c(10, 10, 50)
  )
  empty_students <- list(
    target_students = tibble::tibble(
      student_id = character(), term = integer(), subject_course = character()
    ),
    student_terms = tibble::tibble(
      student_id = character(), term = integer(),
      major_code = character(), student_classification = character()
    )
  )
  inputs <- list(
    enrollment_history = history, preceding_term_history = history,
    waitlist_history = empty_projection_test_waitlists(),
    section_history = sections,
    students = empty_students, target_courses = "TEST 101",
    target_campuses = c("ABQ", "EA"),
    target_market_id = "abq_ea_course_market",
    enrollment_through_term = 202380L,
    delivery_components = empty_projection_test_components(),
    delivery_section_history = empty_projection_test_delivery_sections(),
    delivery_first_day = empty_projection_test_delivery_first_day()
  )

  result <- get_course_enrollment_projections(
    inputs, 202480L, scope_courses = "TEST 101", force_courses = "TEST 101"
  )$projections

  expect_equal(result$capacity_data_quality, "Usable")
  expect_equal(result$recent_capacity_reached_terms, 2L)
  expect_true(result$persistent_capacity_reached)
  expect_equal(result$recommendation, "Add 2 sections")
})

test_that("recent history is saved by delivery campus, each with its own first day", {
  sections <- prepare_projection_section_history(
    test_sections_regstats, courses = "SOCI 100", campuses = c("ABQ", "EA")
  )
  first_day <- prepare_projection_delivery_first_day(
    test_students_regstats, test_sections_regstats, "SOCI 100", c("ABQ", "EA")
  )
  campus <- build_projection_recent_campus_history(
    campus_history_scaffold(202080L), sections, first_day
  )
  abq <- campus %>% dplyr::filter(campus == "ABQ")
  ea <- campus %>% dplyr::filter(campus == "EA")
  expect_equal(nrow(campus), 2L)
  expect_equal(abq$scheduled_sections, 2L)
  expect_equal(abq$scheduled_capacity, 200)
  expect_equal(abq$first_day_enrl, 135)
  expect_equal(abq$first_day_fill, 0.675)
  expect_equal(ea$first_day_enrl, 58)
  expect_equal(ea$first_day_fill, 0.58)
  expect_true(all(campus$first_day_basis == "complete"))
  # Neither campus was full, so nothing is flagged.
  expect_true(is.na(projection_campus_fill_flags(
    tibble::tibble(market_id = "abq_ea_course_market", subject_course = "SOCI 100",
                   target_term = 202180L),
    campus
  )))

  # EC-11c: a campus whose later session had not begun has no first day.
  pending <- prepare_projection_delivery_first_day(
    test_students_pending_session, test_sections_pending_session, "SOCI 100", "ABQ"
  )
  expect_true(is.na(pending$first_day_enrl))
  expect_equal(pending$first_day_basis, "sessions_pending")
})

test_that("a campus full on the first day beside one with room is flagged, never pooled away", {
  projections <- tibble::tibble(
    market_id = "abq_ea_course_market", subject_course = c("TEST 101", "TEST 102"),
    target_term = 202480L
  )
  # Saved campus rows, as the bundle holds them: an analytical frame, not
  # institutional data. TEST 101's online campus filled while ABQ had room.
  history <- tibble::tibble(
    market_id = "abq_ea_course_market",
    subject_course = c("TEST 101", "TEST 101", "TEST 101", "TEST 102", "TEST 102"),
    projection_target_term = 202480L,
    history_term = c(202380L, 202380L, 202280L, 202380L, 202380L),
    recency_rank = c(1L, 1L, 2L, 1L, 1L),
    campus = c("ABQ", "EA", "EA", "ABQ", "EA"),
    first_day_basis = "complete",
    first_day_fill = c(0.80, 1.00, 0.50, 0.95, 1.00)
  )
  # The term is named: "last term" read as the term just finished, which is
  # not the same-season term the flag describes.
  expect_equal(
    projection_campus_fill_flags(projections, history),
    c("EA full in Fall 2023, ABQ had room", NA)
  )
  # Near full is not room, and an incomplete first day is not compared.
  pending <- dplyr::mutate(history, first_day_basis = dplyr::if_else(
    campus == "EA" & recency_rank == 1L, "sessions_pending", first_day_basis
  ))
  expect_true(all(is.na(projection_campus_fill_flags(projections, pending))))
  # Only the latest term counts: an older full term does not raise the flag.
  older <- dplyr::mutate(history, first_day_fill = dplyr::if_else(
    recency_rank == 1L & campus == "EA", 0.70, first_day_fill
  ))
  expect_true(all(is.na(projection_campus_fill_flags(projections, older))))
})

test_that("the market waitlist counts only students on neither campus's class list", {
  # WL01 (designed_test_data.R): seven students carry a waitlist row and two
  # are waiting in the pooled ABQ+EA market. WL_A waits on both campuses and
  # is one student; WL_C is registered; WL_F is a branch campus; WL_G another
  # course. The canonical per-campus rule also keeps WL_D, who holds an EA
  # seat, and WL_E, an early drop the class-list total already counts, so a
  # floor built on it would count both twice.
  history <- prepare_projection_waitlist_history(
    test_students_wlmkt, courses = "PSYC 1110", campuses = c("ABQ", "EA"),
    market_id = "abq_ea_course_market"
  )
  expect_equal(nrow(history), 1L)
  expect_equal(history$term, 202080L)
  expect_equal(history$waitlisted, 2L)

  canonical <- get_true_waitlisted_rows(dplyr::filter(
    test_students_wlmkt, campus %in% c("ABQ", "EA"), subject_course == "PSYC 1110"
  ))
  expect_equal(dplyr::n_distinct(canonical$student_id), 4L)
})

test_that("the expansion response reads what saturated courses did when given room", {
  # Saturation is read on the first day; census sits ten seats lower, so a
  # census rule would find no saturated course here.
  course <- function(name, prior_total, prior_first_day, prior_cap, next_total, next_cap) {
    list(
      history = projection_test_history(
        c(prior_total, next_total), terms = c(202210L, 202310L), course = name
      ) %>% dplyr::mutate(
        term_type = "spring",
        first_day_enrl = c(prior_first_day, next_total),
        census_enrl = first_day_enrl - 10
      ),
      sections = tibble::tibble(
        market_id = "abq_ea_course_market", college = "AS", department = "TEST",
        course_title = name, subject_course = name,
        term = c(202210L, 202310L), term_type = "spring",
        scheduled_sections = 1L, scheduled_enrl = c(prior_total, next_total),
        scheduled_capacity = c(prior_cap, next_cap), n_delivery_components = 1L,
        n_campuses = 1L, capacity_per_section = c(prior_cap, next_cap)
      )
    )
  }
  # Five saturated courses given 50 more seats each, filling 45 of them (0.9),
  # one course that was not saturated, one saturated course held flat.
  cases <- list(
    course("A 1", 100, 95, 100, 145, 150), course("B 1", 100, 95, 100, 145, 150),
    course("C 1", 100, 95, 100, 145, 150), course("D 1", 100, 95, 100, 145, 150),
    course("E 1", 100, 95, 100, 145, 150),
    course("F 1", 60, 60, 100, 120, 150), course("G 1", 100, 95, 100, 100, 100)
  )
  history <- dplyr::bind_rows(lapply(cases, `[[`, "history"))
  sections <- dplyr::bind_rows(lapply(cases, `[[`, "sections"))

  response <- projection_expansion_response(history, sections, 202410L)
  expect_equal(response$n_pairs, 5L)
  expect_equal(response$fill_rate, 0.9)

  thin <- projection_expansion_response(
    history, sections, 202410L, opt = list(expansion_min_pairs = 6L)
  )
  expect_true(is.na(thin$fill_rate))
  expect_snapshot({
    cat(response$note, "\n\n")
    cat(thin$note, "\n")
  })
})

test_that("bundle discovery is per season, not the highest target term", {
  # Fall 202080 is the EARLIER target here. A discovery that returns the highest
  # saved term hands back Spring 202110 for a Fall request -- the failure that
  # would hide Spring the day Fall first publishes.
  fall <- projection_fixture_bundle(202080L, 202060L, 201980L)
  spring <- projection_fixture_bundle(202110L, 202080L, 202080L)
  bundle_dir <- withr::local_tempdir()
  fall_path <- file.path(bundle_dir, "enrollment-projections-202080-latest.qs")
  spring_path <- file.path(bundle_dir, "enrollment-projections-202110-latest.qs")
  write_enrollment_projection_bundle(fall, fall_path)
  write_enrollment_projection_bundle(spring, spring_path)

  saved <- find_enrollment_projection_bundles(bundle_dir)
  expect_equal(saved$target_term, c(202110L, 202080L))
  expect_equal(saved$term_type, c("spring", "fall"))

  expect_equal(find_latest_enrollment_projection_bundle(bundle_dir, "fall"), fall_path)
  expect_equal(find_latest_enrollment_projection_bundle(bundle_dir, "spring"), spring_path)
  expect_equal(load_latest_enrollment_projection_bundle(bundle_dir, "fall")$target_term,
               202080L)
  expect_equal(load_latest_enrollment_projection_bundle(bundle_dir, "spring")$target_term,
               202110L)
  expect_equal(load_enrollment_projection_bundle(bundle_dir, 202080L)$target_term, 202080L)

  # An unpublished season is an empty state; an unnamed season is an error.
  expect_null(load_latest_enrollment_projection_bundle(withr::local_tempdir(), "fall"))
  expect_null(load_enrollment_projection_bundle(bundle_dir, 202710L))
  expect_error(load_latest_enrollment_projection_bundle(bundle_dir),
               "published season is required")
  expect_error(find_latest_enrollment_projection_bundle(bundle_dir, "summer"),
               "published season is required")
  expect_equal(nrow(find_enrollment_projection_bundles(withr::local_tempdir())), 0L)
})

test_that("source fingerprints change when same-shape content changes", {
  first <- projection_table_fingerprint(tibble::tibble(
    term = c(202110L, 202210L), value = c(10, 20)
  ))
  second <- projection_table_fingerprint(tibble::tibble(
    term = c(202110L, 202210L), value = c(10, 21)
  ))

  expect_false(identical(first$content_sha256, second$content_sha256))
  expect_false(identical(first$signature, second$signature))
})
