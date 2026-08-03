context("Pathways branch helpers")


test_that("pathways_level_filter translates UI values to CEDAR level values", {
  expect_null(pathways_level_filter("all"))
  expect_null(pathways_level_filter(""))
  expect_equal(pathways_level_filter("undergrad"), c("lower", "upper"))
  expect_equal(pathways_level_filter("lower"), "lower")
  expect_equal(pathways_level_filter("upper"), "upper")
  expect_equal(pathways_level_filter("grad"), "grad")
})


test_that("filter_pathways_analysis_population excludes unclear entry rows only for entry split", {
  hist_pop <- build_population(
    test_programs, test_degrees,
    opt = list(type = "preset", program_names = "History", split_by = "entry")
  )

  filtered <- filter_pathways_analysis_population(hist_pop, split_by = "entry")

  expect_true("unclear" %in% hist_pop$entry_method)
  expect_false("unclear" %in% filtered$entry_method)
  expect_lt(nrow(filtered), nrow(hist_pop))
})


test_that("filter_pathways_analysis_population applies selected population label", {
  hist_pop <- build_population(
    test_programs, test_degrees,
    opt = list(type = "preset", program_names = "History", split_by = "transfer")
  )
  label <- hist_pop$population_label[1]

  filtered <- filter_pathways_analysis_population(
    hist_pop, split_by = "transfer", selected_label = label
  )

  expect_true(nrow(filtered) > 0)
  expect_true(all(filtered$population_label == label))
})


test_that("resolve_pathways_focal_dept_codes resolves selected program names", {
  opt <- list(type = "major", program_names = "History")

  dept_codes <- resolve_pathways_focal_dept_codes(opt, test_programs)

  expect_equal(dept_codes, "HIST")
})


test_that("resolve_pathways_focal_subjects uses subject lookup, not dept code as course prefix", {
  opt <- list(type = "dept", dept_code = "GES")

  subjects <- resolve_pathways_focal_subjects(opt, test_programs, test_lookups)

  expect_true("GEOG" %in% subjects)
  expect_false("GES" %in% subjects)
})


test_that("resolve_pathways_gen_ed_courses keeps only focal subject courses", {
  opt <- list(type = "dept", dept_code = "HIST")
  focal_subjects <- resolve_pathways_focal_subjects(opt, test_programs, test_lookups)

  courses <- resolve_pathways_gen_ed_courses(focal_subjects)

  expect_true(length(courses) > 0)
  expect_true(all(sub(" .*", "", courses) %in% focal_subjects))
})


test_that("pathways_observation_boundary walks back complete regular terms", {
  # One term of follow-up: Fall 2025 outcomes need Spring 2026 complete.
  expect_equal(pathways_observation_boundary(202610L, 1L), 202580L)
  # Two terms of follow-up (e.g. course-pairs max gap = 2).
  expect_equal(pathways_observation_boundary(202510L, 2L), 202410L)
  # Summer input steps back to the prior regular term.
  expect_equal(pathways_observation_boundary(202560L, 1L), 202510L)
  # Zero follow-up = the boundary is the last complete term itself.
  expect_equal(pathways_observation_boundary(202510L, 0L), 202510L)
})

test_that("pathways_observation_boundary returns NULL when the anchor is unknown", {
  expect_null(pathways_observation_boundary(NULL, 1L))
  expect_null(pathways_observation_boundary(NA_integer_, 1L))
})


# =============================================================================
# pathways_coverage_facts() — what the data window can see about a population
# =============================================================================
#
# These counts back an on-screen disclosure, so the failure that matters is
# overstating coverage: a student whose record is bounded at either end must not
# be counted as fully readable.

cov_pop <- function() {
  tibble::tibble(
    student_id = paste0("S", 1:6),
    # S1 starts at the data edge -> truncated. S2 ends at the edge -> censored.
    # S3 is both. S4/S5/S6 sit inside the window -> complete.
    first_unm_term   = c(202010L, 202080L, 202010L, 202080L, 202110L, 202080L),
    last_record_term = c(202310L, 202480L, 202480L, 202310L, 202310L, 202380L)
  )
}

test_that("coverage facts count truncation, censoring and complete records", {
  f <- pathways_coverage_facts(cov_pop(), min_data_term = 202010L, max_data_term = 202480L)

  expect_equal(f$n, 6)
  expect_equal(f$n_truncated, 2)   # S1, S3
  expect_equal(f$n_censored, 2)    # S2, S3
  expect_equal(f$n_complete, 3)    # S4, S5, S6
  expect_equal(f$pct_complete, 50)
})

test_that("a student at the boundary counts as unreadable, not as a clean start", {
  # first_unm_term == min_data_term cannot be distinguished from "started earlier",
  # so it must fall on the truncated side. Counting it as complete would overstate
  # coverage, which is the one direction this must never fail.
  f <- pathways_coverage_facts(
    tibble::tibble(student_id = "S1", first_unm_term = 202010L, last_record_term = 202310L),
    min_data_term = 202010L, max_data_term = 202480L)

  expect_equal(f$n_truncated, 1)
  expect_equal(f$n_complete, 0)
})

test_that("coverage facts return NA rather than a confident zero when bookends are missing", {
  f <- pathways_coverage_facts(
    tibble::tibble(student_id = c("S1", "S2")),
    min_data_term = 202010L, max_data_term = 202480L)

  expect_equal(f$n, 2)
  expect_true(is.na(f$pct_truncated))
  expect_true(is.na(f$n_complete))
})

test_that("an empty population yields NA counts, not zero coverage", {
  f <- pathways_coverage_facts(cov_pop()[0, ], min_data_term = 202010L, max_data_term = 202480L)
  expect_equal(f$n, 0)
  expect_true(is.na(f$pct_truncated))
})

test_that("coverage percentages never exceed 100 or fall below 0", {
  f <- pathways_coverage_facts(cov_pop(), min_data_term = 202010L, max_data_term = 202480L)
  for (p in c(f$pct_truncated, f$pct_censored, f$pct_complete)) {
    expect_gte(p, 0); expect_lte(p, 100)
  }
})
