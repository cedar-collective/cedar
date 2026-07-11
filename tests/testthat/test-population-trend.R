# Tests for population-trend.R functions
# Tests R/cones/population-trend.R
#
# .recode_population() tests are pure logic — no fixture dependency.
#
# make_population_trend() tests use test_programs (from fixtures/designed_test_data.R).
# Expected values computed from the fixtures, then hard-coded. Changes to
# population-trend.R or the fixture data should produce failures here.
#
# Reference values (HIST dept, program_type="Major", student_level="Undergraduate"):
#   Pre-Major 202010:     6 students — Transfer=1, Continuing=3, Readmit=1, Other=1
#   Pre-Major 202060:     1 student
#   Pre-Major 202080:     2 students
#   Pre-Major 202110:     3 students
#   Declared  202010:    17 students — Continuing=16, Readmit=1
#   Declared  202060:     4 students
#   Declared  202080:     4 students
#   Declared  202110:     9 students
#   Total Declared (all): 34
#   Pct sums per facet:   all 1.000 (verified)

context("Population Trend")


# =============================================================================
# .recode_population() tests — pure function, no fixture needed
# =============================================================================

test_that(".recode_population classifies First Time Freshman strings", {
  inputs   <- c("First Time Freshman", "Beginning Freshman", "First Time Freshman Transfer")
  expected <- c("First-Time Freshman", "First-Time Freshman", "First-Time Freshman")
  expect_equal(.recode_population(inputs), expected)
})

test_that(".recode_population classifies Transfer strings", {
  inputs   <- c("Transfer Student", "Transfer", "Branch to Main Campus Transfer")
  expected <- c("Transfer", "Transfer", "Transfer")
  expect_equal(.recode_population(inputs), expected)
})

test_that(".recode_population classifies Readmit strings", {
  expect_equal(.recode_population("Readmit Student"), "Readmit")
})

test_that(".recode_population classifies Continuing strings", {
  expect_equal(.recode_population("Continuing Student"), "Continuing")
})

test_that(".recode_population returns Other for Level Change and Concurrent", {
  expect_equal(.recode_population("Level Change"), "Other")
  expect_equal(.recode_population("Concurrent Enrollment"), "Other")
})

test_that(".recode_population returns Unknown for NA and empty string", {
  expect_equal(.recode_population(NA_character_), "Unknown")
  expect_equal(.recode_population(""),            "Unknown")
})

test_that(".recode_population returns Other for unrecognized strings", {
  expect_equal(.recode_population("Something Unrecognized"), "Other")
})

test_that(".recode_population handles a mixed vector correctly", {
  inputs   <- c("First Time Freshman", "Transfer Student", "Continuing Student",
                "Readmit Student", NA, "")
  expected <- c("First-Time Freshman", "Transfer", "Continuing", "Readmit", "Unknown", "Unknown")
  expect_equal(.recode_population(inputs), expected)
})


# =============================================================================
# make_population_trend() tests
# =============================================================================

test_that("make_population_trend returns a ggplot object", {
  result <- make_population_trend(test_programs, dept_code = "HIST")
  expect_s3_class(result, "gg")
})

test_that("make_population_trend errors when student_population column is missing", {
  programs_no_pop <- test_programs %>% select(-student_population)
  expect_error(make_population_trend(programs_no_pop, dept_code = "HIST"),
               regexp = "student_population")
})

test_that("make_population_trend returns empty plot for unknown dept_code", {
  expect_warning(
    result <- make_population_trend(test_programs, dept_code = "NONEXISTENT"),
    regexp = "No rows found"
  )
  expect_s3_class(result, "gg")
})

test_that("make_population_trend plot data contains both Pre-Major and Declared Major facets", {
  result        <- make_population_trend(test_programs, dept_code = "HIST")
  major_statuses <- as.character(unique(result$data$major_status))

  expect_true("Pre-Major"      %in% major_statuses)
  expect_true("Declared Major" %in% major_statuses)
})

test_that("make_population_trend pct values sum to 1.0 per term × facet", {
  result <- make_population_trend(test_programs, dept_code = "HIST")

  pct_sums <- result$data %>%
    group_by(term, major_status) %>%
    summarize(total_pct = sum(pct), .groups = "drop")

  expect_true(all(abs(pct_sums$total_pct - 1) < 0.001))
})

test_that("make_population_trend Pre-Major 202010 counts match fixture", {
  result     <- make_population_trend(test_programs, dept_code = "HIST")
  pre_202010 <- result$data %>%
    filter(as.character(major_status) == "Pre-Major", term == 202010)

  # 4 SP1 + 1 SU1 + 2 FA1 never-declared + 2 pre_major-pathway (STU-HIST-PREDECL-001/002)
  expect_equal(sum(pre_202010$n), 6)

  pops <- setNames(pre_202010$n, as.character(pre_202010$population))
  expect_equal(pops[["Continuing"]], 3)
  expect_equal(pops[["Transfer"]],   1)
  expect_equal(pops[["Readmit"]],    1)
  expect_equal(pops[["Other"]],      1)
})

test_that("make_population_trend Declared Major 202010 counts match fixture", {
  result     <- make_population_trend(test_programs, dept_code = "HIST")
  dec_202010 <- result$data %>%
    filter(as.character(major_status) == "Declared Major", term == 202010)

  # 14 SP1-declared + 3 switch-out declared in 202010 = 17 (Continuing=16, Readmit=1)
  expect_equal(sum(dec_202010$n), 17)

  pops <- setNames(dec_202010$n, as.character(dec_202010$population))
  expect_equal(pops[["Continuing"]], 16)
  expect_equal(pops[["Readmit"]],     1)
})

test_that("make_population_trend excludes concentration and minor rows", {
  result <- make_population_trend(test_programs, dept_code = "HIST")

  total_declared <- result$data %>%
    filter(as.character(major_status) == "Declared Major") %>%
    pull(n) %>%
    sum()

  # 17+4+4+9 = 34 declared HIST rows across all terms
  expect_equal(total_declared, 34)
})

test_that("make_population_trend NULL program_type includes all program types", {
  result_all   <- make_population_trend(test_programs, dept_code = "HIST", program_type = NULL)
  result_major <- make_population_trend(test_programs, dept_code = "HIST", program_type = "Major")

  # NULL should include at least as many students as Major-only
  expect_gte(sum(result_all$data$n), sum(result_major$data$n))
})
