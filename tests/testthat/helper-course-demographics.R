# What the tests in test-course-demographics.R share: builders, option lists, constants.

.class_opt <- list(group_cols = c("campus", "college", "term", "term_type",
                                  "student_classification", "subject_course"))

.major_opt <- list(group_cols = c("campus", "college", "term", "term_type",
                                  "major_code", "subject_course"))

.mix_opt <- list(course = "HIST 1110", term = 202010L, min_n = 1L, top_n = 50L)
