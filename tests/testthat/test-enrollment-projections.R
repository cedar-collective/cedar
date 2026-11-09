context("Enrollment projections")

test_that("projections have a standalone canonical route", {
  expect_identical(unname(CEDAR_TAB_SLUGS[["projections"]]), "Projections")
})

# Method tests use prepared pipeline frames rather than raw institutional tables.
# These shapes exist only after prepare_enrollment_projection_inputs(), so keeping
# them local follows the fixture boundary documented in developers/testing.md.

projection_test_history <- function(values = c(100, 110, 120, 130),
                                    terms = c(202080L, 202180L, 202280L, 202380L),
                                    course = "TEST 101") {
  tibble::tibble(
    market_id = "abq_ea_course_market",
    college = "AS",
    subject_course = course,
    term = terms,
    term_type = "fall",
    registered = values,
    dr_early = 0,
    dr_late = 0,
    classlist_total = values,
    first_day_enrl = values,
    first_day_basis = "complete",
    first_day_started_enrl = values,
    census_enrl = values
  )
}

projection_test_row <- function(course = "TEST 101") {
  tibble::tibble(
    market_id = "abq_ea_course_market",
    college = "AS",
    department = "TEST",
    subject_course = course,
    term_type = "fall",
    target_term = 202480L,
    scheduled_sections = 4L,
    scheduled_capacity = 140,
    target_classlist_total_to_date = 135,
    target_registered_now = 130,
    target_early_drops_to_date = 5,
    target_late_drops_to_date = 0,
    target_other_status_to_date = 0,
    target_registration_observed = TRUE,
    target_available_seats = 10,
    target_classlist_fill = 135 / 140,
    target_active_fill = 130 / 140,
    target_capacity_reached = FALSE,
    n_delivery_components = 2L,
    n_campuses = 2L,
    target_schedule_available = TRUE,
    recent_high_fill_terms = 2L,
    recent_capacity_terms = 3L,
    is_forced = TRUE,
    pressure_capacity_shortfall = FALSE,
    pressure_chronic_fill = TRUE,
    pressure_growth = FALSE,
    included = TRUE,
    inclusion_reason = "Test scope"
  )
}

# A published bundle over the designed fixtures, for tests that need real saved
# artifacts rather than a hand-assembled payload. Terms are settled by
# construction so the feature builder's data-edge check passes. The designed
# class lists carry no status dates, so they are dated here: late drops after
# the first class day, every other row before it. First-day enrollment then
# equals census on this fixture; the tests that separate the two build their
# own frames.
projection_fixture_bundle <- function(target_term, as_of_term,
                                      history_start_term) {
  settled_students <- test_students %>%
    dplyr::mutate(
      as_of_date = .cedar_term_start(term) + 30L,
      registration_date = .cedar_term_start(term) + dplyr::if_else(
        registration_status_code %in% STATUS_DROP_LATE, 20L, -10L
      )
    )
  build_enrollment_projection_bundle(
    cl_enrls = calc_cl_enrls(settled_students, by_part_term = TRUE),
    sections = test_sections,
    students = settled_students,
    student_terms = test_student_terms,
    target_term = target_term,
    as_of_term = as_of_term,
    scope_courses = "MATH 1215Z",
    scope_campuses = "ABQ",
    scope_market_id = "abq_course_market",
    force_courses = "MATH 1215Z",
    opt = list(history_start_term = history_start_term),
    built_at = as.POSIXct("2026-08-15 12:00:00", tz = "UTC")
  )
}

empty_projection_test_waitlists <- function() {
  tibble::tibble(
    market_id = character(), subject_course = character(), term = integer(),
    waitlisted = integer()
  )
}

empty_projection_test_components <- function() {
  tibble::tibble(
    market_id = character(), campus = character(), college = character(),
    department = character(), subject_course = character(),
    part_term = character(), target_term = integer(),
    target_term_label = character(), scheduled_sections = integer(),
    scheduled_enrl = numeric(), scheduled_capacity = numeric(),
    capacity_share = numeric(), prior_comparable_term = integer(),
    prior_census_enrl = numeric(), prior_scheduled_capacity = numeric(),
    prior_census_fill = numeric()
  )
}

# No delivery campus rows: these inputs test the pooled market alone.
empty_projection_test_delivery_sections <- function() {
  tibble::tibble(
    campus = character(), college = character(), subject_course = character(),
    part_term = character(), term = integer(), scheduled_sections = integer(),
    scheduled_capacity = numeric()
  )
}

empty_projection_test_delivery_first_day <- function() {
  tibble::tibble(
    campus = character(), term = integer(), subject_course = character(),
    first_day_enrl = numeric(), first_day_basis = character()
  )
}

projection_summary_backtests <- function(
    projected = rep(110, 6), actual = rep(100, length(projected)),
    method_id = "seasonal_last", method_role = "observed_enrollment",
    constrained = rep(FALSE, length(projected))) {
  error <- projected - actual
  method_label <- unname(CEDAR_ENROLLMENT_PROJECTION_METHODS[[method_id]])
  capacity <- ifelse(constrained, actual, 2 * actual)
  tibble::tibble(
    market_id = "abq_ea_course_market", college = "AS", department = "TEST",
    subject_course = "TEST 101", term_type = "fall",
    target_term = seq(201880L, by = 100L, length.out = length(projected)),
    method_id = method_id,
    method_label = method_label,
    method_role = method_role, applicable = TRUE,
    projected_classlist_total = projected, actual_classlist_total = actual,
    first_day_retention_rate = 1,
    projected_first_day_equivalent = projected, actual_first_day = actual,
    actual_census = actual,
    scheduled_capacity = capacity, capacity_fill = actual / capacity,
    capacity_usable = TRUE, capacity_reached = constrained,
    error = error, abs_error = abs(error),
    capacity_censored_abs_error = ifelse(
      constrained, pmax(0, -error), abs(error)
    ),
    pct_error = error / actual, abs_pct_error = abs(error / actual)
  )
}

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
  expected_courses <- sort(unique(c(
    unlist(gen_ed_all, use.names = FALSE),
    expected_always_monitored
  )))

  expect_setequal(
    projection_course_group_courses("critical_courses"),
    expected_courses
  )
  expect_length(projection_course_group_courses("critical_courses"), 139L)
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
  expect_equal(guide$summary, paste0(
    "2 forecasts: ", paste(unname(CEDAR_ENROLLMENT_PROJECTION_METHODS[config$projection_methods]),
                           collapse = ", and ")
  ))
  expect_false(grepl("0 ", guide$summary, fixed = TRUE) || grepl("0 ", guide$overview, fixed = TRUE))
  expect_match(guide$selection_process, "Last year's registrations is the default")
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
  expect_match(detail$schedule_summary, "too few comparable movements")
  # Fall 2022 has no reconstructable first day: it is not a usable term, so
  # it can count neither as reached nor as one of the terms judged.
  expect_match(
    detail$schedule_summary,
    "reached scheduled capacity (98% of seats or more) in 1 of 1 terms where first day and capacity are both known",
    fixed = TRUE
  )
  expect_match(detail$upstream_summary, "enrolled-student population changed")
  expect_match(detail$dfw_summary, "10 of them then enrolled")
  expect_match(detail$caveat, "not causal attribution")

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

test_that("the three axes are explained separately and may disagree", {
  # The state the retired single label could not express: a course whose own
  # history is calm, observed only twice, and forecast closely on those two.
  # Stability says "predictable", depth says "barely watched", accuracy says
  # "close so far". All three are true at once.
  explanation <- projection_axis_explanation(
    stability = "Stable", depth = "Thin", accuracy = "High",
    n_backtests = 2L, wape = 0.045, history_terms = 5L, history_cv = 0.04,
    history_median_yoy = 0.03, term_type = "spring"
  )

  # Reader labels: stability is "Own history" and depth is "Evidence", so
  # neither reads as a synonym of Reliability; no WAPE or aftcast jargon.
  expect_match(explanation, "Own history:", fixed = TRUE)
  expect_match(explanation, "Evidence:", fixed = TRUE)
  expect_match(explanation, "Reliability:", fixed = TRUE)
  expect_match(explanation, "moved only 4.0%", fixed = TRUE)
  expect_match(explanation, "only 2 past Spring forecasts", fixed = TRUE)
  expect_match(explanation, "landed within 4.5% on average", fixed = TRUE)
  expect_false(grepl("WAPE|aftcast|Stability|Depth", explanation))

  # A volatile course says so plainly and frames the swing as the finding,
  # rather than reporting it as a failure of the forecast.
  volatile <- projection_axis_explanation(
    stability = "Volatile", depth = "Deep", accuracy = "Low",
    n_backtests = 4L, wape = 0.42, history_terms = 5L, history_cv = 0.55,
    history_median_yoy = 0.48, term_type = "spring"
  )
  expect_match(volatile, "swings 55.0%", fixed = TRUE)
  expect_match(volatile, "the swing itself is the thing worth investigating",
               fixed = TRUE)
  expect_match(volatile, "4 past Spring forecasts stand behind", fixed = TRUE)
})

test_that("the axis summary stays compact and names the main caveat", {
  brief <- projection_axis_brief(
    stability = "Stable", depth = "Deep", accuracy = "High",
    capacity_constrained = TRUE, methods_disagree = TRUE
  )

  expect_equal(
    brief, "Stable history · Deep evidence · High reliability · capacity-limited"
  )
  expect_match(
    projection_axis_brief("Stable", "Deep", "High", regime_alarm = TRUE),
    "sharp change$"
  )
})

test_that("historical-method plot compares one term type with lifecycle actuals", {
  history <- tidyr::crossing(
    method_id = c("seasonal_last", "spine_adjusted"),
    target_term = c(202410L, 202510L, 202610L)
  ) %>%
    dplyr::mutate(
      subject_course = "CHEM 1215",
      term_type = "spring",
      method_label = unname(CEDAR_ENROLLMENT_PROJECTION_METHODS[method_id]),
      applicable = TRUE,
      raw_projected_classlist_total = dplyr::if_else(
        method_id == "seasonal_last", 200, 210
      ) + dplyr::row_number(),
      actual_classlist_total = c(205, 215, 225)[match(
        target_term, c(202410L, 202510L, 202610L)
      )],
      # Spring 2025 carries no status dates: its first day is a gap.
      actual_first_day = dplyr::if_else(
        target_term == 202510L, NA_real_, actual_classlist_total - 5
      ),
      actual_census = actual_classlist_total - 10,
      actual_final_enrollment = actual_classlist_total - 15
    )

  plot <- build_enrollment_projection_method_history_plot(
    history, selected_method_id = "spine_adjusted"
  )
  built <- plotly::plotly_build(plot)
  trace_names <- vapply(built$x$data, function(trace) trace$name, character(1))

  expect_s3_class(plot, "plotly")
  expect_true("Ever registered (model target)" %in% trace_names)
  expect_true("First day (seats judged here)" %in% trace_names)
  expect_true("Census" %in% trace_names)
  expect_true("Final / last day" %in% trace_names)
  expect_true("Last year's registrations, adjusted (selected)" %in% trace_names)
  expect_equal(length(trace_names), 6L)
  first_day_trace <- built$x$data[[which(trace_names == "First day (seats judged here)")]]
  expect_true(is.na(first_day_trace$y[[2]]))

  mixed <- dplyr::bind_rows(
    history,
    dplyr::mutate(history[1, ], term_type = "fall", target_term = 202480L)
  )
  expect_error(
    build_enrollment_projection_method_history_plot(mixed),
    "must contain one term type"
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
  expect_match(screen$inclusion_reason, "Always monitored")
  expect_true(screen$pressure_capacity_shortfall)
  expect_true(screen$target_schedule_available)
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
  expect_match(
    screen$inclusion_reason,
    paste(
      "Not selected: 1 of 3 recent fall terms with first-day enrollment",
      "at or above 90% of scheduled capacity"
    )
  )
  expect_match(screen$inclusion_reason, "within 10 seats")
  expect_false(grepl("Below pressure thresholds", screen$inclusion_reason))
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
  expect_match(screen$inclusion_reason, "Trend demand exceeds scheduled capacity by 10")
  expect_true(projection_seat_gap_reached(130 - 1e-13 - 120, 10))
  expect_false(projection_seat_gap_reached(9.99, 10))
})

test_that("an unavailable target schedule produces a planning recommendation", {
  history <- projection_test_history(
    c(90, 100, 110), terms = c(202180L, 202280L, 202380L)
  )
  sections <- tibble::tibble(
    market_id = "abq_ea_course_market", college = "AS", department = "TEST",
    course_title = "Test Course", subject_course = "TEST 101",
    term = c(202280L, 202380L), term_type = "fall",
    scheduled_sections = c(3L, 3L), scheduled_enrl = c(90, 100),
    scheduled_capacity = c(105, 105), n_delivery_components = 2L,
    n_campuses = 2L, capacity_per_section = 35
  )
  inputs <- list(
    enrollment_history = history,
    preceding_term_history = history,
    waitlist_history = empty_projection_test_waitlists(),
    section_history = sections,
    students = list(
      target_students = tibble::tibble(
        student_id = character(), term = integer(), subject_course = character()
      ),
      student_terms = tibble::tibble(
        student_id = character(), term = integer(), major_code = character(),
        student_classification = character()
      )
    ),
    target_courses = "TEST 101", target_campuses = c("ABQ", "EA"),
    target_market_id = "abq_ea_course_market",
    enrollment_through_term = 202380L,
    delivery_components = empty_projection_test_components(),
    delivery_section_history = empty_projection_test_delivery_sections(),
    delivery_first_day = empty_projection_test_delivery_first_day()
  )

  result <- get_course_enrollment_projections(
    inputs, 202480L, force_courses = "TEST 101"
  )$projections

  expect_false(result$target_schedule_available)
  # The fixture's prior Fall filled 110 of 105 seats, so the plan is a floor.
  expect_match(result$recommendation, "^Plan at least [0-9]+ section")
  expect_true(result$adjusted_saturated_prior)
})

test_that("planning sections are sized from projected registrations, not first-day seats or census", {
  # 100 students were ever registered, 90 held seats on the first day, and 60
  # were left at census. Sections follow the 100 (plus any pressure bump): the
  # margin above the first day is kept on purpose, because running short of
  # seats costs more than an empty one (0.23.0). With 32-seat sections the
  # three readings disagree -- the first day would plan 3 sections and census 2.
  history <- projection_test_history(
    c(100, 100, 100), terms = c(202180L, 202280L, 202380L)
  ) %>% dplyr::mutate(first_day_enrl = 90, census_enrl = 60, registered = 60)
  sections <- tibble::tibble(
    market_id = "abq_ea_course_market", college = "AS", department = "TEST",
    course_title = "Test Course", subject_course = "TEST 101",
    term = c(202280L, 202380L), term_type = "fall",
    scheduled_sections = c(3L, 3L), scheduled_enrl = c(60, 60),
    scheduled_capacity = c(96, 96), n_delivery_components = 2L,
    n_campuses = 2L, capacity_per_section = 32
  )
  inputs <- list(
    enrollment_history = history,
    preceding_term_history = history,
    waitlist_history = empty_projection_test_waitlists(),
    section_history = sections,
    students = list(
      target_students = tibble::tibble(
        student_id = character(), term = integer(), subject_course = character()
      ),
      student_terms = tibble::tibble(
        student_id = character(), term = integer(), major_code = character(),
        student_classification = character()
      )
    ),
    target_courses = "TEST 101", target_campuses = c("ABQ", "EA"),
    target_market_id = "abq_ea_course_market",
    enrollment_through_term = 202380L,
    delivery_components = empty_projection_test_components(),
    delivery_section_history = empty_projection_test_delivery_sections(),
    delivery_first_day = empty_projection_test_delivery_first_day()
  )

  result <- get_course_enrollment_projections(
    inputs, 202480L, force_courses = "TEST 101",
    opt = list(projection_methods = "seasonal_last")
  )$projections

  expect_equal(result$projected_classlist_total, 100)
  expect_equal(result$first_day_retention_rate, 0.9)
  expect_equal(result$projected_first_day_equivalent, 90)
  # ceiling(100 / 32) = 4; the first day (90) would say 3, census (60) 2.
  expect_equal(result$recommended_sections, 4L)
  expect_equal(result$recommendation, "Plan 4 sections")
  # 90 of 96 seats taken on both judged first days is near full, so the plan
  # carries a 5-student pressure bump (5%); ceiling(105 / 32) is still 4, and
  # the forecast is untouched. No adjusted candidate ran, so the plan has no
  # feeder adjustment.
  expect_true(result$pressure_bump_applied)
  expect_equal(result$pressure_bump, 5)
  expect_equal(result$plan_feeder_adjustment, 0)
  expect_equal(result$planned_registrations, 105)
  expect_equal(result$pressure_bump_sections, 0L)
  expect_equal(result$plan_feeder_sections, 0L)
})

test_that("an always-full course gets a pressure bump on its plan, never on its forecast", {
  # Three Falls of 200 registrations against 200 seats. First-day fill, not
  # registrations, decides near full: 190, 196 and 180 seated are 95%, 98%
  # and 90%.
  history <- projection_test_history(
    c(200, 200, 200), terms = c(202180L, 202280L, 202380L)
  ) %>% dplyr::mutate(first_day_enrl = c(190, 196, 180))
  sections <- tibble::tibble(
    market_id = "abq_ea_course_market", subject_course = "TEST 101",
    term = c(202180L, 202280L, 202380L), term_type = "fall",
    scheduled_capacity = 200
  )
  row <- tibble::tibble(
    market_id = "abq_ea_course_market", subject_course = "TEST 101",
    term_type = "fall", target_term = 202480L, method_id = "seasonal_last",
    observed_baseline = 200, projected_classlist_total = 200,
    adjusted_waitlisted_prior = 0L, adjusted_floor_uplift = 0
  )
  bump <- function(r = row, h = history) {
    projection_pressure_bump(h, sections, r)
  }

  full <- bump()
  expect_true(full$pressure_bump_applied)
  expect_equal(full$pressure_judged_terms, 3L)
  expect_equal(full$pressure_full_terms, 3L)
  expect_equal(full$pressure_bump, 10)
  expect_match(full$pressure_bump_note, paste0(
    "^Pressure bump \\+10: near full on the first day in every recent Fall ",
    "with a first-day count \\(Fall 2021, Fall 2022, Fall 2023\\), so its ",
    "registrations stopped at its seats; the bump is 5% of last Fall's ",
    "200 registrations$"
  ))

  # More students left waiting than 5%: the bump is the waiting count.
  waiting <- bump(dplyr::mutate(row, adjusted_waitlisted_prior = 31L))
  expect_equal(waiting$pressure_bump, 31)
  expect_match(waiting$pressure_bump_note, "the bump is the 31 students left waiting")

  # A floor the published method already added counts toward the bump:
  # max(5% of 200, 7 waiting) - 7 already in the projection = 3.
  floored <- bump(dplyr::mutate(
    row, method_id = "spine_adjusted", adjusted_waitlisted_prior = 7L,
    adjusted_floor_uplift = 7, projected_classlist_total = 207
  ))
  expect_equal(floored$pressure_bump, 3)
  expect_match(floored$pressure_bump_note, "the published projection already adds 7 of them$")

  # One judged Fall below the near-full line is not always near full.
  roomy <- bump(h = dplyr::mutate(history, first_day_enrl = c(190, 196, 170)))
  expect_false(roomy$pressure_bump_applied)
  expect_equal(roomy$pressure_bump, 0)
  expect_match(roomy$pressure_bump_note, "^No pressure bump: Fall 2023 filled 85\\.0% of its seats")

  # A Fall with no first-day count is skipped, never read as full or not
  # full; two judged Falls are enough, one is not.
  gap <- bump(h = dplyr::mutate(history, first_day_enrl = c(NA, 196, 180)))
  expect_true(gap$pressure_bump_applied)
  expect_equal(gap$pressure_judged_terms, 2L)
  thin <- bump(h = dplyr::mutate(history, first_day_enrl = c(NA, NA, 180)))
  expect_false(thin$pressure_bump_applied)
  expect_match(
    thin$pressure_bump_note,
    "1 of the last 3 Fall offerings has a first-day count \\(Fall 2023\\), and the bump needs 2"
  )
  new_course <- bump(h = dplyr::filter(history, term == 202380L))
  expect_false(new_course$pressure_bump_applied)
  expect_match(
    new_course$pressure_bump_note,
    "only 1 Fall offering on record, and the bump needs 2 with a first-day count"
  )

  # Feeders never cancel the bump (0.26.0): a backlog does not leave with
  # them. Their change is the plan's separate feeder adjustment.
  fell <- bump(dplyr::mutate(row, adjusted_feeder_change_rate = -0.08))
  expect_true(fell$pressure_bump_applied)
  expect_equal(fell$pressure_bump, 10)
  expect_no_match(fell$pressure_bump_note, "[Ff]eeder")
})

test_that("a Spring plan follows a listed sequence always and pooled feeders only past the line", {
  # Published rows joined to their adjusted-candidate audit fields: the
  # function's input contract, not institutional data. Fall 2024 is the term
  # just finished.
  row <- tibble::tibble(
    market_id = "abq_ea_course_market", subject_course = "TEST 201",
    term_type = "spring", target_term = 202510L, method_id = "seasonal_last",
    projected_classlist_total = 300, adjusted_applicable = TRUE,
    adjusted_preceding_term = 202480L, adjusted_feeder_check = "measured",
    adjusted_delta_sequence = -68, adjusted_sequence_courses = "SEQ 1",
    adjusted_sequence_change = -100, adjusted_delta_feeder = 3,
    adjusted_feeder_change_rate = 0.02
  )
  plan <- function(...) projection_plan_feeder_adjustment(dplyr::mutate(row, ...))

  # The sequence always counts; pooled feeders moving 2% stay out.
  inside <- plan()
  expect_equal(inside$plan_feeder_adjustment, -68)
  expect_equal(inside$plan_feeder_note, paste0(
    "Feeder adjustment -68: SEQ 1, taken the term before, moved -100 students ",
    "in Fall 2024, which carries -68 into this course; its other feeder ",
    "courses moved +2.0% in Fall 2024, inside the 5% line, so the plan does ",
    "not follow them"
  ))

  # Pooled feeders count at the line exactly and beyond it, either way.
  at_line <- plan(adjusted_feeder_change_rate = -0.05, adjusted_delta_feeder = -12)
  expect_equal(at_line$plan_feeder_adjustment, -80)
  up <- plan(adjusted_sequence_courses = NA_character_, adjusted_delta_sequence = 0,
             adjusted_feeder_change_rate = 0.064, adjusted_delta_feeder = 9.4)
  expect_equal(up$plan_feeder_adjustment, 9)
  expect_match(up$plan_feeder_note,
               "^Feeder adjustment \\+9: its feeder courses moved \\+6\\.4% in Fall 2024, 5% or more, which carries \\+9$")

  # The published adjusted candidate already holds both deltas.
  adjusted <- plan(method_id = "spine_adjusted")
  expect_equal(adjusted$plan_feeder_adjustment, 0)
  expect_match(adjusted$plan_feeder_note,
               "^No feeder adjustment: the published projection already includes the changes in Fall 2024\\. SEQ 1")

  # Two steps out the term just finished is unobserved, so nothing is read.
  unseen <- plan(adjusted_sequence_courses = NA_character_, adjusted_delta_sequence = 0,
                 adjusted_feeder_check = "term_not_observed",
                 adjusted_delta_feeder = 0, adjusted_feeder_change_rate = NA_real_)
  expect_equal(unseen$plan_feeder_adjustment, 0)
  expect_equal(unseen$plan_feeder_note, paste0(
    "No feeder adjustment: feeder courses in Fall 2024 are not observed yet; ",
    "recheck when they settle"
  ))
  none <- plan(adjusted_applicable = FALSE)
  expect_equal(none$plan_feeder_adjustment, 0)

  # A Fall plan does not follow its Spring feeders (0.27.0): the same
  # sequence and an 8% pooled move leave it where the projection is.
  fall <- plan(term_type = "fall", target_term = 202580L,
               adjusted_preceding_term = 202510L,
               adjusted_feeder_change_rate = 0.08, adjusted_delta_feeder = 15)
  expect_equal(fall$plan_feeder_adjustment, 0)
  expect_equal(fall$plan_feeder_note,
               "No feeder adjustment: only Spring plans follow their feeder courses")
  # The season list is a model setting, not a fixed rule.
  both <- projection_plan_feeder_adjustment(
    dplyr::mutate(row, term_type = "fall", target_term = 202580L,
                  adjusted_preceding_term = 202510L),
    list(plan_feeder_seasons = c("spring", "fall"))
  )
  expect_equal(both$plan_feeder_adjustment, -68)
  expect_equal(projection_plan_feeder_seasons_rule(character(0)),
               "no plan follows its feeder courses")
  expect_error(projection_plan_feeder_seasons_rule("autumn"), "Unknown plan_feeder_seasons")
})

test_that("each past forecast term records its seat change and whether the term before was full", {
  # Fall offerings of 100, 100, 130 seats; the first two seated 95 and 70 on
  # day one. Fall 2023 is a +30% seat change after a near-full Fall 2022;
  # Fall 2022 held its seats after a Fall 2021 with room.
  history <- projection_test_history(
    c(100, 100, 120), terms = c(202180L, 202280L, 202380L)
  ) %>% dplyr::mutate(first_day_enrl = c(70, 95, 118))
  sections <- tibble::tibble(
    market_id = "abq_ea_course_market", subject_course = "TEST 101",
    term = c(202180L, 202280L, 202380L), term_type = "fall",
    scheduled_capacity = c(100, 100, 130)
  )
  backtests <- tibble::tibble(
    market_id = "abq_ea_course_market", subject_course = "TEST 101",
    term_type = "fall", target_term = c(202180L, 202280L, 202380L)
  )
  folds <- annotate_projection_fold_conditions(backtests, history, sections)

  expect_true(is.na(folds$fold_seat_change[[1]]))
  expect_true(is.na(folds$fold_prior_near_full[[1]]))
  expect_equal(folds$fold_seat_change[[2]], 0)
  expect_false(folds$fold_prior_near_full[[2]])
  expect_equal(folds$fold_seat_change[[3]], 0.30)
  expect_true(folds$fold_prior_near_full[[3]])
})

test_that("seat consistency counts how often seats moved in the terms behind reliability", {
  projections <- tibble::tibble(
    market_id = "abq_ea_course_market", term_type = "fall",
    subject_course = c("STEADY 1", "ONCE 1", "OFTEN 1", "NEW 1")
  )
  # Only the rule's published aftcasts count; the other candidate's rows and
  # a term with no seat comparison are ignored.
  backtests <- tibble::tribble(
    ~subject_course, ~target_term, ~policy_selected, ~fold_seat_change,
    "STEADY 1", 202280L, TRUE,  0.02,
    "STEADY 1", 202380L, TRUE, -0.05,
    "STEADY 1", 202380L, FALSE,  0.50,
    "ONCE 1",   202280L, TRUE,  0.25,
    "ONCE 1",   202380L, TRUE,  0.00,
    "OFTEN 1",  202180L, TRUE,  NA,
    "OFTEN 1",  202280L, TRUE, -0.20,
    "OFTEN 1",  202380L, TRUE,  0.15
  ) %>% dplyr::mutate(market_id = "abq_ea_course_market", term_type = "fall")
  result <- add_projection_seat_consistency(projections, backtests)

  expect_equal(result$seat_consistency, c("High", "Moderate", "Low", "Unrated"))
  expect_equal(result$seat_consistency_terms, c(2L, 2L, 2L, 0L))
  expect_equal(result$seat_consistency_moves, c(0L, 1L, 2L, 0L))
  expect_equal(result$seat_consistency_reason[[1]],
               "Seats held within 10% in all 2 past forecast terms")
  expect_equal(result$seat_consistency_reason[[3]], paste0(
    "Seats moved 10% or more in 2 of 2 past forecast terms ",
    "(Fall 2022 -20%, Fall 2023 +15%)"
  ))
})

test_that("a past miss is the schedule's only when a full course's seats moved the way it missed", {
  config <- list(seat_consistency_change = 0.10, saturation_fill_threshold = 0.90,
                 accuracy_close_max_wape = 0.10, accuracy_fair_max_wape = 0.20)
  # One row per case, the patterns of the Spring 2027 courses more than 20%
  # off (ISSUES.md I40): a course full every term whose seats were cut and
  # added (ENGL 1110), and one never full whose seats followed its enrollment
  # (FYEX 1110). error is projected minus actual; fill is first day / seats.
  folds <- tibble::tribble(
    ~case,                          ~error, ~fold_seat_change, ~fold_prior_near_full, ~actual_first_day, ~scheduled_capacity,
    "added, low, full before",         -85,  0.48,  TRUE,  102, 100,
    "cut, high, full after",           104, -0.28,  TRUE,  105, 100,
    "added, low, full only after",     -40,  0.30,  FALSE,  95, 100,
    "cut, high, room after",            10, -0.29,  FALSE,  68, 100,
    "added, low, room both",          -185,  3.03,  FALSE,  86, 100,
    "held, high, room after",           20,  0.02,  FALSE,  53, 100,
    "held, low, full after",           -22,  0.04,  FALSE,  96, 100,
    "added, high: against the seats",   15,  0.40,  TRUE,   80, 100,
    "no seat comparison",              -30,    NA,  NA,     90, 100,
    "added, low, fills unknown",       -30,  0.40,  NA,     NA, 100,
    "cut, high, first day unknown",     30, -0.20,  TRUE,   NA, 100
  )
  expect_equal(
    projection_fold_miss_cause(folds, config),
    c("schedule", "schedule", "schedule", "forecast", "forecast", "forecast",
      "seats_full", "forecast", "unknown", "unknown", "unknown")
  )
  # Options resolve through projection_option(), so an empty opt reads the
  # model defaults, which are the levels above.
  expect_equal(projection_fold_miss_cause(folds, list()), projection_fold_miss_cause(folds, config))
  expect_error(projection_fold_miss_cause(dplyr::select(folds, -actual_first_day), config),
               "actual_first_day")

  # Per course, whichever cause holds most of its absolute error; only the
  # rule's published past forecasts count.
  key <- function(course) tibble::tibble(market_id = "m", subject_course = course, term_type = "spring")
  projections <- dplyr::bind_rows(key("ALWAYS 1"), key("MIXED 1"), key("ROOM 1"), key("NEW 1"))
  backtests <- dplyr::bind_rows(
    dplyr::mutate(folds[1:2, ], subject_course = "ALWAYS 1"),
    # 85 of the schedule's against 20 + 10 of the forecast's: mostly seats.
    dplyr::mutate(folds[c(1, 6, 4), ], subject_course = "MIXED 1"),
    dplyr::mutate(folds[c(5, 6), ], subject_course = "ROOM 1"),
    # Another candidate's row never counts.
    dplyr::mutate(folds[5, ], subject_course = "ALWAYS 1", policy_selected = FALSE)
  ) %>%
    dplyr::mutate(market_id = "m", term_type = "spring", abs_error = abs(error),
                  policy_selected = dplyr::coalesce(policy_selected, TRUE))
  attribution <- projection_miss_attribution(projections, backtests, config)
  expect_equal(attribution$miss_cause, c("seats", "seats", "forecast", NA))
  expect_equal(attribution$miss_seat_share, c(1, 85 / 115, 0, NA))
  expect_equal(attribution$miss_forecast_share, c(0, 30 / 115, 1, NA))

  reading <- projection_reliability_reading(
    c("Low", "Low", "Low", "High", "Unrated", "Moderate"),
    c("seats", "forecast", "unknown", "forecast", NA, "seats"), config
  )
  # The words are projection_fold_miss_cause()'s rule, as the error panel
  # says it: a held seat count on a near-full course is the schedule's too,
  # and seats moving against the miss leave it the forecast's.
  expect_match(reading[[1]], "when the course was near full and its seats moved the way of the miss or held: the schedule set those numbers")
  expect_match(reading[[2]], "while the course had seats to spare, or its seats moved against the miss, so the misses were the forecast's")
  expect_match(reading[[3]], "the cause cannot be told")
  expect_match(reading[[4]], "landed close")
  expect_match(reading[[5]], "^Too few past forecasts")
  expect_match(reading[[6]], "^Past forecasts were 10% to 20% off, mostly when the course was near full and its seats moved the way of the miss or held\\.$")
  expect_error(projection_reliability_reading("Low", "seats", list()), "accuracy_close_max_wape")
})

test_that("past error is summed by whose miss each term was", {
  # One row per published past forecast, read by projection_fold_miss_cause():
  # seats +40% on a course near full the year before, forecast low (schedule);
  # seats -30% and the forecast high, near full after (schedule); seats held,
  # near full after (seats_full); seats held with room (forecast, held); seats
  # +20% with room on both sides (forecast, moved); seats +30% and the
  # forecast high, against the move (forecast, moved); no seat change known
  # (unknown); and an unpublished row the summary ignores.
  backtests <- tibble::tribble(
    ~policy_selected, ~error, ~abs_error, ~actual_classlist_total, ~fold_seat_change, ~fold_prior_near_full, ~actual_first_day, ~scheduled_capacity,
    TRUE,  -30, 30, 100,  0.40, TRUE,  98, 100,
    TRUE,   10, 10, 100, -0.30, NA,    95, 100,
    TRUE,   -5,  5, 100,  0.00, TRUE,  96, 100,
    TRUE,   15, 15, 100,  0.05, FALSE, 60, 100,
    TRUE,  -12, 12, 100,  0.20, FALSE, 70, 100,
    TRUE,    8,  8, 100,  0.30, TRUE,  99, 100,
    TRUE,   20, 20, 100,  NA,   NA,    NA,  NA,
    FALSE,  99, 99, 100,  0.00, TRUE,  95, 100
  )
  sources <- summarize_projection_error_sources(backtests)

  expect_equal(sources$source,
               c("schedule", "seats_full", "forecast_seats_moved",
                 "forecast_seats_held", "unknown"))
  expect_equal(sources$owner,
               c("schedule", "schedule", "forecast", "forecast", "unknown"))
  expect_equal(sources$folds, c(2L, 1L, 2L, 1L, 1L))
  # 100 points of error in all, from the rule's published rows only.
  expect_equal(sources$share_of_error, c(40, 5, 20, 15, 20) / 100)
  expect_equal(sources$wape, c(40 / 200, 5 / 100, 20 / 200, 15 / 100, 20 / 100))
  expect_equal(sources$label[[1]], "Near full; seats moved 10% or more the way of the miss")

  summary <- projection_error_sources_summary(backtests, list())
  expect_equal(summary$n_folds, 7L)
  expect_equal(
    summary$sentence,
    paste0(
      "Across 7 past forecasts, 45% of the error came when the course was near ",
      "full and its seats moved the way of the miss (40%) or held (5%): the ",
      "schedule set those numbers. 35% was the forecast's own, with seats to ",
      "spare or seats moving against the miss (3 past forecasts), and 20% came ",
      "from terms whose seats or first day are not known."
    )
  )
})

# The published rule's record beside doing nothing, from saved aftcasts. Four
# Spring folds for one course, actual 100 each; the rule published prior
# same-season in 2023 and 2025 and the adjusted forecast in 2024 and 2026:
#   fold  seats   default |err|  adjusted |err|  published |err|
#   2023  +2%     10             12              10 (default)
#   2024  +30%    20             15              15 (adjusted)
#   2025  -5%      5              9               5 (default)
#   2026  unknown 29             20              20 (adjusted)
# Published 50 / 400 = 12.5%; prior same-season alone 64 / 400 = 16.0%; with
# seats held (2023, 2025) 15 / 200 = 7.5%, with seats moved (2024) 15 / 100 =
# 15.0%. An unknown seat change is neither held nor moved. The published
# errors are -10, -15, +5, -20: 40 low on 400, so the record says the
# forecasts ran 10% low and why.
test_that("the forecast's record is stated beside last year's number alone", {
  backtests <- tibble::tribble(
    ~target_term, ~method_id,       ~policy_selected, ~error, ~fold_seat_change,
    202310L,      "seasonal_last",  TRUE,             -10,     0.02,
    202310L,      "spine_adjusted", FALSE,            -12,     0.02,
    202410L,      "seasonal_last",  FALSE,            -20,     0.30,
    202410L,      "spine_adjusted", TRUE,             -15,     0.30,
    202510L,      "seasonal_last",  TRUE,               5,    -0.05,
    202510L,      "spine_adjusted", FALSE,              9,    -0.05,
    202610L,      "seasonal_last",  FALSE,            -29,     NA,
    202610L,      "spine_adjusted", TRUE,             -20,     NA
  ) %>%
    dplyr::mutate(market_id = "m", subject_course = "TEST 101",
                  term_type = "spring", actual_classlist_total = 100,
                  abs_error = abs(error))
  record <- projection_track_record_summary(backtests, list())
  expect_equal(record$n_folds, 4L)
  expect_equal(record$wape, 50 / 400)
  expect_equal(record$default_wape, 64 / 400)
  expect_equal(record$held_folds, 2L)
  expect_equal(record$held_wape, 15 / 200)
  expect_equal(record$moved_folds, 1L)
  expect_equal(record$moved_wape, 15 / 100)
  expect_equal(record$bias, -40 / 400)
  expect_equal(record$sentence, paste0(
    "When the seats stayed within 10% of the year before, past forecasts ",
    "were 7.5% off on average (2 of 4 past Spring forecasts); when the seats ",
    "moved more than that, 15.0% off (1). Over all 4, ",
    "the published forecast was 12.5% off, and last year's number alone 16.0%.",
    " They ran 10.0% low on average: a course that filled registers only as ",
    "many students as it had seats, so when seats were added the next year, ",
    "more registered than last year's count said."
  ))
  expect_equal(record$headline, paste0(
    "Past Spring forecasts were within 7.5% where the seats held (2 of 4) and ",
    "15.0% off where they moved 10% or more (1): most of the error follows ",
    "the schedule, not the forecast."
  ))
  # A record that ran high says so without the full-course explanation, and
  # one within a point of even says nothing about direction.
  high <- projection_track_record_summary(
    dplyr::mutate(backtests, error = -error), list()
  )
  expect_match(high$sentence, "They ran 10\\.0% high on average\\.$")
  even <- projection_track_record_summary(
    dplyr::mutate(backtests, error = dplyr::if_else(target_term == 202610L, 20, error)),
    list()
  )
  expect_equal(even$bias, 0)
  expect_false(grepl("on average: a course", even$sentence, fixed = TRUE))
  expect_match(even$sentence, "alone 16\\.0%\\.$")
  # Comparing the rule with doing nothing needs doing nothing on every term.
  expect_error(
    projection_track_record_summary(
      dplyr::filter(backtests, !(target_term == 202410L & method_id == "seasonal_last")),
      list()
    ),
    "1 published past forecasts have no prior same-season aftcast"
  )
  expect_match(projection_track_record_summary(backtests[0, ], list())$sentence,
               "^No past forecasts are saved")
})

# ISSUES.md M35. Five published forecasts of 100 for one course; each range is
# rebuilt from the earlier misses only (80th percentile, type 7):
#   fold  actual  miss  earlier misses   half-width  seats   held?
#   1     90      +10   none             --          --      not scored
#   2     110     -10   10               10          +2%     yes
#   3     95       +5   10, 10           10          +5%     yes
#   4     130     -30   10, 10, 5        10          +30%    no, actual above
#   5     100       0   10, 10, 5, 30    18          -3%     yes
# A sixth fold the rule did not publish is never read.
test_that("the range's rolling coverage is reported by whether seats held", {
  backtests <- tibble::tibble(
    market_id = "abq_ea_course_market", subject_course = "TEST 101",
    term_type = "fall", target_term = seq(202080L, by = 100L, length.out = 6),
    policy_selected = c(rep(TRUE, 5), FALSE),
    projected_classlist_total = 100,
    actual_classlist_total = c(90, 110, 95, 130, 100, 40),
    fold_seat_change = c(NA, 0.02, 0.05, 0.30, -0.03, 0)
  )
  coverage <- summarize_projection_range_coverage(backtests)
  expect_equal(coverage$seats, c("steady", "moved", "unknown"))
  expect_equal(coverage$folds, c(3L, 1L, 0L))
  expect_equal(coverage$covered, c(3L, 0L, 0L))
  expect_equal(coverage$actual_above, c(0L, 1L, 0L))
  expect_equal(coverage$coverage, c(1, 0, NA))

  summary <- projection_range_coverage_summary(backtests, list())
  expect_equal(summary$sentence, paste0(
    "The range assumes seats like last year's. Rebuilt for each past forecast ",
    "from the course's earlier ones only, it held 3 of 3 times when seats ",
    "stayed within 10% of the year before, and 0 of 1 when they moved. Of its ",
    "1 miss, 1 had registrations above it."
  ))
  none <- projection_range_coverage_summary(backtests[1, ], list())
  expect_match(none$sentence, "cannot be shown yet\\.$")
  expect_error(
    summarize_projection_range_coverage(dplyr::select(backtests, -fold_seat_change)),
    "fold_seat_change"
  )
})

test_that("the draft comparison separates short of day one from short of the plan", {
  projections <- tibble::tibble(
    market_id = "abq_ea_course_market",
    subject_course = c("DAY 1", "PLAN 1", "COVER 1", "SPARE 1", "MISSING 1"),
    department = "TEST",
    projected_classlist_total = 100,
    planned_registrations = 110, pressure_bump = 10, plan_feeder_adjustment = 0,
    projected_first_day_equivalent = 90,
    recommended_sections = 4L, reference_section_size = 30,
    scheduled_sections = c(2L, 3L, 4L, 7L, 0L),
    # DAY 1 is short of day one by less than a section (30 of 90) and of the
    # plan by two (50 of 110), so the two section counts differ.
    scheduled_capacity = c(60, 100, 115, 200, 0),
    target_schedule_available = c(TRUE, TRUE, TRUE, TRUE, FALSE),
    additional_sections = c(2L, 1L, 0L, 0L, NA),
    target_registration_observed = FALSE, target_registered_now = NA_real_,
    accuracy = "High", accuracy_value = "5.0% off",
    # SPARE 1's Low rating was set by its seats, so it displays grey.
    reliability_tone = c("High", "High", "High", "neutral", "High"),
    reliability_label = c(rep("5.0% off", 3), "5.0% off · set by seats", "5.0% off"),
    seat_consistency = "High", seat_consistency_value = "seats moved in 0 of 4",
    # Last year's registrations, and whether last year was near full: DAY 1
    # and SPARE 1 were, so the draft's seats have their own answer there.
    observed_baseline = c(96, 100, 100, 100, 100),
    adjusted_saturated_prior = c(TRUE, FALSE, NA, TRUE, TRUE)
  )
  components <- tibble::tibble(
    market_id = "abq_ea_course_market", subject_course = "DAY 1",
    campus = c("ABQ", "EA"), part_term = "1", scheduled_sections = c(1L, 1L)
  )
  # Last year's seats: DAY 1 had 80 (1.2 registrations per seat), SPARE 1 had
  # 100; the rest are not needed, and MISSING 1 has no history row at all.
  history <- tibble::tibble(
    market_id = "abq_ea_course_market",
    subject_course = c("DAY 1", "DAY 1", "PLAN 1", "COVER 1", "SPARE 1"),
    recency_rank = c(1L, 2L, 1L, 1L, 1L),
    scheduled_capacity = c(80, 70, 90, 110, 100)
  )
  view <- list(
    projections = projections, delivery_components = components,
    history = history,
    meta = list(target_schedule_as_of = as.Date("2026-10-08"),
                target_term_label = "Spring 2027")
  )
  draft <- build_enrollment_projection_draft_comparison(view)
  table <- draft$table

  # If the draft's seats fill as last year's did: DAY 1's 60 seats at 1.2 per
  # seat hold 72; SPARE 1's 200 at 1.0 hold 200. A course that had seats to
  # spare (PLAN 1), one whose fill is unknown (COVER 1) and one not in the
  # draft (MISSING 1) get no such number: their registrations did not follow
  # their seats, or there are no seats to follow.
  expect_equal(table$if_seats_fill[table$course == "DAY 1"], 72)
  expect_equal(table$if_seats_fill[table$course == "SPARE 1"], 200)
  expect_true(all(is.na(table$if_seats_fill[table$course %in% c("PLAN 1", "COVER 1", "MISSING 1")])))
  expect_match(draft$sentence, paste0(
    " For the 2 courses near full last year, the draft's seats would hold ",
    "about 272 registrations if they fill as last year's did, against 220 ",
    "planned\\.$"
  ))
  # modifyList() would merge a tibble's columns into the old one; replace it.
  no_seats <- view
  no_seats$history <- dplyr::select(history, -scheduled_capacity)
  expect_error(build_enrollment_projection_draft_comparison(no_seats), "scheduled_capacity")

  expect_true(draft$available)
  expect_equal(table$course, c("DAY 1", "PLAN 1", "MISSING 1", "COVER 1", "SPARE 1"))
  expect_equal(table$status,
               c("short_day_one", "short_plan", "not_in_draft", "covers", "spare"))
  expect_equal(
    table$verdict[[1]],
    "Short of day-one seats by 30 (1 section); 50 short of the plan (2 sections)"
  )
  expect_equal(table$verdict[[2]], "Covers day one; 10 short of the plan (1 section)")
  expect_equal(table$verdict[[4]], "Covers the plan, 5 to spare")
  expect_equal(table$verdict[[5]], "90 seats beyond the plan")
  # Draft seats less the plan: negative is short.
  expect_equal(table$draft_vs_plan, c(-50, -10, NA, 5, 90))
  expect_equal(table$campus_sections[[1]], "ABQ 1 \u00b7 EA 1")
  expect_match(draft$sentence, "^The draft schedule \\(pulled October 8, 2026\\) has 475 seats in 4 of the 5 courses shown")
  expect_match(draft$sentence, "1 course is short of the students expected on day one \\(by 30 seats\\)")
  expect_match(draft$sentence, "1 monitored course is not in the draft\\.")
  # One course takes a singular verb.
  expect_match(draft$sentence, paste0(
    "; 1 covers day one but not the plan; 1 covers the plan; 1 has more than ",
    "a section to spare\\."
  ))
  # The ratings travel with the numbers behind them, and with the table's
  # display of them.
  expect_equal(unique(table$reliability_value), "5.0% off")
  expect_equal(unique(table$seat_consistency_value), "seats moved in 0 of 4")
  expect_equal(table$reliability_tone[table$course == "SPARE 1"], "neutral")
  expect_equal(table$reliability_label[table$course == "SPARE 1"], "5.0% off · set by seats")
  expect_equal(table$reliability_label[table$course == "DAY 1"], "5.0% off")

  # No schedule for the target term: says so instead of an empty table.
  none <- build_enrollment_projection_draft_comparison(list(
    projections = dplyr::mutate(projections, target_schedule_available = FALSE),
    delivery_components = components[0, ], history = history,
    meta = list(target_schedule_as_of = as.Date(NA), target_term_label = "Spring 2027")
  ))
  expect_false(none$available)
  expect_match(none$sentence, "^No schedule for Spring 2027 is in the data yet")
  expect_true(all(is.na(none$table$if_seats_fill)))
})

test_that("reliability reads grey 'set by seats' when the schedule set the past numbers", {
  shown <- projection_reliability_display(
    accuracy = c("Low", "Moderate", "Low", "High", "Unrated", "Moderate"),
    accuracy_value = c("32.8% off", "15.0% off", "25.0% off", "4.0% off", "Unrated", "12.0% off"),
    miss_cause = c("seats", "seats", "forecast", "seats", NA, "unknown")
  )
  # Low or Moderate with the schedule's miss: neutral, labelled. A close
  # forecast stays High whatever the seats did; the forecast's own miss and
  # an unknown cause keep their rating colour.
  expect_equal(shown$reliability_tone,
               c("neutral", "neutral", "Low", "High", "Unrated", "Moderate"))
  expect_equal(shown$reliability_label,
               c("32.8% off · set by seats", "15.0% off · set by seats",
                 "25.0% off", "4.0% off", "Unrated", "12.0% off"))

  bundle <- projection_fixture_bundle(202110L, 202080L, 202080L)
  view <- build_enrollment_projection_view(bundle, list(group_id = "all_saved"))
  expect_true(all(c("reliability_tone", "reliability_label") %in% names(view$table)))
  expect_equal(view$meta$n_bundle_rows, nrow(bundle$projections))
  expect_gte(view$meta$n_bundle_rows, view$meta$n_rows)
  # The designed class lists are dated, so no recent term is undated.
  expect_equal(view$meta$undated_terms, character(0))
  expect_match(view$meta$track_record$headline, "^(Past .*forecasts were|No past forecasts)")
})

test_that("a recent term with no first-day count for any course is named, not shown as dashes", {
  history <- tibble::tibble(
    history_term = c(202310L, 202310L, 202410L, 202410L, 202510L, 202510L),
    history_term_label = rep(c("Spring 2023", "Spring 2024", "Spring 2025"), each = 2L),
    subject_course = rep(c("A 1", "B 1"), 3L),
    actual_first_day = c(90, 80, NA, NA, NA, 75),
    actual_classlist_total = c(100, 90, 110, 95, 0, 80)
  )
  # Spring 2024: both courses offered, neither first day known. Spring 2025:
  # A 1 was not offered (no students), B 1's first day is known, so the term
  # is not undated. Spring 2023 is complete.
  expect_equal(projection_undated_history_terms(history), "Spring 2024")
  expect_equal(projection_undated_history_terms(history[0, ]), character(0))
  expect_error(projection_undated_history_terms(dplyr::select(history, -actual_first_day)),
               "actual_first_day")
})

test_that("the ledger of ideas tried is complete and in the page's words", {
  ledger <- enrollment_projection_attempts_ledger()
  expect_equal(names(ledger), c("idea", "result", "status"))
  expect_gte(nrow(ledger), 10L)
  expect_false(any(is.na(ledger) | ledger == ""))
  # The one idea the rules forbid and the one that is next are both listed,
  # so a reader finds them before asking.
  expect_true(any(grepl("schedule's seats as the forecast", ledger$idea)))
  expect_true(any(ledger$status == "Next"))
})

# Reader-facing text says last year's registrations, the students still
# waiting, a change, a sharp change, and a count that stopped at its seats;
# the model's internal names are for the code. Checked on the sentence-like
# string literals (those with a space) of the page's files, comments aside.
test_that("the projections page carries no model jargon in its text", {
  jargon <- "\\b(spine|floor|delta|deltas|regime|aftcast|aftcasts|saturated|saturation|capped)\\b"
  files <- c(
    "R/modules/enrollment-projections.R",
    "R/lists/enrollment_projection_groups.R"
  )
  for (file in files) {
    lines <- readLines(file.path(cedar_base_dir, file), warn = FALSE)
    lines <- lines[!grepl("^\\s*#", lines)]
    strings <- unlist(regmatches(lines, gregexpr('"[^"]*\\s[^"]*"', lines)))
    hits <- strings[grepl(jargon, strings, ignore.case = TRUE)]
    expect_equal(hits, character(0), info = file)
  }
})

test_that("the bundle validator rejects a plan that is not its projection plus its adjustments", {
  rows <- tibble::tibble(
    term_type = "spring", method_id = "seasonal_last",
    projected_classlist_total = c(100, NA), pressure_bump = c(10, 0),
    plan_feeder_adjustment = c(-15, 0),
    pressure_bump_applied = c(TRUE, FALSE), planned_registrations = c(95, NA),
    reference_section_size = 25, recommended_sections = c(4L, NA)
  )
  expect_silent(validate_pressure_bump_rows(rows, "spring", "test"))
  message <- "not its projection plus its feeder adjustment plus its pressure bump"
  expect_error(validate_pressure_bump_rows(
    dplyr::mutate(rows, planned_registrations = c(110, NA),
                  recommended_sections = c(5L, NA)), "spring", "test"
  ), message)
  # The published adjusted candidate already carries the deltas.
  expect_error(validate_pressure_bump_rows(
    dplyr::mutate(rows, method_id = "spine_adjusted"), "spring", "test"
  ), message)
  expect_error(validate_pressure_bump_rows(
    dplyr::mutate(rows, recommended_sections = c(5L, NA)), "spring", "test"
  ), message)
  expect_error(validate_pressure_bump_rows(
    dplyr::mutate(rows, pressure_bump_applied = c(FALSE, FALSE)), "spring", "test"
  ), message)
  # A Fall plan does not follow its feeders unless the model says it does.
  fall <- dplyr::mutate(rows, term_type = "fall")
  expect_error(validate_pressure_bump_rows(fall, "spring", "test"), message)
  expect_silent(validate_pressure_bump_rows(fall, c("spring", "fall"), "test"))
  expect_error(validate_pressure_bump_rows(rows, NULL, "test"), "plan_feeder_seasons")
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
  expect_match(screen$inclusion_reason, "0 of 3 recent fall terms with first-day enrollment")

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
  expect_match(result$capacity_limit_status, "Seat ceiling likely")

  # Before registration opens there is no active fill to quote; the saved
  # note once read "active registration fill is NA".
  unopened <- inputs
  unopened$target_registration_snapshot <- inputs$target_registration_snapshot[0, ]
  early <- get_course_enrollment_projections(
    unopened, 202480L, force_courses = "TEST 101",
    opt = list(projection_methods = "seasonal_last")
  )$projections
  expect_true(is.na(early$target_active_fill))
  expect_equal(early$capacity_limit_note, "Planned registrations exceed capacity by 100")
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

# ---- The spine / floor / delta model -------------------------------------------
#
# One designed scenario, TEST 201, reused by the floor, delta, and regime tests:
#   Springs 2022 and 2023 enrolled 20 and 24 (the spine for Spring 2024 is 24).
#   Falls 2021 to 2023 enrolled 8, 8, 12 in the course itself.
#   FEED 1 enrolled 10, 10, 20 students in those Falls; half of each Fall's
#   FEED 1 students took TEST 201 the following Spring, and a quarter of each
#   Fall's TEST 201 students took it again.
# With `sequence = TRUE`, SEQ 1 is the course taken just before: 8, 8 and 4
#   students in those Falls, half of each of the first two taking TEST 201 the
#   next Spring. Two of Fall 2023's four also took FEED 1.
projection_spine_scenario <- function(spring_capacity = 30, waitlisted = 0L,
                                      sequence = FALSE) {
  springs <- projection_test_history(
    c(20, 24), terms = c(202210L, 202310L), course = "TEST 201"
  ) %>% dplyr::mutate(term_type = "spring")
  falls <- projection_test_history(
    c(8, 8, 12), terms = c(202180L, 202280L, 202380L), course = "TEST 201"
  )
  ids <- function(prefix, n) paste0(prefix, seq_len(n))
  roster <- function(term, course, students) {
    tibble::tibble(student_id = students, term = term, subject_course = course)
  }
  # BIG 1 is the market's large course: 100 students each Fall, of whom two
  # take TEST 201 next Spring. By count it out-feeds FEED 1 over the two pairs
  # (4 transitions against FEED 1's 10 would both have passed the old
  # threshold of 3); by lift it is nothing like a prerequisite (0.02 against
  # the market's 0.064, lift 0.3), where FEED 1's half is lift 7.9.
  enrollments <- dplyr::bind_rows(
    roster(202180L, "FEED 1", ids("f", 10)), roster(202180L, "TEST 201", ids("r", 4)),
    roster(202180L, "BIG 1", ids("b", 100)),
    roster(202210L, "TEST 201", c(ids("f", 5), "r1", ids("x", 12), "b1", "b2")),
    roster(202280L, "FEED 1", ids("g", 10)), roster(202280L, "TEST 201", ids("s", 4)),
    roster(202280L, "BIG 1", ids("c", 100)),
    roster(202310L, "TEST 201", c(ids("g", 5), "s1", ids("y", 16), "c1", "c2")),
    roster(202380L, "FEED 1", ids("h", 20)), roster(202380L, "TEST 201", ids("t", 12)),
    roster(202380L, "BIG 1", ids("d", 100)),
    if (sequence) dplyr::bind_rows(
      roster(202180L, "SEQ 1", ids("q", 8)), roster(202210L, "TEST 201", ids("q", 4)),
      roster(202280L, "SEQ 1", ids("p", 8)), roster(202310L, "TEST 201", ids("p", 4)),
      roster(202380L, "SEQ 1", ids("u", 4)), roster(202380L, "FEED 1", ids("u", 2))
    )
  )
  sections <- tibble::tibble(
    market_id = "abq_ea_course_market", college = "AS", department = "TEST",
    course_title = "Test Course", subject_course = "TEST 201",
    term = c(202210L, 202310L), term_type = "spring",
    scheduled_sections = 1L, scheduled_enrl = c(20, 24),
    scheduled_capacity = c(30, spring_capacity), n_delivery_components = 1L,
    n_campuses = 1L, capacity_per_section = c(30, spring_capacity)
  )
  waitlists <- tibble::tibble(
    market_id = "abq_ea_course_market", subject_course = "TEST 201",
    term = 202310L, waitlisted = as.integer(waitlisted)
  )
  list(
    enrollment_history = springs,
    preceding_term_history = dplyr::bind_rows(springs, falls),
    section_history = sections,
    waitlist_history = waitlists,
    students = list(
      course_enrollments = enrollments,
      target_students = enrollments %>% dplyr::filter(subject_course == "TEST 201"),
      student_terms = tibble::tibble(
        student_id = character(), term = integer(), major_code = character(),
        student_classification = character()
      )
    ),
    row = projection_test_row("TEST 201") %>%
      dplyr::mutate(term_type = "spring", target_term = 202410L)
  )
}

# The scenario's feeders carry 5 students a pair, so these tests lower the
# transition floor from the default 20; the lift rule is the default.
projection_scenario_opt <- function(...) list(feeder_min_students = 3L, ...)

test_that("Fall deltas scale enrollment changes by the historical carry-through", {
  s <- projection_spine_scenario()
  result <- project_spine_adjusted(
    s$enrollment_history, s$preceding_term_history, s$section_history,
    s$waitlist_history, s$students, s$row, 202410L,
    opt = projection_scenario_opt()
  )

  expect_true(result$applicable)
  expect_equal(result$spine, 24)
  expect_equal(result$spine_term, 202310L)
  expect_false(result$saturated_prior)
  expect_equal(result$floor_uplift, 0)
  # Repeat: Fall 2023 enrolled 12 against 8 the year before, and a quarter of
  # Fall enrollees historically took the course again: (12 - 8) x 0.25 = 1.
  expect_equal(result$repeat_rate, 0.25)
  expect_equal(result$delta_repeat, 1)
  # Feeder: FEED 1 enrolled 20 against 10, and half carried in: 10 x 0.5 = 5.
  expect_equal(result$feeder_courses, "FEED 1")
  expect_equal(result$feeder_rate, 0.5)
  expect_equal(result$feeder_change, 10)
  expect_equal(result$delta_feeder, 5)
  expect_equal(result$projected_classlist_total, 30)
  # +50% in the course's own Fall enrollment trips the regime check.
  expect_equal(result$preceding_term_change, 0.5)
  expect_true(result$regime_alarm)
  expect_match(result$component_summary, "feeders \\(FEED 1 7\\.9x the market's 0\\.064\\)")
  expect_true(validate_spine_rows(
    result %>% dplyr::mutate(target_term = 202410L), "fixture"
  ))

  # Two steps out the preceding term is unobserved: the spine stands alone and
  # the row says why, rather than guessing a delta.
  far <- project_spine_adjusted(
    s$enrollment_history, s$preceding_term_history, s$section_history,
    s$waitlist_history, s$students, s$row, 202510L,
    opt = projection_scenario_opt()
  )
  expect_true(far$applicable)
  expect_equal(far$delta_repeat, 0)
  expect_equal(far$delta_feeder, 0)
  expect_match(far$delta_basis, "Fall 2024 is not observed yet")
  expect_true(is.na(far$regime_alarm))
})

# Model 0.30.0: a pooled feeder earns its place by lift (its students take
# the course next at feeder_min_lift times the market's rate), so a large
# course whose students mostly go elsewhere is not a feeder however many it
# sends; the feeders kept are still ranked by transitions. The evidence is in
# forecasting-lessons.md ("Feeders ranked by lift").
test_that("a feeder earns its place by lift, not by size", {
  s <- projection_spine_scenario()
  run <- function(...) project_spine_adjusted(
    s$enrollment_history, s$preceding_term_history, s$section_history,
    s$waitlist_history, s$students, s$row, 202410L,
    opt = projection_scenario_opt(...)
  )

  # The defaults: lift 3 over the market, 20 transitions, four feeders.
  defaults <- enrollment_projection_defaults()
  expect_equal(defaults$feeder_min_lift, 3)
  expect_equal(defaults$feeder_min_students, 20L)
  expect_equal(defaults$feeder_max_courses, 4L)

  # BIG 1 has 4 transitions to FEED 1's 10 and would have been a feeder by
  # count; at lift 0.3 it is not one. The market rate is 14 of the 220
  # non-TEST 201 student-pairs.
  result <- run()
  expect_equal(result$feeder_courses, "FEED 1")
  expect_equal(result$feeder_base_rate, 14 / 220)
  expect_equal(result$feeder_lifts, "FEED 1 7.9x")
  expect_equal(result$feeder_rate, 0.5)
  expect_equal(result$delta_feeder, 5)

  # At the lowest lift the configuration allows, 1, BIG 1 is still out: its
  # students take the course less often than the market does.
  at_one <- run(feeder_min_lift = 1)
  expect_equal(at_one$feeder_courses, "FEED 1")
  # Raised past FEED 1's 7.9, the rule keeps nothing.

  # A lift nothing reaches leaves the course with no feeders, said plainly.
  none <- run(feeder_min_lift = 10)
  expect_true(is.na(none$feeder_courses))
  expect_true(is.na(none$feeder_lifts))
  expect_equal(none$delta_feeder, 0)
  expect_equal(none$feeder_check, "no_feeders")
  expect_match(none$delta_basis, "feeders: none met the evidence threshold")

  # The lift and the market rate travel to the published row.
  pairing <- projection_method_pairing(
    dplyr::bind_rows(
      result %>% dplyr::mutate(
        market_id = "abq_ea_course_market", subject_course = "TEST 201",
        term_type = "spring", target_term = 202410L, wape = NA_real_,
        n_backtests = 0L
      )
    )
  )
  expect_equal(pairing$adjusted_feeder_lifts, "FEED 1 7.9x")
  expect_equal(pairing$adjusted_feeder_base_rate, 14 / 220)

  # A lift under 1 is refused as configuration.
  expect_error(enrollment_projection_model_config(list(feeder_min_lift = 0.5)),
               "feeder_min_lift must be a number of at least 1")
})

# A change that rounds to nothing read "-0%" in the regime note and "repeat -0"
# in the text preview.
test_that("signed changes that round to nothing read 0, never -0 or +0", {
  expect_equal(projection_signed_whole(c(-0.4, 0.4, 3.2, -7.6)), c("0", "0", "+3", "-8"))
  expect_equal(projection_signed_percent(c(-0.004, 0.25, -0.12)), c("0%", "+25%", "-12%"))
})

test_that("the students left waiting in the term just finished are context, never added", {
  # The scenario's class lists cover Fall 2023, the term before the Spring
  # 2024 target, but keep no waitlist row in it: who was left waiting then is
  # unknown (NA), not zero, as in every term before waitlist rows were kept.
  s <- projection_spine_scenario()
  run <- function(waitlists, target = 202410L) project_spine_adjusted(
    s$enrollment_history, s$preceding_term_history, s$section_history,
    waitlists, s$students, s$row, target, opt = projection_scenario_opt()
  )
  base <- run(s$waitlist_history)
  expect_true(is.na(base$waitlisted_preceding))

  # Another monitored course kept waiting students in Fall 2023, so the term
  # retained its waitlists and this course had none.
  other <- dplyr::bind_rows(s$waitlist_history, tibble::tibble(
    market_id = "abq_ea_course_market", subject_course = "OTHER 1",
    term = 202380L, waitlisted = 4L
  ))
  expect_identical(run(other)$waitlisted_preceding, 0L)

  # Nine waited for this course in Fall 2023. The forecast does not move.
  own <- dplyr::bind_rows(other, tibble::tibble(
    market_id = "abq_ea_course_market", subject_course = "TEST 201",
    term = 202380L, waitlisted = 9L
  ))
  waiting <- run(own)
  expect_identical(waiting$waitlisted_preceding, 9L)
  expect_equal(waiting$projected_classlist_total, base$projected_classlist_total)

  # Two steps out, Fall 2024 is not observed: unknown, whatever was retained.
  expect_true(is.na(run(own, target = 202510L)$waitlisted_preceding))
})

test_that("a listed sequence carries its own change and leaves the pooled feeders", {
  s <- projection_spine_scenario(sequence = TRUE)
  sequences <- tibble::tibble(from_course = "SEQ 1", to_course = "TEST 201")
  result <- project_spine_adjusted(
    s$enrollment_history, s$preceding_term_history, s$section_history,
    s$waitlist_history, s$students, s$row, 202410L,
    opt = projection_scenario_opt(sequences = sequences)
  )

  # SEQ 1: half of each earlier Fall's students took TEST 201 next Spring,
  # and Fall 2023 had 4 against 8: (4 - 8) x 0.5 = -2.
  expect_equal(result$sequence_courses, "SEQ 1")
  expect_equal(result$sequence_change, -4)
  expect_equal(result$delta_sequence, -2)
  # SEQ 1's students are out of the pooled feeders, so SEQ 1 is not one and
  # the two who also took FEED 1 in Fall 2023 count once, under SEQ 1:
  # FEED 1 is 20 against 10, x 0.5 = 5, exactly as without the sequence.
  expect_equal(result$feeder_courses, "FEED 1")
  expect_equal(result$feeder_rate, 0.5)
  expect_equal(result$feeder_change, 10)
  expect_equal(result$delta_feeder, 5)
  # 24 + repeat 1 - sequence 2 + feeder 5.
  expect_equal(result$projected_classlist_total, 28)
  expect_match(result$delta_basis, "taken just before, SEQ 1: \\(4 - 8\\) x 0\\.5 = -2\\.0")
  expect_true(validate_spine_rows(
    result %>% dplyr::mutate(target_term = 202410L), "fixture"
  ))

  # Unlisted, SEQ 1 is just another feeder, pooled with FEED 1.
  pooled <- project_spine_adjusted(
    s$enrollment_history, s$preceding_term_history, s$section_history,
    s$waitlist_history, s$students, s$row, 202410L,
    opt = projection_scenario_opt(sequences = sequences[0, ])
  )
  expect_true(is.na(pooled$sequence_courses))
  expect_equal(pooled$delta_sequence, 0)
  expect_equal(pooled$feeder_courses, "FEED 1, SEQ 1")
})

# ISSUES.md I28: a pending session's begun count is a lower bound, so it may
# settle that a threshold was reached but never that it was not, and an
# undated term has no bound at all.
test_that("a first day still pending is judged only when its begun sessions already reach the threshold", {
  judged <- projection_judged_first_day(
    first_day = c(95, NA, NA, NA, NA),
    started = c(95, 95, 80, 95, 95),
    basis = c("complete", "sessions_pending", "sessions_pending", "undated", "sessions_pending"),
    capacity = c(100, 100, 100, 100, NA),
    threshold = .9
  )
  expect_equal(judged, c(95, 95, NA, NA, NA))
})

# EC-11's SOCI 100 at Fall 2020 is taught on two campuses: ABQ in a full-term
# and a first-half session (107 + 28 on the first day, 200 seats) and EA
# (58 of 100). Pooled, the market reads 193 of 300; each campus keeps its own.
campus_history_scaffold <- function(history_term) tibble::tibble(
  market_id = "abq_ea_course_market", subject_course = "SOCI 100",
  projection_target_term = 202180L, history_term = history_term,
  recency_rank = 1L
)

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

test_that("a prior term full on the first day adds its unserved waitlist to the spine", {
  # Spring 2023: 24 students registered. Four dropped before classes began, so
  # 20 of 22 seats were held on the first day (90.9%, over the 90% line); one
  # more dropped in week one, so census read 19 (86%) and a census rule would
  # call the term unsaturated. Three students were still waiting at close and
  # never held a seat. Demand was at least 24 + 3 = 27. First day plus the
  # waitlist is 23, below the ever-registered spine, so a floor built that way
  # lets the early-drop churn absorb the waitlist (ISSUES.md I27).
  s <- projection_spine_scenario(spring_capacity = 22, waitlisted = 3L)
  s$enrollment_history <- dplyr::mutate(
    s$enrollment_history,
    registered = dplyr::if_else(term == 202310L, 19, registered),
    dr_early = dplyr::if_else(term == 202310L, 5, dr_early),
    first_day_enrl = dplyr::if_else(term == 202310L, 20, first_day_enrl),
    census_enrl = dplyr::if_else(term == 202310L, 19, census_enrl)
  )
  result <- project_spine_adjusted(
    s$enrollment_history, s$preceding_term_history, s$section_history,
    s$waitlist_history, s$students, s$row, 202410L,
    opt = projection_scenario_opt()
  )

  expect_equal(result$spine, 24)
  expect_true(result$saturated_prior)
  expect_equal(result$prior_first_day_fill, 20 / 22)
  expect_equal(result$waitlisted_prior, 3L)
  expect_equal(result$floor_uplift, 3)
  expect_match(result$floor_basis, "first-day fill 90.9%")
  expect_match(result$floor_basis, "last year's 24 \\+ 3 still waiting = 27")
  expect_equal(result$projected_classlist_total, 24 + 3 + 1 + 5)
  expect_true(validate_spine_rows(
    result %>% dplyr::mutate(target_term = 202410L), "fixture"
  ))

  # No reconstructable first day for the spine term: saturation is unknown,
  # and census is not consulted in its place.
  undated <- project_spine_adjusted(
    dplyr::mutate(s$enrollment_history, first_day_enrl = NA_real_),
    s$preceding_term_history, s$section_history,
    s$waitlist_history, s$students, s$row, 202410L
  )
  expect_true(is.na(undated$saturated_prior))
  expect_equal(undated$floor_uplift, 0)
  expect_match(undated$floor_basis, "Spring 2023's class lists carry no registration status dates")

  # Spring 2023's class list was pulled before a later session began (ISSUES.md
  # I28). The sessions that had begun seat 20 of all 22 seats, 90.9%: the true
  # fill can only be higher, so saturation is settled and the floor stands,
  # labelled as a lower bound. Seating 15 (68.2%) settles nothing, and the
  # reason names the pending session rather than missing dates.
  pending <- function(started) dplyr::mutate(
    s$enrollment_history,
    first_day_enrl = dplyr::if_else(term == 202310L, NA_real_, first_day_enrl),
    first_day_basis = dplyr::if_else(term == 202310L, "sessions_pending", first_day_basis),
    first_day_started_enrl = dplyr::if_else(term == 202310L, started, first_day_started_enrl)
  )
  settled <- project_spine_adjusted(
    pending(20), s$preceding_term_history, s$section_history,
    s$waitlist_history, s$students, s$row, 202410L
  )
  expect_true(settled$saturated_prior)
  expect_equal(settled$floor_uplift, 3)
  expect_match(settled$floor_basis,
               "first-day fill at least 90.9%, from the sessions that had begun")
  open <- project_spine_adjusted(
    pending(15), s$preceding_term_history, s$section_history,
    s$waitlist_history, s$students, s$row, 202410L
  )
  expect_true(is.na(open$saturated_prior))
  expect_equal(open$floor_uplift, 0)
  expect_match(open$floor_basis, "Some of Spring 2023's sessions had not begun")
  expect_match(open$floor_basis, "fill 68.2% of its seats")

  # Saturated with no waitlist rows retained: the spine is itself the floor.
  none <- project_spine_adjusted(
    s$enrollment_history, s$preceding_term_history, s$section_history,
    s$waitlist_history[0, ], s$students, s$row, 202410L
  )
  expect_true(none$saturated_prior)
  expect_equal(none$floor_uplift, 0)
  expect_match(none$floor_basis, "no waitlist rows retained")

  # No capacity for the spine term: saturation is unknown, never assumed.
  unknown <- project_spine_adjusted(
    s$enrollment_history, s$preceding_term_history, s$section_history[0, ],
    s$waitlist_history, s$students, s$row, 202410L
  )
  expect_true(is.na(unknown$saturated_prior))
  expect_match(unknown$floor_basis, "cannot be judged")
})

test_that("the spine audit trail must reconcile", {
  s <- projection_spine_scenario()
  result <- project_spine_adjusted(
    s$enrollment_history, s$preceding_term_history, s$section_history,
    s$waitlist_history, s$students, s$row, 202410L
  ) %>% dplyr::mutate(target_term = 202410L)
  broken <- dplyr::mutate(result, delta_feeder = delta_feeder + 1)
  expect_error(validate_spine_rows(broken, "fixture"), "spine / floor / delta")
  lowered <- dplyr::mutate(result, floor_uplift = -1,
                           projected_classlist_total = projected_classlist_total - 1)
  expect_error(validate_spine_rows(lowered, "fixture"), "spine / floor / delta")

  # The floor is the unserved waitlist, in the spine's own units. A saturated
  # row lifted by anything else fails even when its parts sum, and so does an
  # unsaturated row lifted at all.
  partial <- dplyr::mutate(result, saturated_prior = TRUE, waitlisted_prior = 3L,
                           floor_uplift = 1,
                           projected_classlist_total = projected_classlist_total + 1)
  expect_error(validate_spine_rows(partial, "fixture"), "spine / floor / delta")
  unsaturated <- dplyr::mutate(result, waitlisted_prior = 2L, floor_uplift = 2,
                               projected_classlist_total = projected_classlist_total + 2)
  expect_error(validate_spine_rows(unsaturated, "fixture"), "spine / floor / delta")
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
  expect_match(response$note, "90% of the added seats")

  thin <- projection_expansion_response(
    history, sections, 202410L, opt = list(expansion_min_pairs = 6L)
  )
  expect_true(is.na(thin$fill_rate))
  expect_match(thin$note, "Only 5")
})

# Full aftcast rows for one method, shaped exactly as
# backtest_course_projection_methods() produces them, so selection and its
# realised record can be exercised without running the whole engine.
projection_policy_backtests <- function(method_id, projected, actual,
                                        terms = seq(202080L, by = 100L,
                                                    length.out = length(projected)),
                                        first_day = actual, capacity = 2 * actual,
                                        course = "TEST 101",
                                        opt = list()) {
  # Resolved before tibble() so the column named method_id cannot mask the
  # argument inside the tibble mask.
  method_label <- unname(CEDAR_ENROLLMENT_PROJECTION_METHODS[[method_id]])
  method_role <- unname(CEDAR_ENROLLMENT_PROJECTION_METHOD_ROLES[[method_id]])
  tibble::tibble(
    market_id = "abq_ea_course_market", college = "AS",
    subject_course = course, term_type = "fall",
    target_term = terms, target_term_label = vapply(terms, fmt_term, character(1)),
    method_id = method_id,
    method_label = method_label,
    method_role = method_role,
    applicable = TRUE, applicability_reason = "test",
    projected_classlist_total = projected,
    first_day_retention_rate = 1, projected_first_day_equivalent = projected,
    actual_classlist_total = actual, actual_first_day = first_day,
    actual_census = first_day, actual_final_enrollment = first_day,
    scheduled_capacity = capacity
  ) %>%
    add_projection_capacity_censoring(opt) %>%
    dplyr::mutate(raw_projected_classlist_total = projected_classlist_total)
}

projection_policy_candidates <- function(method_ids, projections,
                                         course = "TEST 101") {
  row <- projection_test_row(course)
  dplyr::bind_rows(lapply(seq_along(method_ids), function(i) {
    projection_candidate(method_ids[[i]], projections[[i]], TRUE, "ok")
  })) %>%
    dplyr::mutate(
      market_id = row$market_id, college = row$college,
      subject_course = row$subject_course, term_type = row$term_type,
      target_term = row$target_term, .before = 1
    )
}

test_that("selection is rolling: a challenger wins only on earlier shared aftcasts, and accuracy is its realised record", {
  # Prior same-season misses by 10% every fold; the adjusted candidate misses
  # by 2%. Replayed honestly, it can only take over at the fourth fold, once
  # three earlier shared aftcasts exist, so the record a reader would have
  # lived through is 10%, 10%, 10%, 2% -- an 8% WAPE, not the in-sample 2%.
  backtests <- dplyr::bind_rows(
    projection_policy_backtests("seasonal_last", rep(110, 4), rep(100, 4)),
    projection_policy_backtests("spine_adjusted", rep(102, 4), rep(100, 4))
  )
  performance <- summarize_projection_backtests(backtests)
  candidates <- projection_policy_candidates(
    c("seasonal_last", "spine_adjusted"), c(120, 118)
  )

  selected <- select_projection_methods(candidates, performance, backtests)

  expect_equal(selected$method_id, "spine_adjusted")
  expect_equal(selected$selection_common_n, 4L)
  expect_match(selected$selection_reason,
               "adjusted beat Last year's registrations on 4 earlier terms both were made for")
  # Saved reasons are read on the page, so they speak plainly.
  expect_false(any(grepl("WAPE|aftcast", c(
    selected$selection_reason, selected$depth_reason, selected$accuracy_reason
  ), ignore.case = TRUE)))
  expect_equal(selected$n_backtests, 4L)
  expect_equal(selected$wape, 0.08)
  expect_equal(selected$selection_wape, 0.08)
  expect_equal(selected$selection_basis, "Rolling selection")
  expect_equal(selected$depth, "Deep")
  expect_equal(selected$accuracy, "High")
  expect_equal(selected$projected_classlist_total, 118)

  # The realised record names the method that was live at each fold.
  record <- attr(selected, "policy_record")
  expect_equal(
    record$method_id,
    c("seasonal_last", "seasonal_last", "seasonal_last", "spine_adjusted")
  )
  marked <- mark_projection_policy_backtests(backtests, record)
  expect_equal(sum(marked$policy_selected), 4L)
  expect_equal(
    marked$method_id[marked$policy_selected],
    c("seasonal_last", "seasonal_last", "seasonal_last", "spine_adjusted")
  )

  # Two shared folds would let it in a fold earlier; that is a config choice,
  # and the measured reason it is not the default is in the config comment.
  looser <- select_projection_methods(
    candidates, performance, backtests, list(selection_min_backtests = 2L)
  )
  expect_equal(looser$wape, 0.06)
})

test_that("a challenger inside the margin leaves the default in place", {
  backtests <- dplyr::bind_rows(
    projection_policy_backtests("seasonal_last", rep(110, 4), rep(100, 4)),
    projection_policy_backtests("spine_adjusted", rep(109, 4), rep(100, 4))
  )
  candidates <- projection_policy_candidates(
    c("seasonal_last", "spine_adjusted"), c(120, 118)
  )

  selected <- select_projection_methods(
    candidates, summarize_projection_backtests(backtests), backtests
  )

  expect_equal(selected$method_id, "seasonal_last")
  expect_true(is.na(selected$selection_common_n))
  expect_match(selected$selection_reason, "Last year's registrations is the default")
  expect_equal(selected$n_backtests, 4L)
  expect_equal(selected$wape, 0.10)
  expect_equal(selected$projection_low, 110)
  expect_equal(selected$projection_high, 130)
})

test_that("capacity-bounded fit retains fit confidence with a demand caveat", {
  # The first day filled the seats in three of four folds. Accuracy is still
  # the fit to what was observed; the caveat says so rather than downgrading it.
  backtests <- projection_policy_backtests(
    "seasonal_last", c(101, 99, 102, 98), rep(100, 4),
    first_day = c(100, 100, 100, 90), capacity = rep(100, 4)
  )
  candidates <- projection_policy_candidates("seasonal_last", 100)

  selected <- select_projection_methods(
    candidates, summarize_projection_backtests(backtests), backtests
  )

  expect_equal(selected$method_id, "seasonal_last")
  expect_true(selected$capacity_constrained_history)
  expect_equal(selected$n_capacity_reached, 3L)
  expect_equal(selected$accuracy, "High")
  expect_match(selected$accuracy_reason, "varying 1.8% term to term")

  explanation <- projection_axis_explanation(
    "Moderate", selected$depth, selected$accuracy,
    selected$n_backtests, selected$wape,
    history_terms = 5L, history_cv = 0.08,
    term_type = selected$term_type,
    pct_error_sd = selected$selection_pct_error_sd,
    capacity_constrained = selected$capacity_constrained_history,
    n_capacity_reached = selected$n_capacity_reached,
    n_capacity_unreached = selected$n_capacity_unreached,
    method_role = selected$method_role, methods_disagree = TRUE
  )
  expect_match(explanation, "3 of 4", fixed = TRUE)
  expect_match(explanation, "filled its seats on the first day", fixed = TRUE)
  expect_match(explanation, "not everyone who wanted it", fixed = TRUE)
  expect_match(explanation, "the two forecasts differ materially", fixed = TRUE)
})

test_that("variable term errors are reported without downgrading accuracy", {
  backtests <- projection_policy_backtests(
    "seasonal_last", c(103, 97, 105, 95), rep(100, 4)
  )
  candidate <- projection_policy_candidates("seasonal_last", 100)

  selected <- select_projection_methods(
    candidate, summarize_projection_backtests(backtests), backtests
  )

  # Accuracy is a WAPE statement. Term-to-term variation is surfaced in the
  # reason text rather than silently collapsing the rating.
  expect_equal(selected$accuracy, "High")
  expect_equal(selected$wape, 0.04)
  expect_match(selected$accuracy_reason, "varying 4.8% term to term")
})

test_that("backtests separate raw from registration-cap-censored accuracy", {
  backtests <- tibble::tibble(
    market_id = "abq_ea_course_market", college = "AS",
    subject_course = "TEST 101", term_type = "spring",
    target_term = c(202210L, 202310L),
    method_id = "spine_adjusted",
    method_label = "Prior same-season + floor + latest-term changes",
    applicable = TRUE, projected_classlist_total = c(150, 120),
    actual_classlist_total = c(100, 100),
    first_day_retention_rate = 1,
    projected_first_day_equivalent = c(150, 120),
    actual_first_day = c(100, 100),
    actual_census = c(100, 100),
    scheduled_capacity = c(100, 200),
    method_role = "observed_enrollment"
  )

  result <- summarize_projection_backtests(backtests)

  expect_equal(result$wape, 0.35)
  expect_equal(result$first_day_equivalent_wape, 0.35)
  expect_equal(result$capacity_censored_wape, 0.10)
  expect_equal(result$uncensored_wape, 0.20)
  expect_equal(result$n_capacity_reached, 1L)
  expect_equal(result$n_capacity_unreached, 1L)
  expect_equal(result$n_capacity_censored_misses, 1L)
  expect_equal(result$capacity_explained_wape, 0.25)
  expect_equal(result$capacity_explained_error_share, 5 / 7)
  expect_equal(result$capacity_censored_terms, "202210")
  expect_match(result$capacity_miss_assessment, "likely explains most")
  expect_equal(result$backtest_terms, "202210,202310")
  expect_equal(result$backtest_term_range, "Spring 2022 to Spring 2023")
})

test_that("signed aftcast diagnostics distinguish stable bias from WAPE", {
  result <- summarize_projection_backtests(projection_summary_backtests())

  expect_equal(result$wape, 0.10)
  expect_equal(result$weighted_bias, 0.10)
  expect_equal(result$direction_consistency, 1)
  expect_equal(result$pct_error_sd, 0)
  expect_match(result$signed_error_history, "Fall 2018: \\+10.0%")
})

test_that("rows with no applicable method remain explicit", {
  row <- projection_test_row()
  candidates <- projection_candidate("spine_adjusted") %>%
    dplyr::mutate(
      market_id = row$market_id, college = row$college,
      subject_course = row$subject_course,
      term_type = row$term_type, target_term = row$target_term,
      .before = 1
    )

  selected <- select_projection_methods(
    candidates, tibble::tibble(), tibble::tibble()
  )

  expect_equal(nrow(selected), 1)
  expect_equal(selected$method_id, "none")
  expect_true(is.na(selected$projected_classlist_total))
  expect_equal(selected$accuracy, "Unrated")
  expect_equal(selected$depth, "None")
  expect_match(selected$accuracy_reason, "No applicable")
})

test_that("cone preserves candidate provenance when backtests are empty", {
  row <- projection_test_row()
  inputs <- list(
    enrollment_history = projection_test_history(100, terms = 202380L),
    preceding_term_history = projection_test_history(100, terms = 202380L),
    waitlist_history = empty_projection_test_waitlists(),
    section_history = tibble::tibble(
      market_id = "abq_ea_course_market", college = "AS", department = "TEST",
      course_title = "Test Course", subject_course = "TEST 101",
      term = 202480L, term_type = "fall",
      scheduled_sections = 3L, scheduled_enrl = 0,
      scheduled_capacity = 120, n_delivery_components = 2L,
      n_campuses = 2L, capacity_per_section = 40
    ),
    students = list(
      target_students = tibble::tibble(
        student_id = character(), term = integer(), subject_course = character()
      ),
      student_terms = tibble::tibble(
        student_id = character(), term = integer(),
        major_code = character(), student_classification = character()
      )
    ),
    target_courses = "TEST 101",
    target_campuses = c("ABQ", "EA"),
    target_market_id = "abq_ea_course_market",
    enrollment_through_term = 202380L,
    delivery_components = empty_projection_test_components(),
    delivery_section_history = empty_projection_test_delivery_sections(),
    delivery_first_day = empty_projection_test_delivery_first_day()
  )

  analysis <- get_course_enrollment_projections(
    inputs, 202480L, scope_courses = "TEST 101", force_courses = "TEST 101"
  )

  expect_true(all(c("selected", "n_backtests", "wape") %in% names(analysis$candidates)))
  expect_true(any(analysis$candidates$selected))
  expect_true(all(is.na(analysis$candidates$n_backtests)))
})

test_that("pressure-only scopes can publish an explicit empty result", {
  inputs <- list(
    enrollment_history = projection_test_history(),
    preceding_term_history = projection_test_history(),
    waitlist_history = empty_projection_test_waitlists(),
    section_history = tibble::tibble(
      market_id = character(), college = character(), department = character(),
      course_title = character(), subject_course = character(), term = integer(),
      term_type = character(),
      scheduled_sections = integer(), scheduled_enrl = numeric(),
      scheduled_capacity = numeric(), n_delivery_components = integer(),
      n_campuses = integer(), capacity_per_section = numeric()
    ),
    students = list(),
    target_courses = "OTHER 101",
    target_campuses = c("ABQ", "EA"),
    target_market_id = "abq_ea_course_market",
    enrollment_through_term = 202380L,
    delivery_components = empty_projection_test_components(),
    delivery_section_history = empty_projection_test_delivery_sections(),
    delivery_first_day = empty_projection_test_delivery_first_day()
  )

  analysis <- get_course_enrollment_projections(
    inputs, 202480L, scope_courses = "OTHER 101"
  )
  bundle <- new_enrollment_projection_bundle(
    analysis, 202480L, 202380L,
    scope_courses = "OTHER 101", scope_campuses = c("ABQ", "EA"),
    scope_market_id = "abq_ea_course_market",
    model_provenance = enrollment_projection_model_provenance(),
    source_fingerprint = list(test = TRUE)
  )

  expect_equal(nrow(bundle$projections), 0)
  expect_equal(nrow(bundle$candidates), 0)
  expect_equal(nrow(bundle$pressure_screen), 1L)
  expect_equal(bundle$pressure_screen$subject_course, "OTHER 101")
  expect_false(bundle$pressure_screen$included)
  expect_true(all(c("method_id", "stability", "depth", "accuracy", "recommendation") %in%
                    names(bundle$projections)))
  expect_true(validate_enrollment_projection_bundle(bundle))
})

test_that("standalone feature builder runs without Shiny or global data", {
  settled_students <- test_students %>%
    dplyr::mutate(as_of_date = .cedar_term_start(term) + 30L)
  cl <- calc_cl_enrls(settled_students, by_part_term = TRUE)
  bundle <- build_enrollment_projection_bundle(
    cl_enrls = cl,
    sections = test_sections,
    students = settled_students,
    student_terms = test_student_terms,
    target_term = 202110L,
    as_of_term = 202080L,
    scope_courses = "MATH 1215Z",
    scope_campuses = "ABQ",
    scope_market_id = "abq_course_market",
    force_courses = "MATH 1215Z",
    opt = list(history_start_term = 202080L),
    built_at = as.POSIXct("2026-08-15 12:00:00", tz = "UTC")
  )

  expect_true(validate_enrollment_projection_bundle(bundle))
  expect_equal(bundle$target_term, 202110L)
  expect_equal(bundle$as_of_term, 202080L)
  expect_equal(bundle$scope_campuses, "ABQ")
  expect_equal(bundle$scope_market_id, "abq_course_market")
  expect_equal(bundle$model_config$saturation_fill_threshold, 0.90)
  expect_equal(bundle$model_config$selection_min_backtests, 3L)
  expect_equal(bundle$model_config$history_start_term, 202080L)
  expect_equal(
    bundle$model_provenance$model_version,
    CEDAR_ENROLLMENT_PROJECTION_MODEL_VERSION
  )
  expect_equal(
    bundle$model_provenance$schema_version,
    CEDAR_ENROLLMENT_PROJECTION_SCHEMA_VERSION
  )
  expect_true(nrow(bundle$pressure_screen) >= 1)
  expect_equal(nrow(bundle$projections), sum(bundle$pressure_screen$included))
  expect_equal(
    anyDuplicated(bundle$projections[c("market_id", "subject_course", "target_term")]),
    0L
  )
  expect_false("campus" %in% names(bundle$projections))
  expect_equal(
    nrow(bundle$projections),
    dplyr::n_distinct(bundle$projections$subject_course)
  )
  expect_true(all(bundle$delivery_components$campus == "ABQ"))
  expect_true(any(bundle$source_fingerprint$sections$last_term == 202110L))
  expect_lte(bundle$source_fingerprint$classlist_enrollments$last_term, 202110L)
  expect_true(all(bundle$candidates$target_term == 202110L))
  expect_true(all(c("selected", "n_backtests", "wape") %in% names(bundle$candidates)))
  expect_true(all(c(
    "observed_baseline", "adjusted_projection", "selection_common_n",
    "capacity_data_quality", "floor_note", "regime_note"
  ) %in% names(bundle$projections)))
})

test_that("projections follow a course across a former code (0.28.0, ADR-001 step 4)", {
  # MATH 1215Z's history before Spring 2021 listed as MATH 1215, the course id
  # kept: as a confirmed renumbering loads (attach_course_ids()). By course the
  # projection is the untouched data's; the former code changes nothing.
  settle <- function(students) {
    students %>% dplyr::mutate(
      as_of_date = .cedar_term_start(term) + 30L,
      registration_date = .cedar_term_start(term) + dplyr::if_else(
        registration_status_code %in% STATUS_DROP_LATE, 20L, -10L
      )
    )
  }
  relabel <- function(tbl) {
    old <- tbl$listed_code == "MATH 1215Z" & tbl$term < 202110L
    tbl$listed_code[old] <- "MATH 1215"
    tbl
  }
  build <- function(students, sections, cl_students = students, scope = "MATH 1215Z") {
    suppressMessages(build_enrollment_projection_bundle(
      cl_enrls = calc_cl_enrls(cl_students, by_part_term = TRUE),
      sections = sections, students = students, student_terms = test_student_terms,
      target_term = 202110L, as_of_term = 202080L,
      scope_courses = scope, scope_campuses = "ABQ",
      scope_market_id = "abq_course_market", force_courses = scope,
      opt = list(history_start_term = 201980L),
      built_at = as.POSIXct("2026-08-15 12:00:00", tz = "UTC")
    ))
  }
  students <- settle(test_students)
  original <- build(students, test_sections)
  renamed_students <- relabel(students)
  renamed_sections <- relabel(test_sections)
  scope <- enrollment_projection_course_scope(renamed_students, renamed_sections, "MATH 1215")
  expect_equal(scope$scope_courses, "MATH 1215Z")
  expect_null(scope$force_courses)
  renamed <- build(renamed_students, renamed_sections, scope = "MATH 1215")
  cols <- c("subject_course", "projected_classlist_total", "planned_registrations", "method_id")
  expect_equal(renamed$projections[, cols], original$projections[, cols])
  expect_equal(renamed$scope_courses, "MATH 1215Z")

  # Read by code (each code its own course), the relabelled history is another
  # course's and the projection loses it.
  by_code <- function(tbl) {
    tbl <- relabel(tbl)
    tbl$subject_course <- tbl$listed_code
    tbl$course_id <- tbl$listed_code
    tbl
  }
  split <- build(by_code(students), by_code(test_sections))
  expect_false(isTRUE(all.equal(split$projections[, cols], original$projections[, cols])))

  # A demand history counted by code is refused rather than read short.
  expect_error(build(renamed_students, renamed_sections, cl_students = by_code(students)),
               "counted by course code")
})

test_that("published projection builder accepts Fall and refuses Summer", {
  refuse <- function(target_term, as_of_term) {
    build_enrollment_projection_bundle(
      cl_enrls = tibble::tibble(), sections = tibble::tibble(),
      students = tibble::tibble(), target_term = target_term,
      as_of_term = as_of_term, scope_courses = "TEST 101",
      scope_campuses = "ABQ", scope_market_id = "abq_course_market"
    )
  }
  expect_error(refuse(202160L, 202110L), "Spring and Fall")
  # A Fall target clears the season guard and fails later, on the data edge.
  expect_error(refuse(202180L, 202110L), "non-empty students table")
})

test_that("a Fall target publishes through the same pipeline as Spring", {
  bundle <- projection_fixture_bundle(202080L, 202060L, 201980L)

  expect_true(validate_enrollment_projection_bundle(bundle))
  expect_equal(bundle$target_term, 202080L)
  expect_true(all(bundle$candidates$target_term == 202080L))
  # The adjusted candidate exists for a Fall target. With the fixtures' data
  # settled only through Summer 2020, the preceding term's enrollment history
  # cannot supply a carry-through rate, so it says which deltas it lacks
  # instead of failing the build or quietly disappearing.
  adjusted <- bundle$candidates %>% dplyr::filter(method_id == "spine_adjusted")
  expect_equal(nrow(adjusted), 1L)
  expect_true(all(c("floor_basis", "delta_basis") %in% names(adjusted)))
  expect_true(all(c("adjusted_projection", "floor_note", "regime_note") %in%
                    names(bundle$projections)))
})

# Course Dynamics > Projections shows one course's saved outlook per bundle,
# through the Projections page's own view, and says why a course has none
# rather than showing an empty panel.
test_that("Course Dynamics reads one course's outlook off the saved bundle and says why a course has none", {
  bundle <- projection_fixture_bundle(202080L, 202060L, 201980L)

  projected <- enrollment_projection_course_outlook(bundle, "MATH 1215Z")
  expect_equal(projected$status, "projected")
  expect_null(projected$sentence)
  expect_equal(projected$meta$target_term, 202080L)
  expect_equal(projected$detail$current$subject_course, "MATH 1215Z")
  # The same detail the Projections page opens for the course.
  page_detail <- enrollment_projection_course_detail(
    build_enrollment_projection_view(bundle, list(group_id = "all_saved")),
    "MATH 1215Z"
  )
  expect_equal(projected$detail$current, page_detail$current)
  expect_equal(projected$detail$plan_steps, page_detail$plan_steps)

  # Outside every monitored group: no detail, and the sentence says so.
  outside <- enrollment_projection_course_outlook(bundle, "ENGL 1110")
  expect_equal(outside$status, "out_of_scope")
  expect_null(outside$detail)
  expect_match(
    outside$sentence,
    "ENGL 1110 is not in the monitored course groups the Fall 2020 projections cover"
  )

  # Monitored, but left out by the saved pressure screen: its saved reason.
  screened <- bundle
  screened$scope_courses <- c(screened$scope_courses, "TEST 999")
  screened$pressure_screen <- dplyr::bind_rows(
    screened$pressure_screen,
    projection_test_row("TEST 999") %>%
      dplyr::mutate(
        market_id = bundle$scope_market_id, target_term = 202080L,
        # No delivery components for it, so no scheduled seats to reconcile.
        scheduled_sections = 0L, scheduled_capacity = 0,
        is_forced = FALSE, included = FALSE,
        inclusion_reason = "0 of 3 recent fall terms at or above 90% of scheduled capacity"
      )
  )
  expect_true(validate_enrollment_projection_bundle(screened))
  left_out <- enrollment_projection_course_outlook(screened, "TEST 999")
  expect_equal(left_out$status, "screened_out")
  expect_null(left_out$detail)
  expect_equal(
    left_out$sentence,
    paste(
      "TEST 999 is monitored but was not projected for Fall 2020.",
      "0 of 3 recent fall terms at or above 90% of scheduled capacity."
    )
  )

  # In scope with no saved row at all: said, never shown as an empty detail.
  unpublished <- bundle
  unpublished$scope_courses <- c(unpublished$scope_courses, "TEST 998")
  no_row <- enrollment_projection_course_outlook(unpublished, "TEST 998")
  expect_equal(no_row$status, "unpublished")
  expect_match(no_row$sentence, "holds no row for it")

  expect_error(enrollment_projection_course_outlook(bundle, NULL), "one subject_course")
  expect_error(
    enrollment_projection_course_outlook(bundle, c("MATH 1215Z", "ENGL 1110")),
    "one subject_course"
  )
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

test_that("feature builder rejects an unsettled source term", {
  unsettled_students <- test_students %>%
    dplyr::filter(term <= 202080L) %>%
    dplyr::mutate(
      as_of_date = dplyr::if_else(
        term == 202080L,
        .cedar_term_start(term) - 2L,
        .cedar_term_start(term) + 30L
      )
    )
  cl <- calc_cl_enrls(unsettled_students, by_part_term = TRUE)

  expect_error(
    build_enrollment_projection_bundle(
      cl_enrls = cl,
      sections = test_sections,
      students = unsettled_students,
      student_terms = test_student_terms,
      target_term = 202110L,
      as_of_term = 202080L,
      scope_courses = "MATH 1215Z",
      scope_campuses = "ABQ",
      scope_market_id = "abq_course_market",
      force_courses = "MATH 1215Z",
      opt = list(history_start_term = 202080L)
    ),
    "as_of_term 202080 is not settled"
  )
})

test_that("students left waiting in the term just finished are flagged from half a section and stated for every course", {
  # Four Spring 2027 rows with sections of 24: 12 and 11 left waiting in Fall
  # 2026, none, and a term that kept no waitlist rows.
  rows <- tibble::tibble(
    subject_course = c("A 1", "B 1", "C 1", "D 1"),
    target_term = 202710L, adjusted_preceding_term = 202680L,
    adjusted_waitlisted_preceding = c(12L, 11L, 0L, NA),
    adjusted_feeder_check = "measured", reference_section_size = 24
  )
  # Half a section of 24 is 12.
  expect_equal(projection_waiting_flags(rows, list()),
               c("12 left waiting in Fall 2026", NA, NA, NA))
  expect_equal(projection_waiting_flags(rows, list(preceding_waiting_flag_sections = 0.25)),
               c("12 left waiting in Fall 2026", "11 left waiting in Fall 2026", NA, NA))
  # Counts of different widths are not padded to the widest: format() on the
  # vector once gave " 12 left waiting" beside "101 left waiting".
  expect_equal(
    projection_waiting_flags(dplyr::mutate(rows, adjusted_waitlisted_preceding = c(1012L, 12L, 0L, NA)), list()),
    c("1,012 left waiting in Fall 2026", "12 left waiting in Fall 2026", NA, NA)
  )
  notes <- projection_waiting_notes(rows)
  expect_equal(notes[[1]], paste0(
    "12 students were left waiting in Fall 2026 on no class list for the ",
    "course. The plan does not add them: how many register in Spring 2027 ",
    "cannot be measured until its class lists arrive."
  ))
  expect_equal(notes[[3]], "No student was left waiting in Fall 2026.")
  expect_match(notes[[4]], "^Fall 2026 kept no waitlist rows")
  summary <- projection_preceding_waiting_summary(rows)
  expect_equal(summary$students, 23)
  expect_equal(summary$n_courses, 2L)
  expect_match(summary$sentence, "^In Fall 2026, 23 students were left waiting in 2 of the 4 courses shown")

  # A Fall target two steps out: Spring 2027 has not happened.
  ahead <- dplyr::mutate(
    rows, target_term = 202780L, adjusted_preceding_term = 202710L,
    adjusted_waitlisted_preceding = NA_integer_,
    adjusted_feeder_check = "term_not_observed"
  )
  unseen <- "Spring 2027 is not observed yet, so who it leaves waiting cannot be shown."
  expect_true(all(is.na(projection_waiting_flags(ahead, list()))))
  expect_equal(projection_waiting_notes(ahead)[[1]], unseen)
  expect_equal(projection_preceding_waiting_summary(ahead)$sentence, unseen)
})

test_that("the administrator summary says the decision in one sentence and flags why to look", {
  row <- tibble::tibble(
    subject_course = "TEST 101", term_type = "spring",
    projected_classlist_total = 2179, projected_first_day_equivalent = 2080,
    pressure_bump = 218, pressure_bump_applied = TRUE,
    pressure_bump_note = "Pressure bump +218: near full in every recent Spring",
    plan_feeder_adjustment = 0, planned_registrations = 2397,
    recommended_sections = 99L, observed_baseline = 2179,
    adjusted_saturated_prior = TRUE, adjusted_prior_first_day_fill = 0.988,
    adjusted_prior_first_day_basis = "complete", campus_fill_flag = NA_character_,
    waiting_flag = NA_character_,
    adjusted_waitlisted_prior = 15L, adjusted_regime_alarm = FALSE,
    adjusted_preceding_term = 202680L, adjusted_preceding_term_change = 0.02,
    stability = "Moderate", accuracy = "Moderate", wape = 0.1004,
    seat_consistency = "Unrated", miss_cause = NA_character_,
    methods_disagree = FALSE
  )
  sentence <- projection_summary_sentence(row)
  # The plan says how much of it is the pressure bump, and the first-day
  # seats are read off the projection, not the bumped plan.
  expect_match(sentence, paste0(
    "^Plan at least 99 sections for 2,397 registrations: 2,179 projected plus ",
    "a pressure bump of 218 \\(about 2,080 of the projected 2,179 in seats on ",
    "the first day\\)\\."
  ))
  expect_false(grepl("No pressure bump", sentence))

  # The feeder adjustment is stated beside the bump, either way.
  fed <- projection_summary_sentence(dplyr::mutate(
    row, plan_feeder_adjustment = -60, planned_registrations = 2337
  ))
  expect_match(fed, paste0(
    "^Plan at least 99 sections for 2,337 registrations: 2,179 projected, -60 ",
    "for the change in its feeder courses, plus a pressure bump of 218 "
  ))

  # A full course denied the bump says why.
  denied <- dplyr::mutate(
    row, pressure_bump = 0, pressure_bump_applied = FALSE,
    planned_registrations = 2179,
    pressure_bump_note = "No pressure bump: Spring 2026 filled 85.0% of its seats"
  )
  denied_sentence <- projection_summary_sentence(denied)
  expect_match(denied_sentence, "^Plan at least 99 sections for 2,179 registrations \\(about 2,080 in seats on the first day\\)\\.")
  expect_match(denied_sentence, "stopped at its seats and understates demand\\. No pressure bump: Spring 2026 filled 85\\.0% of its seats\\.")
  # The change is the forecast's, named as such: after "Plan ... for 2,397
  # registrations", "That is last year's level" read as though the plan were.
  expect_match(sentence, "The forecast matches last Spring's 2,179\\.")
  expect_false(grepl("That is", sentence))
  # One decimal: whole percents turned 98.8% into "99%" and read as full. A
  # capped count understates demand; it is no floor under this year's
  # (ISSUES.md I42).
  expect_match(sentence, paste0(
    "filled 98\\.8% of its seats on the first day with 15 students waiting, ",
    "so its count stopped at its seats and understates demand; the ",
    "pressure bump allows for that\\."
  ))
  expect_false(grepl("floor", sentence))
  # ISSUES.md I42: the term just finished can take a capped course below last
  # year's count, and the sentence says both. ENGL 1120, Spring 2027: 2,179
  # last Spring, Fall 2026's changes take it to 2,164, the bump adds 109. A
  # change under 1% keeps a decimal, so 2,164 against 2,179 is not "1%" off,
  # nor 716 against 719 (CHEM 1215) a match.
  lower <- projection_summary_sentence(dplyr::mutate(
    row, projected_classlist_total = 2164, pressure_bump = 109,
    planned_registrations = 2273, projected_first_day_equivalent = 2058
  ))
  expect_match(lower, paste0(
    "The forecast is 0.7% below last Spring's 2,179: the changes in Fall 2026 ",
    "point lower\\. Last Spring filled 98\\.8% .* stopped at its seats and ",
    "understates demand; the pressure bump allows for that\\."
  ))
  # The course's own error, as its plan step states it: a Moderate course at
  # 10.0% once read "averaged 10 to 20% off" above a step saying 10.0%.
  expect_match(sentence, "Past forecasts for this course missed by 10\\.0% on average\\.$")
  expect_false(grepl("10 to 20", sentence))
  expect_match(
    projection_summary_sentence(dplyr::mutate(row, accuracy = "Low", wape = 0.264)),
    "missed by 26\\.4% on average; treat it as a rough scale\\.$"
  )
  expect_match(
    projection_summary_sentence(dplyr::mutate(row, accuracy = "Unrated", wape = NA_real_)),
    "Too few past forecasts to say how reliable this is\\.$"
  )
  # A flag says what no column does. Last year's fill and its waiting
  # students are the Day-1 fill column, so a full course carries no flag:
  # when they were flags, 10 of the 11 monitored Spring 2027 courses had one.
  expect_equal(projection_flags(row), "")
  expect_equal(
    projection_flags(dplyr::mutate(row, campus_fill_flag = "EA full in Spring 2026, ABQ had room")),
    "EA full in Spring 2026, ABQ had room"
  )
  expect_error(projection_flags(dplyr::select(row, -campus_fill_flag)), "campus_fill_flag")
  expect_equal(
    projection_flags(dplyr::mutate(row, waiting_flag = "42 left waiting in Fall 2026")),
    "42 left waiting in Fall 2026"
  )
  expect_error(projection_flags(dplyr::select(row, -waiting_flag)), "waiting_flag")

  moved <- dplyr::mutate(
    row, adjusted_saturated_prior = FALSE, adjusted_waitlisted_prior = 0L,
    adjusted_regime_alarm = TRUE, adjusted_preceding_term_change = 0.91,
    projected_classlist_total = 2400, pressure_bump = 0,
    pressure_bump_applied = FALSE, planned_registrations = 2400,
    pressure_bump_note = "No pressure bump: Fall 2026 filled 80.0% of its seats",
    stability = "Volatile", accuracy = "Low"
  )
  expect_match(projection_summary_sentence(moved), "^Plan 99 sections")
  expect_match(projection_summary_sentence(moved), "The forecast is 10% above last Spring's 2,179\\.")
  expect_match(projection_summary_sentence(moved), "Fall 2026 moved \\+91%")
  # Far off as a full course's seats changed is the schedule's, so it is no
  # flag; far off with seats to spare is the forecast's own miss, which no
  # column says, so it is, whatever the seats did.
  expect_equal(projection_flags(moved), "Fall 2026 enrollment +91%")
  expect_equal(
    projection_flags(dplyr::mutate(moved, miss_cause = "seats")),
    "Fall 2026 enrollment +91%"
  )
  expect_equal(
    projection_flags(dplyr::mutate(moved, miss_cause = "forecast")),
    "Fall 2026 enrollment +91% | Off 20%+ with seats to spare"
  )
  expect_equal(
    projection_flags(dplyr::mutate(moved, miss_cause = "forecast", accuracy = "Moderate")),
    "Fall 2026 enrollment +91%"
  )
  # A Fall target read one step ahead compares against the Spring just
  # finished, and the flag names it (ISSUES.md I41).
  expect_equal(
    projection_flags(dplyr::mutate(moved, adjusted_preceding_term = 202710L)),
    "Spring 2027 enrollment +91%"
  )
  # A volatile history warns only when there is no track record to read.
  expect_equal(
    projection_flags(dplyr::mutate(moved, accuracy = "Unrated")),
    "Fall 2026 enrollment +91% | Hard to predict"
  )
  expect_equal(
    projection_flags(dplyr::mutate(moved, methods_disagree = TRUE, adjusted_regime_alarm = FALSE)),
    "Candidates disagree"
  )

  sparse <- dplyr::mutate(row, projected_classlist_total = NA_real_)
  expect_match(projection_summary_sentence(sparse), "^Not enough comparable history")
})

test_that("the Day-1 fill column names last year's fill, who waited, and why a fill is unknown", {
  # Five courses' saved fields, as the bundle holds them: an analytical frame,
  # not institutional data.
  rows <- tibble::tibble(
    spine_term = c(202610L, 202610L, 202610L, 202510L, 202610L),
    adjusted_saturated_prior = c(TRUE, TRUE, FALSE, NA, NA),
    adjusted_prior_first_day_fill = c(0.988, 0.93, 0.72, NA, NA),
    adjusted_prior_first_day_basis = c("complete", "complete", "complete",
                                       "undated", NA),
    adjusted_waitlisted_prior = c(15L, 0L, 0L, NA, NA)
  )
  fill <- projection_prior_fill(rows, header_term = 202610L)
  # 98.8% is full, not merely near full, and shown with one decimal: whole
  # percents turned it into "99%". The two levels are the seat-fill constants.
  expect_equal(fill$prior_fill_text,
               c("Full · 98.8%", "Near full · 93.0%", "72.0%", "Unknown", NA))
  # The table shows the number, with the level beneath it.
  expect_equal(fill$prior_fill_percent, c("98.8%", "93.0%", "72.0%", "Unknown", NA))
  expect_equal(fill$prior_fill_level, c("Full", "Near full", NA, NA, NA))
  expect_equal(fill$prior_fill_note, c("15 waiting", NA, NA, "no status dates", NA))
  expect_equal(fill$prior_fill, c(0.988, 0.93, 0.72, NA, NA))
  # A course starting from an older term than the header's says which.
  expect_equal(fill$prior_fill_term, c(NA, NA, NA, "Spring 2025", NA))
  expect_true(all(is.na(projection_prior_fill(rows)$prior_fill_term)))
  # Every recorded cause of an unknown fill is named (ISSUES.md I28).
  causes <- projection_prior_fill(dplyr::mutate(
    rows[c(4, 4, 4), ],
    adjusted_prior_first_day_basis = c("undated", "sessions_pending", "no_capacity")
  ))
  expect_equal(causes$prior_fill_note,
               c("no status dates", "a session had not begun", "no seat count"))
  expect_error(projection_prior_fill(dplyr::select(rows, -spine_term)), "spine_term")
})

test_that("each rating is shown as the number behind it", {
  rows <- tibble::tibble(
    stability = c("Moderate", "Unrated"), history_cv = c(0.157, NA),
    depth = c("Deep", "None"), n_backtests = c(4L, NA),
    accuracy = c("Moderate", "Unrated"), wape = c(0.10408922, NA),
    seat_consistency = c("Moderate", "Unrated"),
    seat_consistency_moves = c(1L, 0L), seat_consistency_terms = c(4L, 0L)
  )
  values <- projection_axis_values(rows)
  # The same 10.4% the summary sentence and plan steps state.
  expect_equal(values$accuracy_value, c("10.4% off", "Unrated"))
  expect_equal(values$seat_consistency_value, c("seats moved in 1 of 4", "Unrated"))
  expect_equal(values$stability_value, c("15.7% variation", "Unrated"))
  expect_equal(values$depth_value, c("4 past forecasts", "None"))
  expect_equal(projection_axis_values(rows[c(1, 1), ] %>%
                 dplyr::mutate(n_backtests = c(1L, 2L)))$depth_value,
               c("1 past forecast", "2 past forecasts"))
})

test_that("the page says which of the worst misses the schedule set and names the forecast's own", {
  config <- list(accuracy_fair_max_wape = 0.20)
  rows <- tibble::tibble(
    subject_course = c("ENGL 1110", "FYEX 1010", "FYEX 1110", "MATH 1220", "BIOL 1140"),
    accuracy = c("Low", "Low", "Low", "High", "Moderate"),
    miss_cause = c("seats", "seats", "forecast", "forecast", "seats")
  )
  expect_equal(
    projection_miss_sentence(rows, config),
    paste0(
      "3 of the 5 courses shown had past forecasts more than 20% off. For 2, ",
      "most of the miss came when the course was near full and its seats moved ",
      "the way of the miss or held, so the schedule set the number. For 1 ",
      "(FYEX 1110), the course had seats to spare or its seats moved against ",
      "the miss, so the miss was the forecast's own."
    )
  )
  # "None was the forecast's own" is the finding, so it is said.
  expect_match(projection_miss_sentence(rows[1:2, ], config),
               "^2 of the 2 courses shown .*\\. For all 2, most of the miss came .* None was the forecast's own\\.$")
  expect_match(
    projection_miss_sentence(dplyr::mutate(rows[1, ], miss_cause = NA), config),
    "None was the forecast's own\\. For 1, the seats or first day of those terms are not known\\.$"
  )
  # More than five of the forecast's own are counted, not listed.
  many <- tibble::tibble(subject_course = paste("C", 1:6), accuracy = "Low",
                         miss_cause = "forecast")
  expect_match(projection_miss_sentence(many, config),
               "For all 6, the course had seats to spare")
  expect_equal(projection_miss_sentence(rows[4:5, ], config),
               "None of the 2 courses shown has had past forecasts more than 20% off.")
  expect_equal(projection_miss_sentence(rows[4, ], config),
               "The course shown has not had past forecasts more than 20% off.")
  # The threshold is the model's, read live.
  expect_match(projection_miss_sentence(rows, list(accuracy_fair_max_wape = 0.25)), "more than 25% off")
  expect_error(projection_miss_sentence(rows, list()), "accuracy_fair_max_wape")
  expect_error(projection_miss_sentence(dplyr::select(rows, -miss_cause), config), "miss_cause")
})

test_that("a plan's steps add up from last year's class list to its sections", {
  # One published row as the view holds it: the function's input contract.
  # Spring 2027 target: 200 registered last Spring, 6 still waiting, Fall
  # changes of +3.4 (retakes), -6.8 (listed predecessor) and +1.2 (feeders),
  # so the adjusted forecast is round(200 + 6 - 2.2) = 204.
  row <- tibble::tibble(
    term_type = "spring", method_id = "spine_adjusted",
    spine = 200, spine_term = 202610L, floor_uplift = 6,
    delta_repeat = 3.4, delta_sequence = -6.8, delta_feeder = 1.2,
    adjusted_sequence_courses = "SEQ 1", adjusted_preceding_term = 202680L,
    projected_classlist_total = 204, accuracy = "High", wape = 0.068,
    n_backtests = 4L, backtest_term_range = "Spring 2023 to Spring 2026",
    plan_feeder_adjustment = 0, plan_feeder_note = "No feeder adjustment",
    pressure_bump = 10,
    pressure_bump_note = "Pressure bump +10: near full on the first day in every recent Spring",
    planned_registrations = 214, reference_section_size = 25,
    recommended_sections = 9L, scheduled_sections = 8L,
    target_schedule_available = TRUE
  )
  steps <- projection_plan_steps(row)

  expect_equal(steps$label, c(
    "Registered in Spring 2026", "Students still waiting",
    "Enrollment change in Fall 2026", "Forecast registrations",
    "Pressure bump", "Planned registrations", "Sections"
  ))
  expect_equal(steps$kind,
               c("start", "add", "add", "total", "add", "total", "sections"))
  # The arithmetic reads down: each total is the lines above it.
  forecast <- which(steps$label == "Forecast registrations")
  expect_equal(sum(steps$amount[1:(forecast - 1)]), steps$amount[[forecast]])
  planned <- which(steps$label == "Planned registrations")
  expect_equal(sum(steps$amount[forecast:(planned - 1)]), steps$amount[[planned]])
  # Rounded parts (+3, -7, +1) no longer sum to the change (-2), and say so.
  expect_equal(steps$detail[[3]], paste0(
    "students retaking this course +3; SEQ 1, taken just before \u22127; ",
    "other feeder courses +1 (each rounded)"
  ))
  expect_equal(steps$detail[[4]], paste0(
    "Past forecasts for this course missed by 6.8% on average ",
    "(4 terms, Spring 2023 to Spring 2026)"
  ))
  expect_equal(steps$detail[[5]], "Near full on the first day in every recent Spring")
  expect_equal(steps$detail[[7]], paste0(
    "214 registrations at 25.0 per section (the draft schedule's average), ",
    "rounded up; the draft schedule has 8 sections"
  ))

  # Last year's number with no additions: start, forecast, sections.
  plain <- projection_plan_steps(dplyr::mutate(
    row, method_id = "seasonal_last", projected_classlist_total = 200,
    pressure_bump = 0, planned_registrations = 200, recommended_sections = 8L
  ))
  expect_equal(plain$label,
               c("Registered in Spring 2026", "Forecast registrations", "Sections"))
  # Changes that cancel still show, so the adjusted method's work is visible.
  cancelled <- projection_plan_steps(dplyr::mutate(
    row, floor_uplift = 0, delta_repeat = 2, delta_sequence = -3,
    delta_feeder = 1, projected_classlist_total = 200
  ))
  expect_equal(cancelled$amount[cancelled$label == "Enrollment change in Fall 2026"], 0)
  expect_equal(nrow(projection_plan_steps(
    dplyr::mutate(row, projected_classlist_total = NA_real_)
  )), 0L)
  expect_error(projection_plan_steps(dplyr::select(row, -spine)), "spine")
})

test_that("the feeder summary says how many plans it moved, and why when none", {
  # Published rows as the view holds them: the function's input contract.
  rows <- tibble::tibble(
    term_type = "spring", projected_classlist_total = c(100, 200, 300, 400, NA),
    method_id = c("seasonal_last", "seasonal_last", "seasonal_last",
                  "spine_adjusted", "seasonal_last"),
    plan_feeder_adjustment = c(12, -30, -8, 0, 0),
    adjusted_preceding_term = 202680L, adjusted_feeder_check = "measured"
  )
  summary <- projection_plan_feeder_summary(rows, 0.05, "spring")
  expect_equal(summary$n_raised, 1L)
  expect_equal(summary$n_lowered, 2L)
  expect_equal(summary$registrations, -26)
  expect_equal(summary$sentence, paste0(
    "Feeder courses in Fall 2026 raise 1 course's plan by 12 registrations and ",
    "lower 2 courses' plans by 38. A course's listed predecessor, taken the term ",
    "before, always counts; its other feeder courses count when they moved 5% ",
    "or more. 1 course's published projection already includes those changes."
  ))
  still <- projection_plan_feeder_summary(
    dplyr::mutate(rows, plan_feeder_adjustment = 0, method_id = "seasonal_last"), 0.05,
    "spring"
  )
  expect_equal(still$sentence, paste0(
    "No plan shown has a feeder adjustment: where the forecast is last year's ",
    "number, feeder courses moved less than 5% in Fall 2026 and no listed ",
    "predecessor changed it."
  ))
  unseen <- projection_plan_feeder_summary(
    dplyr::mutate(rows, plan_feeder_adjustment = 0, adjusted_feeder_check = "term_not_observed"),
    0.05, "spring"
  )
  expect_match(unseen$sentence, "^No plan has a feeder adjustment: Fall 2026 is not observed yet")
  expect_error(projection_plan_feeder_summary(rows, NULL, "spring"), "plan_feeder_change")
  # A Fall bundle says the rule, not that its feeders are unobserved.
  fall <- projection_plan_feeder_summary(
    dplyr::mutate(rows, term_type = "fall", plan_feeder_adjustment = 0,
                  adjusted_preceding_term = 202710L,
                  adjusted_feeder_check = "term_not_observed"),
    0.05, "spring"
  )
  expect_equal(fall$sentence,
               "No plan has a feeder adjustment: only Spring plans follow their feeder courses.")
  expect_error(projection_plan_feeder_summary(rows, 0.05, NULL), "plan_feeder_seasons")
})

test_that("the view adds a needs-a-look filter without changing a number", {
  bundle <- projection_fixture_bundle(202110L, 202080L, 202080L)
  view <- build_enrollment_projection_view(bundle, list(group_id = "all_saved"))

  expect_true(all(c("planning_sections", "expected_first_day", "demand_range",
                    "flags", "recent_first_day", "recent_sections",
                    "recent_terms",
                    "summary_sentence", "attention") %in% names(view$table)))
  expect_equal(view$table$expected_first_day, view$projections$projected_first_day_equivalent)
  expect_equal(view$table$planning_sections, view$projections$recommended_sections)
  expect_equal(view$meta$n_attention, sum(view$projections$attention))
  # The campus history is saved per delivery campus, inside the saved scope,
  # for each recent term; Spring 2020 is in the window when it opens there.
  history_bundle <- projection_fixture_bundle(202110L, 202080L, 202010L)
  expect_gt(nrow(history_bundle$recent_campus_history), 0L)
  expect_true(all(history_bundle$recent_campus_history$campus %in% history_bundle$scope_campuses))
  expect_setequal(history_bundle$recent_campus_history$history_term,
                  history_bundle$recent_history$history_term)
  history_view <- build_enrollment_projection_view(history_bundle, list(group_id = "all_saved"))
  expect_true(all(history_view$campus_history$subject_course %in% history_view$projections$subject_course))
  # A draft that moves the seats 10% or more from last year's same term says
  # the range assumes steady seats; one within 10% says nothing.
  last <- history_bundle$recent_history %>% dplyr::filter(recency_rank == 1L)
  drafted <- history_bundle
  drafted$projections <- drafted$projections %>%
    dplyr::left_join(
      dplyr::select(last, subject_course, last_capacity = scheduled_capacity),
      by = "subject_course"
    ) %>%
    dplyr::mutate(
      projection_low = 10, projection_high = 30,
      target_schedule_available = TRUE,
      scheduled_capacity = c(1.5, rep(1.05, dplyr::n() - 1L)) * last_capacity
    ) %>%
    dplyr::select(-last_capacity)
  drafted_view <- build_enrollment_projection_view(drafted, list(group_id = "all_saved"))
  moved_course <- drafted$projections$subject_course[[1]]
  expect_equal(
    drafted_view$table$range_note[drafted_view$table$course == moved_course],
    paste0("Draft seats +50% on ", last$history_term_label[last$subject_course == moved_course],
           ": the range assumes steady seats")
  )
  expect_true(all(is.na(drafted_view$table$range_note[drafted_view$table$course != moved_course])))
  expect_match(drafted_view$meta$range_coverage$sentence, "^The range assumes seats like last year's\\.")
  broken <- history_bundle
  broken$recent_campus_history <- dplyr::bind_rows(
    broken$recent_campus_history, broken$recent_campus_history[1, ]
  )
  expect_error(validate_enrollment_projection_bundle(broken), "Campus history")

  # The range is in registrations, the unit sections are sized from. The
  # fixture has too few aftcasts for an interval, so one is set on row 1;
  # its first-day range is narrower and must not be what the page shows.
  ranged_bundle <- bundle
  ranged_bundle$projections$projection_low[[1]] <- 1100
  ranged_bundle$projections$projection_high[[1]] <- 1300
  ranged_bundle$projections$projection_low_first_day_equivalent[[1]] <- 990
  ranged_bundle$projections$projection_high_first_day_equivalent[[1]] <- 1170
  ranged <- build_enrollment_projection_view(
    ranged_bundle, list(group_id = "all_saved")
  )
  course <- ranged_bundle$projections$subject_course[[1]]
  expect_equal(ranged$table$demand_range[ranged$table$course == course], "1,100 to 1,300")
  expect_true(all(is.na(ranged$table$demand_range[ranged$table$course != course])))

  flagged <- build_enrollment_projection_view(
    bundle, list(group_id = "all_saved", attention_only = TRUE)
  )
  expect_true(all(flagged$projections$attention))
  expect_lte(nrow(flagged$projections), nrow(view$projections))
})
