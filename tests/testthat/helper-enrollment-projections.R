# Shared scaffolds for the enrollment projection tests: prepared pipeline
# frames, fixture bundles and backtest builders. Method tests use prepared
# frames rather than raw institutional tables; those shapes exist only after
# prepare_enrollment_projection_inputs(), so keeping them here follows the
# fixture boundary documented in developers/testing.md.

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

# EC-11's SOCI 100 at Fall 2020 is taught on two campuses: ABQ in a full-term
# and a first-half session (107 + 28 on the first day, 200 seats) and EA
# (58 of 100). Pooled, the market reads 193 of 300; each campus keeps its own.
campus_history_scaffold <- function(history_term) tibble::tibble(
  market_id = "abq_ea_course_market", subject_course = "SOCI 100",
  projection_target_term = 202180L, history_term = history_term,
  recency_rank = 1L
)

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

# 40 students in the baseline roster, 10 of them Nursing: a 25% share. Every
# expected value below is derived from these two numbers and the published
# projection, so a changed expectation means the arithmetic moved.
scenario_test_composition <- function(cohort = 10L, others = 30L) {
  tibble::tibble(
    market_id = "abq_course_market",
    subject_course = "MATH 1215Z",
    baseline_term = 202010L,
    major_code = c("NURS", "BIOL"),
    student_classification = "Sophomore",
    n_students = c(cohort, others)
  )
}
