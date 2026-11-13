# What the tests in test-pathways-helpers.R share: builders, option lists, constants.

grouped_path_opt <- function(...) {
  modifyList(list(data_edges = list(first_enrolled = 202010L,
    last_enrolled_complete = 202110L), min_n = 1L, min_band_n = 1L), list(...))
}
