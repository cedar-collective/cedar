# What the tests in test-pathways-integration.R share: builders, option lists, constants.

# The populations the pipeline tests run on, built by build_population() from
# the shared fixtures, and each one's class list inside its Pathways window.
hist_pop <- function() {
  build_population(
    test_programs, test_degrees,
    opt = list(type = "preset", program_names = "History")
  )
}

math_pop <- function() {
  build_population(
    test_programs,
    opt = list(type = "preset", program_names = "Mathematics")
  )
}

anth_pop <- function() {
  build_population(
    test_programs,
    opt = list(type = "dept", dept_code = "ANTH")
  )
}

hist_students <- function() apply_pathways_population_window(test_students, hist_pop())

math_students <- function() apply_pathways_population_window(test_students, math_pop())
