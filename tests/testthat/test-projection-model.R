# Enrollment projections, the model: the two candidates and their audit
# trail, the plan (sections, bump, feeders), rolling selection, backtests
# and the published bundle. The saved reasons and bases are words a reader
# sees, held in snapshots (tests/testthat/_snaps): a wording change is
# accepted with testthat::snapshot_accept() and reviewed as a diff.
testthat::local_edition(3)

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
    waitlist_history = empty_projection_test_waitlists,
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
    delivery_components = empty_projection_test_components,
    delivery_section_history = empty_projection_test_delivery_sections,
    delivery_first_day = empty_projection_test_delivery_first_day
  )

  result <- get_course_enrollment_projections(
    inputs, 202480L, force_courses = "TEST 101"
  )$projections

  expect_false(result$target_schedule_available)
  # The fixture's prior Fall filled 110 of 105 seats, so the plan is a floor.
  expect_true(result$adjusted_saturated_prior)
  expect_snapshot(cat(result$recommendation))
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
    waitlist_history = empty_projection_test_waitlists,
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
    delivery_components = empty_projection_test_components,
    delivery_section_history = empty_projection_test_delivery_sections,
    delivery_first_day = empty_projection_test_delivery_first_day
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

  # More students left waiting than 5%: the bump is the waiting count.
  waiting <- bump(dplyr::mutate(row, adjusted_waitlisted_prior = 31L))
  expect_equal(waiting$pressure_bump, 31)

  # A floor the published method already added counts toward the bump:
  # max(5% of 200, 7 waiting) - 7 already in the projection = 3.
  floored <- bump(dplyr::mutate(
    row, method_id = "spine_adjusted", adjusted_waitlisted_prior = 7L,
    adjusted_floor_uplift = 7, projected_classlist_total = 207
  ))
  expect_equal(floored$pressure_bump, 3)

  # One judged Fall below the near-full line is not always near full.
  roomy <- bump(h = dplyr::mutate(history, first_day_enrl = c(190, 196, 170)))
  expect_false(roomy$pressure_bump_applied)
  expect_equal(roomy$pressure_bump, 0)

  # Each note names the terms judged and where its number came from: 5% of
  # last Fall, the students left waiting, less the floor already published,
  # or the Fall that had room.
  expect_snapshot({
    cat(full$pressure_bump_note, "\n\n")
    cat(waiting$pressure_bump_note, "\n\n")
    cat(floored$pressure_bump_note, "\n\n")
    cat(roomy$pressure_bump_note, "\n")
  })

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
  # and seats moving against the miss leave it the forecast's. In order: Low
  # by the seats, Low the forecast's own, Low with the cause unknown, High,
  # Unrated, Moderate by the seats.
  expect_length(reading, 6L)
  expect_snapshot(cat(reading, sep = "\n\n"))
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

  summary <- projection_error_sources_summary(backtests, list())
  expect_equal(summary$n_folds, 7L)
  # The five sources' labels, as the panel's rows, and the sentence over them.
  expect_snapshot({
    cat(paste0(sources$source, ": ", sources$label), sep = "\n")
    cat("\n", summary$sentence, "\n", sep = "")
  })
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
  expect_true(is.na(far$regime_alarm))
  expect_snapshot(cat(far$delta_basis))
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
  expect_snapshot(cat(none$delta_basis))

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
  # The audit trail shows the sequence's own arithmetic beside the feeders'.
  expect_snapshot(cat(result$delta_basis))
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
  open <- project_spine_adjusted(
    pending(15), s$preceding_term_history, s$section_history,
    s$waitlist_history, s$students, s$row, 202410L
  )
  expect_true(is.na(open$saturated_prior))
  expect_equal(open$floor_uplift, 0)

  # Saturated with no waitlist rows retained: the spine is itself the floor.
  none <- project_spine_adjusted(
    s$enrollment_history, s$preceding_term_history, s$section_history,
    s$waitlist_history[0, ], s$students, s$row, 202410L
  )
  expect_true(none$saturated_prior)
  expect_equal(none$floor_uplift, 0)

  # No capacity for the spine term: saturation is unknown, never assumed.
  unknown <- project_spine_adjusted(
    s$enrollment_history, s$preceding_term_history, s$section_history[0, ],
    s$waitlist_history, s$students, s$row, 202410L
  )
  expect_true(is.na(unknown$saturated_prior))
  # Each floor basis, as the audit trail states it: the fill and the sum
  # (24 + 3 = 27); no status dates; a fill settled from the sessions begun; a
  # session not yet begun with the fill it could show; no waitlist rows; and
  # no seat count to judge by.
  expect_snapshot({
    cat("floor:", result$floor_basis, "\n\n")
    cat("undated:", undated$floor_basis, "\n\n")
    cat("settled pending:", settled$floor_basis, "\n\n")
    cat("open pending:", open$floor_basis, "\n\n")
    cat("no waitlist rows:", none$floor_basis, "\n\n")
    cat("no capacity:", unknown$floor_basis, "\n")
  })
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
  # The challenger won on the four earlier terms both were made for.
  expect_snapshot(cat(selected$selection_reason))
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
  expect_snapshot(cat(selected$selection_reason))
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
  # The reason names the term-to-term variation (1.8%); the explanation says
  # the seats filled in 3 of 4, that the count may understate demand, and
  # that the two forecasts disagree.
  expect_snapshot({
    cat(selected$accuracy_reason, "\n\n")
    cat(explanation, "\n")
  })
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
  expect_snapshot(cat(selected$accuracy_reason))
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
  expect_equal(result$backtest_terms, "202210,202310")
  expect_equal(result$backtest_term_range, "Spring 2022 to Spring 2023")
  expect_snapshot(cat(result$capacity_miss_assessment))
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
  expect_snapshot(cat(selected$accuracy_reason))
})

test_that("cone preserves candidate provenance when backtests are empty", {
  row <- projection_test_row()
  inputs <- list(
    enrollment_history = projection_test_history(100, terms = 202380L),
    preceding_term_history = projection_test_history(100, terms = 202380L),
    waitlist_history = empty_projection_test_waitlists,
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
    delivery_components = empty_projection_test_components,
    delivery_section_history = empty_projection_test_delivery_sections,
    delivery_first_day = empty_projection_test_delivery_first_day
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
    waitlist_history = empty_projection_test_waitlists,
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
    delivery_components = empty_projection_test_components,
    delivery_section_history = empty_projection_test_delivery_sections,
    delivery_first_day = empty_projection_test_delivery_first_day
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
