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

projection_calibration_backtests <- function(
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
    census_retention_rate = 1,
    projected_census_equivalent = projected, actual_census = actual,
    scheduled_capacity = capacity, registration_fill = actual / capacity,
    capacity_usable = TRUE, capacity_reached = constrained,
    error = error, abs_error = abs(error),
    capacity_censored_abs_error = ifelse(
      constrained, pmax(0, -error), abs(error)
    ),
    pct_error = error / actual, abs_pct_error = abs(error / actual)
  )
}

test_that("capacity censoring follows registration capacity, not census fill", {
  backtests <- tibble::tibble(
    projected_classlist_total = c(600, 480, 600, 600),
    actual_classlist_total = c(500, 450, 450, 520),
    projected_census_equivalent = c(450, 400, 500, 450),
    actual_census = c(400, 450, 500, 400),
    scheduled_capacity = c(500, 500, 500, 500)
  ) %>%
    add_projection_capacity_censoring()

  expect_equal(backtests$registration_capacity_gap, c(0, 50, 50, -20))
  expect_equal(backtests$capacity_reached, c(TRUE, FALSE, FALSE, TRUE))
  expect_equal(backtests$abs_error, c(100, 30, 150, 80))
  expect_equal(
    backtests$capacity_censored_classlist_projection,
    c(500, 480, 600, 520)
  )
  expect_equal(backtests$capacity_censored_abs_error, c(0, 30, 150, 0))
  expect_equal(backtests$capacity_explained_classlist_error, c(100, 0, 0, 80))
  expect_equal(backtests$capacity_censored_miss, c(TRUE, FALSE, FALSE, TRUE))
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
  expect_equal(
    CEDAR_ENROLLMENT_PROJECTION_METHOD_ROLES[["spring_cohort_flow"]],
    "structural_demand"
  )
  expect_equal(
    CEDAR_ENROLLMENT_PROJECTION_METHOD_ROLES[["spring_population_growth"]],
    "structural_demand"
  )
  config <- enrollment_projection_model_config()
  expect_equal(config$history_start_term, 202210L)
  expect_equal(config$course_history_start_terms[["MATH 1215"]], 202580L)
  expect_equal(config$course_census_retention_min_terms[["MATH 1215"]], 1L)
  expect_equal(config$calibration_factor_bounds, c(0.75, 1.25))
  expect_equal(config$projection_methods, names(CEDAR_ENROLLMENT_PROJECTION_METHODS))
  expect_identical(
    CEDAR_ENROLLMENT_PROJECTION_METHOD_GUIDE$method_id,
    names(CEDAR_ENROLLMENT_PROJECTION_METHODS)
  )
  expect_identical(
    CEDAR_ENROLLMENT_PROJECTION_METHOD_GUIDE$family_id,
    unname(CEDAR_ENROLLMENT_PROJECTION_METHOD_ROLES)
  )
  guide <- build_enrollment_projection_method_guide(config$projection_methods)
  expect_equal(guide$n_candidates, 9L)
  expect_equal(guide$n_ideas, 6L)
  expect_equal(vapply(guide$families, function(x) nrow(x$methods), integer(1)),
               c(3L, 3L, 3L))
  expect_match(guide$summary, "9 candidates")
  expect_match(guide$selection_process, "Raw upstream indicators never win")
  expect_error(
    enrollment_projection_model_config(
      list(calibration_factor_bounds = c(0.50, 1.25))
    ),
    "must stay within"
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
  students <- tibble::tribble(
    ~student_id, ~term, ~campus, ~college, ~subject_course, ~registration_status_code,
    "s1", 202380L, "ABQ", "AS", "MATH 1215", "RE",
    "s1", 202380L, "EA",  "AS", "MATH 1215", "RE",
    "s2", 202380L, "ABQ", "AS", "MATH 1215", "DW",
    "s5", 202380L, "EA",  "AS", "MATH 1215", "DR",
    "s6", 202380L, "ABQ", "AS", "MATH 1215", "DD",
    "s7", 202380L, "EA",  "AS", "MATH 1215", "DG",
    "s8", 202380L, "ABQ", "AS", "MATH 1215", "WL",
    "s9", 202380L, "EA",  "AS", "MATH 1215", "XX",
    "s3", 202380L, "GA",  "AS", "MATH 1215", "RE",
    "s4", 202380L, "ABQ", "AS", "MATH 1215Z", "RE"
  )

  history <- prepare_projection_market_enrollment_history(
    students,
    courses = "MATH 1215",
    campuses = c("ABQ", "EA"),
    market_id = "abq_ea_course_market"
  )

  expect_equal(nrow(history), 1L)
  expect_equal(history$registered, 1L)
  expect_equal(history$dr_early, 2L)
  expect_equal(history$dr_late, 2L)
  expect_equal(history$other_non_waitlist, 1L)
  expect_equal(history$classlist_total, 6L)
  expect_equal(history$census_enrl, 3L)
  expect_equal(history$census_retention_rate, 1 / 2)
})

test_that("census retention uses only prior same-season class-list outcomes", {
  history <- projection_test_history(
    c(100, 100, 100), terms = c(202080L, 202180L, 202280L)
  ) %>%
    dplyr::mutate(census_enrl = c(80, 90, 100))

  result <- projection_census_retention_for_row(
    history, projection_test_row(), 202280L,
    opt = list(census_retention_min_terms = 2L)
  )

  expect_equal(result$census_retention_rate, 0.85)
  expect_equal(result$census_retention_n_terms, 2L)
  expect_equal(result$census_retention_terms, "202080,202180")
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
    target_term = c(202180L, 202280L, 202380L), applicable = TRUE,
    applicability_reason = "Prior fall", raw_projected_classlist_total =
      c(100, 110, 120), calibrated_projected_classlist_total = c(100, 110, 120),
    calibration_applied = FALSE, calibration_factor = 1,
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
      actual_classlist_total = 100, actual_census = 95,
      actual_final_enrollment = 90, scheduled_sections = 3L,
      scheduled_capacity = 105, prior_classlist_total = 80,
      prior_scheduled_capacity = 85, classlist_change = 0.25,
      capacity_change = 20 / 85, registration_fill = 100 / 105,
      capacity_reached = FALSE, potential_miss_explanation = "Test"
    ) %>%
    tibble::add_row(
      market_id = "abq_ea_course_market", college = "AS", department = "TEST",
      subject_course = "TEST 101", term_type = "fall",
      projection_target_term = 202480L, history_term = 202380L,
      history_term_label = "Fall 2023", recency_rank = 1L,
      actual_classlist_total = 130, actual_census = 125,
      actual_final_enrollment = 120, scheduled_sections = 4L,
      scheduled_capacity = 135, prior_classlist_total = 100,
      prior_scheduled_capacity = 105, classlist_change = 0.30,
      capacity_change = 30 / 105, registration_fill = 130 / 135,
      capacity_reached = TRUE, potential_miss_explanation = "Test"
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
    scheduled_sections = c(3L, 3L, 4L, 4L, 2L, 2L, 3L)
  )

  summary <- build_enrollment_projection_history_summary(
    projections, history
  )

  expect_equal(summary$columns$term, c(202080L, 202180L, 202280L, 202380L))
  expect_equal(summary$columns$header, paste0(
    c("Fa20", "Fa21", "Fa22", "Fa23"), ": first day / sects"
  ))
  expect_equal(
    unname(unlist(
      summary$data[
        summary$data$course == "TEST 101", paste0("history_", 1:4)
      ],
      use.names = FALSE
    )),
    c("100 / 3", "110 / 3", "120 / 4", "130 / 4")
  )
  expect_true(is.na(summary$data$history_2[summary$data$course == "TEST 201"]))
  expect_equal(enrollment_projection_model_config()$recent_history_terms, 4L)
})

test_that("confidence explanations distinguish accuracy from evidence volume", {
  explanation <- projection_confidence_explanation(
    confidence = "Low", n_backtests = 2L, wape = 0.045,
    term_type = "spring"
  )

  expect_match(explanation, "2 comparable Spring aftcasts", fixed = TRUE)
  expect_match(explanation, "4.5% WAPE", fixed = TRUE)
  expect_match(explanation, "Medium requires 3", fixed = TRUE)
  expect_match(explanation, "High requires 4", fixed = TRUE)
})

test_that("summary confidence text stays compact and names the main caveat", {
  brief <- projection_confidence_brief(
    n_backtests = 4L, pct_error_sd = 0.067,
    capacity_constrained = TRUE, methods_disagree = TRUE,
    method_role = "anchored_upstream", coverage_rate = 0.90
  )

  expect_equal(brief, "4 terms · consistent errors · capacity-limited")
})

test_that("historical-method plot compares one term type with lifecycle actuals", {
  history <- tidyr::crossing(
    method_id = c("seasonal_last", "seasonal_trend"),
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
      actual_census = actual_classlist_total - 10,
      actual_final_enrollment = actual_classlist_total - 15
    )

  plot <- build_enrollment_projection_method_history_plot(
    history, selected_method_id = "seasonal_trend"
  )
  built <- plotly::plotly_build(plot)
  trace_names <- vapply(built$x$data, function(trace) trace$name, character(1))

  expect_s3_class(plot, "plotly")
  expect_true("First day / ever registered (model target)" %in% trace_names)
  expect_true("Census" %in% trace_names)
  expect_true("Final / last day" %in% trace_names)
  expect_true("Seasonal trend (selected)" %in% trace_names)
  expect_equal(length(trace_names), 5L)

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
  median_result <- project_seasonal_median(
    history, row, 202480L, list(seasonal_window = 4L)
  )
  trend_result <- project_seasonal_trend(
    history, row, 202480L, list(trend_window = 4L)
  )

  expect_true(last_result$applicable)
  expect_equal(last_result$projected_classlist_total, 40)
  expect_true(median_result$applicable)
  expect_equal(median_result$projected_classlist_total, 25)
  expect_equal(trend_result$projected_classlist_total, 50, tolerance = 1e-8)
  expect_false(grepl("999", median_result$component_summary, fixed = TRUE))
})

test_that("candidate methods can be limited for fast computational audits", {
  row <- projection_test_row()
  inputs <- list(
    enrollment_history = projection_test_history(),
    students = list()
  )

  result <- project_course_method_candidates(
    inputs, row, 202480L,
    opt = list(projection_methods = c("seasonal_last", "seasonal_median"))
  )

  expect_setequal(result$method_id, c("seasonal_last", "seasonal_median"))
  expect_error(
    project_course_method_candidates(
      inputs, row, 202480L,
      opt = list(projection_methods = "imaginary")
    ),
    "Unknown projection method"
  )
})

test_that("selection does not treat non-finite WAPE as scored evidence", {
  row <- projection_test_row()
  candidates <- dplyr::bind_rows(
    projection_candidate("seasonal_last", 120, TRUE, "ok"),
    projection_candidate("seasonal_median", 118, TRUE, "ok")
  ) %>%
    dplyr::mutate(
      market_id = row$market_id, college = row$college,
      subject_course = row$subject_course,
      term_type = row$term_type, target_term = row$target_term,
      .before = 1
    )
  performance <- tibble::tibble(
    market_id = "abq_ea_course_market", college = "AS",
    subject_course = "TEST 101", term_type = "fall",
    method_id = c("seasonal_last", "seasonal_median"),
    method_label = unname(CEDAR_ENROLLMENT_PROJECTION_METHODS[
      c("seasonal_last", "seasonal_median")
    ]),
    n_backtests = c(4L, 4L), mae = c(NA, 20), rmse = c(NA, 25),
    wape = c(Inf, 0.25), bias = c(NA, 3), error_q80 = c(NA, 30)
  )

  selected <- select_projection_methods(candidates, performance, tibble::tibble())

  expect_equal(selected$method_id, "seasonal_median")
  expect_match(selected$selection_reason, "Lowest historical WAPE")
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
      "Not selected: 1 of 3 recent fall terms with class-list registrations",
      "at or above 90% of scheduled capacity"
    )
  )
  expect_match(screen$inclusion_reason, "within 10 seats")
  expect_false(grepl("Below pressure thresholds", screen$inclusion_reason))
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
    section_history = sections,
    students = list(
      course_enrollments = tibble::tibble(
        student_id = character(), term = integer(), subject_course = character()
      ),
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
    delivery_components = empty_projection_test_components()
  )

  result <- get_course_enrollment_projections(
    inputs, 202480L, force_courses = "TEST 101"
  )$projections

  expect_false(result$target_schedule_available)
  expect_match(result$recommendation, "^Plan [0-9]+ section")
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
    c(300, 400, 500), terms = c(202180L, 202280L, 202380L)
  )
  sections <- tibble::tibble(
    market_id = "abq_ea_course_market", college = "AS", department = "TEST",
    course_title = "Test Course", subject_course = "TEST 101",
    term = c(202180L, 202280L, 202380L, 202480L), term_type = "fall",
    scheduled_sections = c(7L, 9L, 11L, 10L),
    scheduled_enrl = c(300, 400, 500, 495),
    scheduled_capacity = c(350, 450, 550, 500),
    n_delivery_components = 2L, n_campuses = 2L,
    capacity_per_section = c(50, 50, 50, 50)
  )
  empty_students <- list(
    course_enrollments = tibble::tibble(
      student_id = character(), term = integer(), subject_course = character()
    ),
    target_students = tibble::tibble(
      student_id = character(), term = integer(), subject_course = character()
    ),
    student_terms = tibble::tibble(
      student_id = character(), term = integer(), major_code = character(),
      student_classification = character()
    )
  )
  inputs <- list(
    enrollment_history = history, section_history = sections,
    target_registration_snapshot = tibble::tibble(
      market_id = "abq_ea_course_market", college = "AS",
      subject_course = "TEST 101", term = 202480L, term_type = "fall",
      registered = 495, dr_early = 25, dr_late = 0,
      other_non_waitlist = 0,
      classlist_total = 520, census_enrl = 495,
      census_retention_rate = 495 / 520
    ),
    students = empty_students, target_courses = "TEST 101",
    target_campuses = c("ABQ", "EA"),
    target_market_id = "abq_ea_course_market",
    delivery_components = empty_projection_test_components()
  )

  result <- get_course_enrollment_projections(
    inputs,
    202480L,
    force_courses = "TEST 101",
    opt = list(
      projection_methods = "seasonal_trend", trend_min_terms = 2L,
      selection_min_backtests = 1L
    )
  )$projections

  expect_equal(result$method_id, "seasonal_trend")
  expect_equal(result$projected_classlist_total, 600)
  expect_equal(result$projected_census_equivalent, 600)
  expect_equal(result$target_classlist_total_to_date, 520)
  expect_equal(result$target_registered_now, 495)
  expect_equal(result$target_available_seats, 5)
  expect_equal(result$target_classlist_fill, 1.04)
  expect_equal(result$target_active_fill, 0.99)
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
    course_enrollments = tibble::tibble(
      student_id = character(), term = integer(),
      subject_course = character()
    ),
    target_students = tibble::tibble(
      student_id = character(), term = integer(), subject_course = character()
    ),
    student_terms = tibble::tibble(
      student_id = character(), term = integer(),
      major_code = character(), student_classification = character()
    )
  )
  inputs <- list(
    enrollment_history = history, section_history = sections,
    students = empty_students, target_courses = "TEST 101",
    target_campuses = c("ABQ", "EA"),
    target_market_id = "abq_ea_course_market",
    delivery_components = empty_projection_test_components()
  )

  result <- get_course_enrollment_projections(
    inputs, 202480L, scope_courses = "TEST 101", force_courses = "TEST 101"
  )$projections

  expect_equal(result$capacity_data_quality, "Usable")
  expect_equal(result$recent_capacity_reached_terms, 2L)
  expect_true(result$persistent_capacity_reached)
  expect_equal(result$recommendation, "Add 2 section(s)")
})

test_that("feeder method deduplicates students appearing in multiple feeders", {
  history <- projection_test_history(
    c(2, 2), terms = c(202180L, 202280L), course = "TEST 201"
  )
  row <- projection_test_row("TEST 201")
  row$target_term <- 202380L

  source_rows <- tibble::tribble(
    ~student_id, ~term, ~subject_course,
    "a1", 202110L, "FEED 1",
    "a1", 202110L, "FEED 2",
    "a2", 202110L, "FEED 1",
    "a2", 202110L, "FEED 2",
    "a3", 202110L, "FEED 1",
    "a4", 202110L, "FEED 1",
    "b1", 202210L, "FEED 1",
    "b1", 202210L, "FEED 2",
    "b2", 202210L, "FEED 1",
    "b2", 202210L, "FEED 2",
    "b3", 202210L, "FEED 1",
    "b4", 202210L, "FEED 1",
    "c1", 202310L, "FEED 1",
    "c1", 202310L, "FEED 2",
    "c2", 202310L, "FEED 1"
  )
  targets <- tibble::tribble(
    ~student_id, ~term, ~subject_course,
    "a1", 202180L, "TEST 201",
    "a2", 202180L, "TEST 201",
    "b1", 202280L, "TEST 201",
    "b2", 202280L, "TEST 201"
  )
  student_inputs <- list(
    course_enrollments = source_rows,
    target_students = targets,
    student_terms = tibble::tibble()
  )

  result <- project_from_feeders(
    history, student_inputs, row, 202380L,
    opt = list(feeder_min_students = 1L, transition_min_terms = 2L)
  )

  expect_true(result$applicable)
  expect_equal(result$coverage_rate, 1)
  expect_equal(result$projected_classlist_total, 1.5, tolerance = 1e-8)
  expect_equal(result$n_components, 2L)
})

test_that("feeder method never emits a non-finite student probability", {
  expect_equal(projection_max_finite(c(NA_real_, 0.2, 0.4)), 0.4)
  expect_true(is.na(projection_max_finite(c(NA_real_, NaN, Inf, -Inf))))
  expect_true(is.na(projection_max_finite(numeric())))
})

test_that("Spring cohort flow propagates matched cells and carries unmatched students", {
  history <- projection_test_history(
    4, terms = 202210L, course = "TEST 201"
  ) %>% dplyr::mutate(term_type = "spring")
  row <- projection_test_row("TEST 201")
  row$term_type <- "spring"
  row$target_term <- 202310L

  make_spine <- function(prefix, term, n, major, classification) {
    tibble::tibble(
      student_id = paste0(prefix, seq_len(n)),
      term = term,
      major_code = major,
      student_classification = classification
    )
  }
  student_terms <- dplyr::bind_rows(
    make_spine("bio", 202180L, 4, "BIOL", "Freshman"),
    make_spine("chem", 202180L, 2, "CHEM", "Sophomore"),
    make_spine("current_bio", 202280L, 6, "BIOL", "Freshman"),
    make_spine("current_chem", 202280L, 1, "CHEM", "Sophomore"),
    make_spine("future", 202380L, 100, "BIOL", "Freshman")
  )
  targets <- tibble::tribble(
    ~student_id, ~term, ~subject_course,
    "bio1", 202210L, "TEST 201",
    "bio2", 202210L, "TEST 201",
    "chem1", 202210L, "TEST 201",
    "spring-only", 202210L, "TEST 201"
  )
  student_inputs <- list(
    course_enrollments = tibble::tibble(),
    target_students = targets,
    student_terms = student_terms
  )

  result <- project_spring_cohort_flow(
    history, student_inputs, row, 202310L,
    opt = list(
      spring_source_min_population = 1L,
      spring_growth_prior_strength = 0
    )
  )

  expect_true(result$applicable)
  expect_equal(result$coverage_rate, 0.75)
  expect_equal(result$matched_baseline, 3)
  expect_equal(result$unmatched_baseline, 1)
  expect_equal(result$matched_projection, 3.5, tolerance = 1e-8)
  expect_equal(result$unmatched_projection, 1)
  expect_equal(result$projected_classlist_total, 4.5, tolerance = 1e-8)
  expect_equal(result$baseline_term, 202210L)
  expect_equal(result$prior_source_term, 202180L)
  expect_equal(result$source_term, 202280L)
  expect_equal(result$source_population_previous, 6)
  expect_equal(result$source_population_current, 7)
  expect_match(result$projection_formula, "unmatched count")
  expect_true(validate_spring_cohort_rows(
    result %>% dplyr::mutate(term_type = "spring", target_term = 202310L),
    "fixture"
  ))
})

test_that("Spring cohort flow is inapplicable to Fall targets", {
  result <- project_spring_cohort_flow(
    projection_test_history(),
    list(student_terms = tibble::tibble(), target_students = tibble::tibble()),
    projection_test_row(),
    202480L
  )

  expect_false(result$applicable)
  expect_match(result$applicability_reason, "only to Spring")
})

test_that("Spring population growth compares the target roster with all Fall students", {
  history <- projection_test_history(
    values = 4,
    terms = 202210L,
    course = "TEST 201"
  ) %>%
    dplyr::mutate(term_type = "spring")
  make_spine <- function(prefix, term, n, major, classification) {
    tibble::tibble(
      student_id = paste0(prefix, seq_len(n)), term = term,
      major_code = major, student_classification = classification
    )
  }
  student_terms <- dplyr::bind_rows(
    make_spine("bio", 202180L, 4, "BIOL", "Freshman"),
    make_spine("chem", 202180L, 2, "CHEM", "Sophomore"),
    make_spine("current_bio", 202280L, 6, "BIOL", "Freshman"),
    make_spine("current_chem", 202280L, 1, "CHEM", "Sophomore")
  )
  targets <- tibble::tribble(
    ~student_id, ~term, ~subject_course,
    "bio1", 202210L, "TEST 201",
    "bio2", 202210L, "TEST 201",
    "bio3", 202210L, "TEST 201",
    "spring-only", 202210L, "TEST 201"
  )
  row <- projection_test_row("TEST 201") %>%
    dplyr::mutate(term_type = "spring", target_term = 202310L)
  student_inputs <- list(
    course_enrollments = tibble::tibble(),
    target_students = targets,
    student_terms = student_terms
  )

  broad <- project_spring_population_growth(
    history, student_inputs, row, 202310L,
    opt = list(
      spring_source_min_population = 1L,
      spring_growth_prior_strength = 0
    )
  )
  cells <- project_spring_cohort_flow(
    history, student_inputs, row, 202310L,
    opt = list(
      spring_source_min_population = 1L,
      spring_growth_prior_strength = 0
    )
  )

  expect_true(broad$applicable)
  expect_equal(broad$matched_projection, 3 * 7 / 6)
  expect_equal(broad$projected_classlist_total, 4.5)
  expect_equal(cells$projected_classlist_total, 5.5)
  expect_match(broad$projection_formula, "total preceding-Fall population")
  expect_true(validate_spring_cohort_rows(
    broad %>% dplyr::mutate(term_type = "spring", target_term = 202310L),
    "fixture"
  ))
})

test_that("method selection is course-specific and based on backtest WAPE", {
  row <- projection_test_row()
  base <- dplyr::bind_rows(
    projection_candidate("seasonal_median", 120, TRUE, "ok"),
    projection_candidate("seasonal_trend", 125, TRUE, "ok")
  ) %>%
    dplyr::mutate(
      market_id = row$market_id, college = row$college,
      subject_course = row$subject_course,
      term_type = row$term_type, target_term = row$target_term,
      .before = 1
    )
  performance <- tibble::tibble(
    market_id = "abq_ea_course_market", college = "AS",
    subject_course = "TEST 101", term_type = "fall",
    method_id = c("seasonal_median", "seasonal_trend"),
    method_label = unname(CEDAR_ENROLLMENT_PROJECTION_METHODS[
      c("seasonal_median", "seasonal_trend")
    ]),
    n_backtests = c(4L, 4L), mae = c(10, 5), rmse = c(12, 6),
    wape = c(0.10, 0.05), bias = c(2, 1), error_q80 = c(15, 8),
    pct_error_sd = c(0.08, 0.04),
    uncensored_pct_error_sd = c(0.08, 0.04)
  )
  backtests <- performance %>%
    dplyr::transmute(
      market_id, subject_course, term_type, method_id,
      applicable = TRUE, abs_error = error_q80
    )

  selected <- select_projection_methods(base, performance, backtests)

  expect_equal(selected$method_id, "seasonal_trend")
  expect_equal(selected$confidence, "High")
  expect_equal(selected$projection_low, 117)
  expect_equal(selected$projection_high, 133)
})

test_that("upstream candidates remain anchored to prior same-season enrollment", {
  anchor <- projection_candidate(
    "seasonal_last", 100, TRUE, "prior Fall"
  )
  upstream <- projection_candidate(
    "feeder", 140, TRUE, "feeder population", coverage_rate = 0.60
  )

  result <- project_anchored_upstream(
    anchor, upstream, "anchored_feeder",
    opt = list(upstream_anchor_weight = 0.50)
  )

  expect_true(result$applicable)
  expect_equal(result$projected_classlist_total, 120)
  expect_equal(result$baseline_classlist_total, 100)
  expect_equal(result$method_role, "anchored_upstream")
  expect_match(result$projection_formula, "prior same-season")
})

test_that("selection prefers credible upstream evidence within the fit margin", {
  row <- projection_test_row()
  candidates <- dplyr::bind_rows(
    projection_candidate("seasonal_last", 100, TRUE, "ok"),
    projection_candidate(
      "anchored_feeder", 110, TRUE, "ok", coverage_rate = 0.60
    )
  ) %>%
    dplyr::mutate(
      market_id = row$market_id, college = row$college,
      subject_course = row$subject_course, term_type = row$term_type,
      target_term = row$target_term, .before = 1
    )
  performance <- candidates %>%
    dplyr::transmute(
      market_id, college, subject_course, term_type, method_id, method_label,
      n_backtests = 4L, mae = c(5, 6), rmse = c(6, 7),
      wape = c(0.05, 0.06), bias = 0, error_q80 = c(8, 9),
      n_capacity_usable = 4L, n_capacity_reached = 0L,
      n_capacity_unreached = 4L, uncensored_wape = c(0.05, 0.06)
    )

  selected <- select_projection_methods(
    candidates, performance, tibble::tibble()
  )

  expect_equal(selected$method_id, "anchored_feeder")
  expect_match(selected$selection_reason, "Upstream-anchored")
  expect_equal(selected$selection_basis, "All-term WAPE")
})

test_that("method selection compares eligible methods on common aftcast folds", {
  row <- projection_test_row()
  candidates <- dplyr::bind_rows(
    projection_candidate("seasonal_last", 100, TRUE, "ok"),
    projection_candidate(
      "anchored_feeder", 110, TRUE, "ok", coverage_rate = 0.60
    )
  ) %>%
    dplyr::mutate(
      market_id = row$market_id, college = row$college,
      subject_course = row$subject_course, term_type = row$term_type,
      target_term = row$target_term, .before = 1
    )
  performance <- candidates %>%
    dplyr::transmute(
      market_id, college, subject_course, term_type, method_id, method_label,
      n_backtests = c(3L, 4L), mae = c(10, 5), rmse = c(10, 5),
      wape = c(0.10, 0.05), bias = 0, error_q80 = c(10, 5),
      pct_error_sd = c(0.01, 0.01),
      n_capacity_usable = c(3L, 4L), n_capacity_reached = 0L,
      n_capacity_unreached = c(3L, 4L), uncensored_wape = c(0.10, 0.05),
      uncensored_pct_error_sd = c(0.01, 0.01)
    )
  backtests <- tibble::tibble(
    market_id = row$market_id,
    subject_course = row$subject_course,
    term_type = row$term_type,
    method_id = c(
      rep("seasonal_last", 3), rep("anchored_feeder", 4)
    ),
    target_term = c(
      202110L, 202210L, 202310L,
      202110L, 202210L, 202310L, 202410L
    ),
    applicable = TRUE,
    actual_classlist_total = 100,
    abs_error = c(rep(5, 3), rep(30, 3), 0),
    pct_error = c(rep(0.05, 3), rep(0.30, 3), 0),
    capacity_usable = TRUE,
    capacity_reached = FALSE
  )

  selected <- select_projection_methods(candidates, performance, backtests)

  expect_equal(selected$method_id, "seasonal_last")
  expect_equal(selected$selection_wape, 0.05)
  expect_equal(selected$selection_n_backtests, 3L)
  expect_equal(selected$selection_basis, "Common all-term WAPE")
})

test_that("capacity-bounded fit retains fit confidence with a demand caveat", {
  row <- projection_test_row()
  candidates <- dplyr::bind_rows(
    projection_candidate("seasonal_last", 100, TRUE, "ok"),
    projection_candidate(
      "anchored_feeder", 115, TRUE, "ok", coverage_rate = 0.60
    )
  ) %>%
    dplyr::mutate(
      market_id = row$market_id, college = row$college,
      subject_course = row$subject_course, term_type = row$term_type,
      target_term = row$target_term, .before = 1
    )
  performance <- candidates %>%
    dplyr::transmute(
      market_id, college, subject_course, term_type, method_id, method_label,
      n_backtests = 4L, mae = c(1, 5), rmse = c(1, 6),
      wape = c(0.01, 0.05), bias = 0, error_q80 = c(2, 7),
      n_capacity_usable = 4L, n_capacity_reached = 3L,
      n_capacity_unreached = 1L, uncensored_wape = c(0.03, 0.04),
      pct_error_sd = c(0.02, 0.06),
      uncensored_pct_error_sd = NA_real_
    )

  selected <- select_projection_methods(
    candidates, performance, tibble::tibble()
  )

  expect_equal(selected$method_id, "anchored_feeder")
  expect_true(selected$capacity_constrained_history)
  expect_false(selected$selection_uses_uncensored)
  expect_equal(selected$confidence, "High")
  expect_match(selected$confidence_reason, "6.0% error variation")

  explanation <- projection_confidence_explanation(
    selected$confidence, selected$selection_n_backtests,
    selected$selection_wape, selected$coverage_rate, selected$term_type,
    selected$selection_basis, selected$selection_pct_error_sd,
    selected$capacity_constrained_history, selected$selection_uses_uncensored,
    selected$n_capacity_reached, selected$n_capacity_unreached,
    selected$method_role, methods_disagree = TRUE
  )
  expect_match(explanation, "High requires at least 4 aftcasts", fixed = TRUE)
  expect_match(explanation, "3 of 4", fixed = TRUE)
  expect_match(explanation, "not proof of unconstrained demand", fixed = TRUE)
  expect_match(explanation, "observational planning relationship", fixed = TRUE)
  expect_match(explanation, "candidate projections differ", fixed = TRUE)
})

test_that("variable term errors lower confidence despite low WAPE", {
  row <- projection_test_row()
  candidate <- projection_candidate("seasonal_last", 100, TRUE, "ok") %>%
    dplyr::mutate(
      market_id = row$market_id, college = row$college,
      subject_course = row$subject_course, term_type = row$term_type,
      target_term = row$target_term, .before = 1
    )
  performance <- candidate %>%
    dplyr::transmute(
      market_id, college, subject_course, term_type, method_id, method_label,
      n_backtests = 4L, mae = 5, rmse = 6, wape = 0.05, bias = 0,
      error_q80 = 7, pct_error_sd = 0.25,
      uncensored_pct_error_sd = 0.25
    )

  selected <- select_projection_methods(
    candidate, performance, tibble::tibble()
  )

  expect_equal(selected$confidence, "None")
  expect_match(selected$confidence_reason, "variation is 25.0%")
})

test_that("structural demand methods do not replace the observed-demand estimate", {
  row <- projection_test_row()
  candidates <- dplyr::bind_rows(
    projection_candidate("seasonal_last", 100, TRUE, "ok"),
    projection_candidate("spring_cohort_flow", 120, TRUE, "ok")
  ) %>%
    dplyr::mutate(
      market_id = row$market_id, college = row$college,
      subject_course = row$subject_course, term_type = row$term_type,
      target_term = row$target_term, .before = 1
    )
  performance <- candidates %>%
    dplyr::transmute(
      market_id, college, subject_course, term_type, method_id, method_label,
      n_backtests = 4L, mae = c(20, 1), rmse = c(22, 2),
      wape = c(0.20, 0.01), bias = 0, error_q80 = c(25, 3)
    )

  selected <- select_projection_methods(
    candidates, performance, tibble::tibble()
  )

  expect_equal(selected$method_id, "seasonal_last")
  expect_equal(selected$method_role, "observed_enrollment")
})

test_that("structural demand signals require credible aftcast evidence", {
  expect_true(projection_structural_credible(
    projection = 120, n_backtests = 4L, wape = 0.12,
    uncensored_wape = NA_real_, coverage_rate = 0.60
  ))
  expect_false(projection_structural_credible(
    projection = 120, n_backtests = 2L, wape = 0.12,
    uncensored_wape = 0.10, coverage_rate = 0.60
  ))
  expect_false(projection_structural_credible(
    projection = 120, n_backtests = 4L, wape = 0.35,
    uncensored_wape = NA_real_, coverage_rate = 0.60
  ))
  expect_false(projection_structural_credible(
    projection = 120, n_backtests = 4L, wape = 0.12,
    uncensored_wape = 0.10, coverage_rate = 0.20
  ))
})

test_that("backtests separate raw from registration-cap-censored accuracy", {
  backtests <- tibble::tibble(
    market_id = "abq_ea_course_market", college = "AS",
    subject_course = "TEST 101", term_type = "spring",
    target_term = c(202210L, 202310L),
    method_id = "spring_cohort_flow",
    method_label = "Spring cohort flow",
    applicable = TRUE, projected_classlist_total = c(150, 120),
    actual_classlist_total = c(100, 100),
    census_retention_rate = 1,
    projected_census_equivalent = c(150, 120),
    actual_census = c(100, 100),
    scheduled_capacity = c(100, 200),
    method_role = "structural_demand"
  )

  result <- summarize_projection_backtests(backtests)

  expect_equal(result$wape, 0.35)
  expect_equal(result$census_equivalent_wape, 0.35)
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
  backtests <- add_projection_rolling_calibration(
    projection_calibration_backtests()
  )
  result <- summarize_projection_backtests(backtests)

  expect_equal(result$wape, 0.10)
  expect_equal(result$weighted_bias, 0.10)
  expect_equal(result$direction_consistency, 1)
  expect_equal(result$pct_error_sd, 0)
  expect_match(result$signed_error_history, "Fall 2018: \\+10.0%")
  expect_equal(result$proposed_calibration_factor, 100 / 110)
})

test_that("projection previews explain bias correction state", {
  result <- projection_preview_bias_correction(
    applied = c(TRUE, FALSE, FALSE, FALSE),
    factor = c(0.912, 1.08, 1, 1),
    adjustment = c(-42, 0, 0, 0),
    candidate = c(TRUE, TRUE, FALSE, FALSE),
    n_validation = c(2L, 0L, 0L, 0L),
    reason = c(
      "Validated calibration improved WAPE by 5.0%",
      "Stable bias found; needs 2 rolling calibration aftcasts",
      "Signed errors are not directionally consistent",
      NA_character_
    ),
    n_backtests = c(6L, 4L, 4L, 0L),
    min_validation = 2L
  )

  expect_equal(result[[1]], "Applied x0.912 (-42 students)")
  expect_equal(result[[2]], "Pending validation: 0/2 trials")
  expect_equal(
    result[[3]],
    "Not applied: signed errors are not directionally consistent"
  )
  expect_equal(result[[4]], "Not assessed: no eligible aftcasts")
})

test_that("rolling calibration uses only prior aftcasts and must improve", {
  backtests <- add_projection_rolling_calibration(
    projection_calibration_backtests()
  )
  result <- summarize_projection_backtests(backtests)

  expect_false(any(backtests$calibration_applied[1:4]))
  expect_true(all(backtests$calibration_applied[5:6]))
  expect_equal(backtests$calibrated_projected_classlist_total[5:6], c(100, 100))
  expect_equal(result$n_calibrated_backtests, 2L)
  expect_equal(result$calibration_comparison_wape, 0.10)
  expect_equal(result$calibrated_wape, 0)
  expect_equal(result$calibration_wape_gain, 0.10)
  expect_true(result$calibration_validated)
  expect_true(result$calibration_recommended)

  candidate <- projection_candidate("seasonal_last") %>%
    dplyr::mutate(
      market_id = "abq_ea_course_market", college = "AS",
      subject_course = "TEST 101", term_type = "fall",
      target_term = 202480L, projected_classlist_total = 110,
      applicable = TRUE, .before = 1
    )
  adjusted <- attach_projection_performance(candidate, result)
  expect_equal(adjusted$raw_projected_classlist_total, 110)
  expect_equal(adjusted$projected_classlist_total, 100)
  expect_equal(adjusted$calibration_adjustment, -10)
  expect_true(adjusted$calibration_applied)

  fractional <- dplyr::mutate(candidate, projected_classlist_total = 110.4)
  published <- select_projection_methods(fractional, result, backtests)
  expect_equal(published$projected_classlist_total, 100)
  expect_equal(
    published$calibrated_projected_classlist_total,
    110.4 * result$proposed_calibration_factor
  )
  expect_true(validate_projection_calibration_rows(
    published, "test published projections", published = TRUE
  ))
})

test_that("inconsistent signed errors do not qualify for calibration", {
  backtests <- projection_calibration_backtests(
    projected = c(130, 130, 130, 90, 90, 90)
  )
  fit <- projection_calibration_fit(backtests, "observed_enrollment")

  expect_equal(fit$weighted_bias, 0.10)
  expect_equal(fit$direction_consistency, 0.50)
  expect_false(fit$applicable)
  expect_match(fit$reason, "not directionally consistent")
})

test_that("structural calibration is learned and validated only on slack terms", {
  constrained <- c(FALSE, FALSE, FALSE, FALSE, TRUE, TRUE)
  backtests <- projection_calibration_backtests(
    method_id = "spring_cohort_flow", method_role = "structural_demand",
    constrained = constrained
  )
  rolling <- add_projection_rolling_calibration(backtests)
  result <- summarize_projection_backtests(rolling)

  expect_true(all(rolling$calibration_applied[5:6]))
  expect_equal(result$calibration_training_n, 4L)
  expect_equal(result$n_calibrated_backtests, 0L)
  expect_false(result$calibration_validated)
  expect_false(result$calibration_recommended)
  expect_match(result$calibration_reason, "needs 2 rolling")

  mostly_constrained <- projection_calibration_backtests(
    method_id = "spring_cohort_flow", method_role = "structural_demand",
    constrained = c(FALSE, FALSE, TRUE, TRUE, TRUE, TRUE)
  )
  fit <- projection_calibration_fit(mostly_constrained, "structural_demand")
  expect_equal(fit$n, 2L)
  expect_false(fit$applicable)
})

test_that("rows with no applicable method remain explicit", {
  row <- projection_test_row()
  candidates <- projection_candidate("seasonal_median") %>%
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
  expect_equal(selected$confidence, "None")
  expect_match(selected$confidence_reason, "No applicable")
})

test_that("cone preserves candidate provenance when backtests are empty", {
  row <- projection_test_row()
  inputs <- list(
    enrollment_history = projection_test_history(100, terms = 202380L),
    section_history = tibble::tibble(
      market_id = "abq_ea_course_market", college = "AS", department = "TEST",
      course_title = "Test Course", subject_course = "TEST 101",
      term = 202480L, term_type = "fall",
      scheduled_sections = 3L, scheduled_enrl = 0,
      scheduled_capacity = 120, n_delivery_components = 2L,
      n_campuses = 2L, capacity_per_section = 40
    ),
    students = list(
      course_enrollments = tibble::tibble(
        student_id = character(), term = integer(),
        subject_course = character()
      ),
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
    delivery_components = empty_projection_test_components()
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
    delivery_components = empty_projection_test_components()
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
  expect_true(all(c("method_id", "confidence", "recommendation") %in%
                    names(bundle$projections)))
  expect_true(validate_enrollment_projection_bundle(bundle))
})

test_that("projection bundles round-trip with method evidence", {
  row <- projection_test_row()
  projections <- tibble::tibble(
    market_id = "abq_ea_course_market", college = "AS", department = "TEST",
    subject_course = "TEST 101", term_type = "fall",
    target_term = 202480L, target_term_label = "Fall 2024",
    projected_classlist_total = 120,
    census_retention_rate = 0.95, census_retention_n_terms = 3L,
    census_retention_terms = "202180,202280,202380",
    projected_census_equivalent = 114,
    method_id = "seasonal_median", method_label = "Seasonal median",
    n_backtests = 3L, wape = 0.10, capacity_censored_wape = 0.08,
    uncensored_wape = 0.10, confidence = "Medium",
    selection_wape = 0.10, selection_n_backtests = 3L,
    selection_pct_error_sd = 0.04,
    selection_basis = "All-term WAPE", selection_uses_uncensored = FALSE,
    capacity_constrained_history = FALSE, n_capacity_unreached = 2L,
    confidence_reason = "3 aftcasts with 10.0% WAPE",
    why_uncertain = "Historical aftcast evidence meets the displayed confidence threshold",
    recommendation = "Monitor near capacity", observed_baseline = 120,
    capacity_data_quality = "Usable", demand_signal = "Not indicated",
    target_schedule_available = TRUE,
    raw_projected_classlist_total = 120, calibrated_projected_classlist_total = 120,
    calibration_factor = 1,
    calibration_applied = FALSE, calibration_adjustment = 0,
    weighted_bias = 0.02, direction_consistency = 0.67,
    signed_error_history = "Fall 2021: +2.0%",
    proposed_calibration_factor = 0.98,
    calibration_candidate = FALSE, n_calibrated_backtests = 0L,
    calibration_validated = FALSE,
    calibration_recommended = FALSE, calibrated_wape = NA_real_,
    calibration_wape_gain = NA_real_,
    calibration_reason = "Weighted bias is below the calibration threshold",
    n_capacity_censored_misses = 1L,
    capacity_explained_error_share = 0.20,
    capacity_miss_assessment = "Capacity may explain part of the apparent error",
    target_classlist_total_to_date = 140, target_registered_now = 135,
    target_early_drops_to_date = 5, target_late_drops_to_date = 0,
    target_other_status_to_date = 0,
    target_registration_observed = TRUE, target_available_seats = 5,
    target_classlist_fill = 1, target_active_fill = 135 / 140,
    target_capacity_reached = TRUE,
    projected_over_capacity = 0, capacity_limit_signal = FALSE,
    capacity_limit_status = "Projection fits scheduled capacity",
    capacity_limit_note = "5 currently available seat(s)",
    recommended_sections = 4L,
    population_projection = 118, population_observed_wape = 0.12,
    population_n_backtests = 3L,
    spring_flow_projection = 122, spring_flow_observed_wape = 0.09,
    spring_flow_n_backtests = 3L,
    coupling_n_backtests = 3L, coupling_wape_gain = 0.03,
    coupling_status = "Major/classification",
    coupling_reason = "Major/classification improves WAPE by 3.0% versus broad population growth",
    backtest_terms = "202180,202280,202380",
    backtest_term_range = "Fall 2021 to Fall 2023"
  )
  candidates <- tibble::tibble(
    market_id = "abq_ea_course_market", college = "AS",
    subject_course = "TEST 101", term_type = "fall",
    target_term = 202480L, target_term_label = "Fall 2024",
    method_id = "seasonal_median", method_label = "Seasonal median",
    method_role = "observed_enrollment",
    projected_classlist_total = 120, applicable = TRUE, selected = TRUE,
    census_retention_rate = 0.95, census_retention_n_terms = 3L,
    census_retention_terms = "202180,202280,202380",
    projected_census_equivalent = 114,
    raw_projected_classlist_total = 120, calibration_factor = 1,
    calibration_applied = FALSE, calibration_adjustment = 0,
    n_backtests = 3L, wape = 0.10, census_equivalent_wape = 0.10,
    uncensored_wape = 0.10, weighted_bias = 0.02, pct_error_sd = 0.04,
    uncensored_pct_error_sd = 0.04,
    direction_consistency = 0.67,
    signed_error_history = "Fall 2021: +2.0%",
    proposed_calibration_factor = 0.98,
    calibration_recommended = FALSE, calibrated_wape = NA_real_,
    calibration_wape_gain = NA_real_,
    calibration_reason = "Weighted bias is below the calibration threshold",
    capacity_censored_wape = 0.08, n_capacity_censored_misses = 1L,
    capacity_explained_wape = 0.02,
    capacity_explained_error_share = 0.20,
    capacity_censored_terms = "202280",
    capacity_miss_assessment = "Capacity may explain part of the apparent error",
    backtest_terms = "202180,202280,202380",
    backtest_term_range = "Fall 2021 to Fall 2023",
    baseline_term = NA_integer_, prior_source_term = NA_integer_,
    source_term = NA_integer_, baseline_classlist_total = NA_real_,
    matched_baseline = NA_real_, unmatched_baseline = NA_real_,
    matched_projection = NA_real_, unmatched_projection = NA_real_,
    source_population_previous = NA_real_,
    source_population_current = NA_real_,
    source_population_growth = NA_real_, projection_formula = NA_character_
  )
  delivery_components <- tibble::tibble(
    market_id = "abq_ea_course_market",
    campus = c("ABQ", "EA"), college = "AS", department = "TEST",
    subject_course = "TEST 101", part_term = "1", target_term = 202480L,
    target_term_label = "Fall 2024", scheduled_sections = c(3L, 1L),
    scheduled_enrl = c(95, 30), scheduled_capacity = c(105, 35),
    capacity_share = c(0.75, 0.25), prior_comparable_term = 202380L,
    prior_census_enrl = c(88, 27), prior_scheduled_capacity = c(100, 30),
    prior_census_fill = c(0.88, 0.90)
  )
  recent_history <- empty_projection_recent_history() %>%
    tibble::add_row(
      market_id = "abq_ea_course_market", college = "AS", department = "TEST",
      subject_course = "TEST 101", term_type = "fall",
      projection_target_term = 202480L, history_term = 202380L,
      history_term_label = "Fall 2023", recency_rank = 1L,
      actual_classlist_total = 130, actual_census = 120,
      actual_final_enrollment = 115,
      actual_census_retention_rate = 120 / 130,
      scheduled_sections = 4L, scheduled_capacity = 140,
      prior_classlist_total = 125, prior_scheduled_capacity = 135,
      classlist_change = 4 / 100, capacity_change = 5 / 135,
      census_fill = 120 / 140, registration_fill = 130 / 140,
      registration_capacity_gap = 10,
      capacity_usable = TRUE, capacity_reached = FALSE,
      method_id = "seasonal_median", method_label = "Seasonal median",
      aftcast_applicable = TRUE, aftcast_reason = "Median of prior falls",
      raw_aftcast_classlist_total = 125, aftcast_classlist_total = 125,
      calibration_applied = FALSE, calibration_factor = 1,
      aftcast_error = -5, aftcast_pct_error = -5 / 130,
      aftcast_capacity_censored = FALSE,
      aftcast_censored_error = -5,
      aftcast_censored_pct_error = -5 / 130,
      potential_miss_explanation =
        "Aftcast was within 10% of observed class-list enrollment"
    )
  analysis <- list(
    pressure_screen = row,
    projections = projections,
    delivery_components = delivery_components,
    candidates = candidates,
    backtests = tibble::tibble(),
    method_performance = empty_projection_performance(),
    recent_history = recent_history
  )
  bundle <- new_enrollment_projection_bundle(
    analysis, 202480L, 202380L,
    scope_courses = "TEST 101", scope_campuses = c("ABQ", "EA"),
    scope_market_id = "abq_ea_course_market",
    model_provenance = enrollment_projection_model_provenance(),
    source_fingerprint = list(students = "fixture"),
    built_at = as.POSIXct("2026-08-15 12:00:00", tz = "UTC")
  )
  path <- file.path(tempdir(), "projection-bundle.qs")

  write_enrollment_projection_bundle(bundle, path)
  restored <- read_enrollment_projection_bundle(path)

  expect_equal(restored$model_version, CEDAR_ENROLLMENT_PROJECTION_MODEL_VERSION)
  expect_equal(restored$model_provenance, bundle$model_provenance)
  expect_equal(restored$scope_courses, "TEST 101")
  expect_equal(restored$scope_campuses, c("ABQ", "EA"))
  expect_equal(restored$scope_market_id, "abq_ea_course_market")
  expect_equal(restored$projections, projections)
  expect_equal(restored$delivery_components, delivery_components)
  expect_equal(restored$candidates, candidates)
  expect_equal(restored$recent_history, recent_history)
  source_manifest <- enrollment_projection_model_source(restored)
  expect_true(all(c("path", "sha256") %in% names(source_manifest)))
  expect_true("R/branches/enrollment-projections.R" %in% source_manifest$path)
  expect_match(
    enrollment_projection_model_source(
      restored, "R/branches/enrollment-projections.R"
    ),
    "new_enrollment_projection_bundle <- function",
    fixed = TRUE
  )
  # A model-policy change requires rebuilding even when the file shape matches.
  pre_audit_fix <- restored
  pre_audit_fix$model_version <- "0.16.0"
  pre_audit_fix$model_provenance$model_version <- "0.16.0"
  expect_error(validate_enrollment_projection_bundle(pre_audit_fix),
               "Unsupported projection model version")

  archived <- restored
  archived$model_version <- "0.10.0"
  archived$schema_version <- 11L
  archived$model_provenance$model_version <- "0.10.0"
  archived$model_provenance$schema_version <- 11L
  archived_path <- file.path(tempdir(), "archived-projection-bundle.qs")
  qs2::qs_save(archived, archived_path)
  expect_match(
    enrollment_projection_model_source(
      archived_path, "R/branches/enrollment-projections.R"
    ),
    "new_enrollment_projection_bundle <- function",
    fixed = TRUE
  )
  expect_error(
    validate_enrollment_projection_bundle(archived),
    "Unsupported projection bundle schema version"
  )

  view <- build_enrollment_projection_view(
    restored, list(group_id = "all_saved", departments = "TEST")
  )
  expect_equal(view$meta$n_rows, 1L)
  expect_equal(view$table$course, "TEST 101")
  expect_equal(view$table$planning_sections, 4L)
  expect_equal(view$method_guide$n_candidates, 9L)
  expect_equal(view$method_guide$n_ideas, 6L)
  expect_false(any(c("coupling", "bias_correction", "recommendation") %in%
                     names(view$table)))
  detail <- enrollment_projection_course_detail(view, "TEST 101")
  expect_equal(detail$history$history_term, 202380L)
  expect_equal(nrow(detail$candidates), 1L)
  expect_equal(
    nrow(build_enrollment_projection_view(
      restored, list(group_id = "always_monitored")
    )$table),
    0L
  )

  preview <- format_enrollment_projection_preview(restored, "TEST 101")
  expect_equal(preview[[1]], "# Enrollment Projection Preview")
  expect_true(any(grepl("Target: Fall 2024", preview, fixed = TRUE)))
  expect_true(any(grepl("| TEST 101 |", preview, fixed = TRUE)))
  expect_true(any(grepl("| Fall 2024 |", preview, fixed = TRUE)))
  expect_true(any(grepl("Fall 2021 to Fall 2023", preview, fixed = TRUE)))
  expect_true(any(grepl("Monitor near capacity", preview, fixed = TRUE)))
  expect_true(any(grepl("Bias correction", preview, fixed = TRUE)))
  expect_true(any(grepl("Coupling", preview, fixed = TRUE)))
  expect_true(any(grepl("Potential explanation", preview, fixed = TRUE)))
  expect_true(any(grepl(
    "Not applied: weighted bias is below the calibration threshold",
    preview,
    fixed = TRUE
  )))
  expect_true(any(grepl("capacity-bounded", preview, ignore.case = TRUE)))
  expect_true(any(grepl("not a claim of zero error", preview, fixed = TRUE)))
  expect_true(any(grepl("| Fall 2023 |", preview, fixed = TRUE)))
  expect_true(any(grepl("|    120 |", preview, fixed = TRUE)))

  bundle_dir <- file.path(tempdir(), paste0("projection-latest-", Sys.getpid()))
  dir.create(bundle_dir, recursive = TRUE, showWarnings = FALSE)
  latest_path <- file.path(
    bundle_dir, "enrollment-projections-202480-latest.qs"
  )
  write_enrollment_projection_bundle(restored, latest_path)
  expect_equal(
    find_latest_enrollment_projection_bundle(bundle_dir), latest_path
  )
  expect_equal(
    load_latest_enrollment_projection_bundle(bundle_dir)$target_term, 202480L
  )

  invalid <- bundle
  invalid$candidates$selected <- FALSE
  expect_error(
    validate_enrollment_projection_bundle(invalid),
    "selected candidates disagree"
  )

  invalid_values <- bundle
  invalid_values$projections$projected_classlist_total[[1]] <- 999
  expect_error(
    validate_enrollment_projection_bundle(invalid_values),
    "projection values and selected candidates disagree"
  )

  invalid_scope <- bundle
  invalid_scope$delivery_components$campus[[1]] <- "GA"
  expect_error(
    validate_enrollment_projection_bundle(invalid_scope),
    "outside the saved scope"
  )

  invalid_calibration <- bundle
  invalid_calibration$candidates$calibration_applied <- TRUE
  invalid_calibration$candidates$calibration_factor <- 0.90
  expect_error(
    validate_enrollment_projection_bundle(invalid_calibration),
    "invalid projection calibration audit trail"
  )

  invalid_source <- bundle
  invalid_source$model_provenance$source_snapshot[[1]] <- paste0(
    invalid_source$model_provenance$source_snapshot[[1]], "\n# changed"
  )
  expect_error(
    validate_enrollment_projection_bundle(invalid_source),
    "does not match its hashes"
  )
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
  expect_equal(bundle$model_config$calibration_min_terms, 4L)
  expect_equal(bundle$model_config$calibration_min_validation_terms, 2L)
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
    "observed_baseline", "spring_flow_projection", "feeder_projection",
    "capacity_data_quality", "demand_signal"
  ) %in% names(bundle$projections)))
})

test_that("published projection builder rejects non-Spring targets", {
  expect_error(
    build_enrollment_projection_bundle(
      cl_enrls = tibble::tibble(), sections = tibble::tibble(),
      students = tibble::tibble(), target_term = 202180L,
      as_of_term = 202160L, scope_courses = "TEST 101",
      scope_campuses = "ABQ", scope_market_id = "abq_course_market"
    ),
    "support Spring targets only"
  )
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
