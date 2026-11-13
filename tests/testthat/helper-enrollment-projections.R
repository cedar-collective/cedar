# What the enrollment projection tests do: stamp a stated series on a prepared
# row, build a bundle over the designed fixtures, set scenario options. Method
# tests use prepared frames rather than raw institutional tables; those shapes
# exist only after prepare_enrollment_projection_inputs(), and the typed rows
# themselves are fixed tables in fixtures/scenario_tables.R.

# A method test states its series; this stamps it on the prepared history row
# (projection_history_row), one row per term, in every count column.
projection_test_history <- function(values = c(100, 110, 120, 130),
                                    terms = c(202080L, 202180L, 202280L, 202380L),
                                    course = "TEST 101") {
  projection_history_row[rep(1L, length(terms)), ] %>%
    dplyr::mutate(
      subject_course = course, term = terms,
      dplyr::across(c(registered, classlist_total, first_day_enrl,
                      first_day_started_enrl, census_enrl), ~ values)
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

# The scenario's feeders carry 5 students a pair, so these tests lower the
# transition floor from the default 20; the lift rule is the default.
projection_scenario_opt <- function(...) list(feeder_min_students = 3L, ...)

# Full aftcast rows for one method, shaped exactly as
# backtest_course_projection_methods() produces them, so selection and its
# realised record can be exercised without running the whole engine. The test
# states the method and its projected and actual series; they are stamped on
# the prepared aftcast row (projection_backtest_row), one row per term.
projection_policy_backtests <- function(method_id, projected, actual,
                                        terms = seq(202080L, by = 100L,
                                                    length.out = length(projected)),
                                        first_day = actual, capacity = 2 * actual,
                                        course = "TEST 101",
                                        opt = list()) {
  # Resolved before mutate() so the column named method_id cannot mask the
  # argument inside the data mask.
  method <- method_id
  method_label <- unname(CEDAR_ENROLLMENT_PROJECTION_METHODS[[method]])
  method_role <- unname(CEDAR_ENROLLMENT_PROJECTION_METHOD_ROLES[[method]])
  projection_backtest_row[rep(1L, length(terms)), ] %>%
    dplyr::mutate(
      subject_course = course,
      target_term = terms, target_term_label = vapply(terms, fmt_term, character(1)),
      method_id = method, method_label = .env$method_label, method_role = .env$method_role,
      projected_classlist_total = projected, projected_first_day_equivalent = projected,
      actual_classlist_total = actual, actual_first_day = first_day,
      actual_census = first_day, actual_final_enrollment = first_day,
      scheduled_capacity = capacity
    ) %>%
    add_projection_capacity_censoring(opt) %>%
    dplyr::mutate(raw_projected_classlist_total = projected_classlist_total)
}

projection_policy_candidates <- function(method_ids, projections,
                                         course = "TEST 101") {
  row <- dplyr::mutate(projection_test_row, subject_course = course)
  dplyr::bind_rows(lapply(seq_along(method_ids), function(i) {
    projection_candidate(method_ids[[i]], projections[[i]], TRUE, "ok")
  })) %>%
    dplyr::mutate(
      market_id = row$market_id, college = row$college,
      subject_course = row$subject_course, term_type = row$term_type,
      target_term = row$target_term, .before = 1
    )
}

scenario_test_bundle <- function(composition = NULL) {
  settled_students <- test_students %>%
    dplyr::mutate(as_of_date = .cedar_term_start(term) + 30L)
  bundle <- build_enrollment_projection_bundle(
    cl_enrls = calc_cl_enrls(settled_students, by_part_term = TRUE),
    sections = test_sections,
    students = settled_students,
    student_terms = test_student_terms,
    target_term = 202110L,
    as_of_term = 202080L,
    scope_courses = "MATH 1215Z",
    scope_campuses = "ABQ",
    scope_market_id = "abq_course_market",
    force_courses = "MATH 1215Z",
    # 202010 is the one prior Spring in the fixture, so the course gets a
    # real published projection (5 students) to anchor the scenario on.
    opt = list(history_start_term = 202010L),
    built_at = as.POSIXct("2026-08-15 12:00:00", tz = "UTC")
  )
  if (!is.null(composition)) bundle$cohort_composition <- composition
  bundle
}
