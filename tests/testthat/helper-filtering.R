# What the tests in test-filtering.R share: builders, option lists, constants.

# uel = FALSE throughout the filtering tests, so the exclude list (loaded by
# load_funcs) doesn't mask section and student records; the uel behaviour is
# tested separately.
filtering_opt <- function(...) create_test_opt(c(list(uel = FALSE), list(...)))
