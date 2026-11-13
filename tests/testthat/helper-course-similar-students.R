# What the tests in test-course-similar-students.R share: their option list.

ss_opt <- function(...) c(list(classification = "Freshman", min_n = 1L, min_cell_n = 1L, data_edges = rp01_edges),
                          list(...))
