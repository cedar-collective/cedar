# Comprehensive Headcount Tests
# Tests headcount.R filter combinations: major, minor, concentration, dept, campus, college
# Uses test_programs (from fixtures/designed_test_data.R).
#
# Reference values (from designed_test_data.R fixtures, term 202010):
#   HIST dept student_count: 25
#   MATH dept student_count: 2
#   ANTH dept student_count: 5
#   History major students (all terms): 46 distinct
#   Psychology minor rows (all terms): 10  (First Minor only)
#   Archaeology concentration rows (all terms): 4  (First Concentration only)
#
# Student IDs used in specific-value assertions (from designed_test_data.R):
#   PSYCH_MINOR_STUDENT: STU-PSYCH-MINOR — has Psychology First Minor
#   ARCH_CONC_STUDENT:   STU-ARCH-CONC   — has Archaeology First Concentration

PSYCH_MINOR_STUDENT <- "STU-PSYCH-MINOR"
ARCH_CONC_STUDENT   <- "STU-ARCH-CONC"

context("Headcount Comprehensive Filter Tests")


# =============================================================================
# Schema / column presence
# =============================================================================

test_that("test_programs has required headcount columns", {
  expect_true("student_college" %in% names(test_programs))
  expect_true("student_campus"  %in% names(test_programs))
  expect_true("dept_code"       %in% names(test_programs))
  expect_true("program_type"    %in% names(test_programs))
  expect_true("program_name"    %in% names(test_programs))
})

test_that("test_programs contains expected program types", {
  # designed_test_data.R provides Major, First Minor, First Concentration
  # (Second Minor/Major/Concentration not included in current fixture)
  types <- unique(test_programs$program_type)
  expect_true("Major"               %in% types)
  expect_true("First Minor"         %in% types)
  expect_true("First Concentration" %in% types)
})


# =============================================================================
# filter_programs_by_opt() — minor and concentration filtering
# =============================================================================

test_that("filter_programs_by_opt sets has_program_filter TRUE for minor", {
  result <- filter_programs_by_opt(test_programs, opt = list(minor = "Psychology"))
  expect_true(result$has_program_filter)
})

test_that("filter_programs_by_opt Psychology minor returns 205 minor rows", {
  result     <- filter_programs_by_opt(test_programs, opt = list(minor = "Psychology"))
  minor_rows <- result$data %>%
    filter(program_type %in% c("First Minor", "Second Minor"),
           program_name == "Psychology")

  expect_equal(nrow(minor_rows), 10)
})

test_that("filter_programs_by_opt Psychology minor includes PSYCH_MINOR_STUDENT", {
  result <- filter_programs_by_opt(test_programs, opt = list(minor = "Psychology"))
  expect_true(PSYCH_MINOR_STUDENT %in% result$data$student_id)
})

test_that("filter_programs_by_opt sets has_program_filter TRUE for concentration", {
  result <- filter_programs_by_opt(test_programs, opt = list(concentration = "Archaeology"))
  expect_true(result$has_program_filter)
})

test_that("filter_programs_by_opt Archaeology concentration returns 85 rows", {
  result    <- filter_programs_by_opt(test_programs, opt = list(concentration = "Archaeology"))
  conc_rows <- result$data %>%
    filter(program_type %in% c("First Concentration", "Second Concentration"),
           program_name == "Archaeology")

  expect_equal(nrow(conc_rows), 4)
})

test_that("filter_programs_by_opt Archaeology concentration includes ARCH_CONC_STUDENT", {
  result <- filter_programs_by_opt(test_programs, opt = list(concentration = "Archaeology"))
  expect_true(ARCH_CONC_STUDENT %in% result$data$student_id)
})

test_that("filter_programs_by_opt returns empty for nonexistent program name", {
  result     <- filter_programs_by_opt(test_programs, opt = list(concentration = "NonExistent XYZ"))
  conc_check <- result$data %>%
    filter(program_type == "First Concentration", program_name == "NonExistent XYZ")

  expect_equal(nrow(conc_check), 0)
})


# =============================================================================
# get_headcount() — major, minor, concentration, dept filters
# =============================================================================

test_that("get_headcount History major finds 46 distinct students", {
  result <- get_headcount(test_programs, opt = list(major = "History"),
                          group_by = c("student_id"))

  expect_equal(n_distinct(result$data$student_id), 46)
})

test_that("get_headcount History major does not include PSYCH_MINOR_STUDENT", {
  # This student has Psychology minor but not History major
  result <- get_headcount(test_programs, opt = list(major = "History"),
                          group_by = c("student_id"))

  expect_false(PSYCH_MINOR_STUDENT %in% result$data$student_id)
})

test_that("get_headcount Psychology minor includes PSYCH_MINOR_STUDENT", {
  result <- get_headcount(test_programs, opt = list(minor = "Psychology"),
                          group_by = c("student_id"))

  expect_true(PSYCH_MINOR_STUDENT %in% result$data$student_id)
})

test_that("get_headcount Archaeology concentration includes ARCH_CONC_STUDENT", {
  result <- get_headcount(test_programs, opt = list(concentration = "Archaeology"),
                          group_by = c("student_id"))

  expect_true(ARCH_CONC_STUDENT %in% result$data$student_id)
})


# =============================================================================
# get_headcount() — department counts by term
# =============================================================================

test_that("get_headcount HIST dept student_count is 25 in 202010", {
  result    <- get_headcount(test_programs %>% filter(term == 202010),
                             opt = list(), group_by = c("dept_code"))
  # summarize_headcount() adds `degree` to the grouping when that column is present,
  # so a department can span multiple rows (HIST = BA + MA). Sum across them for the
  # department total.
  hist_count <- result$data %>%
    filter(dept_code == "HIST") %>%
    summarize(n = sum(student_count)) %>%
    pull(n)

  expect_equal(hist_count, 25)
})

test_that("get_headcount MATH dept student_count is 2 in 202010", {
  result   <- get_headcount(test_programs %>% filter(term == 202010),
                            opt = list(), group_by = c("dept_code"))
  math_row <- result$data %>% filter(dept_code == "MATH")

  expect_equal(math_row$student_count, 2)
})

test_that("get_headcount ANTH dept student_count is 5 in 202010", {
  result   <- get_headcount(test_programs %>% filter(term == 202010),
                            opt = list(), group_by = c("dept_code"))
  anth_row <- result$data %>% filter(dept_code == "ANTH")

  expect_equal(anth_row$student_count, 5)
})


# =============================================================================
# get_headcount() — program_type grouping
# =============================================================================

test_that("get_headcount grouped by program_type includes all six types", {
  result <- get_headcount(test_programs %>% filter(term == 202010),
                          opt = list(), group_by = c("program_type"))

  types <- result$data$program_type
  expect_true("Major"               %in% types)
  expect_true("First Minor"         %in% types)
  expect_true("First Concentration" %in% types)
})


# =============================================================================
# get_headcount() — URL/input normalization and default scope
# =============================================================================

headcount_fixture_lookups <- function() {
  dept_codes <- sort(unique(test_programs$dept_code[!is.na(test_programs$dept_code)]))

  list(
    program_name_lookup = test_programs %>%
      filter(!is.na(program_name), program_name != "",
             !is.na(dept_code), dept_code != "") %>%
      distinct(program_name, dept_code),
    dept_name_lookup = tibble::tibble(
      dept_code = dept_codes,
      dept_name = paste(dept_codes, "Department")
    ),
    college_code_to_name = c(
      AS = "ARTS",
      SC = "STEM",
      SO = "SOSC",
      ED = "EDU",
      NR = "NURS",
      AD = "BUS"
    )
  )
}

test_that("normalize_headcount_opt accepts college code aliases", {
  opt <- normalize_headcount_opt(
    test_programs,
    opt = list(college = "AS"),
    lookups = headcount_fixture_lookups()
  )

  expect_equal(opt$college, "ARTS")
})

test_that("college-level default scope rolls up to departments", {
  result <- get_headcount(
    test_programs,
    opt = list(college = "AS"),
    lookups = headcount_fixture_lookups()
  )

  expect_true(result$rolled_up_by_dept)
  expect_false(result$no_program_filter)
  expect_true(all(c("dept_code", "dept_name") %in% names(result$data)))
  expect_true("HIST" %in% result$data$dept_code)
})

test_that("college-level charts use aggregate plot data, not department subplots", {
  result <- get_headcount(
    test_programs,
    opt = list(college = "AS"),
    lookups = headcount_fixture_lookups()
  )

  expect_true(result$rolled_up_by_dept)
  expect_true(result$plot_as_aggregate)
  expect_true(all(c("term", "student_level", "program_type", "student_count") %in% names(result$plot_data)))
  expect_false(any(c("dept_code", "dept_name", "program_name") %in% names(result$plot_data)))

  plots <- make_headcount_plots_by_level(result)
  expect_true(inherits(plots$undergrad, "plotly"))
  expect_false(any(grepl("^xaxis[0-9]+$", names(plots$undergrad$x$layout))))
  expect_lte(
    length(plots$undergrad$x$data),
    length(unique(stats::na.omit(result$plot_data$program_type)))
  )
})

test_that("department-level default scope breaks out programs", {
  result <- get_headcount(
    test_programs,
    opt = list(dept = "HIST"),
    lookups = headcount_fixture_lookups()
  )

  expect_false(result$rolled_up_by_dept)
  expect_false(result$no_program_filter)
  expect_true("program_name" %in% names(result$data))
  expect_true(all(result$data$program_name == "History"))
})

test_that("department scope fails loudly without program lookup", {
  expect_error(
    get_headcount(test_programs, opt = list(dept = "HIST"), lookups = list()),
    "Missing required cedar_lookups\\$program_name_lookup"
  )
})

test_that("broad program selections roll up with dept_code fallback", {
  programs <- test_programs %>%
    bind_rows(tibble::tibble(
      student_id = paste0("STU-FALLBACK-", seq_len(13)),
      term = 202010L,
      student_college = "ARTS",
      student_campus = "ABQ",
      student_level = "Undergraduate",
      degree = "Bachelor of Arts",
      dept_code = paste0("D", seq_len(13)),
      program_type = "First Concentration",
      program_name = paste0("Unmapped Concentration ", seq_len(13))
    ))

  result <- get_headcount(
    programs,
    opt = list(concentration = paste0("Unmapped Concentration ", seq_len(13))),
    lookups = headcount_fixture_lookups()
  )

  expect_true(result$rolled_up_by_dept)
  expect_false("UNK" %in% result$data$dept_code)
  expect_true(all(paste0("D", seq_len(13)) %in% result$data$dept_code))
})
