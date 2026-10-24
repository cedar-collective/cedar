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
  expect_match(guide$summary, "2 candidates")
  expect_match(guide$selection_process, "Prior same-season is the default")
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

test_that("intersession is left out of every projection input (IS01)", {
  prepare <- function(parts) {
    prepare_enrollment_projection_inputs(
      cl_enrls = calc_cl_enrls(test_students_intersession, by_part_term = TRUE),
      sections = test_sections_intersession,
      students = test_students_intersession,
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
      method_id = "seasonal_last", method_label = "Prior same-season",
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
    method_label = "Prior same-season", policy_selected = TRUE,
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
  expect_equal(recent$aftcast_method_label, rep("Prior same-season", 3))
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
    scheduled_sections = c(3L, 3L, 4L, 4L, 2L, 2L, 3L)
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
  expect_equal(second$recent_sections[[1]], c(2, NA, 2, 3))
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

  expect_match(explanation, "Stability:", fixed = TRUE)
  expect_match(explanation, "Depth:", fixed = TRUE)
  expect_match(explanation, "Reliability:", fixed = TRUE)
  expect_match(explanation, "moved only 4.0%", fixed = TRUE)
  expect_match(explanation, "only 2 comparable Spring aftcasts", fixed = TRUE)
  expect_match(explanation, "within 4.5% WAPE", fixed = TRUE)

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
  expect_match(volatile, "4 comparable Spring aftcasts stand behind", fixed = TRUE)
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
    "regime check$"
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
  expect_true("Prior same-season + floor + Fall deltas (selected)" %in% trace_names)
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
  expect_equal(result$recommendation, "Plan 4 section(s)")
  # 90 of 96 seats taken on both judged first days is near full, so the plan
  # carries a 10-student pressure bump; ceiling(110 / 32) is still 4, and the
  # forecast is untouched.
  expect_true(result$pressure_bump_applied)
  expect_equal(result$pressure_bump, 10)
  expect_equal(result$planned_registrations, 110)
  expect_equal(result$pressure_bump_sections, 0L)
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
    adjusted_waitlisted_prior = 0L, adjusted_floor_uplift = 0,
    adjusted_preceding_term = 202410L, adjusted_feeder_check = "measured",
    adjusted_feeder_courses = "FEED 1", adjusted_feeder_change_rate = 0.02
  )
  bump <- function(r = row, h = history) {
    projection_pressure_bump(h, sections, r)
  }

  full <- bump()
  expect_true(full$pressure_bump_applied)
  expect_equal(full$pressure_judged_terms, 3L)
  expect_equal(full$pressure_full_terms, 3L)
  expect_equal(full$pressure_bump, 20)
  expect_match(full$pressure_bump_note, paste0(
    "^Pressure bump \\+20: near full on the first day in every recent Fall ",
    "with a first-day count \\(Fall 2021, Fall 2022, Fall 2023\\)"
  ))
  expect_match(full$pressure_bump_note, "Feeder courses moved \\+2\\.0% in Spring 2024\\.$")

  # More students left waiting than 10%: the bump is the waiting count.
  waiting <- bump(dplyr::mutate(row, adjusted_waitlisted_prior = 31L))
  expect_equal(waiting$pressure_bump, 31)
  expect_match(waiting$pressure_bump_note, "planned for the 31 students left waiting")

  # A floor the published method already added counts toward the bump.
  floored <- bump(dplyr::mutate(
    row, method_id = "spine_adjusted", adjusted_waitlisted_prior = 12L,
    adjusted_floor_uplift = 12, projected_classlist_total = 212
  ))
  expect_equal(floored$pressure_bump, 8)

  # One judged Fall below the near-full line is not always full.
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

  # Feeders that just fell 5% or more cancel it; feeders not observed yet do
  # not, and the note says to recheck.
  fell <- bump(dplyr::mutate(row, adjusted_feeder_change_rate = -0.08))
  expect_false(fell$pressure_bump_applied)
  expect_match(fell$pressure_bump_note, "but feeder courses moved -8\\.0% in Spring 2024")
  unseen <- bump(dplyr::mutate(
    row, adjusted_feeder_check = "term_not_observed",
    adjusted_feeder_courses = NA_character_, adjusted_feeder_change_rate = NA_real_
  ))
  expect_true(unseen$pressure_bump_applied)
  expect_match(unseen$pressure_bump_note, "Feeder courses in Spring 2024 are not observed yet")
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
  expect_equal(
    projection_fold_error_source(folds$fold_seat_change, folds$fold_prior_near_full),
    c("data_missing", "seats_held_room", "seats_changed")
  )
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

  # Read together: a miss with steady seats is the forecast's.
  reading <- projection_reliability_reading(
    c("Low", "Low", "High", "Unrated"), c("High", "Low", "Low", "High")
  )
  expect_match(reading[[1]], "even though the seats held steady")
  expect_match(reading[[2]], "follow the schedule more than demand")
  expect_match(reading[[3]], "landed close")
  expect_match(reading[[4]], "^Too few past forecasts")
})

test_that("past error is summed by what each miss is attributable to", {
  backtests <- tibble::tribble(
    ~policy_selected, ~abs_error, ~actual_classlist_total, ~fold_seat_change, ~fold_prior_near_full,
    TRUE,  30, 100,  0.40, TRUE,
    TRUE,  10, 100, -0.30, NA,
    TRUE,   5, 100,  0.00, TRUE,
    TRUE,  15, 100,  0.05, FALSE,
    TRUE,  20, 100,  NA,   NA,
    FALSE, 99, 100,  0.00, TRUE
  )
  sources <- summarize_projection_error_sources(backtests)

  expect_equal(sources$source,
               c("seats_changed", "data_missing", "seats_held_full", "seats_held_room"))
  expect_equal(sources$folds, c(2L, 1L, 1L, 1L))
  # 80 points of error in all, from the rule's published rows only.
  expect_equal(sources$share_of_error, c(40, 20, 5, 15) / 80)
  expect_equal(sources$wape, c(40 / 200, 20 / 100, 5 / 100, 15 / 100))
  expect_equal(sources$label[[1]], "Seats changed 10% or more")

  summary <- projection_error_sources_summary(backtests, list())
  expect_equal(summary$n_folds, 5L)
  expect_match(summary$sentence, "^Across 5 past forecasts, 50% of the error came from terms whose seats changed")
  expect_match(summary$sentence, "and 19% from courses with room whose seats held \\(15\\.0% off on average\\)")
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
    planned_registrations = 110, pressure_bump = 10,
    projected_first_day_equivalent = 90,
    recommended_sections = 4L, reference_section_size = 30,
    scheduled_sections = c(2L, 3L, 4L, 7L, 0L),
    scheduled_capacity = c(50, 100, 115, 200, 0),
    target_schedule_available = c(TRUE, TRUE, TRUE, TRUE, FALSE),
    additional_sections = c(2L, 1L, 0L, 0L, NA),
    target_registration_observed = FALSE, target_registered_now = NA_real_,
    accuracy = "High", seat_consistency = "High"
  )
  components <- tibble::tibble(
    market_id = "abq_ea_course_market", subject_course = "DAY 1",
    campus = c("ABQ", "EA"), part_term = "1", scheduled_sections = c(1L, 1L)
  )
  view <- list(
    projections = projections, delivery_components = components,
    meta = list(target_schedule_as_of = as.Date("2026-10-08"),
                target_term_label = "Spring 2027")
  )
  draft <- build_enrollment_projection_draft_comparison(view)
  table <- draft$table

  expect_true(draft$available)
  expect_equal(table$course, c("DAY 1", "PLAN 1", "MISSING 1", "COVER 1", "SPARE 1"))
  expect_equal(table$status,
               c("short_day_one", "short_plan", "not_in_draft", "covers", "spare"))
  expect_equal(table$verdict[[1]], "Short of day-one seats by 40; the plan needs 2 more sections")
  expect_equal(table$verdict[[2]], "Covers day one; 10 short of the plan (1 section)")
  expect_equal(table$verdict[[4]], "Covers the plan, 5 to spare")
  expect_equal(table$verdict[[5]], "90 seats beyond the plan")
  expect_equal(table$campus_sections[[1]], "ABQ 1 \u00b7 EA 1")
  expect_match(draft$sentence, "^The draft schedule \\(pulled October 8, 2026\\) has 465 seats in 4 of the 5 courses shown")
  expect_match(draft$sentence, "1 course is short of the students expected on day one \\(by 40 seats\\)")
  expect_match(draft$sentence, "1 monitored course is not in the draft\\.$")

  # No schedule for the target term: says so instead of an empty table.
  none <- build_enrollment_projection_draft_comparison(list(
    projections = dplyr::mutate(projections, target_schedule_available = FALSE),
    delivery_components = components[0, ],
    meta = list(target_schedule_as_of = as.Date(NA), target_term_label = "Spring 2027")
  ))
  expect_false(none$available)
  expect_match(none$sentence, "^No schedule for Spring 2027 is in the data yet")
})

test_that("the bundle validator rejects a plan that is not its projection plus its bump", {
  rows <- tibble::tibble(
    projected_classlist_total = c(100, NA), pressure_bump = c(10, 0),
    pressure_bump_applied = c(TRUE, FALSE), planned_registrations = c(110, NA),
    reference_section_size = 25, recommended_sections = c(5L, NA)
  )
  expect_silent(validate_pressure_bump_rows(rows, "test"))
  message <- "not its projection plus its pressure bump"
  expect_error(validate_pressure_bump_rows(
    dplyr::mutate(rows, planned_registrations = c(100, NA)), "test"
  ), message)
  expect_error(validate_pressure_bump_rows(
    dplyr::mutate(rows, recommended_sections = c(4L, NA)), "test"
  ), message)
  expect_error(validate_pressure_bump_rows(
    dplyr::mutate(rows, pressure_bump_applied = c(FALSE, FALSE)), "test"
  ), message)
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
  expect_equal(result$recommendation, "Add 2 section(s)")
})

# ---- The spine / floor / delta model -------------------------------------------
#
# One designed scenario, TEST 201, reused by the floor, delta, and regime tests:
#   Springs 2022 and 2023 enrolled 20 and 24 (the spine for Spring 2024 is 24).
#   Falls 2021 to 2023 enrolled 8, 8, 12 in the course itself.
#   FEED 1 enrolled 10, 10, 20 students in those Falls; half of each Fall's
#   FEED 1 students took TEST 201 the following Spring, and a quarter of each
#   Fall's TEST 201 students took it again.
projection_spine_scenario <- function(spring_capacity = 30, waitlisted = 0L) {
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
  enrollments <- dplyr::bind_rows(
    roster(202180L, "FEED 1", ids("f", 10)), roster(202180L, "TEST 201", ids("r", 4)),
    roster(202210L, "TEST 201", c(ids("f", 5), "r1", ids("x", 14))),
    roster(202280L, "FEED 1", ids("g", 10)), roster(202280L, "TEST 201", ids("s", 4)),
    roster(202310L, "TEST 201", c(ids("g", 5), "s1", ids("y", 18))),
    roster(202380L, "FEED 1", ids("h", 20)), roster(202380L, "TEST 201", ids("t", 12))
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

test_that("Fall deltas scale enrollment changes by the historical carry-through", {
  s <- projection_spine_scenario()
  result <- project_spine_adjusted(
    s$enrollment_history, s$preceding_term_history, s$section_history,
    s$waitlist_history, s$students, s$row, 202410L
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
  expect_match(result$component_summary, "feeders \\(FEED 1\\)")
  expect_true(validate_spine_rows(
    result %>% dplyr::mutate(target_term = 202410L), "fixture"
  ))

  # Two steps out the preceding term is unobserved: the spine stands alone and
  # the row says why, rather than guessing a delta.
  far <- project_spine_adjusted(
    s$enrollment_history, s$preceding_term_history, s$section_history,
    s$waitlist_history, s$students, s$row, 202510L
  )
  expect_true(far$applicable)
  expect_equal(far$delta_repeat, 0)
  expect_equal(far$delta_feeder, 0)
  expect_match(far$delta_basis, "Fall 2024 is not observed yet")
  expect_true(is.na(far$regime_alarm))
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
    recency_rank = c(1L, 1L, 2L, 1L, 1L),
    campus = c("ABQ", "EA", "EA", "ABQ", "EA"),
    first_day_basis = "complete",
    first_day_fill = c(0.80, 1.00, 0.50, 0.95, 1.00)
  )
  expect_equal(
    projection_campus_fill_flags(projections, history),
    c("EA full last term, ABQ had room", NA)
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
    s$waitlist_history, s$students, s$row, 202410L
  )

  expect_equal(result$spine, 24)
  expect_true(result$saturated_prior)
  expect_equal(result$prior_first_day_fill, 20 / 22)
  expect_equal(result$waitlisted_prior, 3L)
  expect_equal(result$floor_uplift, 3)
  expect_match(result$floor_basis, "first-day fill 90.9%")
  expect_match(result$floor_basis, "spine 24 \\+ 3 still waiting = 27")
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
               "floor \\+ Fall deltas beat Prior same-season on 4 earlier shared")
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
  expect_match(selected$selection_reason, "Prior same-season is the default")
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
  expect_match(explanation, "first-day enrollment reached", fixed = TRUE)
  expect_match(explanation, "not proof of unconstrained demand", fixed = TRUE)
  expect_match(explanation, "candidate projections differ", fixed = TRUE)
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
    method_label = "Prior same-season + floor + Fall deltas",
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

test_that("the administrator summary says the decision in one sentence and flags why to look", {
  row <- tibble::tibble(
    subject_course = "TEST 101", term_type = "spring",
    projected_classlist_total = 2179, projected_first_day_equivalent = 2080,
    pressure_bump = 218, pressure_bump_applied = TRUE,
    pressure_bump_note = "Pressure bump +218: near full in every recent Spring",
    planned_registrations = 2397,
    recommended_sections = 99L, observed_baseline = 2179,
    adjusted_saturated_prior = TRUE, adjusted_prior_first_day_fill = 0.988,
    adjusted_prior_first_day_basis = "complete", campus_fill_flag = NA_character_,
    adjusted_waitlisted_prior = 15L, adjusted_regime_alarm = FALSE,
    adjusted_preceding_term = 202680L, adjusted_preceding_term_change = 0.02,
    stability = "Moderate", accuracy = "Moderate", seat_consistency = "Unrated",
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

  # A full course denied the bump says why.
  denied <- dplyr::mutate(
    row, pressure_bump = 0, pressure_bump_applied = FALSE,
    planned_registrations = 2179,
    pressure_bump_note = "No pressure bump: feeder courses moved -9% in Fall 2026"
  )
  denied_sentence <- projection_summary_sentence(denied)
  expect_match(denied_sentence, "^Plan at least 99 sections for 2,179 registrations \\(about 2,080 in seats on the first day\\)\\.")
  expect_match(denied_sentence, "so this is a floor\\. No pressure bump: feeder courses moved -9% in Fall 2026\\.")
  expect_match(sentence, "That is last year's level\\.")
  # One decimal: whole percents turned 98.8% into "99%" and read as full.
  expect_match(sentence, "filled 98\\.8% of its seats on the first day with 15 students waiting, so this is a floor\\.")
  expect_match(sentence, "averaged 10 to 20% off\\.$")
  # 98.8% on the first day is full, not merely near full: the flag uses the
  # same two levels as every other page.
  expect_equal(projection_flags(row), "Full last term | 15 waiting")
  expect_equal(
    projection_flags(dplyr::mutate(row, adjusted_prior_first_day_fill = 0.93)),
    "Near full last term | 15 waiting"
  )
  # An unknown fill names its cause (ISSUES.md I28); one with no cause
  # recorded (no prior term to read) adds nothing.
  unknown <- function(basis) projection_flags(dplyr::mutate(
    row, adjusted_saturated_prior = NA, adjusted_prior_first_day_fill = NA_real_,
    adjusted_prior_first_day_basis = basis
  ))
  expect_equal(unknown("undated"), "Last term's fill unknown: no status dates")
  expect_equal(unknown("sessions_pending"), "Last term's fill unknown: a session had not begun")
  expect_equal(unknown("no_capacity"), "Last term's fill unknown: no seat count")
  expect_equal(unknown(NA_character_), "")
  expect_equal(
    projection_flags(dplyr::mutate(row, campus_fill_flag = "EA full last term, ABQ had room")),
    "Full last term | 15 waiting | EA full last term, ABQ had room"
  )
  expect_error(projection_flags(dplyr::select(row, -campus_fill_flag)), "campus_fill_flag")

  moved <- dplyr::mutate(
    row, adjusted_saturated_prior = FALSE, adjusted_waitlisted_prior = 0L,
    adjusted_regime_alarm = TRUE, adjusted_preceding_term_change = 0.91,
    projected_classlist_total = 2400, pressure_bump = 0,
    pressure_bump_applied = FALSE, planned_registrations = 2400,
    pressure_bump_note = "No pressure bump: Fall 2026 filled 80.0% of its seats",
    stability = "Volatile", accuracy = "Low"
  )
  expect_match(projection_summary_sentence(moved), "^Plan 99 sections")
  expect_match(projection_summary_sentence(moved), "That is \\+10% on last Spring\\.")
  expect_match(projection_summary_sentence(moved), "Fall 2026 moved \\+91%")
  expect_equal(
    projection_flags(moved),
    "Fall enrollment +91% | Hard to predict | Past forecasts off by 20%+"
  )
  # A Low course whose seats held is the forecast's miss; one whose seats
  # moved is mostly the schedule's.
  expect_equal(
    projection_flags(dplyr::mutate(moved, seat_consistency = "High")),
    "Fall enrollment +91% | Hard to predict | Off 20%+ with steady seats"
  )
  expect_equal(
    projection_flags(dplyr::mutate(moved, seat_consistency = "Low")),
    "Fall enrollment +91% | Hard to predict | Off 20%+ as seats moved"
  )

  sparse <- dplyr::mutate(row, projected_classlist_total = NA_real_)
  expect_match(projection_summary_sentence(sparse), "^Not enough comparable history")
})

test_that("the view adds a needs-a-look filter without changing a number", {
  bundle <- projection_fixture_bundle(202110L, 202080L, 202080L)
  view <- build_enrollment_projection_view(bundle, list(group_id = "all_saved"))

  expect_true(all(c("planning_sections", "expected_first_day", "demand_range",
                    "change_vs_last", "flags", "recent_first_day", "recent_sections",
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
