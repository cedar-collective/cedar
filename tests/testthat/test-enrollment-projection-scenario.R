context("Enrollment projection scenarios")

# The scenario is arithmetic over rows the bundle already carries, so these
# tests supply that intermediate frame directly rather than routing raw students
# through the whole pipeline. Whether the pipeline actually WRITES matchable
# major codes into cohort_composition is a join-key question the designed
# fixtures cannot express -- test_students$major_code is entirely NA -- and is
# covered by the real-data audit documented in developers/enrollment-projections.md.

scenario_test_bundle <- function(composition = NULL) {
  settled_students <- test_students %>%
    dplyr::mutate(as_of_date = .cedar_term_start(term) + 30L)
  bundle <- build_enrollment_projection_bundle(
    cl_enrls = calc_cl_enrls(settled_students, by_part_term = TRUE),
    sections = test_sections,
    students = settled_students,
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

test_that("year one is the published projection at any growth rate", {
  bundle <- scenario_test_bundle(scenario_test_composition())
  published <- build_enrollment_projection_view(
    bundle, list(group_id = "all_saved")
  )$projections$projected_classlist_total[[1]]

  for (rate in c(0, 0.10, 0.25)) {
    scenario <- build_enrollment_projection_scenario(
      bundle, opt = list(group_id = "all_saved", major_codes = "NURS",
                         growth_rate = rate, horizon_years = 5L,
                         min_population_cohort = 1L)
    )
    year_one <- scenario$rows %>% dplyr::filter(year_index == 1L)
    expect_equal(year_one$projected_classlist_total[[1]], published)
    expect_equal(year_one$basis[[1]], "Published projection")
  }
})

test_that("zero growth is flat and only the population's share moves demand", {
  bundle <- scenario_test_bundle(scenario_test_composition())
  published <- build_enrollment_projection_view(
    bundle, list(group_id = "all_saved")
  )$projections$projected_classlist_total[[1]]
  base_opt <- list(group_id = "all_saved", major_codes = "NURS",
                   horizon_years = 5L, min_population_cohort = 1L)

  flat <- build_enrollment_projection_scenario(
    bundle, opt = utils::modifyList(base_opt, list(growth_rate = 0))
  )
  expect_true(all(flat$rows$projected_classlist_total == published))

  grown <- build_enrollment_projection_scenario(
    bundle, opt = utils::modifyList(base_opt, list(growth_rate = 0.10))
  )
  # 10 Nursing students growing 10% a year add 1.0, 2.1, 3.31, 4.641 students by
  # years 2-5. The other 30 students are held flat -- growth must NOT scale the
  # whole course, which is the mistake that makes a 10% assumption look like a
  # 10% enrollment increase.
  expect_equal(
    grown$rows$projected_classlist_total - published,
    c(0, 1, 2.1, 3.31, 4.641), tolerance = 1e-9
  )
  expect_equal(grown$courses$population_share[[1]], 0.25)
  expect_equal(grown$rows$basis, c("Published projection", rep("Scenario", 4)))
})

test_that("the horizon advances one year per step in the target's own season", {
  bundle <- scenario_test_bundle(scenario_test_composition())
  scenario <- build_enrollment_projection_scenario(
    bundle, opt = list(group_id = "all_saved", major_codes = "NURS",
                       growth_rate = 0.10, horizon_years = 3L,
                       min_population_cohort = 1L)
  )

  expect_equal(scenario$rows$target_term, c(202110L, 202210L, 202310L))
  expect_equal(scenario$rows$target_term_label,
               c("Spring 2021", "Spring 2022", "Spring 2023"))
})

test_that("sections round up from unrounded demand and never go negative", {
  bundle <- scenario_test_bundle(scenario_test_composition())
  scenario <- build_enrollment_projection_scenario(
    bundle, opt = list(group_id = "all_saved", major_codes = "NURS",
                       growth_rate = 0.50, horizon_years = 5L,
                       min_population_cohort = 1L)
  )
  rows <- scenario$rows

  expected <- projection_sections_for_demand(
    rows$projected_classlist_total, rows$reference_section_size
  )
  expect_equal(rows$recommended_sections, expected)
  expect_true(all(rows$additional_sections >= 0L, na.rm = TRUE))
  # Demand rises, so the section requirement can never fall along the horizon.
  expect_false(is.unsorted(rows$recommended_sections[!is.na(rows$recommended_sections)]))
})

test_that("a cohort below the guard is reported, not silently dropped", {
  bundle <- scenario_test_bundle(scenario_test_composition(cohort = 3L))
  scenario <- build_enrollment_projection_scenario(
    bundle, opt = list(group_id = "all_saved", major_codes = "NURS",
                       growth_rate = 0.10, min_population_cohort = 10L)
  )

  expect_equal(nrow(scenario$rows), 0L)
  expect_equal(scenario$excluded$subject_course, "MATH 1215Z")
  expect_match(scenario$excluded$ineligible_reason[[1]], "Only 3 of this population")
  expect_equal(scenario$meta$n_excluded, 1L)
})

test_that("a course with none of the population is excluded with a reason", {
  bundle <- scenario_test_bundle(scenario_test_composition(cohort = 0L))
  scenario <- build_enrollment_projection_scenario(
    bundle, opt = list(group_id = "all_saved", major_codes = "PHRD",
                       growth_rate = 0.10, min_population_cohort = 1L)
  )

  expect_equal(nrow(scenario$rows), 0L)
  expect_equal(nrow(scenario$excluded), 1L)
  expect_match(scenario$excluded$ineligible_reason[[1]], "Only 0 of this population")
})

test_that("the scenario fails loudly rather than guessing", {
  bundle <- scenario_test_bundle(scenario_test_composition())

  expect_error(
    build_enrollment_projection_scenario(bundle, opt = list(growth_rate = 0.1)),
    "population_group or explicit major_codes"
  )
  expect_error(
    build_enrollment_projection_scenario(
      bundle, opt = list(population_group = "Health Professions (Clinical)")
    ),
    "cedar_programs is required"
  )
  expect_error(
    build_enrollment_projection_scenario(
      bundle, opt = list(major_codes = "NURS", horizon_years = 0L)
    ),
    "horizon_years must be at least 1"
  )
  # A bundle predating the composition payload cannot silently produce a
  # scenario of zeros.
  stripped <- bundle
  stripped$cohort_composition <- stripped$cohort_composition[0, ]
  expect_error(
    build_enrollment_projection_scenario(
      stripped, opt = list(major_codes = "NURS")
    ),
    "carries no cohort_composition"
  )
})

test_that("meta states the assumption and names the population", {
  bundle <- scenario_test_bundle(scenario_test_composition())
  scenario <- build_enrollment_projection_scenario(
    bundle, programs = test_programs_hp,
    opt = list(group_id = "all_saved",
               population_group = "Health Professions (Clinical)",
               growth_rate = 0.10, min_population_cohort = 1L)
  )

  expect_equal(scenario$meta$population_label, "Health Professions (Clinical)")
  expect_true("NURS" %in% scenario$meta$population_codes)
  expect_match(scenario$meta$assumption, "held flat")
  expect_match(scenario$meta$assumption, "10.0%")
})
