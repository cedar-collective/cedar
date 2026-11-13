# What the tests in test-pathways-helpers.R share: builders, option lists, constants.

# The population below is intermediate membership scaffolding, not authored raw
# enrollment data. MC02 supplies all course rows, including concurrent labs,
# repeat attempts and a student moving between delivery campuses.
grouped_path_population <- function() {
  test_students_mc %>% distinct(student_id) %>%
    mutate(population_label = "All", relevant_until = NA_integer_)
}

grouped_path_opt <- function(...) {
  modifyList(list(data_edges = list(first_enrolled = 202010L,
    last_enrolled_complete = 202110L), min_n = 1L, min_band_n = 1L), list(...))
}

cov_pop <- function() {
  tibble::tibble(
    student_id = paste0("S", 1:6),
    # S1 starts at the data edge -> truncated. S2 ends at the edge -> censored.
    # S3 is both. S4/S5/S6 sit inside the window -> complete.
    first_unm_term   = c(202010L, 202080L, 202010L, 202080L, 202110L, 202080L),
    last_record_term = c(202310L, 202480L, 202480L, 202310L, 202310L, 202380L)
  )
}

graded_students <- function() {
  mk <- function(term, n, graded) tibble::tibble(
    term = rep(as.integer(term), n),
    final_grade = c(rep("A", graded), rep(NA_character_, n - graded))
  )
  dplyr::bind_rows(
    mk(202480, 100, 91),   # complete
    mk(202580, 100, 91),   # complete
    mk(202610, 100, 7),    # grades not posted yet
    mk(202680, 100, 0)     # in progress
  )
}
